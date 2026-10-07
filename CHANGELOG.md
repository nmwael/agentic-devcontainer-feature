# Changelog

All notable changes to this project are documented in this file. The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed
- **`opencode-agents` 1.2.3 — `limit.output` equalled `limit.context`, which drove opencode into an infinite compact loop.** opencode compacts the conversation when `tokens (input + output + cache read + cache write) >= limit.context - min(20000, maxOutputTokens)`. The generator emitted `output: ($m.output // $m.context)`, so that threshold was `context - context = 0` and **every** assistant turn was followed by a `compaction` turn — forever. Seen in capability-testing profile `q`: the 8b orchestrator session compacted 7× in 3.5 minutes, a coder session 18× in 5 minutes (`agent=compaction` alternating with the agent turn, ending in `compaction in=0 out=0`), and generations ballooned to 4-5k tokens because the provider was told it could emit up to `limit.output`. `generate-opencode.jq` and the shipped `opencode.json.fragment` (which had `output: 65536`) now default `output` to **8192**: threshold becomes `context - 8192` (32768 for a 40960 model) and the per-turn output cap is sane. An explicit per-model `output` in a profile still wins (`$m.output`), and flows through `stack.json` untouched because `llm_write_stack` copies the profile array verbatim.

### Fixed
- **`bifrost-gateway` 1.1.3 — the gateway's upstreams were unreachable: every chat request 404'd and model resolution failed.** Two root causes in `write-bifrost-config.sh`:
  - **Doubled `/v1` path.** `network_config.base_url` was `http://127.0.0.1:{port}/v1`, but bifrost appends `/v1/chat/completions` to `base_url` itself when `base_provider_type` is `openai`. The upstream request became `http://127.0.0.1:8089/v1/v1/chat/completions` and llama-server returned `404` (verified with an HTTP path logger: bifrost sent `POST /v1/v1/chat/completions`). `base_url` is now `http://127.0.0.1:{port}` — no `/v1`.
  - **Wildcard allowlist never matched.** `keys[].models` was `["{name}*"]`, but bifrost v2.2.6 matches allowlist entries **exactly** — a request for `qwen3-8b-s0` does not match the entry `qwen3-8b*` — so resolution failed with `could not auto resolve a provider for the request`. The only wildcard bifrost honours is the whole-string catch-all `["*"]`, and on multi-provider configs that misroutes (with two providers it sent `qwen3-8b` to the `qwen2.5-coder-7b` upstream). The generator now emits the exact ids clients request: `{name}` plus `{name}-s{slot}` for every slot below the model's `parallel` count (`parallel` defaulting to 1). The legacy single-upstream fallback keeps `["*"]` (single provider, catch-all is correct there).

### Fixed
- **`bifrost-gateway` 1.1.2 — the gateway never listened on `PORT`, and never loaded the generated config.** Two independent bugs, both of which made the gateway look "down" (process alive, nothing reachable) and both pre-existing:
  - **Wrong port.** The launcher ran `node bin.js "$PORT_ENV"`, but bifrost v2.2.x parses the port as a **`-port` flag**, not a positional argument. The positional value was silently discarded, so the server started on its own built-in default `127.0.0.1:8080` and `BIFROST_PORT`/`PORT` (default `8082`) was unreachable — `auto-startup.sh` waited on `:8082`, the health probe failed, and the gateway appeared down even though the process was running. `-host` also defaults to `localhost` only, so it was unreachable off-box too. The launcher now passes `-port "$PORT_ENV" -host "$HOST_ENV"` (default host `0.0.0.0`, overridable via `BIFROST_HOST`).
  - **Config never read.** `write-bifrost-config.sh` materializes `<BIFROST_DIR>/config/bifrost.json`, but bifrost reads `<app-dir>/config.json` (default app-dir `/root/.config/bifrost`). Bifrost therefore logged `config file not found ... initializing with default values` and started with **zero providers**, so every request failed with `could not auto resolve a provider` and `/v1/models` returned `{"data":[]}`. The launcher now syncs the generated config into bifrost's app-dir on start (overridable via `BIFROST_APP_DIR`), which keeps routing correct even when the config is refreshed after the build stage (runtime `resolve-stack.sh`).

  Three new regression tests guard these: a static assertion that the flag form is used and the positional form is absent, a static assertion that the app-dir sync is present, and an end-to-end check that `BIFROST_PORT` actually binds.

