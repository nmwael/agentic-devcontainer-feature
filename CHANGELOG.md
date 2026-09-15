# Changelog

All notable changes to this project are documented in this file. The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **Feature collection** (5 features, v0.x → 1.0.0 target):
  - `llama-server` — prebuilt llama.cpp server, OpenAI-compatible `/v1` API, CUDA support, idempotent install
  - `gpu-bridge` — WSL2 GPU driver symlink bridge with `/dev/dxg` verification on start
  - `bifrost-gateway` — pinned `@maximhq/bifrost` install + config scaffold exposing llama-servers as OpenAI-compatible providers
  - `models` — on-demand GGUF fetch from HuggingFace (idempotent, resumable, never baked into images)
  - `opencode-agents` — full multi-agent setup (AGENTS.md, `.opencode/agent/*`, library books, HITL contract) with `WITH_LIBRARY` opt-out
- **`llm-lab` template** — generates `.devcontainer/devcontainer.json` with `GPU_MODE`, `MODEL`, `FEATURES_TAG`, `INCLUDE_AGENTS`/`INCLUDE_MODELS`/`INCLUDE_LIBRARY` options
- **Self-consuming devcontainer** (`.devcontainer/`) — this repo bootstraps its own full stack
- **Extraction pipeline** — the upstream lab repo regenerates this tree reproducibly
- **Website** — `docs/index.html`, served via GitHub Pages: features, multi-agent setup, HITL workflow, Tailscale remote access
- **Docs** — README, CONTRIBUTING, LICENSE (MIT), SECURITY, CHANGELOG

### Changed
- **Config templates now JSON-only, substituted via `jq`** — `models.json` added to `src/models/templates/` and `__LLAMA_PORT__` placeholder removed from `bifrost.json` (valid standalone JSON); placeholder-bearing scripts became static scripts at the feature roots (`fetch-models.sh`, `start-bifrost.sh`, `ensure-bridge.sh`) reading env/config at runtime; installers provision `jq` if missing (graceful degrade to template defaults); `jq` added to the devcontainer `apt-get-packages` feature (`gh,jq`)
- **Template extraction** — shell scripts generated via inline heredocs (`fetch-models.sh`, `start-bifrost`, `ensure-bridge.sh`) extracted into dedicated `src/<feature>/templates/` files with `__PLACEHOLDER__` + `sed` substitution for the `models`/`bifrost-gateway`/`gpu-bridge` features, matching the `bifrost.json` convention; fixed a `2>/dev/null` for-loop glob bug in `opencode-agents` install.sh
- llama-server CUDA arches include Blackwell (`120`) alongside Ampere/Ada/Hopper (`80;86;89;90;120`)

### Fixed
- Template `devcontainer.json` now always includes the `llama-server` feature at `"1"` regardless of other options

## [0.1.0] - 2026-09-13

### Added
- First extract of the feature collection from the upstream lab repo
- Milestones M0–M5 of the portability plan: hello-feature spike (published), llama-server installed from the existing lab image, features verified, dogfooding, README quick-start paths

[0.1.0]: https://github.com/nmwael/agentic-devcontainer-feature/releases/tag/v0.1.0