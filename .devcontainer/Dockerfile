FROM mcr.microsoft.com/devcontainers/base:ubuntu

RUN apt-get update && apt-get install -y \
    git curl unzip xz-utils zip \
    libglu1-mesa \
    python3 python3-venv python3-pip \
    && rm -rf /var/lib/apt/lists/*
