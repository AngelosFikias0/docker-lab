# multistage

4-stage Python Flask image. Multi-stage build, BuildKit cache mounts, test-gate in CI, gunicorn in production.

For image theory (layers, OverlayFS, caching), see [`../README.md`](../README.md).

---

## Stages

| Stage   | From   | Purpose                                         |
| ------- | ------ | ----------------------------------------------- |
| `base`  | slim   | OS-level system deps (gcc, libpq-dev)           |
| `deps`  | base   | Python production packages (flask, gunicorn)    |
| `test`  | deps   | Install pytest, run test suite, gate the build  |
| `final` | base   | Production image: app + packages, no dev tools  |

`final` starts `FROM base`, not `FROM deps`. Build tools and dev infrastructure never land in the production image. Packages cross via `COPY --from=deps`.

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
# Production: tests run first, then final image
docker build -t multistage:latest .
docker run --rm -p 8080:8080 multistage:latest
curl localhost:8080/health

# CI gate: test stage only, no final image produced
docker build --target test .

# Debug: shell into deps stage
docker build --target deps -t multistage:debug .
docker run --rm -it multistage:debug /bin/bash
```
