# CI/CD with GitHub Actions

## Core concepts

A GitHub Actions workflow is a YAML file in `.github/workflows/`. It runs on a hosted runner (ephemeral VM) triggered by events: push, pull_request, workflow_dispatch, schedule, and others.

```
event (push) → runner VM boots → jobs run → runner VM destroyed
```

Each **job** runs in isolation. Jobs can run in parallel or chain with `needs:`. Steps within a job run sequentially on the same VM.

---

## Workflow anatomy

```yaml
on:                        # trigger
  push:
    branches: [main]

jobs:
  my-job:
    runs-on: ubuntu-latest # runner image
    permissions:           # fine-grained GITHUB_TOKEN scope
      contents: read
      packages: write
    steps:
      - uses: actions/checkout@v4   # action (reusable step)
      - name: Run something
        run: echo "shell command"   # inline shell
      - name: Conditional step
        if: github.ref == 'refs/heads/main'
        run: echo "only on main"
```

---

## This repo's pipelines

### CI (`ci.yml`)

Triggered on every push and PR to `main`. Two jobs:

```
push/PR
  └── validate (compose config + bash -n)
        └── build matrix (13 Dockerfiles, parallel, fail-fast: false)
              └── push to ghcr.io (main branch only, publishable images only)
```

**validate job** — fast gate before expensive builds:
- `docker compose config --quiet` on all 4 compose files (catches YAML errors, missing env files, unknown keys)
- `bash -n exercises.sh` on every exercises file (syntax check without execution)

**build job** — matrix strategy spawns one runner per Dockerfile:

```yaml
strategy:
  fail-fast: false    # one failure does not cancel the rest
  matrix:
    include:
      - name: compose/api-db-nginx
        context: ./compose/api-db-nginx/app
        image_name: api   # set only for publishable images
```

Entries without `image_name` build and discard. Entries with `image_name` push to `ghcr.io/<owner>/docker-lab-<name>:latest` on main.

BuildKit GHA cache is scoped per matrix entry so each Dockerfile gets its own cache key:

```yaml
cache-from: type=gha,scope=${{ matrix.name }}
cache-to: type=gha,scope=${{ matrix.name }},mode=max
```

`mode=max` caches every layer, not just the final image layers.

---

### Release (`release.yml`)

Manual trigger via `workflow_dispatch` with a `bump` input (patch / minor / major).

```
workflow_dispatch (bump=patch)
  └── get latest semver tag from git
        └── compute next version (shell arithmetic)
              └── git tag + push
                    └── build Spring Boot API → push ghcr.io (:latest + :vX.Y.Z)
                          └── gh release create --generate-notes
```

Version arithmetic in pure shell — no external action needed:

```bash
MAJOR=$(echo "$VERSION" | cut -d. -f1)
MINOR=$(echo "$VERSION" | cut -d. -f2)
PATCH=$(echo "$VERSION" | cut -d. -f3)

case "${{ inputs.bump }}" in
  major) MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0 ;;
  minor) MINOR=$((MINOR + 1)); PATCH=0 ;;
  patch) PATCH=$((PATCH + 1)) ;;
esac
```

A release produces:
- A git tag (`v0.2.0`)
- A GitHub release with auto-generated notes (commits since last tag)
- Two image tags on ghcr.io: `latest` and the version tag

---

## GITHUB_TOKEN and permissions

Every workflow run gets a short-lived `GITHUB_TOKEN` scoped to the repository. Default permissions are read-only. Capabilities must be declared explicitly:

| Permission | What it unlocks |
|---|---|
| `contents: write` | push tags, create releases |
| `packages: write` | push to ghcr.io |
| `id-token: write` | OIDC (keyless signing, cloud auth) |

Token is available as `${{ secrets.GITHUB_TOKEN }}` or via `GH_TOKEN` env var for the `gh` CLI.

---

## GitHub Container Registry (ghcr.io)

Images are stored under `ghcr.io/<owner>/<image>:<tag>`. The owner must be lowercase — `github.repository_owner` preserves the account's original casing, so it must be lowercased before use:

```bash
OWNER=$(echo "${{ github.repository_owner }}" | tr '[:upper:]' '[:lower:]')
```

By default packages inherit the repo's visibility. To make an image public: GitHub → package → Package settings → Change visibility.

Pull a published image without cloning the repo:

```bash
docker pull ghcr.io/angelosfikias0/docker-lab-api:latest
```

---

## Buildx

