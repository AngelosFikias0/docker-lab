# distroless

A Flask app running on a distroless base image. Demonstrates the trade-off between attack surface, debuggability, and image size compared to slim or alpine.

---

## What is distroless

Distroless images (maintained by Google) contain only your application runtime. No shell, no package manager, no coreutils. Nothing you did not explicitly copy in.

| Image                                | Shell | Pkg manager | Size  |
| ------------------------------------ | ----- | ----------- | ----- |
| `python:3.11`                        | yes   | yes         | ~1.1GB |
| `python:3.11-slim`                   | yes   | yes         | ~200MB |
| `python:3.11-alpine`                 | yes   | yes (apk)   | ~50MB  |
| `gcr.io/distroless/python3-debian12` | no    | no          | ~55MB  |

Size is similar to alpine, but the attack surface is smaller: fewer binaries, fewer vulnerabilities, nothing to exploit interactively if someone gets into the container.

---

## Files

| File              | Purpose                                |
| ----------------- | -------------------------------------- |
| `Dockerfile`      | 2-stage build: builder + distroless    |
| `main.py`         | Flask app: `/health` and `/` endpoints |
| `requirements.txt`| flask, gunicorn                        |

---

## Build and run

```bash
docker build -t distroless-example:latest .
docker run --rm -p 8080:8080 distroless-example:latest
curl localhost:8080/health
curl localhost:8080/
```

---

## No shell

The most immediate consequence of distroless is that `docker exec` into a shell does not work:

```bash
# fails: no /bin/bash, no /bin/sh
docker exec -it <container_id> /bin/bash

# use docker cp to pull files out for inspection instead
docker cp <container_id>:/app/main.py ./main.py
```

## Debugging

Google ships a `:debug` variant that adds a busybox shell for exactly this case:

```bash
# Build against the debug base manually to get a shell
docker run --rm -it \
  --entrypoint /busybox/sh \
  gcr.io/distroless/python3-debian12:debug

# Or debug at the builder stage (full slim image, all tools available)
docker build --target builder -t distroless-example:builder .
docker run --rm -it distroless-example:builder /bin/bash
```

The builder stage approach is usually faster in practice.

---

## Key patterns

**pip --target**: installs packages into a single directory (`/app/packages`) instead of the system site-packages. Makes `COPY --from=builder` clean and explicit.

**PYTHONPATH**: tells Python where to find the packages installed with `--target`. Without it, `import flask` fails even though flask is on disk.

**Exec form only**: distroless has no shell, so all `ENTRYPOINT`, `CMD`, and `HEALTHCHECK` must use exec form `["..."]`. Shell form silently fails because `/bin/sh` does not exist.

**python3 -m gunicorn**: invokes gunicorn via its `__main__` module. Avoids needing the gunicorn binary on `PATH`, which matters when `PATH` is minimal or nonexistent.

---

## Distroless vs slim vs alpine

- **slim**: good default. Has a shell, so you can exec in. Larger attack surface.
- **alpine**: smallest with a shell. Watch for glibc compatibility issues with some Python packages.
- **distroless**: no shell, smallest attack surface. Harder to debug. Best for production when you have confidence in your image.

Use distroless when security posture matters more than debugging convenience.
