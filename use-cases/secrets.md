# Secrets Management

How to handle sensitive values without baking them into images or exposing them in metadata.

---

## What not to do

**Hardcoded in Dockerfile:**

```dockerfile
ENV DB_PASSWORD=supersecret     # visible in docker inspect, docker history, image layers
```

**Build arg:**

```dockerfile
ARG DB_PASSWORD
ENV DB_PASSWORD=$DB_PASSWORD    # visible in docker history, cached in layers
```

Both approaches commit the secret into the image permanently. Anyone who can pull the image can extract it.

---

## Runtime env vars

Pass secrets at `docker run` time. They never touch the image.

```bash
docker run -e DB_PASSWORD=supersecret myapp
```

**Problem:** visible in `docker inspect`, process listing (`/proc/<pid>/environ`), and shell history.

Better — read from the environment of the calling shell:

```bash
export DB_PASSWORD=supersecret
docker run -e DB_PASSWORD myapp     # value comes from shell env, not written in command
```

---

## Env file

Keep secrets in a file, exclude from version control.

```bash
# .env
DB_PASSWORD=supersecret
API_KEY=abc123
```

```bash
docker run --env-file .env myapp
```

```gitignore
.env
.env.*
```

Still visible in `docker inspect`. Better than command-line args for secret count, but not secure enough for production.

---

## Mounted secret file

Mount a file into the container at runtime. The file never enters the image.

```bash
docker run \
  -v /etc/secrets/db_password:/run/secrets/db_password:ro \
  myapp
```

App reads the secret from disk:

```python
with open('/run/secrets/db_password') as f:
    DB_PASSWORD = f.read().strip()
```

The file is on the host — secure that host file using OS permissions (chmod 600, owned by the Docker user).

---

## Docker secrets (Swarm / Compose)

Docker Swarm and Compose have a native secrets primitive. Secret content is mounted at `/run/secrets/<name>` inside the container, never stored in the image or env vars.

```yaml
# docker-compose.yml
services:
  app:
    image: myapp
    secrets:
      - db_password

secrets:
  db_password:
    file: ./secrets/db_password.txt   # local dev
    # external: true                  # Swarm managed secret
```

```bash
docker secret create db_password ./secrets/db_password.txt   # Swarm
docker compose up
```

App reads from `/run/secrets/db_password`. The secret is distributed over an encrypted channel in Swarm mode and stored in the Swarm's Raft log (encrypted at rest).

---

## BuildKit secret mount (build-time secrets)

For secrets needed during `docker build` only (e.g. private registry credentials, API keys for fetching packages).

```dockerfile
# syntax=docker/dockerfile:1
RUN --mount=type=secret,id=npmrc,target=/root/.npmrc \
    npm install
```

```bash
docker buildx build --secret id=npmrc,src=$HOME/.npmrc .
```

Secret is available only within that `RUN` step. Not committed to any layer, not visible in `docker history`.

---

## External secret stores

For production, secrets should live in a dedicated secrets manager, not on the host filesystem.

| Tool | How it integrates |
| ---- | ----------------- |
| HashiCorp Vault | App fetches secrets at startup via Vault API or agent sidecar |
| AWS Secrets Manager | App calls SDK, or use ECS secrets injection |
| GCP Secret Manager | App calls SDK, or Workload Identity |
| Kubernetes Secrets | Mounted as files or env vars into pods (base64, not encrypted by default — use etcd encryption at rest) |

**Vault agent sidecar pattern:** a Vault agent container runs alongside the app, fetches and renews secrets, and writes them to a shared volume. App reads files, never talks to Vault directly.

---

## Kubernetes

Kubernetes secrets are base64-encoded, not encrypted, in etcd by default. Enable [encryption at rest](https://kubernetes.io/docs/tasks/administer-cluster/encrypt-data/) or use an external store.

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: db-secret
type: Opaque
data:
  password: c3VwZXJzZWNyZXQ=   # base64 of "supersecret"
```

```yaml
# inject as env var
env:
  - name: DB_PASSWORD
    valueFrom:
      secretKeyRef:
        name: db-secret
        key: password

# inject as mounted file
volumes:
  - name: secrets
    secret:
      secretName: db-secret
volumeMounts:
  - name: secrets
    mountPath: /run/secrets
    readOnly: true
```

Mounted file is preferred over env var — env vars can be accidentally logged by frameworks.
