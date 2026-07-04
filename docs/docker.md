# Docker

Deep reference covering Docker's architecture, logging, signal handling, health checks, and Kubernetes integration.

---

## Timeline

**2008** — dotCloud founded (Solomon Hykes). PaaS company building LXC-based container infrastructure internally.

**March 2013** — Docker open-sourced at PyCon. Solves the "works on my machine" problem via image-based packaging. Built on top of LXC.

**2014** — Docker drops LXC, replaces it with `libcontainer` — direct syscall interface to kernel namespaces and cgroups. Removes the external dependency, gains full control over container primitives.

**2015** — Open Container Initiative (OCI) founded. Docker donates the container image spec and runtime spec to prevent format fragmentation across competing runtimes (Docker vs rkt vs others).

**2016** — Kubernetes (open-sourced by Google in 2014) starts winning the orchestration war over Docker Swarm. Docker Inc. bets heavily on Swarm — a strategic loss. The orchestration market consolidates around Kubernetes.

**2017** — Docker splits the engine into modular OCI-compliant pieces:
- `containerd` — donated to CNCF. Becomes the industry-standard container runtime manager.
- `runc` — OCI reference implementation spun out of libcontainer, donated to OCI.

This is the architectural split visible in `docker version` today.

**2019** — Docker Inc. sells its enterprise product line (Docker Enterprise) to Mirantis. Refocuses on developer tooling: Docker Desktop, Docker Hub.

**2020** — Kubernetes deprecates `dockershim` (direct Docker daemon support), moving to the CRI standard. Signal: `dockerd` is no longer required to run containers in Kubernetes. `containerd` and `CRI-O` suffice.

**2021** — Docker Desktop introduces licensing fees for large enterprises. Alternatives (Podman Desktop, Rancher Desktop, OrbStack) gain traction. Core engine remains open source.

**2023–present** — Docker Inc. pivots toward developer experience tooling: Docker Build Cloud, Docker Scout (vulnerability scanning), `docker init`. containerd and runc remain the de facto runtime standard across Docker, Kubernetes, and CI systems.

---

## Architecture

```
docker CLI
  -> Docker daemon (dockerd)       # API server, image management, volume/network lifecycle
    -> containerd                  # container lifecycle manager, image distribution
      -> containerd-shim           # one shim per container, keeps container alive if daemon restarts
        -> runc                    # OCI runtime: creates namespaces/cgroups, exec's the process
          -> container process     # your app, PID 1 inside its namespace
```

Each layer has a distinct responsibility. Splitting them allows `containerd` to be used without `dockerd` (as in Kubernetes) and allows `runc` to be swapped for alternative OCI runtimes (gVisor, Kata).

**Daemon configuration** — `/etc/docker/daemon.json`:

```json
{
  "log-driver": "local",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "default-ulimits": {
    "nofile": { "Hard": 64000, "Name": "nofile", "Soft": 64000 }
  },
  "storage-driver": "overlay2"
}
```

Changes take effect after `systemctl reload docker` (soft reload) or `systemctl restart docker` (kills all containers).

---

## Image Distribution

Images are stored as OCI-compliant tarballs in a registry. The pull process:

```
docker pull nginx:alpine
  -> resolve tag to digest (sha256:...)
  -> fetch manifest (list of layer digests + config digest)
  -> for each layer: fetch compressed tarball if not in local cache
  -> extract layers into overlay2 directory
  -> write image metadata to /var/lib/docker/image/overlay2/
```

**Content-addressable storage:** layers are identified by their SHA256 digest. If two images share a layer (same digest), it is stored once on disk and shared. This is how pulling `python:3.13-slim` after `python:3.12-slim` only fetches the diverged layers.

**Inspect local image store:**

```bash
docker image ls
docker image inspect nginx:alpine
docker image history nginx:alpine       # layers + sizes + commands
docker manifest inspect nginx:alpine    # OCI manifest (multi-arch list or single image)
```

---

## Logging

Docker captures **stdout and stderr from PID 1** only. Nothing else. App output written to files inside the container is invisible to `docker logs` unless redirected to stdout/stderr.

