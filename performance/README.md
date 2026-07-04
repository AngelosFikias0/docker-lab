# Performance

VMs get pre-allocated resources at provisioning time. Containers share the host kernel and get no limits by default — a single container can exhaust all host CPU and memory. Cgroups are the enforcement layer.

---

## CPU

### CFS and vruntime

Linux uses the Completely Fair Scheduler (CFS). Each process accumulates `vruntime` (virtual runtime). The scheduler always picks the process with the lowest `vruntime` next, keeping execution time proportionally fair across all runnable processes on a core.

Containers share CPU time from the same host pool. No limit set = no bound on consumption.

### --cpus (hard quota)

Sets a hard cap on CPU time via the cgroup `cpu.cfs_quota_us / cpu.cfs_period_us` ratio.

`--cpus=1.0` means the container gets at most one full CPU worth of time per 100ms period, regardless of how many cores the host has or how idle they are.

```bash
docker run --cpus=0.5 myimage      # max 50% of one CPU
docker run --cpus=2.0 myimage      # max 2 full CPUs worth
```

**Throttling:** when the quota is consumed within a period, the container's processes are put to sleep until the next period begins. Throttling shows up in latency, not CPU% — the usage metric sits at the cap while requests pile up.

```bash
docker inspect <container> --format '{{ .HostConfig.NanoCpus }}'
# divide by 1e9 to get CPUs
```

### --cpu-shares (soft weight)

Relative weight for CFS under contention. Default is 1024.

```bash
docker run --cpu-shares=512 a      # A gets 512/(512+1024) = 33% under contention
docker run --cpu-shares=1024 b     # B gets 1024/(512+1024) = 67% under contention
```

Shares have zero effect when no other container competes. A container with `--cpu-shares=100` can use 100% of CPU if no one else wants it. When contention appears, the scheduler applies the weights.

**Shares are not a cap. They are a priority rule for splitting a contested resource.**

### --cpuset-cpus (pinning)

Restricts the container to specific CPU cores. The container's processes never run on other cores.

```bash
docker run --cpuset-cpus=0,1 myimage    # cores 0 and 1 only
docker run --cpuset-cpus=0 myimage      # single core only
```

Use for latency-sensitive workloads where cache locality matters, or to isolate noisy containers from each other at the hardware level.

---

## Memory

### --memory (hard limit)

Hard cap on container RAM. When exceeded, the Linux OOM killer selects a process in the container's cgroup and kills it.

```bash
docker run --memory=512m myimage
docker run --memory=1g myimage
```

Unlike CPU throttling, there is no grace period. The OOM kill is immediate.

### --memory-swap

Total allowed memory + swap combined. Setting it equal to `--memory` disables swap entirely.

```bash
docker run --memory=512m --memory-swap=512m myimage    # no swap
docker run --memory=512m --memory-swap=1g myimage      # 512MB of swap allowed
docker run --memory=512m --memory-swap=-1 myimage      # unlimited swap
```

If unset, `--memory-swap` defaults to 2x `--memory`.

### --memory-reservation

Soft limit. Not enforced under normal conditions. The kernel uses it as a reclaim hint when the host is under memory pressure.

```bash
docker run --memory=1g --memory-reservation=512m myimage
```

### OOM killer

```bash
docker inspect <container> --format '{{ .State.OOMKilled }}'   # true if OOM killed
docker events --filter event=oom                               # stream live OOM events
```

---

## I/O

Block I/O limits apply per device, identified by major:minor number.

```bash
ls -la /dev/sda     # e.g. 8, 0

docker run --device-read-bps /dev/sda:10mb myimage      # max 10MB/s reads
docker run --device-write-bps /dev/sda:10mb myimage     # max 10MB/s writes
docker run --device-read-iops /dev/sda:100 myimage      # max 100 read IOPS
docker run --device-write-iops /dev/sda:100 myimage     # max 100 write IOPS
```

---

## Observability

### docker stats

Live resource usage per container. CPU%, memory usage vs limit, network I/O, block I/O.

```bash
docker stats                          # all running containers, streaming
docker stats --no-stream <container>  # single snapshot
docker stats --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}\t{{.BlockIO}}"
```

### cgroup files (raw kernel view)

```bash
ID=$(docker inspect <container> --format '{{ .Id }}')

# Memory
cat /sys/fs/cgroup/memory/docker/$ID/memory.usage_in_bytes
cat /sys/fs/cgroup/memory/docker/$ID/memory.limit_in_bytes
cat /sys/fs/cgroup/memory/docker/$ID/memory.stat

# CPU
cat /sys/fs/cgroup/cpu/docker/$ID/cpu.cfs_quota_us      # -1 = unlimited
cat /sys/fs/cgroup/cpu/docker/$ID/cpu.cfs_period_us     # default 100000 (100ms)
cat /sys/fs/cgroup/cpu/docker/$ID/cpu.throttled_time    # nanoseconds throttled
```

cgroup v2 unified path: `/sys/fs/cgroup/<id>/`

---

## Cgroups Under the Hood

Docker translates `docker run` flags directly into cgroup file writes. runc creates the cgroup hierarchy, writes the limits, then forks the container process into the cgroup. From that point the kernel enforces everything — Docker is not in the enforcement path.

| Flag                 | Cgroup file                              |
| -------------------- | ---------------------------------------- |
| `--cpus=1.5`         | `cpu.cfs_quota_us = 150000`              |
| `--cpu-shares=512`   | `cpu.shares = 512`                       |
| `--memory=512m`      | `memory.limit_in_bytes = 536870912`      |
| `--memory-swap=512m` | `memory.memsw.limit_in_bytes`            |

---

## Kubernetes Mapping

| Docker flag            | Kubernetes field              | Mechanism                    |
| ---------------------- | ----------------------------- | ---------------------------- |
| `--cpus`               | `resources.limits.cpu`        | `cpu.cfs_quota_us`           |
| `--cpu-shares`         | `resources.requests.cpu`      | `cpu.shares` (scheduling)    |
| `--memory`             | `resources.limits.memory`     | `memory.limit_in_bytes`      |
| `--memory-reservation` | `resources.requests.memory`   | soft hint for scheduler      |

**QoS classes** (assigned automatically by Kubernetes):

| Class        | Condition                                  | OOM priority  |
| ------------ | ------------------------------------------ | ------------- |
| `Guaranteed` | requests == limits for every container     | Last killed   |
| `Burstable`  | requests < limits, or only requests set    | Middle        |
| `BestEffort` | no requests or limits set                  | First killed  |

Always set both `requests` and `limits`. `BestEffort` pods are the first to be evicted under node pressure.

---

## Labs

```
performance/
+-- resource-limits/      # CPU caps, memory limits, I/O throttling, docker stats
+-- cpu-memory-stress/    # Throttling observation, OOM trigger, CPU shares contention
```
