# dns-resolution

Docker's embedded DNS server. Container name resolution, network aliases, and DNS isolation between networks.

---

## Run the exercises

```bash
bash exercises.sh
```

Run each block individually.

---

## Concepts

### 127.0.0.11

Docker's embedded DNS resolver. Present in `/etc/resolv.conf` of every container on a custom network. The Docker daemon intercepts queries on this address and answers from its in-memory record of running containers on the network. Containers come and go; DNS answers stay accurate without manual update.

### Container name vs network alias

A **container name** (`--name`) is globally unique and automatically registered as a DNS name on any custom network the container joins.

A **network alias** (`--network-alias`) is a name scoped to a specific network. Multiple containers can share the same alias. DNS returns all their IPs, giving basic round-robin load distribution with no extra tooling.

### DNS isolation

A container can only resolve names that exist on networks it belongs to. Containers on different networks are invisible to each other's DNS.

---

## Key commands

```bash
docker exec <container> cat /etc/resolv.conf     # see the DNS server
docker exec <container> nslookup <name>          # query Docker DNS
docker exec <container> nslookup <alias>         # shows all IPs for an alias

docker run -d --network <net> --network-alias <alias> <image>
docker network connect --alias <alias> <net> <container>
```
