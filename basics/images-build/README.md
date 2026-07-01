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
