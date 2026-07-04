# Build Optimization

Patterns for fast builds and small images.

---

## Layer ordering: stable layers first

Docker invalidates the cache at the first changed layer and rebuilds everything below it. Order layers from least to most frequently changed.

**Bad:**

```dockerfile
COPY . .                   # copies everything — any file change busts the cache here
RUN pip install -r requirements.txt   # reinstalls deps every time
```

**Good:**

```dockerfile
COPY requirements.txt .    # only changes when deps change
RUN pip install -r requirements.txt
COPY . .                   # application code — changes often, but deps are cached
```

Rule: `COPY requirements/package files` -> `RUN install` -> `COPY source code`.

---

## Multi-stage builds

Keep build tools out of the final image. Build in one stage, copy only the artifact to a minimal final stage.

```dockerfile
FROM golang:1.22 AS builder
WORKDIR /app
COPY . .
RUN CGO_ENABLED=0 go build -o server .

FROM scratch
COPY --from=builder /app/server /server
ENTRYPOINT ["/server"]
```

Final image is just the binary. No Go toolchain, no OS packages.

---

## BuildKit cache mounts

Mount a persistent cache directory into `RUN` steps. The cache survives across builds without being committed to the image layer.

```dockerfile
# syntax=docker/dockerfile:1
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install -r requirements.txt

RUN --mount=type=cache,target=/root/.npm \
    npm ci
```

Package manager download caches are retained between builds. Particularly valuable in CI where reinstalling 200 packages on every push is the main bottleneck.

---

## .dockerignore

Prevents unnecessary files from entering the build context. A large build context (e.g. including `node_modules`, `.git`, test fixtures) slows every build regardless of caching.

```dockerignore
.git
node_modules
__pycache__
*.pyc
.env
.env.*
tests/
*.log
dist/
```

Check context size: `docker build` prints `Sending build context to Docker daemon X MB`. If it's large, your `.dockerignore` needs work.

---

## Minimize layers in RUN

Each `RUN` creates a layer. Chaining commands with `&&` keeps cleanup in the same layer — deletions in a later layer don't reclaim space already committed to OverlayFS.

```dockerfile
# creates 3 layers, apt cache remains in layer 1 even after rm in layer 3
RUN apt-get update
RUN apt-get install -y curl
RUN rm -rf /var/lib/apt/lists/*

# correct: one layer, cleanup happens before the layer is sealed
RUN apt-get update && \
    apt-get install -y --no-install-recommends curl && \
    rm -rf /var/lib/apt/lists/*
```

---

## Use --no-install-recommends

Apt installs recommended packages by default — often 2-3x more packages than you need.

```dockerfile
RUN apt-get install -y --no-install-recommends <package>
```

---

## Pin base image versions

Unpinned base images (`FROM python:3`) rebuild from a different layer on every pull when the upstream updates, busting your cache.

```dockerfile
# unpinned — upstream digest can change silently
FROM python:3.13-slim

# pinned — deterministic, cache-stable
FROM python:3.13.3-slim-bookworm
```

---

## Image size: choose the right base

| Base | Approx size | Use when |
| ---- | ----------- | -------- |
| `ubuntu` / `debian` | 100-200 MB | Need full apt ecosystem |
| `-slim` variants | 50-100 MB | Most production Python/Node apps |
| `alpine` | 5-10 MB | Shell scripts, CLIs, anything that doesn't need glibc |
| `distroless` | 2-20 MB | No shell required, max attack surface reduction |
| `scratch` | 0 MB | Static binaries only (Go, Rust) |

---

## Inspect what's in your image

```bash
docker history myimage              # layers with sizes
docker image inspect myimage        # full config JSON
dive myimage                        # interactive layer explorer (requires dive)
```

`docker history` shows which instruction created each layer and how much space it takes. If a layer is unexpectedly large, it usually means either build artifacts weren't cleaned up or a `COPY` included unwanted files.
