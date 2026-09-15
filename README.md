# agentic-devcontainer-feature

**All-in-one Local LLM Developer Box — DevContainer Features Collection**

[README](README.md) · [CONTRIBUTING](CONTRIBUTING.md) · [SECURITY](SECURITY.md) · [LICENSE](LICENSE)

This repository contains the canonical source for the agentic devcontainer feature collection. It can be used as:

- **A standalone devcontainer feature home** — published to GHCR and consumable by other repos
- **A reference collection** — 5 features + `llm-lab` template for local LLM development
- **A self-consuming devcontainer** — see "Self-Consumption" below

## Quick Start for New Repos

### Template Path (recommended)
```bash
devcontainer templates apply -w <your-repo> -t ghcr.io/nmwael/agentic-devcontainer-feature/llm-lab
```
This generates `.devcontainer/devcontainer.json` with:
- `GPU_MODE` [wsl2, native, none]
- `MODEL` [gemma-4-26B-A4B-it-UD-IQ2_M] — legacy single-model option
- `MODELS` / `ROLES` — JSON multi-upstream overrides (N models served simultaneously, default = single-model `gemma4-26b-a4b`)
- `FEATURES_TAG` [1]
- `INCLUDE_AGENTS` / `INCLUDE_MODELS` / `INCLUDE_LIBRARY` booleans
- `runArgs` with `--device=nvidia.com/gpu=all`, forwardPorts
- `opencode.json` generated into the workspace from `stack.json` (generate-opencode.sh/.jq; the bundled slot-pinned fragment is the no-manifest fallback — fills only empty/absent configs)

### Direct Features Path
Add to your `devcontainer.json` features block:
```json
"features": {
    "ghcr.io/nmwael/agentic-devcontainer-feature/llama-server": "1",
    "ghcr.io/nmwael/agentic-devcontainer-feature/gpu-bridge": "1",
    "ghcr.io/nmwael/agentic-devcontainer-feature/bifrost-gateway": "1",
    "ghcr.io/nmwael/agentic-devcontainer-feature/models": "1",
    "ghcr.io/nmwael/agentic-devcontainer-feature/opencode-agents": "1",
    "ghcr.io/tailscale/codespace/tailscale": { "version": "latest" }
}
```
Plus `--device=nvidia.com/gpu=all` in `runArgs`.

## Per-Feature Details

### llama-server
- **Provides:** Prebuilt llama.cpp server with OpenAI-compatible `/v1` API
- **Graceful degradation:** If binary unavailable, feature idempotently NO-OPs (detects existing `/opt/llama-server`)
- **Options:** `VERSION` [b10360], `CUDA_ARCHS` [80;86;89;90;120], `ASSET_URL`, `INSTALL_PATH` [/opt/llama-server], `COMPILE` [false], `BUNDLE_CUDA_LIBS` [true]
- **Installs:** `llama-server` binary + `.so*` libs to `INSTALL_PATH`, symlinks to `/usr/local/bin/llama-server`
- **Use case:** Local LLM serving with CUDA acceleration

### gpu-bridge
- **Provides:** WSL2 GPU bridge as a feature; NO-OP on native Linux
- **WSL2 detection:** Checks `/proc/version` for "microsoft" or `/usr/lib/wsl/lib` existence
- **Options:** `WSL2_ONLY` [false], `ENV_REWRITE` [true]
- **If WSL2:** Symlinks CUDA loader libs from `/usr/lib/wsl/drivers/*/` → `/usr/lib/wsl/lib/` for `libcuda.so.1`, `libcuda_loader.so`, `libnvidia-ml.so.1`, `libnvidia-ptxjitcompiler.so.1`, `libnvdxgdmal.so.1`
- **ENV_REWRITE:** Appends `/usr/lib/wsl/lib:/opt/llama-server:/usr/local/cuda/compat:...` to `/etc/environment`
- **postStartCommand:** Re-symlinks and verifies `/dev/dxg` on every container start
- **Use case:** Enable llama-server GPU serve inside WSL2

### bifrost-gateway
- **Provides:** Pinned `@maximhq/bifrost` install + config scaffold
- **Installs:** `npm install --prefix /usr/local/share/llm-lab/bifrost @maximhq/bifrost@<pin>`
- **Launches:** `start-bifrost` script honoring `BIFROST_PORT` / config
- **Config:** `write-bifrost-config.sh` materializes `config/bifrost.json` (v2 schema) from `stack.json` — one provider per llama-server upstream (base_url `:port/v1`), routed by `keys[].models = ["{name}*"]`
- **Options:** `PORT` [8082], `VERSION` [latest], `LLAMA_PORT` [8089, legacy single-upstream fallback]
- **Honors env:** `BIFROST_PORT` (overrides the `PORT` option/`stack.json.bifrost_port` at launch)
- **installsAfter:** [llama-server] (soft)
- **Use case:** Bifrost gateway exposing llama-servers as OpenAI-compatible providers

