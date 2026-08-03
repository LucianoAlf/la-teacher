-- 020-devolutiva-aula-fila-e-skill.sql
--
-- A devolutiva de aula: skill versionada, fila com lease cercado, e a projeção
-- que impede recado interno de sair pra família.
-- Spec: docs/superpowers/specs/2026-08-03-devolutiva-aula-design.md
--
-- Depende da 018 (transporte) e da 019 (presença é afirmação).

-- =====================================================================================
-- 1) fn_devolutiva_fonte — a FRONTEIRA, não uma recomendação
--
-- fn_compor_texto_prontuario monta oito rótulos e dois são material interno:
-- "Observação" (campos.observacao / tronco.obs_gerais) é onde o professor
-- escreve o que ele NÃO diria pra mãe — que a criança chorou, que o pai
-- reclamou da mensalidade, uma suspeita sobre o aluno.
--
-- Proibir isso na skill não é controle: o texto continuaria entrando no prompt,
-- e a única coisa entre o recado interno e o WhatsApp da família seria a boa
-- vontade do modelo naquela geração. Instrução em prompt não é fronteira.
--
-- ⚠️ É LISTA DE PERMISSÃO. Campo de molde novo fica de fora até alguém liberar.
--    O contrário — bloquear o que se conhece — vaza calado no dia em que um
--    molde trouxer `nota_interna` ou `alerta_coordenacao`.
-- =====================================================================================
create or replace function public.fn_devolutiva_fonte(p_tronco jsonb, p_fatia jsonb)
returns jsonb
language sql immutable parallel safe
as $function$
  select jsonb_strip_nulls(jsonb_build_object(
    'objetivo',      nullif(btrim(coalesce(p_fatia->>'objetivo',   p_tronco->>'objetivo')),   ''),
    'conteudo',      nullif(btrim(coalesce(p_fatia->>'atividades', p_tronco->>'atividades')), ''),
    'progresso',     nullif(btrim(p_fatia->>'progresso'), ''),
    'proximo_passo', nullif(btrim(p_fatia->>'proximo_passo'), ''),
    'repertorio',    nullif(btrim(coalesce(p_fatia->>'repertorio', p_tronco->>'repertorio')), ''),
    'dever_casa',    nullif(btrim(coalesce(p_fatia->>'dever_casa', p_tronco->>'dever_casa')), '')
  ))
  -- FORA de propósito: observacao, obs_gerais (recado interno) e materiais
  -- (lista do professor, nível da turma). Ver o cabeçalho.
$function$;

comment on function public.fn_devolutiva_fonte is
  'Projeção family-safe do registro: SÓ os campos liberados. Lista de permissão — campo novo fica fora por padrão (migration 020).';

-- =====================================================================================
-- 2) fabio_skills — o jeito do Fábio escrever mora em dado, não em código
--
-- "A gente não pode colocar uma algema no Fábio" (Alf). O tom vai ser ajustado
-- dezenas de vezes nos primeiros meses, e cada ajuste não pode custar um deploy.
-- Ao mesmo tempo, mudança de tom sem rastro é como se perde a memória do que já
-- foi decidido — por isso versão, e por isso versão antiga nunca é apagada.
-- =====================================================================================
create table if not exists public.fabio_skills (
  id          uuid primary key default gen_random_uuid(),
  nome        text not null,
  versao      integer not null,
  conteudo    text not null,
  ativa       boolean not null default false,
  notas       text,
  criado_em   timestamptz not null default now(),
  criado_por  text
);

create unique index if not exists uq_fabio_skills_nome_versao
  on public.fabio_skills (nome, versao);

-- Uma só versão ativa por skill.
create unique index if not exists uq_fabio_skills_ativa
  on public.fabio_skills (nome) where ativa;

comment on table public.fabio_skills is
  'Skills do Fábio versionadas. Versão antiga nunca é apagada: é o histórico que dá sentido ao skill_versao das devolutivas.';

