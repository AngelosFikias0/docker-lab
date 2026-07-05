#!/usr/bin/env bash
set -euo pipefail

# ─── Block 1: Default container runs as root ─────────────────────────────────
echo "=== Block 1: Default container identity ==="
docker run --rm alpine id
# Output: uid=0(root) gid=0(root) groups=0(root)
# Alpine's default CMD runs as root unless overridden.

# ─── Block 2: Override UID at runtime ────────────────────────────────────────
echo ""
echo "=== Block 2: Runtime --user override ==="
docker run --rm --user 10001:10001 alpine id
# uid=10001 gid=10001 — no /etc/passwd entry required.
# Kernel checks the number, not the name.

echo ""
echo "--- Attempt to write to /etc as UID 10001 ---"
docker run --rm --user 10001:10001 alpine sh -c "touch /etc/test 2>&1 || true"

# ─── Block 3: Build and run image with USER directive ────────────────────────
echo ""
echo "=== Block 3: Image with USER directive ==="
docker build -t sec-user-demo . -q

docker run --rm --name sec-user sec-user-demo &
sleep 2

echo "--- Identity reported by container ---"
docker exec sec-user id

echo "--- USER field in image config ---"
docker inspect sec-user-demo --format 'User: {{ .Config.User }}'

docker rm -f sec-user 2>/dev/null || true

# ─── Block 4: Capability inspection ─────────────────────────────────────────
echo ""
echo "=== Block 4: Default capability set ==="
echo "Root container:"
docker run --rm alpine sh -c 'cat /proc/1/status | grep CapEff'

echo ""
echo "Non-root container (UID 10001):"
docker run --rm --user 10001 alpine sh -c 'cat /proc/1/status | grep CapEff'
# Non-root has CapEff: 0000000000000000 — empty by default.

# ─── Block 5: --cap-drop=ALL ─────────────────────────────────────────────────
echo ""
echo "=== Block 5: Drop all capabilities from root container ==="
docker run --rm --cap-drop=ALL alpine sh -c 'cat /proc/1/status | grep CapEff'
# CapEff: 0000000000000000 — root with no capabilities.
# Still UID 0 but blocked from every capability-gated syscall.

# ─── Block 6: Selective capability add-back ──────────────────────────────────
echo ""
echo "=== Block 6: Drop all, add back only NET_BIND_SERVICE ==="
docker run --rm \
  --cap-drop=ALL \
  --cap-add=NET_BIND_SERVICE \
  alpine sh -c 'cat /proc/1/status | grep CapEff'
# Only CAP_NET_BIND_SERVICE bit set. Minimal footprint.

# ─── Block 7: --read-only filesystem ─────────────────────────────────────────
echo ""
echo "=== Block 7: Read-only root filesystem ==="
echo "--- Write attempt to / (should fail) ---"
docker run --rm --read-only alpine sh -c "touch /test 2>&1 || echo 'blocked: read-only filesystem'"

echo "--- Write attempt to /tmp via tmpfs (should succeed) ---"
docker run --rm --read-only --tmpfs /tmp alpine sh -c "touch /tmp/test && echo 'allowed: tmpfs write'"

# ─── Block 8: --no-new-privileges ────────────────────────────────────────────
echo ""
echo "=== Block 8: --no-new-privileges ==="
echo "Without flag — setuid binary can escalate (if one exists):"
docker run --rm alpine sh -c 'cat /proc/1/status | grep NoNewPrivs'

echo ""
echo "With --no-new-privileges — setuid and file capabilities disabled at exec time:"
docker run --rm --no-new-privileges alpine sh -c 'cat /proc/1/status | grep NoNewPrivs'
# NoNewPrivs: 1 — execve() cannot gain capabilities from setuid or file caps.

# ─── Block 9: Fully hardened run ─────────────────────────────────────────────
echo ""
echo "=== Block 9: Full hardening flags combined ==="
docker run --rm \
  --user 10001:10001 \
  --cap-drop=ALL \
  --security-opt=no-new-privileges \
  --read-only \
  --tmpfs /tmp \
  alpine sh -c '
    echo "UID: $(id -u)"
    echo "CapEff: $(cat /proc/1/status | grep CapEff)"
    echo "NoNewPrivs: $(cat /proc/1/status | grep NoNewPrivs)"
    touch /tmp/ok && echo "tmpfs write: ok"
    touch /etc/test 2>&1 || echo "root write: blocked"
  '

# ─── Block 10: docker container top UID gotcha ───────────────────────────────
echo ""
echo "=== Block 10: container top resolves UIDs via host /etc/passwd ==="
docker run -d --name uid-demo --user 10001 alpine sleep 60

echo "docker container top (resolves via host /etc/passwd — may show wrong name):"
docker container top uid-demo

echo ""
echo "docker exec id (truth — resolved inside container):"
docker exec uid-demo id

docker rm -f uid-demo
