# Contributing to agentic-devcontainer-feature

Thanks for helping build the all-in-one Local LLM Developer Box. This guide covers the development workflow, how to add or modify features, and how to contribute to the library.

## Repository Layout

This repo is the **extracted, canonical source** of the feature collection. Features live at the top level (each directory is a complete devcontainer feature):

```
.
├── llama-server/        # Prebuilt llama.cpp server feature
├── gpu-bridge/          # WSL2 GPU bridge feature
├── bifrost-gateway/     # Bifrost gateway feature
├── models/              # On-demand model fetch feature
├── opencode-agents/     # Multi-agent opencode setup + library
├── llm-lab/             # llm-lab template (devcontainer-template.json + tests)
├── library/             # Reference books shipped by opencode-agents
├── docs/                # Website (GitHub Pages: /docs on main)
├── test/                # Shared test scenarios
└── .devcontainer/       # Self-consuming devcontainer (dogfooding)
```

The upstream source-of-truth repo (`opencode-local-lab`) regenerates this tree with `scripts/extract-features.sh`; production changes should be made there and re-extracted, or made here directly if they only concern the extracted repo.

## Prerequisites

- Dev Container CLI (`devcontainer`), version 0.89.0 or newer
- A container runtime (Docker or podman) for `devcontainer features test`
- GitHub CLI (`gh`) for publish/PR workflows

## Development Workflow

1. **Make changes** to the feature you are working on (its `devcontainer-feature.json` and/or `install.sh`).
2. **Validate the feature manifest**:
   ```bash
   devcontainer features info -f ./llama-server
   ```
3. **Test scenarios** (if you changed install behavior), run the feature test suite:
   ```bash
   devcontainer features test -f ./llama-server -i ghcr.io/devcontainers/features/universal:latest
   ```
   Add or update `test/scenarios.json` entries in `./test/` when behavior changes.
4. **Check the dependency graph**:
   ```bash
   devcontainer features resolve-dependencies --workspace-folder .
   ```
5. **Review the diff**, keep changes small and focused on one feature per PR.

## Adding a New Feature

1. Create `<feature-name>/` at the repo root with:
   - `devcontainer-feature.json` — manifest (id, version, options, `installsAfter`)
   - `install.sh` — must be idempotent and exit non-zero on hard failure
2. Follow the conventions of existing features:
   - Options are `boolean|string` only (no object/array options)
   - `install.sh` runs as root
   - Idempotence: detect an existing install (e.g. `[ -d /opt/llama-server ]`) and NO-OP instead of clobbering
3. Add test scenarios under `test/` for at least one representative image.
4. Update `docs/index.html` with a feature card for the new feature.
5. Update `README.md` per-feature table.
6. Open a PR (see below).

## Contributing to the Library

The `library/` directory ships reference books to consumers via the `opencode-agents` feature.

- Add your book as a document under `library/<role>/` (e.g. `library/coder/`).
- Register it in `library/README.md` with source attribution — every shipped book must record where it came from.
- Respect the consumer **no-clobber guarantee**: the shipped register is never overwritten once a consumer edits it. Keep the register append-friendly.
- If your book is not licensed for redistribution, put it in the consumer extension docs instead — do not ship it in `library/`.

## Website (docs/)

The site is served by GitHub Pages from the `/docs` folder on `main`.

- `docs/index.html` is a single self-contained file (inline CSS, no dependencies).
- After content changes, sanity-check the HTML (balanced tags, no broken links).
- The website must mirror README.md: features, options, quick start, and the multi-agent setup description.

## Doc Requirements

- `README.md` — the front door: quick start, per-feature details, self-consumption, structure, acceptance criteria.
- `CONTRIBUTING.md` — this file: how to contribute.
- `SECURITY.md` — how to report vulnerabilities.
- `LICENSE` — MIT (see file for the holder).

## Publishing Workflow

Publishing happens in CI (`.github/workflows/release.yaml`) — do not publish from your local machine.

- **Features:** `devcontainer features publish ./{feature} -r ghcr.io -n nmwael/agentic-devcontainer-feature`
- **Templates:** `devcontainer templates publish ./llm-lab -r ghcr.io -n nmwael/agentic-devcontainer-feature-templates`
- Requires a token with `packages: write` (GitHub Actions `GITHUB_TOKEN` or a PAT stored as `GH_PAT`).

## Pull Requests

1. Branch from `main`: `git checkout -b feat/your-change`
2. One logical change per PR (one feature, one doc fix, one bugfix).
3. Run the relevant tests listed above before opening the PR.
4. In the PR description, state what changed, why, and what you verified.
5. Keep commits atomic and messages descriptive (repo style: imperative mood, e.g. "Add gpu-bridge feature manifest").

## Code of Conduct

Be respectful and constructive. This project is small and human-scale — treat every contribution like it lands in someone's daily dev box.