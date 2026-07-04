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

The same cgroup primitives, different API surface. Docker flags map directly to k8s resource fields — kubelet writes the same cgroup files underneath.

### requests vs limits

| Concept    | Docker equivalent      | What it controls                                   |
| ---------- | ---------------------- | -------------------------------------------------- |
| `requests` | `--cpu-shares`         | Scheduling — how much the node reserves for the pod|
| `limits`   | `--cpus` / `--memory`  | Enforcement — cgroup hard cap, OOM kill boundary   |

`requests` determines where the pod lands (scheduler uses it for bin-packing). `limits` determines what happens at runtime (kernel enforces via cgroup). A pod with no `limits` is uncapped — it can starve its neighbors.

```yaml
resources:
  requests:
    cpu: "250m"       # reserve 0.25 CPU on the node
    memory: "128Mi"   # reserve 128MB for scheduling
  limits:
    cpu: "1"          # hard cap: 1 full CPU (throttled if exceeded)
    memory: "256Mi"   # hard cap: OOM kill if exceeded
```

CPU is expressed in millicores (`m`): `500m` = 0.5 CPU = `--cpus=0.5`.

### Flags to fields

| Docker flag            | Kubernetes field              | Cgroup file                  |
| ---------------------- | ----------------------------- | ---------------------------- |
| `--cpus`               | `resources.limits.cpu`        | `cpu.cfs_quota_us`           |
| `--cpu-shares`         | `resources.requests.cpu`      | `cpu.shares`                 |
| `--memory`             | `resources.limits.memory`     | `memory.limit_in_bytes`      |
| `--memory-reservation` | `resources.requests.memory`   | soft scheduling hint         |
| `--cpuset-cpus`        | `resources.limits.cpu` (node-level via topology manager) | `cpuset.cpus` |

### QoS classes

Kubernetes assigns a QoS class automatically based on how requests and limits are configured. This determines OOM kill priority and eviction order when the node is under pressure.

| Class        | Condition                                      | OOM / eviction priority |
| ------------ | ---------------------------------------------- | ----------------------- |
| `Guaranteed` | requests == limits for every container in pod  | Last                    |
| `Burstable`  | requests < limits, or only requests set        | Middle                  |
| `BestEffort` | no requests or limits set anywhere             | First                   |

```bash
kubectl get pod <name> -o jsonpath='{.status.qosClass}'
```

`Guaranteed` is what you want for production workloads. It means the pod gets exactly what it asks for and is the last to be evicted if the node runs out of memory.

### CPU throttling in k8s

The same CFS throttling that happens with `--cpus` happens with `resources.limits.cpu`. A pod limited to `500m` will be throttled when it tries to use more than 50ms of CPU per 100ms period. This is a common source of latency in k8s that doesn't show up in CPU% metrics.

```bash
# Check throttling on a running pod
kubectl exec <pod> -- cat /sys/fs/cgroup/cpu/cpu.stat
# or on the node directly
cat /sys/fs/cgroup/kubepods/<qos>/<pod-uid>/cpu.throttled_time
```

High `throttled_time` with low CPU% = your limit is too tight.

### LimitRange and ResourceQuota

| Object          | Scope     | Purpose                                              |
| --------------- | --------- | ---------------------------------------------------- |
| `LimitRange`    | Namespace | Sets default requests/limits when none are specified |
| `ResourceQuota` | Namespace | Caps total CPU/memory across all pods in a namespace |

```yaml
# LimitRange: auto-apply defaults so no pod runs as BestEffort
apiVersion: v1
kind: LimitRange
metadata:
  name: default-limits
spec:
  limits:
  - default:
      cpu: "500m"
      memory: "256Mi"
    defaultRequest:
      cpu: "100m"
      memory: "128Mi"
    type: Container
```

---

## Labs

```
performance/
+-- resource-limits/      # CPU caps, memory limits, I/O throttling, docker stats
+-- cpu-memory-stress/    # Throttling observation, OOM trigger, CPU shares contention
```
