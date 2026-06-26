# syntax=docker/dockerfile:1
# ─────────────────────────────────────────────────────────────────────────────
# SYNTAX DIRECTIVE
# Enables BuildKit explicitly. Required for --mount=type=cache and other
# advanced BuildKit features. Must be the first line of the Dockerfile.
# ─────────────────────────────────────────────────────────────────────────────

# ─────────────────────────────────────────────────────────────────────────────
# STAGE 1: base
# Purpose: OS-level system dependencies only.
# Rarely changes - sits low in the layer stack so it stays cached.
# Named "base" so later stages and --target can reference it.
# ─────────────────────────────────────────────────────────────────────────────
FROM python:3.13-slim AS base

# WORKDIR creates the directory if it doesn't exist and sets it as the
# working directory for all subsequent RUN, COPY, CMD, ENTRYPOINT instructions.
WORKDIR /app

# Chain all apt commands in ONE RUN instruction.
# Separate RUN instructions = separate layers.
# Deletions in a later layer don't remove bytes from earlier layers (OverlayFS).
# Chaining means cleanup happens in the same layer - bytes never persisted.
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        gcc \
        libpq-dev \
        python3-dev \
    && rm -rf /var/lib/apt/lists/*
#   ^^^^^^^^^^^^^^^^^^^^^^^^^^^^
#   Cleanup in same layer = no wasted bytes in image


# ─────────────────────────────────────────────────────────────────────────────
# STAGE 2: deps
# Purpose: Install Python dependencies.
# Separate from source code - deps change less often than code.
# Cache invalidation rule: a layer change invalidates all layers below it.
# Keeping deps separate means editing main.py doesn't trigger pip install.
# ─────────────────────────────────────────────────────────────────────────────
FROM base AS deps

# COPY deps file FIRST - separate layer from source code.
# This layer is only invalidated when requirements.txt changes.
# If you copied everything at once (COPY . .) any code change would
# invalidate this layer and trigger a full pip install.
COPY requirements.txt .

# --mount=type=cache,target=/root/.cache
# Mounts a persistent cache directory from the HOST into this RUN step.
# pip stores downloaded wheels in /root/.cache/pip/
# Without this: wheels are downloaded fresh every build, discarded after.
# With this:    wheels are downloaded once, cached on host, reused forever.
# The cache directory does NOT ship in the final image.
# The cache survives --no-cache and layer invalidation.
RUN --mount=type=cache,target=/root/.cache \
    pip install -r requirements.txt


# ─────────────────────────────────────────────────────────────────────────────
# STAGE 3: test
# Purpose: Run test suite inside the image during CI.
# Built with --target test in CI pipelines.
# If tests fail, the build fails here - final image never produced.
# This stage never ships to production.
# ─────────────────────────────────────────────────────────────────────────────
FROM deps AS test

# pytest is a dev-only dependency - it must not ship in the production image.
# Install it here, in the test stage only, separate from prod deps.
COPY requirements-dev.txt .
RUN --mount=type=cache,target=/root/.cache \
    pip install -r requirements-dev.txt

# Now copy source - this changes constantly, so it goes last.
# Invalidating this layer only rebuilds test + final, not pip install.
COPY . .

# Run tests as part of the build.
# In CI: docker build --target test → gates the pipeline.
RUN python -m pytest tests/ -v


# ─────────────────────────────────────────────────────────────────────────────
# STAGE 4: final
# Purpose: Production image. Lean, secure, minimal.
# Only what is needed to run the app ships here.
# ─────────────────────────────────────────────────────────────────────────────
FROM base AS final

# Copy installed packages from deps stage - not from local filesystem.
# This is the multi-stage pattern: builder stages do the heavy work,
# final stage only takes the output artifacts.
# The deps stage with all its build layers is discarded.
COPY --from=deps /usr/local/lib/python3.13/site-packages /usr/local/lib/python3.13/site-packages
COPY --from=deps /usr/local/bin /usr/local/bin

# Copy only the application source - not test files, not dev requirements.
# This is deliberate: the final image ships only what it needs to run.
COPY main.py .

# Run as non-root user.
# Default Docker runs as root - bad practice.
# UID 65534 = nobody - exists in slim images, no home dir, no shell.
# In Kubernetes: securityContext.runAsNonRoot will enforce this.
USER 65534:65534

# EXPOSE documents the port the app listens on.
# It does NOT publish the port - that's -p on docker run.
# It is metadata for humans and orchestration tools.
EXPOSE 8080

# Health probe using Python stdlib - no curl, no extra packages.
# Runs in the container as the configured user (nobody).
# docker stop / Kubernetes readiness checks will call this.
HEALTHCHECK --interval=10s --timeout=3s --start-period=5s --retries=3 \
    CMD python3 -c "import urllib.request; urllib.request.urlopen('http://localhost:8080/health')"

# gunicorn - production WSGI server.
# Flask's built-in app.run() is single-threaded and not production-safe.
# gunicorn: multi-worker, proper SIGTERM handling, standard in production.
#
# ENTRYPOINT: the fixed executable. Cannot be overridden by docker run args.
# CMD: default arguments, easily overridden at runtime.
# Exec form ensures gunicorn is PID 1 and receives SIGTERM directly.
ENTRYPOINT ["gunicorn"]
CMD ["--bind", "0.0.0.0:8080", "--workers", "2", "--timeout", "30", "main:app"]