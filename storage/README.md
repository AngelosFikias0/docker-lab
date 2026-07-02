# Docker Storage

All container writes go to a thin writable layer on top of the image layers. That layer is destroyed on `docker rm`. Everything in this module is about getting data off that layer and onto something that survives.

---

## Container Filesystem Internals

### UnionFS

Union filesystem stacks multiple read-only directories into one merged view. Files in upper layers shadow files at the same path in lower layers. No copying — just path resolution logic at the kernel level.

Docker uses this to build images as ordered layers, and containers as that layer stack plus one writable delta on top.

### overlay2

Default storage driver on Linux. Four roles:

| Role     | Path                           | What it is                                               |
| -------- | ------------------------------ | -------------------------------------------------------- |
| lowerdir | image layers (colon-separated) | Read-only. Shared across all containers from this image  |
| upperdir | `diff/`                        | Container's writable layer. All writes land here         |
| workdir  | `work/`                        | Kernel scratch space for atomic copy-up. Do not touch    |
| merged   | `merged/`                      | The unified view mounted into the container as `/`       |

```
/var/lib/docker/overlay2/<container-id>/
├── diff/     <- upperdir: files this container has added, modified, or whited-out
├── work/     <- workdir: staging for atomic copy-up (prevents torn writes)
└── merged/   <- live mount point; not real files, a kernel-computed view
```

**Copy-on-write (copy-up):**

When a container modifies a file that exists in a lowerdir:

1. Kernel reads the full file from lowerdir (unmodified)
2. Copies it to `work/<tmp>` — pure duplicate, no modification yet
3. Atomic `rename(work/<tmp>, diff/filename)` — file now exists in upperdir
4. Applies your write to the file now in upperdir

The copy-up cost is paid once per file per container. Subsequent writes to the same file go directly to upperdir.

**Lookup priority:**

Kernel builds a static in-memory merged dentry for every path. Priority is fixed:

```
upperdir > lowerdir[N] > lowerdir[N-1] > ... > lowerdir[0]
```

Lookup for `/etc/nginx.conf`:
- Check `diff/` first, always, no exception
- Found -> done. Never consults lowerdir
- Not found -> fall through lowerdir stack top to bottom, first match wins

**Inspect live:**

```bash
docker inspect <container> | jq '.[0].GraphDriver.Data'
# UpperDir, LowerDir, MergedDir, WorkDir

sudo ls $(docker inspect <container> --format '{{ .GraphDriver.Data.UpperDir }}')
# actual file changes made by this container
```

---

## Storage Types

### Named Volumes

Managed by Docker. Stored at `/var/lib/docker/volumes/<name>/_data/` on the host. Lifecycle is independent of any container. Survives `docker rm` and container restarts.

```bash
docker volume create mydata
docker run -v mydata:/app/data myimage
docker volume inspect mydata
docker volume ls
docker volume rm mydata
docker volume prune                       # remove all unused volumes
```

**VOLUME instruction:** declares a mount point in the image config. At container start, Docker creates an anonymous volume for that path if none is explicitly provided at runtime. Prevents accidental writes to the ephemeral writable layer for paths that must persist.

```dockerfile
VOLUME ["/data"]
```

Anonymous volumes (no name, only a SHA256 id) are created by the `VOLUME` instruction or `-v /path` without a name. Prefer named volumes — they are manageable and portable.

**Volume drivers:** default driver is `local` (host filesystem). Drivers exist for remote backends: AWS EBS, Azure Disk, NFS, etc. Same `docker run` syntax, different backend.

### Bind Mounts

Maps a host filesystem path directly into the container. Docker has no management role — the host owns the path and its lifecycle. The path must already exist on the host.

```bash
docker run -v /host/path:/container/path myimage
docker run -v /host/path:/container/path:ro myimage    # read-only
```

Use cases:
- Local dev: mount source code into a container for live reload without rebuilding
- Config injection: override a config file at runtime without rebuilding the image
- Data access: give a container read access to existing host data

Not suitable for production data portability. Tied to an absolute host path — not portable across machines or environments.

### tmpfs Mounts

RAM only. No disk write. Destroyed when the container stops or restarts. Never appears in volume listings or image history.

```bash
docker run --tmpfs /app/cache myimage
docker run --mount type=tmpfs,destination=/app/cache,tmpfs-size=64m myimage
```

Use for:
- Secrets or credentials that must never touch disk
- High-speed scratch space (faster than bind mounts or volumes)
- Sensitive intermediate data (tokens, session keys, decrypted material)

---

## Comparison

|                             | Named Volume        | Bind Mount          | tmpfs               |
| --------------------------- | ------------------- | ------------------- | ------------------- |
| Managed by                  | Docker              | Host OS             | Kernel (RAM)        |
| Persists after `docker rm`  | Yes                 | Yes (host file)     | No                  |
| Survives container restart  | Yes                 | Yes                 | No                  |
| Host path required          | No                  | Yes                 | No                  |
| Portable between hosts      | With volume driver  | No                  | N/A                 |
| Best for                    | Production data     | Local dev, config   | Secrets, temp cache |

---

## Storage Drivers

| Driver           | OS               | Notes                                            |
| ---------------- | ---------------- | ------------------------------------------------ |
| `overlay2`       | Linux            | Default. Good performance. Requires kernel 4.0+  |
| `fuse-overlayfs` | Linux (rootless) | Rootless Docker equivalent of overlay2           |
| `vfs`            | Any              | No union FS. Full copy per layer. Testing only   |

```bash
docker info | grep -i "storage driver"
```

---

## Inspection Commands

```bash
docker volume create <name>
docker volume ls
docker volume inspect <name>
docker volume rm <name>
docker volume prune

docker run -v <name>:/path image                    # named volume
docker run -v /host/path:/path image                # bind mount
docker run -v /host/path:/path:ro image             # read-only bind mount
docker run --tmpfs /path image                      # tmpfs

docker inspect <container> --format '{{ json .Mounts }}'       # active mounts
docker inspect <container> | jq '.[0].GraphDriver.Data'        # overlay2 paths
```

---

## Labs

```
storage/
+-- volumes/       # Named volumes, persistence, backup, sharing between containers
+-- bind-mounts/   # Bind mounts for config injection and dev workflow, tmpfs
```
