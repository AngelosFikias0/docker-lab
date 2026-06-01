# Images

A lab for understanding and experimenting with Docker image internals — how images are structured, stored, and executed.

---

## What Is a Docker Image

A Docker image is a **read-only, ordered stack of layers** plus metadata. It is not a single file. It is a content-addressable collection of compressed tarballs and JSON manifests assembled by the container runtime at pull or build time.

---

## Build Flow: Dockerfile → Image

Every Dockerfile instruction maps to a specific action the builder takes. Understanding what each instruction does at the layer level removes all ambiguity about size, cache, and behavior.

### Instruction Reference

| Instruction | Produces a Layer | What It Does |
|---|---|---|
| `FROM` | No (inherits) | Seeds the build with an existing image's layer stack. `FROM scratch` starts with zero layers. |
| `RUN` | **Yes** | Executes a command in a temporary container, snapshots the resulting filesystem diff as a new layer. |
| `COPY` | **Yes** | Copies files from the build context into the image filesystem. Hashes source files for cache key. |
| `ADD` | **Yes** | Like `COPY` but also decompresses local tarballs and fetches remote URLs. Prefer `COPY` unless you need those features. |
| `ENV` | No | Writes key-value pairs into the image config. Available at build time and runtime. |
| `ARG` | No | Build-time variable only. Not present in the final image config. Invalidates cache when its value changes. |
| `WORKDIR` | No | Sets working directory in config. Creates the directory if absent (no layer if it already exists). |
| `USER` | No | Sets the default UID/GID in config. No filesystem change. |
| `EXPOSE` | No | Documents intent only. Does not open ports. |
| `VOLUME` | No | Declares a mount point in config. The directory is created at container start, not build time. |
| `ENTRYPOINT` | No | Sets the fixed executable. Config-only. |
| `CMD` | No | Sets default arguments to `ENTRYPOINT`, or the default command if no `ENTRYPOINT` is set. Config-only. |
| `LABEL` | No | Adds arbitrary metadata to the image config. |
| `ONBUILD` | No | Registers a trigger that fires when this image is used as a base in another build. |
| `HEALTHCHECK` | No | Embeds a health probe command in the image config. |
| `SHELL` | No | Overrides the default shell used for `RUN`, `CMD`, `ENTRYPOINT` in shell form. |

### What "No layer" Actually Means

Instructions that produce no layer still produce a **history entry** in `config.json`. They are recorded in the build history with `empty_layer: true`. They affect runtime behavior through the image config but add zero bytes to the filesystem.

```bash
docker image history <image> --no-trunc
# Shows all instructions, including zero-size config-only ones
```

### Build Execution Model

```
docker build .
      │
      ▼
1. Read Dockerfile
2. Send build context to daemon (or BuildKit)
      │
      ├─ FROM <base>
      │     └─ Pull base image layers if not cached
      │        Seed layer stack with base diff_ids
      │
      ├─ RUN <cmd>
      │     └─ Spawn container from current layer stack
      │        Execute command
      │        Snapshot filesystem diff → new layer tar
      │        Compute SHA256 (diff_id)
      │        Append to layer stack
      │
      ├─ COPY <src> <dst>
      │     └─ Hash source files from build context
      │        Check cache: hit → reuse layer, miss → create new layer tar
      │        Append to layer stack
      │
      ├─ ENV / ARG / WORKDIR / USER / CMD / ENTRYPOINT ...
      │     └─ Write to image config only, no new layer
      │
      └─ Commit
            └─ Serialize config.json (with all diff_ids + history)
               Compress each new layer → gzip tar
               Build manifest.json referencing config + compressed layers
               Tag and store in local image store
```

### Key Implications

**`RUN apt-get install && apt-get clean` must be a single instruction.**  
Running clean in a separate `RUN` creates a new layer on top. The package cache bytes are already committed to the prior layer and cannot be removed retroactively.

```dockerfile
# BAD — cache persists in layer N, clean has no effect on size
RUN apt-get update && apt-get install -y curl
RUN apt-get clean

# GOOD — single layer, cache never committed
RUN apt-get update && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/*
```

**`ADD <url>` bypasses the build cache.**  
Remote URL fetches always re-execute. Use `RUN curl` with explicit cache control instead, or use BuildKit cache mounts.

**`ARG` before `FROM` is special.**  
`ARG` declared before the first `FROM` is scoped to the `FROM` line only (for parameterizing the base image tag). It is not available in subsequent instructions unless re-declared.

```dockerfile
ARG BASE_TAG=3.12-slim
FROM python:${BASE_TAG}   # works
RUN echo ${BASE_TAG}      # empty — ARG scope ended at FROM

ARG BASE_TAG              # re-declare to use below FROM
RUN echo ${BASE_TAG}      # now works
```

