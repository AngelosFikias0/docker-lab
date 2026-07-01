# bridge-network

Two containers communicating: first on the default bridge (IP only), then on a custom bridge (by name).

---

## Run the exercises

```bash
bash exercises.sh
```

Run each block individually. Each section is self-contained.

---

## Concepts

### Default bridge

Containers with no `--network` flag join `docker0`. They can reach each other by IP. There is no DNS. IP lookup requires `docker inspect`. This is why the default bridge is not suitable beyond quick tests.

### Custom bridge

`docker network create` creates an isolated bridge. Containers joined to it get:

- Their own IP from the bridge subnet
- Docker's embedded DNS at `127.0.0.11`
- Name resolution for every other container on the same network

A container not in the network cannot reach containers inside it.

### Connecting a container to multiple networks

`docker network connect` attaches a running container to an additional network. It gets a new virtual interface (`eth1`, `eth2`, etc.) for each.

---

## Key commands

```bash
docker network create <name>
docker network ls
docker network inspect <name>
docker network rm <name>
docker network connect <net> <container>
docker network disconnect <net> <container>

docker exec <container> ip addr
docker exec <container> ip route
docker exec <container> ping -c 3 <target>
docker inspect <container> --format '{{ .NetworkSettings.Networks }}'
```
