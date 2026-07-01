# nginx-example

Static site served from a custom nginx configuration.

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

## Notes

`nginx:1.27-alpine` is ~45MB vs ~190MB for the Debian variant.

Default `/etc/nginx/conf.d/default.conf` is removed and replaced. Avoids inheriting base image config you did not write.

`CMD ["nginx", "-g", "daemon off;"]`: without `daemon off;`, nginx forks to the background and the container exits immediately.

`EXPOSE 80` is metadata. `-p 8080:80` on `docker run` is what creates the port mapping.
