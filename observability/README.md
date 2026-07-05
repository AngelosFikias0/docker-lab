# Observability

Metrics pipeline for Docker containers: cAdvisor scrapes cgroup data, Prometheus stores and evaluates it, Grafana visualizes it.

---

## Stack

```
containers
  -> cAdvisor          # reads cgroup files + Docker socket, exposes /metrics
    -> Prometheus      # scrapes cAdvisor every 10s, evaluates alert rules
      -> Grafana       # queries Prometheus via PromQL, renders dashboards
```

| Service    | Port | Purpose                        |
| ---------- | ---- | ------------------------------ |
| Prometheus | 9090 | Metrics store, alert rules, UI |
| cAdvisor   | 8080 | Per-container metrics endpoint |
| Grafana    | 3000 | Dashboards (admin / admin)     |

```bash
docker compose up -d
```

The Grafana dashboard and Prometheus datasource are auto-provisioned on startup — no manual configuration needed.

---

## How cAdvisor Works

cAdvisor reads the same cgroup files inspected manually in the performance module:

```
/sys/fs/cgroup/cpu/docker/<id>/cpu.stat         -> container_cpu_cfs_throttled_periods_total
/sys/fs/cgroup/memory/docker/<id>/memory.usage_in_bytes -> container_memory_usage_bytes
```

It also reads the Docker socket to map cgroup IDs to container names and labels. The result is a `/metrics` endpoint in Prometheus exposition format that Prometheus scrapes on every `scrape_interval`.

**Internal pipeline:**

1. **Discovery** — watches the container runtime (via Docker socket / containerd) for running containers. Auto-detects new containers as they start and stop with no manual registration.
2. **Collection** — reads directly from `/sys/fs/cgroup/` for CPU, memory, network, and disk I/O. Polls at short intervals (default ~1s, tunable in the Kubernetes kubelet context).
3. **Metrics captured** — CPU usage + throttling + per-core breakdown; memory working set, RSS, cache, page faults; filesystem usage + I/O rates; network rx/tx bytes, errors, drops.
4. **Aggregation** — rolls up container-level stats to pod-level in the Kubernetes context. Maintains a short in-memory time-series window — long-term storage is Prometheus's job, not cAdvisor's.
5. **Exposure** — `/metrics` in Prometheus format, `/api/v1/...` REST API. In Kubernetes, kubelet embeds cAdvisor and exposes it at `/metrics/cadvisor` on port 10250.

---

## Prometheus

Prometheus pulls metrics from targets at a fixed interval (10s here) and stores them as time series in its local TSDB. Each series is identified by a metric name + label set.

**Targets UI:** `http://localhost:9090/targets` — all targets should show `UP`.

**Alert rules UI:** `http://localhost:9090/alerts` — shows current state of each rule: `inactive`, `pending`, or `firing`.

### PromQL Reference

```promql
# CPU usage per container as a percentage
rate(container_cpu_usage_seconds_total{name!=""}[2m]) * 100

# CPU throttle ratio (0–1, >0.25 triggers alert)
rate(container_cpu_cfs_throttled_periods_total{name!=""}[2m])
/
rate(container_cpu_cfs_periods_total{name!=""}[2m])

# Memory usage per container in bytes
container_memory_usage_bytes{name!=""}

# Memory usage as % of limit
container_memory_usage_bytes{name!=""}
/
container_spec_memory_limit_bytes{name!=""}

# OOM kill events (non-zero = container was killed)
container_oom_events_total{name!=""}

# Network receive rate (bytes/sec)
rate(container_network_receive_bytes_total{name!=""}[2m])

# Top 3 containers by memory
topk(3, container_memory_usage_bytes{name!=""})
```

`rate()` requires a range vector (`[2m]`). It computes per-second average change over that window. Use `irate()` for spiky metrics where you want instantaneous rate rather than average.

---

## Alert Rules

Defined in `prometheus/alerts.yml`, evaluated every 10s.

| Alert | Condition | Severity |
| ----- | --------- | -------- |
| `ContainerHighCPUThrottling` | Throttle ratio > 25% for 30s | warning |
| `ContainerOOMKilled` | OOM events increment in 5m window | critical |
| `ContainerHighMemoryUsage` | Memory > 85% of limit for 30s | warning |

Alerts transition: `inactive` -> `pending` (condition met, within `for` duration) -> `firing`. Without Alertmanager configured, fired alerts are visible in the Prometheus UI but not routed anywhere. Alertmanager handles routing to Slack, PagerDuty, email, etc.

---

## Grafana Dashboard

Auto-provisioned at startup. Six panels:

| Panel | PromQL |
| ----- | ------ |
| Running containers | `count(container_last_seen{name!=""})` |
| Total memory in use | `sum(container_memory_usage_bytes{name!=""})` |
| CPU % per container | `rate(container_cpu_usage_seconds_total{name!=""}[2m]) * 100` |
| Memory per container | `container_memory_usage_bytes{name!=""}` |
| CPU throttle ratio | throttled periods / total periods |
| Network I/O | rx + tx bytes/sec per container |

