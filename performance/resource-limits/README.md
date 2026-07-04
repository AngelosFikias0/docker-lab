# resource-limits

Applying and observing CPU, memory, and I/O limits via Docker's cgroup interface.

---

## Run the exercises

```bash
bash exercises.sh
```

Run each block individually. Several blocks require a second terminal to run `docker stats` concurrently — noted inline.

---

## Key commands

```bash
docker run --cpus=<n> image
docker run --cpu-shares=<n> image
docker run --cpuset-cpus=<cores> image
docker run --memory=<size> image
docker run --memory-swap=<size> image
docker run --device-read-bps <dev>:<rate> image
docker run --device-write-bps <dev>:<rate> image

docker stats --no-stream <container>
docker inspect <container> --format '{{ .HostConfig.NanoCpus }}'
docker inspect <container> --format '{{ .HostConfig.Memory }}'
docker inspect <container> --format '{{ .State.OOMKilled }}'
```
