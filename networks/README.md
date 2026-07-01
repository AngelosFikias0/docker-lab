# Container Networking

A reference for how Docker networking works at the kernel level, what each driver does, and when to use each.

---

## The Networking Model

When Docker starts, it builds a small virtual network on your host using three kernel primitives.

### docker0 bridge

`docker0` is a virtual L2 switch that lives entirely in RAM. Docker creates it on daemon start. All containers that join the default network connect to this bridge, which gives them L2 adjacency: they can reach each other and the host.

```
Host
+-- docker0 (172.17.0.1) ---+
    |        |        |
  veth1a   veth2a   veth3a    <- host-side ends, attached to docker0
    |        |        |
  [ctr1]  [ctr2]  [ctr3]      <- containers see their end as eth0
```

Inspect it on the host:

```bash
ip link show docker0
ip addr show docker0         # shows 172.17.0.1/16 by default
```

### veth pairs

Every time a container starts, the kernel creates a **veth pair**: two virtual interfaces linked so that packets into one come out the other. One end goes into the host network namespace and attaches to docker0. The other end goes into the container's network namespace and is renamed `eth0`.

```bash
ip link show type veth               # host side, one per running container

docker exec <container> ip link show eth0
docker exec <container> ip addr show eth0
```

### eth0 inside the container

The container end of the veth pair. Docker assigns it an IP from the bridge subnet (default `172.17.0.0/16`) and sets docker0 as the default gateway.

```bash
docker exec <container> ip addr       # eth0 IP and subnet
docker exec <container> ip route      # default route via docker0
docker exec <container> cat /etc/hosts
```

### NAT and outbound traffic

docker0 is the gateway, but containers sit on a private RFC 1918 subnet. Outbound traffic goes through an iptables `MASQUERADE` rule that replaces the container source IP with the host IP before the packet leaves. Return traffic gets rewritten back. Containers get full outbound internet access with no extra config.

```bash
sudo iptables -t nat -L POSTROUTING -n    # see the masquerade rule
```

Inbound traffic requires publishing a port. `-p 8080:80` creates a DNAT rule: packets arriving at host port 8080 are rewritten to hit the container on port 80.

```bash
sudo iptables -t nat -L DOCKER -n         # see port-publish DNAT rules
```

---

## Network Drivers

| Driver    | Isolation | Use case                                              |
| --------- | --------- | ----------------------------------------------------- |
| `bridge`  | Yes       | Default. Single-host container-to-container comms.    |
| `host`    | No        | Container shares the host network namespace. No NAT.  |
| `none`    | Full      | No network at all. Loopback only.                     |
| `overlay` | Yes       | Multi-host (Docker Swarm). Not covered here.          |
| `macvlan` | Yes       | Assigns a real MAC to the container. Not covered here.|

### bridge

Creates or joins a Linux bridge. Containers get their own IP and communicate via the bridge. Two variants: the default bridge (`docker0`) and user-defined bridges created with `docker network create`.

### host

The container shares the host's network namespace directly. No eth0, no veth pair, no docker0. The container binds to the host's interfaces directly. Fastest option, no port mapping needed, but no network isolation.

```bash
docker run --rm --network host nginx
# nginx now binds directly to host port 80
```

### none

No networking except loopback. Container cannot send or receive packets. Use for batch jobs that must have zero network access.

```bash
docker run --rm --network none alpine ping 8.8.8.8
# PING 8.8.8.8: Network unreachable
```

---

## Default Bridge vs Custom Bridge

The most important distinction in Docker networking.

|                       | Default bridge | Custom bridge            |
| --------------------- | -------------- | ------------------------ |
| Created by            | Docker daemon  | `docker network create`  |
| DNS name resolution   | No, IP only    | Yes, by container name   |
| Isolation             | All containers share it | Only containers you add |
| Network aliases       | No             | Yes                      |
| Production use        | No             | Yes                      |

On the default bridge, containers can only reach each other by IP. Docker does not run a DNS server on it. On a custom bridge, Docker embeds a DNS resolver at `127.0.0.11` inside every member container. Containers resolve each other by name automatically.

---

## DNS in Docker

Docker's embedded DNS server runs at `127.0.0.11` inside every container on a custom network.

```bash
docker exec <container> cat /etc/resolv.conf
# nameserver 127.0.0.11
# options ndots:0
```

Queries to `127.0.0.11` are handled by the Docker daemon, which knows the names and IPs of every container on the network. A container named `db` is reachable as `db` from any other container on the same custom network.

**Network aliases** let you assign additional names to a container, or give multiple containers the same name. Docker returns all matching IPs when the alias is queried, giving basic round-robin load distribution.

```bash
docker run -d --network mynet --network-alias web nginx
docker run -d --network mynet --network-alias web nginx
# Both respond to "web". DNS returns both IPs.
```

---

## Port Publishing

```
-p HOST_PORT:CONTAINER_PORT
```

Creates an iptables DNAT rule. Traffic arriving at `HOST_PORT` on any host interface is rewritten to reach `CONTAINER_PORT` inside the container.

`EXPOSE` in a Dockerfile does not publish anything. It is metadata only. `docker run -P` (capital P) reads `EXPOSE` declarations and maps them to random host ports.

```bash
docker run -d -p 8080:80 nginx                  # specific mapping
docker run -d -p 127.0.0.1:8080:80 nginx        # loopback only
docker run -d -P nginx                          # random ports for all EXPOSE'd
docker port <container>                         # see active port mappings
```

---

## Inspection Commands

```bash
docker network ls                               # list all networks
docker network inspect <name>                   # full JSON: subnets, containers, options
docker network create <name>                    # create a custom bridge
docker network rm <name>                        # remove (must have no containers)
docker network connect <net> <container>        # attach running container to network
docker network disconnect <net> <container>

docker inspect <container> --format '{{ .NetworkSettings.Networks }}'
docker inspect <container> | grep IPAddress
docker port <container>                         # port mappings
```

---

## Labs

```
networks/
+-- bridge-network/    # Default vs custom bridge, container-to-container comms
+-- dns-resolution/    # Docker's embedded DNS, aliases, network isolation
```
