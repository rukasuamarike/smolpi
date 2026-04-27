# 🥣 The Pi-Agent Soup

> An experimental, hyper-minimal OCI MicroVM stack for AI agents.
> Created as a fun little experiment by Saichi.

**Status:** 📡 Eyes and Brain are linked.

---

## 🧪 The "Why"

Most AI agents are bloated, slow, and live in giant Docker containers that
take 10 seconds to boot. This project is the antidote. We've combined the
speed of Go, the runtime efficiency of Bun, and the isolation of MicroVMs
to make an agent that feels like it's living in the future.

Stretch goal: run the whole soup — agent **and** brain — on an iPhone.

---

## 🏗️ The Stack (The Ingredients)

### 📦 The "Armor" (Isolation)
- **Smolmachines (`smolvm`)** — no Docker daemon at runtime. The agent lives in
  a hardware-isolated MicroVM that boots in milliseconds.
- **OCI-compliant** — built as a Debian Bookworm Slim OCI image, executed as a
  high-performance MicroVM via `libkrun`.

### 🧠 The "Brain" (LLM)
- **`llama.cpp`** running **Gemma 4 E4B** (~2.7 GB Q4_K_M) locally on the host
  GPU. Vendored as a submodule so the build is reproducible across CUDA / Metal
  / Vulkan / HIP backends.
- **Mirrored networking bridge** — the smolvm guest reaches the host's
  `llama-server` on plain `localhost:8080` thanks to WSL2 mirrored networking
  (legacy `172.16.0.1` hardcoding got retired — it was fragile and changed
  between Windows updates).

### 👁️ The "Eyes" (Web)
- **Go + Chromedp** — a custom-built browser skill compiled to a single static
  binary.
- **Semantic Markdown** — we don't send messy HTML to the LLM. `go-readability`
  + `html-to-markdown` turn the open web into a clean, token-efficient document.
- **No-CDP mode** — engineered to work with libkrun networking by using
  `chromium --dump-dom` to bypass WebSocket-tunnel limitations.

### 🛠️ The "Hands" (Tooling)
- **Bun runtime** — for lightning-fast TypeScript execution.
- **Power tools** baked into the image: `ripgrep`, `fd`, `bat`, `fzf`, `zoxide`,
  `btop`, `neovim`, `jq`, `sed`, plus `chromium` headless.
- **Modular Capability Registry** — a self-describing registry
  (`agent/capabilities.ts`) that probes the system at startup and **autogenerates
  the system prompt** from the tools that actually resolved on `$PATH`. Add a
  capability, the prompt grows. Remove a binary, it quietly disappears.

---

## 🚀 Getting Started

> Setup depends on your hardware (CUDA vs. Metal vs. CPU-only, WSL2 vs. native
> Linux vs. Apple Silicon). All of that is documented in
> [`HOST_SETUP.md`](./HOST_SETUP.md) — read it once, then come back here.

Once your host has Docker, `smolvm`, and `llama-server` installed:

```bash
# 1. Fire up the Brain (uses GPU offload if your llama.cpp build supports it)
./scripts/run-brain.sh

# 2. Boot the Machine (first run creates the VM from the Smolfile)
make machine-up
make machine-init        # one-off: install guest packages
make machine-snapshot    # cache the configured VM for instant future boots

# 3. Verify the guest can reach the brain
make test-brain

# 4. Let it cook
make machine-run
```

Future boots are just `make machine-up && make machine-run` — the snapshot
brings the VM up in well under a second.

---

## ⚠️ Known Quirks

- **The "ghost" network** — if you `cat /proc/net/tcp` inside the guest, it's
  empty. That's not a bug; it's **Transparent Socket Impersonation (TSI)** —
  libkrun proxies sockets at the syscall layer, so connections never appear in
  the guest kernel's tables.
- **Memory pressure** — running a 4B-param model and a headless Chromium on a
  single host is like fitting a V8 engine in a lawnmower. It's loud, it's fast,
  and it might get warm. The Smolfile caps the guest at 4 GiB to leave the
  host's GPU and `llama-server` enough headroom.
- **Apple Silicon shortcut** — Metal is auto-enabled at build time, so the
  default CPU build instructions in `HOST_SETUP.md` already produce a
  Metal-accelerated `llama-server` on M-series Macs.

---

## 🛣️ Roadmap

- [ ] **iPhone deployment** — the whole point. Gemma 4 E4B Q2_K (~1.5 GB) fits
      iPhone 13/14; Q4_K_M fits 15 Pro+.
- [ ] **NPU offload** on Apple Silicon (CoreML / ANE path for the brain).
- [ ] **Multi-agent** — let two soups talk to each other over a shared bridge.

---

## 👨‍🔬 Author

**Saichi** — experiments in making agents smol, fast, and dangerous.
