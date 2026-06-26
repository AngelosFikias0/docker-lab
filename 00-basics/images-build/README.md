# images-build

Minimal annotated image. No pip deps, stdlib only.

## Files

| File            | Purpose                                  |
| --------------- | ---------------------------------------- |
| `Dockerfile`    | Every instruction commented with its why |
| `app.py`        | HTTP server using only `http.server`     |
| `.dockerignore` | Keeps build context clean                |

## Build and run

```bash
docker build -t images-build:0.0.1 .
docker run -it --rm -p 8080:8080 images-build:0.0.1
curl localhost:8080
```

## What each instruction does

| Instruction  | Why                                                |
| ------------ | -------------------------------------------------- |
| `FROM`       | Base image, sets the foundation                    |
| `COPY`       | Brings files into the image                        |
| `RUN`        | Executes commands during build                     |
| `ENV`        | Sets environment variables that persist at runtime |
| `EXPOSE`     | Documents the port, does not publish it            |
| `USER`       | Drops root, run as nobody                          |
| `ENTRYPOINT` | Fixed executable, PID 1, receives signals          |
| `CMD`        | Default args to entrypoint, overridable at runtime |

## Key rules

- Deps before code. Least changed layers go first.
- Chain RUN commands. Deletions in separate layers don't save space.
- Exec form always. Shell form breaks signal handling.
