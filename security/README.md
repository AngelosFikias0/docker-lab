# Security

Reference covering Linux kernel security primitives, Docker hardening, and Kubernetes enforcement. Every layer explained from mechanism up.

---

## Modules

| Module | Covers |
| ------ | ------ |
| `user-permissions/` | Non-root users, UID mapping, capability drops, read-only filesystem |
| `secrets-basics/` | Secret injection patterns, BuildKit secret mounts, Compose secrets |
| `distroless/` | Minimal attack surface, no-shell debugging, CVE comparison |

---

## 1. Kernel-Level Identity

### 1.1 UID/GID

Integers. Kernel authority units. Names in `/etc/passwd` are cosmetic lookups only — kernel checks numbers, not strings. A UID needs no `/etc/passwd` entry to be valid.

### 1.2 Four UID Fields Per Process

```bash
cat /proc/<pid>/status | grep Uid
# Uid: <real> <effective> <saved> <filesystem>
```

| Field                | Purpose                                                                                          |
| -------------------- | ------------------------------------------------------------------------------------------------ |
| **RUID** (Real)      | Who's accountable. Used for `kill()` checks, accounting. Doesn't change during normal execution. |
| **EUID** (Effective) | Checked on every syscall/file access. **This is what matters 95% of the time.**                  |
| **SUID** (Saved)     | Reclaim point. Lets a process drop to RUID and reclaim SUID later without re-`execve()`.         |
| **FSUID**            | Filesystem-check-only. Rarely diverges from EUID. Exists for NFS server edge cases.              |

**setuid trace (`passwd` example):**

```
1. Shell:        RUID=1000, EUID=1000, SUID=1000
2. execve(passwd, setuid-root binary):  RUID=1000, EUID=0, SUID=0
3. seteuid(1000) — drop privilege:       RUID=1000, EUID=1000, SUID=0
4. seteuid(0) — reclaim (SUID=0 allows): RUID=1000, EUID=0, SUID=0
```

No re-exec needed at step 4 — SUID is the ratchet that makes this possible.

### 1.3 Inodes & Permission Bits

Inode = on-disk metadata (owner UID, owner GID, permission bits, size, timestamps). Filename lives in the _directory entry_, not the inode — this is why hardlinks share one inode, one permission set.

```
-rwxrwxrwx
 owner group other
```

**Check order (stops at first match):**

1. EUID == owner UID → owner bits apply
2. GID/supplementary GID == file GID → group bits apply
3. Else → other bits apply

```bash
ls -i file       # inode number
stat file         # full metadata
ls -n file        # numeric UID/GID (trust this over ls -l across namespaces)
chmod 750 file    # numeric form: r=4 w=2 x=1, summed per set
```

### 1.4 UID Ranges — Convention, Not Kernel Law

| Range   | Category                                       | Enforced by                          |
| ------- | ---------------------------------------------- | ------------------------------------ |
| 0       | root                                           | Kernel special-case in DAC checks    |
| 1–99    | Static system accounts                         | Distro packaging convention          |
| 100–999 | Dynamic service accounts (`nginx`, `postgres`) | `useradd --system`                   |
| 1000+   | Human users                                    | `/etc/login.defs` `UID_MIN`          |
| 65534   | `nobody`                                       | Convention — "no privilege" fallback |

Kernel treats every UID identically. Ranges are policy, not mechanism.

---

## 2. Capabilities — Root Decomposed

Pre-2.2 kernel: binary model, UID 0 = unrestricted. Modern kernel: root's power split into ~40 discrete units.

**Default non-root UID (e.g. 1000): empty Effective/Permitted capability set.**

```bash
getpcaps $$
# Capabilities for '<pid>': =        <- empty
```

**Root (UID 0): full capability set + separate kernel DAC bypass.**

```bash
cat /proc/1/status | grep Cap
# CapEff: 000001ffffffffff            <- full mask
capsh --decode=000001ffffffffff       # human-readable list
```

