# Debugging Containers

Playbook for diagnosing common Docker problems.

---

## Container exits immediately

**Symptoms:** `docker run myapp` returns instantly, container status is `Exited (1)`.

**Diagnosis:**

```bash
docker logs <container>             # check stderr output
docker inspect <container> --format '{{ .State.ExitCode }}'
docker inspect <container> --format '{{ .State.Error }}'
```

**Common causes:**

| Exit code | Cause |
| --------- | ----- |
| 1 | Application error (check logs) |
| 127 | Command not found — wrong entrypoint or CMD |
| 126 | Command not executable — permission issue |
| 137 | OOM kill (exit code = 128 + signal 9) |
| 143 | SIGTERM received but not handled (128 + 15) |

**Fix pattern:** override CMD to get a shell and inspect the environment:

```bash
docker run --rm -it --entrypoint sh myapp
# check: ls, env, which <binary>, cat /etc/passwd
```

---

## Container starts but app is unreachable

**Symptoms:** container is running, port is published, connection refused or times out.

**Diagnosis:**

```bash
# confirm port is actually published
docker port <container>

# confirm process is listening inside the container
docker exec <container> ss -tulnp
# or
docker exec <container> netstat -tulnp

# check if it's listening on 127.0.0.1 instead of 0.0.0.0
docker exec <container> ss -tulnp | grep LISTEN
```

**Common causes:**

- App bound to `127.0.0.1` (loopback only) — must bind to `0.0.0.0` inside the container.
- Published port on wrong interface: `docker run -p 127.0.0.1:8080:80` — only accessible from host, not network.
- Firewall/iptables dropping traffic: check `iptables -L DOCKER -n`.

---

## Container is slow / high CPU

**Symptoms:** app works but response time is bad, `docker stats` shows throttling.

```bash
docker stats <container>            # live CPU%, MEM, NET I/O
docker top <container>              # processes inside with CPU/MEM
docker exec <container> top        # interactive process view inside
```

**CPU throttling** — check if the container is hitting its quota:

```bash
CGROUP=$(docker inspect <container> --format '{{ .Id }}')
cat /sys/fs/cgroup/cpu/docker/$CGROUP/cpu.stat
# look for throttled_time > 0
```

If `throttled_time` is climbing, raise `--cpus` or reduce load.

---

## OOM kill

**Symptoms:** container exits with code 137, `docker inspect` shows `OOMKilled: true`.

```bash
docker inspect <container> --format '{{ .State.OOMKilled }}'
dmesg | grep -i "out of memory"     # kernel OOM log
```

**Fix options:**
- Raise `--memory` limit.
- Add `--memory-swap` to allow swap buffer.
- Profile the app for leaks: `docker exec <container> cat /proc/<pid>/status | grep VmRSS`.

---

## Network connectivity issues

**Symptoms:** container can't reach another container or the internet.

```bash
# test DNS resolution
docker exec <container> nslookup other-container 127.0.0.11

# test reachability
docker exec <container> ping other-container
docker exec <container> wget -qO- http://other-container:8080

# confirm both containers are on the same network
docker network inspect <network> --format '{{ range .Containers }}{{ .Name }} {{ end }}'
```

**Common causes:**

- Containers on different networks — connect with `docker network connect`.
- Using default bridge — no embedded DNS. Switch to a user-defined network.
- Service name mismatch — DNS resolves the container name, not the image name.
- App inside container uses hardcoded `localhost` — must use container/service name.

---

## Debugging without a shell (distroless / scratch)

When there's no shell in the image:

```bash
# copy a static debug binary into the running container
docker cp /usr/bin/busybox <container>:/busybox
docker exec <container> /busybox sh

# or use --pid to share the container's process namespace from a debug container
docker run --rm -it \
  --pid=container:<container> \
  --network=container:<container> \
  --volumes-from <container> \
  busybox sh
```

---

## Inspect the process tree

```bash
ps axlfww                       # full process tree with arguments, forest view
ps -ejH                         # process hierarchy with session/group IDs
pstree -p                       # visual tree with PIDs
ps aux | grep containerd-shim   # find all container root processes on the host
```

`containerd-shim` is the host-side process per container — one shim per container, keeps the container alive even if the daemon restarts. Your container's PID 1 is a child of the shim.

