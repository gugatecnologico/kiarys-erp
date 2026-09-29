import { lazy, Suspense, useEffect, useMemo, useRef, useState, type FormEvent } from 'react';
import {
  api,
  ApiError,
  type CaixaAberto,
  type Categoria,
  type Pagamento,
  type ProdutoBusca,
  type Venda,
  type VariacaoEstoque,
} from '../lib/api';
import { Miniatura } from '../components/Miniatura';

// lazy: a lib de leitura de código de barras é pesada (zxing) e só a
// vendedora que aperta 📷 precisa baixá-la.
const ScannerCodigoBarras = lazy(() =>
  import('../components/ScannerCodigoBarras').then((m) => ({ default: m.ScannerCodigoBarras }))
);

type ItemCarrinho = { variacao: VariacaoEstoque; quantidade: number };

const moeda = (v: number | string) => Number(v).toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' });

export function Vender() {
  const [caixa, setCaixa] = useState<CaixaAberto | null | undefined>(undefined); // undefined = carregando
  const [valorInicial, setValorInicial] = useState('');
  const [erroCaixa, setErroCaixa] = useState<string | null>(null);

  const [categorias, setCategorias] = useState<Categoria[]>([]);
  const [categoriaFiltro, setCategoriaFiltro] = useState<string | null>(null);

  const [busca, setBusca] = useState('');
  const [produtos, setProdutos] = useState<ProdutoBusca[] | null>(null);
  const [buscando, setBuscando] = useState(false);
  const [erroBusca, setErroBusca] = useState<string | null>(null);
  const [scanAberto, setScanAberto] = useState(false);

  const [produtoAberto, setProdutoAberto] = useState<string | null>(null);
  const [gradePorProduto, setGradePorProduto] = useState<Record<string, VariacaoEstoque[]>>({});
  const [carregandoGrade, setCarregandoGrade] = useState<string | null>(null);

  const [carrinho, setCarrinho] = useState<ItemCarrinho[]>([]);
  const [descontoGeral, setDescontoGeral] = useState('0');
  const [pagamentos, setPagamentos] = useState<Pagamento[]>([{ forma: 'PIX', valor: 0 }]);
  const [confirmando, setConfirmando] = useState(false);
  const [erroVenda, setErroVenda] = useState<string | null>(null);
  const [vendaFeita, setVendaFeita] = useState<Venda | null>(null);
  const [chaveIdempotencia, setChaveIdempotencia] = useState(() => crypto.randomUUID());

  useEffect(() => {
    carregarCaixa();
    carregarProdutos('');
    api.categorias().then(setCategorias).catch(() => {});
  }, []);

  // busca ao digitar (com debounce) — o botão "Buscar" continua existindo
  // pra quem prefere apertar, mas não é mais obrigatório. Pula a primeira
  // renderização: o mount já carregou o catálogo inicial na hora.
  const primeiraRenderBusca = useRef(true);
  useEffect(() => {
    if (primeiraRenderBusca.current) {
      primeiraRenderBusca.current = false;
      return;
    }
    const t = setTimeout(() => carregarProdutos(busca.trim()), 400);
    return () => clearTimeout(t);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [busca]);

  function carregarCaixa() {
    api
      .caixaAberto()
      .then((rows) => setCaixa(rows[0] ?? null))
      .catch(() => setCaixa(null));
  }

  async function carregarProdutos(termo: string) {
    setBuscando(true);
    setErroBusca(null);
    try {
      setProdutos(await api.buscarProdutos(termo));
    } catch (err) {
      setErroBusca(err instanceof ApiError ? err.message : 'busca falhou');
    } finally {
      setBuscando(false);
    }
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

  function buscar(e: FormEvent) {
    e.preventDefault();
    carregarProdutos(busca.trim());
  }

  function codigoLido(codigo: string) {
    setScanAberto(false);
    setBusca(codigo);
    carregarProdutos(codigo);
  }

  async function toggleProduto(p: ProdutoBusca) {
    if (produtoAberto === p.produto_id) {
      setProdutoAberto(null);
      return;
    }
    setProdutoAberto(p.produto_id);
    if (gradePorProduto[p.produto_id]) return;
    setCarregandoGrade(p.produto_id);
    try {
      const grade = await api.gradeDoProduto(p.referencia);
      setGradePorProduto((atual) => ({ ...atual, [p.produto_id]: grade }));
    } catch {
      // deixa a lista vazia — a vendedora tenta de novo fechando/abrindo
    } finally {
      setCarregandoGrade(null);
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

  function removerDoCarrinho(variacaoId: string) {
    setCarrinho((atual) => atual.filter((i) => i.variacao.variacao_id !== variacaoId));
  }

  const produtosFiltrados = useMemo(
    () => (categoriaFiltro ? (produtos ?? []).filter((p) => p.categoria_id === categoriaFiltro) : produtos ?? []),
    [produtos, categoriaFiltro]
  );

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
    setProdutoAberto(null);
    carregarProdutos('');
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
          <button
            type="button"
            className="btn secondary small"
            style={{ flex: '0 0 auto' }}
            onClick={() => setScanAberto(true)}
            aria-label="escanear código de barras"
          >
            📷
          </button>
          <button className="btn small" type="submit" disabled={buscando} style={{ flex: '0 0 auto' }}>
            {buscando ? '…' : 'Buscar'}
          </button>
        </div>
        {erroBusca && <div className="alert error">{erroBusca}</div>}

        {scanAberto && (
          <Suspense fallback={null}>
            <ScannerCodigoBarras onLido={codigoLido} onFechar={() => setScanAberto(false)} />
          </Suspense>
        )}

        {categorias.length > 0 && (
          <div style={{ display: 'flex', gap: 6, overflowX: 'auto', marginTop: 10, paddingBottom: 2 }}>
            <button
              type="button"
              className={`badge ${categoriaFiltro === null ? 'ok' : ''}`}
              style={{ border: 'none', cursor: 'pointer', flexShrink: 0, padding: '6px 12px' }}
              onClick={() => setCategoriaFiltro(null)}
            >
              Todas
            </button>
            {categorias.map((c) => (
              <button
                key={c.id}
                type="button"
                className={`badge ${categoriaFiltro === c.id ? 'ok' : ''}`}
                style={{ border: 'none', cursor: 'pointer', flexShrink: 0, padding: '6px 12px' }}
                onClick={() => setCategoriaFiltro(categoriaFiltro === c.id ? null : c.id)}
              >
                {c.nome}
              </button>
            ))}
          </div>
        )}
      </form>

      {produtos && produtosFiltrados.length === 0 && <p className="muted">Nada encontrado.</p>}

      {produtosFiltrados.map((p) => (
        <div className="card" key={p.produto_id}>
          <button className="list-item" onClick={() => toggleProduto(p)} style={{ gap: 10 }}>
            <span style={{ display: 'flex', alignItems: 'center', gap: 10, textAlign: 'left' }}>
              <Miniatura src={p.foto_url} alt={p.nome} />
              <span>
                <strong>{p.nome}</strong>
                <br />
                <span className="muted">
                  {p.referencia} · {p.preco_min === p.preco_max ? moeda(p.preco_min) : `${moeda(p.preco_min)} – ${moeda(p.preco_max)}`}
                </span>
              </span>
            </span>
            <span className={`badge ${p.saldo_total <= 0 ? 'low' : 'ok'}`}>
              {produtoAberto === p.produto_id ? '▲' : `${p.saldo_total} un. ▼`}
            </span>
          </button>
          {produtoAberto === p.produto_id && (
            <div style={{ marginTop: 8 }}>
              {carregandoGrade === p.produto_id && <p className="muted">carregando…</p>}
              {gradePorProduto[p.produto_id]?.map((v) => (
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
            <div key={i.variacao.variacao_id} className="list-item" style={{ gap: 10 }}>
              <span style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
                <Miniatura src={i.variacao.foto_url} alt={i.variacao.nome} tamanho={36} />
                <span>
                  {i.variacao.nome}
                  <br />
                  <span className="muted">
                    {i.variacao.tamanho} · {i.variacao.cor} · {moeda(i.variacao.preco_efetivo)}
                  </span>
                </span>
              </span>
              <span className="row" style={{ maxWidth: 150, alignItems: 'center' }}>
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
                <button
                  className="btn secondary small"
                  type="button"
                  onClick={() => removerDoCarrinho(i.variacao.variacao_id)}
                  aria-label="remover"
                >
                  ×
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
