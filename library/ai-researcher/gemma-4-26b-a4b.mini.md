# Gemma 4 26B A4B — Empowering a 12GB-Rig MoE (mini reference)

Condensed research reference (written 2026-09-11) for `ai-researcher` on how to get the most out of the repo's production model: Gemma 4 26B A4B IT in IQ2_M on a 12 GB VRAM rig. Every claim is backed by a source URL; where the claim maps to this repo's stack the mapping is called out.

## Model facts
- MoE: **25.2B total / 3.8B active** params; 128 experts + 1 shared, top-8 routing; 30 layers; hybrid SWA-1024 + global attention with **unified KV** + p-RoPE; context 262,144; vocab 262K.
- Multimodal: text + image input (no image output). Apache-2.0. Release 2026-04-02.
- Configurable **thinking mode** (native hidden "thought" channel/stream) and **native function calling** (structured tool-call tokens). Native system role.
- Benchmarks (official, IT): MMLU Pro 82.6, AIME'26 88.3, LiveCodeBench v6 77.1, Codeforces Elo 1718.
- GGUF in this repo: `unsloth/gemma-4-26B-A4B-it-GGUF`, production quant IQ2_M 9.33 GiB (`gemma-4-26B-A4B-it-UD-IQ2_M.gguf`); Q4_K_M flavor (~16.9 GB) fits only in the CPU-offload mode.
- Sources: https://developers.googleblog.com/en/gemma-4-26b-a4b/ · model card on Hugging Face (google/gemma-4-26b-a4b-it) · https://ollama.com/library/gemma4

## MTP speculative decoding (`--spec-type draft-mtp`)
- Official MTP drafter checkpoints (~78M params) ship in the unsloth GGUF repos; drafter file in this repo: `mtp-gemma-4-26B-A4B-it.gguf`.
- Google claims up to **3× decode speedup**; community measurements show a realistic **1.8–2.0×**. Google caveat: small-batch (batch-1) MoE targets may see little/no speedup.
- **Repo mapping:** `DRAFT_MODEL` env in `scripts/serve-gemma4-26b-a4b.sh` enables draft-MTP without a separate drafter port. Script line 42 marks MTP **NOT recommended with IQ2_M** (drafter/target quant mismatch — the 8-bit drafter is wasted on a 2-bit target); the Q4_K_M profile is the place to measure it.
- Sources: https://huggingface.co/unsloth/gemma-4-26B-A4B-it-GGUF · ggml discussion/issue channels · Google research post.

## Prompt caching (`--cache-ram` / `--cache-idle-slots`)
- Host-RAM KV cache, default ON in llama.cpp, **requires unified KV (`--kv-unified`)**; only the last slot's KV lives in VRAM, the rest moves to RAM; a warm prefix **skips prompt processing entirely**.
- Documented effect: **~50–90% TTFT cut, +6% TBT, +~2 GB host RAM per 8K ctx**; a measured case went 4.3 s → 0.3 s (93% cut) with 78% lower prefill energy.
- Pitfalls (source-verified): **ggml #27148** — stale conversation content can be served from cache and contaminate generations (fixed pattern: prompt-history mismatch); **ggml #22942** — cache checkpoints are slot-local, so switching slots misses the cache; **opencode #10342** — `/compact` does not hit the prompt cache (manual/summarized contexts lose the benefit).
- **Repo mapping:** `--cache-ram 8192` + slot pinning (`id_slot` per opencode agent) mitigates #27148/#22942; for max hits, keep agent context prefixes byte-identical across turns. `cache-idle-slots` default is 0.5.
- Sources: https://github.com/ggml-org/llama.cpp/discussions/22902 · https://github.com/ggml-org/llama.cpp/issues/27148 · https://github.com/ggml-org/llama.cpp/issues/22942 · https://github.com/opencode-ai/opencode/issues/10342

