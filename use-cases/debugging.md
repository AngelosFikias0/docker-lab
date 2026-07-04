# Debugging Containers

Playbook for diagnosing common Docker problems.

---

## Container exits immediately

**Symptoms:** `docker run myapp` returns instantly, container status is `Exited (1)`.

**Diagnosis:**

```bash
docker logs <container>             # check stderr output
docker inspect <container> --format '{{ .State.ExitCode }}'
docker inspect <container> --format '{{ .State.Error }}'
```

**Common causes:**

| Exit code | Cause |
| --------- | ----- |
| 1 | Application error (check logs) |
| 127 | Command not found — wrong entrypoint or CMD |
| 126 | Command not executable — permission issue |
| 137 | OOM kill (exit code = 128 + signal 9) |
| 143 | SIGTERM received but not handled (128 + 15) |

**Fix pattern:** override CMD to get a shell and inspect the environment:

```bash
docker run --rm -it --entrypoint sh myapp
# check: ls, env, which <binary>, cat /etc/passwd
```

---

## Container starts but app is unreachable

**Symptoms:** container is running, port is published, connection refused or times out.

**Diagnosis:**

```bash
# confirm port is actually published
docker port <container>

# confirm process is listening inside the container
docker exec <container> ss -tulnp
# or
docker exec <container> netstat -tulnp

# check if it's listening on 127.0.0.1 instead of 0.0.0.0
docker exec <container> ss -tulnp | grep LISTEN
```

**Common causes:**

- App bound to `127.0.0.1` (loopback only) — must bind to `0.0.0.0` inside the container.
- Published port on wrong interface: `docker run -p 127.0.0.1:8080:80` — only accessible from host, not network.
- Firewall/iptables dropping traffic: check `iptables -L DOCKER -n`.

---

## Container is slow / high CPU

**Symptoms:** app works but response time is bad, `docker stats` shows throttling.

```bash
docker stats <container>            # live CPU%, MEM, NET I/O
docker top <container>              # processes inside with CPU/MEM
docker exec <container> top        # interactive process view inside
```

**CPU throttling** — check if the container is hitting its quota:

```bash
CGROUP=$(docker inspect <container> --format '{{ .Id }}')
cat /sys/fs/cgroup/cpu/docker/$CGROUP/cpu.stat
# look for throttled_time > 0
```

If `throttled_time` is climbing, raise `--cpus` or reduce load.

---

## OOM kill

**Symptoms:** container exits with code 137, `docker inspect` shows `OOMKilled: true`.

```bash
docker inspect <container> --format '{{ .State.OOMKilled }}'
dmesg | grep -i "out of memory"     # kernel OOM log
```

**Fix options:**
- Raise `--memory` limit.
- Add `--memory-swap` to allow swap buffer.
- Profile the app for leaks: `docker exec <container> cat /proc/<pid>/status | grep VmRSS`.

---

## Network connectivity issues

**Symptoms:** container can't reach another container or the internet.

```bash
# test DNS resolution
docker exec <container> nslookup other-container 127.0.0.11

# test reachability
docker exec <container> ping other-container
docker exec <container> wget -qO- http://other-container:8080

# confirm both containers are on the same network
docker network inspect <network> --format '{{ range .Containers }}{{ .Name }} {{ end }}'
```

**Common causes:**

- Containers on different networks — connect with `docker network connect`.
- Using default bridge — no embedded DNS. Switch to a user-defined network.
- Service name mismatch — DNS resolves the container name, not the image name.
- App inside container uses hardcoded `localhost` — must use container/service name.

---

## Debugging without a shell (distroless / scratch)

When there's no shell in the image:

```bash
# copy a static debug binary into the running container
docker cp /usr/bin/busybox <container>:/busybox
docker exec <container> /busybox sh

# or use --pid to share the container's process namespace from a debug container
docker run --rm -it \
  --pid=container:<container> \
  --network=container:<container> \
  --volumes-from <container> \
  busybox sh
```

---

## Read live state without exec

```bash
docker logs -f <container>                              # follow stdout/stderr
docker events --filter container=<container>            # real-time Docker events
docker inspect <container>                              # full JSON metadata
nsenter -t $(docker inspect -f '{{.State.Pid}}' <c>) -n ss -tulnp   # enter netns directly
```
