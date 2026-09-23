import { Router } from 'express';
import { comoUsuario } from '../db.js';
import { assinarToken, requireAuth, erroParaHttp } from '../auth.js';

export const authRouter = Router();

authRouter.post('/login', async (req, res) => {
  const { email, senha } = req.body ?? {};
  if (!email || !senha) {
    return res.status(400).json({ erro: 'email e senha são obrigatórios' });
  }

  try {
    const perfil = await comoUsuario(null, async (client) => {
      const { rows } = await client.query('select * from kiarys.autenticar($1, $2)', [email, senha]);
      return rows[0];
    });

    const token = assinarToken(perfil);
    res.json({
      token,
      perfil: {
        id: perfil.id,
        nome: perfil.nome,
        email: perfil.email,
        papel: perfil.papel,
      },
    });
  } catch (err) {
    const { status, erro } = erroParaHttp(err);
    res.status(status).json({ erro });
  }
});

authRouter.get('/me', requireAuth, async (req, res) => {
  try {
    const perfil = await comoUsuario(req.uid, async (client) => {
      const [{ rows: p }, { rows: custo }, { rows: cadastra }] = await Promise.all([
        client.query(
          'select id, nome, email, papel, ativo, comissao_pct, limite_desconto_pct from kiarys.perfis where id = $1',
          [req.uid]
        ),
        client.query('select kiarys.pode_ver_custo() as v'),
        client.query('select kiarys.pode_cadastrar() as v'),
      ]);
      return { ...p[0], pode_ver_custo: custo[0].v, pode_cadastrar: cadastra[0].v };
    });
    res.json(perfil);
  } catch (err) {
    const { status, erro } = erroParaHttp(err);
    res.status(status).json({ erro });
  }
});

authRouter.post('/trocar-senha', requireAuth, async (req, res) => {
  const { senha_atual, senha_nova } = req.body ?? {};
  if (!senha_atual || !senha_nova) {
    return res.status(400).json({ erro: 'senha_atual e senha_nova são obrigatórias' });
  }
  try {
    await comoUsuario(req.uid, (client) =>
      client.query('select kiarys.trocar_senha($1, $2)', [senha_atual, senha_nova])
    );
    res.status(204).end();
  } catch (err) {
    const { status, erro } = erroParaHttp(err);
    res.status(status).json({ erro });
  }
});
