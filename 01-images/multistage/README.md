# Docker — Complete Reference

Everything covered in this session. Each section maps to a real decision in the Dockerfile.

---

## 1. How Docker Images Work

An image is a stack of **read-only layers**. Each `RUN`, `COPY`, `ADD` instruction creates one layer.

```
Layer 4: COPY . .               ← your code
Layer 3: pip install            ← dependencies
Layer 2: apt-get install gcc    ← system deps
Layer 1: python:3.13-slim       ← base image
```

At runtime a thin **read-write layer** is added on top. The container writes there. The image layers never change.

Docker uses **OverlayFS** to union all layers into a single filesystem view. Reading a file walks layers top-down and returns the first match.

---

## 2. Layers Are Additive — Deletions Don't Remove Bytes

This is the most common Docker mistake.

```dockerfile
# WRONG — 200MB still ships
RUN apt-get install -y gcc        # layer A: +200MB
RUN rm -rf /var/lib/apt/lists/*   # layer B: whiteout marker, bytes still in A

# CORRECT — cleanup in same layer
RUN apt-get install -y gcc && \
    rm -rf /var/lib/apt/lists/*   # one layer, bytes never persisted
```

A "deletion" in a later layer creates a **whiteout file** — a marker that hides the file from above. The actual bytes still exist in the earlier layer and still count toward image size.

**Rule**: chain commands that belong together in a single `RUN`.

---

## 3. Layer Cache Invalidation

Docker caches layers by hash. Any change to a layer **invalidates all layers below it**.

```
Layer 1: FROM python          cached
Layer 2: COPY requirements    cached     ← requirements.txt unchanged
Layer 3: pip install          CACHED     ← skipped entirely
Layer 4: COPY . .             REBUILT    ← main.py changed
Layer 5: CMD                  REBUILT
```

**Rule**: order layers by change frequency — least changed at top, most changed at bottom.

```dockerfile
COPY requirements.txt .       # changes occasionally
RUN pip install               # cached until requirements changes
COPY . .                      # changes constantly — always last
```

---

## 4. Multi-Stage Builds

Multiple `FROM` instructions in one Dockerfile. Each stage starts fresh. Only what you explicitly `COPY --from` carries forward.

```dockerfile
FROM python:3.13-slim AS builder
RUN apt-get install -y gcc
RUN pip install -r requirements.txt   # gcc, apt cache, wheels — all here

FROM python:3.13-slim AS final
COPY --from=builder /usr/local/lib/python3.13/site-packages .
# gcc, apt cache, build tools — all discarded
```

**Result**: final image contains only what you need to run. Not what you need to build.

**Use stages for**:

- Separating build tools from runtime
- Running tests as a CI gate
- Debugging with `--target`

---

## 5. BuildKit Mount Cache

```dockerfile
# syntax=docker/dockerfile:1

RUN --mount=type=cache,target=/root/.cache \
    pip install -r requirements.txt
```

`/root/.cache` is where pip stores downloaded wheel files.

|                             | Without mount cache | With mount cache      |
| --------------------------- | ------------------- | --------------------- |
| First build                 | Downloads from PyPI | Downloads from PyPI   |
| Subsequent builds           | Downloads again     | Reads from host cache |
| Cache survives `--no-cache` | No                  | **Yes**               |
| Ships in image              | N/A                 | **No**                |
| Invalidated by file changes | N/A                 | **Never**             |

The mount exists only during the `RUN` step. It does not become a layer. It does not ship in the image. It persists on the host between builds.

**In CI**: mount cache is lost when the runner is destroyed. Use registry-based caching:

```yaml
- uses: docker/build-push-action@v5
  with:
    cache-from: type=gha
    cache-to: type=gha,mode=max
```

---

## 6. Base Image Size

```bash
python:3.13          # ~1.1GB — full Debian + build tools
python:3.13-slim     # ~200MB — Debian minimal
python:3.13-alpine   # ~50MB  — Alpine Linux
scratch              # 0MB    — empty, for static binaries only
```

For Python: use `slim`. Alpine can cause issues with packages that need glibc (psycopg2, numpy, etc).

---

## 7. ENTRYPOINT vs CMD

|                                 | ENTRYPOINT       | CMD                     |
| ------------------------------- | ---------------- | ----------------------- |
| Purpose                         | Fixed executable | Default arguments       |
| Overridden by `docker run args` | No               | Yes — replaced entirely |
| Override flag                   | `--entrypoint`   | just pass args          |

```dockerfile
ENTRYPOINT ["python3"]     # always runs python3
CMD ["main.py"]            # default script, overridable
```

```bash
docker run myimage                  # python3 main.py
docker run myimage other.py         # python3 other.py
docker run --entrypoint bash myimage # bash (entrypoint replaced)
```

**Always use exec form** `["python3", "main.py"]`, never shell form `python3 main.py`.

Shell form runs as `/bin/sh -c python3 main.py`. PID 1 is the shell. Your app never receives SIGTERM from `docker stop` or Kubernetes — gets hard-killed after grace period instead.

