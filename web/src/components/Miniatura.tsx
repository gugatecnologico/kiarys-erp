// Miniatura.tsx — thumbnail de produto com fallback, usado em toda lista
// (Vender, Estoque, carrinho, seletor do admin) pra parar de mostrar só
// texto onde tem foto disponível.

export function Miniatura({ src, alt, tamanho = 44 }: { src: string | null; alt: string; tamanho?: number }) {
  const estilo = {
    width: tamanho,
    height: tamanho,
    borderRadius: 8,
    objectFit: 'cover' as const,
    border: '1px solid var(--border)',
    background: '#f0ede8',
    flexShrink: 0,
  };

  if (!src) {
    return (
      <div
        style={{ ...estilo, display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: tamanho * 0.45 }}
        aria-hidden
      >
        🛍️
      </div>
    );
  }

  return <img src={src} alt={alt} style={estilo} />;
}
