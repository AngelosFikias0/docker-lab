# syntax=docker/dockerfile:1
FROM python:3.13-slim

WORKDIR /app
COPY app.py .

# Build-time secret — fetched during build, never written to any layer.
# Usage: docker buildx build --secret id=build_token,env=BUILD_TOKEN .
RUN --mount=type=secret,id=build_token \
    echo "Build token present: $(test -f /run/secrets/build_token && echo yes || echo no)"

USER nobody
CMD ["python", "app.py"]