```bash
docker logs <container>
docker logs -f <container>              # follow (like tail -f)
docker logs --tail 100 <container>
docker logs --since 10m <container>
docker logs -t <container>             # include timestamps
```

### Logging drivers

Docker routes logs through a pluggable driver. Set globally in `daemon.json` or per-container with `--log-driver`.

| Driver | Behavior |
| ------ | -------- |
| `json-file` | Default. Writes JSON-encoded lines to disk on the host. No rotation by default. |
| `local` | Binary format, auto-rotates by default. Preferred over `json-file`. |
| `journald` | Sends to systemd-journald. Query with `journalctl`. |
| `syslog` | Forwards to syslog daemon. |
| `fluentd` | Forwards to Fluentd collector — common in Kubernetes-adjacent pipelines. |
| `awslogs` | Direct to CloudWatch Logs. |
| `splunk` | Direct to Splunk HEC. |
| `none` | Disables logging entirely. Use for high-throughput containers where log I/O is a bottleneck. |

**Rotation** — configure on `json-file` or `local`:

```bash
docker run \
  --log-opt max-size=10m \
  --log-opt max-file=3 \
  myapp
```

Or globally in `daemon.json`:

```json
{
  "log-driver": "local",
  "log-opts": { "max-size": "10m", "max-file": "3" }
}
```

Without rotation, `json-file` will grow unbounded and fill the host disk on long-running containers. This is the most common logging footgun in production Docker setups.

### stdout / stderr are file descriptors

Every process inherits three standard file descriptors from its parent:

| FD | Name | Number | Purpose |
| -- | ---- | ------ | ------- |
| stdin | standard input | 0 | data flowing in |
| stdout | standard output | 1 | normal program output |
| stderr | standard error | 2 | error / diagnostic output |

These are integers pointing to kernel-level file objects. Docker attaches pipes to FD 1 and FD 2 of the container's PID 1, reads from those pipes, and routes output to the active log driver.

---

## Signal Handling and Termination

```
docker stop <container>
  -> SIGTERM sent to PID 1
  -> grace period (default: 10s)
  -> SIGKILL if still running
```

| Signal | Number | Catchable | Cleanup possible | Kernel enforces |
| ------ | ------ | --------- | ---------------- | --------------- |
| SIGTERM | 15 | Yes | Yes | No |
| SIGKILL | 9 | No | No | Yes, immediate |

**SIGTERM** is a request. The process can install a handler, run cleanup (flush buffers, finish in-flight requests, close DB connections), and exit. If no handler exists, the default OS behavior is to terminate the process.

**The PID 1 problem:** shell form `CMD` runs your app as a child of `/bin/sh`. Shell form does not forward signals to children. `docker stop` sends SIGTERM to `/bin/sh` (PID 1) which ignores it, so Docker force-kills after the grace period — no graceful shutdown.

```dockerfile
# Shell form — /bin/sh is PID 1, signals are not forwarded
CMD python app.py

# Exec form — python is PID 1, receives SIGTERM directly
CMD ["python", "app.py"]
```

Always use exec form for long-running processes.

**Adjust grace period:**

```bash
docker stop --time=30 <container>       # 30s before SIGKILL
```

```yaml
# Compose
services:
  app:
    stop_grace_period: 30s
```

In Kubernetes, the equivalent is `terminationGracePeriodSeconds` on the PodSpec (default: 30s).

---

## Health Checks

Docker provides the mechanism. You define what "healthy" means for your app.

```dockerfile
HEALTHCHECK --interval=10s --timeout=3s --start-period=15s --retries=3 \
  CMD curl -f http://localhost:8080/healthz || exit 1
```

| Option | Default | Purpose |
| ------ | ------- | ------- |
| `--interval` | 30s | Time between checks |
| `--timeout` | 30s | Time before a check is considered failed |
| `--start-period` | 0s | Grace window at startup before failures count |
| `--retries` | 3 | Consecutive failures before marking unhealthy |

