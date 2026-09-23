# web/Dockerfile
# Build multi-stage: compila o Vite (VITE_API_URL entra em tempo de
# build — variável de ambiente do Vite não existe em runtime) e serve o
# estático com nginx, com fallback de SPA pro React Router.
FROM node:20-alpine AS build
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
ARG VITE_API_URL
ENV VITE_API_URL=$VITE_API_URL
RUN npm run build

FROM nginx:alpine
COPY --from=build /app/dist /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 80
# build: 1790194609
