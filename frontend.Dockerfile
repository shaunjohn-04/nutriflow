# ---------------------------------------------------------
# NutriFlow Frontend
# React + Vite
# ---------------------------------------------------------

FROM node:20-alpine AS build

WORKDIR /app

# Install dependencies
COPY frontend/package.json frontend/package-lock.json ./

RUN npm ci

# Copy application
COPY frontend/ ./

# Vite environment variable
# This value is baked into the frontend during build.
ARG VITE_API_URL

ENV VITE_API_URL=${VITE_API_URL}

# Build React application
RUN npm run build


# ---------------------------------------------------------
# Nginx production image
# ---------------------------------------------------------

FROM nginx:1.27-alpine AS serve

COPY --from=build /app/dist /usr/share/nginx/html

COPY nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 80

HEALTHCHECK \
  --interval=30s \
  --timeout=5s \
  --start-period=10s \
  --retries=3 \
  CMD wget -qO- http://127.0.0.1/ || exit 1

CMD ["nginx", "-g", "daemon off;"]
