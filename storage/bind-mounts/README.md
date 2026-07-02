# bind-mounts

Bind mounts for config injection, local dev workflow, and read-only access. tmpfs for sensitive in-memory scratch space.

---

## Run the exercises

```bash
bash exercises.sh
```

Run each block individually.

---

## Concepts

### Bind mount

Maps a host filesystem path directly into the container. Docker has no management role. The host owns the path and its lifecycle.

```bash
docker run -v /host/path:/container/path image
docker run -v /host/path:/container/path:ro image    # read-only
```

Write-through is immediate in both directions. Container writes are visible on the host instantly and vice versa.

### tmpfs

RAM-only mount. No disk write. Destroyed when the container stops. Never appears in volume listings or image history.

```bash
docker run --tmpfs /path image
docker run --mount type=tmpfs,destination=/path,tmpfs-size=64m image
```

### When to use which

- **Bind mount**: dev workflow (live code reload), runtime config override, host data access
- **tmpfs**: secrets, tokens, session keys — anything that must not touch disk
- **Named volume**: production persistent data

---

## Key commands

```bash
docker run -v /host/path:/container/path image
docker run -v /host/path:/container/path:ro image
docker run --tmpfs /path image
docker inspect <container> --format '{{ json .Mounts }}'
```
