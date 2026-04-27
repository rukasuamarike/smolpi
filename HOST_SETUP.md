# Host Setup — pi-agent-smol

Everything needed to build and run this project on a fresh host.

Tested on:
- Ubuntu 24.04 (WSL2), x86_64 — primary dev target
- macOS 14+ on Apple Silicon (M1–M4) — for `llama-server` only; smolvm guests run on Linux hosts

Linux/WSL2 sections cover Docker, smolvm, libkrun, etc. Mac users primarily need section 5 (llama-server) — smolvm itself currently targets Linux.

---

## 1. Docker & Buildx

Docker Engine with buildx is required for multi-arch OCI image builds and the local registry bridge.

```bash
# Install Docker Engine (not Docker Desktop)
sudo apt-get update
sudo apt-get install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
  https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin

# Run without sudo
sudo usermod -aG docker $USER
newgrp docker

# Verify
docker buildx version
```

### QEMU for ARM64 cross-compilation

Required for `make build ARCH=arm64` on an x86_64 host:

```bash
docker run --rm --privileged multiarch/qemu-user-static --reset -p yes

# Verify
docker buildx build --platform linux/arm64 -t test-arm64 - <<< 'FROM alpine' --load
```

---

## 2. Go 1.22+

Only needed if you want to run `go mod tidy` or build `browser_skill` outside Docker. The Dockerfile handles Go compilation internally.

```bash
GO_VERSION=1.22.5
curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz" | sudo tar -C /usr/local -xz
echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.bashrc
source ~/.bashrc

# Verify
go version
```

---

## 3. Bun

Only needed for running the agent locally outside Docker/smolvm.

```bash
curl -fsSL https://bun.sh/install | bash
source ~/.bashrc

# Verify
bun --version
```

---

## 4. smolvm CLI

The MicroVM runtime. Packs OCI images into self-contained executables with sub-second boot.

```bash
# Install (check https://smolmachines.com for latest instructions)
curl -fsSL https://smolmachines.com/install.sh | bash

# Verify
smolvm --version   # should be v0.5.x+
```

### libkrun (MicroVM backend)

smolvm bundles `libkrun` and `libkrunfw` in `~/.smolvm/lib/`. The `smolvm` wrapper script sets `LD_LIBRARY_PATH` so it finds them automatically. However, **packed binaries** (e.g. `./pi-agent`) do not — they link against the system library path.

Install the bundled libs system-wide:

```bash
# Copy from smolvm's bundled libs
sudo cp ~/.smolvm/lib/libkrun.so /usr/local/lib/libkrun.so.1.9.1
sudo cp ~/.smolvm/lib/libkrunfw.so.5.3.0 /usr/local/lib/libkrunfw.so.5.3.0

# Create symlinks
sudo ln -sf /usr/local/lib/libkrun.so.1.9.1 /usr/local/lib/libkrun.so.1
sudo ln -sf /usr/local/lib/libkrun.so.1.9.1 /usr/local/lib/libkrun.so
sudo ln -sf /usr/local/lib/libkrunfw.so.5.3.0 /usr/local/lib/libkrunfw.so.5
sudo ln -sf /usr/local/lib/libkrunfw.so.5.3.0 /usr/local/lib/libkrunfw.so

# Update linker cache
sudo ldconfig

# Verify
ldconfig -p | grep libkrun
```

#### Troubleshooting: `libkrun.so.1: cannot open shared object file`

This error means the packed binary can't find libkrun in the system path.

**Quick fix** (temporary, current shell only):

```bash
export LD_LIBRARY_PATH="$HOME/.smolvm/lib:$LD_LIBRARY_PATH"
./pi-agent --help
```

**Permanent fix** (recommended):

Run the `sudo cp`, `sudo ln -sf`, and `sudo ldconfig` commands above. Verify with:

```bash
./pi-agent --help   # should print usage, no library errors
```

---

## 5. llama-server (llama.cpp)

The local LLM backend. Must listen on `0.0.0.0` so the smolvm guest can reach it via the host gateway (`172.16.0.1`).

### Get the source

`llama.cpp` is vendored as a git submodule. If you cloned this repo without `--recurse-submodules`:

```bash
git submodule update --init --recursive
```

Otherwise, clone it standalone:

```bash
git clone https://github.com/ggerganov/llama.cpp.git
```

### Build (CPU-only — fastest to set up)

```bash
sudo apt-get install -y build-essential cmake
cd llama.cpp
cmake -B build
cmake --build build --config Release -j$(nproc)

# Binary is at build/bin/llama-server
sudo cp build/bin/llama-server /usr/local/bin/
```

