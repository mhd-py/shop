#!/bin/bash
set -e

echo "=== Installing Flutter ==="

if [ ! -d "$HOME/flutter" ]; then
    git clone https://github.com/flutter/flutter.git \
        -b stable "$HOME/flutter"
fi

export PATH="$HOME/flutter/bin:$PATH"

flutter config --no-analytics
flutter config --enable-web

echo "=== Checking Flutter ==="
flutter doctor

echo "=== Creating Python virtual environment ==="

cd /workspaces/shop

if [ ! -d ".venv" ]; then
    python3 -m venv .venv
fi

source .venv/bin/activate

pip install --upgrade pip
pip install pytest ruff

echo "=== Setup completed ==="
