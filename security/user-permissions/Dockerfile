FROM alpine:3.20

# High UID avoids collision with host system UIDs (1000 is often a real host user).
RUN addgroup -g 10001 appgroup && \
    adduser -u 10001 -G appgroup -D -s /sbin/nologin appuser && \
    mkdir /app && chown 10001:10001 /app

WORKDIR /app
COPY --chown=10001:10001 app.sh .
RUN chmod +x app.sh

USER 10001:10001

ENTRYPOINT ["/app/app.sh"]