### models
- **Provides:** On-demand model fetch + the shared `stack.json` manifest (write once, consumed by bifrost, opencode-agents, auto-startup); weights are NEVER baked into image layers
- **Installs:** `fetch-models.sh` (iterates `stack.json.models[]`) to `/usr/local/share/llm-lab/models/`, plus `stack.json` at `/usr/local/share/llm-lab/stack.json`
- **Options:** `MODELS`/`ROLES` [JSON multi-upstream, schema-1], `BIFROST_PORT` [8082], `MODEL` [gemma-4-26B-A4B-it-UD-IQ2_M] / `QUANT` [IQ2_M] (legacy single-model), `MODELS_DIR` [default: $PWD/models]
- **stack.json schema:** `models[] = { name, provider, hf, quant, port, context, parallel }`; each entry becomes its own llama-server, opencode provider, and bifrost upstream
- **fetch-models.sh:** Idempotent: skip if the target file already exists; `curl -L --retry 5 --continue-at -`
- **MODELS_DIR:** Derived from workspace when unset (default `$PWD/models` → bind-mount friendly)
- **Use case:** Download and cache GGUF models without bloating the image

### opencode-agents
- **Provides:** Complete primary agentic setup + library (AGENTS.md / AGENTS_LIFECYCLE.md, `.opencode/agent/*.md`, library/ reference books)
- **Consumer-extensible + opt-out:** `WITH_LIBRARY` boolean option
  - `WITH_LIBRARY=true` (default): Ships library books with attribution/README + LICENSE notices
  - `WITH_LIBRARY=false`: Installs NO shipped library books (zero redistribution surface); leaving only extension docs + empty register; the rest of the agentic setup is unaffected and functional
- **Scaffold mechanism:** `scaffold.sh` copies payload into workspace (idempotent, skip-if-exists unless `OVERWRITE=true`)
- **Payload contents:** AGENTS.md + AGENTS_LIFECYCLE.md, `.opencode/agent/*.md` (7 role definitions), library/skills + library/ai-researcher (2 mini-books), release-it.mini.md, EXTENSIONS.md
- **EXCLUDED:** domainbooks/, 3dprints/library/, repo-specific project_stack.md, boxforsine flows/SCAD, cad-validate/verify-pair skills
- **Library Extensions Guide:** Documents how consumers can add books by dropping files into `library/<role>/` and registering in `library/README.md`'s consumer section; the shipped register is never overwritten once the consumer edits it (no-clobber guarantee)
- **Config generation:** `generate-opencode.sh` + `generate-opencode.jq` emit `opencode.json` from `stack.json` — one provider per model (`provider.models[].name = <name>-s<slot>`, `limit.context` from the model `context` field), primary+subagents with role→slot pinning, permissions, compaction, `subagent_depth`; the bundled `opencode.json.fragment` is the no-manifest fallback
- **Options:** `OVERWRITE` [false], `WITH_LIBRARY` [true], `INSTALL_DIR` [/usr/local/share/opencode-agents]
- **Use case:** Full opencode agentic setup with behavioral HITL contract

## Self-Consumption

This repository can **self-consume** — meaning you can use the feature collection from within itself. Since the repo is the canonical source, you can:

1. **Add the features to your own devcontainer.json** (just like any other consumer repo)
2. **Or use the template:** `devcontainer templates apply -w . -t ghcr.io/nmwael/agentic-devcontainer-feature/llm-lab`
3. **Or reference features directly:** Add the 5 features to `.devcontainer/devcontainer.json`

When self-consuming, the repo will boot with:
- One llama-server per `stack.json` model (default `gemma4-26b-a4b` at `:8089`)
- Bifrost gateway at `:8082`
- Opencode agents scaffolded with AGENTS.md/AGENTS_LIFECYCLE.md
- Library books installed (unless `WITH_LIBRARY=false`)
- Models fetched via `fetch-models.sh`
- Agentic workflow following the HITL approval contract

This makes the repo both a **reference implementation** and a **working developer box** — you can `devcontainer up` and immediately have the full stack running.

## Contributing

See **[CONTRIBUTING.md](CONTRIBUTING.md)** for the full development workflow, how to add features, and library contribution rules.

