#!/bin/sh
echo "=== Process Identity ==="
id

echo ""
echo "=== Capability Sets ==="
cat /proc/1/status | grep Cap

echo ""
echo "=== Filesystem Access Test ==="
touch /test-write 2>&1 && echo "write to / : allowed" || echo "write to / : denied (read-only)"
touch /tmp/test-write 2>&1 && echo "write to /tmp: allowed" || echo "write to /tmp: denied"

echo ""
echo "=== Staying alive for exec ==="
exec sleep 3600
