# Project Stack & Specifications

## Purpose
A devcontainer that runs `llama-server` (from llama.cpp) on an NVIDIA GPU and exposes it to `opencode` as local LLM providers through a Bifrost gateway. Used for AI-assisted coding entirely offline / locally (the hosted `opencode` Console is the only cloud path, and only for the primary agent fallback).

## Software Stack
- **Loader:** llama.cpp `llama-server`, built from source with `GGML_CUDA=ON`. Custom Gemma-4 fork lineage (commit `48d22e2` era — see `scripts/serve-gemma4-26b-a4b.sh` comments). Binaries in `/opt/llama-server/`: `llama-server` is a 17 KB launcher; the real implementation is `libllama-server-impl.so` (always string/flag-check the impl lib, not the launcher). Supports: MTP speculative decoding (`--spec-type draft-mtp`), RAM prompt cache (`--cache-ram` / `--cache-idle-slots`), unified KV (`--kv-unified`), MoE CPU expert offload (`--n-cpu-moe`). Unknown OpenAI-style extras (e.g. `prompt_cache_key`) are silently ignored; the rejection that bit us came from the hosted `opencode` provider (see Conventions).
- **Gateway:** Bifrost v2.1.1 (pinned via `BIFROST_TRANSPORT_VERSION=v2.1.1`) on port 8082; tmux session `bifrost`; config `config/bifrost.json` -> `data/bifrost/config.json`; binary cache pinned into the workspace (`data/bifrost/cache`) so it survives container rebuilds.
- **Orchestrator:** opencode serve on port 4096 (`server.port` in `opencode.json`), bundle v1.18.30 at `/usr/local/bin/opencode`.
- **Base image:** `nvidia/cuda:12.6.3-cudnn-devel-ubuntu24.04`. Node 22 from nodesource (opencode needs Node >=20).

## Model Specifications
- **Production default:** Gemma 4 26B A4B IT (MoE: 25.2B total / 3.8B active, 128 experts + 1 shared, top-8 routing, 30 layers, 256K ctx, built-in thinking mode, native function calling), unsloth UD-GGUF `gemma-4-26B-A4B-it-UD-IQ2_M.gguf` (9.33 GiB — fits ENTIRELY in 12 GB VRAM with `CPU_MOE=0`). Model alias: `gemma4-26b-a4b`. See `library/ai-researcher/gemma-4-26b-a4b.mini.md` for the model reference.
- **Slot mapping** (5 slots, `--kv-unified` shared 65536-token pool; opencode pins each agent to a slot by sending `id_slot`; model ids from `provider.local-gemma4-26b.models` in `opencode.json`):
  - `gemma4-26b-a4b-s0` — architect (context 65536)
  - `gemma4-26b-a4b-s1` — coder (context 49152)
  - `gemma4-26b-a4b-s2` — researcher (context 49152)
  - `gemma4-26b-a4b-s3` — reviewer (context 49152)
  - `gemma4-26b-a4b-s4` — build + ui/artist/ai-researcher (context 32768)
  - `gemma4-26b-a4b` — unpinned fallback (context 65536)
  - `model` and `small_model` in `opencode.json` point at `local-gemma4-26b/gemma4-26b-a4b-s4`.
- **Other enabled providers:** `opencode` (hosted Console; MUST carry `options.setCacheKey=false`, see Conventions), `local-gemma4-12b` (`gemma4-12b-orchestrator`, 65536, Q4_K_M + MTP), `local-gemma4-31b` (`gemma4-31b-orchestrator`, 32768, IQ2_XXS). Legacy, unused but still configured: `local-nemotron` (`nemotron-orchestrator-8b`), `local-qwen3` (`qwen3-4b-instruct`).
- **Bifrost upstreams** (`config/bifrost.json`, all `base_provider_type: openai`): `llama-26b` -> `http://127.0.0.1:8089`, `llama-31b` -> `:8088`, `llama-12b` -> `:8087`. opencode provider options must set header `x-bf-passthrough-extra-params: true` so `id_slot` reaches llama-server.
- **Model ID sync:** the model id under `provider.models` and the `--alias` passed to `llama-server` (and the bifrost `models` list) MUST stay in sync, or completion requests 404.

## Serve Flags that Matter (serve-gemma4-26b-a4b.sh)
- `CTX=65536` + `SLOTS=5` + `--kv-unified`: every slot reports 65536 and a solo slot gets the full 64K (verified empirically; source-verified against commit 48d22e2).
- `--cache-ram 8192` + `--cache-idle-slots` (default on; requires unified KV): host-RAM prompt cache, warm prompts skip prompt processing (see ggml #27148 stale-conversation caveat — opencode's per-agent `id_slot` pinning keeps prefixes identical and is the mitigation).
- KV cache: `--cache-type-k q4_0 --cache-type-v q4_0` (VRAM-forced at 64K unified on 12 GB; upstream llama.cpp warns `-ctk q4_0` can degrade tool-calling — locally verified "tool-call quality identical to Q4_K_M (3/4 on same battery)"; q8_0 A/B is scheduled for the next server-up session).
- `--reasoning off --reasoning-budget 0`, `--temp 0.3 --top-p 0.95 --min-p 0.05 --repeat-penalty 1.1`.
- MTP drafting: `DRAFT_MODEL=mtp-gemma-4-26B-A4B-it.gguf` enables `--spec-type draft-mtp` (currently OFF; NOT recommended with IQ2_M — drafter/target quant mismatch; retest with the Q4_K_M mode).

## Environment & Hardware
- **GPU:** NVIDIA GPU, **12 GB VRAM** (measured ceiling ≈12.2 GiB for the 26B IQ2_M profile: VRAM 11.6-12.2 GiB with 2x64K slots).
- **CUDA Architectures:** 80, 86, 89, 90, 120 (Ampere, Ada, Hopper, Blackwell).
- **Older cards:** add `75` to `CMAKE_CUDA_ARCHITECTURES` in the Dockerfile on Turing if "no kernel image available" errors occur.

## Project Conventions
- **Context limits:** raise `--ctx-size` (`CTX` env) on serve scripts on "context length exceeded"; `limit.context` in `opencode.json` should match the value set in the serve script.
- **Hosted provider fix (REQUIRED):** `provider.opencode.options.setCacheKey = false` — opencode injects `prompt_cache_key` into requests to any provider whose `providerID` starts with `"opencode"`; the hosted (llama.cpp-based) backend rejects that argument. Without this override every hosted completion fails.
- **Model storage:** keep `models/` gitignored. Never commit `.gguf` files; use `scripts/fetch-*.sh` for reproducibility.
- **gpg:** `commit.gpgsign=true` is set but gpg fails in this environment — commit with `git -c commit.gpgsign=false commit` (unset config if desired).