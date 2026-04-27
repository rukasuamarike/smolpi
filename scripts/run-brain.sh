#!/usr/bin/env bash
set -euo pipefail

PORT="${PORT:-8080}"
HOST="0.0.0.0"
CTX_SIZE="${CTX_SIZE:-4096}"
MODELS_DIR="./models"

# ── Locate llama-server ──────────────────────────────────────
SEARCH_PATHS=(
    "./llama.cpp/build/bin/llama-server"
    "./llama.cpp/llama-server"
    "$(command -v llama-server 2>/dev/null || true)"
    "/usr/local/bin/llama-server"
)

LLAMA_SERVER=""
for p in "${SEARCH_PATHS[@]}"; do
    if [[ -n "$p" && -x "$p" ]]; then
        LLAMA_SERVER="$p"
        break
    fi
done

if [[ -z "$LLAMA_SERVER" ]]; then
    echo "ERROR: llama-server not found."
    echo ""
    echo "Searched:"
    for p in "${SEARCH_PATHS[@]}"; do
        [[ -n "$p" ]] && echo "  - $p"
    done
    echo ""
    echo "Build it:"
    echo "  git clone https://github.com/ggerganov/llama.cpp.git"
    echo "  cd llama.cpp && cmake -B build && cmake --build build -j\$(nproc)"
    exit 1
fi

echo "Found: $LLAMA_SERVER"

# ── Select a GGUF model ─────────────────────────────────────
if [[ ! -d "$MODELS_DIR" ]]; then
    echo "ERROR: No $MODELS_DIR directory found."
    echo "Create it and place .gguf files inside:"
    echo "  mkdir -p $MODELS_DIR"
    exit 1
fi

mapfile -t MODELS < <(find "$MODELS_DIR" -maxdepth 1 -name '*.gguf' -type f | sort)

if [[ ${#MODELS[@]} -eq 0 ]]; then
    echo "ERROR: No .gguf files found in $MODELS_DIR/"
    echo ""
    echo "Download one, e.g.:"
    echo "  curl -L -o $MODELS_DIR/gemma-2-2b-Q4_K_M.gguf \\"
    echo '    "https://huggingface.co/bartowski/gemma-2-2b-it-GGUF/resolve/main/gemma-2-2b-it-Q4_K_M.gguf"'
    exit 1
fi

if [[ ${#MODELS[@]} -eq 1 ]]; then
    MODEL="${MODELS[0]}"
    echo "Using only available model: $(basename "$MODEL")"
else
    echo ""
    echo "Available models:"
    for i in "${!MODELS[@]}"; do
        size=$(du -h "${MODELS[$i]}" | cut -f1)
        echo "  [$((i+1))] $(basename "${MODELS[$i]}") ($size)"
    done
    echo ""
    read -rp "Select model [1-${#MODELS[@]}]: " choice
    if [[ ! "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#MODELS[@]} )); then
        echo "Invalid selection."
        exit 1
    fi
    MODEL="${MODELS[$((choice-1))]}"
fi

# ── GPU reminder ─────────────────────────────────────────────
echo ""
echo "────────────────────────────────────────────────────"
echo "  GPU ACCELERATION REMINDER"
echo ""
echo "  Add --n-gpu-layers N to offload layers to GPU:"
echo ""
echo "    NVIDIA : --n-gpu-layers 99  (requires CUDA build)"
echo "    Apple  : --n-gpu-layers 99  (Metal is auto-enabled)"
echo "    CPU    : omit the flag (default, slower)"
echo ""
echo "  Set GPU_LAYERS env var to add it automatically:"
echo "    GPU_LAYERS=99 ./scripts/run-brain.sh"
echo "────────────────────────────────────────────────────"
echo ""

# ── Build the command ────────────────────────────────────────
CMD=(
    "$LLAMA_SERVER"
    --host "$HOST"
    --port "$PORT"
    --model "$MODEL"
    --ctx-size "$CTX_SIZE"
)

if [[ -n "${GPU_LAYERS:-}" ]]; then
    CMD+=(--n-gpu-layers "$GPU_LAYERS")
    echo "GPU offload: $GPU_LAYERS layers"
fi

echo "Starting: ${CMD[*]}"
echo "Endpoint: http://${HOST}:${PORT}"
echo ""

exec "${CMD[@]}"
