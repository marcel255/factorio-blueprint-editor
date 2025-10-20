# Stage 1: build the static website assets
FROM node:20-bullseye AS website-builder

WORKDIR /app

# Install dependencies using the workspace-aware lockfile
COPY package.json package-lock.json ./
COPY packages ./packages
COPY tsconfig.json ./

RUN npm ci

# Build the production assets for the website workspace
RUN npm run build:website

# Stage 2: build the exporter binary
FROM rust:1.83-slim AS exporter-builder

WORKDIR /app

# Install build dependencies for reqwest/OpenSSL
RUN apt-get update \
    && apt-get install -y --no-install-recommends pkg-config libssl-dev \
    && rm -rf /var/lib/apt/lists/*

# Prime the cargo cache
COPY packages/exporter/Cargo.toml ./Cargo.toml
COPY packages/exporter/Cargo.lock ./Cargo.lock
RUN mkdir src \
    && echo "fn main() {}" > src/main.rs \
    && cargo build --locked --release \
    && rm -rf src target/release/deps target/release/build target/release/incremental

# Compile the actual exporter with sources and assets
COPY packages/exporter ./
RUN cargo build --locked --release

# Stage 3: runtime image for the exporter service
FROM debian:bookworm-slim AS exporter

WORKDIR /app

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        libatomic1 \
        libcurl4 \
        libstdc++6 \
        libxml2 \
        xz-utils \
        zlib1g \
    && rm -rf /var/lib/apt/lists/*

COPY --from=exporter-builder /app/target/release/factorio_data_exporter /usr/local/bin/factorio_data_exporter
COPY packages/exporter/basisu ./basisu
COPY packages/exporter/basisu.exe ./basisu.exe
COPY packages/exporter/data ./data

RUN mkdir -p /app/data/output

EXPOSE 8081

VOLUME ["/app/data/output"]

ENTRYPOINT ["/usr/local/bin/factorio_data_exporter"]

# Stage 4: serve the built assets with nginx
FROM nginx:1.27-alpine AS runtime

# Copy the compiled site into nginx's public directory
COPY --from=website-builder /app/packages/website/dist /usr/share/nginx/html

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
