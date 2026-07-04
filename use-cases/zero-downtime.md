# Zero-Downtime Deployments

Patterns for updating containers without dropping requests.

---

## The problem

`docker stop` sends SIGTERM, waits the grace period, then SIGKILL. If the container is handling requests when it stops, those requests are dropped.

Three things need to work together:
1. The app handles SIGTERM gracefully (finishes in-flight requests, then exits).
2. The load balancer stops sending new requests before the container stops.
3. The new container is healthy before traffic shifts.

---

## Graceful shutdown in the app

The app must catch SIGTERM, stop accepting new connections, drain in-flight requests, then exit.

**Python (FastAPI / uvicorn):** uvicorn handles SIGTERM gracefully by default when run in exec form.

**Node.js:**

```js
process.on('SIGTERM', () => {
  server.close(() => {
    process.exit(0);
  });
});
```

**Go:** use `http.Server.Shutdown(ctx)` with a deadline context.

If your entrypoint is shell form (`CMD app`), `/bin/sh` is PID 1 and does not forward signals to the child process. Use exec form (`CMD ["app"]`) so the app is PID 1 and receives SIGTERM directly.

---

## Health checks

Docker won't route traffic to a container until its health check passes. Without one, the container is considered healthy immediately on start — before the app is actually ready.

```dockerfile
HEALTHCHECK --interval=5s --timeout=3s --start-period=10s --retries=3 \
  CMD curl -f http://localhost:8000/health || exit 1
```

- `--start-period` — grace window before failures count. Use it for apps with slow startup.
- `--interval` — how often to probe.
- `--retries` — consecutive failures before marking unhealthy.

```bash
docker inspect <container> --format '{{ .State.Health.Status }}'
# starting -> healthy -> unhealthy
```

---

## Rolling update with Compose

Compose v2 supports rolling updates for services with `--scale`:

```bash
docker compose up -d --scale app=3 --no-recreate   # scale out
docker compose up -d app                            # rolling recreate
```

With `depends_on: condition: service_healthy`, dependents wait for health check before traffic shifts. Combine with `deploy.update_config` in Compose for explicit parallelism and order control.

---

## Blue-green deployment

Run two identical stacks. Switch traffic at the load balancer level.

```bash
# blue is live
docker run -d --name app-blue --network frontend-net myapp:v1

# deploy green
docker run -d --name app-green --network frontend-net myapp:v2
# wait for green health check to pass

# switch nginx upstream to green (reload without dropping connections)
docker exec nginx nginx -s reload

# remove blue
docker rm -f app-blue
```

nginx `-s reload` uses `SIGHUP` to reload config and gracefully replace workers without closing the listening socket. No dropped connections during the switch.

---

## Stop grace period

Give the app enough time to finish draining. Default grace period is 10 seconds.

```bash
docker stop --time=30 <container>    # 30s before SIGKILL
```

In Compose:

```yaml
services:
  app:
    stop_grace_period: 30s
```

In Kubernetes, this is `terminationGracePeriodSeconds` on the PodSpec. Same concept.

---

## Readiness vs liveness (Kubernetes mapping)

| Probe | Docker equivalent | Purpose |
| ----- | ----------------- | ------- |
| Liveness | HEALTHCHECK | Is the process alive? Restart if not. |
| Readiness | — (no native equivalent) | Is the app ready to receive traffic? Remove from load balancer if not. |

Docker's HEALTHCHECK combines both — a single check gates both traffic and restarts. Kubernetes splits them deliberately: an app can be alive (don't restart it) but not ready (don't send it traffic). This distinction matters for apps that take time to warm up caches or load models.

---

## Canary releases

Route a percentage of traffic to the new version while the old version handles the rest.

With nginx upstream weights:

```nginx
upstream backend {
    server app-v1:8000 weight=9;   # 90% of traffic
    server app-v2:8000 weight=1;   # 10% of traffic
}
```

Increment the v2 weight as confidence grows. Roll back by setting v2 weight to 0 and reloading.

In Kubernetes this is done with replica ratios: 9 v1 pods + 1 v2 pod = 10% canary without any nginx config.
