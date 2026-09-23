import { Router } from 'express';
import { comoUsuario } from '../db.js';
import { requireAuth, erroParaHttp } from '../auth.js';

export const estoqueRouter = Router();
estoqueRouter.use(requireAuth);

// Produtos — cria com grade tamanho × cor já pronta.
estoqueRouter.post('/produtos', async (req, res) => {
  const {
    referencia,
    nome,
    categoria_id = null,
    colecao_id = null,
    fornecedor_id = null,
    preco_venda,
    tamanhos,
    cores,
    foto_url = null,
  } = req.body ?? {};

  try {
    const produto = await comoUsuario(req.uid, async (client) => {
      const { rows } = await client.query(
        `select * from kiarys.criar_produto_com_grade($1,$2,$3,$4,$5,$6,$7,$8,$9)`,
        [referencia, nome, categoria_id, colecao_id, fornecedor_id, preco_venda, tamanhos, cores, foto_url]
      );
      return rows[0];
    });
    res.status(201).json(produto);
  } catch (err) {
    const { status, erro } = erroParaHttp(err);
    res.status(status).json({ erro });
  }
});

// Importação em massa por CSV — o frontend faz o parse e manda as linhas
// já estruturadas (ver kiarys.importar_produtos).
estoqueRouter.post('/produtos/importar', async (req, res) => {
  const { linhas } = req.body ?? {};
  if (!Array.isArray(linhas) || linhas.length === 0) {
    return res.status(400).json({ erro: 'linhas é obrigatório' });
  }
  try {
    const resultado = await comoUsuario(req.uid, async (client) => {
      const { rows } = await client.query('select * from kiarys.importar_produtos($1::jsonb)', [
        JSON.stringify(linhas),
      ]);
      return rows;
    });
    res.json(resultado);
  } catch (err) {
    const { status, erro } = erroParaHttp(err);
    res.status(status).json({ erro });
  }
});

estoqueRouter.post('/entradas', async (req, res) => {
  const { fornecedor_id = null, itens, frete = 0, outras_despesas = 0, doc_ref = null } = req.body ?? {};
  if (!Array.isArray(itens) || itens.length === 0) {
    return res.status(400).json({ erro: 'itens é obrigatório' });
  }
  try {
    const entrada = await comoUsuario(req.uid, async (client) => {
      const { rows } = await client.query(
        'select * from kiarys.registrar_entrada($1, $2::jsonb, $3, $4, $5)',
        [fornecedor_id, JSON.stringify(itens), frete, outras_despesas, doc_ref]
      );
      return rows[0];
    });
    res.status(201).json(entrada);
  } catch (err) {
    const { status, erro } = erroParaHttp(err);
    res.status(status).json({ erro });
  }
});

estoqueRouter.post('/ajustar', async (req, res) => {
  const { variacao_id, nova_qtd_contada, motivo, tipo = 'AJUSTE' } = req.body ?? {};
  try {
    const mov = await comoUsuario(req.uid, async (client) => {
      const { rows } = await client.query('select * from kiarys.ajustar_estoque($1, $2, $3, $4)', [
        variacao_id,
        nova_qtd_contada,
        motivo,
        tipo,
      ]);
      return rows[0];
    });
    res.status(201).json(mov);
  } catch (err) {
    const { status, erro } = erroParaHttp(err);
    res.status(status).json({ erro });
  }
});

estoqueRouter.post('/precos', async (req, res) => {
  const { variacao_id, preco_venda, preco_promocional = null, promo_ate = null } = req.body ?? {};
  try {
    const variacao = await comoUsuario(req.uid, async (client) => {
      const { rows } = await client.query('select * from kiarys.alterar_precos($1, $2, $3, $4)', [
        variacao_id,
        preco_venda,
        preco_promocional,
        promo_ate,
      ]);
      return rows[0];
    });
    res.json(variacao);
  } catch (err) {
    const { status, erro } = erroParaHttp(err);
    res.status(status).json({ erro });
  }
});
