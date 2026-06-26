# Images

A lab for understanding and experimenting with Docker image internals: how images are structured, stored, and executed.

---

## What Is a Docker Image

A Docker image is a **read-only, ordered stack of layers** plus metadata. It is not a single file. It is a content-addressable collection of compressed tarballs and JSON manifests assembled by the container runtime at pull or build time.

---

## Build Flow: Dockerfile -> Image

Every Dockerfile instruction maps to a specific action the builder takes. Understanding what each instruction does at the layer level removes all ambiguity about size, cache, and behavior.

### Instruction Reference

| Instruction   | Produces a Layer | What It Does                                                                                                            |
| ------------- | ---------------- | ----------------------------------------------------------------------------------------------------------------------- |
| `FROM`        | No (inherits)    | Seeds the build with an existing image's layer stack. `FROM scratch` starts with zero layers.                           |
| `RUN`         | **Yes**          | Executes a command in a temporary container, snapshots the resulting filesystem diff as a new layer.                    |
| `COPY`        | **Yes**          | Copies files from the build context into the image filesystem. Hashes source files for cache key.                       |
| `ADD`         | **Yes**          | Like `COPY` but also decompresses local tarballs and fetches remote URLs. Prefer `COPY` unless you need those features. |
| `ENV`         | No               | Writes key-value pairs into the image config. Available at build time and runtime.                                      |
| `ARG`         | No               | Build-time variable only. Not present in the final image config. Invalidates cache when its value changes.              |
| `WORKDIR`     | No               | Sets working directory in config. Creates the directory if absent (no layer if it already exists).                      |
| `USER`        | No               | Sets the default UID/GID in config. No filesystem change.                                                               |
| `EXPOSE`      | No               | Documents intent only. Does not open ports.                                                                             |
| `VOLUME`      | No               | Declares a mount point in config. The directory is created at container start, not build time.                          |
| `ENTRYPOINT`  | No               | Sets the fixed executable. Config-only.                                                                                 |
| `CMD`         | No               | Sets default arguments to `ENTRYPOINT`, or the default command if no `ENTRYPOINT` is set. Config-only.                  |
| `LABEL`       | No               | Adds arbitrary metadata to the image config.                                                                            |
| `ONBUILD`     | No               | Registers a trigger that fires when this image is used as a base in another build.                                      |
| `HEALTHCHECK` | No               | Embeds a health probe command in the image config.                                                                      |
| `SHELL`       | No               | Overrides the default shell used for `RUN`, `CMD`, `ENTRYPOINT` in shell form.                                          |

### What "No Layer" Actually Means

Instructions that produce no layer still produce a **history entry** in `config.json`. They are recorded in the build history with `empty_layer: true`. They affect runtime behavior through the image config but add zero bytes to the filesystem.

```bash
docker image history <image> --no-trunc
# Shows all instructions, including zero-size config-only ones
```

### Build Execution Model

```
docker build .
      |
      v
1. Read Dockerfile
2. Send build context to daemon (or BuildKit)
      |
      +- FROM <base>
      |     +- Pull base image layers if not cached
      |        Seed layer stack with base diff_ids
      |
      +- RUN <cmd>
      |     +- Spawn container from current layer stack
      |        Execute command
      |        Snapshot filesystem diff -> new layer tar
      |        Compute SHA256 (diff_id)
      |        Append to layer stack
      |
      +- COPY <src> <dst>
      |     +- Hash source files from build context
      |        Check cache: hit -> reuse layer, miss -> create new layer tar
      |        Append to layer stack
      |
      +- ENV / ARG / WORKDIR / USER / CMD / ENTRYPOINT ...
      |     +- Write to image config only, no new layer
      |
      +- Commit
            +- Serialize config.json (with all diff_ids + history)
               Compress each new layer -> gzip tar
               Build manifest.json referencing config + compressed layers
               Tag and store in local image store
```

### Key Implications

**`RUN apt-get install && apt-get clean` must be a single instruction.**
Running clean in a separate `RUN` creates a new layer on top. The package cache bytes are already committed to the prior layer and cannot be removed retroactively.

```dockerfile
# BAD: cache persists in layer N, clean has no effect on size
RUN apt-get update && apt-get install -y curl
RUN apt-get clean

# GOOD: single layer, cache never committed
RUN apt-get update && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/*
```

**`ADD <url>` bypasses the build cache.**
Remote URL fetches always re-execute. Use `RUN curl` with explicit cache control instead, or use BuildKit cache mounts.

**`ARG` before `FROM` is special.**
`ARG` declared before the first `FROM` is scoped to the `FROM` line only. Not available in subsequent instructions unless re-declared.

```dockerfile
ARG BASE_TAG=3.12-slim
FROM python:${BASE_TAG}   # works
RUN echo ${BASE_TAG}      # empty, ARG scope ended at FROM

ARG BASE_TAG              # re-declare to use below FROM
RUN echo ${BASE_TAG}      # now works
```

---

## Image Structure

```
Image
+-- Manifest (manifest.json)          # Index of layers + config reference
+-- Image Config (config.json)        # Env, Cmd, entrypoint, history, OS/arch
+-- Layers (layer.tar.gz x N)         # Ordered filesystem diffs (tarballs)
```

### Layer

Each `RUN`, `COPY`, and `ADD` instruction produces a new layer. A layer is a **tar archive of filesystem changes** relative to the previous layer: additions, modifications, and deletions (whiteout files).

