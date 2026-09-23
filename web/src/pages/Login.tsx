import { useState, type FormEvent } from 'react';
import { useAuth } from '../context/AuthContext';
import { ApiError } from '../lib/api';

export function Login() {
  const { login } = useAuth();
  const [email, setEmail] = useState('');
  const [senha, setSenha] = useState('');
  const [erro, setErro] = useState<string | null>(null);
  const [enviando, setEnviando] = useState(false);

  async function onSubmit(e: FormEvent) {
    e.preventDefault();
    setErro(null);
    setEnviando(true);
    try {
      await login(email, senha);
    } catch (err) {
      setErro(err instanceof ApiError ? err.message : 'não deu pra entrar — tenta de novo');
    } finally {
      setEnviando(false);
    }
  }

  return (
    <div className="center" style={{ padding: 24 }}>
      <form onSubmit={onSubmit} style={{ width: '100%', maxWidth: 360 }}>
        <h1>Kiarys</h1>
        {erro && <div className="alert error">{erro}</div>}
        <div className="field">
          <label htmlFor="email">E-mail</label>
          <input
            id="email"
            type="email"
            autoComplete="username"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            required
          />
        </div>
        <div className="field">
          <label htmlFor="senha">Senha</label>
          <input
            id="senha"
            type="password"
            autoComplete="current-password"
            value={senha}
            onChange={(e) => setSenha(e.target.value)}
            required
          />
        </div>
        <button className="btn" type="submit" disabled={enviando}>
          {enviando ? 'Entrando…' : 'Entrar'}
        </button>
      </form>
    </div>
  );
}
