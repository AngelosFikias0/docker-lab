#!/usr/bin/env bash
# bind-mounts/exercises.sh
# Run blocks individually. Each section is self-contained.
# Not meant to be executed top-to-bottom as a pipeline.

# ---------------------------------------------------------------------------
# 1. BASIC BIND MOUNT - host directory into container
# ---------------------------------------------------------------------------
mkdir -p /tmp/bindlab
echo "hello from host" > /tmp/bindlab/hello.txt

docker run --rm -v /tmp/bindlab:/data alpine cat /data/hello.txt
# hello from host

# ---------------------------------------------------------------------------
# 2. WRITE-THROUGH - container writes are immediately visible on the host
# ---------------------------------------------------------------------------
docker run --rm -v /tmp/bindlab:/data alpine \
  sh -c "echo 'written by container' > /data/from-container.txt"

cat /tmp/bindlab/from-container.txt
# written by container - host sees it immediately

# ---------------------------------------------------------------------------
# 3. READ-ONLY BIND MOUNT
# ---------------------------------------------------------------------------
docker run --rm -v /tmp/bindlab:/data:ro alpine \
  sh -c "echo 'try write' > /data/fail.txt" 2>&1 || true
# Expected: /data/fail.txt: Read-only file system

# ---------------------------------------------------------------------------
# 4. SINGLE FILE MOUNT - mount one file, not an entire directory
# Useful for injecting a single config without exposing the rest of the dir.
# ---------------------------------------------------------------------------
echo "APP_ENV=production" > /tmp/app.env

docker run --rm \
  -v /tmp/app.env:/app/.env:ro \
  alpine cat /app/.env

# ---------------------------------------------------------------------------
# 5. CONFIG INJECTION - override nginx config without rebuilding the image
# ---------------------------------------------------------------------------
mkdir -p /tmp/nginx-conf
cat > /tmp/nginx-conf/default.conf << 'EOF'
server {
    listen 8080;
    location / {
        return 200 "injected config\n";
        add_header Content-Type text/plain;
    }
}
EOF

docker run -d --name nginx-injected \
  -v /tmp/nginx-conf/default.conf:/etc/nginx/conf.d/default.conf:ro \
  -p 8080:8080 \
  nginx:alpine

curl -s localhost:8080
# injected config

docker stop nginx-injected && docker rm nginx-injected

# ---------------------------------------------------------------------------
# 6. TMPFS MOUNT - RAM only, no disk write, destroyed on container stop
# ---------------------------------------------------------------------------
docker run -d --name tmpfs-demo \
  --tmpfs /app/cache:size=64m \
  alpine sleep infinity

docker exec tmpfs-demo sh -c "echo 'in ram' > /app/cache/secret.txt && cat /app/cache/secret.txt"
docker exec tmpfs-demo df -h /app/cache    # shows: tmpfs

docker stop tmpfs-demo && docker rm tmpfs-demo

# New container, same image, same path - data is gone
docker run --rm alpine sh -c "cat /app/cache/secret.txt 2>/dev/null || echo 'gone'"

# ---------------------------------------------------------------------------
# 7. INSPECT ACTIVE MOUNTS ON A RUNNING CONTAINER
# ---------------------------------------------------------------------------
docker run -d --name inspect-demo \
  -v /tmp/bindlab:/data:ro \
  --tmpfs /tmp/scratch:size=32m \
  alpine sleep infinity

docker inspect inspect-demo --format '{{ json .Mounts }}' | python3 -m json.tool

docker stop inspect-demo && docker rm inspect-demo

# ---------------------------------------------------------------------------
# 8. PERMISSIONS - container runs as non-root, host file owned by root
# Bind mounts use host filesystem permissions as-is.
# If the container process can't write to the host path, writes fail.
# ---------------------------------------------------------------------------
mkdir -p /tmp/perms-test

docker run --rm \
  -v /tmp/perms-test:/data \
  --user 1000:1000 \
  alpine sh -c "echo 'test' > /data/test.txt 2>&1 || echo 'permission denied'"

# Fix: set permissions on the host path first
chmod 777 /tmp/perms-test

docker run --rm \
  -v /tmp/perms-test:/data \
  --user 1000:1000 \
  alpine sh -c "echo 'test' > /data/test.txt && echo 'wrote ok'"

# ---------------------------------------------------------------------------
# 9. CLEANUP
# ---------------------------------------------------------------------------
rm -rf /tmp/bindlab /tmp/nginx-conf /tmp/app.env /tmp/perms-test