### Build with GPU acceleration (CUDA / Metal / Vulkan / HIP)

> **Apple Silicon shortcut**: Metal is auto-enabled on macOS by default. The CPU-only build instructions above already produce a Metal-accelerated `llama-server` on M-series Macs. Skip ahead to "Apple Silicon (Metal)" for prereqs and verification.

On Linux/WSL2 the default build is **CPU-only**. Without a GPU backend, `--n-gpu-layers` is silently ignored — the model loads to host RAM and runs on CPU. To verify any build's backends:

```bash
./build/bin/llama-server --list-devices
# CPU-only build shows just "CPU"
# CUDA build shows e.g. "CUDA0 - NVIDIA GeForce RTX 4090 (...)"
# Metal build shows e.g. "Metal - Apple M4 Pro"
```

#### Apple Silicon (Metal) — macOS

Apple Silicon Macs (M1 / M2 / M3 / M4) get GPU offload "for free" — llama.cpp detects Metal at build time and enables it unless explicitly disabled.

> **Terminology**: llama.cpp uses **Metal** directly (low-level GPU API), not **MPS** (Metal Performance Shaders, which is the higher-level PyTorch/MLX layer). When llama.cpp says "GPU offload to Metal" that's the right thing — you do not need MPS or MLX installed.

Prereqs:

```bash
# Xcode Command Line Tools (provides clang, make, etc.)
xcode-select --install

# Homebrew (if not already installed)
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# cmake
brew install cmake
```

Build (Metal auto-enabled — no flag needed):

```bash
cd llama.cpp
cmake -B build
cmake --build build --config Release -j$(sysctl -n hw.ncpu)

# Install
sudo cp build/bin/llama-server /usr/local/bin/

# Verify Metal is present
llama-server --list-devices
# Should show e.g.:
#   Metal - Apple M4 Pro (54 GB)
```

To **disable** Metal (rare — debugging, comparing CPU perf):

```bash
cmake -B build -DGGML_METAL=OFF
```

Run with full GPU offload — Apple Silicon's unified memory means you can offload all layers as long as the model fits in your total RAM:

```bash
GPU_LAYERS=99 ./scripts/run-brain.sh
```

The MacBook Pro M4 (24 GB+) handles Gemma 4 E4B Q4_K_M (~2.7 GB) with `--n-gpu-layers 99` instantly — first token in well under a second.

#### NVIDIA (CUDA) — WSL2 prerequisites

CUDA in WSL2 requires:
1. Recent NVIDIA driver on **Windows** (not in WSL — WSL inherits it)
2. CUDA toolkit installed in **WSL** (not Windows)

Verify:

```bash
nvidia-smi                    # should show GPU + driver (works inside WSL)
nvcc --version                # CUDA toolkit version
```

If `nvcc` is missing, install the CUDA toolkit for WSL-Ubuntu:
<https://developer.nvidia.com/cuda-downloads> → Linux → WSL-Ubuntu

#### Rebuild with the right backend

```bash
cd llama.cpp
rm -rf build

# Pick ONE of:
cmake -B build -DGGML_CUDA=ON       # NVIDIA
cmake -B build -DGGML_HIP=ON        # AMD
cmake -B build -DGGML_VULKAN=ON     # Vulkan (cross-vendor)
cmake -B build -DGGML_METAL=ON      # Apple Silicon (auto on macOS)

cmake --build build --config Release -j$(nproc)
sudo cp build/bin/llama-server /usr/local/bin/

# Verify the backend is present
llama-server --list-devices
```

`scripts/run-brain.sh` runs `--list-devices` automatically and refuses to pass `--n-gpu-layers` unless a GPU backend is detected — so you'll see a clear warning if a CPU-only build is still in place.

### Download a model

```bash
# Gemma 4 E4B (4-bit, ~2.7GB) — fits iPhone 13+ and MacBook Pro M4
mkdir -p ~/models

# Q4_K_M — best balance of quality and size for Apple Silicon / iPhone
curl -L -o ~/models/gemma-4-E4B-it-Q4_K_M.gguf \
  "https://huggingface.co/unsloth/gemma-4-E4B-it-GGUF/resolve/main/gemma-4-E4B-it-Q4_K_M.gguf"

# Q2_K — smaller (~1.5GB), better for iPhone 13/14 with tighter RAM
curl -L -o ~/models/gemma-4-E4B-it-Q2_K.gguf \
  "https://huggingface.co/unsloth/gemma-4-E4B-it-GGUF/resolve/main/gemma-4-E4B-it-Q2_K.gguf"
```

