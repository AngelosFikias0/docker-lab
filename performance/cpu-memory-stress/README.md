# cpu-memory-stress

Stress testing under enforced resource limits. Observing CPU throttling, OOM kills, and CPU share contention in real time.

---

## Run the exercises

```bash
bash exercises.sh
```

Run each block individually. Several blocks are designed to be watched with `docker stats` in a second terminal — noted inline.

---

## The stress image

`Dockerfile` builds an Alpine image with `stress-ng` installed. `stress-ng` generates precise, controllable load on CPU, memory, and I/O.

```bash
docker build -t stress:latest .
```

Key `stress-ng` flags used in these exercises:

```bash
stress-ng --cpu <n>              # spin N CPU workers at 100%
stress-ng --vm <n> --vm-bytes <size>   # allocate and write to memory
stress-ng --timeout <duration>  # run for this long then exit
stress-ng --metrics-brief       # print summary at end
```

---

## Key observations

- **Throttling**: CPU% in `docker stats` sits at the `--cpus` cap. Latency goes up, throughput stays at the limit.
- **OOM kill**: `docker inspect --format '{{ .State.OOMKilled }}'` returns `true`. The process is gone — no warning, no graceful shutdown.
- **CPU shares**: only visible under contention. Two containers spinning at 100% CPU show the share ratio in `docker stats`.
