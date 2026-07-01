# syntax=docker/dockerfile:1

# Stage 1: OS-level system deps only.
# Sits low in the layer stack - changes rarely, stays cached.
FROM python:3.13-slim AS base

WORKDIR /app

# Chained in one RUN so cleanup happens in the same layer.
# Deletions in a later layer don't remove bytes already committed to OverlayFS.
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        gcc \
        libpq-dev \
        python3-dev \
    && rm -rf /var/lib/apt/lists/*


# Stage 2: Python production deps.
# Separate from source - deps change less often than code.
# requirements.txt change -> pip reinstall. main.py change -> pip cache hit.
FROM base AS deps

COPY requirements.txt .

RUN --mount=type=cache,target=/root/.cache \
    pip install -r requirements.txt


# Stage 3: Run test suite as part of the build.
# Built with --target test in CI. Failure here aborts the build before final.
FROM deps AS test

COPY requirements-dev.txt .
RUN --mount=type=cache,target=/root/.cache \
    pip install -r requirements-dev.txt

COPY . .
RUN python -m pytest tests/ -v


# Stage 4: Production image.
# Starts FROM base, not FROM deps. Build tools and test infra are never here.
FROM base AS final

# Packages cross from deps via COPY --from. Builder layers are discarded.
COPY --from=deps /usr/local/lib/python3.13/site-packages /usr/local/lib/python3.13/site-packages
COPY --from=deps /usr/local/bin /usr/local/bin

COPY main.py .

# UID 65534 = nobody. No home dir, no shell, no privileges.
USER 65534:65534

EXPOSE 8080

# Health probe using Python stdlib - no curl, no extra packages needed.
HEALTHCHECK --interval=10s --timeout=3s --start-period=5s --retries=3 \
    CMD python3 -c "import urllib.request; urllib.request.urlopen('http://localhost:8080/health')"

# Exec form: gunicorn is PID 1 and receives SIGTERM directly.
ENTRYPOINT ["gunicorn"]
CMD ["--bind", "0.0.0.0:8080", "--workers", "2", "--timeout", "30", "main:app"]
