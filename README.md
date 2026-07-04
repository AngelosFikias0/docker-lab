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
├── compose/              # (planned) Docker Compose, multi-service stacks
│
├── docs/                 # Reference notes on internals and theory
│   ├── linux-basics.md   # Processes, namespaces, cgroups, syscalls
│   ├── containers.md     # Fundamentals, history, lifecycle, identity files
│   ├── docker.md         # Architecture, logging, signals, health checks, k8s integration
│   ├── networking.md     # Bridge, veth, DNS, NAT, overlay, k8s mapping
│   └── operations.md     # Container management, restart policies, cleanup
│
├── image-inspection/     # Pulling images apart: history, inspect, save, dive
│   └── layer-analysis/   # Hands-on inspection of real images
│
├── images/               # Image creation, layering, and optimization
│   ├── multistage/       # 4-stage build: base -> deps -> test -> final
│   ├── distroless/       # Flask on distroless, no shell, minimal attack surface
│   └── nginx-example/    # Static site via custom nginx config
│
├── networks/             # Container networking: bridge, DNS, isolation
│   ├── bridge-network/   # Default vs custom bridge, veth pairs, iptables
│   └── dns-resolution/   # Embedded DNS at 127.0.0.11, aliases, isolation
│
├── observability/        # Metrics pipeline: cAdvisor + Prometheus + Grafana
│   ├── prometheus/       # Scrape config, alert rules (OOM, throttle, memory)
│   └── grafana/          # Auto-provisioned datasource and dashboard
│
├── performance/          # Resource limits, cgroup internals, throttling, OOM
│   ├── resource-limits/  # CPU caps, memory limits, I/O throttling, docker stats
│   └── cpu-memory-stress/# Throttling observation, OOM trigger, share contention
│
├── security/             # (planned) Non-root, capabilities, secrets
│
├── storage/              # Persistent data: volumes, bind mounts, tmpfs, overlay2
│   ├── volumes/          # Named volume lifecycle, persistence, backup, sharing
│   └── bind-mounts/      # Config injection, dev workflow, tmpfs
│
└── use-cases/            # Problem-solution reference by scenario
    ├── debugging.md      # Container exits, OOM, network issues, no-shell images
    ├── build-optimization.md  # Layer ordering, cache mounts, multi-stage, .dockerignore
    ├── web-app-stack.md  # Reverse proxy + backend + DB, health checks, restart policy
    ├── ci-cd.md          # DinD vs socket, registry cache, multi-arch, tagging
    ├── zero-downtime.md  # Graceful shutdown, health checks, blue-green, canary
    └── secrets.md        # Env vars, mounted files, Docker secrets, Vault, k8s
```

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
