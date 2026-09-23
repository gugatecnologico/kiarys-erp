import { useState, type FormEvent } from 'react';
import { api, ApiError, type VariacaoEstoque } from '../../lib/api';
import { VariacaoPicker } from './VariacaoPicker';

export function AdminPrecos() {
  const [variacao, setVariacao] = useState<VariacaoEstoque | null>(null);
  const [precoVenda, setPrecoVenda] = useState('');
  const [precoPromo, setPrecoPromo] = useState('');
  const [promoAte, setPromoAte] = useState('');
  const [erro, setErro] = useState<string | null>(null);
  const [ok, setOk] = useState<string | null>(null);
  const [salvando, setSalvando] = useState(false);

  function escolher(v: VariacaoEstoque) {
    setVariacao(v);
    setPrecoVenda(v.preco_venda);
    setPrecoPromo(v.preco_promocional ?? '');
    setPromoAte(v.promo_ate ? v.promo_ate.slice(0, 10) : '');
    setErro(null);
    setOk(null);
  }

  async function salvar(e: FormEvent) {
    e.preventDefault();
    if (!variacao) return;
    setErro(null);
    setOk(null);
    setSalvando(true);
    try {
      await api.alterarPrecos(
        variacao.variacao_id,
        Number(precoVenda),
        precoPromo ? Number(precoPromo) : null,
        promoAte || null
      );
      setOk('Preço atualizado.');
      setVariacao(null);
    } catch (err) {
      setErro(err instanceof ApiError ? err.message : 'não deu pra atualizar o preço');
    } finally {
      setSalvando(false);
    }
  }

  return (
    <div>
      <h1>Preços e promoção</h1>

      {!variacao && <VariacaoPicker onEscolher={escolher} />}

      {variacao && (
        <form onSubmit={salvar} className="card">
          <div className="list-item">
            <span>
              <strong>{variacao.nome}</strong>
              <br />
              <span className="muted">
                {variacao.referencia} · {variacao.tamanho} · {variacao.cor}
              </span>
            </span>
          </div>

          <div className="field" style={{ marginTop: 12 }}>
            <label htmlFor="precoVenda">Preço de venda</label>
            <input
              id="precoVenda"
              type="number"
              inputMode="decimal"
              step="0.01"
              min="0"
              value={precoVenda}
              onChange={(e) => setPrecoVenda(e.target.value)}
              required
            />
          </div>
          <div className="row">
            <div className="field">
              <label htmlFor="precoPromo">Preço promocional (opcional)</label>
              <input
                id="precoPromo"
                type="number"
                inputMode="decimal"
                step="0.01"
                min="0"
                value={precoPromo}
                onChange={(e) => setPrecoPromo(e.target.value)}
              />
            </div>
            <div className="field">
              <label htmlFor="promoAte">Promoção até</label>
              <input id="promoAte" type="date" value={promoAte} onChange={(e) => setPromoAte(e.target.value)} />
            </div>
          </div>

          {erro && <div className="alert error">{erro}</div>}
          {ok && <div className="alert success">{ok}</div>}

          <div className="row">
            <button type="button" className="btn secondary" onClick={() => setVariacao(null)}>
              trocar item
            </button>
            <button className="btn" type="submit" disabled={salvando}>
              {salvando ? 'Salvando…' : 'Salvar preço'}
            </button>
          </div>
        </form>
      )}
    </div>
  );
}