-- =====================================================================================
-- 3) fabio_devolutivas — uma linha por registro confirmado de aluno presente
-- =====================================================================================
create table if not exists public.fabio_devolutivas (
  id                 uuid primary key default gen_random_uuid(),
  registro_fatia_id  uuid not null references public.fabio_registros_aula(id) on delete cascade,
  aluno_id           integer not null,
  professor_id       integer not null,

  -- destinatário: o que a IDADE inferiu vs o que o PROFESSOR decidiu
  destinatario               text,      -- 'responsavel' | 'aluno'
  destinatario_override      text,      -- quando existe, MANDA
  destinatario_origem        text,      -- 'idade' | 'professor'
  destinatario_nome          text,
  destinatario_decidido_por  integer,
  destinatario_decidido_em   timestamptz,
  idade_na_geracao           integer,

  texto_normal       text,
  texto_apoio_casa   text,

  skill_id           uuid references public.fabio_skills(id),
  skill_versao       integer,

  status             text not null default 'pendente',
  lease_token        uuid,
  lease_expira_em    timestamptz,
  proxima_tentativa_em timestamptz,
  aguardando_desde   timestamptz,
  envio_chave        text,
  envio_recibo       text,
  erro               text,
  tentativas         integer not null default 0,

  oferecida_em         timestamptz,
  copiada_em           timestamptz,
  editada_em           timestamptz,
  compartilhada_em     timestamptz,
  envio_confirmado_em  timestamptz,

  criado_em     timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),

  constraint fabio_devolutivas_status_check check (status = any (array[
    'pendente','gerando','aguardando_destinatario','gerada',
    'oferecida','entrega_incerta','falhou','descartada'])),
  constraint fabio_devolutivas_destinatario_check check (
    destinatario is null or destinatario in ('responsavel','aluno')),
  constraint fabio_devolutivas_override_check check (
    destinatario_override is null or destinatario_override in ('responsavel','aluno'))
);

-- Uma fatia gera UMA devolutiva. Reconfirmar não duplica.
-- ⚠️ Índice único e ON CONFLICT são um contrato só — o enfileirador abaixo usa
--    exatamente esta chave.
create unique index if not exists uq_fabio_devolutiva_por_registro
  on public.fabio_devolutivas (registro_fatia_id);

create index if not exists ix_fabio_devolutivas_fila
  on public.fabio_devolutivas (status, proxima_tentativa_em);

comment on column public.fabio_devolutivas.destinatario_override is
  'O que o PROFESSOR decidiu. Campo separado da inferência: se caísse no mesmo, um reprocessamento sobrescreveria a decisão humana com a idade e ninguém notaria.';
comment on column public.fabio_devolutivas.idade_na_geracao is
  'Idade congelada. Daqui a um ano, olhando um texto que fala com a mãe, dá pra saber que na época estava certo.';

-- =====================================================================================
-- 4) O enfileirador. Predicado do §2.4 da spec, FALHANDO FECHADO.
--
-- ⚠️ `= 'presente'`, nunca `<> 'ausente'`. A primeira versão da spec usava
--    coalesce(...,'presente') <> 'ausente' — o mesmo coalesce que este projeto
--    passou o dia inteiro tirando do sistema. Como 31 de 31 registros não têm a
--    chave, aquele predicado liberaria devolutiva pra TODO MUNDO, inclusive pra
--    quem faltou. Só é elegível quem foi AFIRMADO presente.
-- =====================================================================================
create or replace function public.fabio_enfileirar_devolutivas(p_registro_id uuid)
returns integer
language plpgsql
security definer
set search_path to 'public'
as $function$
declare v_n integer;
begin
  with elegiveis as (
    select r.id, r.aluno_id, r.professor_id
      from public.fabio_registros_aula r
     where (r.id = p_registro_id or r.parent_id = p_registro_id)
       and r.aluno_id is not null                    -- fatia OU raiz 1:1; nunca tronco
       and r.status = 'gravado_emusys'
       and r.confirmado_em is not null
       and public.fn_presenca_declarada(r.campos) = 'presente'   -- falha fechada
  )
  insert into public.fabio_devolutivas (registro_fatia_id, aluno_id, professor_id, status)
  select id, aluno_id, professor_id, 'pendente' from elegiveis
  on conflict (registro_fatia_id) do nothing;
  get diagnostics v_n = row_count;
  return v_n;
end $function$;

comment on function public.fabio_enfileirar_devolutivas is
  'Enfileira devolutiva para cada registro de aluno PRESENTE do tronco. Só enfileira — gerar texto roda fora, no worker (migration 020).';

