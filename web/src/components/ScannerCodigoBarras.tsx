import { useEffect, useRef, useState } from 'react';
import { BrowserMultiFormatReader } from '@zxing/browser';

// Scanner de código de barras via câmera — modal simples, sem UI framework
// (mesmo padrão do resto do app). Usa @zxing/library: funciona no Android
// e no iOS (Safari 17+ e app nativo do Instagram/WhatsApp embutido, que é
// onde a vendedora normalmente abre isso), diferente da BarcodeDetector
// nativa do navegador, que ainda não existe em todo Safari.
export function ScannerCodigoBarras({ onLido, onFechar }: { onLido: (codigo: string) => void; onFechar: () => void }) {
  const videoRef = useRef<HTMLVideoElement>(null);
  const [erro, setErro] = useState<string | null>(null);

  useEffect(() => {
    const leitor = new BrowserMultiFormatReader();
    let controls: { stop: () => void } | undefined;
    let ativo = true;

    leitor
      .decodeFromVideoDevice(undefined, videoRef.current ?? undefined, (resultado, err) => {
        if (resultado && ativo) {
          ativo = false;
          onLido(resultado.getText());
        }
        // err dispara a cada frame sem leitura — não é erro real, ignora.
        void err;
      })
      .then((c) => {
        controls = c;
      })
      .catch(() => {
        setErro('não deu pra acessar a câmera — verifique a permissão do navegador');
      });

    return () => {
      ativo = false;
      controls?.stop();
    };
  }, [onLido]);

  return (
    <div
      style={{
        position: 'fixed',
        inset: 0,
        background: 'rgba(0,0,0,0.85)',
        zIndex: 100,
        display: 'flex',
        flexDirection: 'column',
        alignItems: 'center',
        justifyContent: 'center',
        padding: 16,
      }}
    >
      {erro ? (
        <div className="alert error" style={{ maxWidth: 320 }}>
          {erro}
        </div>
      ) : (
        <>
          <video ref={videoRef} style={{ width: '100%', maxWidth: 360, borderRadius: 14 }} muted playsInline />
          <p style={{ color: '#fff', marginTop: 14, fontSize: 14 }}>Aponte pro código de barras</p>
        </>
      )}
      <button className="btn secondary" style={{ marginTop: 18, maxWidth: 200 }} onClick={onFechar} type="button">
        cancelar
      </button>
    </div>
  );
}
