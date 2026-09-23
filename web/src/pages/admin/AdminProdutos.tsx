import { useEffect, useState, type FormEvent } from 'react';
import { api, ApiError, type Categoria, type Colecao, type Fornecedor } from '../../lib/api';

export function AdminProdutos() {
  const [categorias, setCategorias] = useState<Categoria[]>([]);
  const [colecoes, setColecoes] = useState<Colecao[]>([]);
  const [fornecedores, setFornecedores] = useState<Fornecedor[]>([]);

  const [referencia, setReferencia] = useState('');
  const [nome, setNome] = useState('');
  const [categoriaId, setCategoriaId] = useState('');
  const [colecaoId, setColecaoId] = useState('');
  const [fornecedorId, setFornecedorId] = useState('');
  const [precoVenda, setPrecoVenda] = useState('');
  const [tamanhos, setTamanhos] = useState('');
  const [cores, setCores] = useState('');
  const [fotoUrl, setFotoUrl] = useState('');

  const [novaCategoria, setNovaCategoria] = useState('');
  const [novaColecao, setNovaColecao] = useState('');
  const [novoFornecedor, setNovoFornecedor] = useState('');

  const [erro, setErro] = useState<string | null>(null);
  const [ok, setOk] = useState<string | null>(null);
  const [salvando, setSalvando] = useState(false);

  useEffect(() => {
    recarregarCadastros();
  }, []);

  function recarregarCadastros() {
    api.categorias().then(setCategorias).catch(() => {});
    api.colecoes().then(setColecoes).catch(() => {});
    api.fornecedores().then(setFornecedores).catch(() => {});
  }

  async function adicionarCategoria() {
    if (!novaCategoria.trim()) return;
    try {
      const c = await api.criarCategoria(novaCategoria.trim());
      setNovaCategoria('');
      setCategorias((prev) => [...prev, c]);
      setCategoriaId(c.id);
    } catch (err) {
      setErro(err instanceof ApiError ? err.message : 'não deu pra criar a categoria');
    }
  }

  async function adicionarColecao() {
    if (!novaColecao.trim()) return;
    try {
      const c = await api.criarColecao(novaColecao.trim());
      setNovaColecao('');
      setColecoes((prev) => [...prev, c]);
      setColecaoId(c.id);
    } catch (err) {
      setErro(err instanceof ApiError ? err.message : 'não deu pra criar a coleção');
    }
  }

  async function adicionarFornecedor() {
    if (!novoFornecedor.trim()) return;
    try {
      const f = await api.criarFornecedor(novoFornecedor.trim());
      setNovoFornecedor('');
      setFornecedores((prev) => [...prev, f]);
      setFornecedorId(f.id);
    } catch (err) {
      setErro(err instanceof ApiError ? err.message : 'não deu pra criar o fornecedor');
    }
  }

  async function salvar(e: FormEvent) {
    e.preventDefault();
    setErro(null);
    setOk(null);
    const listaTamanhos = tamanhos.split(',').map((s) => s.trim()).filter(Boolean);
    const listaCores = cores.split(',').map((s) => s.trim()).filter(Boolean);
    if (listaTamanhos.length === 0 || listaCores.length === 0) {
      setErro('informe ao menos um tamanho e uma cor, separados por vírgula');
      return;
    }
    setSalvando(true);
    try {
      await api.criarProduto({
        referencia: referencia.trim(),
        nome: nome.trim(),
        categoria_id: categoriaId || null,
        colecao_id: colecaoId || null,
        fornecedor_id: fornecedorId || null,
        preco_venda: Number(precoVenda),
        tamanhos: listaTamanhos,
        cores: listaCores,
        foto_url: fotoUrl.trim() || null,
      });
      setOk(`Produto "${nome}" cadastrado com ${listaTamanhos.length * listaCores.length} variações.`);
      setReferencia('');
      setNome('');
      setPrecoVenda('');
      setTamanhos('');
      setCores('');
      setFotoUrl('');
    } catch (err) {
      setErro(err instanceof ApiError ? err.message : 'não deu pra cadastrar');
    } finally {
      setSalvando(false);
    }
  }

  return (
    <div>
      <h1>Cadastrar produto</h1>
      <div className="card">
        {erro && <div className="alert error">{erro}</div>}
        {ok && <div className="alert success">{ok}</div>}
        <form onSubmit={salvar}>
          <div className="row">
            <div className="field">
              <label htmlFor="referencia">Referência</label>
              <input id="referencia" value={referencia} onChange={(e) => setReferencia(e.target.value)} required />
            </div>
            <div className="field">
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
          </div>

          <div className="field">
            <label htmlFor="nome">Nome</label>
            <input id="nome" value={nome} onChange={(e) => setNome(e.target.value)} required />
          </div>

          <div className="field">
            <label htmlFor="categoria">Categoria</label>
            <div className="row">
              <select id="categoria" value={categoriaId} onChange={(e) => setCategoriaId(e.target.value)}>
                <option value="">— sem categoria —</option>
                {categorias.map((c) => (
                  <option key={c.id} value={c.id}>
                    {c.nome}
                  </option>
                ))}
              </select>
            </div>
            <div className="row" style={{ marginTop: 6 }}>
              <input
                placeholder="categoria nova"
                value={novaCategoria}
                onChange={(e) => setNovaCategoria(e.target.value)}
              />
              <button type="button" className="btn secondary small" onClick={adicionarCategoria} style={{ flex: '0 0 auto' }}>
                + criar
              </button>
            </div>
          </div>

          <div className="field">
            <label htmlFor="colecao">Coleção</label>
            <select id="colecao" value={colecaoId} onChange={(e) => setColecaoId(e.target.value)}>
              <option value="">— sem coleção —</option>
              {colecoes.map((c) => (
                <option key={c.id} value={c.id}>
                  {c.nome}
                </option>
              ))}
            </select>
            <div className="row" style={{ marginTop: 6 }}>
              <input placeholder="coleção nova" value={novaColecao} onChange={(e) => setNovaColecao(e.target.value)} />
              <button type="button" className="btn secondary small" onClick={adicionarColecao} style={{ flex: '0 0 auto' }}>
                + criar
              </button>
            </div>
          </div>

          <div className="field">
            <label htmlFor="fornecedor">Fornecedor</label>
            <select id="fornecedor" value={fornecedorId} onChange={(e) => setFornecedorId(e.target.value)}>
              <option value="">— sem fornecedor —</option>
              {fornecedores.map((f) => (
                <option key={f.id} value={f.id}>
                  {f.nome}
                </option>
              ))}
            </select>
            <div className="row" style={{ marginTop: 6 }}>
              <input
                placeholder="fornecedor novo"
                value={novoFornecedor}
                onChange={(e) => setNovoFornecedor(e.target.value)}
              />
              <button type="button" className="btn secondary small" onClick={adicionarFornecedor} style={{ flex: '0 0 auto' }}>
                + criar
              </button>
            </div>
          </div>

          <div className="field">
            <label htmlFor="tamanhos">Tamanhos (separados por vírgula)</label>
            <input id="tamanhos" placeholder="P, M, G" value={tamanhos} onChange={(e) => setTamanhos(e.target.value)} required />
          </div>

          <div className="field">
            <label htmlFor="cores">Cores (separadas por vírgula)</label>
            <input id="cores" placeholder="Preto, Branco" value={cores} onChange={(e) => setCores(e.target.value)} required />
          </div>

          <p className="muted" style={{ marginTop: -6, marginBottom: 14 }}>
            Vai criar uma variação pra cada combinação de tamanho × cor, todas com o mesmo preço.
          </p>

          <div className="field">
            <label htmlFor="fotoUrl">Foto (URL, opcional)</label>
            <input id="fotoUrl" value={fotoUrl} onChange={(e) => setFotoUrl(e.target.value)} />
          </div>

          <button className="btn" type="submit" disabled={salvando}>
            {salvando ? 'Salvando…' : 'Cadastrar produto'}
          </button>
        </form>
      </div>
    </div>
  );
}
