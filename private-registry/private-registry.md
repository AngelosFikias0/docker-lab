# Private Registry

## Problem

Docker Hub has rate limits (100 pulls/6h unauthenticated, 200/6h free accounts). CI pipelines on shared runners hit these limits frequently. Air-gapped environments cannot reach Docker Hub at all. Enterprise builds need a single source of truth for all artifact types with consistent access control.

## Solution

Run a private registry. Options by scale:

| Option | Use case |
|---|---|
| `registry:2` | Self-hosted, Docker images only, minimal config |
| ghcr.io | GitHub-native, per-org, free for public repos |
| AWS ECR / GCR / ACR | Cloud-native, IAM-integrated, managed |
| Artifactory / Nexus | Enterprise, multi-artifact type, audit logging |

`registry:2` is the Docker-maintained open-source implementation — the same engine Artifactory's Docker repos are built on.

---

## registry:2 as a push/pull store

### Start the registry

```bash
docker volume create registry-data

docker run -d \
  --name registry \
  --restart unless-stopped \
  -p 5000:5000 \
  -v registry-data:/var/lib/registry \
  registry:2
```

The registry is now listening on `localhost:5000`. By default no auth, no TLS — suitable for local use only.

### Push an image

```bash
# Build something
docker build -t myapp:latest ./basics/images-build

# Tag it for the local registry
docker tag myapp:latest localhost:5000/myapp:latest

# Push
docker push localhost:5000/myapp:latest
```

### Pull it back

```bash
docker pull localhost:5000/myapp:latest
```

### Inspect what's stored

```bash
# List repositories
curl -s http://localhost:5000/v2/_catalog | python3 -m json.tool

# List tags for an image
curl -s http://localhost:5000/v2/myapp/tags/list | python3 -m json.tool

# Fetch the manifest
curl -s http://localhost:5000/v2/myapp/manifests/latest \
  -H "Accept: application/vnd.docker.distribution.manifest.v2+json" \
  | python3 -m json.tool
```

The registry speaks the OCI Distribution Spec — same API surface as Docker Hub and ghcr.io.

---

## registry:2 as a pull-through cache

A pull-through cache proxies requests to an upstream registry and stores the result locally. Subsequent pulls hit the cache instead of Docker Hub.

```bash
docker run -d \
  --name registry-cache \
  --restart unless-stopped \
  -p 5001:5000 \
  -e REGISTRY_PROXY_REMOTEURL=https://registry-1.docker.io \
  registry:2
```

Tell the Docker daemon to use it as a mirror by adding to `/etc/docker/daemon.json`:

```json
{
  "registry-mirrors": ["http://localhost:5001"]
}
```

Restart the daemon: `sudo systemctl restart docker`

Now `docker pull nginx:alpine` hits the cache first. First pull is slow (fetches from Docker Hub and stores locally). Every subsequent pull from any machine pointing at this mirror is instant and rate-limit-free.

This is exactly what Artifactory's `docker-remote` repo type does.

---

## Compose stack

```yaml
services:
  registry:
    image: registry:2
    ports:
      - "5000:5000"
    volumes:
      - registry-data:/var/lib/registry
    restart: unless-stopped

  registry-ui:
    image: joxit/docker-registry-ui:latest
    ports:
      - "8080:80"
    environment:
      - SINGLE_REGISTRY=true
      - REGISTRY_URL=http://registry:5000
      - REGISTRY_TITLE=Local Registry
    depends_on:
      - registry

volumes:
  registry-data:
```

Browse the registry at `http://localhost:8080` — lists repos, tags, manifests, and lets you delete images.

---

## CI integration

In GitHub Actions, use your registry to avoid Docker Hub rate limits on the runner:

```yaml
steps:
  - name: Pull base image via cache registry
    run: docker pull ${{ secrets.REGISTRY_URL }}/python:3.13-slim

  - name: Build
    run: |
      docker build \
        --build-arg BASE=my-registry.internal/python:3.13-slim \
        -t my-registry.internal/myapp:${{ github.sha }} .

  - name: Push
    run: docker push my-registry.internal/myapp:${{ github.sha }}
```

For self-hosted runners on a private network, the registry URL is typically a hostname resolvable within the network. For GitHub-hosted runners, ghcr.io or ECR with OIDC is the standard path.

---

## TLS and auth for production

`registry:2` with no TLS is only safe on localhost. For any networked use:

**TLS** — mount a cert and key and set:
```bash
-e REGISTRY_HTTP_TLS_CERTIFICATE=/certs/domain.crt \
-e REGISTRY_HTTP_TLS_KEY=/certs/domain.key
```

**Basic auth** — generate htpasswd file and set:
```bash
-e REGISTRY_AUTH=htpasswd \
-e REGISTRY_AUTH_HTPASSWD_REALM="Registry Realm" \
-e REGISTRY_AUTH_HTPASSWD_PATH=/auth/htpasswd
```

In practice, running TLS + auth on `registry:2` yourself is where most teams switch to a managed option (ECR, ghcr.io, GCR) rather than maintaining their own.

---

## Kubernetes mapping

| Local concept | Kubernetes equivalent |
|---|---|
| `registry:2` on host | In-cluster registry (Harbor, Zot) or cloud registry (ECR, GCR) |
| `daemon.json` mirror | `containerd` mirror config in `/etc/containerd/config.toml` |
| Pull-through cache | `registry.mirrors` in containerd config, per-namespace |
| Registry credentials | `imagePullSecrets` on Pod spec or ServiceAccount |
| Rate limit protection | `imagePullPolicy: IfNotPresent` to avoid redundant pulls |
