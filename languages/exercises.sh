#!/usr/bin/env bash
set -euo pipefail

# 1. Build Python image
# Interpreted: no compile step, runtime bundled, pip deps cached separately from source
docker build -t lang-python languages/python/
docker images lang-python

# 2. Build Go image
# Static binary via CGO_ENABLED=0, final image is scratch — zero OS layer
docker build -t lang-go languages/go/
docker images lang-go

# 3. Build C image
# Static binary via musl libc, also lands on scratch
docker build -t lang-c languages/c/
docker images lang-c

# 4. Build Java image
# Multi-stage: JDK compiles, JRE runs. Bytecode needs the JVM at runtime.
docker build -t lang-java languages/java/
docker images lang-java

# 5. Compare all image sizes side by side
# Go and C land at a few MB. Python pulls in the interpreter. Java pulls in the JRE.
docker images --format "table {{.Repository}}\t{{.Size}}" | grep lang-

# 6. Run all four
docker run -d --name py   -p 8081:8080 lang-python
docker run -d --name go   -p 8082:8080 lang-go
docker run -d --name c    -p 8083:8080 lang-c
docker run -d --name java -p 8084:8080 lang-java
sleep 2

# 7. Curl each
curl -s http://localhost:8081
curl -s http://localhost:8082
curl -s http://localhost:8083
curl -s http://localhost:8084

# 8. Layer count per image
# Python: ~6 layers (base OS + pip install + app copy)
# Java: ~4 layers (JRE base + JAR copy)
# C: 1 layer (binary only — scratch has no base layers)
# Go: 1 layer (binary only — scratch has no base layers)
for img in lang-python lang-java lang-c lang-go; do
  echo "$img layers: $(docker history $img --no-trunc --format '{{.CreatedBy}}' | wc -l)"
done

# 9. Try to exec into scratch-based images
# These have no shell — exec will fail. The tradeoff: smaller and more secure, but undebuggable.
docker exec go /bin/sh  2>&1 || echo "no shell in scratch image"
docker exec c  /bin/sh  2>&1 || echo "no shell in scratch image"
# Python and Java have a shell:
docker exec py python --version
docker exec java java -version

# 10. Cleanup
docker rm -f py go c java
docker rmi lang-python lang-go lang-c lang-java
