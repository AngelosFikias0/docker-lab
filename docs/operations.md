# Operations

Container management commands and cleanup procedures.

---

## Production container lifecycle

The path from code to running container in production:

```
1. Build and test locally
   docker build + docker run on dev machine
   Verifies the image works before committing

2. CI builds the official image
   Triggered by git push, produces a deterministic image from clean state
   Runs tests inside the build (test stage) or as a separate job

3. Push to registry
   docker push ghcr.io/org/image:sha or :v1.2.3
   Registry is the handoff point between build and runtime

4. Deploy to server/orchestrator
   docker run, docker compose up, or kubectl apply
   Runtime pulls the image from the registry and starts the container

5. Orchestrate at scale
   Health checks, restart policies, rolling updates, resource limits
   In production this is Kubernetes or Docker Swarm, not bare docker run
```

Docker's role across this lifecycle:

| Concern | Docker mechanism |
|---|---|
| Isolation | namespaces (pid, net, mnt, uts, ipc, user) |
| Resource limits | cgroups v2 (CPU, memory, I/O) |
| Networking | bridge/overlay drivers, embedded DNS, port mapping |
| Configuration | env vars, mounted config files, secrets |
| Packaging | image layers, OCI spec, registry distribution |
| Logging | log drivers (json-file, journald, fluentd, awslogs) |
| Health | HEALTHCHECK instruction, `--health-*` flags |
| Scheduling | restart policies locally; Kubernetes / Swarm at scale |
| Service discovery | embedded DNS (Compose); CoreDNS / Consul in production |
| Load balancing | iptables DNAT (single host); kube-proxy / IPVS / eBPF in k8s |
| Orchestration | Docker Compose (single host); Kubernetes (multi-host) |
| Distributed deployment | blue-green and canary via orchestrator; multiple CRI runtimes (containerd, CRI-O) |

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
