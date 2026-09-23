import { useEffect, useMemo, useState, type FormEvent } from 'react';
import { api, ApiError, type CaixaAberto, type Pagamento, type Venda, type VariacaoEstoque } from '../lib/api';

type ItemCarrinho = { variacao: VariacaoEstoque; quantidade: number };

type ProdutoAgrupado = {
  produto_id: string;
  referencia: string;
  nome: string;
  foto_url: string | null;
  variacoes: VariacaoEstoque[];
};

function agruparPorProduto(linhas: VariacaoEstoque[]): ProdutoAgrupado[] {
  const mapa = new Map<string, ProdutoAgrupado>();
  for (const v of linhas) {
    const atual = mapa.get(v.produto_id);
    if (atual) atual.variacoes.push(v);
    else mapa.set(v.produto_id, { produto_id: v.produto_id, referencia: v.referencia, nome: v.nome, foto_url: v.foto_url, variacoes: [v] });
  }
  return [...mapa.values()];
}

const moeda = (v: number | string) => Number(v).toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' });

export function Vender() {
  const [caixa, setCaixa] = useState<CaixaAberto | null | undefined>(undefined); // undefined = carregando
  const [valorInicial, setValorInicial] = useState('');
  const [erroCaixa, setErroCaixa] = useState<string | null>(null);

  const [busca, setBusca] = useState('');
  const [resultados, setResultados] = useState<ProdutoAgrupado[] | null>(null);
  const [produtoAberto, setProdutoAberto] = useState<string | null>(null);
  const [buscando, setBuscando] = useState(false);
  const [erroBusca, setErroBusca] = useState<string | null>(null);

  const [carrinho, setCarrinho] = useState<ItemCarrinho[]>([]);
  const [descontoGeral, setDescontoGeral] = useState('0');
  const [pagamentos, setPagamentos] = useState<Pagamento[]>([{ forma: 'PIX', valor: 0 }]);
  const [confirmando, setConfirmando] = useState(false);
  const [erroVenda, setErroVenda] = useState<string | null>(null);
  const [vendaFeita, setVendaFeita] = useState<Venda | null>(null);
  const [chaveIdempotencia, setChaveIdempotencia] = useState(() => crypto.randomUUID());

  useEffect(() => {
    carregarCaixa();
  }, []);

  function carregarCaixa() {
    api
      .caixaAberto()
      .then((rows) => setCaixa(rows[0] ?? null))
      .catch(() => setCaixa(null));
  }

  async function abrirCaixa(e: FormEvent) {
    e.preventDefault();
    setErroCaixa(null);
    try {
      const c = await api.abrirCaixa(Number(valorInicial));
      setCaixa(c);
    } catch (err) {
      setErroCaixa(err instanceof ApiError ? err.message : 'não deu pra abrir o caixa');
    }
  }

  async function buscar(e: FormEvent) {
    e.preventDefault();
    if (busca.trim().length < 2) return;
    setBuscando(true);
    setErroBusca(null);
    try {
      const linhas = await api.estoque(busca.trim());
      const agrupado = agruparPorProduto(linhas);
      setResultados(agrupado);
      setProdutoAberto(agrupado.length === 1 ? agrupado[0].produto_id : null);
    } catch (err) {
      setErroBusca(err instanceof ApiError ? err.message : 'busca falhou');
    } finally {
      setBuscando(false);
    }
  }

  function adicionarAoCarrinho(v: VariacaoEstoque) {
    if (v.saldo <= 0) return;
    setCarrinho((atual) => {
      const idx = atual.findIndex((i) => i.variacao.variacao_id === v.variacao_id);
      if (idx >= 0) {
        const copia = [...atual];
        copia[idx] = { ...copia[idx], quantidade: copia[idx].quantidade + 1 };
        return copia;
      }
      return [...atual, { variacao: v, quantidade: 1 }];
    });
  }

  function alterarQuantidade(variacaoId: string, delta: number) {
    setCarrinho((atual) =>
      atual
        .map((i) => (i.variacao.variacao_id === variacaoId ? { ...i, quantidade: i.quantidade + delta } : i))
        .filter((i) => i.quantidade > 0)
    );
  }

  const subtotal = useMemo(
    () => carrinho.reduce((soma, i) => soma + Number(i.variacao.preco_efetivo) * i.quantidade, 0),
    [carrinho]
  );
  const desconto = Number(descontoGeral) || 0;
  const total = Math.max(0, subtotal - desconto);
  const somaPagamentos = pagamentos.reduce((s, p) => s + (Number(p.valor) || 0), 0);
  const pagamentoBate = Math.abs(somaPagamentos - total) < 0.01;

  function ajustarPagamentoUnico(valor: number) {
    setPagamentos((atual) => (atual.length === 1 ? [{ ...atual[0], valor }] : atual));
  }

  // mantém o único pagamento sincronizado com o total, até a vendedora
  // decidir dividir (nesse ponto ela ajusta cada um na mão).
  useEffect(() => {
    if (pagamentos.length === 1) ajustarPagamentoUnico(Number(total.toFixed(2)));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [total]);

  function adicionarPagamento() {
    setPagamentos((atual) => [...atual, { forma: 'DINHEIRO', valor: 0 }]);
  }

  function removerPagamento(idx: number) {
    setPagamentos((atual) => atual.filter((_, i) => i !== idx));
  }

  async function confirmarVenda() {
    setErroVenda(null);
    setConfirmando(true);
    try {
      const venda = await api.registrarVenda({
        itens: carrinho.map((i) => ({ variacao_id: i.variacao.variacao_id, quantidade: i.quantidade })),
        pagamentos: pagamentos.map((p) => ({ ...p, valor: Number(p.valor) })),
        chave_idempotencia: chaveIdempotencia,
        desconto_geral: desconto,
      });
      setVendaFeita(venda);
    } catch (err) {
      setErroVenda(err instanceof ApiError ? err.message : 'não deu pra registrar a venda');
    } finally {
      setConfirmando(false);
    }
  }

  function novaVenda() {
    setCarrinho([]);
    setDescontoGeral('0');
    setPagamentos([{ forma: 'PIX', valor: 0 }]);
    setVendaFeita(null);
    setErroVenda(null);
    setChaveIdempotencia(crypto.randomUUID());
    setBusca('');
    setResultados(null);
  }

  if (caixa === undefined) {
    return <p className="muted">carregando…</p>;
  }

  if (caixa === null) {
    return (
      <div className="card">
        <h2>Abrir o caixa</h2>
        <p className="muted">Precisa abrir o caixa da loja antes de vender.</p>
        {erroCaixa && <div className="alert error">{erroCaixa}</div>}
        <form onSubmit={abrirCaixa}>
          <div className="field">
            <label htmlFor="valorInicial">Valor inicial (troco)</label>
            <input
              id="valorInicial"
              type="number"
              inputMode="decimal"
              step="0.01"
              min="0"
              value={valorInicial}
              onChange={(e) => setValorInicial(e.target.value)}
              required
            />
          </div>
          <button className="btn" type="submit">
            Abrir caixa
          </button>
        </form>
      </div>
    );
  }

  if (vendaFeita) {
    return (
      <div className="card">
        <div className="alert success">Venda #{vendaFeita.numero} registrada!</div>
        <p style={{ fontSize: 28, fontWeight: 700, margin: '8px 0' }}>{moeda(vendaFeita.total)}</p>
        <button className="btn" onClick={novaVenda}>
          Nova venda
        </button>
      </div>
    );
  }

  return (
    <div>
      <form onSubmit={buscar} className="card">
        <h2>Vender</h2>
        <div className="row">
          <input
            placeholder="Nome, referência ou código de barras"
            value={busca}
            onChange={(e) => setBusca(e.target.value)}
            autoFocus
          />
          <button className="btn small" type="submit" disabled={buscando} style={{ flex: '0 0 auto' }}>
            {buscando ? '…' : 'Buscar'}
          </button>
        </div>
        {erroBusca && <div className="alert error">{erroBusca}</div>}
      </form>

      {resultados && resultados.length === 0 && <p className="muted">Nada encontrado.</p>}

      {resultados?.map((p) => (
        <div className="card" key={p.produto_id}>
          <button
            className="list-item"
            onClick={() => setProdutoAberto(produtoAberto === p.produto_id ? null : p.produto_id)}
          >
            <span>
              <strong>{p.nome}</strong>
              <br />
              <span className="muted">{p.referencia}</span>
            </span>
            <span className="muted">{produtoAberto === p.produto_id ? '▲' : '▼'}</span>
          </button>
          {produtoAberto === p.produto_id && (
            <div style={{ marginTop: 8 }}>
              {p.variacoes.map((v) => (
                <button
                  key={v.variacao_id}
                  className="list-item"
                  disabled={v.saldo <= 0}
                  onClick={() => adicionarAoCarrinho(v)}
                >
                  <span>
                    {v.tamanho} · {v.cor}
                    {v.preco_promocional && <span className="badge ok" style={{ marginLeft: 6 }}>promo</span>}
                  </span>
                  <span>
                    <span className={`badge ${v.saldo <= 0 ? 'low' : v.saldo <= v.estoque_minimo ? 'low' : 'ok'}`}>
                      {v.saldo <= 0 ? 'sem estoque' : `${v.saldo} un.`}
                    </span>{' '}
                    {moeda(v.preco_efetivo)}
                  </span>
                </button>
              ))}
            </div>
          )}
        </div>
      ))}

      {carrinho.length > 0 && (
        <div className="card">
          <h2>Carrinho</h2>
          {carrinho.map((i) => (
            <div key={i.variacao.variacao_id} className="list-item">
              <span>
                {i.variacao.nome}
                <br />
                <span className="muted">
                  {i.variacao.tamanho} · {i.variacao.cor} · {moeda(i.variacao.preco_efetivo)}
                </span>
              </span>
              <span className="row" style={{ maxWidth: 120, alignItems: 'center' }}>
                <button
                  className="btn secondary small"
                  type="button"
                  onClick={() => alterarQuantidade(i.variacao.variacao_id, -1)}
                >
                  −
                </button>
                <span style={{ minWidth: 20, textAlign: 'center' }}>{i.quantidade}</span>
                <button
                  className="btn secondary small"
                  type="button"
                  onClick={() => alterarQuantidade(i.variacao.variacao_id, 1)}
                  disabled={i.quantidade >= i.variacao.saldo}
                >
                  +
                </button>
              </span>
            </div>
          ))}

          <div className="field" style={{ marginTop: 12 }}>
            <label htmlFor="desconto">Desconto (R$)</label>
            <input
              id="desconto"
              type="number"
              inputMode="decimal"
              step="0.01"
              min="0"
              value={descontoGeral}
              onChange={(e) => setDescontoGeral(e.target.value)}
            />
          </div>

          <div className="list-item">
            <span className="muted">Subtotal</span>
            <span>{moeda(subtotal)}</span>
          </div>
          <div className="list-item">
            <strong>Total</strong>
            <strong>{moeda(total)}</strong>
          </div>

          <h2 style={{ marginTop: 16 }}>Pagamento</h2>
          {pagamentos.map((p, idx) => (
            <div className="row" key={idx} style={{ marginBottom: 8, alignItems: 'center' }}>
              <select
                value={p.forma}
                onChange={(e) =>
                  setPagamentos((atual) =>
                    atual.map((x, i) => (i === idx ? { ...x, forma: e.target.value as Pagamento['forma'] } : x))
                  )
                }
              >
                <option value="PIX">Pix</option>
                <option value="DEBITO">Débito</option>
                <option value="CREDITO">Crédito</option>
                <option value="DINHEIRO">Dinheiro</option>
              </select>
              <input
                type="number"
                inputMode="decimal"
                step="0.01"
                min="0"
                value={p.valor}
                onChange={(e) =>
                  setPagamentos((atual) =>
                    atual.map((x, i) => (i === idx ? { ...x, valor: Number(e.target.value) } : x))
                  )
                }
              />
              {pagamentos.length > 1 && (
                <button className="btn danger small" type="button" onClick={() => removerPagamento(idx)}>
                  ×
                </button>
              )}
            </div>
          ))}
          <button className="btn secondary small" type="button" onClick={adicionarPagamento}>
            + dividir pagamento
          </button>

          {!pagamentoBate && (
            <div className="alert error" style={{ marginTop: 12 }}>
              Os pagamentos ({moeda(somaPagamentos)}) precisam somar o total ({moeda(total)}).
            </div>
          )}
          {erroVenda && <div className="alert error">{erroVenda}</div>}

          <button
            className="btn"
            style={{ marginTop: 12 }}
            disabled={!pagamentoBate || confirmando || carrinho.length === 0}
            onClick={confirmarVenda}
          >
            {confirmando ? 'Confirmando…' : `Confirmar venda — ${moeda(total)}`}
          </button>
        </div>
      )}
    </div>
  );
}
