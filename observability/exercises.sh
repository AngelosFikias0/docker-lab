#!/usr/bin/env bash
set -euo pipefail

# ─── Block 1: Start the stack ────────────────────────────────────────────────
echo "=== Block 1: Start the observability stack ==="
docker compose up -d

echo "Waiting for all services to be ready..."
sleep 10

docker compose ps
echo ""
echo "Prometheus : http://localhost:9090"
echo "cAdvisor   : http://localhost:8080"
echo "Grafana    : http://localhost:3000  (admin / admin)"

# ─── Block 2: Verify Prometheus targets ──────────────────────────────────────
echo ""
echo "=== Block 2: Prometheus scrape targets ==="
# All targets should show health: "up"
curl -s 'http://localhost:9090/api/v1/targets' \
  | jq '.data.activeTargets[] | {job: .labels.job, instance: .labels.instance, health: .health}'

# ─── Block 3: Query CPU usage per container ──────────────────────────────────
echo ""
echo "=== Block 3: Current CPU usage per container ==="
curl -s 'http://localhost:9090/api/v1/query?query=rate(container_cpu_usage_seconds_total{name!=""}[2m])*100' \
  | jq '.data.result[] | {container: .metric.name, cpu_percent: (.value[1] | tonumber | . * 100 | round / 100)}'

echo ""
echo "--- docker stats snapshot (same source, different interface) ---"
docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}"

# ─── Block 4: Query memory usage ─────────────────────────────────────────────
echo ""
echo "=== Block 4: Memory usage per container ==="
curl -s 'http://localhost:9090/api/v1/query?query=container_memory_usage_bytes{name!=""}' \
  | jq '.data.result[] | {container: .metric.name, memory_mb: (.value[1] | tonumber / 1048576 | round)}'

# ─── Block 5: Stress test — watch CPU spike ──────────────────────────────────
echo ""
echo "=== Block 5: CPU stress — observe throttling ==="
echo "Starting stress container with --cpus=0.5 limit..."
docker run -d \
  --name stress-cpu \
  --cpus=0.5 \
  gcr.io/cadvisor/cadvisor:v0.49.1 \
  stress-ng --cpu 2 --timeout 60 2>/dev/null || \
docker run -d \
  --name stress-cpu \
  --cpus=0.5 \
  alpine sh -c "while true; do :; done" 2>/dev/null || true

sleep 15

echo "CPU usage during stress:"
curl -s 'http://localhost:9090/api/v1/query?query=rate(container_cpu_usage_seconds_total{name="stress-cpu"}[1m])*100' \
  | jq '.data.result[] | {container: .metric.name, cpu_percent: (.value[1] | tonumber | . * 100 | round / 100)}'

echo "Throttle ratio for stress-cpu:"
curl -s 'http://localhost:9090/api/v1/query?query=rate(container_cpu_cfs_throttled_periods_total{name="stress-cpu"}[1m])/rate(container_cpu_cfs_periods_total{name="stress-cpu"}[1m])' \
  | jq '.data.result[] | {container: .metric.name, throttle_ratio: (.value[1] | tonumber | . * 100 | round / 100 | tostring + "%")}'

docker rm -f stress-cpu 2>/dev/null || true

# ─── Block 6: OOM kill — observe the event ───────────────────────────────────
echo ""
echo "=== Block 6: Trigger OOM kill and observe metric ==="
echo "Starting container with 32MB limit and allocating past it..."
docker run -d \
  --name stress-oom \
  --memory=32m \
  --memory-swap=32m \
  python:3.13-slim \
  python3 -c "x = bytearray(64 * 1024 * 1024)" 2>/dev/null || true

sleep 5

echo "OOM events in Prometheus:"
curl -s 'http://localhost:9090/api/v1/query?query=container_oom_events_total{name!=""}' \
  | jq '.data.result[] | select(.value[1] != "0") | {container: .metric.name, oom_events: .value[1]}'

echo "Container state after OOM:"
docker inspect stress-oom --format 'OOMKilled: {{ .State.OOMKilled }}, ExitCode: {{ .State.ExitCode }}' 2>/dev/null || true
docker rm -f stress-oom 2>/dev/null || true

# ─── Block 7: Check alert rules ──────────────────────────────────────────────
echo ""
echo "=== Block 7: Alert rules status ==="
curl -s 'http://localhost:9090/api/v1/rules' \
  | jq '.data.groups[].rules[] | {alert: .name, state: .state, query: .query}'

# ─── Block 8: Explore cAdvisor raw metrics ───────────────────────────────────
echo ""
echo "=== Block 8: cAdvisor raw metrics (sample) ==="
echo "cAdvisor exposes the same cgroup files we read manually in the performance module:"
echo ""
curl -s 'http://localhost:8080/metrics' \
  | grep '^container_memory_usage_bytes{' \
  | grep 'name="' \
  | head -5

echo ""
echo "Full metrics endpoint: http://localhost:8080/metrics"
echo "Prometheus scrape interval: 10s (see prometheus/prometheus.yml)"

# ─── Block 9: PromQL reference queries ───────────────────────────────────────
echo ""
echo "=== Block 9: Useful PromQL queries ==="

echo ""
echo "-- Top container by memory --"
curl -s 'http://localhost:9090/api/v1/query?query=topk(3,container_memory_usage_bytes{name!=""})' \
  | jq '.data.result[] | {container: .metric.name, bytes: (.value[1] | tonumber | round)}'

echo ""
echo "-- Containers with non-zero CPU throttling --"
curl -s 'http://localhost:9090/api/v1/query?query=rate(container_cpu_cfs_throttled_periods_total{name!=""}[5m])>0' \
  | jq '.data.result[] | {container: .metric.name}'

echo ""
echo "-- Network receive rate (bytes/sec) --"
curl -s 'http://localhost:9090/api/v1/query?query=rate(container_network_receive_bytes_total{name!=""}[2m])' \
  | jq '.data.result[] | {container: .metric.name, rx_bps: (.value[1] | tonumber | round)}'

# ─── Block 10: Clean up ──────────────────────────────────────────────────────
echo ""
echo "=== Block 10: Tear down ==="
docker compose down
echo "Stack removed. Volumes retained (run 'docker compose down -v' to also remove them)."
