# multistage

A 4-stage Python Flask image demonstrating multi-stage builds, BuildKit cache mounts, a test-as-CI-gate pattern, and production-grade execution with gunicorn.

For Docker image theory (layers, OverlayFS, caching, ENTRYPOINT vs CMD), see [`../README.md`](../README.md).

---

## Stages

| Stage   | From   | Purpose                                         |
| ------- | ------ | ----------------------------------------------- |
| `base`  | slim   | OS-level system deps (gcc, libpq-dev)           |
| `deps`  | base   | Python production packages (flask, gunicorn)    |
| `test`  | deps   | Install pytest, run test suite, gate the build  |
| `final` | base   | Production image: app + packages, no dev tools  |

---

## Files

| File                   | Purpose                                    |
| ---------------------- | ------------------------------------------ |
| `Dockerfile`           | 4-stage build                              |
| `main.py`              | Flask app: `/health` and `/` endpoints     |
| `requirements.txt`     | Production deps: flask, gunicorn           |
| `requirements-dev.txt` | Dev deps: pytest                           |
| `tests/test_main.py`   | pytest suite, runs in test stage           |

---

## Build and run

```bash
# Production build: tests run first, then final image is produced
docker build -t multistage:latest .
docker run --rm -p 8080:8080 multistage:latest
curl localhost:8080/health
curl localhost:8080/

# CI gate only: tests must pass, no final image produced
docker build --target test .

# Debug: shell into the deps stage at the point of failure
docker build --target deps -t multistage:debug .
docker run --rm -it multistage:debug /bin/bash
```

---

## Key patterns

**Multi-stage isolation**: `final` starts `FROM base`, not `FROM deps`. Build tools and test infrastructure are never present in the final image. Only installed packages are carried across via `COPY --from=deps`.

**Layer order**: `requirements.txt` is copied and installed before application source. Editing `main.py` does not invalidate the pip cache layer.

**BuildKit cache mount**: pip wheels are cached on the host between builds. Survives `--no-cache`. Never lands in the image.

**Test gate**: the `test` stage runs pytest during `docker build`. A failure stops the build before `final` is ever reached.

**Dev/prod deps split**: `pytest` lives in `requirements-dev.txt` and is only installed in the `test` stage. The `final` image has no test tooling.

**Minimal COPY in final**: `COPY main.py .` only ships what the app needs to run. Not `tests/`, not dev manifests, not anything else.

**HEALTHCHECK without curl**: uses Python stdlib (`urllib.request`) so no additional packages are needed.

**gunicorn**: production WSGI server. Multi-worker, proper SIGTERM handling. Flask's `app.run()` is single-threaded and only suitable for local development.
