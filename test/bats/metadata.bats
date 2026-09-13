#!/usr/bin/env bats
# Runner-side metadata suite - validates the collection WITHOUT building
# containers. Each test iterates every published feature in src/.

load helpers

@test "every feature dir has devcontainer-feature.json + install.sh" {
    for feature in "${FEATURES[@]}"; do
        [ -f "$REPO_ROOT/src/$feature/devcontainer-feature.json" ] || {
            echo "missing src/$feature/devcontainer-feature.json"
            return 1
        }
        [ -f "$REPO_ROOT/src/$feature/install.sh" ] || {
            echo "missing src/$feature/install.sh"
            return 1
        }
    done
}

@test "feature id equals its directory name" {
    for feature in "${FEATURES[@]}"; do
        id="$(feature_json_field "$feature" id)"
        [ "$id" = "$feature" ] || {
            echo "src/$feature: id '$id' != dir name '$feature'"
            return 1
        }
    done
}

@test "feature versions are semver (GHCR republish depends on bumps)" {
    for feature in "${FEATURES[@]}"; do
        version="$(feature_json_field "$feature" version)"
        is_semver "$version" || {
            echo "src/$feature: version '$version' is not X.Y.Z"
            return 1
        }
    done
}

@test "install.sh shebang is #!/bin/sh" {
    for feature in "${FEATURES[@]}"; do
        install="$REPO_ROOT/src/$feature/install.sh"
        head -1 "$install" | grep -qx '#!/bin/sh' || {
            echo "src/$feature/install.sh: bad shebang"
            return 1
        }
    done
}

@test "install.sh passes dash -n (runs under /bin/sh, no bash-isms)" {
    for feature in "${FEATURES[@]}"; do
        dash -n "$REPO_ROOT/src/$feature/install.sh" || {
            echo "src/$feature/install.sh: dash syntax error"
            return 1
        }
    done
}

@test "install.sh is shellcheck-clean at warning severity" {
    for feature in "${FEATURES[@]}"; do
        shellcheck -x -S warning "$REPO_ROOT/src/$feature/install.sh" || {
            echo "src/$feature/install.sh: shellcheck findings"
            return 1
        }
    done
}

@test "option defaults are never arrays (bash-array footgun)" {
    for feature in "${FEATURES[@]}"; do
        python3 -c '
import json, sys
data = json.load(open(sys.argv[1]))
for name, spec in data.get("options", {}).items():
    assert not isinstance(spec.get("default"), list), f"option {name}"
' "$REPO_ROOT/src/$feature/devcontainer-feature.json" || {
            echo "src/$feature: option default is a JSON array"
            return 1
        }
    done
}

@test "llm-lab template metadata is valid" {
    python3 -c '
import json, re, sys
data = json.load(open(sys.argv[1]))
for key in ("id", "version", "name", "publisher", "description"):
    assert data.get(key), f"missing {key}"
assert re.match(r"^\d+\.\d+\.\d+$", data["version"]), "version not semver"
' "$REPO_ROOT/src/templates/llm-lab/devcontainer-template.json"
}

@test "llm-lab template ships a devcontainer definition + test harness" {
    tpl_root="$REPO_ROOT/src/templates/llm-lab"
    if [ -f "$tpl_root/devcontainer.json" ]; then
        devcontainer_json="$tpl_root/devcontainer.json"
    else
        devcontainer_json="$tpl_root/.devcontainer/devcontainer.json"
    fi
    [ -f "$devcontainer_json" ] || return 1
    python3 -c '
import json, sys
data = json.load(open(sys.argv[1]))
assert isinstance(data, dict) and "features" in data, "template devcontainer.json must carry a features map"
' "$devcontainer_json"
    [ -f "$tpl_root/test/test.sh" ] || return 1
}

@test "scripts/ and test harness shell scripts are shellcheck-clean" {
    shellcheck -x -S warning \
        "$REPO_ROOT"/scripts/*.sh \
        "$REPO_ROOT"/src/templates/llm-lab/test/test.sh
}