// cadastros.js
// CRUD simples (sem RPC dedicada) para categorias/coleções/fornecedores —
// grant direto na tabela (0014_permissoes.sql) já restringe write a
// pode_cadastrar() via RLS; a rota só passa a query adiante, mesmo padrão
// de whitelist do views.js.

import { Router } from 'express';
import { comoUsuario } from '../db.js';
import { requireAuth, erroParaHttp } from '../auth.js';

export const cadastrosRouter = Router();
cadastrosRouter.use(requireAuth);

const TABELAS = {
  categorias: { colunas: ['nome'] },
  colecoes: { colunas: ['nome', 'estacao', 'ano'] },
  fornecedores: { colunas: ['nome', 'whatsapp', 'obs'] },
};

cadastrosRouter.get('/:tabela', async (req, res) => {
  const config = TABELAS[req.params.tabela];
  if (!config) return res.status(404).json({ erro: 'cadastro desconhecido' });
  try {
    const linhas = await comoUsuario(req.uid, async (client) => {
      const { rows } = await client.query(
        `select * from kiarys.${req.params.tabela} order by nome limit 500`
      );
      return rows;
    });
    res.json(linhas);
  } catch (err) {
    const { status, erro } = erroParaHttp(err);
    res.status(status).json({ erro });
  }
});

cadastrosRouter.post('/:tabela', async (req, res) => {
  const config = TABELAS[req.params.tabela];
  if (!config) return res.status(404).json({ erro: 'cadastro desconhecido' });

  const valores = config.colunas.map((col) => req.body?.[col] ?? null);
  const placeholders = config.colunas.map((_, i) => `$${i + 1}`).join(', ');
  try {
    const linha = await comoUsuario(req.uid, async (client) => {
      const { rows } = await client.query(
        `insert into kiarys.${req.params.tabela} (${config.colunas.join(', ')}) values (${placeholders}) returning *`,
        valores
      );
      return rows[0];
    });
    res.status(201).json(linha);
  } catch (err) {
    const { status, erro } = erroParaHttp(err);
    res.status(status).json({ erro });
  }
});
