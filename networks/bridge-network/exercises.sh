#!/usr/bin/env bash
# bridge-network/exercises.sh
# Run blocks individually. Each section is self-contained.
# Not meant to be executed top-to-bottom as a pipeline.

# ---------------------------------------------------------------------------
# 1. DEFAULT BRIDGE - start two containers with no network flag
# Both land on docker0 automatically.
# ---------------------------------------------------------------------------
docker run -d --name box-a alpine sleep infinity
docker run -d --name box-b alpine sleep infinity

docker ps

# ---------------------------------------------------------------------------
# 2. DEFAULT BRIDGE - communicate by IP
# Containers on docker0 can reach each other, but only by IP.
# .NetworkSettings.IPAddress is only populated for the default bridge.
# ---------------------------------------------------------------------------
docker inspect box-a --format '{{ .NetworkSettings.Networks.bridge.IPAddress }}'

# Copy the IP from above and ping it from box-b
docker exec box-b ping -c 3 172.17.0.2    # replace with actual IP if different

# ---------------------------------------------------------------------------
# 3. DEFAULT BRIDGE - name resolution fails
# Docker does not run a DNS server on the default bridge.
# ---------------------------------------------------------------------------
docker exec box-b ping -c 2 box-a
# Expected: ping: bad address 'box-a'

docker stop box-a box-b && docker rm box-a box-b

# ---------------------------------------------------------------------------
# 4. CUSTOM BRIDGE - create an isolated network
# ---------------------------------------------------------------------------
docker network create lab-net

docker network ls
docker network inspect lab-net \
  --format 'Subnet: {{range .IPAM.Config}}{{.Subnet}}{{end}}'

# ---------------------------------------------------------------------------
# 5. CUSTOM BRIDGE - run containers on the new network
# ---------------------------------------------------------------------------
docker run -d --name svc-a --network lab-net alpine sleep infinity
docker run -d --name svc-b --network lab-net alpine sleep infinity

docker network inspect lab-net \
  --format '{{range $k, $v := .Containers}}{{$v.Name}} {{$v.IPv4Address}}{{"\n"}}{{end}}'

# ---------------------------------------------------------------------------
# 6. CUSTOM BRIDGE - ping by name works
# Docker's embedded DNS at 127.0.0.11 resolves container names automatically.
# ---------------------------------------------------------------------------
docker exec svc-b ping -c 3 svc-a
docker exec svc-a ping -c 3 svc-b

docker exec svc-b cat /etc/resolv.conf

# ---------------------------------------------------------------------------
# 7. NETWORK ISOLATION - containers outside lab-net cannot reach inside
# ---------------------------------------------------------------------------
docker run --rm alpine ping -c 2 svc-a
# Expected: ping: bad address 'svc-a'

# Network name contains a dash - use index to avoid template parse error
SVC_A_IP=$(docker inspect svc-a \
  --format '{{ (index .NetworkSettings.Networks "lab-net").IPAddress }}')
docker run --rm alpine ping -c 2 "$SVC_A_IP"
# Expected: no response or unreachable

# ---------------------------------------------------------------------------
# 8. CONNECT AN EXISTING CONTAINER TO AN ADDITIONAL NETWORK
# A container can belong to multiple networks at once.
# Docker adds a new virtual interface for each network.
# ---------------------------------------------------------------------------
docker run -d --name bridge-side alpine sleep infinity   # on default bridge

docker network connect lab-net bridge-side              # now also on lab-net

docker exec bridge-side ping -c 3 svc-a

# Both interfaces visible inside the container (eth0 = bridge, eth1 = lab-net)
docker exec bridge-side ip addr

docker network disconnect lab-net bridge-side
docker stop bridge-side && docker rm bridge-side

# ---------------------------------------------------------------------------
# 9. INSPECT
# ---------------------------------------------------------------------------
docker network inspect lab-net \
  --format '{{range $k, $v := .Containers}}{{$v.Name}} {{$v.IPv4Address}}{{"\n"}}{{end}}'

docker inspect svc-a \
  --format '{{range $net, $cfg := .NetworkSettings.Networks}}{{$net}}: {{$cfg.IPAddress}}{{"\n"}}{{end}}'

# ---------------------------------------------------------------------------
# 10. CLEANUP
# ---------------------------------------------------------------------------
docker stop svc-a svc-b
docker rm svc-a svc-b
docker network rm lab-net