### Fixed
- **`models` 1.4.0 — profile files and `models_dir` are resolved at RUNTIME, not build time.** A feature installs during the build stage, but the repo is bind-mounted at container start, so `install.sh` could never read `.devcontainer/llm-lab-models.json`. Compounding it, the `$PWD/models` default baked the CLI's temp feature-extraction path into `stack.json` and `/etc/environment` (e.g. `/tmp/dev-container-features/models_3/models`), leaving a working box unable to find any weights:
  - **New `resolve-stack.sh`** — wired via the feature's `postCreateCommand` (the CLI runs lifecycle hooks with cwd = the workspace folder). Reads `.devcontainer/llm-lab-{models,roles}.json`, applies the same integrity validation as the build, and rewrites `stack.json`, the `models.json` mirror, and the bifrost routing config.
  - **`MODELS_DIR`** — no longer defaults to `$PWD/models`. Empty at build time; the resolver sets it to `<workspace>/models` unless explicitly configured. `/etc/environment` is only written when `MODELS_DIR` is set, so no stale/empty export can shadow the runtime value.
  - **New `stack-lib.sh`** — shared validators/writers sourced by both `install.sh` and `resolve-stack.sh`, so the two paths cannot drift.
  - **Explicit options win.** `install.sh` records whether `MODELS`/`ROLES` arrived as feature options (`/usr/local/share/llm-lab/.build-state`); when they did, the resolver leaves the stack untouched instead of clobbering it with a workspace profile file.
  - Switching profiles now needs only a container restart, not a rebuild. The resolver is idempotent and rejects malformed JSON, unknown role models, and slots beyond a model's `parallel` count without corrupting a working stack.
  - **Tests** — `test/models/runtime-resolution.sh` (14 assertions, runs inside `devcontainer features test`) covers the build/runtime split, precedence, cloud-mode preservation, idempotency, and the integrity rejections. The old `test.sh` assertion that `MODELS_DIR` was always exported to `/etc/environment` now asserts the opposite (no stale build-time export).

### Added
- **Cloud mode for the whole agentic stack** — `CLOUD_MODE=true` makes every opencode agent ride the hosted `opencode` provider on GPU-less/cloud boxes:
  - **`models` 1.2.0** — new `CLOUD_MODE` (boolean) + `CLOUD_MODEL` (default `big-pickle`) options. With `CLOUD_MODE=true` and no explicit `MODELS`, writes a cloud-only `stack.json` (`cloud: true`, `cloud_provider: "opencode"`, empty `models[]`, every role carrying a hosted model id). Explicit `MODELS`/`ROLES` (or `.devcontainer/llm-lab-{models,roles}.json`) always win and force the local slot-pinned stack. Local mode adds `cloud: false` to the manifest.
  - **`opencode-agents` 1.2.0** — `generate-opencode.jq` cloud branch: every `agent.<role>.model = opencode/<model>`, `model`/`small_model` from the `build` role, `enabled_providers = ["opencode"]`, no local bifrost providers, no `limit` (hosted defaults). Local generation is byte-identical to 1.1.3.
  - **`scripts/auto-startup.sh`** — honors `stack.json.cloud=true`: skips llama-server AND bifrost; opencode serve + Tailscale still start (`SKIP_LLAMA_START` unchanged).
  - **`llm-lab` template 1.2.0** — `CLOUD_MODE`/`CLOUD_MODEL` passthrough options; repo `.devcontainer` passes `CLOUD_MODE`/`CLOUD_MODEL` via `containerEnv`.
  - **Tests** — models `cloud-mode` + `cloud-mode-explicit-models-wins` scenarios, template `default-cloud` asserts every agent pin starts with `opencode/`, integration bats covers the cloud generator output.
