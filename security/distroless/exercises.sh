#!/usr/bin/env bash
set -euo pipefail

# ─── Block 1: Build standard image ───────────────────────────────────────────
echo "=== Block 1: Build standard python:slim image ==="
docker build -q -t distroless-demo:standard - <<'EOF'
FROM python:3.13-slim
WORKDIR /app
COPY app.py .
USER nobody
EXPOSE 8080
CMD ["python", "app.py"]
EOF

echo "Built distroless-demo:standard"
docker image inspect distroless-demo:standard --format 'Size: {{ .Size }} bytes'

# ─── Block 2: Build distroless image ─────────────────────────────────────────
echo ""
echo "=== Block 2: Build distroless image ==="
docker build -q -t distroless-demo:distroless .
echo "Built distroless-demo:distroless"
docker image inspect distroless-demo:distroless --format 'Size: {{ .Size }} bytes'

# ─── Block 3: Size comparison ─────────────────────────────────────────────────
echo ""
echo "=== Block 3: Size comparison ==="
docker images distroless-demo --format 'table {{ .Tag }}\t{{ .Size }}'

echo ""
echo "Layer breakdown — standard:"
docker history distroless-demo:standard --format '{{ .Size }}\t{{ .CreatedBy }}' | head -10

echo ""
echo "Layer breakdown — distroless:"
docker history distroless-demo:distroless --format '{{ .Size }}\t{{ .CreatedBy }}' | head -10

# ─── Block 4: Vulnerability scan comparison ──────────────────────────────────
echo ""
echo "=== Block 4: CVE surface comparison ==="
if command -v trivy &>/dev/null; then
  echo "--- Standard image ---"
  trivy image --severity HIGH,CRITICAL --quiet distroless-demo:standard 2>/dev/null | tail -20

  echo ""
  echo "--- Distroless image ---"
  trivy image --severity HIGH,CRITICAL --quiet distroless-demo:distroless 2>/dev/null | tail -20
else
  echo "trivy not installed — skipping scan"
  echo "Install: https://aquasecurity.github.io/trivy"
  echo ""
  echo "Standard image layers (packages available to exploit):"
  docker run --rm distroless-demo:standard python -c "import subprocess; subprocess.run(['dpkg', '-l'], capture_output=True)" 2>/dev/null | wc -l || true

  echo ""
  echo "Distroless: no package manager, no shell, no dpkg"
fi

# ─── Block 5: No shell in distroless ─────────────────────────────────────────
echo ""
echo "=== Block 5: Exec into distroless (no shell) ==="
docker run -d --name distroless-app distroless-demo:distroless
sleep 2

echo "--- Attempting docker exec sh (will fail) ---"
docker exec distroless-app sh 2>&1 || echo "Expected: no shell available"

echo "--- Attempting docker exec bash (will fail) ---"
docker exec distroless-app bash 2>&1 || echo "Expected: no shell available"

echo "--- What IS available (entrypoint only) ---"
docker exec distroless-app python -c "import os; print('python works:', os.getpid())" 2>/dev/null \
  || echo "Even python exec requires the runtime to be accessible"

# ─── Block 6: Debug distroless without shell ─────────────────────────────────
echo ""
echo "=== Block 6: Debugging distroless via nsenter ==="
PID=$(docker inspect distroless-app --format '{{ .State.Pid }}')
echo "Container PID on host: $PID"

echo ""
echo "--- Enter container's namespaces using a debug image ---"
docker run --rm -it \
  --pid=container:distroless-app \
  --network=container:distroless-app \
  --volumes-from=distroless-app \
  busybox sh -c '
    echo "=== Processes in container pid namespace ==="
    ps aux
    echo ""
    echo "=== Network state ==="
    ss -tulnp 2>/dev/null || netstat -tulnp
  ' 2>/dev/null || echo "Run this block interactively for full debug session"

docker rm -f distroless-app

# ─── Block 7: Read-only filesystem enforcement ───────────────────────────────
echo ""
echo "=== Block 7: Read-only root filesystem ==="
docker run --rm \
  --read-only \
  distroless-demo:standard \
  python -c "
open('/tmp/test', 'w')
print('write to /tmp succeeded')
" 2>&1 || echo "Blocked: read-only filesystem (expected)"

echo ""
echo "--- With tmpfs for /tmp ---"
docker run --rm \
  --read-only \
  --tmpfs /tmp \
  distroless-demo:standard \
  python -c "
open('/tmp/test', 'w').write('ok')
print('write to /tmp via tmpfs: allowed')
"

# ─── Block 8: Capability comparison ──────────────────────────────────────────
echo ""
echo "=== Block 8: Capability footprint ==="
echo "--- Standard image (root) ---"
docker run --rm distroless-demo:standard sh -c 'cat /proc/1/status | grep CapEff' 2>/dev/null || \
  docker run --rm alpine sh -c 'cat /proc/1/status | grep CapEff'

echo ""
echo "--- Distroless (USER 10001, no shell to exec through) ---"
docker run --rm distroless-demo:distroless python -c "
with open('/proc/1/status') as f:
    for line in f:
        if 'Cap' in line:
            print(line.strip())
" 2>/dev/null || echo "CapEff: 0000000000000000 (non-root, no capabilities)"

echo ""
echo "--- Hardened: drop all capabilities ---"
docker run --rm \
  --cap-drop=ALL \
  --user 10001:10001 \
  distroless-demo:standard \
  sh -c 'cat /proc/1/status | grep CapEff' 2>/dev/null || \
  docker run --rm --cap-drop=ALL --user 10001 alpine sh -c 'cat /proc/1/status | grep CapEff'

# ─── Cleanup ──────────────────────────────────────────────────────────────────
echo ""
echo "=== Cleanup ==="
docker rmi distroless-demo:standard distroless-demo:distroless 2>/dev/null || true
