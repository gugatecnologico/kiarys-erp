import { Router } from 'express';
import { randomUUID } from 'node:crypto';
import { comoUsuario } from '../db.js';
import { requireAuth, erroParaHttp } from '../auth.js';

export const vendasRouter = Router();
vendasRouter.use(requireAuth);

vendasRouter.post('/', async (req, res) => {
  const { itens, pagamentos, cliente_id = null, desconto_geral = 0 } = req.body ?? {};
  // Chave de idempotência: sempre preferir a que o celular manda (sobrevive
  // a reenvio por queda de conexão — ver kiarys.registrar_venda). Gerar
  // aqui é só um fallback pra não quebrar um cliente antigo; não protege
  // contra duplo-envio do mesmo jeito.
  const chave_idempotencia = req.body?.chave_idempotencia ?? randomUUID();

  if (!Array.isArray(itens) || itens.length === 0) {
    return res.status(400).json({ erro: 'itens é obrigatório' });
  }
  if (!Array.isArray(pagamentos) || pagamentos.length === 0) {
    return res.status(400).json({ erro: 'pagamentos é obrigatório' });
  }

  try {
    const venda = await comoUsuario(req.uid, async (client) => {
      const { rows } = await client.query(
        `select * from kiarys.registrar_venda($1::jsonb, $2::jsonb, $3, $4, $5)`,
        [JSON.stringify(itens), JSON.stringify(pagamentos), chave_idempotencia, cliente_id, desconto_geral]
      );
      return rows[0];
    });
    res.status(201).json(venda);
  } catch (err) {
    const { status, erro } = erroParaHttp(err);
    res.status(status).json({ erro });
  }
});

vendasRouter.post('/:id/cancelar', async (req, res) => {
  const { motivo } = req.body ?? {};
  if (!motivo) {
    return res.status(400).json({ erro: 'motivo é obrigatório' });
  }
  try {
    const venda = await comoUsuario(req.uid, async (client) => {
      const { rows } = await client.query('select * from kiarys.cancelar_venda($1, $2)', [
        req.params.id,
        motivo,
      ]);
      return rows[0];
    });
    res.json(venda);
  } catch (err) {
    const { status, erro } = erroParaHttp(err);
    res.status(status).json({ erro });
  }
});
