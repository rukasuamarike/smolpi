#!/usr/bin/env bash
set -euo pipefail

IMAGE_NAME="pi-agent-smol"
ARCH="${1:-amd64}"
FULL_TAG="latest-${ARCH}"
PACK_BIN="./pi-agent"
REG_PORT="5000"
REG_NAME="smol-registry"
REG_IMAGE="localhost:${REG_PORT}/${IMAGE_NAME}:${FULL_TAG}"

echo "[1/4] Building OCI image (${ARCH})..."
docker buildx build --platform "linux/${ARCH}" \
    --build-arg "TARGETARCH=${ARCH}" \
    -t "${IMAGE_NAME}:${FULL_TAG}" \
    --load .

echo "[2/4] Ensuring local registry is running..."
if ! docker inspect "${REG_NAME}" >/dev/null 2>&1; then
    docker run -d --name "${REG_NAME}" -p "${REG_PORT}:5000" --restart=always registry:2
fi

echo "[3/4] Pushing to local registry..."
docker tag "${IMAGE_NAME}:${FULL_TAG}" "${REG_IMAGE}"
docker push "${REG_IMAGE}"

echo "[4/4] Packing into Smolmachines MicroVM..."
smolvm pack create --image "${REG_IMAGE}" -o "${PACK_BIN}"

echo "Done. Packed binary: ${PACK_BIN}"
echo ""
echo "Run with:"
echo "  ${PACK_BIN} run --net -- /bin/bash"