- **devcontainer CLI test tier** — `devcontainer features test` mirrors the repo layout (`test/<feature>/test.sh`, `duplicate.sh`, `scenarios.json` + per-scenario scripts, `_global` full-stack scenario) and is run in CI via a matrix job (llama-server, gpu-bridge, bifrost-gateway, models, opencode-agents, full-stack)
- **Static guardrails** for the mirrored test suite: `run-static.sh` validates the test mirror contract (every feature has `test.sh`, every scenario key has a matching `.sh`) and shellcheck covers all `test/**.sh` scripts; `metadata.bats` enforces the contract.
- **Template smoke in release** — after publishing `llm-lab`, CI applies the published template to a throwaway workspace and builds the generated dev container to validate option rendering and feature resolution.

### Added
- **Feature collection** (5 features, v0.x → 1.0.0 target):
  - `llama-server` — prebuilt llama.cpp server, OpenAI-compatible `/v1` API, CUDA support, idempotent install
  - `gpu-bridge` — WSL2 GPU driver symlink bridge with `/dev/dxg` verification on start
  - `bifrost-gateway` — pinned `@maximhq/bifrost` install + config scaffold exposing llama-servers as OpenAI-compatible providers
  - `models` — on-demand GGUF fetch from HuggingFace (idempotent, resumable, never baked into images)
  - `opencode-agents` — full multi-agent setup (AGENTS.md, `.opencode/agent/*`, library books, HITL contract) with `WITH_LIBRARY` opt-out
- **Full multi-upstream (Option C) — v1.1.0**: consumers declare N models; the whole stack serves them simultaneously via a shared `stack.json` manifest:
  - **`models` 1.1.0** — new `MODELS`/`ROLES`/`BIFROST_PORT` options (legacy `MODEL`/`QUANT` deprecated); owns and writes `stack.json` (`schema:1`, `models`, `roles`, `models_dir`, `bifrost_port`, `opencode_port`, `subagent_depth`) with integrity validation (role→model exists, slot < parallel); `fetch-models.sh` iterates the model list
  - **`bifrost-gateway` 1.1.0** — `write-bifrost-config.sh` materializes a v2 multi-provider config (one provider per llama-server upstream, `keys[].models` route `"{name}*"`), re-runnable after a stack change; installs into the feature dir
  - **`opencode-agents` 1.1.0** — `generate-opencode.sh` + `generate-opencode.jq` materialize `opencode.json` from `stack.json` (per-slot provider models, role pins, `model`/`small_model` = build role, `server.port`, `limit.context`); `scaffold.sh` generates from stack.json when present, falls back to the shipped fragment; provisions `jq`
  - **`scripts/auto-startup.sh`** — starts one `llama-server` per model in `stack.json` (per-model port + `--ctx-size`), ports for bifrost/opencode read from the manifest (env-var + defaults preserved)
  - **`llm-lab` template 1.1.0** — `MODELS`/`ROLES` passthrough options forwarded to the `models` feature
- **`llm-lab` template** — generates `.devcontainer/devcontainer.json` with `GPU_MODE`, `MODEL`, `FEATURES_TAG`, `INCLUDE_AGENTS`/`INCLUDE_MODELS`/`INCLUDE_LIBRARY` options
- **Self-consuming devcontainer** (`.devcontainer/`) — this repo bootstraps its own full stack
- **Extraction pipeline** — the upstream lab repo regenerates this tree reproducibly
- **Website** — `docs/index.html`, served via GitHub Pages: features, multi-agent setup, HITL workflow, Tailscale remote access
- **Docs** — README, CONTRIBUTING, LICENSE (MIT), SECURITY, CHANGELOG

