# Containers

---

## Fundamentals

Linux containers are processes, not VMs. They share the host kernel.

**Isolation primitives:**

| Primitive  | What it controls                                       |
| ---------- | ------------------------------------------------------ |
| Namespaces | What a process can see (PID, NET, MNT, UTS, IPC, USER) |
| Cgroups    | What a process can use (CPU, memory, I/O)              |
| OverlayFS  | Union filesystem at `/var/lib/docker/overlay2/`        |

**Docker architecture:**

```
Client (docker CLI)
  -> Docker Engine API
    -> Docker daemon (dockerd)
      -> containerd -> runc -> container process
      -> Virtual bridge (docker0)
      -> Docker registry (pull/push)
```

OCI images: one or more ordered filesystem layers + metadata (config.json + manifest.json).

---

## History

```
Unix Kernel
-> chroot (1979)         # isolate filesystem root
-> jail (FreeBSD 2000)   # isolate filesystem + processes + network
-> Solaris Zones (2004)  # full OS virtualization on single kernel
-> LXC (2008)            # first Linux cgroups + namespaces combo
-> user namespaces       # unprivileged containers
-> Docker (2013)         # UX layer on top of LXC, later libcontainer/runc
```

---

## systemd and Services

A service is a systemd unit (`.service`). systemd spawns and manages processes:

```
systemctl start nginx
-> nginx.service
   -> nginx master process    (PID tracked by systemd)
   -> worker processes        (child PIDs tracked via cgroups)
```

- `service` = controller (policy, restart, lifecycle)
- `ps` processes = runtime children

---

## Lifecycle

```bash
docker container create <image>   # allocate filesystem + config from image (no process)
docker container start <name>     # start the process
docker container run <image>      # create + start in one step

docker stop <name>                # SIGTERM -> wait grace period -> SIGKILL
docker rm <name>                  # remove stopped container
```

---

## Identity Files

Docker writes three files as **bind mounts** into the container, not as image layers:

```
/etc/hostname     <- container ID short hash (or --hostname value)
/etc/resolv.conf  <- copied from host resolv.conf (or --dns overrides)
/etc/hosts        <- loopback + container name -> IP entry
```

**Implications:**

- Per-container, not per-image. Same image, different container = different files.
- Not in the union filesystem. `docker commit` does not capture changes to them.
- Docker owns their lifecycle; they are regenerated each run.

**Runtime overrides:**

| Flag                         | Effect                                     |
| ---------------------------- | ------------------------------------------ |
| `--hostname foo.example.com` | Sets `/etc/hostname`, enables FQDN         |
| `--dns 8.8.8.8`              | Overrides nameserver in `/etc/resolv.conf` |
| `--dns-search example.com`   | Sets search domain                         |
| `--dns-search .`             | Clears search domain entirely              |

In Kubernetes, this is abstracted: kubelet + CoreDNS manage pod DNS. The equivalent of `--dns` and `--dns-search` is `dnsPolicy` / `dnsConfig` on the PodSpec. Same mechanics underneath the CRI.

---

## Container Data on Disk

Every running or stopped container has a dedicated directory on the host:

```
/var/lib/docker/containers/<full-container-id>/
  config.v2.json    # full container config (image, env, mounts, network)
  hostconfig.json   # runtime config (--cpus, --memory, restart policy)
  <id>-json.log     # stdout/stderr log file (json-file driver)
```

This is what `docker inspect` reads. The log file here is what `docker logs` tails. With the `local` log driver, the format is binary instead of JSON.

```bash
ls /var/lib/docker/containers/
cat /var/lib/docker/containers/<id>/config.v2.json | jq .Config
```

---

## docker container top — UID Gotcha

`docker container top <name>` resolves usernames via the **host's** `/etc/passwd`, not the container's. A UID that maps to `appuser` inside the container may display as a different name or a raw number on the host depending on what UID mappings exist there.

```bash
docker container top <container>    # shown via host /etc/passwd — may be wrong name
docker exec <container> id          # shown via container /etc/passwd — always correct
```

Never trust the display name from `docker container top` for security reasoning — verify the numeric UID with `docker exec`.

---

## crictl

`crictl` is a CLI for runtimes that implement the Kubernetes CRI (Container Runtime Interface). It targets `containerd` and `CRI-O` at the node level. Not a Docker tool.

---

## OCI Runtimes

The OCI runtime spec defines what a runtime must do: unpack a bundle, create namespaces/cgroups, exec the process. `runc` is the reference implementation. Others are drop-in replacements with different isolation trade-offs.