**States:** `starting` -> `healthy` -> `unhealthy`

```bash
docker inspect <container> --format '{{ .State.Health.Status }}'
docker inspect <container> --format '{{ json .State.Health }}' | jq .
```

**Use in Compose** — block dependents until health passes:

```yaml
services:
  db:
    image: postgres:16
    healthcheck:
      test: ["CMD", "pg_isready", "-U", "postgres"]
      interval: 5s
      retries: 5

  app:
    image: myapp
    depends_on:
      db:
        condition: service_healthy
```

Without `service_healthy`, `depends_on` only waits for the container to start — not for the service inside to be ready. Race conditions on startup are almost always a missing or misconfigured health check.

**Kubernetes equivalent:**

| Docker | Kubernetes | Purpose |
| ------ | ---------- | ------- |
| HEALTHCHECK | `livenessProbe` | Is the process alive? Restart if not. |
| — | `readinessProbe` | Ready to receive traffic? Remove from Service endpoints if not. |
| — | `startupProbe` | Override liveness during slow startup. |

Docker conflates liveness and readiness in a single check. Kubernetes separates them deliberately — an app can be alive but not ready (warming up a cache, running migrations).

---

## Kubernetes Integration

Kubernetes does not use `dockerd`. It talks to a CRI-compliant runtime directly.

```
kubelet -> CRI (gRPC API) -> containerd (CRI plugin) -> containerd-shim -> runc
```

**CRI (Container Runtime Interface)** — gRPC API spec defining the contract between `kubelet` and the runtime: `RunPodSandbox`, `CreateContainer`, `PullImage`, `StopContainer`, etc. Introduced in Kubernetes 1.5 to decouple kubelet from any single runtime.

**Docker path vs Kubernetes path:**

```
docker CLI  -> dockerd -> containerd -> containerd-shim -> runc
kubelet     -> CRI     -> containerd -> containerd-shim -> runc
```

Same `containerd` and `runc` at the bottom. The `dockerd` layer is absent in Kubernetes. Docker images built with `docker build` run identically in Kubernetes because both paths reach the same OCI runtime.

### CRI-compliant runtimes

| Runtime | Notes |
| ------- | ----- |
| `containerd` | Default in EKS, GKE, AKS, kubeadm. CNCF graduated. General purpose. |
| `CRI-O` | Purpose-built for Kubernetes only. Default on OpenShift. No general daemon overhead. Narrower attack surface. |
| `gVisor` (runsc) | Userspace kernel — intercepts and handles syscalls in userspace before they reach the host kernel. Plugged in via `RuntimeClass`. Strong isolation for untrusted workloads. |
| `Kata Containers` | VM-level isolation per pod, still speaks CRI. Heavier than gVisor but stronger isolation. For hard multi-tenancy or compliance. |
| `Firecracker` | Microvm runtime (AWS-originated). Fast-boot VM isolation. Used in Lambda-style serverless architectures. |

**RuntimeClass** (Kubernetes) — selects which OCI runtime to use per workload:

```yaml
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata:
  name: gvisor
handler: runsc
---
apiVersion: v1
kind: Pod
spec:
  runtimeClassName: gvisor
  containers:
    - name: app
      image: myapp
```

---

## BuildKit

Default build backend since Docker 23. Replaces the legacy builder.

```bash
# confirm BuildKit is active
docker buildx version
DOCKER_BUILDKIT=1 docker build .    # explicit (not needed on modern Docker)
```

**Key features over legacy builder:**

| Feature | Legacy | BuildKit |
| ------- | ------ | -------- |
| Parallel stage execution | No | Yes |
| Cache mounts (`--mount=type=cache`) | No | Yes |
| Secret mounts (`--mount=type=secret`) | No | Yes |
| SSH agent forwarding in build | No | Yes |
| Multi-platform builds | No | Yes (via buildx) |
| Inline cache (`--cache-from`) | Limited | Full |

`buildx` is the CLI frontend for BuildKit. It manages builder instances and enables multi-platform builds via QEMU emulation or native remote builders.
