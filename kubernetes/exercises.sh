#!/usr/bin/env bash
set -euo pipefail

# Kubernetes exercises using kind (Kubernetes in Docker).
# Prerequisites: kind, kubectl
# Install kind:   go install sigs.k8s.io/kind@latest  OR  brew install kind
# Install kubectl: https://kubernetes.io/docs/tasks/tools/

CLUSTER="lab"

# ─── Block 1: Create a kind cluster ──────────────────────────────────────────
echo "=== Block 1: Create kind cluster ==="
cat <<EOF | kind create cluster --name "$CLUSTER" --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
  - role: worker
  - role: worker
EOF

kubectl cluster-info --context "kind-${CLUSTER}"
kubectl get nodes

# ─── Block 2: Deploy a pod directly ──────────────────────────────────────────
echo ""
echo "=== Block 2: Apply pod manifest ==="
kubectl apply -f manifests/pod.yml
kubectl wait --for=condition=Ready pod/lab-pod --timeout=60s
kubectl get pod lab-pod -o wide
kubectl describe pod lab-pod | grep -A5 "Conditions:"

# ─── Block 3: Exec into the pod ──────────────────────────────────────────────
echo ""
echo "=== Block 3: Exec and inspect ==="
kubectl exec lab-pod -- wget -qO- http://localhost/ | head -5
kubectl exec lab-pod -- cat /proc/1/status | grep -E "^(Name|Pid|PPid|Uid|Gid)"
echo ""
echo "Capabilities (should show only NET_BIND_SERVICE):"
kubectl exec lab-pod -- cat /proc/1/status | grep Cap

# ─── Block 4: Deployment — replicas and scheduling ───────────────────────────
echo ""
echo "=== Block 4: Deploy 3-replica deployment ==="
kubectl apply -f manifests/deployment.yml
kubectl rollout status deployment/lab-app --timeout=90s
kubectl get pods -l app=lab-app -o wide
# Pods spread across the two worker nodes

# ─── Block 5: Expose via Service and port-forward ────────────────────────────
echo ""
echo "=== Block 5: Service and port-forward ==="
kubectl apply -f manifests/service.yml
kubectl get svc

echo ""
echo "Port-forwarding ClusterIP service to localhost:8080 for 5 seconds..."
kubectl port-forward svc/lab-app 8080:80 &
PF_PID=$!
sleep 2
curl -s -o /dev/null -w "HTTP %{http_code}\n" http://localhost:8080
kill "$PF_PID" 2>/dev/null || true

# ─── Block 6: Rolling update ─────────────────────────────────────────────────
echo ""
echo "=== Block 6: Rolling update ==="
kubectl set image deployment/lab-app app=nginx:1.27-alpine
kubectl rollout status deployment/lab-app --timeout=90s

echo ""
echo "ReplicaSet history (two RS: old + new):"
kubectl get replicasets -l app=lab-app

# ─── Block 7: Rollback ───────────────────────────────────────────────────────
echo ""
echo "=== Block 7: Rollback ==="
kubectl rollout history deployment/lab-app
kubectl rollout undo deployment/lab-app
kubectl rollout status deployment/lab-app --timeout=90s

echo ""
echo "Image after rollback:"
kubectl get deployment lab-app -o jsonpath='{.spec.template.spec.containers[0].image}'
echo ""

# ─── Block 8: Scale ──────────────────────────────────────────────────────────
echo ""
echo "=== Block 8: Scale to 6 replicas ==="
kubectl scale deployment lab-app --replicas=6
kubectl rollout status deployment/lab-app --timeout=60s
kubectl get pods -l app=lab-app -o wide
# Watch pods distribute across worker nodes

# ─── Block 9: PersistentVolumeClaim ──────────────────────────────────────────
echo ""
echo "=== Block 9: PVC ==="
kubectl apply -f manifests/pvc.yml
kubectl wait --for=condition=Ready pod/pvc-demo --timeout=60s

kubectl get pvc lab-data
kubectl get pv

echo ""
echo "Data written to PVC:"
kubectl exec pvc-demo -- cat /data/out.txt

echo ""
echo "Delete and recreate pod — data persists:"
kubectl delete pod pvc-demo
kubectl apply -f manifests/pvc.yml
kubectl wait --for=condition=Ready pod/pvc-demo --timeout=60s
kubectl exec pvc-demo -- cat /data/out.txt

# ─── Block 10: Tear down ─────────────────────────────────────────────────────
echo ""
echo "=== Block 10: Tear down ==="
kubectl delete -f manifests/
kind delete cluster --name "$CLUSTER"
echo "Done."
