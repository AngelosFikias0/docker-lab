# Compiled to native binary: CGO_ENABLED=0 produces a static binary with no libc dependency.
# Two cache mounts: module cache (downloaded deps) and build cache (compiled packages).
# -ldflags="-s -w" strips symbol table and DWARF debug info, reducing binary size significantly.
FROM golang:1.22-alpine AS build
WORKDIR /app
COPY go.mod .
RUN --mount=type=cache,target=/go/pkg/mod \
    go mod download
COPY main.go .
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o server .

FROM scratch
COPY --from=build /app/server /server
EXPOSE 8080
CMD ["/server"]
