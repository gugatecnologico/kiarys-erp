// api.ts — cliente HTTP fino pra API do Kiarys ERP. Sem lib externa
// (fetch nativo é suficiente e mantém o bundle pequeno).

const API_URL = import.meta.env.VITE_API_URL as string;

const TOKEN_KEY = 'kiarys_token';

export function getToken(): string | null {
  return localStorage.getItem(TOKEN_KEY);
}

export function setToken(token: string | null) {
  if (token) localStorage.setItem(TOKEN_KEY, token);
  else localStorage.removeItem(TOKEN_KEY);
}

class ApiError extends Error {
  status: number;
  constructor(status: number, message: string) {
    super(message);
    this.status = status;
  }
}

async function request<T>(path: string, opts: RequestInit = {}): Promise<T> {
  const token = getToken();
  const res = await fetch(`${API_URL}${path}`, {
    ...opts,
    headers: {
      'content-type': 'application/json',
      ...(token ? { authorization: `Bearer ${token}` } : {}),
      ...(opts.headers ?? {}),
    },
  });

  if (res.status === 401) {
    setToken(null);
  }

  if (!res.ok) {
    const body = await res.json().catch(() => ({}));
    throw new ApiError(res.status, body.erro ?? `erro ${res.status}`);
  }
  if (res.status === 204) return null as T;
  return res.json();
}

export type Perfil = {
  id: string;
  nome: string;
  email: string;
  papel: 'vendedora' | 'gerente' | 'admin';
  ativo: boolean;
  comissao_pct: string;
  limite_desconto_pct: string | null;
  pode_ver_custo: boolean;
  pode_cadastrar: boolean;
};

export type VariacaoEstoque = {
  produto_id: string;
  referencia: string;
  nome: string;
  foto_url: string | null;
  variacao_id: string;
  tamanho: string;
  cor: string;
  codigo_barras: string;
  preco_venda: string;
  preco_promocional: string | null;
  promo_ate: string | null;
  preco_efetivo: string;
  saldo: number;
  estoque_minimo: number;
};

export type ProdutoBusca = {
  produto_id: string;
  referencia: string;
  nome: string;
  foto_url: string | null;
  ativo: boolean;
  preco_min: string;
  preco_max: string;
  saldo_total: number;
};

export type CaixaAberto = {
  id: string;
  usuario_abertura: string;
  aberto_por_nome: string;
  aberto_em: string;
  valor_inicial: string;
};

export type Venda = {
  id: string;
  numero: string;
  total: string;
  subtotal: string;
  desconto: string;
  status: 'PAGA' | 'CANCELADA';
  criado_em: string;
};

export type MinhaVenda = {
  id: string;
  numero: string;
  criado_em: string;
  status: 'PAGA' | 'CANCELADA';
  vendedora_nome: string;
  total: string;
  comissao: string;
  dia: string;
};

export type ItemVenda = { variacao_id: string; quantidade: number };
export type Pagamento = { forma: 'PIX' | 'DEBITO' | 'CREDITO' | 'DINHEIRO'; valor: number; parcelas?: number };

export const api = {
  login: (email: string, senha: string) =>
    request<{ token: string; perfil: Perfil }>('/auth/login', {
      method: 'POST',
      body: JSON.stringify({ email, senha }),
    }),
  me: () => request<Perfil>('/auth/me'),
  trocarSenha: (senha_atual: string, senha_nova: string) =>
    request<void>('/auth/trocar-senha', { method: 'POST', body: JSON.stringify({ senha_atual, senha_nova }) }),

  buscarProdutos: (q: string) =>
    request<ProdutoBusca[]>(`/api/views/v_produtos_busca?${new URLSearchParams({ q, limit: '20' })}`),
  gradeDoProduto: (referencia: string) =>
    request<VariacaoEstoque[]>(`/api/views/v_estoque?${new URLSearchParams({ q: referencia, limit: '100' })}`),
  caixaAberto: () => request<CaixaAberto[]>('/api/views/v_caixa_aberto'),
  minhasVendas: () => request<MinhaVenda[]>('/api/views/v_minhas_vendas?limit=100'),
  estoque: (q = '') => request<VariacaoEstoque[]>(`/api/views/v_estoque?${new URLSearchParams({ q, limit: '100' })}`),

  registrarVenda: (payload: {
    itens: ItemVenda[];
    pagamentos: Pagamento[];
    chave_idempotencia: string;
    cliente_id?: string | null;
    desconto_geral?: number;
  }) => request<Venda>('/api/vendas', { method: 'POST', body: JSON.stringify(payload) }),
  cancelarVenda: (id: string, motivo: string) =>
    request<Venda>(`/api/vendas/${id}/cancelar`, { method: 'POST', body: JSON.stringify({ motivo }) }),

  abrirCaixa: (valor_inicial: number) =>
    request<CaixaAberto>('/api/caixa/abrir', { method: 'POST', body: JSON.stringify({ valor_inicial }) }),
  movimentarCaixa: (tipo: 'SANGRIA' | 'SUPRIMENTO', valor: number, motivo: string) =>
    request('/api/caixa/movimentar', { method: 'POST', body: JSON.stringify({ tipo, valor, motivo }) }),
  fecharCaixa: (valor_contado: number) =>
    request('/api/caixa/fechar', { method: 'POST', body: JSON.stringify({ valor_contado }) }),
};

export { ApiError };