-- =====================================================================================
-- 5) Claim com lease E cerca, igual ao da 018 — mesma classe de problema.
-- =====================================================================================
create or replace function public.fabio_devolutiva_claim(
  p_worker text, p_lote integer default 5, p_lease_minutos integer default 5)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare v_token uuid := gen_random_uuid(); v_itens jsonb;
begin
  with alvo as (
    select d.id from public.fabio_devolutivas d
     where d.status = 'pendente'
       and (d.proxima_tentativa_em is null or d.proxima_tentativa_em <= now())
     order by d.criado_em
     limit greatest(p_lote, 1)
     for update skip locked
  ), tomadas as (
    update public.fabio_devolutivas d
       set status = 'gerando',
           lease_token = v_token,
           lease_expira_em = now() + make_interval(mins => p_lease_minutos),
           tentativas = d.tentativas + 1,
           atualizado_em = now()
      from alvo where d.id = alvo.id
    returning d.id, d.registro_fatia_id, d.aluno_id, d.professor_id
  )
  select coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) into v_itens from tomadas t;

  return jsonb_build_object('ok', true, 'worker', p_worker,
                            'lease_token', v_token, 'itens', v_itens);
end $function$;

-- =====================================================================================
-- 6) Conclusões — TODAS exigem o token E o lease vivo.
--    Zero linhas = o trabalho não é mais meu: descartar, não insistir.
-- =====================================================================================
create or replace function public.fabio_devolutiva_gerada(
  p_id uuid, p_lease_token uuid,
  p_texto_normal text, p_texto_apoio_casa text,
  p_destinatario text, p_destinatario_nome text, p_idade integer,
  p_skill_id uuid, p_skill_versao integer)
returns boolean
language plpgsql
security definer
set search_path to 'public'
as $function$
declare v_n integer;
begin
  update public.fabio_devolutivas
     set status = 'gerada',
         texto_normal = p_texto_normal, texto_apoio_casa = p_texto_apoio_casa,
         destinatario = p_destinatario, destinatario_nome = p_destinatario_nome,
         destinatario_origem = coalesce(destinatario_origem, 'idade'),
         idade_na_geracao = p_idade,
         skill_id = p_skill_id, skill_versao = p_skill_versao,
         erro = null, atualizado_em = now()
   where id = p_id and status = 'gerando'
     and lease_token = p_lease_token and lease_expira_em > now();
  get diagnostics v_n = row_count;
  return v_n > 0;
end $function$;

create or replace function public.fabio_devolutiva_falhou(
  p_id uuid, p_lease_token uuid, p_erro text, p_backoff_segundos integer default 300)
returns boolean
language plpgsql
security definer
set search_path to 'public'
as $function$
declare v_n integer; v_teto constant integer := 5;
begin
  update public.fabio_devolutivas
     set status = case when tentativas >= v_teto then 'falhou' else 'pendente' end,
         erro = p_erro,
         -- backoff de verdade: sem isto o próximo tick pega a mesma linha e ela
         -- queima LLM a cada minuto.
         proxima_tentativa_em = now() + make_interval(secs => greatest(p_backoff_segundos, 1)),
         lease_token = null, lease_expira_em = null, atualizado_em = now()
   where id = p_id and status = 'gerando'
     and lease_token = p_lease_token and lease_expira_em > now();
  get diagnostics v_n = row_count;
  return v_n > 0;
end $function$;

-- Idade impossível (ou destinatário indecidível) PARA ANTES do prompt. Gerar
-- primeiro e perguntar depois produziria um texto com vocativo inventado — e
-- queimaria uma chamada de LLM pra fazer algo inútil.
create or replace function public.fabio_devolutiva_aguardar_destinatario(
  p_id uuid, p_lease_token uuid, p_motivo text)
returns boolean
language plpgsql
security definer
set search_path to 'public'
as $function$
declare v_n integer;
begin
  update public.fabio_devolutivas
     set status = 'aguardando_destinatario', aguardando_desde = now(),
         erro = p_motivo, lease_token = null, lease_expira_em = null,
         atualizado_em = now()
   where id = p_id and status = 'gerando'
     and lease_token = p_lease_token and lease_expira_em > now();
  get diagnostics v_n = row_count;
  return v_n > 0;
end $function$;

