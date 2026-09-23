import { useState, type FormEvent } from 'react';
import { api, ApiError, type VariacaoEstoque } from '../../lib/api';
import { VariacaoPicker } from './VariacaoPicker';

type ItemEntrada = { variacao: VariacaoEstoque; quantidade: string; custo_unitario_nf: string };

export function AdminEntrada() {
  const [itens, setItens] = useState<ItemEntrada[]>([]);
  const [frete, setFrete] = useState('0');
  const [docRef, setDocRef] = useState('');
  const [erro, setErro] = useState<string | null>(null);
  const [ok, setOk] = useState<string | null>(null);
  const [salvando, setSalvando] = useState(false);

  function adicionar(v: VariacaoEstoque) {
    if (itens.some((i) => i.variacao.variacao_id === v.variacao_id)) return;
    setItens((prev) => [...prev, { variacao: v, quantidade: '1', custo_unitario_nf: '' }]);
  }

  function remover(id: string) {
    setItens((prev) => prev.filter((i) => i.variacao.variacao_id !== id));
  }

  function atualizar(id: string, campo: 'quantidade' | 'custo_unitario_nf', valor: string) {
    setItens((prev) => prev.map((i) => (i.variacao.variacao_id === id ? { ...i, [campo]: valor } : i)));
  }

  async function salvar(e: FormEvent) {
    e.preventDefault();
    setErro(null);
    setOk(null);
    if (itens.length === 0) {
      setErro('adicione pelo menos um item');
      return;
    }
    if (itens.some((i) => !i.quantidade || !i.custo_unitario_nf)) {
      setErro('preencha quantidade e custo de cada item');
      return;
    }
    setSalvando(true);
    try {
      await api.registrarEntrada({
        itens: itens.map((i) => ({
          variacao_id: i.variacao.variacao_id,
          quantidade: Number(i.quantidade),
          custo_unitario_nf: Number(i.custo_unitario_nf),
        })),
        frete: Number(frete) || 0,
        doc_ref: docRef.trim() || null,
      });
      setOk('Entrada registrada. Estoque e custo médio atualizados.');
      setItens([]);
      setFrete('0');
      setDocRef('');
    } catch (err) {
      setErro(err instanceof ApiError ? err.message : 'não deu pra registrar a entrada');
    } finally {
      setSalvando(false);
    }
  }

  return (
    <div>
      <h1>Entrada de mercadoria</h1>
      <p className="muted" style={{ marginTop: -10, marginBottom: 14 }}>
        Busque a variação, adicione à lista, informe quantidade e custo unitário da nota. O frete é rateado entre os
        itens pelo valor de cada um.
      </p>

      <VariacaoPicker onEscolher={adicionar} />

      {itens.length > 0 && (
        <form onSubmit={salvar} className="card">
          <h2>Itens da entrada</h2>
          {itens.map((i) => (
            <div key={i.variacao.variacao_id} style={{ marginBottom: 14, paddingBottom: 14, borderBottom: '1px solid var(--border)' }}>
              <div className="list-item" style={{ borderBottom: 'none', padding: '0 0 8px' }}>
                <span>
                  <strong>{i.variacao.nome}</strong>
                  <br />
                  <span className="muted">
                    {i.variacao.referencia} · {i.variacao.tamanho} · {i.variacao.cor}
                  </span>
                </span>
                <button type="button" className="btn secondary small" onClick={() => remover(i.variacao.variacao_id)}>
                  remover
                </button>
              </div>
              <div className="row">
                <div className="field">
                  <label>Quantidade</label>
                  <input
                    type="number"
                    inputMode="numeric"
                    min="1"
                    value={i.quantidade}
                    onChange={(e) => atualizar(i.variacao.variacao_id, 'quantidade', e.target.value)}
                  />
                </div>
                <div className="field">
                  <label>Custo unitário (nota)</label>
                  <input
                    type="number"
                    inputMode="decimal"
                    step="0.01"
                    min="0"
                    value={i.custo_unitario_nf}
                    onChange={(e) => atualizar(i.variacao.variacao_id, 'custo_unitario_nf', e.target.value)}
                  />
                </div>
              </div>
            </div>
          ))}

          <div className="row">
            <div className="field">
              <label htmlFor="frete">Frete (rateado)</label>
              <input id="frete" type="number" inputMode="decimal" step="0.01" min="0" value={frete} onChange={(e) => setFrete(e.target.value)} />
            </div>
            <div className="field">
              <label htmlFor="docRef">Nota / referência (opcional)</label>
              <input id="docRef" value={docRef} onChange={(e) => setDocRef(e.target.value)} />
            </div>
          </div>

          {erro && <div className="alert error">{erro}</div>}
          {ok && <div className="alert success">{ok}</div>}

          <button className="btn" type="submit" disabled={salvando}>
            {salvando ? 'Registrando…' : 'Registrar entrada'}
          </button>
        </form>
      )}
    </div>
  );
}
