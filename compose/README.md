# Docker Compose

Declarative multi-container orchestration for a single host. A `docker-compose.yml` file describes the full application stack — services, networks, volumes — and Compose manages their lifecycle as a unit.

---

## Modules

| Module | Stack | Covers |
| ------ | ----- | ------ |
| `simple-stack/` | Flask + Redis | Core Compose concepts, CLI, networking basics |
| `api-db-nginx/` | Spring Boot + PostgreSQL + nginx | Production pattern: reverse proxy, DB, health checks |
| `multi-service-app/` | Web + Worker + Redis + PostgreSQL | Scaling, profiles, env_file, depends_on health checks |

---

## File Anatomy

```yaml
services:            # one or more containers
  web:
    image: nginx:alpine
    build: ./app     # build from Dockerfile instead of pulling
    ports:
      - "80:80"      # host:container — published to the host
    expose:
      - "8080"       # internal only — available to other services, not host
    environment:
      - DB_HOST=postgres
    env_file:
      - .env
    volumes:
      - pgdata:/var/lib/postgresql/data   # named volume
      - ./nginx.conf:/etc/nginx/nginx.conf:ro  # bind mount
    networks:
      - frontend
    depends_on:
      postgres:
        condition: service_healthy  # wait for health check, not just container start
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
      interval: 10s
      timeout: 3s
      retries: 3
      start_period: 20s

networks:
  frontend:
    driver: bridge
    name: myapp-frontend   # explicit name, not auto-prefixed

volumes:
  pgdata:            # named volume, persists across down/up cycles
```

**`version`** — the top-level `version:` key is obsolete in Compose v2+. Omit it. Compose now uses the schema version from the binary, not the file.

---

## Key Service Directives

| Directive | Purpose |
| --------- | ------- |
| `image` | Pull this image from the registry |
| `build` | Build from a Dockerfile (path or object with `context`/`dockerfile`) |
| `ports` | Publish `host:container` — creates a DNAT rule in iptables |
| `expose` | Document internal port — no iptables rule, no host binding |
| `environment` | Inline env vars. Values with no `=` are passed through from the shell |
| `env_file` | Load vars from a file — keep secrets out of the compose file |
| `volumes` | Named volume or bind mount per service |
| `networks` | Which networks this service connects to |
| `depends_on` | Start ordering + optional health condition |
| `restart` | `no` / `always` / `unless-stopped` / `on-failure` |
| `healthcheck` | Overrides or sets the image's HEALTHCHECK |
| `deploy.replicas` | Number of containers for this service (Compose v2) |
| `profiles` | Service only starts when the named profile is active |

---

## CLI Reference

```bash
docker compose config          # validate + print merged compose file
docker compose build           # build all services with build: context
docker compose pull            # pull all images without starting
docker compose up -d           # create + start all services, detached
docker compose up -d --build   # rebuild images then start
docker compose logs -f         # follow logs from all services
docker compose logs -f web     # follow logs from one service
docker compose top             # running processes across all services
docker compose ps              # container status
docker compose exec web sh     # exec into a running service container
docker compose run --rm web sh # one-off container from service config
docker compose stop            # stop containers, keep them
docker compose start           # start stopped containers
docker compose pause           # SIGSTOP all service containers
docker compose unpause         # SIGCONT
docker compose down            # stop + remove containers + default network
docker compose down -v         # + remove named volumes
docker compose down --rmi all  # + remove images
docker compose scale web=3     # run 3 replicas of web (no port conflicts — use expose)
```

---

## Networking

Compose creates a default bridge network per project named `<project>_default`. Every service joins it automatically unless you define explicit networks.

**DNS:** service name resolves to the container IP within the same network. `web` can reach `postgres` by hostname `postgres`. No `/etc/hosts` editing, no hardcoded IPs.

```bash
docker compose exec web ping postgres   # resolves via embedded DNS at 127.0.0.11
```

**Network isolation pattern:**

```yaml
networks:
  frontend:   # nginx <-> app
  backend:    # app <-> db

services:
  nginx:
    networks: [frontend]
  app:
    networks: [frontend, backend]   # bridges both
  postgres:
    networks: [backend]             # db unreachable from nginx directly
```

---

## depends_on and Health Checks

`depends_on` with no condition only waits for the container to start — not for the service to be ready. Race conditions on startup are almost always a missing `condition: service_healthy`.

```yaml
services:
  app:
    depends_on:
      postgres:
        condition: service_healthy   # waits for postgres HEALTHCHECK to pass
      redis:
        condition: service_started   # default — container started only

  postgres:
    image: postgres:16-alpine
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 5s
      retries: 5
```

States: `starting` -> `healthy` -> `unhealthy`. Compose blocks the dependent service until `healthy`.

---

## Environment and Secrets

```yaml
# inline — avoid for secrets, visible in docker inspect
environment:
  DB_PASSWORD: plaintext

# env_file — keep out of version control
env_file:
  - .env

# Docker secrets (Compose v2)
secrets:
  db_password:
    file: ./secrets/db_password.txt

services:
  app:
    secrets: [db_password]
    # mounted at /run/secrets/db_password inside container
```

---

## Profiles

Profiles let you define services that only start when explicitly activated — useful for debug tools, migration runners, or optional dependencies.

```yaml
services:
  app:
    image: myapp      # always starts

  adminer:
    image: adminer    # only with --profile debug
    profiles: [debug]
    ports:
      - "8080:8080"
```

```bash
docker compose --profile debug up -d   # starts app + adminer
docker compose up -d                   # starts app only
```

---

## Kubernetes Mapping

| Compose | Kubernetes |
| ------- | ---------- |
| `service` | `Deployment` + `Service` |
| `ports` | `Service` type `NodePort` or `LoadBalancer` |
| `expose` | `Service` type `ClusterIP` (internal only) |
| `networks` | `NetworkPolicy` |
| `volumes` (named) | `PersistentVolumeClaim` |
| `volumes` (bind mount) | `hostPath` volume (avoid in production) |
| `environment` | `ConfigMap` (non-sensitive) / `Secret` (sensitive) |
| `env_file` | `ConfigMap` mounted as env |
| `depends_on` | `initContainers` or readiness gates |
| `restart: unless-stopped` | `restartPolicy: Always` |
| `healthcheck` | `livenessProbe` + `readinessProbe` |
| `deploy.replicas` | `replicas` in Deployment spec |
| `profiles` | Helm chart `values.yaml` conditions or Kustomize overlays |
| `secrets` | `Secret` resource + `volumeMount` at `/run/secrets/` |
