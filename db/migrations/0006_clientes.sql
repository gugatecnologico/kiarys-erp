-- 0006_clientes.sql
-- LGPD (seção 8): só o necessário, com flag de consentimento de marketing.

set search_path = kiarys, public;

-- Normaliza WhatsApp para só dígitos, para casar buscas mesmo com
-- formatação diferente ("(88) 9 9999-9999" vs "88999999999").
create or replace function kiarys.normalizar_whatsapp(p_numero text)
returns text
language sql
immutable
as $$ select nullif(regexp_replace(coalesce(p_numero, ''), '\D', '', 'g'), '') $$;

create table kiarys.clientes (
  id                  uuid primary key default gen_random_uuid(),
  nome                text not null check (btrim(nome) <> ''),
  whatsapp            text,
  whatsapp_normalizado text generated always as (kiarys.normalizar_whatsapp(whatsapp)) stored,
  cpf                 text,
  aniversario         date,
  tamanho_preferido   text,
  aceita_marketing    boolean not null default false,
  criado_em           timestamptz not null default now()
);

create unique index idx_clientes_whatsapp_unico
  on kiarys.clientes (whatsapp_normalizado)
  where whatsapp_normalizado is not null;

create index idx_clientes_nome_trgm on kiarys.clientes using gin (nome gin_trgm_ops);

comment on column kiarys.clientes.cpf is
  'Opcional. Só coletado se a cliente informar — não é obrigatório para '
  'venda, já que o fiscal é resolvido fora deste sistema (brief, seção 1).';
