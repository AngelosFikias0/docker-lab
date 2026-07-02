FROM python:3.13-slim

WORKDIR /app
COPY app.py .

# Declares /data as a persistent mount point.
# Without an explicit -v at runtime, Docker creates an anonymous volume here.
# Data written to /data never goes to the ephemeral writable layer.
VOLUME ["/data"]

CMD ["python", "app.py"]