The throttle ratio panel has a red threshold line at 25% — the same value the `ContainerHighCPUThrottling` alert uses.

---

## Prometheus Service Discovery

Static targets in `prometheus.yml` work for this lab but don't scale. In production Kubernetes, Prometheus uses dynamic service discovery to find targets automatically.

```yaml
scrape_configs:
  - job_name: kubernetes-pods
    kubernetes_sd_configs:
      - role: pod
    relabel_configs:
      # only scrape pods that opt in with this annotation
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
        action: keep
        regex: "true"
      # use the annotated port instead of the default
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_port]
        action: replace
        target_label: __address__
        regex: (.+)
        replacement: $1
```

Pods annotate themselves with `prometheus.io/scrape: "true"` and `prometheus.io/port: "9090"`. Prometheus's relabeling picks them up automatically on every scrape cycle. No manual target list, no config change per deploy.

**Relabeling** is the filter/transform step between raw discovery output (noisy — every pod, every port) and what actually gets scraped. `source_labels`, `action: keep/drop/replace`, and `regex` are the building blocks.

**Storage** — scraped samples land in the local TSDB (2-hour blocks, compacted, WAL for crash recovery). For long-term storage and multi-cluster global query, Prometheus remote-writes to Thanos, Cortex, or Mimir.

---

## Grafana — Advanced

**Dashboard variables** — templated PromQL using `label_values()` queries against Prometheus build dropdown filters for namespace, pod, job, etc. Critical for multi-tenant dashboards — hardcoding a container name in PromQL means the dashboard is useless for everything else.

**Two alerting paths:**

| Path | Where rules live | Who routes |
| ---- | ---------------- | ---------- |
| Prometheus + Alertmanager | `alerts.yml` in Prometheus | Alertmanager (dedup, silence, route to Slack/PD/email) |
| Grafana-native alerting | Inside Grafana | Grafana contact points |

Prometheus + Alertmanager is the standard for production. Grafana-native alerting (post-Grafana 8) is useful when you want a single alerting UI across multiple data sources, not just Prometheus.

---

## node_exporter

cAdvisor reports container-level metrics. Neither cAdvisor nor `kube-state-metrics` touches the OS layer. Node-level data (CPU load, disk I/O, memory pressure, network interface stats) requires `node_exporter`.

**What it does:** runs as a daemon on every node, reads `/proc` and `/sys` directly, exposes CPU, memory, disk I/O, network, filesystem, and load average as Prometheus-format metrics on port 9100.

**Kubernetes deployment:** DaemonSet — one pod per node with `hostNetwork: true` and read-only `/proc` and `/sys` mounts from the host:

```yaml
volumes:
  - name: proc
    hostPath: { path: /proc }
  - name: sys
    hostPath: { path: /sys }
```

Without these host mounts, node_exporter reads the container's cgroup view, not the node's — wrong data entirely.

**Exceptions that need more than proc/sys:**
- Filesystem collector — calls `statfs()` syscall against each mount point, needs broader host filesystem visibility.
- Textfile collector — reads `.prom` files from a custom directory; used to inject metrics from cron jobs or batch scripts.
- Systemd collector — talks to systemd over D-Bus, not proc/sys at all.

---

## Common Pitfalls

- **Static config in Kubernetes** — hand-editing target lists per deploy doesn't scale. Use `kubernetes_sd_config` + relabeling.
- **Label cardinality explosions** — high-cardinality labels (request IDs, user IDs as labels) create one time series per unique value. Directly hits Prometheus memory and query latency. Watch `__name__` and label count.
- **Grafana as a data store** — Grafana renders. If Prometheus is down, dashboards are empty. Grafana has no historical data of its own.
- **scrape_timeout >= scrape_interval** — causes overlapping scrapes on slow targets. `scrape_timeout` must always be less than `scrape_interval`.

---

## Kubernetes Mapping

This exact stack is how production Kubernetes monitoring works.

| This lab | Kubernetes equivalent |
| -------- | --------------------- |
| cAdvisor (standalone) | cAdvisor runs embedded inside `kubelet` on every node |
| Prometheus (manual config) | `kube-prometheus-stack` Helm chart (Prometheus Operator) |
| Grafana (manual provisioning) | Included in `kube-prometheus-stack`, pre-built k8s dashboards |
| Alert rules in `alerts.yml` | `PrometheusRule` CRD — same YAML structure, Kubernetes-managed |
| Alertmanager (not deployed here) | `AlertmanagerConfig` CRD in kube-prometheus-stack |

`metrics-server` is a lighter alternative used only for `kubectl top` and HPA autoscaling — it does not store metrics or support alerting. Prometheus is the production-grade choice.

```bash
# equivalent kubectl commands to what you did with PromQL
kubectl top pods --all-namespaces
kubectl top nodes
```
