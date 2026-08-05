-- 032 — vinculo entre lead_experimentais e a aula real (aulas_emusys)
--
-- Ver docs/superpowers/specs/2026-08-05-ciclo-da-aula-experimental-design.md
-- (v2.3, carimbada pelo Alfredo) para o raciocinio completo. Resumo do que
-- este arquivo cria:
--
--   - HISTORICO, nao estado atual: varias linhas por lead, uma vigente
--     (indice unico PARCIAL em substituido_em is null).
--   - OCUPACAO e uma pergunta DIFERENTE de vigencia: usa `estado`, nao
--     `cancelado_em` — e essa distincao e o que fecha "aula que ja
--     aconteceu nao pode ficar livre so porque a matricula foi cancelada
--     depois" (achado do Alfredo, v2.2).
--   - `aula_local_id` aponta pro id LOCAL (serial) de aulas_emusys — NUNCA
--     confundir com `lead_experimentais.emusys_aula_id` (legado, id de
--     evento do Emusys, nao casa) nem com `aulas_emusys.emusys_id`.

create table public.lead_experimental_aulas (
  id                    bigserial primary key,
  lead_experimental_id  integer not null references public.lead_experimentais(id),

  -- Id LOCAL de aulas_emusys (aulas_emusys.id), nao o emusys_id externo.
  aula_local_id         integer references public.aulas_emusys(id),

  estado                text not null default 'pendente'
    check (estado in ('pendente','vinculado','manual','realizado','faltou','cancelado')),
    -- pendente  -> sem par ainda; o reconciliador REAVALIA a cada rodada
    -- vinculado -> casado pela chave natural; reavaliavel se reagendar
    -- manual    -> decisao humana; o reconciliador NUNCA sobrescreve
    -- realizado -> a aula aconteceu; PERMANECE realizado pra sempre, mesmo
    --              com cancelado_em preenchido depois (matricula cancelada)
    -- faltou    -> aula existiu, professor esteve la, familia nao veio.
    --              Ocupa o horario como 'realizado' (NAO e 'cancelado'),
    --              mas nao habilita registro/presenca/devolutiva.
    -- cancelado -> so alcancado ANTES de realizar; libera o horario

  motivo_pendencia      text
    check (motivo_pendencia is null or motivo_pendencia in ('sem_par','ambiguo')),
  casado_por            text
    check (casado_por is null or casado_por in ('chave_natural','manual')),

  criado_em             timestamptz not null default now(),
  vinculado_em          timestamptz,
  vinculado_por         text,
  substituido_em        timestamptz,   -- reagendamento de verdade: linha sai de vigencia
  cancelado_em          timestamptz,

  -- Contrato 3 — matricula com recibo
  aluno_id              integer references public.alunos(id),
  aluno_vinculado_em    timestamptz,
  aluno_vinculado_por   text,
  aluno_origem          text
);

-- VIGENCIA: uma linha vigente por lead. So `substituido_em` retira uma linha
-- de vigencia — de proposito SEM `cancelado_em` aqui. Uma experimental
-- cancelada sem reagendamento CONTINUA vigente pro lead: so passa a existir
-- uma segunda linha vigente quando HOUVE reagendamento de verdade.
create unique index uq_lead_exp_aula_vigente
    on public.lead_experimental_aulas (lead_experimental_id)
 where substituido_em is null;

-- OCUPACAO: uma aula do Emusys nao serve a dois leads ao mesmo tempo — mas
-- "ocupada" e definido por `estado`, nao pela presenca de `cancelado_em`.
-- estado='realizado' ou 'faltou' continuam ocupando o horario mesmo se
-- cancelado_em for preenchido depois (matricula cancelada a posteriori).
-- So estado='cancelado' (alcancado ANTES de realizar) libera.
create unique index uq_lead_exp_aula_ocupada
    on public.lead_experimental_aulas (aula_local_id)
 where aula_local_id is not null
   and substituido_em is null
   and estado <> 'cancelado';

revoke all on table public.lead_experimental_aulas from public, anon, authenticated;
grant select, insert, update on table public.lead_experimental_aulas to service_role;
grant usage, select on sequence public.lead_experimental_aulas_id_seq to service_role;

comment on table public.lead_experimental_aulas is
'Vinculo (historico) entre lead_experimentais e a aula real em aulas_emusys. Uma linha vigente por lead (substituido_em is null); ocupacao do horario usa estado, nao cancelado_em. Ver spec 2026-08-05-ciclo-da-aula-experimental-design.md v2.3.';
