# Web App Stack

Patterns for running a reverse proxy + backend + database stack.

---

## Canonical structure

```
nginx (reverse proxy, port 80/443)
  -> app (backend, port 8000, internal only)
    -> postgres (database, port 5432, internal only)
```

Only nginx is exposed to the host. App and database communicate over a private Docker network. The database is never reachable from outside.

---

## Network isolation

```bash
docker network create backend-net    # app + db
docker network create frontend-net   # nginx + app

# database: backend-net only
docker run -d --name postgres --network backend-net postgres:16

# app: both networks (bridges the two)
docker run -d --name app --network backend-net myapp
docker network connect frontend-net app

# nginx: frontend-net only
docker run -d --name nginx --network frontend-net -p 80:80 nginx
```

The DB has no route to the internet. Nginx cannot reach the DB directly.

---

## Startup ordering problem

Docker starts containers in the order you declare them, but the application process is ready at an unpredictable time after the container starts. A backend that connects to Postgres on startup will fail if Postgres isn't ready yet.

**Solutions:**

1. **Retry logic in the app** (preferred) — app retries the DB connection with backoff. The container itself never fails.

2. **wait-for-it / dockerize** — shell script that polls TCP until the port is open, then exec's the app:

```bash
dockerize -wait tcp://postgres:5432 -timeout 30s app-start-command
```

3. **`depends_on` with `condition: service_healthy`** (Compose) — Compose waits for a health check to pass before starting the dependent container.

---

## Health checks

Tell Docker when a container is actually ready to serve traffic, not just started.

```dockerfile
HEALTHCHECK --interval=10s --timeout=3s --retries=3 \
  CMD curl -f http://localhost:8000/health || exit 1
```

```bash
docker inspect <container> --format '{{ .State.Health.Status }}'
# starting | healthy | unhealthy
```

A container is `healthy` only after the health check passes. `depends_on: condition: service_healthy` in Compose blocks dependents until then.

---

## Reverse proxy config pattern

Nginx proxying to the backend by container name (DNS resolves automatically on user-defined networks):

```nginx
upstream backend {
    server app:8000;
}

server {
    listen 80;

    location / {
        proxy_pass         http://backend;
        proxy_set_header   Host $host;
        proxy_set_header   X-Real-IP $remote_addr;
        proxy_set_header   X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
```

---

## Persistent database data

Databases write state to disk. Without a volume, all data is lost when the container is removed.

```bash
docker volume create pgdata

docker run -d \
  --name postgres \
  --network backend-net \
  -e POSTGRES_PASSWORD=secret \
  -v pgdata:/var/lib/postgresql/data \
  postgres:16
```

Named volume `pgdata` persists across `docker stop`, `docker rm`, and `docker run` cycles. Data survives as long as the volume exists.

---

## Restart policy

Production containers should recover from crashes and survive daemon restarts.

```bash
docker run -d \
  --restart=unless-stopped \
  --name app \
  myapp
```

| Policy | Use case |
| ------ | -------- |
| `no` | Dev / one-shot tasks |
| `unless-stopped` | Long-running production services |
| `always` | Same as above but also restarts after daemon reboot |
| `on-failure:3` | Jobs that should retry a bounded number of times |

---

## Environment config injection

Never bake secrets into images. Inject at runtime.

```bash
# env vars (simple, readable in docker inspect)
docker run -e DB_PASSWORD=secret myapp

# env file (keep out of version control)
docker run --env-file .env myapp

# Docker secrets (Compose/Swarm, mounted as /run/secrets/<name>)
```

---

## Logs

All stdout/stderr goes to Docker's log driver. Default is `json-file`.

```bash
docker logs <container>             # all logs
docker logs -f <container>          # follow
docker logs --tail=100 <container>  # last 100 lines
docker logs --since=1h <container>  # last hour
```

In production, forward logs to a centralized system (Loki, CloudWatch, Datadog) via a log driver or a sidecar. Don't rely on `json-file` on disk — it grows unbounded unless capped:

```bash
docker run --log-opt max-size=10m --log-opt max-file=3 myapp
```
