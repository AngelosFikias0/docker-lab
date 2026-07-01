# syntax=docker/dockerfile:1

# STAGE 1: builder
# Use a full Python image to install dependencies.
# pip --target collects everything into one directory so the COPY --from is explicit.
FROM python:3.11-slim AS builder

WORKDIR /app

COPY requirements.txt .
RUN --mount=type=cache,target=/root/.cache \
    pip install --target /app/packages -r requirements.txt


# STAGE 2: final
# gcr.io/distroless/python3-debian12 contains Python 3.11 and nothing else.
# No shell. No package manager. No coreutils. No /bin/sh.
# Smaller attack surface: fewer binaries means fewer things to exploit.
FROM gcr.io/distroless/python3-debian12

WORKDIR /app

# Copy the packages installed in builder, not the system site-packages.
COPY --from=builder /app/packages /app/packages

# Copy only the application source.
COPY main.py .

# Tell Python where to find the packages we copied.
# Required because we used pip --target instead of installing into site-packages.
ENV PYTHONPATH=/app/packages

EXPOSE 8080

# Exec form is not optional here - there is no /bin/sh to interpret shell form.
# This applies to ENTRYPOINT, CMD, and HEALTHCHECK.
HEALTHCHECK --interval=10s --timeout=3s --start-period=5s --retries=3 \
    CMD ["python3", "-c", "import urllib.request; urllib.request.urlopen('http://localhost:8080/health')"]

# python3 -m gunicorn invokes gunicorn via its __main__ module.
# This avoids needing the gunicorn binary on PATH.
ENTRYPOINT ["python3", "-m", "gunicorn"]
CMD ["--bind", "0.0.0.0:8080", "--workers", "2", "--timeout", "30", "main:app"]
