# Use Debian 12 as base
FROM debian:12

ARG USERNAME=dev
ARG USER_UID=1000
ARG USER_GID=1000

# Install required build tools for Debian packages
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y \
        # Core Debian package building tools (for mkdebs.sh)
        build-essential dpkg-dev debhelper fakeroot lintian \
        # Security and version control
        gnupg2 git sudo \
        # Python and pip for MkDocs (for mkdocs.sh)
        python3 python3-pip python3-venv python3-full \
        # Compression and archiving tools (for mkrepo.sh)
        gzip bzip2 tar xz-utils \
        # Network and download tools (for generated scripts)
        curl wget \
        # Text processing and utilities (for all scripts)
        coreutils findutils sed grep \
        # Additional utilities for repository creation
        file \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install MkDocs and dependencies as the user (not root)
# This will be done in mkdocs.sh script to ensure proper user installation

# Create a non-root user matching host UID/GID (will be overridden by devcontainer "updateRemoteUserUID")
RUN set -eux; \
    if ! getent group "$USERNAME" >/dev/null; then \
        groupadd --gid "$USER_GID" --non-unique "$USERNAME"; \
    fi; \
    if ! id -u "$USERNAME" >/dev/null 2>&1; then \
        useradd --uid "$USER_UID" --gid "$USER_GID" --non-unique -m "$USERNAME"; \
    fi; \
    echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/$USERNAME; \
    chmod 0440 /etc/sudoers.d/$USERNAME

# Set non-root user by default
USER $USERNAME
WORKDIR /home/$USERNAME

# (Optional) any post-install steps for your environment
