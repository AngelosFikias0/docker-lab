# volumes

Named volume lifecycle, data persistence across container restarts, volume sharing, and backup/restore patterns.

---

## Run the exercises

```bash
bash exercises.sh
```

Run each block individually.

---

## The counter app

`app.py` reads a counter from `/data/count.txt`, increments it, writes it back. Run it without a volume and the count resets every time. Run it with a named volume and the count persists.

```bash
docker build -t counter:latest .
docker run --rm counter:latest                       # count=1, lost on exit
docker run --rm -v lab-data:/data counter:latest     # count persists
docker run --rm -v lab-data:/data counter:latest     # count=2
```

---

## Key commands

```bash
docker volume create <name>
docker volume ls
docker volume inspect <name>
docker volume rm <name>
docker volume prune

docker run -v <name>:/path image
docker run -v /host/path:/path image
```
