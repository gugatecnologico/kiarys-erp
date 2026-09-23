# Kiarys ERP — web

Frontend da tela do Time (Vender · Estoque · Meu caixa · Minhas vendas).
Vite + React + TypeScript, sem UI framework — CSS simples em
`src/index.css`, mobile-first (a vendedora usa isso na arara, com o
celular na mão).

## Desenvolvimento

```bash
cp .env.example .env   # aponte VITE_API_URL pra API rodando local
npm install
npm run dev
```

## Deploy

Build estático (`npm run build`, saída `dist/`) — ver seção "Frontend"
do README da raiz do repo.
