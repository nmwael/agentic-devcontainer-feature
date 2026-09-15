# Changelog

All notable changes to this project are documented in this file. The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
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