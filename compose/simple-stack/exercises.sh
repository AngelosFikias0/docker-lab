#!/usr/bin/env bash
set -euo pipefail

# ─── Block 1: Validate the compose file ──────────────────────────────────────
echo "=== Block 1: Validate and inspect compose config ==="
docker compose config
# Prints the merged, resolved compose file. Catches syntax errors and variable substitution.

# ─── Block 2: Build and start ────────────────────────────────────────────────
echo ""
echo "=== Block 2: Build image and start stack ==="
docker compose build
docker compose up -d
docker compose ps

# ─── Block 3: Service DNS — containers reach each other by name ──────────────
echo ""
echo "=== Block 3: Service DNS resolution ==="
docker compose exec web python -c "import socket; print('redis resolves to:', socket.gethostbyname('redis'))"
# Compose creates a bridge network. Service name 'redis' resolves via embedded DNS at 127.0.0.11.

# ─── Block 4: Hit the app and watch Redis increment ──────────────────────────
echo ""
echo "=== Block 4: Hit counter increments across requests ==="
for i in 1 2 3 4 5; do
  curl -s http://localhost:5000/
done

# ─── Block 5: Logs ───────────────────────────────────────────────────────────
echo ""
echo "=== Block 5: Service logs ==="
docker compose logs --tail=10 web
docker compose logs --tail=5 redis

# ─── Block 6: Process view ───────────────────────────────────────────────────
echo ""
echo "=== Block 6: Processes across all services ==="
docker compose top

# ─── Block 7: Exec into a service container ──────────────────────────────────
echo ""
echo "=== Block 7: Exec into redis and inspect state ==="
docker compose exec redis redis-cli get hits

# ─── Block 8: Stop and start without removing ────────────────────────────────
echo ""
echo "=== Block 8: Stop preserves state, start resumes ==="
docker compose stop
echo "Stack stopped — Redis data still on disk"

docker compose start
sleep 3

echo "After restart — hit counter resumes from where it left off:"
curl -s http://localhost:5000/

# ─── Block 9: Named network inspection ───────────────────────────────────────
echo ""
echo "=== Block 9: Inspect the auto-created network ==="
PROJECT=$(docker compose config --format json | python3 -c "import sys,json; print(json.load(sys.stdin).get('name','simple-stack'))" 2>/dev/null || echo "simple-stack")
docker network ls | grep "$PROJECT\|app-net"
docker network inspect simple-stack_app-net 2>/dev/null || \
  docker network inspect "$(docker compose config --format json 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(list(d.get('networks',{}).keys())[0])" 2>/dev/null || echo app-net)" 2>/dev/null || true

# ─── Block 10: Run a one-off command ─────────────────────────────────────────
echo ""
echo "=== Block 10: Run a one-off container from service config ==="
docker compose run --rm web python -c "import redis,os; r=redis.Redis(host='redis'); print('hits:', r.get('hits'))"

# ─── Block 11: Tear down ─────────────────────────────────────────────────────
echo ""
echo "=== Block 11: Tear down ==="
docker compose down
echo "Containers and network removed. Named volumes retained."
echo "Run 'docker compose down -v' to also remove volumes."
