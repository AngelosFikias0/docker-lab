# Basics

Two exercises. No dependencies. Everything runs with a plain Docker install.

## Structure

```
00-basics/
├── docker-run/
│   ├── exercises.sh     # 10 runtime flag exercises — run individually
│   └── README.md
└── images-build/
    ├── Dockerfile        # annotated — every instruction explains its why
    ├── .dockerignore
    ├── app.py            # minimal stdlib HTTP server, zero pip deps
    └── README.md
```

## What you're learning

`docker-run` — how Docker starts and manages containers. Covers the flags
you'll use daily: `-d`, `-it`, `-p`, `-e`, `--rm`, `--name`, `--memory`,
`--cpus`, `docker inspect`.

`images-build` — the image build lifecycle. Covers `FROM`, `COPY`, `RUN`,
`ENV`, `EXPOSE`, `USER`, `ENTRYPOINT` vs `CMD`, layer caching order, and
`.dockerignore`.
