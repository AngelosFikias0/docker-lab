# Linux Basics

The primitives Docker is built on. Understanding these removes the abstraction.

---

## Everything is a process

Linux runs one kernel. All programs are processes. Processes are created by `fork()` (clone the parent) then `exec()` (replace with new program). Every process has a PID, a parent PID (PPID), and belongs to a process tree rooted at PID 1.

```bash
ps aux                  # all running processes
ps -ef --forest         # process tree with hierarchy
pstree -p               # visual tree with PIDs
cat /proc/<pid>/status  # raw process info from kernel
```

PID 1 is special: it receives signals that orphaned processes deliver, and it does not get automatically killed by SIGTERM. In a container, your entrypoint becomes PID 1 — which is why exec form matters.

---

## Signals

The primary way to communicate with a running process.

| Signal    | Number | Default behavior                             |
| --------- | ------ | -------------------------------------------- |
| `SIGTERM` | 15     | Graceful shutdown (catchable, ignorable)     |
| `SIGKILL` | 9      | Immediate kill (cannot be caught or ignored) |
| `SIGINT`  | 2      | Interrupt (Ctrl+C)                           |
| `SIGHUP`  | 1      | Hangup / reload config                       |

`docker stop` sends SIGTERM, waits the grace period, then SIGKILL. If your process ignores SIGTERM (e.g. because `/bin/sh` is PID 1 in shell form), it gets force-killed with no cleanup.

---

## File descriptors and everything-is-a-file

Every process has a file descriptor table. stdin=0, stdout=1, stderr=2. Regular files, sockets, pipes, devices — all accessed via file descriptors.

```bash
ls /proc/<pid>/fd       # open file descriptors for a process
lsof -p <pid>           # all files/sockets a process has open
```

---

## The filesystem hierarchy

```
/               root of the entire filesystem tree
/etc/           configuration files
/var/lib/       persistent application state (Docker stores data here)
/proc/          virtual FS: live kernel and process data (not on disk)
/sys/           virtual FS: kernel objects, devices, cgroups
/dev/           device files (block devices, character devices)
/tmp/           ephemeral scratch space, cleared on reboot
/run/           runtime data (PIDs, sockets), cleared on reboot
```

`/proc` and `/sys` contain no real files — the kernel generates their content on every read. Useful for inspecting live state without any external tools.

---

## Namespaces

Kernel feature that wraps a global resource so a process sees its own isolated instance. Containers are a combination of several namespaces applied together.

| Namespace | Isolates                                                     |
| --------- | ------------------------------------------------------------ |
| `pid`     | Process IDs — container sees its own PID 1                   |
| `net`     | Network interfaces, routes, iptables                         |
| `mnt`     | Filesystem mount points                                      |
| `uts`     | Hostname and domain name                                     |
| `ipc`     | Inter-process communication (shared memory)                  |
| `user`    | UIDs and GIDs (maps container root to unprivileged host UID) |

```bash
ls -la /proc/<pid>/ns/          # namespaces a process belongs to
lsns                            # list all namespaces on the host
nsenter -t <pid> -n ip addr     # enter a process's network namespace
```

---

## Cgroups

Kernel feature that limits and accounts for resource usage per group of processes. Namespaces control what a process *sees*. Cgroups control what it *uses*.

```
/sys/fs/cgroup/                 # cgroup v2 hierarchy root
  memory/                       # memory limits, usage stats
  cpu/                          # CPU shares, quotas
  io/                           # block I/O throttling
```

Docker translates `--memory` and `--cpus` directly into cgroup limits. In Kubernetes, `resources.limits` in the pod spec does the same thing via kubelet.

```bash
cat /sys/fs/cgroup/memory/<container-cgroup>/memory.limit_in_bytes
docker inspect <container> --format '{{ .HostConfig.Memory }}'
```

---

## File permissions and UIDs

Linux permissions: owner / group / other, each with read/write/execute.

```bash
ls -la          # permissions, owner UID, group GID
stat <file>     # full inode metadata
id              # current user's UID, GID, groups
```

Root = UID 0. Has unrestricted access to everything. Running as root inside a container is dangerous because if the container escapes its namespace, the process is root on the host too. Use `USER` in Dockerfiles and `runAsNonRoot` in k8s.

**Capabilities:** root's powers are split into ~40 discrete capabilities (e.g. `CAP_NET_ADMIN`, `CAP_SYS_PTRACE`). Docker drops most by default. A container can have specific capabilities without being fully privileged.

