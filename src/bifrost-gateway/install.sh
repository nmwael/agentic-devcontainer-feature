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

echo "Installing @maximhq/bifrost@$VERSION into $BIFROST_DIR ..."
npm install --prefix "$BIFROST_DIR" "@maximhq/bifrost@$VERSION" 2>/dev/null || {
    echo "WARNING: npm install failed for @maximhq/bifrost@$VERSION"
    echo "Bifrost gateway will not be fully functional."
    exit 0
}

# Write launcher script start-bifrost
cat > "/usr/local/bin/start-bifrost" <<LAUNCHER_EOF
#!/bin/sh
# Bifrost gateway launcher honoring BIFROST_PORT / config
PORT_ENV="${BIFROST_PORT:-$PORT}"
export BIFROST_PORT="$PORT_ENV"
export LLAMA_PORT="${LLAMA_PORT:-8089}"
exec node "$BIFROST_DIR/dist/index.js" "\$PORT_ENV"
LAUNCHER_EOF
chmod 0755 "/usr/local/bin/start-bifrost"

# Scaffold config/bifrost.json into workspace from template (idempotent create-if-missing)
CONFIG_DIR="/workspaces/opencode-local-lab/config"
mkdir -p "$CONFIG_DIR"

cat > "$CONFIG_DIR/bifrost.json" <<CONFIG_EOF
{
    "upstream": "http://127.0.0.1:${LLAMA_PORT}/v1",
    "slot_routing": "gemma4-26b-a4b-sN",
    "setCacheKey": false,
    "x-bf-passthrough-extra-params": ""
}
CONFIG_EOF

echo "Bifrost config scaffolded to $CONFIG_DIR/bifrost.json"

# Stamp version
echo "$VERSION" > "$BIFROST_DIR/version"

echo "Done! Bifrost gateway installed."
echo "Run 'start-bifrost' to launch the gateway."
echo "Config at: $CONFIG_DIR/bifrost.json"