# syntax=docker/dockerfile:1
# ─────────────────────────────────────────────────────────────────────────────
# SYNTAX DIRECTIVE
# Enables BuildKit explicitly. Required for --mount=type=cache and other
# advanced BuildKit features. Must be the first line of the Dockerfile.
# ─────────────────────────────────────────────────────────────────────────────

# ─────────────────────────────────────────────────────────────────────────────
# STAGE 1: base
# Purpose: OS-level system dependencies only.
# Rarely changes — sits low in the layer stack so it stays cached.
# Named "base" so later stages and --target can reference it.
# ─────────────────────────────────────────────────────────────────────────────
FROM python:3.13-slim AS base

# WORKDIR creates the directory if it doesn't exist and sets it as the
# working directory for all subsequent RUN, COPY, CMD, ENTRYPOINT instructions.
WORKDIR /app

# Chain all apt commands in ONE RUN instruction.
# Separate RUN instructions = separate layers.
# Deletions in a later layer don't remove bytes from earlier layers (OverlayFS).
# Chaining means cleanup happens in the same layer — bytes never persisted.
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
# Separate from source code — deps change less often than code.
# Cache invalidation rule: a layer change invalidates all layers below it.
# Keeping deps separate means editing main.py doesn't trigger pip install.
# ─────────────────────────────────────────────────────────────────────────────
FROM base AS deps

# COPY deps file FIRST — separate layer from source code.
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
# If tests fail, the build fails here — final image never produced.
# This stage never ships to production.
# ─────────────────────────────────────────────────────────────────────────────
FROM deps AS test

# Now copy source — this changes constantly, so it goes last.
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

# Copy installed packages from deps stage — not from local filesystem.
# This is the multi-stage pattern: builder stages do the heavy work,
# final stage only takes the output artifacts.
# The deps stage with all its build layers is discarded.
COPY --from=deps /usr/local/lib/python3.13/site-packages /usr/local/lib/python3.13/site-packages
COPY --from=deps /usr/local/bin /usr/local/bin

# Copy application source — changes frequently, so copied last.
# Keeps all previous layers cached on code changes.
COPY . .

# Run as non-root user.
# Default Docker runs as root — bad practice.
# UID 65534 = nobody — exists in slim images, no home dir, no shell.
# In Kubernetes: securityContext.runAsNonRoot will enforce this.
USER 65534:65534

# EXPOSE documents the port the app listens on.
# It does NOT publish the port — that's -p on docker run.
# It is metadata for humans and orchestration tools.
EXPOSE 8080

# ENTRYPOINT: the fixed executable. Always runs. Cannot be overridden by
# docker run arguments — only by --entrypoint flag.
# Use exec form ["python3"] not shell form (python3) to ensure:
#   - PID 1 is your process, not /bin/sh
#   - SIGTERM from docker stop / Kubernetes reaches your app
#   - Graceful shutdown works correctly
ENTRYPOINT ["python3"]

# CMD: default arguments passed to ENTRYPOINT.
# Overridden entirely if arguments are passed to docker run.
# Kubernetes controls this via spec.containers[].args
CMD ["main.py"]