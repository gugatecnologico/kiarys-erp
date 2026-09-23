import { useState, type FormEvent } from 'react';
import { api, ApiError } from '../../lib/api';

export function AdminUsuarias() {
  const [nome, setNome] = useState('');
  const [email, setEmail] = useState('');
  const [senha, setSenha] = useState('');
  const [papel, setPapel] = useState<'vendedora' | 'gerente' | 'admin'>('vendedora');
  const [comissaoPct, setComissaoPct] = useState('0');
  const [limiteDesconto, setLimiteDesconto] = useState('');
  const [erro, setErro] = useState<string | null>(null);
  const [ok, setOk] = useState<string | null>(null);
  const [salvando, setSalvando] = useState(false);

  async function salvar(e: FormEvent) {
    e.preventDefault();
    setErro(null);
    setOk(null);
    setSalvando(true);
    try {
      await api.criarUsuaria({
        nome: nome.trim(),
        email: email.trim(),
        senha,
        papel,
        comissao_pct: Number(comissaoPct) || 0,
        limite_desconto_pct: limiteDesconto ? Number(limiteDesconto) : null,
      });
      setOk(`Login criado para ${nome}. Repasse o e-mail e a senha pra ela.`);
      setNome('');
      setEmail('');
      setSenha('');
      setPapel('vendedora');
      setComissaoPct('0');
      setLimiteDesconto('');
    } catch (err) {
      setErro(err instanceof ApiError ? err.message : 'não deu pra criar a usuária');
    } finally {
      setSalvando(false);
    }
  }

  return (
    <div>
      <h1>Nova usuária</h1>
      <div className="card">
        <p className="muted">
          O login usa e-mail — se a pessoa não tiver um e-mail próprio, use algo como
          nome@kiarabijous.com.br.
        </p>
      </div>
      <form onSubmit={salvar} className="card">
        <div className="field">
          <label htmlFor="nome">Nome</label>
          <input id="nome" value={nome} onChange={(e) => setNome(e.target.value)} required />
        </div>
        <div className="field">
          <label htmlFor="email">E-mail (login)</label>
          <input id="email" type="email" value={email} onChange={(e) => setEmail(e.target.value)} required />
        </div>
        <div className="field">
          <label htmlFor="senha">Senha</label>
          <input id="senha" value={senha} onChange={(e) => setSenha(e.target.value)} required minLength={6} />
        </div>
        <div className="field">
          <label htmlFor="papel">Papel</label>
          <select id="papel" value={papel} onChange={(e) => setPapel(e.target.value as typeof papel)}>
            <option value="vendedora">Vendedora</option>
            <option value="gerente">Gerente</option>
            <option value="admin">Admin (acesso total)</option>
          </select>
        </div>
        <div className="row">
          <div className="field">
            <label htmlFor="comissao">Comissão (%)</label>
            <input
              id="comissao"
              type="number"
              inputMode="decimal"
              step="0.01"
              min="0"
              value={comissaoPct}
              onChange={(e) => setComissaoPct(e.target.value)}
            />
          </div>
          <div className="field">
            <label htmlFor="limiteDesconto">Limite de desconto (%, opcional)</label>
            <input
              id="limiteDesconto"
              type="number"
              inputMode="decimal"
              step="0.01"
              min="0"
              value={limiteDesconto}
              onChange={(e) => setLimiteDesconto(e.target.value)}
            />
          </div>
        </div>

        {erro && <div className="alert error">{erro}</div>}
        {ok && <div className="alert success">{ok}</div>}

        <button className="btn" type="submit" disabled={salvando}>
          {salvando ? 'Criando…' : 'Criar login'}
        </button>
      </form>
    </div>
  );
}
