import { useEffect, useState } from 'react';
import { api, ApiError, type MinhaVenda } from '../lib/api';
import { useAuth } from '../context/AuthContext';

const moeda = (v: number | string) => Number(v).toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' });
const dataHora = (iso: string) => new Date(iso).toLocaleString('pt-BR', { dateStyle: 'short', timeStyle: 'short' });

export function MinhasVendas() {
  const { perfil } = useAuth();
  const [vendas, setVendas] = useState<MinhaVenda[] | null>(null);
  const [cancelandoId, setCancelandoId] = useState<string | null>(null);
  const [erro, setErro] = useState<string | null>(null);

  const podeCancelar = perfil?.papel === 'admin' || perfil?.papel === 'gerente';

  useEffect(() => {
    carregar();
  }, []);

  function carregar() {
    api.minhasVendas().then(setVendas).catch(() => setVendas([]));
  }

  async function cancelar(id: string) {
    const motivo = window.prompt('Motivo do cancelamento:');
    if (!motivo) return;
    setErro(null);
    setCancelandoId(id);
    try {
      await api.cancelarVenda(id, motivo);
      carregar();
    } catch (err) {
      setErro(err instanceof ApiError ? err.message : 'não deu pra cancelar');
    } finally {
      setCancelandoId(null);
    }
  }

  if (!vendas) return <p className="muted">carregando…</p>;

  const totalPago = vendas.filter((v) => v.status === 'PAGA').reduce((s, v) => s + Number(v.total), 0);
  const comissaoTotal = vendas.filter((v) => v.status === 'PAGA').reduce((s, v) => s + Number(v.comissao), 0);

  return (
    <div>
      <div className="card">
        <h2>Minhas vendas</h2>
        <div className="list-item">
          <span className="muted">Total vendido</span>
          <span>{moeda(totalPago)}</span>
        </div>
        <div className="list-item">
          <span className="muted">Comissão</span>
          <span>{moeda(comissaoTotal)}</span>
        </div>
      </div>

      {erro && <div className="alert error">{erro}</div>}

      <div className="card">
        {vendas.length === 0 && <p className="muted">Nenhuma venda ainda.</p>}
        {vendas.map((v) => (
          <div className="list-item" key={v.id}>
            <span>
              #{v.numero}
              <br />
              <span className="muted">{dataHora(v.criado_em)}</span>
            </span>
            <span style={{ textAlign: 'right' }}>
              {v.status === 'CANCELADA' && <span className="badge low">cancelada</span>}{' '}
              <strong style={{ textDecoration: v.status === 'CANCELADA' ? 'line-through' : 'none' }}>
                {moeda(v.total)}
              </strong>
              {podeCancelar && v.status === 'PAGA' && (
                <>
                  <br />
                  <button
                    type="button"
                    className="btn secondary small"
                    style={{ marginTop: 6 }}
                    disabled={cancelandoId === v.id}
                    onClick={() => cancelar(v.id)}
                  >
                    {cancelandoId === v.id ? 'cancelando…' : 'cancelar'}
                  </button>
                </>
              )}
            </span>
          </div>
        ))}
      </div>
    </div>
  );
}
