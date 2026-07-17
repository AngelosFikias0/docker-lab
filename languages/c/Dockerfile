# Compiled to native binary: no runtime needed. Static linking against musl libc
# produces a self-contained binary that runs on scratch (zero-byte base image).
FROM alpine:3.20 AS build
RUN apk add --no-cache gcc musl-dev
WORKDIR /app
COPY main.c .
RUN gcc -o server main.c -static -Wall

FROM scratch
COPY --from=build /app/server /server
EXPOSE 8080
CMD ["/server"]
