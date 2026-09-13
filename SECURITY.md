# Security Policy

## Reporting a Vulnerability

This project ships devcontainer features that run **as root inside the container** by design (the standard devcontainer feature contract) and may pull model weights from HuggingFace. Please treat security seriously.

If you find a vulnerability:

- **Do not open a public issue** for security bugs that could be exploited before a fix ships.
- Email the maintainer (see the GitHub profile for contact info), or
- Open a private advisory via GitHub: **Security → Report a vulnerability** on this repository.

Please include:

1. The affected feature and version (check `devcontainer-feature.json`).
2. A description of the vulnerability and its impact.
3. Reproduction steps (image, options, commands).
4. Any suggested fix, if you have one.

## Scope

In scope:

- The `install.sh` scripts and feature manifests in this repo
- The scaffold payload of the `opencode-agents` feature (AGENTS.md, `.opencode/agent/*.md`)
- The `llm-lab` template's generated `devcontainer.json`
- The website (`docs/index.html`)

Out of scope (run at your own risk, follow upstream advisories):

- The llama.cpp / llama-server binary (upstream: ggerganov/llama.cpp)
- Bifrost gateway (upstream: maximhq/bifrost)
- GGUF models downloaded from HuggingFace (review model licenses before use)
- opencode itself (upstream: opencode)

## Security Posture

- Features are **idempotent** and refuse to clobber an existing install unless explicitly asked.
- The models feature **never bakes weights into image layers** — models stay in the bind-mounted workspace.
- Tailscale is recommended for remote access instead of exposing ports to the public internet — see the website's "Work From Anywhere" section.

## Supported Versions

| Version | Supported          |
|---------|--------------------|
| 1.0.0   | :white_check_mark: |
| < 1.0   | :x:                |