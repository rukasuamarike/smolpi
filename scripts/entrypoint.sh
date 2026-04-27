#!/bin/sh
# Seed entropy pool — fixes MicroVM/WSL2 boot hang on low entropy
if command -v haveged >/dev/null 2>&1; then
    haveged -w 1024 >/dev/null 2>&1 || true
fi

exec "$@"
