#!/usr/bin/env bats
# Container-side assertions for the models feature. Install time must NEVER
# download model weights (9-16 GB) - it only scaffolds the on-demand fetch
# script. A quick default sanity check builds on that.

@test "fetch-models.sh scaffolded into the feature dir" {
    [ -f /usr/local/share/llm-lab/models/fetch-models.sh ]
    [ -x /usr/local/share/llm-lab/models/fetch-models.sh ]
}

@test "fetch-models.sh is sh-clean" {
    dash -n /usr/local/share/llm-lab/models/fetch-models.sh
}

@test "default model name/quant embedded in the fetch script" {
    grep -q "gemma-4-26B-A4B-it-UD-IQ2_M" /usr/local/share/llm-lab/models/fetch-models.sh
    grep -q 'QUANT=' /usr/local/share/llm-lab/models/fetch-models.sh
}

@test "MODELS_DIR exported to /etc/environment" {
    grep -q "MODELS_DIR" /etc/environment
}

@test "no model weights were downloaded at install time" {
    [ ! -d /workspaces/ci/models ] || [ -z "$(ls -A /workspaces/ci/models 2>/dev/null)" ]
}

@test "second install is a no-op (idempotent)" {
    run /bin/sh /tmp/feature/install.sh
    [ "$status" -eq 0 ]
    [ -x /usr/local/share/llm-lab/models/fetch-models.sh ]
}