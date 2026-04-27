# Host Setup — pi-agent-smol

Everything needed to build and run this project on a fresh Ubuntu/WSL2 host.

Tested on: Ubuntu 24.04 (WSL2), x86_64.

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

### Build from source

```bash
sudo apt-get install -y build-essential cmake

git clone https://github.com/ggerganov/llama.cpp.git
cd llama.cpp
cmake -B build
cmake --build build --config Release -j$(nproc)

# Binary is at build/bin/llama-server
sudo cp build/bin/llama-server /usr/local/bin/
```

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

Add `--n-gpu-layers 99` if you have NVIDIA (CUDA build) or Apple Silicon (Metal auto-enabled).

### Verify from host

```bash
curl http://localhost:8080/health
```

---

## Quick validation

After installing everything:

```bash
cd pi-agent-smol

# Build the image (uses Docker, no local Go/Bun needed)
make build

# Run the 3 dry-run tests
make test

# Pack and test guest-to-host networking
# (requires llama-server running on 0.0.0.0:8080)
make pack
make test-smol-net
```