**Critical distinction:** root's DAC bypass (VFS-layer, historical) and root's capability set are two separate mechanisms. Stripping capabilities from a UID-0 process (`--cap-drop=ALL`) still leaves UID 0 special-cased in some DAC paths, but blocks every capability-gated syscall (mount, ptrace, module load, raw socket). This is why `--cap-drop=ALL` on a root container is real hardening, not theater.

### 2.1 High-Risk Capabilities — Never Grant Without Review

| Capability                | Grants                               | Risk                                    |
| ------------------------- | ------------------------------------ | --------------------------------------- |
| `CAP_SYS_ADMIN`           | Catch-all admin (mount, misc ioctls) | **Critical — near-root**                |
| `CAP_SYS_PTRACE`          | Read/write other process memory      | Critical — full compromise vector       |
| `CAP_SYS_MODULE`          | Load kernel modules                  | Critical — kernel code exec             |
| `CAP_SETUID`/`CAP_SETGID` | Change process UID/GID               | High — escalation primitive             |
| `CAP_DAC_OVERRIDE`        | Bypass file rwx checks               | High                                    |
| `CAP_NET_ADMIN`           | Network config, routes, firewall     | High                                    |
| `CAP_NET_BIND_SERVICE`    | Bind ports <1024                     | Low                                     |
| `CAP_NET_RAW`             | Raw sockets, packet crafting         | Medium — Docker default, often unneeded |
| `CAP_CHOWN`               | Arbitrary ownership change           | Medium                                  |
| `CAP_KILL`                | Signal processes not owned by caller | Medium                                  |

### 2.2 Five Capability Sets Per Process

| Set             | Meaning                                                      |
| --------------- | ------------------------------------------------------------ |
| Permitted (P)   | Ceiling — what process _may_ use                             |
| Effective (E)   | Live — what kernel _actually checks_ right now               |
| Inheritable (I) | Passed to children across `execve()`                         |
| Bounding (B)    | Hard ceiling for process + all descendants, lifetime         |
| Ambient (A)     | Survives `execve()` into unprivileged binaries (kernel 4.3+) |

```bash
getpcaps <pid>
cat /proc/<pid>/status | grep Cap
capsh --decode=<hex>
```

### 2.3 Attachment Mechanisms

```bash
# File capability (preferred) — no UID change, one specific bit
setcap cap_net_bind_service=+ep /usr/bin/myserver
getcap /usr/bin/myserver

# setuid bit (legacy) — grants ALL of root, larger blast radius
ls -l /usr/bin/passwd    # -rwsr-xr-x
```

**Rule:** file capability > setuid. Smaller blast radius if the binary is compromised — attacker gets one capability, not full root.

### 2.4 Bounding Set — Privileged-Then-Drop Pattern

```c
bind(port_80);                    // needs CAP_NET_BIND_SERVICE, still root
cap_drop_bound(ALL_EXCEPT_NONE);  // shrink bounding set permanently
setuid(10001);                    // drop UID
// exec real app — no path back to root, ever
```

This is what `gosu`/`su-exec` implement for container entrypoints instead of setuid-at-startup.

### 2.5 Docker Default Capability Set (non-privileged)

```
CAP_CHOWN, CAP_DAC_OVERRIDE, CAP_FOWNER, CAP_FSETID, CAP_KILL,
CAP_SETGID, CAP_SETUID, CAP_SETPCAP, CAP_NET_BIND_SERVICE,
CAP_NET_RAW, CAP_SYS_CHROOT, CAP_MKNOD, CAP_AUDIT_WRITE, CAP_SETFCAP
```

Already broader than most workloads need. Drop all, add back explicitly.

```bash
docker run --cap-drop=ALL --cap-add=NET_BIND_SERVICE myimage
```

`--privileged`: ALL capabilities + seccomp disabled + AppArmor/SELinux disabled + full device access. Container escape near-guaranteed given time. **Never in production.**

