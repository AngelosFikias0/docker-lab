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
├── 00-basics/                # Container lifecycle, core CLI, image fundamentals
│   ├── docker-run/           # 10 runtime flag exercises
│   └── images-build/         # Annotated Dockerfile, minimal stdlib app
│
├── 01-images/                # Image creation, layering, and optimization
│   ├── multistage/           # 4-stage build: base -> deps -> test -> final
│   ├── distroless/           # Flask on distroless, no shell, minimal attack surface
│   └── nginx-example/        # Static site via custom nginx config
```

Modules 00 and 01 are complete. Modules 02-07 are planned.

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