-- =====================================================================================
-- 7) O gancho na confirmação: ENFILEIRA, não gera. Não-fatal, igual ao da
--    presença — confirmar registro nunca pode falhar porque a devolutiva falhou.
-- =====================================================================================
create or replace function public.fabio_emitir_presenca_por_registro_e_devolutiva(p_registro_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare v_presenca jsonb; v_devs integer := 0;
begin
  begin
    v_presenca := public.fabio_emitir_presenca_por_registro(p_registro_id);
  exception when others then v_presenca := jsonb_build_object('aplicado',false,'erro',sqlerrm); end;
  begin
    v_devs := public.fabio_enfileirar_devolutivas(p_registro_id);
  exception when others then v_devs := -1; end;
  return jsonb_build_object('presenca', v_presenca, 'devolutivas_enfileiradas', v_devs);
end $function$;

-- =====================================================================================
-- 8) A skill v1. Texto é dado — muda sem deploy, com histórico.
-- =====================================================================================
insert into public.fabio_skills (nome, versao, conteudo, ativa, notas, criado_por)
select 'devolutiva_aula', 1, $skill$
Você escreve a DEVOLUTIVA DE UMA AULA para o professor encaminhar.

QUEM LÊ
- Se o destinatário for "responsavel": fale COM o responsável, pelo nome, e do
  aluno em terceira pessoa.
- Se for "aluno": fale com ele, em segunda pessoa.
- Sem nome do responsável: fale com a família SEM vocativo nominal. Nunca invente
  nome, nunca escreva "Sr(a). Responsável".

O QUE ENTRA
- Só o que está na fonte recebida. Você NÃO acrescenta fato nenhum.
- Diga o que a criança FEZ e o que vem DEPOIS.
- Fora: dificuldade técnica, comparação com outros alunos, diagnóstico de
  comportamento, qualquer coisa que soe como avaliação de valor.
- Recital/apresentação só se houver data real na fonte. Sem data, não existe.

AS DUAS VERSÕES
1. normal.
2. apoio_casa: pede parceria para praticar. REGRA: PEDIR, NUNCA ACUSAR.
   - NÃO: "o Gustavo não praticou esta semana."
   - SIM: "Um pouquinho de prática em casa, uns 10 minutos por dia, ajudaria
     muito o Gustavo a fixar o que ele já conseguiu na aula."
   Quem lê não pode terminar com sensação de bronca — nem ele, nem o filho.

TOM
Curto, caloroso, concreto. WhatsApp, não ofício. Sem emoji em excesso.
$skill$, true, 'Versão inicial — tom aprovado pelo Alf no desenho.', 'migration-020'
where not exists (select 1 from public.fabio_skills where nome='devolutiva_aula' and versao=1);

-- =====================================================================================
-- 9) ACL. Tabelas novas: RLS ligada e sem policy — só service_role/definer
--    entram. Ver 018b: função nova nasce aberta e eu já esqueci uma vez.
-- =====================================================================================
alter table public.fabio_devolutivas enable row level security;
alter table public.fabio_skills      enable row level security;

revoke all on function
  public.fabio_enfileirar_devolutivas(uuid),
  public.fabio_devolutiva_claim(text, integer, integer),
  public.fabio_devolutiva_gerada(uuid, uuid, text, text, text, text, integer, uuid, integer),
  public.fabio_devolutiva_falhou(uuid, uuid, text, integer),
  public.fabio_devolutiva_aguardar_destinatario(uuid, uuid, text),
  public.fabio_emitir_presenca_por_registro_e_devolutiva(uuid),
  public.fn_devolutiva_fonte(jsonb, jsonb)
from public, anon, authenticated;

grant execute on function
  public.fabio_enfileirar_devolutivas(uuid),
  public.fabio_devolutiva_claim(text, integer, integer),
  public.fabio_devolutiva_gerada(uuid, uuid, text, text, text, text, integer, uuid, integer),
  public.fabio_devolutiva_falhou(uuid, uuid, text, integer),
  public.fabio_devolutiva_aguardar_destinatario(uuid, uuid, text),
  public.fabio_emitir_presenca_por_registro_e_devolutiva(uuid),
  public.fn_devolutiva_fonte(jsonb, jsonb)
to service_role, fabio_agent;