---

## 3. Namespaces — Isolation Boundaries

Container = process + namespaces + cgroups. **No hypervisor. One shared kernel.**

| Namespace | Isolates                  | Default in Docker |
| --------- | ------------------------- | ----------------- |
| PID       | Process tree              | Yes               |
| Mount     | Filesystem view           | Yes               |
| Network   | Interfaces, ports         | Yes               |
| UTS       | Hostname                  | Yes               |
| IPC       | Shared memory, semaphores | Yes               |
| **User**  | **UID/GID mapping**       | **NO — opt-in**   |
| Cgroup    | Cgroup root view          | Yes               |
| Time      | Boot/monotonic clock      | Kernel 5.6+       |

### 3.1 The User Namespace Gap — Critical

Without `--userns-remap`, there is **no UID translation layer**. Container UID 0 **is** host UID 0 — same integer, same kernel identity. Namespaces isolate _view_, not _identity_, unless user namespace is explicitly enabled.

**Attack path without remap:**

```
Container: UID 0, CAP_SYS_ADMIN
  ↓ (bind mount misconfig / kernel escape CVE)
Host: same UID 0, same CAP_SYS_ADMIN — full host authority
```

`docker.sock` bind-mounted into a container = root-equivalent host control, no exploit required.

**With `--userns-remap` (real isolation):**

```
Container UID 0  →  Host UID 100000
Container UID 1  →  Host UID 100001
```

```bash
cat /proc/<pid>/uid_map     # <inside-UID> <outside-UID> <range>
docker info | grep -i userns
```

Container root becomes a genuinely unprivileged UID on the host. Escapes relying on "I have UID 0" fail.

**K8s equivalent:** `hostUsers: false` (K8s 1.25+, requires containerd + `UserNamespacesSupport` feature gate).

### 3.2 Why Containers ≠ VMs

|                       | VM                    | Container                             |
| --------------------- | --------------------- | ------------------------------------- |
| Isolation boundary    | Hypervisor / hardware | Kernel bookkeeping (software)         |
| Kernel                | Separate guest kernel | Shared host kernel                    |
| Kernel exploit impact | Contained to guest    | Potential cross-container/host escape |

A kernel zero-day is a cross-tenant escape vector by construction in containers. Patch kernels aggressively. Never treat container boundary as VM-equivalent for hostile multi-tenant workloads.

```bash
lsns                            # list all namespaces
ls -la /proc/<pid>/ns/           # namespaces a process belongs to
```

---

## 4. Seccomp — Syscall Filtering

Restricts _which syscalls_ a process may invoke, independent of UID/capabilities.

Docker's default profile blocks ~44 dangerous syscalls (`mount`, `reboot`, `ptrace` variants, kernel keyring ops) even if the matching capability is present.

```bash
docker run --security-opt seccomp=default.json myimage
```

```yaml
# K8s
securityContext:
  seccompProfile:
    type: RuntimeDefault
```

Verify it's actually active, don't trust the manifest:

```bash
kubectl exec <pod> -- cat /proc/1/status | grep Seccomp
# Seccomp: 2   <- 2 = filter mode active
```

---

## 5. MAC — SELinux / AppArmor

DAC = owner decides (discretionary). MAC = system policy, owner cannot override — confines even root.

```bash
getenforce              # SELinux: Enforcing/Permissive/Disabled
ls -Z file                # SELinux context
aa-status                 # AppArmor status
```

**SELinux**: label-based (`user:role:type:level`), fine-grained, RHEL/Fedora default.
**AppArmor**: path-based, simpler, Ubuntu/Debian default.

A process with `CAP_DAC_OVERRIDE` can bypass rwx checks — MAC policy can still block it regardless. Defense in depth, not redundant.

```bash
ausearch -m avc -ts recent     # SELinux denials
dmesg | grep -i apparmor         # AppArmor denials
```

**Yama LSM** (Ubuntu default): restricts `ptrace()` scope beyond raw capability checks.

