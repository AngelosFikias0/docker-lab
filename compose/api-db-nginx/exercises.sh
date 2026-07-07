#!/usr/bin/env bash
set -euo pipefail

# ─── Block 1: Build and start the full stack ─────────────────────────────────
echo "=== Block 1: Build and start nginx + Spring Boot + PostgreSQL ==="
docker compose up -d --build

echo ""
echo "Waiting for Spring Boot to be healthy (downloads deps + JVM startup ~60s)..."
until docker inspect lab-api --format '{{ .State.Health.Status }}' 2>/dev/null | grep -q "healthy"; do
  sleep 5
  echo "  still starting..."
done
echo "Stack is healthy."
docker compose ps

# ─── Block 2: Verify depends_on health gate ──────────────────────────────────
echo ""
echo "=== Block 2: depends_on health gate ==="
echo "postgres health:"
docker inspect lab-postgres --format '{{ .State.Health.Status }}'
echo "api health:"
docker inspect lab-api --format '{{ .State.Health.Status }}'
# app only started after postgres reported 'healthy' via pg_isready

# ─── Block 3: Test through nginx reverse proxy ───────────────────────────────
echo ""
echo "=== Block 3: API through nginx on port 80 ==="
echo "--- GET /api/items (empty) ---"
curl -s http://localhost/api/items | python3 -m json.tool

echo ""
echo "--- POST /api/items ---"
curl -s -X POST http://localhost/api/items \
  -H "Content-Type: application/json" \
  -d '{"name": "docker-lab"}' | python3 -m json.tool

curl -s -X POST http://localhost/api/items \
  -H "Content-Type: application/json" \
  -d '{"name": "spring-boot"}' | python3 -m json.tool

echo ""
echo "--- GET /api/items (persisted) ---"
curl -s http://localhost/api/items | python3 -m json.tool

# ─── Block 4: Health endpoint ────────────────────────────────────────────────
echo ""
echo "=== Block 4: Spring Actuator health ==="
curl -s http://localhost/actuator/health | python3 -m json.tool

# ─── Block 5: Network isolation ──────────────────────────────────────────────
echo ""
echo "=== Block 5: Network isolation ==="
echo "nginx networks (frontend only — cannot reach postgres):"
docker inspect lab-nginx --format '{{ range $k, $v := .NetworkSettings.Networks }}{{ $k }} {{ end }}'

echo "api networks (frontend + backend — bridges both):"
docker inspect lab-api --format '{{ range $k, $v := .NetworkSettings.Networks }}{{ $k }} {{ end }}'

echo ""
echo "nginx cannot reach postgres directly:"
docker compose exec nginx sh -c "nc -zv postgres 5432 2>&1" || echo "Expected: connection refused (different network)"

echo ""
echo "app can reach postgres:"
docker compose exec app sh -c "nc -zv postgres 5432 2>&1" && echo "ok"

# ─── Block 6: Data persistence ───────────────────────────────────────────────
echo ""
echo "=== Block 6: Data persists across container restart ==="
echo "Items before restart:"
curl -s http://localhost/api/items | python3 -m json.tool

docker compose restart app
echo "Waiting for app to be healthy again..."
until docker inspect lab-api --format '{{ .State.Health.Status }}' 2>/dev/null | grep -q "healthy"; do
  sleep 5
done

echo "Items after restart (data from PostgreSQL volume, not container):"
curl -s http://localhost/api/items | python3 -m json.tool

# ─── Block 7: Volume inspection ──────────────────────────────────────────────
echo ""
echo "=== Block 7: Named volume on disk ==="
docker volume ls | grep pgdata
docker volume inspect "$(docker compose config --format json 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(list(d.get('volumes',{}).keys())[0])" 2>/dev/null || echo api-db-nginx_pgdata)" 2>/dev/null | python3 -m json.tool || \
  docker volume ls --format '{{ .Name }}' | grep pgdata | xargs docker volume inspect | python3 -m json.tool

# ─── Block 8: Logs across services ───────────────────────────────────────────
echo ""
echo "=== Block 8: Logs ==="
docker compose logs --tail=5 nginx
docker compose logs --tail=5 app

# ─── Block 9: Delete an item ─────────────────────────────────────────────────
echo ""
echo "=== Block 9: DELETE ==="
ITEM_ID=$(curl -s http://localhost/api/items | python3 -c "import sys,json; items=json.load(sys.stdin); print(items[0]['id']) if items else print('')")
if [ -n "$ITEM_ID" ]; then
  curl -s -X DELETE http://localhost/api/items/$ITEM_ID
  echo "Deleted item $ITEM_ID"
  curl -s http://localhost/api/items | python3 -m json.tool
fi

# ─── Block 10: Tear down ─────────────────────────────────────────────────────
echo ""
echo "=== Block 10: Tear down ==="
docker compose down
echo "Containers removed. pgdata volume retained."
echo "Run 'docker compose down -v' to also drop the database volume."
