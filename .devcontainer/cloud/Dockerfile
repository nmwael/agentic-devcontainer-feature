# Cloud-mode lightweight Dockerfile (no llama.cpp, no CUDA/nvidia build stages)
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV PIP_BREAK_SYSTEM_PACKAGES=1

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        curl \
        ca-certificates \
        git \
        vim \
        jq \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /opt /models /data /usr/local/share/llm-lab \
    && chown -R 1000:1000 /opt /models /data /usr/local/share/llm-lab

COPY --chown=1000:1000 scripts /scripts
RUN chmod -R +x /scripts || true