**Recommended quants by device:**

```
┌────────────────┬────────┬────────┬──────────────────────────────────────────┐
│     Device     │ Quant  │ ~Size  │                  Notes                   │
├────────────────┼────────┼────────┼──────────────────────────────────────────┤
│ MacBook Pro M4 │ Q4_K_M │ ~2.7GB │ Full speed via Metal, plenty of headroom │
├────────────────┼────────┼────────┼──────────────────────────────────────────┤
│ iPhone 15 Pro+ │ Q4_K_M │ ~2.7GB │ 8GB RAM, fits comfortably                │
├────────────────┼────────┼────────┼──────────────────────────────────────────┤
│ iPhone 13/14   │ Q2_K   │ ~1.5GB │ 4-6GB RAM, tighter margins               │
└────────────────┴────────┴────────┴──────────────────────────────────────────┘
```

### Run

```bash
# From the llama.cpp build directory:
./llama-server \
  -m ~/models/gemma-4-E4B-it-Q4_K_M.gguf \
  --host 0.0.0.0 \
  --port 8080 \
  --ctx-size 4096

# Or if installed to PATH:
llama-server \
  -m ~/models/gemma-4-E4B-it-Q4_K_M.gguf \
  --host 0.0.0.0 \
  --port 8080 \
  --ctx-size 4096
```

`--host 0.0.0.0` is **mandatory**. Without it, the server binds to `127.0.0.1` and the smolvm guest cannot connect.

Add `--n-gpu-layers 99` if you have a GPU build (see "Build with GPU acceleration" above). Or just use `GPU_LAYERS=99 ./scripts/run-brain.sh` — it auto-detects the backend.

### Verify from host

```bash
curl http://localhost:8080/health
```

---

## 6. WSL2 Mirrored Networking (REQUIRED for guest → host LLM)

By default, WSL2 puts your distro behind a NAT bridge. The smolvm guest sits behind a second NAT layer, so reaching `llama-server` on the WSL2 host through `localhost` does not work without configuration. The legacy workaround was hardcoding the host gateway (`172.16.0.1`), which is fragile and changes between Windows updates.

**Mirrored networking** is the supported fix. It makes the WSL2 host share the Windows network stack so `localhost` resolves the same from the host, the guest, and the Windows side.

### Enable

On Windows, open `%USERPROFILE%` (paste into File Explorer's address bar) and create or edit `.wslconfig`:

```ini
[wsl2]
networkingMode=mirrored
```

Then restart WSL from PowerShell (Admin):

```powershell
wsl --shutdown
```

Re-open your WSL terminal. Verify mirrored mode:

```bash
ip addr show eth0 | grep inet
# In mirrored mode, you'll see Windows-side interfaces, not 172.x.x.x
```

### Verify the agent can reach the LLM

With `llama-server` running on the host:

```bash
make machine-up
make test-brain
```

Expected output:
```
── LLM Connection Test (port 8080, timeout 2000ms) ──

  localhost              127.0.0.1        PASS (200)

PASS: LLM is reachable.
```

### Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `localhost: TIMEOUT` | Mirrored mode not active | Re-check `.wslconfig`, run `wsl --shutdown`, re-open terminal |
| `localhost: REFUSED` | llama-server not running | Start with `--host 0.0.0.0 --port 8080` |
| Test hangs forever | Old `172.16.0.1` probe | Pull latest — that probe was removed |
| `localhost: PASS` but agent fails | Wrong endpoint path | Agent appends `/v1/chat/completions` automatically; only set `LLM_URL` to base URL |

Even with mirrored networking, **always start `llama-server` with `--host 0.0.0.0`**. Binding to `127.0.0.1` only is fragile and breaks if mirroring is later disabled.

---

## Quick validation

After installing everything:

```bash
cd pi-agent-smol

# Smolfile-based dev workflow (recommended):
make machine-up        # Boot the dev VM (uses snapshot if available)
make machine-init      # First-time package install (one-off, then snapshot)
make machine-snapshot  # Cache the configured VM for fast future boots
make test-brain        # Verify guest → host LLM connection
make machine-run       # Start the agent

# OR full Docker pipeline:
make build             # Build the OCI image
make test              # Dry-run tests (chromium, go binary, tar)
make pack              # Pack into a self-contained smolvm executable
make test-smol-net     # End-to-end network test
```
