# ============================================================
# Stage 1: Go builder — compile browser_skill
# ============================================================
FROM golang:1.22-bookworm AS go-builder

ARG TARGETARCH=amd64

WORKDIR /build
COPY browser/ ./
RUN go mod tidy && \
    CGO_ENABLED=0 GOARCH=${TARGETARCH} go build -ldflags="-s -w" -o /browser_skill browser_skill.go

# ============================================================
# Stage 2: Final image — Bun + Neovim + Chromium (headless)
# ============================================================
FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

# Core packages + headless Chromium deps (no X11/GUI bloat)
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl unzip git \
    neovim fzf ripgrep btop \
    chromium \
    libnss3 libatk1.0-0 libatk-bridge2.0-0 libcups2 \
    libdrm2 libxkbcommon0 libxcomposite1 libxdamage1 \
    libxrandr2 libgbm1 libasound2 libpango-1.0-0 \
    libcairo2 \
    && rm -rf /var/lib/apt/lists/*

# Install Bun
RUN curl -fsSL https://bun.sh/install | bash
ENV PATH="/root/.bun/bin:${PATH}"

# Install zoxide
RUN curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | bash
ENV PATH="/root/.local/bin:${PATH}"

# Copy Go browser skill binary
COPY --from=go-builder /browser_skill /usr/local/bin/browser_skill

# Copy agent source
WORKDIR /app
COPY agent/ ./agent/

# Shell config for agent-friendly terminal
RUN echo 'eval "$(zoxide init bash)"' >> /root/.bashrc && \
    echo 'export CHROME_BIN=/usr/bin/chromium' >> /root/.bashrc && \
    echo 'alias ll="ls -la"' >> /root/.bashrc

ENV CHROME_BIN=/usr/bin/chromium
ENV BROWSER_BIN=/usr/local/bin/browser_skill

CMD ["bun", "run", "agent/index.ts"]
