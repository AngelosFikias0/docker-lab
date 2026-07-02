#!/usr/bin/env bash
# volumes/exercises.sh
# Run blocks individually. Each section is self-contained.
# Not meant to be executed top-to-bottom as a pipeline.

# ---------------------------------------------------------------------------
# 1. CREATE AND INSPECT A NAMED VOLUME
# Docker manages the path. No host path needed.
# ---------------------------------------------------------------------------
docker volume create lab-data

docker volume inspect lab-data
# MountPoint: /var/lib/docker/volumes/lab-data/_data

docker volume ls

# ---------------------------------------------------------------------------
# 2. DATA PERSISTENCE - write data, remove container, read with new container
# ---------------------------------------------------------------------------
docker run --rm -v lab-data:/data alpine sh -c "echo 'persisted' > /data/hello.txt"

# Container is gone. Volume is not.
docker run --rm -v lab-data:/data alpine cat /data/hello.txt
# persisted

# ---------------------------------------------------------------------------
# 3. WITHOUT A VOLUME - writable layer is destroyed on docker rm
# ---------------------------------------------------------------------------
docker run --rm alpine sh -c "echo 'ephemeral' > /tmp/test.txt && cat /tmp/test.txt"
# Works inside the container

# Second container - different writable layer, file is gone
docker run --rm alpine cat /tmp/test.txt 2>/dev/null || echo "file is gone"

# ---------------------------------------------------------------------------
# 4. NAMED VOLUME VS ANONYMOUS VOLUME
# VOLUME instruction in a Dockerfile creates an anonymous volume if no -v given.
# ---------------------------------------------------------------------------
docker run -d --name anon -v /data alpine sleep infinity     # anonymous: SHA256 id
docker run -d --name named -v lab-data:/data alpine sleep infinity  # named

docker volume ls
# one entry has a sha256 id (anonymous), one has "lab-data"

docker stop anon named && docker rm anon named
docker volume prune -f    # remove the anonymous volume

# ---------------------------------------------------------------------------
# 5. VOLUME POPULATED FROM IMAGE AT FIRST RUN
# If the mount point has content in the image, Docker copies it into the
# volume on first use. Subsequent mounts see the volume content, not the image.
# ---------------------------------------------------------------------------
docker run --rm -v lab-data:/data alpine sh -c "ls /data"
# hello.txt is still there from block 2 - volume content wins

# ---------------------------------------------------------------------------
# 6. SHARE A VOLUME BETWEEN TWO CONTAINERS
# Writer and reader mount the same volume concurrently.
# ---------------------------------------------------------------------------
docker run -d --name writer -v lab-data:/data \
  alpine sh -c "while true; do date >> /data/log.txt; sleep 2; done"

docker run --rm -v lab-data:/data alpine tail -5 /data/log.txt
# Entries written by writer are immediately visible

docker stop writer && docker rm writer

# ---------------------------------------------------------------------------
# 7. VOLUME BACKUP - tar the volume content to the host
# Spin up a throwaway container with two mounts: the volume (ro) and
# the backup destination (bind mount to current dir).
# ---------------------------------------------------------------------------
docker run --rm \
  -v lab-data:/data:ro \
  -v "$(pwd)":/backup \
  alpine tar czf /backup/lab-data.tar.gz -C /data .

ls -lh lab-data.tar.gz

# ---------------------------------------------------------------------------
# 8. VOLUME RESTORE
# ---------------------------------------------------------------------------
docker volume create lab-data-restored

docker run --rm \
  -v lab-data-restored:/data \
  -v "$(pwd)":/backup \
  alpine tar xzf /backup/lab-data.tar.gz -C /data

docker run --rm -v lab-data-restored:/data alpine ls /data
# same files as the original volume

# ---------------------------------------------------------------------------
# 9. COUNTER APP - VOLUME instruction in a Dockerfile
# Without a volume mount the count resets every run (writable layer).
# With a named volume the count persists across container restarts.
# ---------------------------------------------------------------------------
docker build -t counter:latest .

echo "--- without volume (resets each run) ---"
docker run --rm counter:latest
docker run --rm counter:latest

echo "--- with named volume (persists) ---"
docker run --rm -v lab-data:/data counter:latest
docker run --rm -v lab-data:/data counter:latest
docker run --rm -v lab-data:/data counter:latest

# ---------------------------------------------------------------------------
# 10. INSPECT THE HOST PATH
# ---------------------------------------------------------------------------
MOUNTPOINT=$(docker volume inspect lab-data --format '{{ .Mountpoint }}')
echo "Volume on host: $MOUNTPOINT"
sudo ls "$MOUNTPOINT"

# ---------------------------------------------------------------------------
# 11. CLEANUP
# ---------------------------------------------------------------------------
rm -f lab-data.tar.gz
docker volume rm lab-data lab-data-restored
docker rmi counter:latest