```bash
cat /proc/sys/kernel/yama/ptrace_scope
```

---

## 6. Full Kernel Enforcement Pipeline

Every privileged operation passes through, in order:

```
1. Seccomp     — is this syscall permitted to execute at all?
2. LSM/MAC     — does policy (SELinux/AppArmor) allow this action?
3. Capability  — does EUID/process hold the required bit?
4. DAC         — does file rwx + EUID/GID satisfy standard check?
```

**All four must pass.** Fail any = `EPERM`/`EACCES`. No single layer substitutes for another.

---

## 7. Cgroups — Resource Limits (Separate Concern)

Controls _how much_, not _what_. Not access control.

```bash
cat /sys/fs/cgroup/memory.max
cat /sys/fs/cgroup/memory.pressure    # PSI — check before chasing phantom app bugs
```

```yaml
resources:
  limits:
    memory: "512Mi"
    cpu: "500m"
```

Misconfigured limits → OOM-kills that masquerade as application bugs. Check cgroup pressure before debugging app-layer.

---

## 8. Docker Runtime Hardening Checklist

```bash
docker run \
  --user 10001:10001 \
  --cap-drop=ALL \
  --cap-add=NET_BIND_SERVICE \
  --security-opt=no-new-privileges \
  --security-opt seccomp=default.json \
  --read-only \
  --tmpfs /tmp \
  --userns-remap=default \
  myimage
```

**Never:**

- `--privileged` — no exceptions, no "just for debugging."
- Bind-mount `docker.sock` without extreme justification.
- Skip `--cap-drop=ALL` and rely on Docker's default set.

**Diagnostics — `docker container top` UID gotcha:**
`docker container top <name>` resolves usernames via the **host's** `/etc/passwd`, not the container's. A UID that maps to `nginx` inside the container may display as `uuidd`, another name, or a raw number on the host. Never trust the displayed username for security reasoning — verify the numeric UID.

```bash
docker exec <container> id
docker inspect --format '{{.Config.User}}' <image>
```

---

## 9. Dockerfile-Level Security — Full Depth

### 9.1 Base Image Selection

```dockerfile
# WORST — mutable tag, full OS
FROM ubuntu:latest

# BETTER — pinned digest, not tag
FROM ubuntu:22.04@sha256:2b7412e6465c3c7fc5bb21d3e6f1917c167358449fecac8176c6e496e5c1f05

# BEST (most workloads) — no shell, no package manager
FROM gcr.io/distroless/nodejs20-debian12

# BEST (static binaries — Go/Rust) — nothing but the binary
FROM scratch
```

Tags are mutable pointers — upstream can rebuild the same tag with different contents. Digest is an immutable content hash.

```bash
docker inspect ubuntu:22.04 --format='{{index .RepoDigests 0}}'
```

Trade-off: distroless/scratch has no shell for `docker exec -it sh`. Accept it — use structured logging + a separate debug image variant, not a weakened prod image.

### 9.2 Multi-Stage Builds — Non-Negotiable

```dockerfile
FROM golang:1.22 AS builder
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -o /app -ldflags="-s -w" .

FROM gcr.io/distroless/static-debian12
COPY --from=builder /app /app
USER 10001
ENTRYPOINT ["/app"]
```

Final image: zero compiler, zero source, zero build deps. Compromise yields no shell, no interpreter, no pivot tools.

For Node/Python:

```dockerfile
FROM node:20 AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev
COPY . .

FROM gcr.io/distroless/nodejs20-debian12
WORKDIR /app
COPY --from=builder /app /app
USER 10001
CMD ["server.js"]
```

`npm ci`, never `npm install` — deterministic, lockfile-exact, fails on mismatch. Prevents supply-chain drift.

### 9.3 USER Directive

```dockerfile
RUN addgroup --gid 10001 appgroup && \
    adduser --uid 10001 --gid 10001 --disabled-password --gecos "" appuser
USER 10001:10001
```

