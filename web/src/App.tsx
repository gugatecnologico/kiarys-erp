import { NavLink, Navigate, Route, BrowserRouter, Routes } from 'react-router-dom';
import { AuthProvider, useAuth } from './context/AuthContext';
import { Login } from './pages/Login';
import { Vender } from './pages/Vender';
import { MeuCaixa } from './pages/MeuCaixa';
import { Estoque } from './pages/Estoque';
import { MinhasVendas } from './pages/MinhasVendas';

function Protegido({ children }: { children: React.ReactNode }) {
  const { perfil, carregando } = useAuth();
  if (carregando) return <div className="center">carregando…</div>;
  if (!perfil) return <Navigate to="/login" replace />;
  return <>{children}</>;
}

// Sem isso, depois do login o formulário continua na tela — a rota
// /login só troca pra Vender por navegação explícita, e o login() do
// AuthContext só atualiza o estado, nunca navega sozinho.
function SomenteVisitante({ children }: { children: React.ReactNode }) {
  const { perfil, carregando } = useAuth();
  if (carregando) return <div className="center">carregando…</div>;
  if (perfil) return <Navigate to="/" replace />;
  return <>{children}</>;
}

function Layout({ children }: { children: React.ReactNode }) {
  const { perfil, logout } = useAuth();
  return (
    <div className="app">
      <div className="app-body">
        <div className="top-bar">
          <strong>Kiarys</strong>
          {perfil && (
            <span className="who">
              {perfil.nome}{' '}
              <button className="btn secondary small" style={{ marginLeft: 8 }} onClick={logout} type="button">
                sair
              </button>
            </span>
          )}
        </div>
        {children}
      </div>
      {perfil && (
        <nav className="tabbar">
          <NavLink to="/" end className={({ isActive }) => (isActive ? 'active' : '')}>
            <span className="icon">🛍️</span>Vender
          </NavLink>
          <NavLink to="/estoque" className={({ isActive }) => (isActive ? 'active' : '')}>
            <span className="icon">📦</span>Estoque
          </NavLink>
          <NavLink to="/caixa" className={({ isActive }) => (isActive ? 'active' : '')}>
            <span className="icon">💰</span>Meu caixa
          </NavLink>
          <NavLink to="/minhas-vendas" className={({ isActive }) => (isActive ? 'active' : '')}>
            <span className="icon">🧾</span>Vendas
          </NavLink>
        </nav>
      )}
    </div>
  );
}

function AppRoutes() {
  return (
    <Routes>
      <Route
        path="/login"
        element={
          <SomenteVisitante>
            <Login />
          </SomenteVisitante>
        }
      />
      <Route
        path="/"
        element={
          <Protegido>
            <Vender />
          </Protegido>
        }
      />
      <Route
        path="/estoque"
        element={
          <Protegido>
            <Estoque />
          </Protegido>
        }
      />
      <Route
        path="/caixa"
        element={
          <Protegido>
            <MeuCaixa />
          </Protegido>
        }
      />
      <Route
        path="/minhas-vendas"
        element={
          <Protegido>
            <MinhasVendas />
          </Protegido>
        }
      />
    </Routes>
  );
}

function App() {
  return (
    <AuthProvider>
      <BrowserRouter>
        <Layout>
          <AppRoutes />
        </Layout>
      </BrowserRouter>
    </AuthProvider>
  );
}

export default App;