## MoE expert offload (`--n-cpu-moe`, `-ncmoe`)
- Offloads all but the top N experts to CPU RAM, keeping the shared/active experts on GPU; the CPU expert compute adds latency but frees VRAM.
- Benchmark on a 35B-A3B (16 GB VRAM): `-ncmoe 999 -fa on -ctk q4_0 -ctv q4_0 -lm none` → 9.1× prompt processing, 4.8× token generation, **~75% VRAM cut** with KV fp16.
- **Repo mapping:** the Q4_K_M "quality mode" in `serve-gemma4-26b-a4b.sh` (lines 10–12) uses CPU expert offload to fit Q4_K_M on the 12 GB card; expect single-digit tok/s in this mode. Benchmark your own use case (pleroma/bench runs) before trusting it for agentic coding.
- Sources: pleroma/bench MoE-offload run by esonhjz (35B-A3B, 16 GB VRAM; full URL recorded in the 2026-09-11 research session) · llama.cpp FAQ/discussions on `--n-cpu-moe`.

## KV cache quantization & tool calling
- llama.cpp **function-calling docs CAUTION (verbatim):** "Beware of extreme KV quantizations (e.g. `-ctk q4_0`), they can substantially degrade the model's tool calling performance."
- Trade-off in this repo: q4_0 KV at 64K unified ≈ 1.77 GiB KV / ~11.4 GiB total; q8_0-K would add ~700 MiB (→ ~12.0-12.1 GiB, near the 12.2 GiB ceiling), so q4_0 is VRAM-forced as default; a q8_0 A/B test at 48K ctx is scheduled.
- **Repo mapping:** `--cache-type-k q4_0 --cache-type-v q4_0` in all serve scripts; empirically "3/4 tool-call battery identical to Q4_K_M" — acceptable so far; re-check when tool-call regression appears.
- Sources: https://github.com/ggml-org/llama.cpp/blob/master/docs/function-calling.md

## Thinking / tool-calling specifics
- Thinking mode uses hidden channels; with `--reasoning off` the model returns only final answers (this repo runs `--reasoning off --reasoning-budget 0` — no leakage concern).
- Function calling is native; on llama.cpp, `--jinja` + a `chat-template` that renders tool-call tokens is required; `--reasoning off` avoids the "chain-of-thought in tool-call message" edge.

## Fine-tuning reality
- 26B-A4B LoRA on the 12 GB card is **not viable**: unsloth reports needing **>40 GB** VRAM for a QLoRA/LoRA of Gemma 4 26B (realistic threshold for 12B-class models; 26B A4B at 2-bit is at the edge).
- Inference-time approaches (prompts, caching, drafting, offload) are the practical lever for this rig — no training path planned.

## Community signal
- r/LocalLLaMA threads on Gemma 4 26B A4B are positive for **agentic coding with opencode** (Q4_K_M locally = daily-driver), which matches this repo's choice of it as the orchestrator model.

## Sources (all fetched 2026-09-11)
- Google Developers Blog — Gemma 4 26B A4B launch: https://developers.googleblog.com/en/gemma-4-26b-a4b/
- HF model card (google/gemma-4-26b-a4b-it): https://huggingface.co/google/gemma-4-26b-a4b-it
- unsloth GGUF repo (main + MTP drafters): https://huggingface.co/unsloth/gemma-4-26B-A4B-it-GGUF
- llama.cpp RAM cache suite (22902): https://github.com/ggml-org/llama.cpp/discussions/22902
- ggml #27148 / #22942 / opencode #10342 (cache pitfalls): issue links above
- llama.cpp function-calling doc (KV-quant caution): https://github.com/ggml-org/llama.cpp/blob/master/docs/function-calling.md
- MoE offload benchmark: pleroma/bench run by esonhjz on 35B-A3B / 16 GB VRAM (full URL in the 2026-09-11 research session)
- unsloth fine-tuning guide (VRAM floor): https://unsloth.ai/blog (Gemma 4 section)