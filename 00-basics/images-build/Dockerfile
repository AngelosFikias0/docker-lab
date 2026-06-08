# -----------------------------------------------------------------------------
# BASE IMAGE
# Always pin to a specific tag. Never use `latest` — it's non-deterministic.
# `slim` variants strip debug tools. Good for production, fine for basics.
# -----------------------------------------------------------------------------
FROM python:3.12-slim

# -----------------------------------------------------------------------------
# METADATA
# Labels are queryable via `docker inspect`. Use them.
# -----------------------------------------------------------------------------
LABEL maintainer="fikias@test.com"
LABEL description="00-basics image-build exercise"

# -----------------------------------------------------------------------------
# ENV — build-time and runtime variables
# These become the defaults. Override with `docker run -e KEY=value`.
# -----------------------------------------------------------------------------
ENV APP_ENV=production \
    PORT=8080 \
    PYTHONUNBUFFERED=1

# PYTHONUNBUFFERED=1: forces Python stdout/stderr to be unbuffered.
# Without this, logs don't appear in `docker logs` until the buffer flushes.

# -----------------------------------------------------------------------------
# WORKDIR
# Sets the working directory for all subsequent instructions.
# Creates the directory if it doesn't exist.
# Never dump files into /. Use a dedicated path.
# -----------------------------------------------------------------------------
WORKDIR /app

# -----------------------------------------------------------------------------
# COPY
# COPY <src> <dest>
# src is relative to the build context (your local filesystem).
# dest is relative to WORKDIR inside the image.
#
# Copy dependency manifests first (if any) before source code.
# Docker caches each RUN/COPY layer. If requirements.txt doesn't change,
# the pip install layer is reused — build is fast.
# Only then copy source code, which changes more frequently.
#
# Here: no dependencies, so we copy the app directly.
# -----------------------------------------------------------------------------
COPY app.py .

# -----------------------------------------------------------------------------
# EXPOSE
# Documents which port the app listens on.
# Does NOT publish the port. That's `-p` at `docker run` time.
# Purely informational — but always include it.
# -----------------------------------------------------------------------------
EXPOSE 8080

# -----------------------------------------------------------------------------
# USER — never run as root in production
# Python slim image doesn't have a non-root user by default, so we create one.
# In real images (nginx-unprivileged, etc.) this is already handled.
# -----------------------------------------------------------------------------
RUN useradd --no-create-home --shell /bin/false appuser
USER appuser

# -----------------------------------------------------------------------------
# ENTRYPOINT vs CMD
#
# ENTRYPOINT — defines the executable. Hard to override (requires --entrypoint).
# CMD        — defines default arguments. Easily overridden at `docker run`.
#
# Combined pattern (preferred):
#   ENTRYPOINT ["python"]         <- the binary
#   CMD ["app.py"]                <- the default argument
#
# This lets you do: `docker run myimage app.py` (uses CMD)
# Or override:      `docker run myimage other.py` (replaces CMD only)
#
# Always use exec form ["..."] not shell form "..." — exec form doesn't
# spawn a shell, so SIGTERM reaches your process directly (clean shutdown).
# -----------------------------------------------------------------------------
ENTRYPOINT ["python"]
CMD ["app.py"]
