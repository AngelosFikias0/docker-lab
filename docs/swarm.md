# Docker Swarm

## Classic Swarm vs Swarm Mode

| | Classic Swarm | Swarm Mode |
|---|---|---|
| Available since | Docker 1.6 (external tool) | Docker 1.12 (built-in) |
| Cluster state | External KV store (etcd/Consul/ZooKeeper) | Raft consensus built into dockerd |
| Setup | Separate swarm container per node | `docker swarm init` |
| Status | Deprecated | Current |

Classic Swarm is dead. Swarm Mode is what `docker swarm` refers to today.

---

## Raft and manager quorum

Swarm managers use the Raft consensus algorithm to maintain cluster state. Raft requires a quorum — a majority of managers must agree before any state change commits.

```
1 manager  → tolerates 0 failures (no HA)
3 managers → tolerates 1 failure  (quorum = 2)
5 managers → tolerates 2 failures (quorum = 3)
7 managers → tolerates 3 failures (quorum = 4)
```

Always use an odd number of managers. Even numbers buy no additional fault tolerance and add Raft overhead. Workers do not participate in Raft — add as many as needed.

---

## Node roles

```
Manager node(s)              Worker node(s)
─────────────────            ─────────────────
Raft state machine           Executes tasks (containers)
Schedules tasks              Reports health back to manager
Serves API (docker -H)       Cannot run management commands
Can also run tasks           
```

A single-node swarm (manager only) is valid and fully functional — the manager runs tasks too.

---

## Init and join

```bash
# On the manager node
docker swarm init --advertise-addr <manager-ip>

# Output includes join tokens:
# To add a worker:
docker swarm join --token SWMTKN-1-... <manager-ip>:2377

# To add another manager:
docker swarm join-token manager

# Retrieve worker token later
docker swarm join-token --quiet worker

# List nodes
docker node ls

# Inspect a node
docker node inspect --pretty <node-name>
```

---

## Overlay network

Swarm services on multiple hosts need a network that spans machines. Overlay uses VXLAN encapsulation (same as Docker standalone overlay, but with built-in key distribution via Raft instead of an external KV store).

```bash
docker network create --driver=overlay default-net

docker network ls
# TYPE overlay = spans all swarm nodes
```

Containers on the same overlay network resolve each other by service name via the built-in DNS.

---

## Services

A **service** is the Swarm equivalent of `docker run`, but declarative and replicated.

```bash
docker service create \
  --detach=false \
  --name myapp \
  --replicas 2 \
  --publish published=80,target=8080 \
  --network default-net \
  nginx:alpine

docker service ls            # list services + replica count
docker service ps myapp      # list tasks (containers) + which node they run on
docker service logs myapp    # aggregated logs from all replicas
docker service inspect myapp # full service spec
```

### Routing mesh

When `--publish` is set, Swarm creates a **routing mesh**: every node in the cluster listens on the published port, regardless of which node the container is running on. Traffic arriving on any node is forwarded to a healthy task.

```
curl http://node-3:80        # works even if no replica runs on node-3
```

This replaces the need for a separate external load balancer for simple cases. Internally it uses `iptables DNAT` + an IPVS load balancer in the `ingress` overlay network.

---

## Scaling and updates

```bash
# Scale
docker service scale --detach=false myapp=4

# Rolling update (one container at a time by default)
docker service update \
  --image nginx:1.27 \
  --update-parallelism 1 \
  --update-delay 10s \
  myapp

# Rollback to previous spec
docker service rollback myapp
```

`--update-parallelism` controls how many tasks update simultaneously. `--update-delay` is the wait between batches. These prevent a bad deploy from taking down all replicas at once.

---

## docker stack

`docker stack` deploys a Compose file to a Swarm cluster. It is the bridge between Compose syntax and Swarm scheduling.

```bash
docker stack deploy --compose-file docker-compose-stack.yml mystack

docker stack ls              # list stacks
docker stack services mystack # services in the stack
docker stack ps mystack      # tasks across all services

docker stack rm mystack      # tear down (leaves volumes intact)
```

Not all Compose keys are supported in stack mode. Keys ignored by Swarm: `build`, `depends_on`, `links`. Keys added by Swarm: `deploy` block.

```yaml
services:
  web:
    image: nginx:alpine
    deploy:
      replicas: 3
      update_config:
        parallelism: 1
        delay: 10s
      restart_policy:
        condition: on-failure
      placement:
        constraints:
          - node.role == worker
    ports:
      - "80:80"
    networks:
      - default-net

networks:
  default-net:
    driver: overlay
```

---

## Kubernetes mapping

| Swarm concept | Kubernetes equivalent |
|---|---|
| Manager node | Control plane node |
| Worker node | Worker node |
| Service (`--replicas`) | Deployment + ReplicaSet |
| Routing mesh (ingress) | Service (NodePort / LoadBalancer) |
| Overlay network | CNI plugin (Calico, Cilium) |
| `docker stack deploy` | `kubectl apply -f` |
| `docker service scale` | `kubectl scale deployment` |
| `docker service rollback` | `kubectl rollout undo` |
| Raft (manager quorum) | etcd (control plane quorum) |
| `docker service update` | `kubectl set image` / rolling update |
