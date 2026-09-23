import { NavLink } from 'react-router-dom';
import { useAuth } from '../../context/AuthContext';

const ITENS_CADASTRO = [
  { to: '/admin/produtos', icon: '🆕', label: 'Cadastrar produto', desc: 'Produto novo, com grade tamanho × cor' },
  { to: '/admin/importar', icon: '📥', label: 'Importar produtos', desc: 'Colar uma planilha em CSV' },
  { to: '/admin/entrada', icon: '📦', label: 'Entrada de mercadoria', desc: 'Recebimento de fornecedor, com custo' },
  { to: '/admin/precos', icon: '🏷️', label: 'Preços e promoção', desc: 'Mudar preço de venda ou colocar em promoção' },
];

// Ajustar estoque e criar login são só admin (RPCs kiarys.ajustar_estoque
// e kiarys.criar_usuaria exigem eh_admin(), não pode_cadastrar()).
const ITENS_ADMIN = [
  { to: '/admin/ajuste', icon: '🔧', label: 'Ajustar estoque', desc: 'Corrigir contagem, perda ou quebra' },
  { to: '/admin/usuarias', icon: '👤', label: 'Nova usuária', desc: 'Criar login para o time' },
];

export function AdminHub() {
  const { perfil } = useAuth();
  const itens = perfil?.papel === 'admin' ? [...ITENS_CADASTRO, ...ITENS_ADMIN] : ITENS_CADASTRO;

  return (
    <div>
      <h1>Admin</h1>
      <div className="card">
        {itens.map((item) => (
          <NavLink to={item.to} key={item.to} className="list-item" style={{ textDecoration: 'none', color: 'inherit' }}>
            <span>
              <span style={{ marginRight: 10 }}>{item.icon}</span>
              <strong>{item.label}</strong>
              <br />
              <span className="muted" style={{ marginLeft: 26 }}>
                {item.desc}
              </span>
            </span>
            <span className="muted">›</span>
          </NavLink>
        ))}
      </div>
    </div>
  );
}
