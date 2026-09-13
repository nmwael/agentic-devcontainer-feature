#!/usr/bin/env bats
# Container-side assertions for the bifrost-gateway feature. The nvidia/cuda
# base images lack node/npm, so the feature must self-provision them, install
# @maximhq/bifrost, and write a launcher that points at the package's REAL
# entrypoint (bin.js - the old dist/index.js path never existed).

@test "node and npm are provisioned by the feature" {
    command -v node
    command -v npm
}

@test "@maximhq/bifrost installed into the feature dir" {
    [ -f /usr/local/share/llm-lab/bifrost/node_modules/@maximhq/bifrost/bin.js ]
}

@test "start-bifrost launcher installed and executable" {
    [ -x /usr/local/bin/start-bifrost ]
}

@test "launcher references the packaged entrypoint (bin.js), not dist/" {
    grep -q "node_modules/@maximhq/bifrost/bin.js" /usr/local/bin/start-bifrost
    if grep -q "dist/index.js" /usr/local/bin/start-bifrost; then
        echo "launcher still points at the nonexistent dist/index.js"
        return 1
    fi
}

@test "scaffolded config dir exists (workspace-agnostic)" {
    [ -d /usr/local/share/llm-lab/bifrost/config ]
}

@test "launcher is sh-clean" {
    dash -n /usr/local/bin/start-bifrost
}

@test "second install stays functional (idempotent)" {
    run /bin/sh /tmp/feature/install.sh
    [ "$status" -eq 0 ]
    [ -x /usr/local/bin/start-bifrost ]
}