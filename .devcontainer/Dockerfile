# syntax=docker/dockerfile:1
#
# agentic-devcontainer-feature — base image for the feature collection's own
# devcontainer. Features activate on top via devcontainer.json.
#
# The pinned CUDA llama.cpp stage exists because the llama-server feature
# otherwise installs a CPU-only build: upstream's llama-<v>-bin-ubuntu-x64
# release asset ships no libggml-cuda.so at all, so `llama-server
# --list-devices` reports "(none)" and the bundled libcudart/libcublas go
# unused. No Linux CUDA asset is published for that release line.
#
# The official server-cuda image does ship real kernels. Its libggml-cuda.so
# was checked with cuobjdump, not assumed: it contains sm_120a SASS cubins
# (Blackwell / RTX 5070, compute_cap 12.0) plus PTX for sm_50..sm_90 as a JIT
# fallback. It is built against CUDA 12.8, so the base is aligned to 12.8.1 —
# the 13.3 line has no prebuilt equivalent. Pinned by digest so a floating tag
# cannot silently swap the GPU binary out from under a rebuild.
#
# This keeps the collection's own box on the same GPU stack it ships, so a
# regression in the llama-server feature surfaces here rather than in a
# consumer's container.
FROM ghcr.io/ggml-org/llama.cpp@sha256:5d0812fe45cb5dcb4ac5c588148a601aca63b6b224601f8d1f6f01fdfb07a111 AS llamacpp

FROM nvidia/cuda:12.8.1-cudnn-runtime-ubuntu24.04

# libgomp1 === the prebuilt ggml libraries are OpenMP-linked exactly like the
# release build, and libgomp1 is a separate package from libgcc-s1. Without it
# every llama-server binary dies with "libgomp.so.1: cannot open shared object
# file", including the CPU fallback the feature installs.
RUN apt-get update \
    && apt-get install -y --no-install-recommends libgomp1 ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Flatten the CUDA build into /opt/llama-server. The llama-server feature
# checks for /opt/llama-server/llama-server and no-ops when present ("custom
# image as base") — otherwise it installs the CPU build over the top and
# silently shadows the GPU one.
COPY --from=llamacpp /app/ /opt/llama-server/

# The upstream binary carries RUNPATH="/app/build/bin:" — a build-time path
# absent from the finished image, with a trailing colon the loader reads as an
# empty entry, i.e. "also search the current working directory". Upstream only
# works because its WORKDIR is /app, so it breaks the moment anything runs it
# from elsewhere. ldconfig makes it cwd-independent instead. The --version
# check runs from / so a regression fails the build, not the first prompt.
RUN echo /opt/llama-server > /etc/ld.so.conf.d/llama-server.conf \
    && ln -sf /opt/llama-server/llama-server /usr/local/bin/llama-server \
    && ldconfig \
    && cd / && /opt/llama-server/llama-server --version
