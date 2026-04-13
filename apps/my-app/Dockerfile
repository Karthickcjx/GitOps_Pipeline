# =============================================================================
# Multi-Stage Dockerfile
# =============================================================================
# Best practices:
#   - Multi-stage build (builder + distroless final)
#   - Non-root user
#   - No secrets in image layers
#   - Health check instruction
#   - Minimal attack surface with distroless
# =============================================================================

# ── Stage 1: Build ──────────────────────────────────────────────────────────
FROM golang:1.22-alpine AS builder

# Build arguments for version injection
ARG VERSION=dev
ARG COMMIT=unknown
ARG BUILD_TIME=unknown

# Install dependencies
RUN apk add --no-cache git ca-certificates tzdata

WORKDIR /app

# Cache Go modules
COPY go.mod go.sum ./
RUN go mod download && go mod verify

# Copy source code
COPY src/ ./src/

# Build the binary with optimizations
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build \
    -ldflags="-w -s \
      -X main.version=${VERSION} \
      -X main.commit=${COMMIT} \
      -X main.buildTime=${BUILD_TIME}" \
    -o /app/server \
    ./src/main.go

# ── Stage 2: Final (Distroless) ────────────────────────────────────────────
FROM gcr.io/distroless/static-debian12:nonroot

# Labels for image metadata
LABEL maintainer="platform-team@example.com"
LABEL org.opencontainers.image.title="my-app"
LABEL org.opencontainers.image.description="GitOps Platform Microservice"
LABEL org.opencontainers.image.source="https://github.com/org/gitops-platform"

# Copy timezone data and CA certificates from builder
COPY --from=builder /usr/share/zoneinfo /usr/share/zoneinfo
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/

# Copy the binary
COPY --from=builder /app/server /server

# Expose ports
EXPOSE 8080 9090

# Run as non-root user (distroless nonroot user = 65534)
USER 65534:65534

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD ["/server", "--health-check"] || exit 1

# Entrypoint
ENTRYPOINT ["/server"]
