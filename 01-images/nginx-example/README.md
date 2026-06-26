# nginx-example

A minimal static site served from a custom nginx configuration. Demonstrates replacing the default nginx config and serving content from a custom HTML directory.

---

## Files

| File              | Purpose                                     |
| ----------------- | ------------------------------------------- |
| `Dockerfile`      | Extend nginx:alpine, swap config, copy HTML |
| `nginx.conf`      | Custom server block                         |
| `html/index.html` | Static content                              |

---

## Build and run

```bash
docker build -t nginx-example:0.0.1 .
docker run --rm -p 8080:80 nginx-example:0.0.1
curl localhost:8080
```

---

## Key patterns

**Alpine base**: `nginx:1.27-alpine` is ~45MB vs ~190MB for the Debian variant. Appropriate for a static content server with no system packages needed.

**Replace default config**: the default `/etc/nginx/conf.d/default.conf` is removed and replaced with a minimal custom config. Avoids inheriting base image configuration you didn't write.

**Exec form CMD**: `["nginx", "-g", "daemon off;"]` runs nginx in the foreground. Without `daemon off;`, nginx forks to the background and the container exits immediately.

**Port mapping**: nginx listens on 80. The `-p 8080:80` flag on `docker run` maps host port 8080 to container port 80. `EXPOSE 80` in the Dockerfile is metadata only, it does not open the port.
