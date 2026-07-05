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
