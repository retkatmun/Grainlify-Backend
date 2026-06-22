# Development Guide

## Logging Guidelines

To maintain security and reduce noise in production, follow these logging guidelines:
1. **Never log secrets or PII at INFO level.** This includes tokens (`SOROBAN_SOURCE_SECRET`, OAuth tokens, JWT secrets), emails, and KYC decision data.
2. **Use `slog.Debug` for verbose data.** Large payloads (like webhook bodies) and full header dumps must be logged at `Debug` level, not `Info`.
3. **Redact sensitive fields.** When logging maps or structs that contain addresses or amounts, use the `logger.RedactMap` helper to sanitize the output before logging at `Info`.

Example:
```go
import "github.com/jagadeesh/grainlify/backend/internal/logger"

redactedArgs := logger.RedactMap(args)
slog.Info("interaction occurred", "args", redactedArgs) // Safe for INFO
slog.Debug("interaction detailed", "args", args)        // Safe for DEBUG
```

## Running the Backend Server

### Option 1: Auto-reload with Air (Recommended for Development) ⚡

The server will **automatically restart** when you make changes to any `.go` file.

```bash
# Quick start - recommended (handles PATH and installation automatically)
./run-dev.sh

# Or directly with air (if already installed)
air

# Or using make
make dev
```

**What gets watched:**
- All `.go` files in `cmd/`, `internal/`, and root
- Automatically excludes: `tmp/`, `vendor/`, `testdata/`, `migrations/`, `.git/`, test files
- Restarts within 1 second of file changes

**First time setup:**
```bash
# Install air
go install github.com/air-verse/air@latest

# Add to PATH (add to ~/.zshrc or ~/.bashrc)
export PATH=$PATH:$HOME/go/bin
```

### Option 2: Standard Go Run (No Auto-reload)

```bash
go run ./cmd/api

# Or using make
make run
```

## Installing Air

If `air` is not found, install it:

```bash
go install github.com/air-verse/air@latest
```

Make sure `~/go/bin` is in your PATH. Add this to your `~/.zshrc` or `~/.bashrc`:

```bash
export PATH=$PATH:$HOME/go/bin
```

## Configuration

Air configuration is in `.air.toml`. It watches for changes in:
- All `.go` files
- Excludes `tmp/`, `vendor/`, `testdata/`, `migrations/`, `.git/`
- Excludes `*_test.go` files

## Build Commands

```bash
# Build binary
make build
# or
go build -o ./api ./cmd/api

# Run migrations
go run ./cmd/migrate

# Run worker
go run ./cmd/worker
```

## Running Tests

### Unit tests (no database required)

```bash
go test ./internal/handlers/... ./internal/ingest/...
```

The handler tests (`internal/handlers`) are pure unit tests with a mock bus — no external dependencies.

### Integration tests (requires PostgreSQL)

DB integration tests in `internal/ingest` are gated behind the `TEST_DB_URL` environment variable.  
When the variable is absent the tests are **skipped automatically** — they never fail in CI unless you opt in.

Set `TEST_DB_URL` to a throwaway Postgres database:

```bash
export TEST_DB_URL="postgres://user:pass@localhost:5432/grainlify_test?sslmode=disable"
go test ./internal/ingest/...
```

The test harness calls `migrate.Up` automatically, so the target database only needs to exist (it does not need pre-created tables).  
Each test cleans up the rows it inserts via `t.Cleanup`, so the schema stays clean between runs.

> **CI**: add `TEST_DB_URL` as a secret/environment variable in your pipeline to enable DB integration tests.

## Running Lint

CI runs `golangci-lint` with the pinned version in `.github/workflows/ci.yml`.

Install the same version locally:

```bash
go install github.com/golangci/golangci-lint/v2/cmd/golangci-lint@v2.12.2
```

Then run:

```bash
golangci-lint run ./...
# or
make lint
```

The lint configuration is in `.golangci.yml`. Existing legacy findings are explicitly excluded there so new changes can be checked without forcing a broad cleanup in the first linting PR.

## Docker Compose (fully containerised stack)

Runs the API, worker, Postgres, and NATS together — no local Go toolchain or database required.

### Prerequisites

- [Docker Desktop](https://docs.docker.com/get-docker/) ≥ 24 (includes Compose v2)

### First-time setup

```bash
# Copy the env template — compose reads .env automatically
cp .env.example .env
# Edit .env and fill in GitHub OAuth, JWT_SECRET, etc.
# DB_URL and NATS_URL are overridden by compose; you can leave them blank.
```

### Start the stack

```bash
docker compose up --build
```

This will:
1. Build the `api` and `worker` images from the repo root using the multi-stage `Dockerfile`.
2. Start Postgres (with a persistent volume) and NATS.
3. Run database migrations automatically (`AUTO_MIGRATE=true`).
4. Serve the API at **http://localhost:8080**.

### Common commands

```bash
# Start in the background
docker compose up -d --build

# Tail logs for a specific service
docker compose logs -f api

# Stop and remove containers (data volume is preserved)
docker compose down

# Stop and destroy all data
docker compose down -v

# Rebuild after source changes
docker compose up --build api
```

### Build targets

The `Dockerfile` accepts a `TARGET` build arg (`api` or `worker`) to select which `cmd/` entrypoint to compile. Compose passes this automatically; to build either image manually:

```bash
docker build --build-arg TARGET=api    -t grainlify-api:local .
docker build --build-arg TARGET=worker -t grainlify-worker:local .
```

### Security notes

- The runtime image (`alpine:3.21`) contains no build toolchain.
- The binary runs as uid **10001** (non-root).
- Secrets are never baked into the image; they are injected at runtime via `env_file` / environment variables.