`docker buildx` is the CLI plugin that wraps BuildKit. It replaces the legacy builder (`docker build`) and is the default since Docker 23.

```bash
docker buildx ls                        # list builders
docker buildx create --use --name lab   # create a builder backed by a BuildKit container
docker buildx inspect --bootstrap       # show builder capabilities (platforms, cache)
```

Key capabilities over the legacy builder:

| Feature | Legacy builder | Buildx + BuildKit |
|---|---|---|
| Multi-platform | No | `--platform linux/amd64,linux/arm64` |
| Cache exports | No | `--cache-to type=gha,registry,s3` |
| Secret mounts | No | `--mount=type=secret` |
| SSH mounts | No | `--mount=type=ssh` |
| Concurrent stages | No | Parallel stage execution |
| OCI output | No | `--output type=oci` |

In CI, `docker/setup-buildx-action` creates a builder and sets it as the default. All subsequent `docker build` or `docker/build-push-action` calls use BuildKit automatically.

---

## GHA cache for BuildKit

BuildKit supports external cache backends. The `gha` backend stores layer blobs in the Actions cache (10 GB per repo, evicted LRU).

```yaml
cache-from: type=gha,scope=my-image
cache-to: type=gha,scope=my-image,mode=max
```

`scope` isolates caches between matrix entries. Without it, all jobs share one cache key and overwrite each other.

Cache hit behavior: BuildKit checks each layer's content hash against the cache. A cache miss on layer N invalidates N+1 onwards — same as local builds. This is why layer ordering in Dockerfiles matters for CI speed.

---

## Contexts and expressions

```yaml
# Branch check
if: github.ref == 'refs/heads/main'

# Event type
if: github.event_name == 'pull_request'

# Step output reference
echo "value=foo" >> "$GITHUB_OUTPUT"   # write
${{ steps.my-step.id.outputs.value }}  # read

# Job output reference (cross-job)
outputs:
  result: ${{ steps.my-step.outputs.value }}
# then in downstream job:
${{ needs.my-job.outputs.result }}
```

---

## Artifact registries

### ghcr.io vs enterprise registries

ghcr.io covers Docker images for a single GitHub org. In larger orgs the full artifact surface is broader:

| Artifact type | Dev tool | Enterprise registry |
|---|---|---|
| Docker images | ghcr.io / Docker Hub | Artifactory, ECR, GCR |
| npm packages | npmjs.org | Artifactory npm repo |
| Maven/Gradle jars | Maven Central | Artifactory maven repo |
| Python wheels | PyPI | Artifactory PyPI repo |
| Helm charts | Artifact Hub | Artifactory Helm repo |
| Terraform modules | Terraform Registry | Artifactory generic repo |

Without a unified registry you end up with separate systems per type, inconsistent access control, and no unified audit log.

### Artifactory repo types

Artifactory organises storage into three repo types, all addressable through the same URL pattern:

```
Local repos   — artifacts you build and own
               docker-local, npm-local, maven-local

Remote repos  — proxy + cache for external sources
               docker-remote → caches Docker Hub pulls
               npm-remote    → caches npmjs.org pulls
               Benefit: external outage does not kill CI; cache hits are instant

Virtual repos — single endpoint aggregating local + remote
               docker-virtual = docker-local + docker-remote
               Clients point at the virtual URL and never know the difference
```

### Pipeline position

```
[git push]
    ↓
[CI build] → Docker image + npm package + Helm chart
    ↓
[push all three to Artifactory]   ← one registry, three repo types
    ↓
[K8s pulls Docker image from Artifactory]
[npm install pulls package from Artifactory npm repo]
[helm install pulls chart from Artifactory Helm repo]
```

### Local equivalent: registry:2

The Docker-maintained `registry:2` image is the open-source equivalent for Docker images only. It is what Artifactory's docker-local repo is built on internally and what most self-hosted setups use for air-gapped environments. See `use-cases/private-registry.md` for a runnable example.

---

## Kubernetes mapping

| GHA concept | Kubernetes equivalent |
|---|---|
| Runner VM | Pod |
| Job | Job / init container chain |
| Matrix strategy | Job with parallelism + completions |
| `needs:` dependency | init containers or DAG in Argo Workflows |
| `GITHUB_TOKEN` | ServiceAccount + RBAC |
| GHA cache | PVC or Tekton workspace |
| `workflow_dispatch` | CronJob (scheduled) or manual trigger via `kubectl create job` |
