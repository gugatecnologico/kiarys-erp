import { useEffect, useState } from 'react';
import { api, type MinhaVenda } from '../lib/api';

const moeda = (v: number | string) => Number(v).toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' });
const dataHora = (iso: string) => new Date(iso).toLocaleString('pt-BR', { dateStyle: 'short', timeStyle: 'short' });

export function MinhasVendas() {
  const [vendas, setVendas] = useState<MinhaVenda[] | null>(null);

  useEffect(() => {
    api.minhasVendas().then(setVendas).catch(() => setVendas([]));
  }, []);

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

      <div className="card">
        {vendas.length === 0 && <p className="muted">Nenhuma venda ainda.</p>}
        {vendas.map((v) => (
          <div className="list-item" key={v.id}>
            <span>
              #{v.numero}
              <br />
              <span className="muted">{dataHora(v.criado_em)}</span>
            </span>
            <span>
              {v.status === 'CANCELADA' && <span className="badge low">cancelada</span>}{' '}
              <strong style={{ textDecoration: v.status === 'CANCELADA' ? 'line-through' : 'none' }}>
                {moeda(v.total)}
              </strong>
            </span>
          </div>
        ))}
      </div>
    </div>
  );
}
