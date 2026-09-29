import { useEffect, useMemo, useState, type FormEvent } from 'react';
import { api, ApiError, type VariacaoEstoque } from '../lib/api';
import { Miniatura } from '../components/Miniatura';

const moeda = (v: number | string) => Number(v).toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' });

export function Estoque() {
  const [busca, setBusca] = useState('');
  const [linhas, setLinhas] = useState<VariacaoEstoque[] | null>(null);
  const [carregando, setCarregando] = useState(false);
  const [erro, setErro] = useState<string | null>(null);
  const [soBaixo, setSoBaixo] = useState(false);

  useEffect(() => {
    carregar('');
  }, []);

  async function carregar(termo: string) {
    setCarregando(true);
    setErro(null);
    try {
      setLinhas(await api.estoque(termo));
    } catch (err) {
      setErro(err instanceof ApiError ? err.message : 'busca falhou');
    } finally {
      setCarregando(false);
    }
  }

  function buscar(e: FormEvent) {
    e.preventDefault();
    carregar(busca.trim());
  }

  const visiveis = useMemo(
    () => (soBaixo ? (linhas ?? []).filter((v) => v.saldo <= v.estoque_minimo) : linhas ?? []),
    [linhas, soBaixo]
  );

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

        <button
          type="button"
          className={`badge ${soBaixo ? 'low' : ''}`}
          style={{ border: 'none', cursor: 'pointer', marginTop: 10, padding: '6px 12px' }}
          onClick={() => setSoBaixo((v) => !v)}
        >
          {soBaixo ? '✓ ' : ''}só estoque baixo
        </button>
      </form>

      {linhas && visiveis.length === 0 && (
        <p className="muted">{soBaixo ? 'Nada com estoque baixo.' : 'Nada encontrado.'}</p>
      )}

      {visiveis.length > 0 && (
        <div className="card">
          {visiveis.map((v) => (
            <div className="list-item" key={v.variacao_id} style={{ gap: 10 }}>
              <span style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
                <Miniatura src={v.foto_url} alt={v.nome} />
                <span>
                  <strong>{v.nome}</strong>
                  <br />
                  <span className="muted">
                    {v.referencia} · {v.tamanho} · {v.cor}
                  </span>
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
