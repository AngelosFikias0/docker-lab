# Docker Lab

A structured Docker engineering lab. Progressive depth from container primitives to production systems.

---

## Structure

```
docker-lab/
├── basics/               # Container lifecycle, core CLI, image fundamentals
│   ├── docker-run/       # 10 runtime flag exercises
│   └── images-build/     # Annotated Dockerfile, minimal stdlib app
│
├── images/               # Image creation, layering, and optimization
│   ├── multistage/       # 4-stage build: base -> deps -> test -> final; multi-arch exercises
│   ├── distroless/       # Flask on distroless, no shell, minimal attack surface
│   └── nginx-example/    # Static site via custom nginx config
│
├── image-inspection/     # Pulling images apart: history, inspect, save, dive
│   └── layer-analysis/   # Hands-on inspection of real images
│
├── networks/             # Container networking: bridge, DNS, isolation
│   ├── bridge-network/   # Default vs custom bridge, veth pairs, iptables
│   └── dns-resolution/   # Embedded DNS at 127.0.0.11, aliases, isolation
│
├── storage/              # Persistent data: volumes, bind mounts, tmpfs, overlay2
│   ├── volumes/          # Named volume lifecycle, persistence, backup, sharing
│   └── bind-mounts/      # Config injection, dev workflow, tmpfs
│
├── performance/          # Resource limits, cgroup internals, throttling, OOM
│   ├── resource-limits/  # CPU caps, memory limits, I/O throttling, docker stats
│   └── cpu-memory-stress/# Throttling observation, OOM trigger, share contention
│
├── security/             # Non-root, capabilities, secrets, distroless hardening
│   ├── user-permissions/ # UID mapping, cap-drop, read-only filesystem
│   ├── secrets-basics/   # Secret injection patterns, BuildKit mounts
│   └── distroless/       # Attack surface comparison, no-shell debugging
│
├── compose/              # Docker Compose: declarative multi-container stacks
│   ├── simple-stack/     # Flask + Redis, core Compose concepts and CLI
│   ├── api-db-nginx/     # Spring Boot + PostgreSQL + nginx reverse proxy
│   └── multi-service-app/# Web + worker + Redis, scaling, profiles, env_file
│
├── observability/        # Metrics pipeline: cAdvisor + Prometheus + Grafana
│   ├── prometheus/       # Scrape config, alert rules (OOM, throttle, memory)
│   └── grafana/          # Auto-provisioned datasource and dashboard
│
├── private-registry/     # Local registry:2 + UI, pull-through cache, v2 API exercises
│
├── swarm/                # Docker Swarm Mode: services, overlay networks, stacks, routing mesh
│   └── swarm.md          # Raft, routing mesh, services, docker stack internals
│
├── kubernetes/           # Kubernetes: pod, deployment, service, PVC — exercises via kind
│   ├── kubernetes.md     # Pods, Deployments, Services, PVC, kubectl, kind/minikube/k3s
│   └── manifests/        # pod.yml, deployment.yml, service.yml, pvc.yml
│
├── docs/                 # Reference notes on internals and theory
│   ├── linux-basics.md   # Processes, namespaces, cgroups, syscalls
│   ├── containers.md     # Fundamentals, history, lifecycle, identity files
│   ├── docker.md         # Architecture, logging, signals, health checks, k8s integration
│   ├── networking.md     # Bridge, veth, DNS, NAT, overlay, k8s mapping
│   ├── operations.md     # Container management, restart policies, cleanup
│   ├── ci-cd.md          # GitHub Actions internals, GHA cache, ghcr.io, release flow
│   ├── vms.md            # KVM, QEMU, protection rings, EPT, Firecracker
│   └── 12-factor.md      # 12-Factor App + Reactive Manifesto mapped to Docker/k8s
│
└── use-cases/            # Problem-solution reference by scenario
    ├── debugging.md      # Container exits, OOM, network issues, no-shell images
    ├── build-optimization.md  # Layer ordering, cache mounts, multi-stage, .dockerignore
    ├── web-app-stack.md  # Reverse proxy + backend + DB, health checks, restart policy
    ├── ci-cd.md          # DinD vs socket, registry cache, multi-arch, tagging
    ├── zero-downtime.md  # Graceful shutdown, health checks, blue-green, canary
    ├── secrets.md        # Env vars, mounted files, Docker secrets, Vault, k8s
    └── tini.md           # PID 1 problem, signal forwarding, zombie reaping
```

