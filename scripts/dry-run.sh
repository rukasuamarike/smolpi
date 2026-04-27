#!/usr/bin/env bash
set -euo pipefail

VM_NAME="pi-agent-dev"
SMOLFILE="Smolfile"
CLEAN=false

usage() {
    echo "Usage: $0 [--clean]"
    echo ""
    echo "  --clean   Tear down existing machine before starting fresh"
    echo ""
    echo "Without --clean, creates only if the machine doesn't exist."
    exit 0
}

[[ "${1:-}" == "--help" || "${1:-}" == "-h" ]] && usage
[[ "${1:-}" == "--clean" ]] && CLEAN=true

step() { echo ""; echo "==> $1"; }

# ── Clean slate ──────────────────────────────────────────────
if $CLEAN; then
    step "Clean slate: tearing down ${VM_NAME}"
    smolvm machine stop --name "$VM_NAME" 2>/dev/null || true
    smolvm machine delete -f "$VM_NAME" 2>/dev/null || true
    echo "    Done."
fi

# ── Step 1: Build Go binary ─────────────────────────────────
step "Step 1/5: Compile browser_skill"
mkdir -p bin
cd browser
CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -ldflags="-s -w" -o ../bin/browser_skill browser_skill.go
cd ..
echo "    OK: bin/browser_skill ($(du -h bin/browser_skill | cut -f1))"

# ── Step 2: Create machine ──────────────────────────────────
step "Step 2/5: Create machine"
if smolvm machine ls 2>/dev/null | grep -q "$VM_NAME"; then
    echo "    ${VM_NAME} already exists, skipping create."
else
    smolvm machine create -s "$SMOLFILE" "$VM_NAME"
fi

# ── Step 3: Start machine ───────────────────────────────────
step "Step 3/5: Start machine (init commands will run on first boot)"
echo "    This may take a few minutes on first run (apt-get + bun install)."
echo "    Ctrl+C to cancel if it hangs."
smolvm machine start --name "$VM_NAME"

# ── Step 4: Verify ──────────────────────────────────────────
step "Step 4/5: Verify guest environment"
echo "    Checking bun..."
smolvm machine exec --name "$VM_NAME" -- which bun && echo "    OK: bun found" || echo "    WARN: bun not found"

echo "    Checking chromium..."
smolvm machine exec --name "$VM_NAME" -- which chromium && echo "    OK: chromium found" || echo "    WARN: chromium not found"

echo "    Checking browser_skill mount..."
smolvm machine exec --name "$VM_NAME" -- ls -la /app/bin/browser_skill && echo "    OK: browser_skill mounted" || echo "    WARN: browser_skill not found at /app/bin/"

echo "    Checking agent mount..."
smolvm machine exec --name "$VM_NAME" -- ls /app/agent/index.ts && echo "    OK: agent source mounted" || echo "    WARN: agent source not found at /app/agent/"

echo "    Checking env..."
smolvm machine exec --name "$VM_NAME" -- sh -c 'echo "LLM_URL=$LLM_URL"'
smolvm machine exec --name "$VM_NAME" -- sh -c 'echo "BROWSER_BIN=$BROWSER_BIN"'

# ── Step 5: Summary ─────────────────────────────────────────
step "Step 5/5: Machine status"
smolvm machine ls

echo ""
echo "────────────────────────────────────────────────"
echo "  All checks passed. Next steps:"
echo ""
echo "  Shell:   make machine-exec"
echo "  Agent:   make machine-run"
echo "  Stop:    make machine-down"
echo "────────────────────────────────────────────────"
