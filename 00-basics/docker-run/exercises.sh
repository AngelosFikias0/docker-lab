#!/usr/bin/env bash
# exercises.sh
# Run blocks individually. Each section is self-contained.
# Not meant to be executed top-to-bottom as a pipeline.

# ---------------------------------------------------------------------------
# 1. BASELINE — confirm Docker is working
# ---------------------------------------------------------------------------
docker run hello-world

# ---------------------------------------------------------------------------
# 2. INTERACTIVE — drop into a container shell
# -i  keep stdin open
# -t  allocate a pseudo-TTY
# Combined: -it gives you an interactive terminal session
# ---------------------------------------------------------------------------
docker run -it ubuntu bash

# Inside: run `whoami`, `ls /`, `cat /etc/os-release`, then `exit`

# ---------------------------------------------------------------------------
# 3. DETACHED — run in the background
# -d returns the container ID immediately
# ---------------------------------------------------------------------------
docker run -d --name my-nginx nginx

docker ps                          # confirm it's running
docker logs my-nginx               # stream logs
docker logs -f my-nginx            # follow logs (like tail -f)
docker stop my-nginx
docker rm my-nginx

# ---------------------------------------------------------------------------
# 4. PORT MAPPING — expose container port to host
# Syntax: -p HOST:CONTAINER
# ---------------------------------------------------------------------------
docker run -d --name web -p 8080:80 nginx

# curl http://localhost:8080
# or open browser at http://localhost:8080

docker stop web && docker rm web

# ---------------------------------------------------------------------------
# 5. EPHEMERAL — auto-remove on exit
# --rm cleans up the container when it exits
# Use for one-off commands
# ---------------------------------------------------------------------------
docker run --rm alpine echo "hello from alpine"
docker run --rm -it alpine sh

# After exit: `docker ps -a` — container is gone

# ---------------------------------------------------------------------------
# 6. ENVIRONMENT VARIABLES — inject config at runtime
# This is how 12-factor apps receive config
# Never bake secrets into images
# ---------------------------------------------------------------------------
docker run --rm \
  -e APP_ENV=production \
  -e DB_HOST=postgres \
  alpine env | grep -E "APP_ENV|DB_HOST"

# ---------------------------------------------------------------------------
# 7. NAMING — always name containers in any non-throwaway context
# Unnamed containers get random names (elegant_hopper, etc.) — useless
# ---------------------------------------------------------------------------
docker run -d --name postgres-dev \
  -e POSTGRES_PASSWORD=secret \
  postgres:16-alpine

docker exec -it postgres-dev psql -U postgres   # connect into running container
docker stop postgres-dev && docker rm postgres-dev

# ---------------------------------------------------------------------------
# 8. RESOURCE CONSTRAINTS — always set in production
# --memory  hard limit — OOM kill if exceeded
# --cpus    fractional CPU cores
# Without these, a container can starve the host
# ---------------------------------------------------------------------------
docker run -d --name constrained \
  --memory=128m \
  --cpus=0.5 \
  nginx

docker stats constrained           # live resource usage
docker stop constrained && docker rm constrained

# ---------------------------------------------------------------------------
# 9. INSPECT — understand what's inside a container
# ---------------------------------------------------------------------------
docker run -d --name inspect-me nginx

docker inspect inspect-me                                  # full JSON
docker inspect inspect-me | grep -i IPAddress             # container IP
docker inspect inspect-me --format '{{ .State.Status }}'  # single field

docker stop inspect-me && docker rm inspect-me

# ---------------------------------------------------------------------------
# 10. CLEANUP
# ---------------------------------------------------------------------------
docker ps -a                       # list all containers (including stopped)
docker container prune             # remove all stopped containers
docker image prune                 # remove dangling images
