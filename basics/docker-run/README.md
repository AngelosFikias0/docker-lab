# docker-run

Core runtime flags. Every command here is independent. Run them one at a time and understand the output before moving on.

## What you're learning

- How Docker starts and manages containers
- The difference between foreground, interactive, and detached modes
- How port mapping, naming, env injection, and resource constraints work at the CLI level

## Run the exercises

```bash
bash exercises.sh
```

Or execute each block individually. Prefer individual. Understand each flag before combining them.

---

## Concepts

### Lifecycle

```
docker run   -> creates + starts a container
docker start -> starts a stopped container
docker stop  -> sends SIGTERM, then SIGKILL after grace period
docker rm    -> removes stopped container
```

### Foreground vs Detached

```
docker run nginx          # foreground, blocks your terminal, logs stream
docker run -d nginx       # detached, runs in background, returns container ID
```

### Port mapping

```
-p HOST_PORT:CONTAINER_PORT
```

Container exposes a port internally. `-p` maps it to your host. Without `-p`, the container port is unreachable from outside.

### `--rm`

Removes the container automatically when it exits. Use for one-off tasks. Don't use for containers you need to inspect after failure.

### Resource constraints

Docker doesn't enforce limits by default. A container can consume all host memory. Always set limits in production. This applies to Kubernetes too (requests/limits in the pod spec).