### Changed
- **`opencode-agents` 1.1.2** — shipped `AGENTS.md` conventions repointed from the (nonexistent) `serve.sh` to `scripts/auto-startup.sh` and the shared `stack.json` manifest (`--alias` ↔ model-id sync, `limit.context` from the store `context` field, `fetch-models.sh` path); generator display-name and fragment slot contexts converged; mirrors the repo-root file
- **`llm-lab` template 1.1.0** — ships `apt-get-packages` feature (`gh,jq,shfmt`) in its generated `devcontainer.json`
- **Config templates now JSON-only, substituted via `jq`** — `models.json` added to `src/models/templates/` and `__LLAMA_PORT__` placeholder removed from `bifrost.json` (valid standalone JSON); placeholder-bearing scripts became static scripts at the feature roots (`fetch-models.sh`, `start-bifrost.sh`, `ensure-bridge.sh`) reading env/config at runtime; installers provision `jq` if missing (graceful degrade to template defaults); `jq` added to the devcontainer `apt-get-packages` feature (`gh,jq`)
- **Template extraction** — shell scripts generated via inline heredocs (`fetch-models.sh`, `start-bifrost`, `ensure-bridge.sh`) extracted into dedicated `src/<feature>/templates/` files with `__PLACEHOLDER__` + `sed` substitution for the `models`/`bifrost-gateway`/`gpu-bridge` features, matching the `bifrost.json` convention; fixed a `2>/dev/null` for-loop glob bug in `opencode-agents` install.sh
- llama-server CUDA arches include Blackwell (`120`) alongside Ampere/Ada/Hopper (`80;86;89;90;120`)

### Fixed
- **All-feature divergence sweep** — full audit of code vs docs caught and fixed:
  - `bifrost-gateway` **1.1.1** — the `PORT` option is now authoritative (baked into the deployed launcher default); `write-bifrost-config.sh` upstream `base_url` now includes the `/v1` path (llama-server's OpenAI endpoint) in both the manifest and legacy fallback branches
  - `opencode-agents` **1.1.2** — `generate-opencode.jq` provider display name no longer emits a double `local`; shipped `opencode.json.fragment` slot contexts unified to the uniform per-model `context` (mirrors the generator; dropped the historical 49152/32768 per-slot curation)
  - `models` **1.1.1** — `fetch-models.sh` idempotency comment aligned with behavior (existence check, not checksum)
  - `scripts/auto-startup.sh` — `.gguf` discovery mirrors `fetch-models.sh` naming (`/` → `_` in HF slugs), so slash-containing repos launch correctly
  - `llm-lab` template **1.1.1** — previously inert `FEATURES_TAG`/`MODEL`/`INCLUDE_LIBRARY` options are now wired into the generated `devcontainer.json`
  - Self-consuming devcontainer pins fixed (malformed `:1.0.x` feature keys) and `devcontainer-lock.json` refreshed to the published 1.1.x digests
- **`scripts/auto-startup.sh`** — now passes `--alias <name>` and `--parallel <slots>` to every `llama-server` (per-model from `stack.json`, legacy fallback `gemma4-26b-a4b`/`SLOTS`) so `/v1/models` advertises the model family and slot count matches the declared `parallel` — closes the model-id/alias 404 gap (regression guard added to the static suite)
- Template `devcontainer.json` now always includes the `llama-server` feature at `"1"` regardless of other options

## [0.1.0] - 2026-09-13

### Added
- First extract of the feature collection from the upstream lab repo
- Milestones M0–M5 of the portability plan: hello-feature spike (published), llama-server installed from the existing lab image, features verified, dogfooding, README quick-start paths

[0.1.0]: https://github.com/nmwael/agentic-devcontainer-feature/releases/tag/v0.1.0