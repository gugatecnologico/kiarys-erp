// auth.js
// Emissão/verificação do JWT de sessão. O banco não sabe o que é um JWT
// (kiarys.autenticar só devolve o perfil) — é aqui que a sessão vira token.

import jwt from 'jsonwebtoken';

const SECRET = process.env.JWT_SECRET;
if (!SECRET) {
  throw new Error('JWT_SECRET não definida — obrigatória, sem fallback (ver README)');
}

const EXPIRA_EM = '12h'; // turno de loja física — reloga no dia seguinte

export function assinarToken(perfil) {
  return jwt.sign({ sub: perfil.id, papel: perfil.papel, nome: perfil.nome }, SECRET, {
    expiresIn: EXPIRA_EM,
  });
}

export function requireAuth(req, res, next) {
  const header = req.headers.authorization ?? '';
  const token = header.startsWith('Bearer ') ? header.slice(7) : null;

  if (!token) {
    return res.status(401).json({ erro: 'não autenticado' });
  }

  try {
    const payload = jwt.verify(token, SECRET);
    req.uid = payload.sub;
    req.papel = payload.papel;
    next();
  } catch {
    res.status(401).json({ erro: 'sessão inválida ou expirada' });
  }
}

// Mapeia exceções do Postgres (levantadas pelas RPCs com `errcode`) pro
// status HTTP certo, em vez de tudo virar 500. Ver os errcodes usados nas
// migrations 0002/0010/0011/0012 (28000/28P01 = auth, 42501 = permissão,
// 22023 = validação, 23514/23505 = conflito de dado, 55000 = estado
// inválido tipo "sem caixa aberto").
export function erroParaHttp(err) {
  const codigo = err.code;
  if (codigo === '28000' || codigo === '28P01') return { status: 401, erro: err.message };
  if (codigo === '42501') return { status: 403, erro: err.message };
  if (codigo === '22023' || codigo === '23514') return { status: 400, erro: err.message };
  if (codigo === '23505') return { status: 409, erro: err.message };
  if (codigo === '55000') return { status: 409, erro: err.message };
  console.error('🔴 erro não mapeado:', err);
  return { status: 500, erro: 'erro interno' };
}
