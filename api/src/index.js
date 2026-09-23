import express from 'express';
import cors from 'cors';
import { authRouter } from './routes/auth.js';
import { viewsRouter } from './routes/views.js';
import { caixaRouter } from './routes/caixa.js';
import { vendasRouter } from './routes/vendas.js';
import { estoqueRouter } from './routes/estoque.js';
import { usuariasRouter } from './routes/usuarias.js';
import { cadastrosRouter } from './routes/cadastros.js';

const app = express();

// CORS_ORIGIN="*" precisa virar a STRING '*' (curinga de verdade pra lib
// `cors`), não um array ['*'] — .split(',') numa string "*" devolve
// ['*'], e a lib trata array como allowlist de valores exatos, nunca
// batendo com nenhuma origem real. Foi assim que o preview local (porta
// diferente da API) ficou bloqueado em silêncio até eu testar de verdade
// num navegador — curl nunca manda Origin, então nunca pega esse bug.
const corsOrigin =
  !process.env.CORS_ORIGIN || process.env.CORS_ORIGIN === '*' ? '*' : process.env.CORS_ORIGIN.split(',');

app.use(cors({ origin: corsOrigin }));
app.use(express.json());

app.get('/health', (_req, res) => res.json({ ok: true }));

app.use('/auth', authRouter);
app.use('/api/views', viewsRouter);
app.use('/api/caixa', caixaRouter);
app.use('/api/vendas', vendasRouter);
app.use('/api/estoque', estoqueRouter);
app.use('/api/usuarias', usuariasRouter);
app.use('/api/cadastros', cadastrosRouter);

// eslint-disable-next-line no-unused-vars
app.use((err, _req, res, _next) => {
  console.error('🔴 erro não tratado:', err);
  res.status(500).json({ erro: 'erro interno' });
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`🟢 kiarys-api ouvindo na porta ${PORT}`);
});
