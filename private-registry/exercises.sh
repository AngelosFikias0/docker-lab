#!/usr/bin/env bash
set -euo pipefail

# ─── Block 1: Start the registry stack ───────────────────────────────────────
echo "=== Block 1: Start registry + UI ==="
docker compose up -d
sleep 2
docker compose ps

echo ""
echo "Registry API: http://localhost:5000"
echo "Registry UI:  http://localhost:8080"

# ─── Block 2: Verify the registry speaks the OCI Distribution API ─────────────
echo ""
echo "=== Block 2: v2 API ping ==="
curl -s http://localhost:5000/v2/ | python3 -m json.tool
# expects: {}  with HTTP 200 — confirms Distribution Spec compliance

echo ""
echo "Catalog (empty at start):"
curl -s http://localhost:5000/v2/_catalog | python3 -m json.tool

# ─── Block 3: Push an image ───────────────────────────────────────────────────
echo ""
echo "=== Block 3: Tag and push ==="
docker pull alpine:3.20
docker tag alpine:3.20 localhost:5000/alpine:3.20
docker push localhost:5000/alpine:3.20

echo ""
echo "Catalog after push:"
curl -s http://localhost:5000/v2/_catalog | python3 -m json.tool

echo ""
echo "Tags for alpine:"
curl -s http://localhost:5000/v2/alpine/tags/list | python3 -m json.tool

# ─── Block 4: Pull it back ────────────────────────────────────────────────────
echo ""
echo "=== Block 4: Pull from local registry ==="
docker rmi localhost:5000/alpine:3.20
docker pull localhost:5000/alpine:3.20
docker images localhost:5000/alpine

# ─── Block 5: Inspect the manifest via the v2 API ────────────────────────────
echo ""
echo "=== Block 5: Fetch manifest ==="
curl -s \
  -H "Accept: application/vnd.docker.distribution.manifest.v2+json" \
  http://localhost:5000/v2/alpine/manifests/3.20 \
  | python3 -m json.tool
# schemaVersion, mediaType, config digest, layer digests

# ─── Block 6: Push a local build ─────────────────────────────────────────────
echo ""
echo "=== Block 6: Build and push a local image ==="
docker build \
  -t localhost:5000/lab-app:latest \
  ../../basics/images-build

docker push localhost:5000/lab-app:latest

echo ""
echo "Catalog now:"
curl -s http://localhost:5000/v2/_catalog | python3 -m json.tool

# ─── Block 7: Inspect storage on disk ────────────────────────────────────────
echo ""
echo "=== Block 7: What's stored in the volume ==="
docker run --rm \
  -v private-registry_registry-data:/data \
  alpine find /data/docker/registry/v2/repositories -type d | sort

# ─── Block 8: Delete an image via the API ────────────────────────────────────
echo ""
echo "=== Block 8: Delete image via API ==="
DIGEST=$(curl -sI \
  -H "Accept: application/vnd.docker.distribution.manifest.v2+json" \
  http://localhost:5000/v2/alpine/manifests/3.20 \
  | grep -i docker-content-digest | tr -d '\r' | awk '{print $2}')

echo "Digest: $DIGEST"

curl -s -X DELETE \
  "http://localhost:5000/v2/alpine/manifests/${DIGEST}"

echo "Tags after delete:"
curl -s http://localhost:5000/v2/alpine/tags/list | python3 -m json.tool

# ─── Block 9: Pull-through cache ─────────────────────────────────────────────
echo ""
echo "=== Block 9: Pull-through cache ==="
echo "Restarting registry with Docker Hub as upstream proxy..."

docker compose down
docker compose run --rm -e REGISTRY_PROXY_REMOTEURL=https://registry-1.docker.io \
  -d --service-ports registry

sleep 2

echo "Pulling nginx via the cache:"
docker pull localhost:5000/library/nginx:alpine

echo ""
echo "Catalog — nginx layers now cached locally:"
curl -s http://localhost:5000/v2/_catalog | python3 -m json.tool

# ─── Block 10: Tear down ─────────────────────────────────────────────────────
echo ""
echo "=== Block 10: Tear down ==="
docker compose down -v
echo "Done."
