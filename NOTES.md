# Docker Lab Notes

---

## Container Fundamentals

Linux containers are processes, not VMs. They share the host kernel.

**Isolation primitives:**

| Primitive    | What it controls                                       |
| ------------ | ------------------------------------------------------ |
| Namespaces   | What a process can see (PID, NET, MNT, UTS, IPC, USER) |
| Cgroups      | What a process can use (CPU, memory, I/O)              |
| OverlayFS    | Union filesystem at `/var/lib/docker/overlay2/`        |

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

## Container History

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

## Container Lifecycle

```bash
docker container create <image>   # allocate filesystem + config from image (no process)
docker container start <name>     # start the process
docker container run <image>      # create + start in one step

docker stop <name>                # SIGTERM -> wait grace period -> SIGKILL
docker rm <name>                  # remove stopped container
```

---

## Container Identity Files

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

| Flag                         | Effect                                               |
| ---------------------------- | ---------------------------------------------------- |
| `--hostname foo.example.com` | Sets `/etc/hostname`, enables FQDN                   |
| `--dns 8.8.8.8`              | Overrides nameserver in `/etc/resolv.conf`           |
| `--dns-search example.com`   | Sets search domain                                   |
| `--dns-search .`             | Clears search domain entirely                        |

In Kubernetes, this is abstracted: kubelet + CoreDNS manage pod DNS. The equivalent of `--dns` and `--dns-search` is `dnsPolicy` / `dnsConfig` on the PodSpec. Same mechanics underneath the CRI.

---

## crictl

`crictl` is a CLI for runtimes that implement the Kubernetes CRI (Container Runtime Interface). It targets `containerd` and `CRI-O` at the node level. Not a Docker tool.

---

## Docker Networking Internals

### Core Primitive: Network Namespaces

Each container = isolated Linux **network namespace** (`netns`).

- Separate routing table, iptables rules, interfaces, ARP table.
- Zero visibility into host's or other containers' network stack unless explicitly connected.

### Bridge Networks

**1. Docker creates a Linux bridge device** (virtual switch) per user-defined network.

```bash
ip link show | grep br-
# br-<network_id>
```

**2. Each container gets a veth pair** (virtual ethernet cable, two ends).

- One end inside the container's netns -> appears as `eth0`.
- Other end attached to the bridge on the host.

```bash
ip link show
# veth1234@if5 (host side, attached to br-xxxx)
```

**3. Bridge acts as an L2 switch.** All veth host-ends on the same bridge forward Ethernet frames to each other. Same-network containers reach each other by IP.

**4. IP assignment:** Docker's internal IPAM assigns each container an IP from the bridge's subnet (e.g. `172.18.0.0/16`) and sets the container's default route to the bridge gateway IP.

### Embedded DNS (127.0.0.11)

- Docker injects `/etc/resolv.conf` pointing to `127.0.0.11` inside the container netns.
- Not a real per-container listener. Docker daemon intercepts DNS queries via iptables redirect to its internal resolver process.
- Resolver holds a live map: **container name -> current IP**, updated on start/stop.
- **Default bridge does not wire this up.** No name registration on `docker0`. Always use user-defined networks.

### External Connectivity: NAT via iptables

Containers reach the internet through **SNAT/MASQUERADE** in the `POSTROUTING` chain.

```bash
iptables -t nat -L POSTROUTING
# MASQUERADE all -- 172.18.0.0/16 anywhere
```

- Requires `net.ipv4.ip_forward=1` on the host.
- Inbound (`docker run -p 8080:80`) creates a **DNAT** rule in `PREROUTING`/`DOCKER`, forwarding `host:8080 -> container:80`.

### Cross-Network Isolation

- Separate bridges = separate L2 broadcast domains. No frame crosses `br-net1 <-> br-net2` unless routed.
- Docker inserts explicit DROP rules in `DOCKER-ISOLATION-STAGE-1/2` chains.

```bash
iptables -L DOCKER-ISOLATION-STAGE-2
# DROP rules between bridge interfaces
```

- `docker network connect othernet container` does **not** bridge the two networks. It adds a second veth pair into the container's netns (`eth1`) with an IP on the second bridge. The container straddles both L2 domains individually. The networks themselves stay isolated.

### Multi-Host: Overlay Networks

Single-host bridges can't span machines. Overlay uses **VXLAN** encapsulation:

- Each container frame is wrapped in a UDP packet (VXLAN header + VNI id) and sent host-to-host.
- Each host runs a VXLAN Tunnel Endpoint (VTEP).
- A distributed key-value store or gossip protocol syncs the IP -> MAC -> host mapping.

### Kubernetes Mapping

| Docker concept                     | Kubernetes equivalent                                             |
| ---------------------------------- | ----------------------------------------------------------------- |
| Container netns                    | Pod netns (same primitive)                                        |
| dockerd wiring veth/bridge         | CNI plugin (Calico, Cilium, etc.)                                 |
| iptables NAT/isolation             | eBPF (Cilium) - same job, no linear chain traversal               |
| Embedded DNS resolver (127.0.0.11) | CoreDNS - same idea, cluster-scoped                               |
| `DOCKER-ISOLATION` chains          | NetworkPolicy - same enforcement point, label-selector based      |

### Inspect Live

```bash
docker network create testnet
docker run -d --name c1 --network testnet alpine sleep 3600

brctl show                                                            # bridge + attached veths
nsenter -t $(docker inspect -f '{{.State.Pid}}' c1) -n ip addr       # inspect container netns directly
```

`ip netns list` won't show container netns because Docker doesn't register them under `/var/run/netns`. Use `nsenter` against the container's PID instead.
