# Operations

Container management commands and cleanup procedures.

---

## Container Management

```bash
docker container create <image>          # allocate filesystem + config, no process started
docker container update <name>           # update resource limits on a running container
docker container stop <name>             # SIGTERM -> grace period -> SIGKILL
docker kill <name>                       # SIGKILL immediately, no grace period
docker pause <name>                      # freeze all processes in the container (SIGSTOP)
docker rm <name>                         # remove stopped container
docker rm -f <name>                      # force: kill + remove in one step
docker rm -v <name>                      # remove container + its anonymous volumes
docker container prune                   # remove all stopped containers
```

**Restart policies** (`--restart`):

| Policy                  | Behavior                                              |
| ----------------------- | ----------------------------------------------------- |
| `no`                    | Never restart (default)                               |
| `always`                | Always restart, including on daemon start             |
| `unless-stopped`        | Restart unless manually stopped                       |
| `on-failure:<n>`        | Restart on non-zero exit, up to n times               |

```bash
docker run --restart=unless-stopped nginx
docker run --restart=on-failure:3 myapp
```

---

## Cleanup and Maintenance

### 1. Diagnose first

```bash
docker system df        # summary: images, containers, volumes, cache + reclaimable
docker system df -v     # verbose: per-object breakdown
```

Never prune blind. Know what you're reclaiming before running any prune command.

### 2. Object hierarchy

Docker has four cleanup targets. Dependencies flow downward — clean in this order:

```
Containers -> Images -> Volumes -> Networks
```

You cannot remove an image used by a container. You cannot remove a volume mounted by a running container. Stop containers first.

### 3. Containers

```bash
docker container ls -a                  # all containers including stopped
docker container prune                  # remove all stopped containers
docker rm <id>                          # remove one
docker rm -f <id>                       # force: kill + remove running container
docker rm -v <id>                       # also remove anonymous volumes attached to it
```

`container prune` only touches stopped containers. Safe to run freely.

### 4. Images

```bash
docker image ls
docker image prune                      # dangling images only (untagged, orphaned layers)
docker image prune -a                   # all unused images (not referenced by any container)
docker rmi <id>
```

`image prune -a` deletes every image not backing a running container — including ones pulled intentionally for later use. On a dev machine this means re-pulling large base images next build. Check `docker image ls` before running on shared infra.

### 5. Volumes

```bash
docker volume ls
docker volume ls -f dangling=true       # volumes not attached to any container
docker volume prune                     # remove all unused volumes
docker volume rm <name>
```

Volumes hold stateful data — DB files, persistent app state. `volume prune` is irreversible with a single `y/N` prompt. Named volumes with production data have no business being pruned casually. Never run `docker volume prune` on a host you didn't provision yourself without listing volumes first.

### 6. Networks

```bash
docker network ls
docker network prune                    # remove unused custom networks
docker network rm <name>
```

Low risk. Default networks (`bridge`, `host`, `none`) are protected and cannot be removed.

### 7. Build cache

```bash
docker builder prune                    # remove dangling build cache
docker builder prune -a                 # remove all build cache
```

Grows fast with multi-stage builds and CI pipelines. Frequently the largest reclaimable category on build hosts — check `docker system df` first.

### 8. Nuclear commands

```bash
docker system prune                     # stopped containers + dangling images + unused networks + build cache
docker system prune -a                  # + all unused images (not just dangling)
docker system prune -a --volumes        # + all unused volumes
```

`--volumes` is not included in `system prune` by default — deliberate safety design. You must opt in explicitly.

### 9. Compose-scoped cleanup

```bash
docker compose down                     # stop + remove containers and default network
docker compose down -v                  # + remove named volumes
docker compose down --rmi all           # + remove images built/pulled for this compose file
docker compose down --remove-orphans    # + remove containers not in current compose file
```

Scoped to the project — safer than global prune when working in a multi-project environment.
