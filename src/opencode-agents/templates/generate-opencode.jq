# generate-opencode.jq — convert the shared stack.json manifest (written by the
# models feature) into an opencode.json:
#   * cloud mode   (stack.json.cloud == true): every agent routes to the hosted
#     opencode provider ("opencode/<roles[].model>"); no local providers, no
#     per-slot ids, slots/latency/context come from the hosted model directly.
#   * local mode   (default): one provider per model backend (baseURL through the
#     bifrost gateway), per-slot model ids "{name}" + "-s0..-s{parallel-1}",
#     agent -> model-id pin map from stack.roles, and top-level model/small_model
#     = the "build" role's model id (keyed off the first role when "build" absent).
#
# Every agent entry also carries per-role sampling/budget defaults (temperature,
# steps). An explicit .temperature/.steps on the stack.roles entry overrides the
# per-role default.
def temp_default($role):
    { architect: 0.1, coder: 0.1, researcher: 0.1, reviewer: 0.1,
      build: 0.2, ui: 0.2, artist: 0.3 }[$role] // 0.1;
def steps_default($role):
    { architect: 30, coder: 25, researcher: 20, reviewer: 15,
      build: 40, ui: 20, artist: 15 }[$role] // 20;
(.cloud // false) as $is_cloud
| (.cloud_provider // "opencode") as $cprov
| .opencode_port as $op
| .subagent_depth as $sd
| .roles as $roles
| ((if ($roles | has("build")) then $roles.build else ($roles | to_entries[0].value) end)) as $primary
| if $is_cloud then
    ((reduce ($roles | to_entries[]) as $e ({};
          . + { ($e.key): {
                    model: ($cprov + "/" + $e.value.model),
                    temperature: ($e.value.temperature // temp_default($e.key)),
                    steps: ($e.value.steps // steps_default($e.key))
                } }))) as $agent_map
    | {
        "$schema": "https://opencode.ai/config.json",
        model: ($cprov + "/" + $primary.model),
        small_model: ($cprov + "/" + $primary.model),
        provider: { ($cprov): { options: { setCacheKey: false } } },
        agent: $agent_map,
        enabled_providers: [ $cprov ],
        subagent_depth: $sd,
        permission: "allow",
        server: { port: $op }
      }
  else
    .bifrost_port as $bp
    | .models as $models
    | (($models | map(.context) | max)) as $max_ctx
    | (($primary.model) as $pn | (first($models[] | select(.name == $pn))).provider) as $primary_provider
    | ($primary_provider + "/" + $primary.model + "-s" + ($primary.slot | tostring)) as $primary_id
    | ((
          reduce $models[] as $m ({};
              . + {
                  ($m.provider): {
                      npm: "@ai-sdk/openai-compatible",
                      name: ("Bifrost (local " + $m.name + ")"),
                      options: {
                          baseURL: ("http://127.0.0.1:" + ($bp | tostring) + "/v1"),
                          headers: { "x-bf-passthrough-extra-params": "true" }
                      },
                      models:
                          ({ ($m.name): { name: ($m.name + " (unpinned fallback)"), limit: { context: $m.context, output: ($m.output // 8192) } } }
                           + (reduce range(0; $m.parallel) as $i ({};
                                 . + { (($m.name) + "-s" + ($i | tostring)):
                                           { name: ($m.name + " - Slot " + ($i | tostring)), limit: { context: $m.context, output: ($m.output // 8192) } } })))
                  }
              }
          )
      ) + { opencode: { options: { setCacheKey: false } } }) as $providers
    | ((reduce $models[] as $m ([]; . + [$m.provider])) | unique | . + ["opencode"]) as $enabled
    | ((reduce ($roles | to_entries[]) as $e ({};
              . + { ($e.key): { model:
                        ((first($models[] | select(.name == $e.value.model))).provider
                         + "/" + $e.value.model + "-s" + ($e.value.slot | tostring)),
                    temperature: ($e.value.temperature // temp_default($e.key)),
                    steps: ($e.value.steps // steps_default($e.key)) } }))) as $agent_map
    | {
        "$schema": "https://opencode.ai/config.json",
        model: $primary_id,
        small_model: $primary_id,
        provider: $providers,
        agent: $agent_map,
        enabled_providers: $enabled,
        subagent_depth: $sd,
        permission: "allow",
        server: { port: $op },
        limit: { context: $max_ctx }
      }
  end