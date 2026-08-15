-- A aula sem aluno para de engolir o trabalho do professor.
--
-- 15/08/2026. O professor grava o áudio da aula. A aula, no espelho do Emusys,
-- está com ZERO aluno. O normalizador recusa — e recusa CERTO: sem roster não
-- dá pra fatiar o conteúdo por aluno sem inventar gente. A linha vai pra
-- `erro_terminal` e acaba ali. O professor não recebe nada. O trabalho dele
-- some em silêncio.
--
-- MEDIDO em 15/08 (30 dias, produção):
--
--   4.975 aulas não canceladas
--     129 sem nenhum aluno no roster
--      92 dessas são a ÂNCORA operacional (as outras 37 o
--         fn_aula_operacional_id já resolve pra um gêmeo com roster)
--      91 das 92 têm `qtd_alunos = 0` VINDO DO EMUSYS — não é sync perdida,
--         é o Emusys dizendo que a turma está vazia
--       1 áudio de professor morto por isso (prof 35, G_Seg_17/CG, 10/08)
--
-- ⚠️ O radar dizia "758 aulas / 4 áudios". Os outros 3 áudios eram
-- EXPERIMENTAL entrando pela porta do aluno — defeito de outra família, já
-- fechado em 20260815070000. Aqui é só a aula comum.
--
-- O que ESTA migration NÃO faz, de propósito: não cria registro sem fatia, não
-- deixa o professor listar quem estava, não inventa aluno. Se um registro de
-- turma sem fatia por aluno vale como registro é decisão pedagógica, não minha.
-- O que ela faz é o que não depende de decisão nenhuma:
--
--   1. a fila para de ser um beco sem saída silencioso (o professor fica
--      sabendo, com o motivo certo: não é ele, é a turma vazia no sistema);
--   2. quando a secretaria lançar os alunos, o áudio volta a andar SOZINHO —
--      a promessa da mensagem é cumprida por código, não por lembrança.
--
-- ⚠️ NADA aqui lê o campo `erro`. Aquele texto é escrito pelo AGENTE e já
-- mandou duas investigações pro lado errado. A régua é fato de banco:
-- a aula operacional tem linha em `aula_alunos_emusys` ou não tem.

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. A lista honesta. Fonte única de "fila parada porque a aula não tem aluno".

create or replace view public.vw_fila_audio_sem_roster as
select
  f.id                                       as fila_id,
  f.professor_id,
  f.unidade_id,
  f.aula_id                                  as aula_id_da_fila,
  a.id                                       as aula_operacional_id,
  f.status,
  f.origem,
  f.criado_em,
  f.atualizado_em,
  (f.storage_path is not null)               as tem_audio,
  (coalesce(btrim(f.transcricao), '') <> '') as tem_transcricao,
  a.tipo,
  a.categoria,
  a.turma_nome,
  a.curso_nome,
  a.qtd_alunos                               as qtd_alunos_emusys,
  (a.data_hora_inicio at time zone 'America/Sao_Paulo') as inicio_brt,
  exists (
    select 1 from public.fabio_registros_aula r
     where r.aula_id = a.id and r.parent_id is null
  ) as ja_tem_registro
from public.fabio_fila_audios f
join public.aulas_emusys a
  on a.id = public.fn_aula_operacional_id(f.aula_id)
where f.vinculo_id is null            -- experimental tem worker e porta próprios
  and f.status in ('erro', 'erro_terminal')
  and not exists (
    select 1 from public.aula_alunos_emusys r
     where r.aula_emusys_id = a.id
  );

comment on view public.vw_fila_audio_sem_roster is
  'Áudio de aula COMUM parado porque a aula operacional não tem nenhum aluno no roster. Régua de FATO (ausência de linha em aula_alunos_emusys), nunca o texto do campo erro — aquele é escrito pelo agente. Buraco conhecido: fn_aula_operacional_id devolve NULL quando não há candidata NÃO cancelada, então quem gravou sobre aula cancelada e sem gêmeo cai fora deste join. Medido em 15/08: 0 linhas nessa situação — buraco teórico hoje, não perda em curso.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Quem precisa saber. O worker lê daqui.
--
-- Dois recortes, e cada um tem motivo:
--   • `p_dias` — sem isso, ligar este aviso despeja o passivo inteiro no
--     WhatsApp dos professores de uma vez, sobre áudio que ninguém mais espera.
--   • `p_grace_minutos` — a secretaria pode estar lançando a turma agora.
--     Avisar em 2 minutos é ruído; em 30, é notícia.
--
-- Não existe recorte de cancelada: aula cancelada não chega até aqui, porque
-- `fn_aula_operacional_id` só considera candidata NÃO cancelada e devolve NULL
-- quando não há nenhuma. Filtro que nunca dispara é decoração — fica de fora,
-- e o buraco fica NOMEADO no comentário da view em vez de fingido resolvido.

