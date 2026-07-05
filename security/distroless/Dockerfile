FROM python:3.13-slim AS builder
WORKDIR /app
COPY app.py .

FROM gcr.io/distroless/python3-debian12
COPY --from=builder /app/app.py /app/app.py
WORKDIR /app
USER 10001
EXPOSE 8080
CMD ["app.py"]
