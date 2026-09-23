import { useState, type FormEvent } from 'react';
import { api, ApiError, type VariacaoEstoque } from '../../lib/api';
import { VariacaoPicker } from './VariacaoPicker';

export function AdminAjuste() {
  const [variacao, setVariacao] = useState<VariacaoEstoque | null>(null);
  const [novaQtd, setNovaQtd] = useState('');
  const [motivo, setMotivo] = useState('');
  const [erro, setErro] = useState<string | null>(null);
  const [ok, setOk] = useState<string | null>(null);
  const [salvando, setSalvando] = useState(false);

  async function salvar(e: FormEvent) {
    e.preventDefault();
    if (!variacao) return;
    setErro(null);
    setOk(null);
    setSalvando(true);
    try {
      await api.ajustarEstoque(variacao.variacao_id, Number(novaQtd), motivo.trim());
      setOk(`Estoque de ${variacao.nome} (${variacao.tamanho} · ${variacao.cor}) ajustado para ${novaQtd} un.`);
      setVariacao(null);
      setNovaQtd('');
      setMotivo('');
    } catch (err) {
      setErro(err instanceof ApiError ? err.message : 'não deu pra ajustar');
    } finally {
      setSalvando(false);
    }
  }

  return (
    <div>
      <h1>Ajustar estoque</h1>
      <p className="muted" style={{ marginTop: -10, marginBottom: 14 }}>
        Pra corrigir contagem, perda ou quebra — informe a quantidade CERTA (não a diferença). Só admin faz isso.
      </p>

      {!variacao && <VariacaoPicker onEscolher={setVariacao} />}

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
            <span className="badge">{variacao.saldo} un. hoje</span>
          </div>

          <div className="field" style={{ marginTop: 12 }}>
            <label htmlFor="novaQtd">Quantidade certa (contada)</label>
            <input
              id="novaQtd"
              type="number"
              inputMode="numeric"
              min="0"
              value={novaQtd}
              onChange={(e) => setNovaQtd(e.target.value)}
              required
            />
          </div>
          <div className="field">
            <label htmlFor="motivo">Motivo</label>
            <input id="motivo" value={motivo} onChange={(e) => setMotivo(e.target.value)} required />
          </div>

          {erro && <div className="alert error">{erro}</div>}
          {ok && <div className="alert success">{ok}</div>}

          <div className="row">
            <button type="button" className="btn secondary" onClick={() => setVariacao(null)}>
              trocar item
            </button>
            <button className="btn" type="submit" disabled={salvando}>
              {salvando ? 'Salvando…' : 'Confirmar ajuste'}
            </button>
          </div>
        </form>
      )}
    </div>
  );
}
