#!/usr/bin/env bash
set -euo pipefail

# Multi-arch builds with Buildx.
# Requires: docker buildx, QEMU (installed automatically by setup step below).
# To push to a real registry, set REGISTRY and log in first.

REGISTRY="${REGISTRY:-localhost:5000}"
IMAGE="${REGISTRY}/lab-multistage"

# ─── Block 1: Check and set up Buildx ────────────────────────────────────────
echo "=== Block 1: Buildx setup ==="
docker buildx version
docker buildx ls

echo ""
echo "Creating a multi-platform builder backed by BuildKit..."
docker buildx create --name multiarch-builder --driver docker-container --use || \
  docker buildx use multiarch-builder

docker buildx inspect --bootstrap
# Look for: Platforms: linux/amd64, linux/arm64, linux/arm/v7 ...
# QEMU binfmt_misc handlers are what enable cross-compilation on the runner

# ─── Block 2: Install QEMU emulators ─────────────────────────────────────────
echo ""
echo "=== Block 2: QEMU binfmt registration ==="
docker run --rm --privileged tonistiigi/binfmt --install all
# Registers QEMU handlers in the kernel for arm64, arm/v7, s390x, etc.
# Without this, building for a foreign arch fails at the first RUN instruction

cat /proc/sys/fs/binfmt_misc/qemu-aarch64 2>/dev/null | head -5 || \
  echo "(binfmt entry not shown — may need kernel support)"

# ─── Block 3: Build for amd64 only (baseline) ────────────────────────────────
echo ""
echo "=== Block 3: Single-arch build (baseline) ==="
time docker buildx build \
  --platform linux/amd64 \
  --tag "${IMAGE}:amd64-only" \
  --load \
  .

docker images "${IMAGE}:amd64-only"

# ─── Block 4: Build for amd64 + arm64 ────────────────────────────────────────
echo ""
echo "=== Block 4: Multi-arch build (amd64 + arm64) ==="
# --load only works for single-platform. Multi-platform output must be pushed
# or written to a local OCI tarball.
time docker buildx build \
  --platform linux/amd64,linux/arm64 \
  --tag "${IMAGE}:multi" \
  --output "type=oci,dest=/tmp/lab-multistage-multi.tar" \
  .

ls -lh /tmp/lab-multistage-multi.tar
echo "OCI layout tarball contains both platform manifests"

# ─── Block 5: Inspect the manifest list ──────────────────────────────────────
echo ""
echo "=== Block 5: Inspect OCI tarball contents ==="
tar -tf /tmp/lab-multistage-multi.tar | head -20

echo ""
echo "index.json (the manifest list):"
tar -xOf /tmp/lab-multistage-multi.tar index.json | python3 -m json.tool
# mediaType: application/vnd.oci.image.index.v1+json
# manifests[]: one entry per platform, each with platform.os + platform.architecture

# ─── Block 6: Push multi-arch image to local registry ────────────────────────
echo ""
echo "=== Block 6: Push to local registry ==="
echo "Starting local registry on :5000 if not already running..."
docker run -d --name temp-registry -p 5000:5000 registry:2 2>/dev/null || true
sleep 1

docker buildx build \
  --platform linux/amd64,linux/arm64 \
  --tag "${IMAGE}:latest" \
  --push \
  .

echo ""
echo "Verifying manifest list in registry:"
docker buildx imagetools inspect "${IMAGE}:latest"
# Shows: Name, MediaType (image index), Digest, then per-platform entries

# ─── Block 7: Pull by platform digest ────────────────────────────────────────
echo ""
echo "=== Block 7: Pull a specific platform ==="
AMD64_DIGEST=$(docker buildx imagetools inspect "${IMAGE}:latest" --raw \
  | python3 -c "
import sys, json
data = json.load(sys.stdin)
for m in data['manifests']:
    if m['platform']['architecture'] == 'amd64':
        print(m['digest'])
        break
")

echo "amd64 digest: ${AMD64_DIGEST}"
docker pull --platform linux/amd64 "${IMAGE}@${AMD64_DIGEST}"

# ─── Block 8: Compare image sizes per arch ───────────────────────────────────
echo ""
echo "=== Block 8: Layer size comparison ==="
docker buildx imagetools inspect "${IMAGE}:latest" --raw \
  | python3 -c "
import sys, json
data = json.load(sys.stdin)
for m in data.get('manifests', []):
    arch = m['platform']['architecture']
    size = m.get('size', 0)
    print(f'{arch}: digest={m[\"digest\"][:19]}... size={size} bytes')
"
# arm64 and amd64 layer sizes differ due to compiled Python extensions

# ─── Block 9: Simulate CI — what GitHub Actions does ─────────────────────────
echo ""
echo "=== Block 9: What the CI matrix does ==="
cat <<'YAML'
# In ci.yml this becomes:
- name: Set up Docker Buildx
  uses: docker/setup-buildx-action@v3   # creates the builder, installs QEMU

- name: Build and push
  uses: docker/build-push-action@v6
  with:
    platforms: linux/amd64,linux/arm64  # the key addition
    push: true
    tags: ghcr.io/owner/image:latest
    cache-from: type=gha,scope=my-image
    cache-to: type=gha,scope=my-image,mode=max
YAML

# ─── Block 10: Tear down ─────────────────────────────────────────────────────
echo ""
echo "=== Block 10: Cleanup ==="
docker stop temp-registry 2>/dev/null && docker rm temp-registry 2>/dev/null || true
docker buildx rm multiarch-builder 2>/dev/null || true
rm -f /tmp/lab-multistage-multi.tar
echo "Done."
