# Stage 1: build the static website assets
FROM node:20-bullseye AS builder

WORKDIR /app

# Install dependencies using the workspace-aware lockfile
COPY package.json package-lock.json ./
COPY packages ./packages
COPY tsconfig.json ./

RUN npm ci

# Build the production assets for the website workspace
RUN npm run build:website

# Stage 2: serve the built assets with nginx
FROM nginx:1.27-alpine AS runtime

# Copy the compiled site into nginx's public directory
COPY --from=builder /app/packages/website/dist /usr/share/nginx/html

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
