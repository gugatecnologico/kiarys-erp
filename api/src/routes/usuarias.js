import { Router } from 'express';
import { comoUsuario } from '../db.js';
import { requireAuth, erroParaHttp } from '../auth.js';

export const usuariasRouter = Router();
usuariasRouter.use(requireAuth);

// A checagem "só admin" é da RPC (kiarys.eh_admin()), não daqui — a rota
// não decide permissão, só repassa.
usuariasRouter.post('/', async (req, res) => {
  const { nome, email, senha, papel = 'vendedora', comissao_pct = 0, limite_desconto_pct = null } =
    req.body ?? {};
  try {
    const perfil = await comoUsuario(req.uid, async (client) => {
      const { rows } = await client.query(
        'select id, nome, email, papel, ativo from kiarys.criar_usuaria($1,$2,$3,$4,$5,$6)',
        [nome, email, senha, papel, comissao_pct, limite_desconto_pct]
      );
      return rows[0];
    });
    res.status(201).json(perfil);
  } catch (err) {
    const { status, erro } = erroParaHttp(err);
    res.status(status).json({ erro });
  }
});
