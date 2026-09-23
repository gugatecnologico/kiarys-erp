import { useEffect, useState, type FormEvent } from 'react';
import { api, ApiError, type CaixaAberto } from '../lib/api';

const moeda = (v: number | string) => Number(v).toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' });

export function MeuCaixa() {
  const [caixa, setCaixa] = useState<CaixaAberto | null | undefined>(undefined);
  const [tipo, setTipo] = useState<'SANGRIA' | 'SUPRIMENTO'>('SANGRIA');
  const [valor, setValor] = useState('');
  const [motivo, setMotivo] = useState('');
  const [erro, setErro] = useState<string | null>(null);
  const [ok, setOk] = useState<string | null>(null);

  const [valorContado, setValorContado] = useState('');
  const [fechando, setFechando] = useState(false);
  const [resultadoFechamento, setResultadoFechamento] = useState<{
    valor_contado: string;
    valor_esperado: string;
    diferenca: string;
  } | null>(null);

  useEffect(() => {
    carregar();
  }, []);

  function carregar() {
    api
      .caixaAberto()
      .then((rows) => setCaixa(rows[0] ?? null))
      .catch(() => setCaixa(null));
  }

  async function movimentar(e: FormEvent) {
    e.preventDefault();
    setErro(null);
    setOk(null);
    try {
      await api.movimentarCaixa(tipo, Number(valor), motivo);
      setOk(`${tipo === 'SANGRIA' ? 'Sangria' : 'Suprimento'} de ${moeda(Number(valor))} registrada.`);
      setValor('');
      setMotivo('');
    } catch (err) {
      setErro(err instanceof ApiError ? err.message : 'não deu pra registrar');
    }
  }

  async function fechar(e: FormEvent) {
    e.preventDefault();
    setErro(null);
    setFechando(true);
    try {
      const r = (await api.fecharCaixa(Number(valorContado))) as {
        valor_contado: string;
        valor_esperado: string;
        diferenca: string;
      };
      setResultadoFechamento(r);
    } catch (err) {
      setErro(err instanceof ApiError ? err.message : 'não deu pra fechar o caixa');
    } finally {
      setFechando(false);
    }
  }

  if (caixa === undefined) return <p className="muted">carregando…</p>;

  if (resultadoFechamento) {
    const diferenca = Number(resultadoFechamento.diferenca);
    return (
      <div className="card">
        <h2>Caixa fechado</h2>
        <div className="list-item">
          <span className="muted">Contado</span>
          <span>{moeda(resultadoFechamento.valor_contado)}</span>
        </div>
        <div className="list-item">
          <span className="muted">Esperado</span>
          <span>{moeda(resultadoFechamento.valor_esperado)}</span>
        </div>
        <div className="list-item">
          <strong>Diferença</strong>
          <strong style={{ color: diferenca === 0 ? 'var(--success)' : 'var(--danger)' }}>
            {moeda(diferenca)}
          </strong>
        </div>
        <button
          className="btn"
          style={{ marginTop: 12 }}
          onClick={() => {
            setResultadoFechamento(null);
            setValorContado('');
            carregar();
          }}
        >
          Ok
        </button>
      </div>
    );
  }

  if (caixa === null) {
    return (
      <div className="card">
        <p className="muted">Nenhum caixa aberto no momento.</p>
      </div>
    );
  }

  return (
    <div>
      <div className="card">
        <h2>Caixa aberto</h2>
        <div className="list-item">
          <span className="muted">Aberto por</span>
          <span>{caixa.aberto_por_nome}</span>
        </div>
        <div className="list-item">
          <span className="muted">Valor inicial</span>
          <span>{moeda(caixa.valor_inicial)}</span>
        </div>
      </div>

      <div className="card">
        <h2>Sangria / suprimento</h2>
        {erro && <div className="alert error">{erro}</div>}
        {ok && <div className="alert success">{ok}</div>}
        <form onSubmit={movimentar}>
          <div className="field">
            <label htmlFor="tipo">Tipo</label>
            <select id="tipo" value={tipo} onChange={(e) => setTipo(e.target.value as 'SANGRIA' | 'SUPRIMENTO')}>
              <option value="SANGRIA">Sangria (retirar)</option>
              <option value="SUPRIMENTO">Suprimento (colocar)</option>
            </select>
          </div>
          <div className="field">
            <label htmlFor="valorMov">Valor</label>
            <input
              id="valorMov"
              type="number"
              inputMode="decimal"
              step="0.01"
              min="0.01"
              value={valor}
              onChange={(e) => setValor(e.target.value)}
              required
            />
          </div>
          <div className="field">
            <label htmlFor="motivo">Motivo</label>
            <input id="motivo" value={motivo} onChange={(e) => setMotivo(e.target.value)} required />
          </div>
          <button className="btn secondary" type="submit">
            Registrar
          </button>
        </form>
      </div>

      <div className="card">
        <h2>Fechar caixa</h2>
        <p className="muted">Conte o dinheiro antes de ver o esperado.</p>
        <form onSubmit={fechar}>
          <div className="field">
            <label htmlFor="valorContado">Valor contado</label>
            <input
              id="valorContado"
              type="number"
              inputMode="decimal"
              step="0.01"
              min="0"
              value={valorContado}
              onChange={(e) => setValorContado(e.target.value)}
              required
            />
          </div>
          <button className="btn danger" type="submit" disabled={fechando}>
            {fechando ? 'Fechando…' : 'Fechar caixa'}
          </button>
        </form>
      </div>
    </div>
  );
}
