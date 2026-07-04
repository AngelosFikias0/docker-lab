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
