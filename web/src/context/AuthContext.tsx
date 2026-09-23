import { createContext, useContext, useEffect, useState, type ReactNode } from 'react';
import { api, getToken, setToken, type Perfil } from '../lib/api';

type AuthState = {
  perfil: Perfil | null;
  carregando: boolean;
  login: (email: string, senha: string) => Promise<void>;
  logout: () => void;
};

const AuthContext = createContext<AuthState | null>(null);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [perfil, setPerfil] = useState<Perfil | null>(null);
  const [carregando, setCarregando] = useState(true);

  useEffect(() => {
    if (!getToken()) {
      setCarregando(false);
      return;
    }
    api
      .me()
      .then(setPerfil)
      .catch(() => setToken(null))
      .finally(() => setCarregando(false));
  }, []);

  async function login(email: string, senha: string) {
    const { token, perfil } = await api.login(email, senha);
    setToken(token);
    setPerfil(perfil);
    // /auth/me traz os flags pode_ver_custo/pode_cadastrar que o login não devolve
    const completo = await api.me();
    setPerfil(completo);
  }

  function logout() {
    setToken(null);
    setPerfil(null);
  }

  return <AuthContext.Provider value={{ perfil, carregando, login, logout }}>{children}</AuthContext.Provider>;
}

export function useAuth() {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error('useAuth precisa estar dentro de <AuthProvider>');
  return ctx;
}
