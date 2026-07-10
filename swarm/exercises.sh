#!/usr/bin/env bash
set -euo pipefail

# Single-node Swarm exercises.
# All blocks run on one machine — the manager also executes tasks.
# For multi-node, replace 127.0.0.1 with your manager's advertise IP.

MANAGER_IP="${MANAGER_IP:-127.0.0.1}"

# ─── Block 1: Init the swarm ──────────────────────────────────────────────────
echo "=== Block 1: Swarm init ==="
docker swarm init --advertise-addr "$MANAGER_IP" 2>/dev/null || \
  echo "(already a swarm member)"

docker node ls
# MANAGER STATUS = Leader on the single node

echo ""
echo "Worker join token (paste this on worker nodes to join):"
docker swarm join-token --quiet worker

# ─── Block 2: Create an overlay network ──────────────────────────────────────
echo ""
echo "=== Block 2: Overlay network ==="
docker network create --driver=overlay swarm-net 2>/dev/null || true
docker network ls --filter driver=overlay

# ─── Block 3: Deploy a service ───────────────────────────────────────────────
echo ""
echo "=== Block 3: Create service with 2 replicas ==="
docker service create \
  --detach=false \
  --name webserver \
  --replicas 2 \
  --publish published=8000,target=80 \
  --network swarm-net \
  nginx:alpine

docker service ls
echo ""
docker service ps webserver
# shows which tasks are running and on which node

# ─── Block 4: Routing mesh ───────────────────────────────────────────────────
echo ""
echo "=== Block 4: Routing mesh ==="
echo "Hitting port 8000 on the manager — traffic routed to any healthy replica:"
curl -s -o /dev/null -w "HTTP %{http_code}\n" http://localhost:8000
# Works even if the replica is technically on a different node

# ─── Block 5: Scale the service ──────────────────────────────────────────────
echo ""
echo "=== Block 5: Scale to 4 replicas ==="
docker service scale --detach=false webserver=4
docker service ps webserver

echo ""
echo "Service state after scale:"
docker service ls

# ─── Block 6: Inspect service logs ───────────────────────────────────────────
echo ""
echo "=== Block 6: Aggregated logs ==="
curl -s http://localhost:8000 > /dev/null  # generate a log entry
docker service logs webserver --tail=10

# ─── Block 7: Rolling update ─────────────────────────────────────────────────
echo ""
echo "=== Block 7: Rolling update (one replica at a time) ==="
docker service update \
  --detach=false \
  --image nginx:1.27-alpine \
  --update-parallelism 1 \
  --update-delay 5s \
  --update-failure-action rollback \
  webserver

docker service ps webserver
# Previous tasks show as Shutdown; new ones show the updated image

# ─── Block 8: Rollback ───────────────────────────────────────────────────────
echo ""
echo "=== Block 8: Rollback to previous spec ==="
docker service rollback --detach=false webserver
docker service ps webserver
# Tasks flip back to the previous image

# ─── Block 9: docker stack deploy ────────────────────────────────────────────
echo ""
echo "=== Block 9: Stack deploy from Compose file ==="
docker service rm webserver  # remove manual service first

docker stack deploy \
  --compose-file docker-compose-stack.yml \
  labstack

docker stack ls
echo ""
docker stack services labstack
echo ""
docker stack ps labstack

echo ""
echo "Stack web service on port 80, visualizer on port 8080"
sleep 5
curl -s -o /dev/null -w "HTTP %{http_code}\n" http://localhost:80

# ─── Block 10: Tear down ─────────────────────────────────────────────────────
echo ""
echo "=== Block 10: Tear down ==="
docker stack rm labstack
sleep 3
docker network rm swarm-net 2>/dev/null || true
docker swarm leave --force
echo "Done."
