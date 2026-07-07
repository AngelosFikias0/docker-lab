#!/usr/bin/env bash
set -euo pipefail

# ─── Block 1: Start stack and verify ─────────────────────────────────────────
echo "=== Block 1: Start multi-service stack ==="
docker compose up -d --build
sleep 5
docker compose ps

# ─── Block 2: env_file — how .env is loaded ──────────────────────────────────
echo ""
echo "=== Block 2: env_file injection ==="
echo ".env contents:"
cat .env

echo ""
echo "Env inside web container (REDIS_HOST from .env):"
docker compose exec web env | grep REDIS_HOST

# ─── Block 3: Enqueue jobs ───────────────────────────────────────────────────
echo ""
echo "=== Block 3: Enqueue jobs via API ==="
for i in 1 2 3 4 5; do
  curl -s -X POST http://localhost:5000/jobs \
    -H "Content-Type: application/json" \
    -d "{\"payload\": \"task-$i\"}" | python3 -m json.tool
done

# ─── Block 4: Watch worker process jobs ──────────────────────────────────────
echo ""
echo "=== Block 4: Worker processing jobs ==="
sleep 3
docker compose logs worker --tail=20

echo ""
echo "Job status after processing:"
curl -s http://localhost:5000/jobs | python3 -m json.tool

# ─── Block 5: Scale workers ──────────────────────────────────────────────────
echo ""
echo "=== Block 5: Scale workers to 3 ==="
docker compose up -d --scale worker=3 --no-recreate
docker compose ps

echo ""
echo "Enqueue 6 more jobs — distributed across 3 workers:"
for i in 6 7 8 9 10 11; do
  curl -s -X POST http://localhost:5000/jobs \
    -H "Content-Type: application/json" \
    -d "{\"payload\": \"task-$i\"}" > /dev/null
done

sleep 5
echo "Worker logs (see which worker ID picked up which job):"
docker compose logs worker --tail=20

# ─── Block 6: Profiles — debug service ───────────────────────────────────────
echo ""
echo "=== Block 6: Profiles ==="
echo "Services without debug profile:"
docker compose ps --services

echo ""
echo "Services with --profile debug:"
docker compose --profile debug config --services

echo ""
echo "Start with debug profile (adds Redis UI on :8001):"
docker compose --profile debug up -d
docker compose ps

# ─── Block 7: depends_on health check in action ──────────────────────────────
echo ""
echo "=== Block 7: depends_on health dependency ==="
docker inspect multi-redis --format 'redis health: {{ .State.Health.Status }}'
# web and worker only started after redis reported healthy

# ─── Block 8: Scale back down ────────────────────────────────────────────────
echo ""
echo "=== Block 8: Scale workers back to 1 ==="
docker compose up -d --scale worker=1
docker compose ps

# ─── Block 9: Override a service command at runtime ──────────────────────────
echo ""
echo "=== Block 9: Run a one-off job with run ==="
# docker compose run spins up a fresh container from the service config
# but with the command overridden — doesn't touch running containers
docker compose run --rm worker python -c "
import redis, os
r = redis.Redis(host=os.environ.get('REDIS_HOST','redis'), decode_responses=True)
print('Queue length:', r.llen('jobs:pending'))
print('Done count:', r.llen('jobs:done'))
"

# ─── Block 10: Tear down ─────────────────────────────────────────────────────
echo ""
echo "=== Block 10: Tear down ==="
docker compose --profile debug down
echo "Done."
