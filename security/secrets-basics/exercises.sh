#!/usr/bin/env bash
set -euo pipefail

# ─── Block 1: Bad pattern — env var secret ───────────────────────────────────
echo "=== Block 1: Secret in -e flag (visible in docker inspect) ==="
docker run -d --name bad-env -e API_KEY=supersecret alpine sleep 60

echo "--- docker inspect exposes it ---"
docker inspect bad-env --format '{{ range .Config.Env }}{{ println . }}{{ end }}' | grep API_KEY

echo "--- /proc/<pid>/environ exposes it too ---"
PID=$(docker inspect bad-env --format '{{ .State.Pid }}')
cat /proc/$PID/environ | tr '\0' '\n' | grep API_KEY 2>/dev/null || \
  docker exec bad-env sh -c 'cat /proc/1/environ | tr "\0" "\n" | grep API_KEY'

docker rm -f bad-env

# ─── Block 2: Bad pattern — secret baked into image via ENV ──────────────────
echo ""
echo "=== Block 2: Secret in Dockerfile ENV — permanently in image ==="
docker build -q -t bad-env-image - <<'EOF'
FROM alpine:3.20
ENV API_KEY=supersecret
CMD ["sh"]
EOF

echo "--- docker history reveals it ---"
docker history bad-env-image --format '{{ .CreatedBy }}' | grep -i api_key || \
  docker inspect bad-env-image --format '{{ range .Config.Env }}{{ println . }}{{ end }}' | grep API_KEY

docker rmi bad-env-image -f

# ─── Block 3: Bad pattern — COPY .env into image ─────────────────────────────
echo ""
echo "=== Block 3: COPY .env into image — secret in layer forever ==="
echo "API_KEY=supersecret" > /tmp/demo.env

docker build -q -t bad-copy-image - <<EOF
FROM alpine:3.20
COPY /tmp/demo.env /app/.env
RUN echo "removing env..."
RUN rm /app/.env
CMD ["sh"]
EOF

echo "--- Even after rm, the secret exists in an earlier layer ---"
echo "--- docker history shows the COPY layer ---"
docker history bad-copy-image --format '{{ .CreatedBy }}' | grep -i "COPY\|demo.env" || true

docker rmi bad-copy-image -f
rm /tmp/demo.env

# ─── Block 4: Better — mounted file secret ───────────────────────────────────
echo ""
echo "=== Block 4: Secret as a mounted file (not in image, not in env) ==="
echo "my-runtime-secret" > /tmp/api_key.txt

docker run --rm \
  -v /tmp/api_key.txt:/run/secrets/api_key:ro \
  alpine sh -c '
    echo "Secret value: $(cat /run/secrets/api_key)"
    echo "Visible in env: $(env | grep -i api || echo none)"
  '

rm /tmp/api_key.txt

# ─── Block 5: BuildKit secret mount — not in any layer ───────────────────────
echo ""
echo "=== Block 5: BuildKit --mount=type=secret ==="
echo "build-time-token-xyz" > /tmp/build_token.txt

DOCKER_BUILDKIT=1 docker build -q \
  --secret id=build_token,src=/tmp/build_token.txt \
  -t secrets-demo . 2>&1 | tail -5 || true

echo ""
echo "--- Verify secret does not appear in any layer ---"
docker history secrets-demo --no-trunc 2>/dev/null | grep -i "token\|secret\|password\|key" \
  && echo "WARNING: secret found in history" \
  || echo "Clean: no secrets in image history"

docker rmi secrets-demo -f 2>/dev/null || true
rm /tmp/build_token.txt

# ─── Block 6: Docker Compose secrets ─────────────────────────────────────────
echo ""
echo "=== Block 6: Docker Compose secrets ==="
mkdir -p secrets
echo "compose-secret-value" > secrets/api_key.txt

docker compose build -q
docker compose run --rm app python app.py

docker compose down
rm -rf secrets

# ─── Block 7: Scan image history for leaked secrets ──────────────────────────
echo ""
echo "=== Block 7: Audit image layers for potential secret leaks ==="
echo "Scanning python:3.13-slim layers for common secret patterns..."
docker history python:3.13-slim --no-trunc --format '{{ .CreatedBy }}' \
  | grep -iE "token|password|key|secret|credential" \
  && echo "WARNING: potential secret in base image history" \
  || echo "Clean: no obvious secrets in base image layers"

echo ""
echo "Pattern to add to CI pipeline:"
echo '  docker history --no-trunc <image> | grep -iE "token|password|key|secret"'

# ─── Block 8: Summary — what each pattern exposes ────────────────────────────
echo ""
echo "=== Block 8: Exposure comparison ==="
echo ""
echo "Pattern                     | docker inspect | docker history | /proc/environ | Layer"
echo "----------------------------|----------------|----------------|---------------|------"
echo "-e API_KEY=secret           | YES            | NO             | YES           | NO"
echo "ENV API_KEY=secret          | YES            | YES            | YES           | YES"
echo "COPY .env (then rm)         | NO             | YES            | NO            | YES"
echo "Mounted file (-v)           | NO             | NO             | NO            | NO"
echo "BuildKit --mount=type=secret| NO             | NO             | NO            | NO"
echo "Compose secrets             | NO             | NO             | NO            | NO"
