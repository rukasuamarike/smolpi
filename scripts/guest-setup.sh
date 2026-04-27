#!/bin/sh
set -e

echo "[1/4] Updating apt..."
apt-get update

echo "[2/4] Installing packages..."
apt-get install -y --no-install-recommends \
    ca-certificates curl unzip \
    chromium \
    libnss3 libatk1.0-0 libatk-bridge2.0-0 libcups2 \
    libdrm2 libxkbcommon0 libxcomposite1 libxdamage1 \
    libxrandr2 libgbm1 libasound2 libpango-1.0-0 \
    libcairo2 \
    neovim fzf ripgrep btop haveged
rm -rf /var/lib/apt/lists/*

echo "[3/4] Installing bun..."
if ! command -v bun >/dev/null 2>&1; then
    curl -fsSL https://bun.sh/install | bash
    ln -sf /root/.bun/bin/bun /usr/local/bin/bun
fi

echo "[4/4] Verifying..."
echo "  bun:            $(bun --version 2>/dev/null || echo 'MISSING')"
echo "  chromium:       $(which chromium 2>/dev/null || echo 'MISSING')"
echo "  browser_skill:  $(ls /app/bin/browser_skill 2>/dev/null || echo 'MISSING')"
echo "  agent:          $(ls /app/agent/index.ts 2>/dev/null || echo 'MISSING')"
echo ""
echo "Guest setup complete."
