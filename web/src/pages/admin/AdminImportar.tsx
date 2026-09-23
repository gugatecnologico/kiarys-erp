import { useState, type FormEvent } from 'react';
import { api, ApiError, type LinhaImportacao, type ResultadoImportacao } from '../../lib/api';

const COLUNAS = [
  'referencia',
  'nome',
  'categoria',
  'colecao',
  'fornecedor',
  'tamanho',
  'cor',
  'preco_venda',
  'codigo_barras',
  'estoque_inicial',
] as const;

const MODELO = 'referencia,nome,categoria,colecao,fornecedor,tamanho,cor,preco_venda,codigo_barras,estoque_inicial\nBLZ001,Blazer alfaiataria,Blazer,Verão 26,Fornecedor X,P,Preto,189.90,,5\nBLZ001,Blazer alfaiataria,Blazer,Verão 26,Fornecedor X,M,Preto,189.90,,5';

function parseCsv(texto: string): LinhaImportacao[] {
  const linhas = texto.trim().split(/\r?\n/).filter((l) => l.trim() !== '');
  if (linhas.length < 2) throw new Error('cole o cabeçalho e pelo menos uma linha de dados');
  const cabecalho = linhas[0].split(',').map((c) => c.trim());
  return linhas.slice(1).map((linha) => {
    const valores = linha.split(',').map((v) => v.trim());
    const obj: Record<string, string> = {};
    cabecalho.forEach((col, i) => (obj[col] = valores[i] ?? ''));
    if (!obj.referencia || !obj.nome || !obj.tamanho || !obj.cor || !obj.preco_venda) {
      throw new Error('cada linha precisa de referencia, nome, tamanho, cor e preco_venda');
    }
    return {
      referencia: obj.referencia,
      nome: obj.nome,
      categoria: obj.categoria || undefined,
      colecao: obj.colecao || undefined,
      fornecedor: obj.fornecedor || undefined,
      tamanho: obj.tamanho,
      cor: obj.cor,
      preco_venda: Number(obj.preco_venda.replace(',', '.')),
      codigo_barras: obj.codigo_barras || undefined,
      estoque_inicial: obj.estoque_inicial ? Number(obj.estoque_inicial) : undefined,
    };
  });
}

export function AdminImportar() {
  const [csv, setCsv] = useState('');
  const [erro, setErro] = useState<string | null>(null);
  const [resultado, setResultado] = useState<ResultadoImportacao[] | null>(null);
  const [enviando, setEnviando] = useState(false);

  async function enviar(e: FormEvent) {
    e.preventDefault();
    setErro(null);
    setResultado(null);
    let linhas: LinhaImportacao[];
    try {
      linhas = parseCsv(csv);
    } catch (err) {
      setErro(err instanceof Error ? err.message : 'CSV inválido');
      return;
    }
    setEnviando(true);
    try {
      setResultado(await api.importarProdutos(linhas));
    } catch (err) {
      setErro(err instanceof ApiError ? err.message : 'não deu pra importar');
    } finally {
      setEnviando(false);
    }
  }

  const falhas = resultado?.filter((r) => !r.ok) ?? [];
  const sucessos = resultado?.filter((r) => r.ok) ?? [];

  return (
    <div>
      <h1>Importar produtos</h1>
      <div className="card">
        <p className="muted">
          Cole abaixo o conteúdo de uma planilha em CSV (separado por vírgula), com a primeira linha de cabeçalho.
          Colunas aceitas: {COLUNAS.join(', ')}. Categoria/coleção/fornecedor são criados automaticamente se ainda
          não existirem.
        </p>
        <button type="button" className="btn secondary small" onClick={() => setCsv(MODELO)}>
          usar modelo de exemplo
        </button>
      </div>

      <div className="card">
        {erro && <div className="alert error">{erro}</div>}
        <form onSubmit={enviar}>
          <div className="field">
            <label htmlFor="csv">CSV</label>
            <textarea
              id="csv"
              value={csv}
              onChange={(e) => setCsv(e.target.value)}
              rows={10}
              style={{
                width: '100%',
                padding: 10,
                borderRadius: 10,
                border: '1px solid var(--border)',
                fontFamily: 'monospace',
                fontSize: 13,
              }}
              required
            />
          </div>
          <button className="btn" type="submit" disabled={enviando}>
            {enviando ? 'Importando…' : 'Importar'}
          </button>
        </form>
      </div>

      {resultado && (
        <div className="card">
          <h2>Resultado</h2>
          <div className="list-item">
            <span className="muted">Linhas importadas</span>
            <span className="badge ok">{sucessos.length}</span>
          </div>
          {falhas.length > 0 && (
            <div className="list-item">
              <span className="muted">Linhas com erro</span>
              <span className="badge low">{falhas.length}</span>
            </div>
          )}
          {falhas.map((f) => (
            <div className="list-item" key={f.linha}>
              <span>linha {f.linha}</span>
              <span className="muted">{f.erro}</span>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
