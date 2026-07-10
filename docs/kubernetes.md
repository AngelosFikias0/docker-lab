# Kubernetes

## What Kubernetes adds over Docker/Swarm

Docker runs containers. Swarm schedules containers across nodes. Kubernetes schedules containers across nodes with production-grade primitives: declarative desired state, self-healing, fine-grained networking policies, pluggable storage, RBAC, and a rich API that third-party tooling builds on.

---

## Local cluster tools

| Tool | How nodes run | Use case |
|---|---|---|
| minikube | VMs (via hypervisor) or containers | Single-node, closest to real VM-based clusters |
| kind (Kubernetes in Docker) | Docker containers as nodes | Multi-node on a laptop, CI pipelines |
| k3s | Lightweight binary, native OS | Edge, Raspberry Pi, fast local dev |

kind is the most common choice for CI and multi-node local testing. k3s is common for edge and resource-constrained environments.

```bash
# kind
kind create cluster --name lab --config kind-config.yml
kubectl cluster-info --context kind-lab

# minikube
minikube start --driver=docker --nodes=2
minikube status
```

---

## Core objects

### Pod

The smallest schedulable unit. One or more containers sharing the same:
- Network namespace (same IP, same port space)
- IPC namespace
- cgroup (resource limits applied at the pod level)
- Volumes (mounted into individual containers)

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: myapp
spec:
  containers:
    - name: app
      image: nginx:alpine
      ports:
        - containerPort: 80
      resources:
        requests:
          memory: "64Mi"
          cpu: "100m"
        limits:
          memory: "128Mi"
          cpu: "500m"
```

Pods are ephemeral. They are not restarted by themselves — that is the job of a Deployment or StatefulSet.

### Deployment

Manages a ReplicaSet, which manages Pods. The Deployment controller continuously reconciles actual state with desired state.

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
spec:
  replicas: 3
  selector:
    matchLabels:
      app: myapp
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
  template:
    metadata:
      labels:
        app: myapp
    spec:
      containers:
        - name: app
          image: nginx:alpine
          ports:
            - containerPort: 80
          readinessProbe:
            httpGet:
              path: /
              port: 80
            initialDelaySeconds: 5
            periodSeconds: 5
```

```bash
kubectl apply -f deployment.yml
kubectl rollout status deployment/myapp
kubectl rollout history deployment/myapp
kubectl rollout undo deployment/myapp         # rollback
kubectl scale deployment myapp --replicas=5
kubectl set image deployment/myapp app=nginx:1.27  # rolling update
```

### Service

Stable network endpoint in front of a dynamic set of pods. Pods come and go; the Service IP/DNS stays constant.

```yaml
apiVersion: v1
kind: Service
metadata:
  name: myapp
spec:
  selector:
    app: myapp          # matches Deployment pod labels
  ports:
    - port: 80
      targetPort: 80
  type: ClusterIP       # ClusterIP | NodePort | LoadBalancer
```

| Service type | Accessible from | Use case |
|---|---|---|
| ClusterIP | Inside cluster only | Default; internal service-to-service |
| NodePort | Any node IP + port (30000-32767) | Local dev, simple external access |
| LoadBalancer | Cloud LB (external IP) | Production ingress (GCP/AWS/Azure) |

```bash
kubectl get svc myapp
kubectl port-forward svc/myapp 8080:80   # tunnel to local machine
```

### PersistentVolume and PersistentVolumeClaim

PV = a piece of storage provisioned in the cluster (disk, NFS, cloud volume).
PVC = a request for storage by a pod.

```yaml
# PVC — pod asks for storage
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: data-pvc
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
  storageClassName: standard   # maps to a StorageClass (dynamic provisioning)
```

```yaml
# Mount PVC in a pod
volumes:
  - name: data
    persistentVolumeClaim:
      claimName: data-pvc
containers:
  - name: app
    volumeMounts:
      - mountPath: /data
        name: data
```

```bash
kubectl get pvc
kubectl get pv
kubectl describe pvc data-pvc   # shows bound PV + access mode
```

---

## kubectl reference

```bash
# Context
kubectl config get-contexts
kubectl config use-context kind-lab

# Apply / delete
kubectl apply -f manifest.yml
kubectl delete -f manifest.yml

# Inspect
kubectl get pods -o wide          # includes node assignment
kubectl get all -n default        # pods, services, deployments, replicasets
kubectl describe pod <name>       # events, conditions, container state
kubectl logs <pod> -f             # stream logs
kubectl logs <pod> -c <container> # multi-container pod

# Exec
kubectl exec -it <pod> -- sh

# Rollouts
kubectl rollout status deployment/<name>
kubectl rollout history deployment/<name>
kubectl rollout undo deployment/<name>

# Port-forward
kubectl port-forward pod/<name> 8080:80
kubectl port-forward svc/<name> 8080:80
```

---

## Docker/Swarm to Kubernetes mapping

| Docker/Swarm | Kubernetes |
|---|---|
| `docker run` | Pod |
| `docker service create` | Deployment |
| Named volume | PersistentVolumeClaim |
| `docker network create --overlay` | CNI plugin (Calico, Cilium, Flannel) |
| Embedded DNS (127.0.0.11) | CoreDNS |
| `docker service update --image` | `kubectl set image` / rolling update |
| `docker service rollback` | `kubectl rollout undo` |
| `docker stack deploy` | `kubectl apply -f` |
| `docker service scale` | `kubectl scale` |
| `docker service ls` | `kubectl get deployments` |
| Swarm routing mesh | Service (NodePort/LoadBalancer) + kube-proxy |
| Manager quorum (Raft) | etcd cluster (control plane HA) |
| `--health-cmd` | `livenessProbe` / `readinessProbe` |
| `--cap-drop=ALL` | `securityContext.capabilities.drop` |
| `--read-only` | `securityContext.readOnlyRootFilesystem` |
| `USER 10001` | `securityContext.runAsUser: 10001` |
