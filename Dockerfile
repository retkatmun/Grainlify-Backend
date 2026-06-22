# syntax=docker/dockerfile:1

# ─── Stage 1: build ──────────────────────────────────────────────────────────
# Downloads modules and compiles the requested binary.
# Build arg TARGET selects the entrypoint: api (default) or worker.
FROM golang:1.24-alpine AS builder

ARG TARGET=api

WORKDIR /src

# Cache module downloads as a separate layer.
COPY go.mod go.sum ./
RUN go mod download

# Copy source and compile a fully-static binary (no libc dependency).
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build \
      -trimpath \
      -ldflags="-s -w" \
      -o /out/app \
      ./cmd/${TARGET}

# ─── Stage 2: runtime ────────────────────────────────────────────────────────
# Alpine is minimal (~7 MB), ships wget for healthchecks, and has no build
# toolchain. The binary runs as a dedicated nonroot user (uid 10001).
FROM alpine:3.21 AS runtime

RUN addgroup -S app && adduser -S -G app -u 10001 app

COPY --from=builder /out/app /app

USER app

EXPOSE 8080

ENTRYPOINT ["/app"]