create or replace function public.fabio_fila_sem_roster_a_avisar(
  p_limite integer default 20,
  p_grace_minutos integer default 30,
  p_dias integer default 7
)
returns table (
  fila_id uuid,
  professor_id integer,
  aula_operacional_id integer,
  turma_nome text,
  curso_nome text,
  tipo text,
  inicio_brt timestamp,
  tem_transcricao boolean
)
language sql
stable
security definer
set search_path to 'pg_catalog', 'public'
as $function$
  select v.fila_id, v.professor_id, v.aula_operacional_id,
         v.turma_nome::text, v.curso_nome::text, v.tipo::text,
         v.inicio_brt, v.tem_transcricao
    from public.vw_fila_audio_sem_roster v
   where not v.ja_tem_registro
     and v.professor_id is not null
     and v.criado_em     > now() - make_interval(days => greatest(p_dias, 1))
     and v.atualizado_em < now() - make_interval(mins => greatest(p_grace_minutos, 0))
     and not exists (
       select 1 from public.fabio_notificacoes n
        where n.referencia_tipo = 'fila_audio_sem_roster'
          and n.referencia_id   = v.fila_id::text
          and n.status          = 'enviada'
     )
   order by v.criado_em
   limit greatest(p_limite, 1);
$function$;

comment on function public.fabio_fila_sem_roster_a_avisar(integer, integer, integer) is
  'Áudios parados por aula sem aluno que o professor ainda não soube. Exclui quem já tem registro e quem já recebeu aviso ENVIADO — o claim por referência é que impede o duplicado, isto aqui só evita remontar o corpo à toa.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. A promessa cumprida por código.
--
-- A mensagem diz "assim que a secretaria lançar os alunos, eu processo
-- sozinho". Quem cumpre é esta função — e ela sabe EM QUAIS linhas a promessa
-- foi feita porque a própria notificação enviada é o marcador. Sem isso eu
-- precisaria de uma coluna nova só pra lembrar, ou religaria às cegas todo
-- `erro_terminal` cuja aula tem roster — inclusive os que morreram por outro
-- motivo semântico e vão morrer de novo.
--
-- `fn_fabio_chama_edge` é chamada aqui em vez de só marcar 'pendente' porque
-- `fn_fabio_retry_fila` só alcança linha com `criado_em` nos últimos 3 dias:
-- deixar em pendente não faria nada pra quem passou disso.

create or replace function public.fn_fila_audio_retomar_por_roster(
  p_limite integer default 20
)
returns integer
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $function$
declare
  r record;
  n integer := 0;
begin
  for r in
    select f.id,
           f.aula_id                                as aula_antiga,
           public.fn_aula_operacional_id(f.aula_id) as aula_nova
      from public.fabio_fila_audios f
     where f.vinculo_id is null
       and f.status in ('erro', 'erro_terminal')
       -- A promessa só foi feita onde o aviso saiu.
       and exists (
         select 1 from public.fabio_notificacoes nt
          where nt.referencia_tipo = 'fila_audio_sem_roster'
            and nt.referencia_id   = f.id::text
            and nt.status          = 'enviada'
       )
       -- E só vale a pena voltar se AGORA tem em quem lançar.
       and exists (
         select 1 from public.aula_alunos_emusys ra
          where ra.aula_emusys_id = public.fn_aula_operacional_id(f.aula_id)
       )
       and not exists (
         select 1 from public.fabio_registros_aula rg
          where rg.aula_id = public.fn_aula_operacional_id(f.aula_id)
            and rg.parent_id is null
       )
     order by f.criado_em
     limit greatest(p_limite, 1)
  loop
    insert into public.audit_log(tabela, registro_id_text, acao, dados_antigos, dados_novos, origem)
    values (
      'fabio_fila_audios', r.id::text, 'retomada_por_roster',
      jsonb_build_object('aula_id', r.aula_antiga, 'status', 'erro/erro_terminal'),
      jsonb_build_object('aula_id', r.aula_nova, 'status', 'pendente'),
      'fn_fila_audio_retomar_por_roster'
    );

    update public.fabio_fila_audios
       set aula_id       = r.aula_nova,
           status        = 'pendente',
           erro_tipo     = 'transitorio',
           erro          = null,
           tentativas    = 0,
           atualizado_em = now()
     where id = r.id;

    perform public.fn_fabio_chama_edge(r.id);
    n := n + 1;
  end loop;
  return n;
end
$function$;

comment on function public.fn_fila_audio_retomar_por_roster(integer) is
  'Religa o áudio que morreu por aula sem aluno, quando o roster apareceu. Só toca em linha onde o aviso ao professor JÁ saiu — a notificação enviada é o marcador da promessa. Grava audit_log antes do UPDATE.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. Portas fechadas. Isto é maquinário de worker, não de cliente.

revoke all on public.vw_fila_audio_sem_roster from public, anon, authenticated;
revoke all on function
  public.fabio_fila_sem_roster_a_avisar(integer, integer, integer),
  public.fn_fila_audio_retomar_por_roster(integer)
  from public, anon, authenticated;

grant select on public.vw_fila_audio_sem_roster to service_role;
grant execute on function
  public.fabio_fila_sem_roster_a_avisar(integer, integer, integer),
  public.fn_fila_audio_retomar_por_roster(integer)
  to service_role;
