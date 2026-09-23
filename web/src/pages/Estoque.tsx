import { useState, type FormEvent } from 'react';
import { api, ApiError, type VariacaoEstoque } from '../lib/api';

const moeda = (v: number | string) => Number(v).toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' });

export function Estoque() {
  const [busca, setBusca] = useState('');
  const [linhas, setLinhas] = useState<VariacaoEstoque[] | null>(null);
  const [carregando, setCarregando] = useState(false);
  const [erro, setErro] = useState<string | null>(null);

  async function buscar(e: FormEvent) {
    e.preventDefault();
    setCarregando(true);
    setErro(null);
    try {
      setLinhas(await api.estoque(busca.trim()));
    } catch (err) {
      setErro(err instanceof ApiError ? err.message : 'busca falhou');
    } finally {
      setCarregando(false);
    }
  }

  return (
    <div>
      <form onSubmit={buscar} className="card">
        <h2>Estoque</h2>
        <div className="row">
          <input
            placeholder="Nome, referência ou código de barras"
            value={busca}
            onChange={(e) => setBusca(e.target.value)}
          />
          <button className="btn small" type="submit" disabled={carregando} style={{ flex: '0 0 auto' }}>
            {carregando ? '…' : 'Buscar'}
          </button>
        </div>
        {erro && <div className="alert error">{erro}</div>}
      </form>

      {linhas?.length === 0 && <p className="muted">Nada encontrado.</p>}

      {linhas && linhas.length > 0 && (
        <div className="card">
          {linhas.map((v) => (
            <div className="list-item" key={v.variacao_id}>
              <span>
                <strong>{v.nome}</strong>
                <br />
                <span className="muted">
                  {v.referencia} · {v.tamanho} · {v.cor}
                </span>
              </span>
              <span>
                <span className={`badge ${v.saldo <= v.estoque_minimo ? 'low' : 'ok'}`}>{v.saldo} un.</span>{' '}
                {moeda(v.preco_efetivo)}
              </span>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
