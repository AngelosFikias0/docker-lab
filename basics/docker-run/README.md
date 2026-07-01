# docker-run

Core runtime flags. Every command here is independent. Run them one at a time and understand the output before moving on.

## Run the exercises

```bash
bash exercises.sh
```

Or execute each block individually.

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
docker run nginx          # foreground, blocks terminal, logs stream
docker run -d nginx       # detached, returns container ID immediately
```

### Port mapping

```
-p HOST_PORT:CONTAINER_PORT
```

Container exposes a port internally. `-p` maps it to the host. Without `-p`, the container port is unreachable from outside.

### `--rm`

Removes the container on exit. Not suitable for containers you want to inspect post-failure.

### Resource constraints

No limits applied by default. A container can consume all host memory and CPU. `--memory` and `--cpus` set hard bounds.
