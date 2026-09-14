# llama.cpp Reference (Tag b10360)

## Overview
- **llama.cpp**: GGML tensor library for high-performance inference of GGUF models.
- **llama-server**: Provides an OpenAI-compatible `/v1` API.

## Build & Architecture
- **Compilation**: Use CMake with `GGML_CUDA=ON`.
- **GPU Architectures**: Repo bakes in 80, 86, 89, 90, 120 (Ampere/Ada/Hopper/Blackwell). Turing (`75`) requires manual addition to `CMAKE_CUDA_ARCHITECTURES`.
- **Multi-GPU**: Supported via `--n-gpu-layers` and backend optimizations.

## Model & Quantization
- **GGUF Format**: Standard for llama.cpp inference.
- **Quantizations**: 
  - `Q4_K_M`, `Q4_K_L`: Balanced quality/size (preferred).
  - `Q8_0`, `F16`: Higher precision, higher memory usage.

## Context & KV Cache
- **Context Window**: Controlled by `--ctx-size`.
- **Parallel Processing**: Use `--parallel <n>` to define slots. Each slot has its own context.
- **KV Cache**: 
  - `--cache-type-k/v q4_0`: Quantized KV cache for memory efficiency.
  - `--flash-attn`: Enables Flash Attention for faster processing and lower memory.
  - `ctx_other`: Required by some architectures (e.g., Gemma4Assistant) to fit assistant layers.

## Speculative Decoding
- **Mechanism**: Uses a draft model to predict tokens, then validates with the main model.
- **Draft Models**: Use `--spec-draft-model` and `--spec-type draft-mtp`.
- **MTP (Multi-Token Prediction)**: Shared KV cache between draft and main models (e.g., `mtp-gemma-4-12b-it`).
- **Parameters**: 
  - `--spec-draft-n-max`: Max tokens to speculate.
  - `--spec-draft-ngl`: Number of GPU layers for the draft model.
  - **Note**: Some models (e.g., Qwen3-0.6B) may show a net loss in acceptance rate; use with caution.

## llama-server Operations
- **Alias**: `--alias <id>` MUST match the `model` ID sent by opencode.
- **Networking**: `--host 0.0.0.0`, `--port <port>`.
- **Metrics**: `--metrics` enables performance tracking.
- **Reasoning**: Use `--reasoning off` to disable specific reasoning modes.
- **Batching**: `--ubatch-size` controls the number of tokens processed per batch.

## Grammar & Constrained Decoding
- **GBNF Grammars**: Use `--grammar` or `--grammar-file` to constrain output structure (e.g., JSON, Bash).
- **llguidance**: Advanced constrained decoding via grammars and logic.
- **Function Calling**: Achieved through grammar-based sampling of JSON schemas.