Avoid reusing UID 1000 blindly — without user namespace remapping, host UID 1000 may be a real privileged host user. Prefer high UIDs (10000+) to reduce collision risk.

```bash
docker inspect --format '{{.Config.User}}' <image>
```

Empty or `0`/`root` output → reject in CI.

### 9.4 COPY vs ADD

```dockerfile
# NEVER — silent URL fetch + auto-extract, MITM/supply-chain risk
ADD https://example.com/file.tar.gz /app/

# ALWAYS — explicit, local, auditable
COPY file.tar.gz /app/
RUN tar -xzf /app/file.tar.gz -C /app/ && rm /app/file.tar.gz
```

### 9.5 Secrets — Never in Layers

```dockerfile
# CATASTROPHIC — permanently recoverable even if later layer deletes it
COPY .env /app/.env

# CORRECT — BuildKit secret mount, never persists to layer
RUN --mount=type=secret,id=npm_token \
    NPM_TOKEN=$(cat /run/secrets/npm_token) npm install
```

```bash
DOCKER_BUILDKIT=1 docker build --secret id=npm_token,src=./token.txt .
```

Layers are additive diffs — `rm` in a later layer does not erase the earlier layer's blob. Treat every `COPY`/`RUN` as permanent and public.

```bash
docker history --no-trunc <image> | grep -iE "token|password|key|secret"
```

### 9.6 Pin Every Dependency

```dockerfile
RUN apt-get update && apt-get install -y curl=7.88.1-10+deb12u5 \
    && rm -rf /var/lib/apt/lists/*
```

Cleanup must be in the **same** `RUN` instruction — a separate layer doesn't shrink the image; the earlier blob persists regardless.

### 9.7 HEALTHCHECK

```dockerfile
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:8080/health || exit 1
```

Catches failures before orchestrator-level probes fire. Tightens MTTR.

### 9.8 Read-Only Filesystem

```dockerfile
VOLUME ["/tmp", "/app/cache"]
```

```bash
docker run --read-only --tmpfs /tmp myimage
```

If the image filesystem can't be written at runtime, malware/webshell drops fail outright. Real containment, not hygiene.

### 9.9 .dockerignore

```
.git
.env
*.pem
*.key
node_modules
.npmrc
Dockerfile
docker-compose.yml
**/*.md
```

Missing this sends your entire build context (including `.git` history with old secrets) to the daemon — candidate for accidental `COPY . .` inclusion.

### 9.10 Full Hardened Template

```dockerfile
# syntax=docker/dockerfile:1.7
FROM golang:1.22@sha256:<pinned-digest> AS builder
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN --mount=type=cache,target=/root/.cache/go-build \
    CGO_ENABLED=0 GOOS=linux go build -o /app -ldflags="-s -w -extldflags=-static" .

FROM gcr.io/distroless/static-debian12@sha256:<pinned-digest>
COPY --from=builder --chown=10001:10001 /app /app
USER 10001:10001
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s CMD ["/app", "--healthcheck"]
ENTRYPOINT ["/app"]
```

---

## 10. Image Scanning — Verify, Don't Assume

Dockerfile discipline catches design flaws. Scanning catches known CVEs in dependencies/base image.

```bash
trivy image myimage:latest
trivy image --severity HIGH,CRITICAL --exit-code 1 myimage:latest   # CI hard gate
grype myimage:latest                                                  # SBOM alternative
```

Integrate as a CI gate that fails the build — not a report nobody reads.

---

## 11. Kubernetes — Cluster-Scale Enforcement

### 11.1 Full Hardened Pod Spec

