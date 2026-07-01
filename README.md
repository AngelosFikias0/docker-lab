# Docker Lab

A structured hands-on Docker engineering lab.

Not a collection of examples. A progressive learning system moving from Docker fundamentals to multi-service architectures to production container systems.

---

## Purpose

Build deep practical competence in:

- Container lifecycle management
- Image creation and optimization
- Container networking
- Persistent storage and volumes
- Multi-service system design with Docker Compose
- Security fundamentals in containerized environments
- Performance constraints and resource control

Aligned with real-world DevOps and Platform Engineering workflows.

---

## Structure

Each folder is a conceptual layer. Work through them in order.

```
Docker-Lab/
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
│   ├── bridge-network/   # Default vs custom bridge
│   └── dns-resolution/   # Embedded DNS, aliases, cross-network isolation
│
├── storage/              # (planned) Named volumes, bind mounts, tmpfs
├── compose/              # (planned) Docker Compose, multi-service stacks
├── multi-service/        # (planned) API + DB + reverse proxy
├── security/             # (planned) Non-root, capabilities, secrets
└── performance/          # (planned) Resource limits, cgroup constraints
```

`basics`, `images`, `image-inspection`, and `networks` are complete. The rest are planned.

---

## Prerequisites

- Docker Engine 24+ (BuildKit enabled by default)
- `curl` for testing endpoints

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

**Security**

- [Docker security overview](https://docs.docker.com/engine/security/)
- [Rootless mode](https://docs.docker.com/engine/security/rootless/)
- [Seccomp profiles](https://docs.docker.com/engine/security/seccomp/)

**Runtime and performance**

- [Resource constraints](https://docs.docker.com/engine/containers/resource_constraints/)
- [Runtime metrics](https://docs.docker.com/engine/containers/runmetrics/)
