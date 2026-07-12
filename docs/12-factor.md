# 12-Factor App + Reactive Manifesto

Design principles for software that runs well in containers and distributed systems. Not rules — a diagnostic framework for identifying why a service is hard to deploy, scale, or operate.

---

## 12-Factor App

Originally from Heroku (2012). Written before Kubernetes existed, but maps almost perfectly onto container/orchestrator design.

### I. Codebase

One codebase, many deploys. Every Docker image for a given application is built from a single source code repository. Multiple services = multiple repos (or a monorepo with clear boundaries). Never share code between services by copying files — publish a package or library.

**Docker mapping:** one `Dockerfile` per service, one CI pipeline per repo, image tag = git SHA.

### II. Dependencies

Declare and isolate dependencies explicitly. Never rely on a system-installed package being available on the host. All dependencies are pulled in during the build.

```dockerfile
# Good — explicit
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Bad — assumes curl exists on the runtime host
RUN curl https://example.com/setup.sh | bash
```

**Docker mapping:** `requirements.txt`, `pom.xml`, `package.json`, `go.mod` checked into the repo. Build stage resolves them. Final image contains only what's needed.

### III. Config

Store config in environment variables, not in code or in files baked into the image. Config is whatever varies between environments (staging vs production). Code does not change — config does.

```bash
# Bad — hardcoded
DB_HOST=postgres.internal

# Good — injected at runtime
docker run -e DB_HOST=postgres.staging myapp
```

**Docker mapping:** `ENV` for defaults, `docker run -e` or Compose `environment:` for overrides, Kubernetes `ConfigMap` + `Secret` injected as env vars.

**GitOps mapping:** Helm values files per environment. Never commit secrets — use sealed-secrets or external-secrets-operator.

### IV. Backing Services

Treat all backing services (databases, queues, caches, email providers) as attached resources addressed by URL. A local database and a cloud database are interchangeable — the app just reads the connection string from config.

```yaml
# Compose: local postgres is just a URL
environment:
  DB_URL: postgres://user:pass@postgres:5432/mydb

# Production: RDS is the same URL shape
DB_URL: postgres://user:pass@prod.rds.amazonaws.com:5432/mydb
```

Application code does not change. Only config changes.

### V. Build, Release, Run

Strictly separate three stages:

```
Build   — compile code, pull deps, produce an image artifact
           docker build -t myapp:abc123 .

Release — combine image with environment config
           helm upgrade myapp ./chart --set image.tag=abc123

Run     — execute the release in the target environment
           kubectl rollout status deployment/myapp
```

A build artifact is immutable. Never modify a running container — build a new image. The ability to run any release in isolation (for debugging, rollback, audit) comes from keeping these stages clean.

**CI/CD mapping:** CI owns Build. CD (ArgoCD, Flux) owns Release and Run.

### VI. Processes

Run the app as one or more stateless processes. No critical state in memory or local disk. Session data goes in Redis. Uploaded files go in S3 or an object store. The assumption: any container can be killed and replaced at any time without data loss.

**Container mapping:** containers are ephemeral by design. `--restart=unless-stopped` handles crashes, but the process itself must not depend on surviving them.

### VII. Port Binding

Services are self-contained and export HTTP (or other protocols) by binding a port. No reliance on a runtime-injected web server (old PHP/CGI pattern). The app starts its own server.

```dockerfile
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "app.jar"]
```

**Kubernetes mapping:** `containerPort` in the pod spec, `targetPort` in the Service.

### VIII. Concurrency

Scale out by adding more process instances (horizontal), not by adding more resources to one instance (vertical). Design processes to be stateless so they can be replicated freely.

```bash
docker compose up --scale worker=5
kubectl scale deployment worker --replicas=5
```

Process types (web, worker, scheduler) can scale independently.

### IX. Disposability

Processes should start fast and shut down gracefully. Fast startup = faster scaling and recovery. Graceful shutdown = no dropped requests on `SIGTERM`.

```python
import signal, sys

def shutdown(sig, frame):
    # flush buffers, close DB connections, drain queue
    sys.exit(0)

signal.signal(signal.SIGTERM, shutdown)
```