```
Layer N-1:  /usr/bin/python3
Layer N:    /app/requirements.txt  <- COPY instruction
Layer N+1:  /usr/lib/python3/...   <- RUN pip install
```

Deletions are represented as whiteout files: `.wh.<filename>` or `.wh..wh..opq` (opaque whiteout, hides entire directory).

### Image Config (`config.json`)

```json
{
  "architecture": "amd64",
  "os": "linux",
  "config": {
    "Env": ["PATH=/usr/local/bin:/usr/bin:/bin"],
    "Cmd": ["/bin/sh"],
    "WorkingDir": "/app",
    "Entrypoint": null,
    "ExposedPorts": { "8080/tcp": {} }
  },
  "rootfs": {
    "type": "layers",
    "diff_ids": ["sha256:abc123...", "sha256:def456..."]
  }
}
```

### Manifest (`manifest.json`)

```json
{
  "schemaVersion": 2,
  "config": { "digest": "sha256:...", "size": 7023 },
  "layers": [{ "digest": "sha256:...", "size": 31379712 }]
}
```

> `diff_ids` in config = **uncompressed** SHA256.
> `digest` in manifest = **compressed** SHA256.
> They will never match. This is intentional.

---

## Union Filesystem (OverlayFS)

```
Container writable layer  <- upperdir  (ephemeral, destroyed on stop)
-------------------------
Image Layer N             <- lowerdir (read-only)
Image Layer N-1           <- lowerdir (read-only)
Image Layer 0             <- lowerdir (read-only)
```

Writes go to upperdir only (copy-on-write). Image layers are never modified.

```bash
docker inspect <container_id> | jq '.[0].GraphDriver.Data'
```

---

## Layer Caching

Cache is keyed on base image digest, instruction string, and file content hash. **Invalidated from the point of change downward.**

```dockerfile
# Order by volatility: stable -> volatile
COPY requirements.txt .              # rarely changes, gets cached
RUN pip install -r requirements.txt
COPY . .                             # changes every commit, always last
```

BuildKit cache mounts: persist across builds, never ship in image.

```dockerfile
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install -r requirements.txt
```

---

## Image Optimization

### 1. Minimal base image

```
python:3.13          ~1.1GB  full Debian + build tools
python:3.13-slim     ~200MB  Debian minimal
python:3.13-alpine   ~50MB   Alpine (watch for glibc issues)
scratch              0MB     static binaries only
```

### 2. Multi-stage builds

Builder stages do the heavy work. Final stage takes only the output. Build tools never ship.

```dockerfile
FROM python:3.13-slim AS builder
RUN pip install -r requirements.txt

FROM python:3.13-slim AS final
COPY --from=builder /usr/local/lib/python3.13/site-packages \
                    /usr/local/lib/python3.13/site-packages
```

### 3. Non-root execution

```dockerfile
USER 65534:65534   # nobody, no home, no shell, no privileges
```

### 4. Exec form entrypoint

Shell form makes `/bin/sh` PID 1. Your app never receives SIGTERM.

```dockerfile
ENTRYPOINT ["python3", "main.py"]   # correct, your process is PID 1
ENTRYPOINT python3 main.py          # wrong, /bin/sh is PID 1
```

---

## Inspect Commands

```bash
docker image inspect <image>                   # full metadata
docker image history <image>                   # layer history + sizes
docker save <image> | tar -xvC ./unpacked/     # raw image structure
dive <image>                                   # interactive layer explorer
```

---

## Labs

```
01-images/
+-- multistage/               # Production-grade Python Flask image
|   +-- Dockerfile            # 4-stage build: base -> deps -> test -> final
|   +-- main.py               # Flask app: /health and / endpoints
|   +-- requirements.txt      # Production deps: flask, gunicorn
|   +-- requirements-dev.txt  # Dev deps: pytest
|   +-- tests/
|       +-- test_main.py      # pytest suite, CI gate in test stage
+-- distroless/               # Flask app on a distroless base, no shell
|   +-- Dockerfile            # 2-stage build: builder + distroless final
|   +-- main.py               # Flask app: /health and / endpoints
|   +-- requirements.txt      # flask, gunicorn
+-- nginx-example/            # Static site served via nginx
    +-- Dockerfile
    +-- nginx.conf
    +-- html/
        +-- index.html
```

### multistage

```bash
docker build -t multistage:latest .
docker run --rm -p 8080:8080 multistage:latest
curl localhost:8080/health

# Debug: shell into deps stage
docker build --target deps -t multistage:debug .
docker run --rm -it multistage:debug /bin/bash

# CI gate: test stage only
docker build --target test .
```

### distroless

```bash
docker build -t distroless-example:latest .
docker run --rm -p 8080:8080 distroless-example:latest
curl localhost:8080/health

# Debug: builder stage has a full shell
docker build --target builder -t distroless-example:builder .
docker run --rm -it distroless-example:builder /bin/bash
```

### nginx-example

```bash
docker build -t nginx-example:0.0.1 .
docker run --rm -p 8080:80 nginx-example:0.0.1
```

---

## References

- [OCI Image Spec](https://github.com/opencontainers/image-spec)
- [Docker Image Manifest v2 Schema](https://docs.docker.com/registry/spec/manifest-v2-2/)
- [OverlayFS](https://www.kernel.org/doc/html/latest/filesystems/overlayfs.html)
- [Dive](https://github.com/wagoodman/dive)
