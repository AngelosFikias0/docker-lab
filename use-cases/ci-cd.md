# CI/CD Patterns

Docker in CI pipelines: building, caching, testing, and publishing images.

---

## Docker-in-Docker vs socket mount

Two ways to run Docker inside a CI job.

**Docker-in-Docker (DinD):**

```yaml
# GitLab CI example
services:
  - docker:dind

variables:
  DOCKER_HOST: tcp://docker:2376
  DOCKER_TLS_CERTDIR: "/certs"

build:
  image: docker:latest
  script:
    - docker build -t myimage .
```

- Runs a full Docker daemon as a sidecar.
- Isolated from the host. Safe on shared runners.
- Slower startup (daemon initialization per job).
- Requires `privileged: true` on the runner.

**Socket mount:**

```yaml
build:
  image: docker:latest
  volumes:
    - /var/run/docker.sock:/var/run/docker.sock
  script:
    - docker build -t myimage .
```

- Reuses the host daemon. Fast, no privileged runner needed.
- Shares the host's Docker state. Containers and images built here are visible on the host.
- Security risk on shared runners — anyone with socket access has root-equivalent control.
- Use only on dedicated, trusted runners.

**Recommendation:** DinD on shared/cloud runners. Socket mount on self-hosted dedicated runners where you control who runs jobs.

---

## Build cache in CI

CI runners are ephemeral — the layer cache from one job is gone by the next. Without explicit cache export, every build starts cold.

**Registry cache (recommended):**

```bash
docker buildx build \
  --cache-from type=registry,ref=registry.example.com/myapp:cache \
  --cache-to   type=registry,ref=registry.example.com/myapp:cache,mode=max \
  -t registry.example.com/myapp:$COMMIT_SHA \
  --push .
```

`mode=max` exports all intermediate layers, not just the final stage — important for multi-stage builds where the cache benefit is in early stages.

**GitHub Actions cache:**

```yaml
- uses: docker/build-push-action@v5
  with:
    cache-from: type=gha
    cache-to: type=gha,mode=max
```

Stores the BuildKit cache in GitHub's cache backend. Automatic key management.

---

## Tagging strategy

```bash
IMAGE=registry.example.com/myapp

docker build \
  -t $IMAGE:$COMMIT_SHA \      # immutable, maps to exact commit
  -t $IMAGE:$BRANCH_NAME \     # mutable, points to latest on branch
  -t $IMAGE:latest \           # mutable, points to latest main
  .
```

- Tag by commit SHA for traceability. Know exactly what code is in production.
- `latest` is convenient but should never be used in production manifests — it's a moving target.
- Use commit SHA in Kubernetes/Compose deployments so rollbacks are deterministic.

---

## Multi-arch builds

Build images that run on both amd64 (CI/cloud) and arm64 (Mac M-series, Graviton).

```bash
docker buildx create --use --name multiarch
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -t myimage:latest \
  --push .
```

BuildKit farms each platform to the appropriate emulator (QEMU) or native node. The registry stores a manifest list — `docker pull` picks the right variant automatically.

---

## CI pipeline structure

```
1. Build image (cache-from registry)
2. Run tests inside the image
3. Scan for vulnerabilities (trivy / grype)
4. Push to registry (cache-to registry)
5. Deploy (update k8s deployment / compose service)
```

**Run tests inside the image:**

```bash
docker run --rm myimage:$COMMIT_SHA pytest tests/
```

Tests run in the exact same environment that will go to production. No "works on my machine" with a different Python/Node version.

**Scan before push:**

```bash
trivy image myimage:$COMMIT_SHA --exit-code 1 --severity CRITICAL
```

Exit code 1 on CRITICAL findings fails the pipeline before the image reaches the registry.

---

## Secrets in CI builds

Never pass secrets as build args — they appear in `docker history` and are cached in layers.

```dockerfile
# WRONG: secret visible in build history
ARG API_KEY
RUN curl -H "Authorization: $API_KEY" https://private-registry/...
```

**Correct — BuildKit secret mount:**

```dockerfile
# syntax=docker/dockerfile:1
RUN --mount=type=secret,id=api_key \
    API_KEY=$(cat /run/secrets/api_key) && \
    curl -H "Authorization: $API_KEY" https://private-registry/...
```

```bash
docker buildx build --secret id=api_key,env=API_KEY .
```

Secret is available only during that `RUN` step and never committed to any layer.

---

## .dockerignore in CI

Always include `.dockerignore`. In CI, the build context often contains:

- `.git/` — can be hundreds of MB
- `node_modules/` — gigabytes
- Test fixtures, coverage reports, local env files

These inflate the context sent to the daemon on every build. A missing `.dockerignore` is the most common cause of inexplicably slow CI builds.
