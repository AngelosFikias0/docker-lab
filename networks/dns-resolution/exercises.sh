#!/usr/bin/env bash
# dns-resolution/exercises.sh
# Run blocks individually. Each section is self-contained.
# Not meant to be executed top-to-bottom as a pipeline.

# ---------------------------------------------------------------------------
# 1. SETUP - create a custom network
# DNS is only available on custom networks, not the default bridge.
# ---------------------------------------------------------------------------
docker network create dns-lab

# ---------------------------------------------------------------------------
# 2. THE DNS SERVER - see where queries go inside a container
# Docker injects 127.0.0.11 as the nameserver in /etc/resolv.conf.
# ---------------------------------------------------------------------------
docker run -d --name alpha --network dns-lab alpine sleep infinity

docker exec alpha cat /etc/resolv.conf
# nameserver 127.0.0.11

# Compare with a container on the default bridge (no 127.0.0.11)
docker run --rm alpine cat /etc/resolv.conf

# ---------------------------------------------------------------------------
# 3. NAME RESOLUTION - containers find each other by name
# Pass 127.0.0.11 explicitly to avoid search domain noise in nslookup output.
# ---------------------------------------------------------------------------
docker run -d --name beta --network dns-lab alpine sleep infinity

docker exec beta nslookup alpha 127.0.0.11
# Server:    127.0.0.11
# Name:      alpha
# Address:   172.x.x.x

docker exec alpha nslookup beta 127.0.0.11

docker exec beta ping -c 3 alpha

# ---------------------------------------------------------------------------
# 4. NETWORK ALIASES - one name, multiple containers
# Multiple containers sharing an alias all appear in DNS responses.
# ---------------------------------------------------------------------------
docker run -d --name web-1 --network dns-lab --network-alias web nginx:alpine
docker run -d --name web-2 --network dns-lab --network-alias web nginx:alpine

# nslookup for "web" returns both IPs
docker exec alpha nslookup web 127.0.0.11
# Name:   web
# Address: 172.x.x.2
# Address: 172.x.x.3

# Each request hits one backend (round-robin per DNS query)
for i in 1 2 3 4; do
  docker exec alpha wget -qO - http://web > /dev/null && echo "request $i: ok"
done

# ---------------------------------------------------------------------------
# 5. DNS ISOLATION - containers on different networks cannot resolve each other
# ---------------------------------------------------------------------------
# Container on default bridge: DNS is the host resolver, not Docker's 127.0.0.11
docker run --rm alpine timeout 3 nslookup alpha 2>&1 || true
# Expected: can't resolve 'alpha' - server has no entry

docker network create other-net
docker run -d --name outsider --network other-net alpine sleep infinity

# outsider cannot see dns-lab containers
docker exec outsider nslookup alpha 127.0.0.11 2>&1 || true
# Expected: NXDOMAIN or no address

# Connect outsider to dns-lab - now it can resolve both networks
docker network connect dns-lab outsider
docker exec outsider nslookup alpha 127.0.0.11
docker exec outsider nslookup beta 127.0.0.11

docker network disconnect dns-lab outsider

# ---------------------------------------------------------------------------
# 6. ASSIGN AN ALIAS WHEN CONNECTING TO AN EXISTING NETWORK
# Start db-primary on the default bridge first, then connect to dns-lab
# with an alias. This is the pattern for giving a container a role name.
# ---------------------------------------------------------------------------
docker run -d --name db-primary alpine sleep infinity   # default bridge first

docker network connect --alias db dns-lab db-primary   # join dns-lab as "db"

docker exec alpha nslookup db 127.0.0.11          # resolves to db-primary's IP
docker exec alpha nslookup db-primary 127.0.0.11  # also works by container name

# ---------------------------------------------------------------------------
# 7. CLEANUP
# ---------------------------------------------------------------------------
docker stop alpha beta web-1 web-2 outsider db-primary
docker rm alpha beta web-1 web-2 outsider db-primary
docker network rm dns-lab other-net
