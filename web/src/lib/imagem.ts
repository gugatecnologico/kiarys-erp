// imagem.ts — comprime uma foto no navegador antes de mandar pra API.
// Sem bucket de arquivo configurado ainda: a foto vira data URL (base64)
// guardada direto em produtos.foto_url. É "pra identificação interna",
// não pro catálogo público, então um JPEG pequeno já resolve — o
// redimensionamento evita mandar 4000×3000 do celular pro banco.

export function comprimirImagem(arquivo: File, maxLado = 800, qualidade = 0.72): Promise<string> {
  return new Promise((resolve, reject) => {
    const leitor = new FileReader();
    leitor.onerror = () => reject(new Error('não deu pra ler o arquivo'));
    leitor.onload = () => {
      const img = new Image();
      img.onerror = () => reject(new Error('arquivo não é uma imagem válida'));
      img.onload = () => {
        const escala = Math.min(1, maxLado / Math.max(img.width, img.height));
        const largura = Math.round(img.width * escala);
        const altura = Math.round(img.height * escala);
        const canvas = document.createElement('canvas');
        canvas.width = largura;
        canvas.height = altura;
        const ctx = canvas.getContext('2d');
        if (!ctx) return reject(new Error('canvas indisponível'));
        ctx.drawImage(img, 0, 0, largura, altura);
        resolve(canvas.toDataURL('image/jpeg', qualidade));
      };
      img.src = leitor.result as string;
    };
    leitor.readAsDataURL(arquivo);
  });
}