---

## Image Structure

```
Image
├── Manifest (manifest.json)          # Index of layers + config reference
├── Image Config (config.json)        # Env, Cmd, entrypoint, history, OS/arch
└── Layers (layer.tar.gz × N)         # Ordered filesystem diffs (tarballs)
```

### Layer

Each `RUN`, `COPY`, and `ADD` instruction in a Dockerfile produces a new layer. A layer is a **tar archive of filesystem changes** relative to the previous layer — additions, modifications, and deletions (whiteout files).

```
Layer N-1:  /usr/bin/python3
Layer N:    /app/requirements.txt  ← COPY instruction
Layer N+1:  /usr/lib/python3/...   ← RUN pip install
```

Deletions are represented as **whiteout files**: `.wh.<filename>` or `.wh..wh..opq` (opaque whiteout, hides entire directory).

### Image Config (`config.json`)

Contains everything needed to run the container:

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
    "diff_ids": [
      "sha256:abc123...",   ← uncompressed layer digest
      "sha256:def456..."
    ]
  },
  "history": [...]          ← per-instruction metadata (including empty layers)
}
```

### Manifest (`manifest.json`)

The manifest is what the registry and runtime use to locate the image:

```json
{
  "schemaVersion": 2,
  "mediaType": "application/vnd.docker.distribution.manifest.v2+json",
  "config": {
    "mediaType": "application/vnd.docker.container.image.v1+json",
    "digest": "sha256:...",
    "size": 7023
  },
  "layers": [
    {
      "mediaType": "application/vnd.docker.image.rootfs.diff.tar.gzip",
      "digest": "sha256:...",   ← compressed layer digest (used for pull/push)
      "size": 31379712
    }
  ]
}
```

> `diff_ids` in config = **uncompressed** SHA256.  
> `digest` in manifest = **compressed** SHA256.  
> They will never match. This is intentional.

---

## Union Filesystem (OverlayFS)

At container runtime, Docker stacks image layers using **OverlayFS**:

```
Container writable layer  ← upperdir  (ephemeral, destroyed on stop)
─────────────────────────
Image Layer N             ← lowerdir (read-only)
Image Layer N-1           ← lowerdir (read-only)
...
Image Layer 0             ← lowerdir (read-only)
```

OverlayFS merges all lowerdirs into a single unified view. Writes go to the upperdir only (copy-on-write). The image layers are never modified.

```bash
# Inspect the overlay mount of a running container
docker inspect <container_id> | jq '.[0].GraphDriver.Data'

# Output:
# {
#   "LowerDir":  "/var/lib/docker/overlay2/<id>/diff:...",
#   "MergedDir": "/var/lib/docker/overlay2/<id>/merged",
#   "UpperDir":  "/var/lib/docker/overlay2/<id>/diff",
#   "WorkDir":   "/var/lib/docker/overlay2/<id>/work"
# }
```

---

## Content Addressability

Every layer and config is identified by its **SHA256 digest**. Docker never stores duplicates. If two images share a base, they reference the same layer blobs on disk.

```bash
# Verify layer digests
docker image inspect <image> | jq '.[0].RootFS.Layers'

# Raw layer content on disk
ls /var/lib/docker/overlay2/
```

---

## Inspect Commands

```bash
# Full image metadata
docker image inspect <image>

# Layer history with sizes
docker image history <image>

# Export image as tar and inspect raw structure
docker save <image> | tar -xvC ./unpacked/

# Contents of unpacked image:
# manifest.json
# <config_digest>.json
# <layer_digest>/
#   └── layer.tar

# Decompress and inspect a specific layer
tar -xvf unpacked/<layer>/layer.tar

# Interactive layer explorer
dive <image>
```

---

## Layer Caching

The Docker build cache is keyed on:

1. **Base image identity** — `FROM` digest
2. **Instruction string** — exact text of the Dockerfile instruction
3. **File content hash** — for `COPY` / `ADD`, SHA256 of the source files

Cache is **invalidated from the point of change downward**. Every instruction after a cache miss rebuilds.

```dockerfile
# Order by volatility: stable → volatile
COPY requirements.txt .          # rarely changes → cached
RUN pip install -r requirements.txt
COPY . .                         # changes every commit → cache busted here only
```

**BuildKit cache mounts** (bypass layer cache, persist across builds):

```dockerfile
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install -r requirements.txt
```

---

## References

- [OCI Image Spec](https://github.com/opencontainers/image-spec)
- [Docker Image Manifest v2 Schema](https://docs.docker.com/registry/spec/manifest-v2-2/)
- [OverlayFS — kernel docs](https://www.kernel.org/doc/html/latest/filesystems/overlayfs.html)
- [Dive — layer explorer](https://github.com/wagoodman/dive)