---

## CI/CD

Two workflows in `.github/workflows/`:

| Workflow | Trigger | What it does |
|---|---|---|
| `ci.yml` | push / PR to `main` | Validates all Compose files and shell scripts, then builds all 13 Dockerfiles in parallel. Pushes `simple-stack`, `multi-service-app`, and `api` images to ghcr.io on merges to main. |
| `release.yml` | manual (`workflow_dispatch`) | Bumps semver tag (patch / minor / major), builds and pushes a versioned API image to ghcr.io, creates a GitHub release with auto-generated notes. |

Published images:

```
ghcr.io/angelosfikias0/docker-lab-api:latest
ghcr.io/angelosfikias0/docker-lab-api:v0.1.0
ghcr.io/angelosfikias0/docker-lab-simple-stack:latest
ghcr.io/angelosfikias0/docker-lab-multi-service-app:latest
```

See [`docs/ci-cd.md`](docs/ci-cd.md) for internals: GHA job model, matrix strategy, BuildKit GHA cache, GITHUB_TOKEN permissions, ghcr.io publishing, and the release version arithmetic.

---

## Prerequisites

- Docker Engine 24+ (BuildKit enabled by default)
- `curl` for testing endpoints
- `jq` for JSON inspection commands

---

## References

**Core docs**

- [Docker Engine overview](https://docs.docker.com/engine/)
- [Dockerfile reference](https://docs.docker.com/reference/dockerfile/)
- [docker run reference](https://docs.docker.com/reference/cli/docker/container/run/)
- [Docker Compose reference](https://docs.docker.com/reference/compose-file/)

**Images and builds**

- [BuildKit overview](https://docs.docker.com/build/buildkit/)
- [Multi-stage builds](https://docs.docker.com/build/building/multi-stage/)
- [Build cache](https://docs.docker.com/build/cache/)
- [OCI Image Spec](https://github.com/opencontainers/image-spec)

**Networking**

- [Networking overview](https://docs.docker.com/engine/network/)
- [Bridge networks](https://docs.docker.com/engine/network/drivers/bridge/)

**Storage**

- [Volumes](https://docs.docker.com/engine/storage/volumes/)
- [Bind mounts](https://docs.docker.com/engine/storage/bind-mounts/)
- [tmpfs mounts](https://docs.docker.com/engine/storage/tmpfs/)
- [Storage drivers](https://docs.docker.com/engine/storage/drivers/)
- [OverlayFS](https://www.kernel.org/doc/html/latest/filesystems/overlayfs.html)

**Security**

- [Docker security overview](https://docs.docker.com/engine/security/)
- [Rootless mode](https://docs.docker.com/engine/security/rootless/)
- [Seccomp profiles](https://docs.docker.com/engine/security/seccomp/)

**Runtime and performance**

- [Resource constraints](https://docs.docker.com/engine/containers/resource_constraints/)
- [Runtime metrics](https://docs.docker.com/engine/containers/runmetrics/)
- [CFS scheduler](https://www.kernel.org/doc/html/latest/scheduler/sched-design-CFS.html)
- [cgroups v2](https://www.kernel.org/doc/html/latest/admin-guide/cgroup-v2.html)

**Books**

- _Docker: Up and Running_ - Karl Matthias, Sean P. Kane (O'Reilly)
- _Docker Deep Dive_ (2025 Edition) - Nigel Poulton
