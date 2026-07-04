#!/usr/bin/env bash
# cpu-memory-stress/exercises.sh
# Run blocks individually. Each section is self-contained.
# Build the image first: docker build -t stress:latest .

# ---------------------------------------------------------------------------
# 1. BUILD THE STRESS IMAGE
# ---------------------------------------------------------------------------
docker build -t stress:latest .

# ---------------------------------------------------------------------------
# 2. CPU STRESS WITHOUT A LIMIT - baseline
# Two CPU workers spinning. Host CPU usage climbs to whatever is available.
# Open a second terminal: docker stats cpu-no-limit
# ---------------------------------------------------------------------------
docker run -d --name cpu-no-limit \
  stress:latest --cpu 2 --timeout 30s

docker stats --no-stream cpu-no-limit
docker wait cpu-no-limit && docker rm cpu-no-limit

# ---------------------------------------------------------------------------
# 3. CPU THROTTLING - same workers, hard cap applied
# Two CPU workers but container is limited to 0.5 CPUs.
# The workers will be throttled. CPU% in stats stays near 50%.
# Open a second terminal: docker stats cpu-throttled
# ---------------------------------------------------------------------------
docker run -d --name cpu-throttled \
  --cpus=0.5 \
  stress:latest --cpu 2 --timeout 30s

docker stats --no-stream cpu-throttled

# Check how much time was throttled
ID=$(docker inspect cpu-throttled --format '{{ .Id }}')
echo "Throttled time (nanoseconds):"
sudo cat /sys/fs/cgroup/cpu/docker/$ID/cpu.throttled_time 2>/dev/null \
  || sudo cat /sys/fs/cgroup/$ID/cpu.stat 2>/dev/null | grep throttled

docker wait cpu-throttled && docker rm cpu-throttled

# ---------------------------------------------------------------------------
# 4. CPU SHARES CONTENTION - observe the weight ratio in action
# Run both containers simultaneously and watch the CPU split in docker stats.
# Without contention each gets 100%. With both running the ratio appears.
# Open a second terminal: docker stats low-share high-share
# ---------------------------------------------------------------------------
docker run -d --name low-share \
  --cpu-shares=256 \
  stress:latest --cpu 1 --timeout 30s

docker run -d --name high-share \
  --cpu-shares=1024 \
  stress:latest --cpu 1 --timeout 30s

# Expected: low-share ~20%, high-share ~80% (256:1024 ratio)
docker stats --no-stream low-share high-share

docker wait low-share high-share
docker rm low-share high-share

# ---------------------------------------------------------------------------
# 5. MEMORY STRESS - stay under the limit
# 2 VM workers each allocating 64MB. Container limit is 256MB.
# Should run cleanly to completion.
# ---------------------------------------------------------------------------
docker run --rm --name mem-ok \
  --memory=256m \
  --memory-swap=256m \
  stress:latest --vm 2 --vm-bytes 64M --timeout 15s --metrics-brief

# ---------------------------------------------------------------------------
# 6. OOM KILL - exceed the memory limit
# VM workers try to allocate 200MB total in a 64MB container.
# The OOM killer will terminate the process mid-run.
# ---------------------------------------------------------------------------
docker run --name oom-demo \
  --memory=64m \
  --memory-swap=64m \
  stress:latest --vm 1 --vm-bytes 200M --timeout 30s

echo "Exit code: $?"
docker inspect oom-demo --format 'OOMKilled: {{ .State.OOMKilled }}'
# OOMKilled: true

docker rm oom-demo

# ---------------------------------------------------------------------------
# 7. COMBINED STRESS - CPU + memory simultaneously
# Simulates a realistic workload. Watch both CPU% and memory usage in stats.
# Open a second terminal: docker stats combined-stress
# ---------------------------------------------------------------------------
docker run -d --name combined-stress \
  --cpus=1.0 \
  --memory=256m \
  --memory-swap=256m \
  stress:latest --cpu 2 --vm 1 --vm-bytes 128M --timeout 30s

docker stats --no-stream combined-stress

docker wait combined-stress && docker rm combined-stress

# ---------------------------------------------------------------------------
# 8. CPU PINNING UNDER STRESS
# Pin the container to core 0 only. All stress workers share that one core.
# Compare against unpinned: same --cpus but different core affinity.
# ---------------------------------------------------------------------------
docker run -d --name pinned-stress \
  --cpuset-cpus=0 \
  stress:latest --cpu 4 --timeout 20s

docker stats --no-stream pinned-stress
# All 4 workers compete for a single core - throughput is bounded by core 0

docker wait pinned-stress && docker rm pinned-stress

# ---------------------------------------------------------------------------
# 9. CLEANUP
# ---------------------------------------------------------------------------
docker rmi stress:latest