**Container mapping:** `docker stop` sends SIGTERM. The grace period (`--stop-timeout`) is the window for cleanup. Kubernetes `preStop` hook can drain traffic before SIGTERM.

### X. Dev/Prod Parity

Keep development, staging, and production as similar as possible. The main gaps that bite teams:

| Gap | Risk |
|---|---|
| Different OS / package versions | "works on my machine" |
| Mocked backing services in dev | Bugs only appear in production |
| Different config handling | Env-specific code paths |

**Docker mapping:** same image runs in every environment. Dev uses `docker compose`, prod uses Kubernetes — same image, different config injection.

### XI. Logs

Treat logs as event streams. The app writes to stdout/stderr, unbuffered. Log routing, aggregation, and storage are infrastructure concerns, not application concerns.

```python
import sys
print("event happened", file=sys.stdout, flush=True)
```

```dockerfile
# Never configure log files inside the container
# Let Docker capture stdout/stderr
CMD ["python", "-u", "app.py"]   # -u = unbuffered
```

**Observability mapping:** Docker log drivers route stdout to the configured sink (journald, fluentd, awslogs). In Kubernetes, `kubectl logs` reads container stdout. Fluentd/Fluent Bit ship to Elasticsearch or Loki.

### XII. Admin Processes

Run admin/management tasks as one-off processes in the same environment as the app — same image, same config, same release. Not a separate codebase or a manual SSH session.

```bash
# One-off migration
docker compose run --rm app python manage.py migrate

# Kubernetes
kubectl run --rm -it migration \
  --image=myapp:v1.2.0 \
  --restart=Never \
  -- python manage.py migrate
```

---

## Reactive Manifesto

Design principles for distributed systems that remain responsive under failure and load. Published 2013. Maps onto microservices and async architecture patterns.

### Responsive

The system responds in a timely manner under all conditions. Responsiveness enables detection of problems early — timeouts and latency budgets are explicit, not "it feels slow."

**Practice:** SLOs, latency percentiles (p95/p99), circuit breakers (Hystrix, Resilience4j).

### Resilient

The system stays responsive in the face of failure. Resilience is achieved through replication, isolation, and delegation. Failures are contained — one component failing does not cascade.

**Practice:** bulkheads (isolate thread pools per dependency), retries with backoff, graceful degradation (return cached data when DB is down). In Kubernetes: `PodDisruptionBudget`, health probes, multiple replicas across zones.

### Elastic

The system stays responsive under varying workload. Scale out to meet demand, scale in when load drops. No contention points, no single bottlenecks.

**Practice:** horizontal pod autoscaling (HPA), event-driven scaling (KEDA), stateless services, queue-based load leveling.

### Message Driven

Reactive systems use asynchronous message passing to establish a boundary between components. Loose coupling, location transparency, back-pressure.

```
Synchronous (blocking):
  Client → HTTP request → waits → Server responds
  Tight coupling. Server goes down = client errors immediately.

Asynchronous (message-driven):
  Client → Kafka/RabbitMQ → message stored → Server consumes when ready
  Loose coupling. Server goes down = messages queue up, no immediate failure.
```

**Practice:** Kafka for high-throughput event streaming, RabbitMQ for task queues, NATS for lightweight pub-sub. Back-pressure: producers slow down when consumers can't keep up (Kafka consumer lag monitoring).

---

## Combined mapping to Docker/Kubernetes

| Principle | Docker/Compose | Kubernetes |
|---|---|---|
| Config (III) | `env_file`, `environment:` | ConfigMap, Secret |
| Backing services (IV) | Service name as host | Service DNS `<svc>.<ns>.svc.cluster.local` |
| Build/Release/Run (V) | `docker build` + `docker push` + `docker compose up` | CI build + Helm release + `kubectl apply` |
| Processes (VI) | Stateless containers, external volumes | StatefulSet for state, Deployment for stateless |
| Concurrency (VIII) | `--scale worker=N` | `kubectl scale`, HPA |
| Disposability (IX) | `--stop-timeout`, SIGTERM handler | `terminationGracePeriodSeconds`, `preStop` hook |
| Logs (XI) | stdout → log driver | stdout → Fluentd/Loki |
| Admin (XII) | `docker compose run --rm` | `kubectl run --rm -it --restart=Never` |
