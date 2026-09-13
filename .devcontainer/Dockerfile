# agentic-devcontainer-feature — Base image for the feature collection home repo
# Uses nvidia/cuda runtime; features activate on top via devcontainer.json

FROM nvidia/cuda:13.3.0-cudnn-runtime-ubuntu24.04

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
RUN apt-get update && apt-get install -y --no-install-recommends sudo python3.12 \
    && mkdir -p /etc/sudoers.d \
    && rm -rf /var/lib/apt/lists/*

# 2. Create the vscode user (idempotent UID/GID handling)
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

# 3. Allow the resolved vscode user to run sudo without a password
RUN echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/${USERNAME} \
    && chmod 0440 /etc/sudoers.d/${USERNAME}

# 4. Safe creation of the models directory and assign ownership
RUN mkdir -p ${MODELS_DIR:-/workspaces} && chown -R ${USER_UID}:${USER_GID} ${MODELS_DIR:-/workspaces}

# 5. Post-create command will handle the rest via features

# Switch to the final non-root user context
USER ${USERNAME}
WORKDIR /workspaces

CMD ["bash"]