```yaml
apiVersion: v1
kind: Pod
spec:
  hostUsers: false # user namespace remap, K8s 1.25+
  securityContext:
    runAsNonRoot: true
    runAsUser: 10001
    runAsGroup: 10001
    fsGroup: 10001
    seccompProfile:
      type: RuntimeDefault
  containers:
    - name: app
      securityContext:
        allowPrivilegeEscalation: false
        readOnlyRootFilesystem: true
        capabilities:
          drop: ["ALL"]
          add: ["NET_BIND_SERVICE"] # omit entirely if unneeded
      resources:
        limits:
          memory: "512Mi"
          cpu: "500m"
```

### 11.2 Field Responsibility — Don't Confuse These

| Field                             | What it actually does                                                                                                    |
| --------------------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| `runAsNonRoot: true`              | Policy gate — refuses scheduling if default UID is 0. Does **not** stop non-root process holding dangerous capabilities. |
| `allowPrivilegeEscalation: false` | Blocks setuid binaries and `no_new_privs` bypass at exec time.                                                           |
| `capabilities.drop: ["ALL"]`      | The field most manifests skip. Without it, runtime default capability set applies, not zero.                             |
| `hostUsers: false`                | The only field that changes whether root is **real** on the host, not just policy-disallowed.                            |
| `readOnlyRootFilesystem`          | Blocks persistence of dropped payloads at the filesystem layer.                                                          |

### 11.3 Cluster-Wide Enforcement — Don't Rely on Per-Manifest Discipline

- **Pod Security Admission** `restricted` profile — built-in K8s 1.25+, replaces deprecated PodSecurityPolicy.
- **OPA/Gatekeeper or Kyverno** — reject `--privileged`, reject missing `drop: ALL`, allowlist `capabilities.add`.

### 11.4 Verification — Run These, Don't Trust the YAML

```bash
kubectl exec <pod> -- getpcaps 1
kubectl exec <pod> -- cat /proc/1/status | grep Seccomp
kubectl exec <pod> -- id
kubectl get pod <pod> -o jsonpath='{.spec.hostUsers}'

# Cluster-wide capability audit
for img in $(kubectl get pods -A -o jsonpath='{.items[*].spec.containers[*].image}' | tr ' ' '\n' | sort -u); do
  echo "=== $img ==="
  docker run --rm "$img" sh -c 'getcap -r / 2>/dev/null'
done
```

---

## 12. Threat Model Summary — Memorize This

| Layer                  | Stops                                                 | Doesn't stop                                      |
| ---------------------- | ----------------------------------------------------- | ------------------------------------------------- |
| DAC (UID/GID/rwx)      | Unauthorized access by unprivileged UID               | Root, or any process with `CAP_DAC_OVERRIDE`      |
| Capabilities           | Root's syscall power scoped down                      | Anything within the granted capability set        |
| Namespaces (no userns) | Process seeing other containers/host resources        | UID 0 acting with real host authority on escape   |
| User namespace remap   | Container root having real host authority             | Nothing within the container's own remapped scope |
| Seccomp                | Specific dangerous syscalls                           | Anything not in the blocklist                     |
| MAC (SELinux/AppArmor) | Policy-violating actions regardless of UID/capability | Misconfigured or absent policy                    |

**No single layer is sufficient. Stack all six or the gap is the attack surface.**

---

## 13. Security Baseline

The minimum bar for a production container workload:

| Control | Implementation |
| ------- | -------------- |
| Non-root UID | `USER 10001:10001` in Dockerfile + `runAsNonRoot: true` in pod spec |
| Zero capabilities | `--cap-drop=ALL`, add back only what the process actually needs |
| Seccomp | `RuntimeDefault` profile — blocks ~44 dangerous syscalls by default |
| Read-only root filesystem | `--read-only` + `--tmpfs /tmp` for scratch space |
| Resource limits | `--memory` + `--cpus` — prevents noisy-neighbour and OOM cascades |
| Pinned base image | Digest, not tag — immutable, scannable, deterministic |
| CI image scan | `trivy image --severity HIGH,CRITICAL --exit-code 1` as a hard gate |

Anything short of this is incomplete, not a style choice. Each missing control is a known exploit path, not a theoretical risk.