---

## 8. PID 1 and Signal Handling

```bash
# Exec form — correct
docker exec app ps
# PID 1 = python3   ← receives SIGTERM, can shut down gracefully

# Shell form — wrong
docker exec app ps
# PID 1 = /bin/sh   ← receives SIGTERM, ignores or passes it wrong
# PID 2 = python3   ← never receives signal
```

In Kubernetes: `terminationGracePeriodSeconds` is wasted if PID 1 is a shell.

---

## 9. Non-Root Execution

Default Docker runs as root. Root in container = root on host if container escapes.

```dockerfile
USER 65534:65534   # nobody — no home dir, no shell, no privileges
```

In Kubernetes enforce it at the cluster level:

```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 65534
```

---

## 10. Debugging Builds

**Classic builder**: failed layer hash is accessible, run it directly.

**BuildKit**: intermediate layers not exported to daemon. Use `--target` instead.

```dockerfile
FROM node:18 AS base
# ... working steps

FROM base AS broken
RUN npm installer   # ← fails here
```

```bash
# Build only up to base — last known good state
docker build --target base -t myapp:debug .

# Shell in at the failure point
docker run --rm -it myapp:debug /bin/bash

# Reproduce failure manually, find fix, exit
root@container:/# npm installer
# see exact error
root@container:/# npm install
# works — now fix Dockerfile
```

**Stage naming convention for debuggability**:

| Stage   | Purpose     | `--target` use         |
| ------- | ----------- | ---------------------- |
| `base`  | System deps | Verify apt installs    |
| `deps`  | App deps    | Debug pip/npm failures |
| `test`  | Test suite  | CI gate                |
| `final` | Production  | Never debug here       |

---

## 11. `docker build` Structure

```bash
docker build [OPTIONS] PATH

docker build \
  -t name:tag \              # image name:tag (repeatable for multiple tags)
  -f Dockerfile.prod \       # dockerfile path
  --target stagename \       # stop at named stage
  --build-arg KEY=VALUE \    # inject into ARG instruction
  --no-cache \               # ignore layer cache
  --platform linux/amd64 \  # target architecture
  --progress=plain \         # full uncompressed build output
  .                          # build context — always last
```

`.dockerignore` controls what gets sent to the daemon as build context. Always set it.

```
.git
__pycache__
*.pyc
*.log
.env
tests/
```

---

## 12. `docker run` Structure

```bash
docker run [OPTIONS] IMAGE [COMMAND] [ARGS]
```

**Critical**: flags must come before the image name. Everything after the image name is passed to the container.

```bash
docker run -it myimage        # correct — -it consumed by docker
docker run myimage -it        # wrong   — -it sent to container as argument
```

```bash
docker run \
  -d \                        # detached
  -it \                       # interactive + tty
  --rm \                      # delete on exit
  --name mycontainer \        # assign name
  -p 8080:80 \                # host:container port
  -v $(pwd):/app \            # host:container volume
  -e KEY=VALUE \              # environment variable
  --memory=128m \             # memory limit
  --cpus=0.5 \                # cpu limit
  --entrypoint /bin/bash \    # override entrypoint
  --network mynetwork \       # network
  myimage:tag \               # image
  python3 other.py            # args passed to entrypoint
```

---

## 13. Inspection and Logs

```bash
# Image metadata — entrypoint, cmd, env, layers, size
docker inspect myimage

# Layer history — each instruction + size contribution
docker history myimage

# Interactive layer explorer
docker run --rm -it \
  -v /var/run/docker.sock:/var/run/docker.sock \
  wagoodman/dive myimage

# Container stdout/stderr
docker logs mycontainer
docker logs -f mycontainer          # follow
docker logs --tail=50 mycontainer   # last 50 lines

# Shell into running container
docker exec -it mycontainer /bin/bash

# Disk usage
docker system df
docker system df -v
```

---

## 14. Where Things Live on the Host

```
/var/lib/docker/
├── overlay2/       ← layer data (actual file contents)
├── image/          ← image metadata and layer manifests
├── containers/     ← per-container config and logs
└── volumes/        ← named volumes

/var/lib/docker/buildkit/cache/   ← BuildKit mount cache
```

For k3s (containerd, not Docker):

```
/var/lib/rancher/k3s/agent/containerd/
```

Two separate caches. `docker build` and `kubectl` image pulls do not share layers.

---

## 15. Cleanup

```bash
docker stop mycontainer && docker rm mycontainer
docker rmi myimage

docker builder prune        # build cache only
docker image prune          # dangling images only
docker system prune -af     # everything unused
```

---

## The Mental Model

```
Dockerfile = recipe
Image      = snapshot (immutable, layered)
Container  = running instance of an image (adds thin RW layer)
Layer      = filesystem diff, identified by content hash
Cache      = reuse layers whose hash hasn't changed
```

Every optimization follows from one principle: **only rebuild what actually changed.**
