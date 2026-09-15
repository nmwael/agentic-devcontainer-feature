#!/bin/sh
set -e

echo "Activating feature 'bifrost-gateway'"

# The 'install.sh' entrypoint script is always executed as the root user.
# Option values are passed in as environment variables named after the option id,
# converted to UPPERCASE (e.g. 'port' -> $PORT, 'version' -> $VERSION).
echo "The effective dev container remoteUser is '$_REMOTE_USER'"
echo "The effective dev container containerUser is '$_CONTAINER_USER'"

PORT="${PORT:-8082}"
VERSION="${VERSION:-latest}"
LLAMA_PORT="${LLAMA_PORT:-8089}"

# Install @maximhq/bifrost
BIFROST_DIR="/usr/local/share/llm-lab/bifrost"
mkdir -p "$BIFROST_DIR"

# Bifrost is a node app; base images (e.g. nvidia/cuda) often lack node/npm.
# Provision a runtime here so the feature is self-sufficient.
# jq is installed in the same pass to materialize bifrost.json from its JSON template.
if ! command -v npm >/dev/null 2>&1 || ! command -v node >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
    echo "node/npm/jq not found — provisioning nodejs + npm + jq via apt..."
    if apt-get update -qq && apt-get install -y --no-install-recommends nodejs npm jq >/dev/null 2>&1; then
        echo "node $(node --version 2>/dev/null || echo ?) ready"
    else
        echo "WARNING: nodejs/npm/jq install failed — bifrost config keeps defaults and the gateway will not be functional"
        exit 0
    fi
fi

echo "Installing @maximhq/bifrost@$VERSION into $BIFROST_DIR ..."
npm install --prefix "$BIFROST_DIR" "@maximhq/bifrost@$VERSION" 2>/dev/null || {
    echo "WARNING: npm install failed for @maximhq/bifrost@$VERSION"
    echo "Bifrost gateway will not be fully functional."
    exit 0
}

# Install the static launcher script start-bifrost from the feature root
SCRIPT_SRC="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
cp -f "$SCRIPT_SRC/start-bifrost.sh" "/usr/local/bin/start-bifrost"
chmod 0755 "/usr/local/bin/start-bifrost"

# Scaffold config/bifrost.json into the feature dir (workspace-agnostic).
# The gateway runs with defaults if absent; copy it into your project as
# config/bifrost.json to customize upstream routing / slot_routing.
CONFIG_DIR="/usr/local/share/llm-lab/bifrost/config"
mkdir -p "$CONFIG_DIR"

if command -v jq >/dev/null 2>&1; then
    jq --arg p "$LLAMA_PORT" '.upstream = ("http://127.0.0.1:" + $p + "/v1")' \
        "$SCRIPT_SRC/templates/bifrost.json" >"$CONFIG_DIR/bifrost.json"
else
    cp -f "$SCRIPT_SRC/templates/bifrost.json" "$CONFIG_DIR/bifrost.json"
    echo "WARNING: jq unavailable — bifrost.json keeps default upstream port 8089"
fi

echo "Bifrost config scaffolded to $CONFIG_DIR/bifrost.json (copy to your project's config/bifrost.json to customize)"

# Stamp version
echo "$VERSION" >"$BIFROST_DIR/version"

echo "Done! Bifrost gateway installed."
echo "Run 'start-bifrost' to launch the gateway."
echo "Config at: $CONFIG_DIR/bifrost.json"
