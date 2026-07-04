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
│   ├── multistage/       # 4-stage build: base -> deps -> test -> final
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
├── compose/              # (planned) Docker Compose, multi-service stacks
└── security/             # (planned) Non-root, capabilities, secrets
```

`basics`, `images`, `image-inspection`, `networks`, `storage`, and `performance` are complete.

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
