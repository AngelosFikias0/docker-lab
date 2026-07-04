#!/usr/bin/env bash
# resource-limits/exercises.sh
# Run blocks individually. Each section is self-contained.
# Not meant to be executed top-to-bottom as a pipeline.

# ---------------------------------------------------------------------------
# 1. BASELINE - no limits
# Container can use all available host CPU and memory.
# Open a second terminal and run: docker stats baseline
# ---------------------------------------------------------------------------
docker run -d --name baseline \
  alpine sh -c "while true; do :; done"

docker stats --no-stream baseline
docker stop baseline && docker rm baseline

# ---------------------------------------------------------------------------
# 2. CPU HARD CAP - --cpus
# Container is limited to 25% of one CPU regardless of host load.
# When quota is consumed the process is throttled until the next 100ms period.
# Open a second terminal: docker stats cpu-capped
# ---------------------------------------------------------------------------
docker run -d --name cpu-capped \
  --cpus=0.25 \
  alpine sh -c "while true; do :; done"

docker stats --no-stream cpu-capped
# CPUPerc should hover near 25%

docker inspect cpu-capped --format 'NanoCpus: {{ .HostConfig.NanoCpus }}'
# NanoCpus / 1e9 = 0.25 CPUs

docker stop cpu-capped && docker rm cpu-capped

# ---------------------------------------------------------------------------
# 3. CPU SHARES - soft weight under contention
# Shares only matter when two containers compete for the same CPU time.
# Without contention both containers use 100% — shares are irrelevant.
# Run both, then watch stats while both are spinning.
# ---------------------------------------------------------------------------
docker run -d --name low-priority  --cpu-shares=256  alpine sh -c "while true; do :; done"
docker run -d --name high-priority --cpu-shares=1024 alpine sh -c "while true; do :; done"

# Under contention: low-priority gets ~20%, high-priority gets ~80%
docker stats --no-stream low-priority high-priority

docker stop low-priority high-priority && docker rm low-priority high-priority

# ---------------------------------------------------------------------------
# 4. CPU PINNING - restrict to specific cores
# --cpuset-cpus pins the container to given cores only.
# Processes in this container will never run on other cores.
# ---------------------------------------------------------------------------
docker run -d --name pinned \
  --cpuset-cpus=0 \
  alpine sh -c "while true; do :; done"

docker inspect pinned --format 'CpusetCpus: {{ .HostConfig.CpusetCpus }}'
# CpusetCpus: 0

docker stats --no-stream pinned
docker stop pinned && docker rm pinned

# ---------------------------------------------------------------------------
# 5. MEMORY LIMIT - --memory
# Container is allowed 64MB. Writing more triggers OOM kill.
# ---------------------------------------------------------------------------
docker run -d --name mem-limited \
  --memory=64m \
  alpine sleep infinity

docker inspect mem-limited --format 'Memory: {{ .HostConfig.Memory }}'
# Memory: 67108864 (64 * 1024 * 1024 bytes)

docker stats --no-stream mem-limited
docker stop mem-limited && docker rm mem-limited

# ---------------------------------------------------------------------------
# 6. OOM KILL - exceed memory limit deliberately
# Allocate 200MB inside a 64MB container. OOM killer will terminate the process.
# ---------------------------------------------------------------------------
docker run --rm \
  --memory=64m \
  --memory-swap=64m \
  alpine sh -c "dd if=/dev/zero of=/dev/shm/fill bs=1M count=200 2>&1 || echo 'killed'"

# Run with --oom-kill-disable to see the container hang instead
# (do not do this in production - container will freeze and require manual kill)

# ---------------------------------------------------------------------------
# 7. DISABLE SWAP
# --memory-swap equal to --memory means no swap allowed.
# Default is 2x --memory if not set.
# ---------------------------------------------------------------------------
docker run -d --name no-swap \
  --memory=128m \
  --memory-swap=128m \
  alpine sleep infinity

docker inspect no-swap \
  --format 'Memory: {{ .HostConfig.Memory }}  MemorySwap: {{ .HostConfig.MemorySwap }}'

docker stop no-swap && docker rm no-swap

# ---------------------------------------------------------------------------
# 8. INSPECT CONFIGURED LIMITS
# All resource constraints are visible via docker inspect.
# ---------------------------------------------------------------------------
docker run -d --name inspect-limits \
  --cpus=0.5 \
  --cpu-shares=512 \
  --memory=256m \
  --memory-swap=256m \
  alpine sleep infinity

docker inspect inspect-limits --format \
  'CPUs: {{ .HostConfig.NanoCpus }}  Shares: {{ .HostConfig.CpuShares }}  Memory: {{ .HostConfig.Memory }}'

docker stop inspect-limits && docker rm inspect-limits

# ---------------------------------------------------------------------------
# 9. READ CGROUP FILES DIRECTLY
# Docker writes these files. The kernel reads them for enforcement.
# Requires root on the host.
# ---------------------------------------------------------------------------
docker run -d --name cgroup-demo \
  --cpus=1.0 \
  --memory=256m \
  alpine sleep infinity

ID=$(docker inspect cgroup-demo --format '{{ .Id }}')

echo "--- CPU quota (100000 = 1 CPU) ---"
sudo cat /sys/fs/cgroup/cpu/docker/$ID/cpu.cfs_quota_us 2>/dev/null \
  || sudo cat /sys/fs/cgroup/$ID/cpu.max 2>/dev/null

echo "--- Memory limit (bytes) ---"
sudo cat /sys/fs/cgroup/memory/docker/$ID/memory.limit_in_bytes 2>/dev/null \
  || sudo cat /sys/fs/cgroup/$ID/memory.max 2>/dev/null

docker stop cgroup-demo && docker rm cgroup-demo

# ---------------------------------------------------------------------------
# 10. DOCKER STATS FORMATTED OUTPUT
# ---------------------------------------------------------------------------
docker run -d --name stats-demo --memory=128m --cpus=0.5 alpine sleep infinity

docker stats --no-stream \
  --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}\t{{.BlockIO}}"

docker stop stats-demo && docker rm stats-demo
