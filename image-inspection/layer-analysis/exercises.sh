#!/usr/bin/env bash
# layer-analysis/exercises.sh
# Run blocks individually. Each section is self-contained.
# Not meant to be executed top-to-bottom as a pipeline.

# ---------------------------------------------------------------------------
# 1. LAYER HISTORY - size delta per instruction
# Zero-size rows are config-only (ENV, WORKDIR, USER, CMD, etc.)
# ---------------------------------------------------------------------------
docker image history nginx:alpine \
  --format "table {{.CreatedBy}}\t{{.Size}}"

# ---------------------------------------------------------------------------
# 2. SPOT A BAD LAYER PATTERN
# Look for RUN instructions that add bytes followed by a separate RUN that
# removes them. The removal is in a new layer - the bytes are already committed.
# ---------------------------------------------------------------------------
docker pull python:3.13-slim

docker image history python:3.13-slim \
  --format "table {{.CreatedBy}}\t{{.Size}}" | head -20

# ---------------------------------------------------------------------------
# 3. INSPECT: TARGETED FIELD EXTRACTION
# Raw `docker image inspect` dumps 300+ lines. Use --format to extract fields.
# ---------------------------------------------------------------------------
docker image inspect nginx:alpine --format '{{ .Config.Entrypoint }}'
docker image inspect nginx:alpine --format '{{ .Config.Cmd }}'
docker image inspect nginx:alpine --format '{{ .Config.Env }}'
docker image inspect nginx:alpine --format '{{ .Config.ExposedPorts }}'
docker image inspect nginx:alpine --format '{{ .Config.User }}'
docker image inspect nginx:alpine --format '{{ .Architecture }}'
docker image inspect nginx:alpine --format '{{ len .RootFS.Layers }}'

echo "nginx:alpine layers:      $(docker image inspect nginx:alpine --format '{{ len .RootFS.Layers }}')"
echo "python:3.13-slim layers:  $(docker image inspect python:3.13-slim --format '{{ len .RootFS.Layers }}')"

# ---------------------------------------------------------------------------
# 4. SIZE COMPARISON: base image variants
# ---------------------------------------------------------------------------
docker pull python:3.13
docker pull python:3.13-alpine

docker image ls python \
  --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}"

# ---------------------------------------------------------------------------
# 5. DOCKER SAVE: export and read the tar structure
# ---------------------------------------------------------------------------
WORKDIR=$(mktemp -d)
docker save nginx:alpine -o "$WORKDIR/nginx-alpine.tar"

echo "Tar contents:"
tar tf "$WORKDIR/nginx-alpine.tar"

echo ""
echo "manifest.json:"
tar xf "$WORKDIR/nginx-alpine.tar" manifest.json -O | python3 -m json.tool

# ---------------------------------------------------------------------------
# 6. READ KEY FIELDS FROM THE IMAGE CONFIG
# diff_ids = uncompressed layer SHA256s (won't match manifest digests)
# ---------------------------------------------------------------------------
CONFIG=$(tar xf "$WORKDIR/nginx-alpine.tar" manifest.json -O \
  | python3 -c "import sys,json; print(json.load(sys.stdin)[0]['Config'])")

echo "Config: $CONFIG"

# Extract only the fields that matter
tar xf "$WORKDIR/nginx-alpine.tar" "$CONFIG" -O | python3 -c "
import sys, json
c = json.load(sys.stdin)
cfg = c.get('config', {})
print('Entrypoint:', cfg.get('Entrypoint'))
print('Cmd:        ', cfg.get('Cmd'))
print('Env:        ', cfg.get('Env'))
print('User:       ', cfg.get('User'))
print('WorkingDir: ', cfg.get('WorkingDir'))
print('Layers:     ', len(c.get('rootfs', {}).get('diff_ids', [])))
"

# ---------------------------------------------------------------------------
# 7. LOOK INSIDE A LAYER
# Each layer.tar is the filesystem diff for that layer.
# ---------------------------------------------------------------------------
FIRST_LAYER=$(tar tf "$WORKDIR/nginx-alpine.tar" | grep 'layer.tar' | head -1)

echo "Files in first layer ($FIRST_LAYER):"
tar xf "$WORKDIR/nginx-alpine.tar" "$FIRST_LAYER" -O | tar tf - | head -30

# ---------------------------------------------------------------------------
# 8. CLEANUP
# ---------------------------------------------------------------------------
rm -rf "$WORKDIR"

# docker rmi python:3.13 python:3.13-slim python:3.13-alpine nginx:alpine
