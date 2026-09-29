# syntax=docker/dockerfile:1
#
# agentic-devcontainer-feature — Base image for the feature collection home repo
# Uses nvidia/cuda runtime; features activate on top via devcontainer.json
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
FROM ghcr.io/ggml-org/llama.cpp@sha256:5d0812fe45cb5dcb4ac5c588148a601aca63b6b224601f8d1f6f01fdfb07a111 AS llamacpp

FROM nvidia/cuda:12.8.1-cudnn-runtime-ubuntu24.04

ARG USERNAME=vscode
ARG USER_UID=1000
ARG USER_GID=1000

ENV DEBIAN_FRONTEND=noninteractive \
    USERNAME=${USERNAME} \
    USER_UID=${USER_UID} \
    USER_GID=${USER_GID}

# 1. Install sudo and ensure the configuration directory exists.
#    python3.12 = FULL stdlib (json etc.); the base image only ships
#    python3.12-minimal, and crewai/uv venv sync fails without it.
#    libgomp1 === the prebuilt ggml libraries are OpenMP-linked exactly like the
#    release build, and libgomp1 is a separate package from libgcc-s1. Without
#    it every llama-server binary dies with "libgomp.so.1: cannot open shared
#    object file", including the CPU fallback the feature installs.
RUN apt-get update && apt-get install -y --no-install-recommends sudo python3.12 libgomp1 \
    && mkdir -p /etc/sudoers.d \
    && rm -rf /var/lib/apt/lists/*

# 2. Flatten the CUDA build into /opt/llama-server. Two reasons this exact path
#    matters: (a) the llama-server feature checks for
#    /opt/llama-server/llama-server and no-ops when present ("custom image as
#    base") — otherwise it installs the CPU build over the top and silently
#    shadows the GPU one; (b) it keeps the feature's documented install layout.
COPY --from=llamacpp /app/ /opt/llama-server/

# 3. Library resolution. The upstream binary carries RUNPATH="/app/build/bin:"
#    — a build-time path absent from the finished image, with a trailing colon
#    the loader reads as an empty entry, i.e. "also search the current working
#    directory". Upstream only works because its WORKDIR is /app, so it breaks
#    the moment anything runs it from elsewhere. ldconfig makes it
#    cwd-independent instead of relying on that. The --version check runs from /
#    so a regression here fails the build rather than the first agent prompt.
RUN echo /opt/llama-server > /etc/ld.so.conf.d/llama-server.conf \
    && ln -sf /opt/llama-server/llama-server /usr/local/bin/llama-server \
    && ldconfig \
    && cd / && /opt/llama-server/llama-server --version

# 4. Create the vscode user (idempotent UID/GID handling)
RUN EXISTING_USER=$(getent passwd ${USER_UID} | cut -d: -f1) \
    && EXISTING_GROUP=$(getent group ${USER_GID} | cut -d: -f1) \
    && if [ -n "${EXISTING_USER}" ]; then \
        if [ "${EXISTING_USER}" != "${USERNAME}" ]; then \
            usermod -l ${USERNAME} ${EXISTING_USER} && usermod -d /home/${USERNAME} -m ${USERNAME}; \
        fi; \
    else \
        if ! getent group ${USER_GID} >/dev/null; then groupadd --gid ${USER_GID} ${USERNAME}; fi \
        && useradd --uid ${USER_UID} --gid ${USER_GID} -m ${USERNAME}; \
    fi \
    && if [ -n "${EXISTING_GROUP}" ] && [ "${EXISTING_GROUP}" != "${USERNAME}" ]; then \
        groupmod -n ${USERNAME} ${EXISTING_GROUP}; \
    fi

# 5. Allow the resolved vscode user to run sudo without a password
RUN echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/${USERNAME} \
    && chmod 0440 /etc/sudoers.d/${USERNAME}

# 6. Safe creation of the models directory and assign ownership
RUN mkdir -p ${MODELS_DIR:-/workspaces} && chown -R ${USER_UID}:${USER_GID} ${MODELS_DIR:-/workspaces}

# 7. Post-create command will handle the rest via features

# Switch to the final non-root user context
USER ${USERNAME}
WORKDIR /workspaces

CMD ["bash"]
