# ── codebase-memory-mcp — production runtime image ──────────────
#
# Multi-stage build: compile the static C binary inside Alpine, then copy
# to a minimal runtime image. No C toolchain in the final image.
#
# Build:
#   docker build -t cbm .
#   docker build --build-arg WITH_UI=true -t cbm-ui .
#
# Run:
#   docker run --rm -i -v cbm-data:/data cbm
#
# The binary is fully static (musl). The runtime image needs only git
# (for pass_githistory.c fallback + detect_changes tool) and ca-certificates.

ARG ALPINE_VERSION=3.21

# ── Stage 1: Builder ────────────────────────────────────────────
FROM alpine:${ALPINE_VERSION} AS builder

# Build dependencies
RUN apk add --no-cache \
    build-base \
    linux-headers \
    zlib-dev \
    zlib-static \
    libgit2-dev \
    pkg-config \
    bash \
    git \
    ca-certificates

# Install Node.js only when building with UI
ARG WITH_UI=false
RUN if [ "$WITH_UI" = "true" ]; then \
      apk add --no-cache nodejs npm; \
    fi

WORKDIR /src

# Copy source (respects .dockerignore if present)
COPY . .

# Build the static binary
# STATIC=1 → fully static (musl), portable to any Linux distro
# CC=gcc CXX=g++ → Alpine's system compiler
RUN if [ "$WITH_UI" = "true" ]; then \
      scripts/build.sh --with-ui CC=gcc CXX=g++ STATIC=1; \
    else \
      scripts/build.sh CC=gcc CXX=g++ STATIC=1; \
    fi

# Verify the binary is statically linked
RUN file build/c/codebase-memory-mcp | grep -q "statically linked" \
    && echo "=== Verified: statically linked ===" \
    || (echo "ERROR: binary is not statically linked" && exit 1)

# ── Stage 2: Runtime ────────────────────────────────────────────
FROM alpine:${ALPINE_VERSION}

# git: needed for pass_githistory.c fallback (popen("git log")) and
#       detect_changes tool (git diff)
# ca-certificates: for HTTPS update checks
RUN apk add --no-cache git ca-certificates && \
    rm -rf /var/cache/apk/*

# Copy the static binary
COPY --from=builder /src/build/c/codebase-memory-mcp /usr/local/bin/codebase-memory-mcp

# Copy license
COPY --from=builder /src/LICENSE /usr/share/doc/codebase-memory-mcp/LICENSE

# Persistent graph storage
ENV CBM_CACHE_DIR=/data
RUN mkdir -p /data

# Expose UI port (only used when built with WITH_UI=true)
EXPOSE 9749

# MCP server runs over stdio (JSON-RPC 2.0)
ENTRYPOINT ["codebase-memory-mcp"]
CMD []