```bash
capsh --print           # capabilities of current process
```

---

## Key networking primitives

```bash
ip link show            # network interfaces
ip addr show            # interfaces with IP addresses
ip route show           # routing table
ss -tulnp               # open sockets with process info (modern netstat)
iptables -L -n -v       # firewall rules
iptables -t nat -L -n   # NAT rules (MASQUERADE, DNAT)
```

`ip` replaces the old `ifconfig`/`route`/`netstat` commands. `ss` replaces `netstat`. Know both because older systems still use the old ones.

---

## System calls

Processes run in userspace. To do anything real (open a file, send a packet, fork), they make a **syscall** — a controlled jump into kernel mode.

```bash
strace -p <pid>         # trace syscalls of a running process
strace <command>        # trace syscalls of a command from start
```

Useful for debugging containers that fail silently — `strace` shows exactly what system call failed and why.

---

## Essential commands reference

```bash
# processes
ps aux / ps -ef --forest
top / htop
kill -SIGTERM <pid>
lsof -p <pid>

# filesystem
stat <file>
df -h                   # disk usage by mount
du -sh <dir>            # size of a directory
mount | grep overlay    # active overlay mounts

# networking
ip addr / ip link / ip route
ss -tulnp
iptables -L -n -v

# debugging
strace <cmd>
lsns
nsenter -t <pid> -n <cmd>
cat /proc/<pid>/cmdline
cat /proc/<pid>/environ
```

---

## chroot and unshare

Two primitives that predate Docker but underpin how containers work.

### chroot

Changes the apparent root directory for a process and its children. The process cannot navigate above its new root — it is locked in a "chroot jail."

```bash
# Create a minimal root filesystem
mkdir -p /tmp/myjail/{bin,lib,lib64}
cp /bin/sh /tmp/myjail/bin/
# copy required shared libs...

chroot /tmp/myjail /bin/sh
# inside: / is now /tmp/myjail on the real host
# cannot cd .. above /
```

chroot only isolates the **filesystem view**. It does not isolate PIDs, network, or users — those require namespaces. A root process in a chroot can still interact with host processes via `/proc`. chroot is necessary but not sufficient for container isolation.

Container filesystems work the same way: the container's root `/` is a directory on the host's real filesystem, treated as `/` by a different mount namespace.

### unshare

Creates new namespaces for a process without requiring a container runtime. The low-level equivalent of `docker run` for experimenting with isolation primitives.

```bash
# Create a new PID + network namespace for a shell
unshare --pid --net --fork --mount-proc bash
# inside: PID 1 is your shell, no network interfaces visible

# Create a user namespace (unprivileged)
unshare --user --map-root-user bash
# inside: appears as root, but mapped to your real UID on the host
```

`unshare` is used in tests, container runtimes, and sandboxes. Docker's runc uses these syscalls (`CLONE_NEWPID`, `CLONE_NEWNET`, etc.) when starting a container.

---

## /sys: kernel state interface

`/sys` is a virtual filesystem (sysfs) that exposes the internal state of the kernel, device drivers, and hardware to userspace. Nothing on disk — generated on every read.

```
/sys/
  block/          # block devices (disks)
  bus/            # hardware bus subsystems
  class/          # device classes (net, block, etc.)
  devices/        # device tree
  fs/             # filesystem-related kernel state
  fs/cgroup/      # cgroup v2 hierarchy
  kernel/         # kernel parameters
  net/            # network device state
  power/          # power management
```

For container work, the relevant subtrees:

```bash
# cgroup limits and stats for a Docker container
/sys/fs/cgroup/system.slice/docker-<id>.scope/
  memory.current          # current memory usage in bytes
  memory.max              # memory limit
  cpu.stat                # CPU usage counters
  cpu.max                 # CPU quota/period

# network device state
/sys/class/net/<interface>/
  /sys/class/net/eth0/address    # MAC address
  /sys/class/net/eth0/mtu        # MTU
  /sys/class/net/eth0/operstate  # up/down
```

The cgroup path for a specific container:

```bash
# find the container's cgroup path
docker inspect <id> --format '{{ .HostConfig.CgroupParent }}'
# or
cat /proc/<container-pid>/cgroup
```

Docker uses `/sys/fs/cgroup/` not just to enforce limits but also to read resource usage for `docker stats`.