| Runtime | Isolation mechanism | Overhead | Isolation strength | Use case |
|---|---|---|---|---|
| `runc` | namespaces + cgroups (shared host kernel) | near-zero | weak (shared kernel) | default, trusted workloads |
| `crun` | same as runc, written in C | near-zero | same as runc | drop-in runc replacement, faster startup, lower memory |
| `gVisor` (runsc) | user-space kernel intercepts syscalls | low-moderate | medium (no real kernel access) | semi-trusted workloads, GCP Cloud Run |
| `Kata Containers` | full micro-VM per pod (KVM + lightweight VMM) | moderate (~100-200ms boot) | strong (hardware VM boundary) | multi-tenant, untrusted code, compliance |
| `Firecracker` | microVM, no container semantics natively | low (~125ms boot) | strong | serverless (AWS Lambda/Fargate) |

### gVisor in depth

Mechanism: a user-space kernel (called Sentry) intercepts syscalls before they reach the host kernel. Sentry reimplements the Linux kernel surface in Go, running either in ptrace mode or KVM mode.

```
Container process → syscall → Sentry (user-space kernel) → limited real syscalls to host
```

- Compatibility: partial Linux syscall coverage. Syscall-heavy workloads (high I/O) take a performance hit — every syscall traverses Sentry.
- Attack surface: smaller than a full VM, but Sentry itself is a large Go codebase.
- Startup: fast (~100ms). Good for autoscaling and serverless.
- Selected by `RuntimeClass: gvisor` in Kubernetes.

### Kata Containers in depth

Mechanism: real hardware virtualization. Each pod gets a lightweight VM (QEMU or Cloud Hypervisor) with its own kernel. The container runtime interface is presented at the VM boundary.

```
kubelet → CRI → Kata agent → lightweight VM kernel → container process
```

- Full Linux kernel compatibility. Runs anything a normal VM runs.
- Isolation boundary: hardware-enforced via VT-x/AMD-V. Same guarantee as a full VM.
- Startup: ~500ms-1s. Slower than gVisor but full kernel compatibility.
- Attack surface: strongest isolation. Real hardware boundary between tenants.

---

## nsenter vs runc exec

Two ways to enter a running container's namespaces. They look similar but have an important security difference.

### Normal exec path

```
docker exec → dockerd (API) → containerd → containerd-shim → runc exec
```

`runc exec` reads the container's `config.json` and re-applies its full security profile to the new process: seccomp filters, capability drops, no-new-privileges, AppArmor/SELinux labels. The container's security policy is enforced automatically.

```bash
# runc exec (via docker exec)
docker exec mycontainer sh
# → runs with container's seccomp profile, dropped capabilities, etc.
```

### nsenter

```bash
# Direct namespace entry — bypasses the container runtime entirely
nsenter --target <container-pid> --net --pid --mount --uts --ipc -- bash
```

`nsenter` joins only the namespaces you explicitly flag. It reads from `/proc/<pid>/ns/*` only — no config file, no state directory, no security profile reapplication. The new process runs with **your calling shell's privilege set**, not the container's.

```
runc exec  → joins namespaces + inherits full container security policy
nsenter    → joins namespaces + inherits caller's privileges (does NOT apply container policy)
```

**Practical implication:** `nsenter` as root gives you root inside the container's namespaces even if the container runs as UID 10001 with all capabilities dropped. This is useful for debugging distroless/no-shell images but must not be confused with "running as the container would."

`nsenter` also survives runc state corruption — it needs only `/proc/<pid>/ns/`, not runc's state directory.

---

## Alternative Container Runtimes and Tools

| Tool | Type | Notes |
|---|---|---|
| `podman` | Container engine | Docker-compatible CLI, daemonless (no persistent daemon), rootless by default. Drop-in `alias docker=podman` for many workflows. |
| `nerdctl` | Container CLI | Docker-compatible CLI for containerd directly. Good for environments where you want containerd without dockerd overhead. |
| `Rancher Desktop` | Desktop app | Bundles containerd + nerdctl + k3s. Alternative to Docker Desktop on macOS/Windows. |
| `k3s` | Lightweight Kubernetes | Single binary Kubernetes. Default runtime: containerd. Used in edge, IoT, and small clusters. |
| `kubeadm` | Cluster bootstrapping | Standard tool to stand up a production-grade Kubernetes cluster. `kubespray` adds Ansible automation on top. |
| `rke2` | Enterprise Kubernetes | Rancher's hardened Kubernetes distribution. CIS benchmark compliant by default. |
