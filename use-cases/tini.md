# Tini — PID 1 in Containers

---

## The Problem

Linux gives PID 1 special responsibilities:

1. **Signal forwarding** — PID 1 does not receive SIGTERM by default the same way other processes do. If your app is PID 1 and doesn't install a SIGTERM handler, `docker stop` times out and force-kills it with SIGKILL.
2. **Zombie reaping** — When a child process exits, it becomes a zombie until its parent calls `wait()`. If the parent exits first, the zombie is re-parented to PID 1. PID 1 is expected to reap them. A normal application process does not do this.

Most apps are not written to handle either of these. They are written to be children, not inits.

---

## Shell Form Makes It Worse

```dockerfile
# Shell form — /bin/sh is PID 1, your app is a child
CMD python app.py

# Exec form — your app IS PID 1
CMD ["python", "app.py"]
```

With shell form, `/bin/sh` is PID 1. The shell does not forward signals to children. `docker stop` sends SIGTERM to `/bin/sh`, which ignores it, so Docker force-kills after the grace period — no graceful shutdown.

Exec form makes your app PID 1, which is better, but the app still needs to handle SIGTERM and reap zombies if it spawns children.

---

## Tini

Tini is a minimal init specifically for containers. It does exactly two things:

1. Forwards signals to the child process.
2. Reaps zombie processes.

Nothing else. 100KB binary.

```
docker stop
  -> SIGTERM to tini (PID 1)
    -> tini forwards SIGTERM to your app
      -> app handles it, cleans up, exits
        -> tini exits with app's exit code
```

---

## Usage

**In Dockerfile:**

```dockerfile
FROM python:3.13-slim

RUN apt-get update && apt-get install -y --no-install-recommends tini \
    && rm -rf /var/lib/apt/lists/*

COPY app.py .

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["python", "app.py"]
```

`tini --` separates tini's args from the child command. Your app runs as a child of tini, receives signals correctly, and tini reaps any zombie grandchildren.

**Alpine:**

```dockerfile
FROM alpine:3.20
RUN apk add --no-cache tini
ENTRYPOINT ["/sbin/tini", "--"]
CMD ["myapp"]
```

**Multi-stage (copy binary only, no package manager in final image):**

```dockerfile
FROM alpine:3.20 AS tini
RUN apk add --no-cache tini

FROM gcr.io/distroless/static-debian12
COPY --from=tini /sbin/tini /tini
COPY --from=builder /app /app
ENTRYPOINT ["/tini", "--"]
CMD ["/app"]
```

---

## Docker's Built-in --init Flag

```bash
docker run --init myimage
```

Injects [tini](https://github.com/krallin/tini) as PID 1 at runtime without modifying the image. Uses the tini binary bundled with Docker at `/usr/bin/docker-init`.

Use this for quick fixes or dev environments. Prefer baking tini into the image for production — portable, not dependent on the Docker host having the binary.

---

## Alternatives

| Tool | Size | Notes |
| ---- | ---- | ----- |
| `tini` | ~100KB | Purpose-built, minimal, most common |
| `dumb-init` | ~100KB | Similar to tini, from Yelp, also popular |
| `s6-overlay` | ~3MB | Full supervision suite — use if you need multiple processes per container |
| `--init` flag | 0 (host) | Runtime injection, no image change needed |

`s6-overlay` is the right choice if you genuinely need multiple supervised processes in one container (e.g. nginx + app without Compose). For single-process containers, tini or dumb-init.

---

## Verify Tini Is PID 1

```bash
docker exec <container> cat /proc/1/cmdline | tr '\0' ' '
# /usr/bin/tini -- python app.py

docker exec <container> ps aux
# PID 1: tini
# PID 7: python app.py  <- your app as a child
```

---

## Kubernetes

Kubernetes manages pod lifecycle at the kubelet level — it sends SIGTERM to the container's PID 1 and waits `terminationGracePeriodSeconds` (default 30s). Tini in Kubernetes works identically to Docker: it receives the signal and forwards it to your app.

If you use a distroless image (no shell, no tini), your app must handle SIGTERM directly. If it doesn't, you will see 30-second shutdown delays on every pod deletion or rolling update.

```yaml
spec:
  terminationGracePeriodSeconds: 30
  containers:
    - name: app
      # If CMD is exec form and app handles SIGTERM: no tini needed.
      # If app spawns children or doesn't handle SIGTERM: add tini.
```
