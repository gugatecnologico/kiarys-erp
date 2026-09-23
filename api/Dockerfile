# api/Dockerfile
# Dockerfile explícito em vez de deixar o Railpack do Railway adivinhar —
# o repo tem 3 package.json irmãos (raiz, api/, tests/concorrencia/) sem
# workspaces declarados, e a detecção automática de monorepo escolheu o
# pacote errado (instalou as dependências de tests/concorrencia — só
# `pg` — em vez das da API). Com Dockerfile não tem adivinhação: o
# contexto de build já é `api/` (rootDirectory do serviço no Railway).
FROM node:20-alpine

WORKDIR /app

COPY package*.json ./
RUN npm install --omit=dev

COPY . .

EXPOSE 3000
CMD ["node", "src/index.js"]
