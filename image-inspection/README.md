# Image Inspection

Pulling images apart: reading their config, measuring their layers, understanding what is actually inside before you ship it.

---

## docker image history

Shows every instruction that built the image, in order, with the size each one added.

```bash
docker image history <image>
docker image history <image> --no-trunc          # full instruction text, not truncated
docker image history <image> --format "table {{.CreatedBy}}\t{{.Size}}"
```

The `CREATED BY` column shows the exact `RUN`, `COPY`, or `ADD` instruction. Zero-size rows are config-only instructions: `ENV`, `WORKDIR`, `USER`, `EXPOSE`, `CMD`, `ENTRYPOINT`.

---

## docker image inspect

Returns the full image config as JSON: entrypoint, cmd, environment variables, exposed ports, labels, architecture, OS, and the list of layer digests.

```bash
docker image inspect <image>                                  # full JSON
docker image inspect <image> --format '{{ .Config.Entrypoint }}'
docker image inspect <image> --format '{{ .Config.Env }}'
docker image inspect <image> --format '{{ .Config.ExposedPorts }}'
docker image inspect <image> --format '{{ .Config.User }}'
docker image inspect <image> --format '{{ .Architecture }}'
docker image inspect <image> --format '{{ len .RootFS.Layers }}'   # layer count
docker image inspect <image> --format '{{ .RootFS.Layers }}'       # layer digests
```

---

## docker save: the raw image on disk

`docker save` exports an image to a tar file. The tar is exactly what the registry stores and what the daemon pulls. Unpacking it reveals the actual structure.

```bash
docker save <image> -o image.tar
tar tf image.tar
```

The tar contains:

```
manifest.json              <- lists layers in order and points to the config file
<sha256>.json              <- image config: env, cmd, entrypoint, history, layer diff_ids
<layer-sha>/
  layer.tar                <- the actual filesystem diff for that layer
  json                     <- legacy layer metadata
  VERSION
```

```bash
# Read the manifest
tar xf image.tar manifest.json -O | python3 -m json.tool

# Read the image config
CONFIG=$(tar xf image.tar manifest.json -O | python3 -c "import sys,json; print(json.load(sys.stdin)[0]['Config'])")
tar xf image.tar "$CONFIG" -O | python3 -m json.tool

# List files in the first layer
LAYER=$(tar tf image.tar | grep 'layer.tar' | head -1)
tar xf image.tar "$LAYER" -O | tar tf - | head -30
```

---

## Size comparison

```bash
docker image ls                               # all images with sizes
docker image ls --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}"

# Pull and compare base image variants
docker pull python:3.13
docker pull python:3.13-slim
docker pull python:3.13-alpine
docker image ls python
```

---

## dive

`dive` is an interactive terminal tool for exploring layers. It shows the layer tree on the left and what changed in the filesystem on the right.

```bash
# Install
# Ubuntu/Debian: download the .deb from https://github.com/wagoodman/dive/releases
# Or run it as a container (no install)
docker run --rm -it \
  -v /var/run/docker.sock:/var/run/docker.sock \
  wagoodman/dive:latest <image>
```

`dive` also reports image efficiency: the ratio of unique bytes to total bytes. A low score means data is duplicated or deleted across layers without being collapsed.

---

## docker manifest inspect

Inspects the manifest as stored in the registry, before pulling. Shows what platforms (OS + architecture) an image supports.

```bash
docker manifest inspect nginx:alpine
docker manifest inspect python:3.13-slim
```

Useful for verifying that an image supports `linux/arm64` before deploying to ARM-based infrastructure.

---

## Labs

```
image-inspection/
+-- layer-analysis/    # Hands-on inspection of real images
```
