# distroless

Flask app on `gcr.io/distroless/python3-debian12`. No shell, no package manager, no coreutils.

---

## Base image comparison

| Image                                | Shell | Pkg manager | Size   |
| ------------------------------------ | ----- | ----------- | ------ |
| `python:3.11`                        | yes   | yes         | ~1.1GB |
| `python:3.11-slim`                   | yes   | yes         | ~200MB |
| `python:3.11-alpine`                 | yes   | yes (apk)   | ~50MB  |
| `gcr.io/distroless/python3-debian12` | no    | no          | ~55MB  |

Size is comparable to alpine. Attack surface is smaller: fewer binaries, nothing to exploit interactively.

---

## Files

| File               | Purpose                                |
| ------------------ | -------------------------------------- |
| `Dockerfile`       | 2-stage build: builder + distroless    |
| `main.py`          | Flask app: `/health` and `/` endpoints |
| `requirements.txt` | flask, gunicorn                        |

---

## Build and run

```bash
docker build -t distroless-example:latest .
docker run --rm -p 8080:8080 distroless-example:latest
curl localhost:8080/health
```

---

## No shell

`docker exec` into a shell does not work. There is no `/bin/sh`:

```bash
docker exec -it <container_id> /bin/bash    # fails

docker cp <container_id>:/app/main.py ./main.py    # extract files instead
```

Google ships a `:debug` variant with busybox. The builder stage is usually faster for debugging:

```bash
docker build --target builder -t distroless-example:builder .
docker run --rm -it distroless-example:builder /bin/bash
```

---

## Notes

**pip --target**: packages land in `/app/packages`, not system site-packages. Makes `COPY --from=builder` explicit and predictable.

**PYTHONPATH**: required when using `pip --target`. Without it, `import flask` fails even though flask is on disk.

**Exec form only**: no `/bin/sh`, so `ENTRYPOINT`, `CMD`, and `HEALTHCHECK` must all use `["..."]` form.

**python3 -m gunicorn**: invokes via `__main__` module, avoids needing the gunicorn binary on `PATH`.

---

## slim vs alpine vs distroless

- **slim**: has a shell, largest attack surface, easiest to debug
- **alpine**: smallest with a shell, watch for glibc compatibility
- **distroless**: no shell, smallest attack surface, hardest to debug