---

## strace — syscall tracing

Intercepts every syscall a process makes to the kernel. Shows the call, arguments, and return value in real time.

**Mechanism:** uses `ptrace(2)` to attach to the target PID. Kernel stops the process at each syscall entry/exit, strace reads registers, decodes arguments, prints, resumes.

**Output format:**
```
open("/etc/nginx/nginx.conf", O_RDONLY) = 3
read(3, "user nginx;\nworker_processes...", 4096) = 512
close(3) = 0
```

**Use cases:**
- Process hanging — see if it's blocked on `read`, `connect`, or `futex`
- Missing files — grep for `ENOENT` in `open`/`openat` calls
- Permission issues — `EACCES` on file or socket ops
- Reverse-engineer undocumented binary behavior

```bash
strace -p <pid>                 # attach to running process
strace -f -p <pid>              # follow forked children too
strace -e trace=network -p <pid># filter to network syscalls only
strace -c -p <pid>              # summary: count + time per syscall type
strace -T -p <pid>              # show time spent inside each syscall
strace -o out.log -p <pid>      # dump to file instead of stdout
```

**Cost:** significant overhead. Every syscall round-trips through the tracer. Don't run on production hot paths without measuring impact. For lower overhead, use `perf trace` (tracepoints) or `bpftrace` (eBPF).

**Container context:** attaching to a container PID works because `ptrace` operates on host PIDs — namespaces don't block it if you have `CAP_SYS_PTRACE`. Same reason `docker exec` and `nsenter` work.

---

## docker container diff — filesystem changes

Shows what changed in the container's writable layer relative to the image.

```
A = added
C = changed (content or metadata)
D = deleted
```

```bash
docker container diff <container>
```

**Practical workflow:**

```bash
# 1. See what changed
docker container diff <container>

# 2. Pull the file out to inspect content
docker cp <container>:/etc/nginx/conf.d/default.conf ./check.conf

# 3. Full context / size — export entire rootfs
docker container export <container> | tar -tvf - | grep nginx

# 4. Live process attribution — who is writing
docker exec <container> ls -la /var/cache/nginx

# 5. Deeper — enter the container's mount namespace from the host
nsenter -t $(docker inspect -f '{{.State.Pid}}' <container>) -m -- find /var/cache -newer /tmp
```

**Kubernetes mapping:** `container diff` is why `readOnlyRootFilesystem: true` exists in pod security context. Anything showing up as `A`/`C` outside expected scratch paths (`/tmp`, `/var/cache`) is a signal those paths need an explicit `emptyDir` volume mount, not root filesystem write access. Detect it structurally at deploy time rather than manually diffing at runtime.

Fleet-scale drift detection: `docker container diff` is single-container only. For production, use image scanning (Trivy/Grype) at build time and Falco runtime rules for unexpected file writes across a cluster.

---

## Network inspection

```bash
docker network ls
docker network inspect <network>

# active sockets on the host
netstat -an         # all sockets, numeric (no DNS lookups)
ss -tulnp           # same, modern replacement
```

Containers connected via the default bridge show published ports as `docker-proxy` in `netstat`, not as your application process. `docker-proxy` is the userspace component that forwards host-port traffic into the container's network namespace.

Use `docker container ls` to cross-reference exposed ports to container names — `netstat` alone won't tell you which container owns a port.

With `--network host`, there's no proxy layer — the containerized process binds the host port directly and appears in `netstat` as its own binary name (e.g. `nginx`, `node`).

---

## Read live state without exec

```bash
docker logs -f <container>                              # follow stdout/stderr
docker events --filter container=<container>            # real-time Docker events
docker inspect <container>                              # full JSON metadata
nsenter -t $(docker inspect -f '{{.State.Pid}}' <c>) -n ss -tulnp   # enter netns directly
```

```bash
# Docker daemon event broadcaster — every state change in real time
docker system events
docker system events --filter type=container --filter event=die
```

The daemon's internal event broadcaster fires on every state mutation — container lifecycle, network connect/disconnect, image pull, volume create. `docker system events` is a subscriber to that stream. Useful for debugging race conditions or unexpected container exits without polling `docker inspect`.
