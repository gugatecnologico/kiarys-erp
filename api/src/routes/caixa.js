import { Router } from 'express';
import { comoUsuario } from '../db.js';
import { requireAuth, erroParaHttp } from '../auth.js';

export const caixaRouter = Router();
caixaRouter.use(requireAuth);

caixaRouter.post('/abrir', async (req, res) => {
  const { valor_inicial } = req.body ?? {};
  try {
    const caixa = await comoUsuario(req.uid, async (client) => {
      const { rows } = await client.query('select * from kiarys.abrir_caixa($1)', [valor_inicial]);
      return rows[0];
    });
    res.status(201).json(caixa);
  } catch (err) {
    const { status, erro } = erroParaHttp(err);
    res.status(status).json({ erro });
  }
});

caixaRouter.post('/movimentar', async (req, res) => {
  const { tipo, valor, motivo } = req.body ?? {};
  try {
    const mov = await comoUsuario(req.uid, async (client) => {
      const { rows } = await client.query('select * from kiarys.movimentar_caixa($1, $2, $3)', [
        tipo,
        valor,
        motivo,
      ]);
      return rows[0];
    });
    res.status(201).json(mov);
  } catch (err) {
    const { status, erro } = erroParaHttp(err);
    res.status(status).json({ erro });
  }
});

caixaRouter.post('/fechar', async (req, res) => {
  const { valor_contado } = req.body ?? {};
  try {
    const caixa = await comoUsuario(req.uid, async (client) => {
      const { rows } = await client.query('select * from kiarys.fechar_caixa($1)', [valor_contado]);
      return rows[0];
    });
    res.json(caixa);
  } catch (err) {
    const { status, erro } = erroParaHttp(err);
    res.status(status).json({ erro });
  }
});
