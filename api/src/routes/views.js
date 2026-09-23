// views.js
// Leitura genérica das views de public/ (db/migrations/0013_api_views.sql)
// por whitelist — nunca interpola o :name na query sem checar antes que
// ele está nesta lista fixa (é o que impede um /api/views/kiarys.perfis
// ou qualquer nome arbitrário de virar SQL).

import { Router } from 'express';
import { comoUsuario } from '../db.js';
import { requireAuth, erroParaHttp } from '../auth.js';

export const viewsRouter = Router();

const VIEWS = {
  v_estoque: { busca: ['nome', 'referencia', 'codigo_barras'] },
  v_estoque_admin: { busca: ['nome', 'referencia', 'codigo_barras'] },
  v_produtos_busca: { busca: ['nome', 'referencia'] },
  v_caixa_aberto: {},
  v_caixas: {},
  v_minhas_vendas: {},
  v_vendas_dia: {},
  v_margem: {},
};

viewsRouter.get('/:name', requireAuth, async (req, res) => {
  const config = VIEWS[req.params.name];
  if (!config) {
    return res.status(404).json({ erro: 'view desconhecida' });
  }

  const limit = Math.min(Number(req.query.limit) || 200, 500);
  const q = typeof req.query.q === 'string' ? req.query.q.trim() : '';

  let where = '';
  const params = [];
  if (q && config.busca?.length) {
    params.push(`%${q}%`);
    where = 'where ' + config.busca.map((col) => `${col} ilike $1`).join(' or ');
  }
  params.push(limit);

  try {
    const linhas = await comoUsuario(req.uid, async (client) => {
      // nome da view vem só de VIEWS (whitelist acima) — nunca de req.params direto.
      const { rows } = await client.query(
        `select * from public.${req.params.name} ${where} limit $${params.length}`,
        params
      );
      return rows;
    });
    res.json(linhas);
  } catch (err) {
    const { status, erro } = erroParaHttp(err);
    res.status(status).json({ erro });
  }
});