### Quick Summary

1. Make changes to the feature source under `src/<feature-name>/` (e.g. `src/llama-server/install.sh`)
2. Validate with `devcontainer features info -f ./src/llama-server`
3. Test scenarios with `devcontainer features test` and the shared `test/` scenarios
4. Update `docs/index.html` if the feature description changes
5. Open a PR — one logical change per PR

### Publishing

Publishing happens in CI via `.github/workflows/release.yaml`:

```bash
# Features (the whole collection in one command — publishes collection metadata too)
devcontainer features publish ./src -r ghcr.io -n nmwael/agentic-devcontainer-feature

# Template
devcontainer templates publish ./src/templates -r ghcr.io -n nmwael/agentic-devcontainer-feature-templates
```

Requires `GITHUB_TOKEN` (automatic, with `packages: write` job permission). CI publishes on push to `main` or `v*` tags — do not publish from local.

## Repository Structure

This repository is the extracted, standalone feature collection in the canonical devcontainer layout (features under `src/`, template under `src/templates/`):

```
.
├── src/
│   ├── llama-server/        # Prebuilt llama.cpp server feature
│   ├── gpu-bridge/          # WSL2 GPU bridge feature
│   ├── bifrost-gateway/     # Bifrost gateway feature
│   ├── models/              # On-demand model fetch feature
│   ├── opencode-agents/     # Multi-agent setup + library feature
│   └── templates/
│       └── llm-lab/         # llm-lab template (devcontainer-template.json + tests)
├── library/             # Reference books shipped by opencode-agents
├── docs/                # Website (index.html) — GitHub Pages source
├── test/                # Shared test scenarios
├── .devcontainer/       # Self-consuming devcontainer (dogfooding)
├── .github/workflows/   # CI (release.yaml publishes features + template)
├── README.md            # This file
├── CONTRIBUTING.md      # Contribution guide
├── SECURITY.md          # Security policy
├── CHANGELOG.md         # Version history
└── LICENSE              # MIT license
```

## Per-Feature Summary (for Website)

| Feature | Key Options | Install Path | postStart |
|---------|------------|-------------|-----------|
| **llama-server** | VERSION, CUDA_ARCHS, BUNDLE_CUDA_LIBS | /opt/llama-server | None (idempotent) |
| **gpu-bridge** | WSL2_ONLY, ENV_REWRITE | /usr/local/share/llm-lab/gpu-bridge | Re-symlinks + /dev/dxg verify |
| **bifrost-gateway** | PORT, VERSION, LLAMA_PORT | /usr/local/share/llm-lab/bifrost | None (config scaffold) |
| **models** | MODELS, ROLES, BIFROST_PORT, MODEL, QUANT, MODELS_DIR | /usr/local/share/llm-lab/models | None (script install + manifest) |
| **opencode-agents** | OVERWRITE, WITH_LIBRARY, INSTALL_DIR | /usr/local/share/opencode-agents | scaffold.sh copies payload |

## Website

The website at `docs/index.html` provides:
- Hero section with project name, tagline, and badge row
- **What You Get** — 5 feature cards (llama-server, gpu-bridge, bifrost-gateway, models, opencode-agents) with install paths, behaviors, and options
- **Multi-Role Agent Setup** — full agent roster (build → architect → coder/researcher/reviewer/ai-researcher/ui/artist), the HITL approval workflow, and what consumers get
- **Work From Anywhere with Tailscale** — mesh-network access to `:8082` (bifrost), `:8089` (llama-server), `:4096` (opencode) from your phone with zero public exposure
- Quick Start — template path and direct-features path with `runArgs`
- How to Use — consumer, self-consumption, contributor modes
- Footer — repo and doc links

The website is served via GitHub Pages from the `/docs` folder on the `main` branch.

## Acceptance Criteria

Either (a) the `llm-lab` template is applied into a fresh repo, or (b) the repo references all 5 features directly + `--device=nvidia.com/gpu=all` → container boots and serves the IQ2_M model through bifrost (8082) into opencode on BOTH WSL2 and native Linux hosts; workspace is scaffolded with the full agentic contract (AGENTS.md/AGENTS_LIFECYCLE.md, `.opencode/agent/*`, library books + attribution) and `opencode` lists the same primary+sub agents as this repo.

**Library contract holds both ways:** consumer-added book under `library/<role>/` + register entry survives re-scaffold (incl. OVERWRITE=true); `WITH_LIBRARY=false` consumer boots agents-without-library configuration (no shipped books, empty register preserved, agents functional).
