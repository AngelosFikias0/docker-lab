# Basics

Container lifecycle and image build mechanics. No dependencies.

## Structure

```
basics/
├── docker-run/
│   ├── exercises.sh     # 10 runtime flag exercises, run individually
│   └── README.md
└── images-build/
    ├── Dockerfile        # annotated, every instruction explains its why
    ├── .dockerignore
    ├── app.py            # minimal stdlib HTTP server, zero pip deps
    └── README.md
```

`docker-run`: runtime flags and container lifecycle. `-d`, `-it`, `-p`, `-e`, `--rm`, `--name`, `--memory`, `--cpus`, `docker inspect`.

`images-build`: Dockerfile instruction set, layer cache behavior, `ENTRYPOINT` vs `CMD`, signal handling, `.dockerignore`.
