-- 074 (teste) — a mesa do professor
--
-- Os passos que dão nome à migration: o DEDUPE (a carteira tem 1.224 linhas
-- para 1.165 alunos — sem dedupe a barrinha nunca fecha), o RESPONDIDO
-- (coração + as três perguntas) e a COLUNA CERTA de última aula
-- (`ultima_aula_registrada`, não `data_ultima_aula`, que é o fim do contrato e
-- está no futuro em 1.191 das 1.224 linhas).
--
-- O aluno arquivado é arquivado DENTRO da transação e some no rollback do
-- harness: fixture em banco compartilhado vaza, transação não.

create temp table _res(passo text, esperado text, obtido text) on commit drop;

-- ─── Guardas ────────────────────────────────────────────────────────────────
do $$
declare v_saida jsonb;
begin
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);
  v_saida := public.app_professor_feedback_mesa(null);
  insert into _res values ('sem identidade a mesa devolve erro', 'sim',
    case when v_saida ? 'erro' then 'sim' else 'NAO — ' || v_saida::text end);
end $$;

do $$
declare v_erro text := 'nao levantou';
begin
  begin perform public.app_professor_feedback_salvar(1, 'verde');
  exception when others then v_erro := sqlerrm; end;
  insert into _res values ('sem identidade o salvar recusa', 'sim',
    case when v_erro like '%sem_professor_vinculado%' then 'sim' else 'NAO — ' || v_erro end);
end $$;

-- ─── Escolhe um professor com carteira e assume a identidade dele ───────────
create temp table _ctx on commit drop as
  select v.professor_id, u.auth_user_id
    from public.vw_jornada_professor_atual v
    join public.professores p on p.id = v.professor_id
    join public.usuarios u    on u.id = p.usuario_id
   where u.auth_user_id is not null and coalesce(u.ativo, true)
   group by v.professor_id, u.auth_user_id
  having count(distinct v.aluno_id) >= 3
   limit 1;

insert into _res select 'ancora: ha professor com login e 3+ alunos', 'sim',
  case when count(*) = 0 then 'NAO' else 'sim' end from _ctx;

do $$
declare v_uid uuid;
begin
  select auth_user_id into v_uid from _ctx;
  if v_uid is not null then
    perform set_config('request.jwt.claim.sub', v_uid::text, true);
  end if;
end $$;

-- ─── A âncora do dedupe ─────────────────────────────────────────────────────
insert into _res
select 'ancora: esse professor tem aluno com 2 matriculas', 'sim',
  case when count(*) > 0 then 'sim'
       else 'NAO — sem duplicata, o dedupe nao falseia' end
from (select v.aluno_id
        from public.vw_jornada_professor_atual v, _ctx c
       where v.professor_id = c.professor_id
       group by v.aluno_id having count(*) > 1) d;

create temp table _mesa on commit drop as
  select public.app_professor_feedback_mesa(null) as j;

insert into _res
select 'a mesa conta ALUNO, nao matricula', 'sim',
  case when (select (j->>'total')::int from _mesa)
          = (select count(distinct v.aluno_id)::int
               from public.vw_jornada_professor_atual v, _ctx c
              where v.professor_id = c.professor_id)
       then 'sim' else 'NAO — total=' || (select j->>'total' from _mesa) end;

insert into _res
select 'nenhum aluno aparece duas vezes na mesa', 'sim',
  case when count(*) = 0 then 'sim' else 'NAO — ' || count(*) || ' repetido(s)' end
from (select a->>'aluno_id' as id
        from _mesa, lateral jsonb_array_elements(j->'alunos') a
       group by 1 having count(*) > 1) r;

-- ─── A coluna certa de última aula ──────────────────────────────────────────
insert into _res
select 'ancora: data_ultima_aula esta no FUTURO (e a coluna errada)', 'sim',
  case when count(*) > 0 then 'sim'
       else 'NAO — sem contrato futuro, trocar a coluna nao falseia' end
from public.vw_jornada_professor_atual v, _ctx c
where v.professor_id = c.professor_id
  and v.data_ultima_aula > public.fn_hoje_brt();

insert into _res
select 'ninguem tem dias_sem_aula negativo', 'sim',
  case when count(*) = 0 then 'sim' else 'NAO — ' || count(*) || ' negativo(s)' end
from _mesa, lateral jsonb_array_elements(j->'alunos') a
where (a->>'dias_sem_aula') is not null and (a->>'dias_sem_aula')::int < 0;

insert into _res
select 'quem tem aula no mes esta no bloco "viu"', 'sim',
  case when count(*) = 0 then 'sim' else 'NAO — ' || count(*) || ' fora do bloco' end
from _mesa, lateral jsonb_array_elements(j->'alunos') a
join (select v.aluno_id, max(v.ultima_aula_registrada) as ult
        from public.vw_jornada_professor_atual v, _ctx c
       where v.professor_id = c.professor_id group by v.aluno_id) u
  on u.aluno_id = (a->>'aluno_id')::int
where (u.ult >= public.fn_competencia_feedback())
  and (a->>'teve_aula_no_mes')::boolean is false;

-- ─── A direção oposta: quem NÃO teve aula real não pode aparecer como "viu".
-- O passo acima só prova que quem teve aula aparece — não pega hardcode
-- (`teve_aula_no_mes` sempre true) nem a coluna errada (`data_ultima_aula`,
-- que empurra pra "viu" por estar quase sempre no futuro): as duas mutações
-- só produzem FALSOS POSITIVOS, nunca um "viu" virando "não viu".
insert into _res
select 'ancora: professor tem aluno sem aula real no mes (bloco "nao viu" nao e vazio)', 'sim',
  case when count(*) > 0 then 'sim'
       else 'NAO — sem esse caso, nao da pra falsear teve_aula_no_mes=true indevido' end
from (select v.aluno_id, max(v.ultima_aula_registrada) as ult
        from public.vw_jornada_professor_atual v, _ctx c
       where v.professor_id = c.professor_id group by v.aluno_id) x
where x.ult is null or x.ult < public.fn_competencia_feedback();

insert into _res
select 'quem NAO teve aula real no mes NAO aparece marcado como "viu"', 'sim',
  case when count(*) = 0 then 'sim' else 'NAO — ' || count(*) || ' marcado(s) errado' end
from _mesa, lateral jsonb_array_elements(j->'alunos') a
join (select v.aluno_id, max(v.ultima_aula_registrada) as ult
        from public.vw_jornada_professor_atual v, _ctx c
       where v.professor_id = c.professor_id group by v.aluno_id) u
  on u.aluno_id = (a->>'aluno_id')::int
where (u.ult is null or u.ult < public.fn_competencia_feedback())
  and (a->>'teve_aula_no_mes')::boolean is true;

-- ─── Salvar: só a própria carteira ──────────────────────────────────────────
do $$
declare v_erro text := 'nao levantou'; v_alheio int;
begin
  select v.aluno_id into v_alheio
    from public.vw_jornada_professor_atual v, _ctx c
   where v.professor_id <> c.professor_id limit 1;
  insert into _res values ('ancora: existe aluno de outro professor', 'sim',
    case when v_alheio is null then 'NAO' else 'sim' end);
  begin perform public.app_professor_feedback_salvar(v_alheio, 'verde');
  exception when others then v_erro := sqlerrm; end;
  insert into _res values ('salvar recusa aluno fora da carteira', 'sim',
    case when v_erro like '%aluno_fora_da_sua_carteira%' then 'sim' else 'NAO — ' || v_erro end);
end $$;

-- ─── "Respondido" é coração + as TRÊS perguntas ─────────────────────────────
do $$
declare
  v_aluno int; v_prog jsonb; v_antes int; v_prof int; v_comp date;
  v_origem_antes text; v_respondido_antes timestamptz;
begin
  select professor_id into v_prof from _ctx;
  v_comp := public.fn_competencia_feedback();

  select (a->>'aluno_id')::int into v_aluno
    from _mesa, lateral jsonb_array_elements(j->'alunos') a limit 1;
  select (j->>'respondidos')::int into v_antes from _mesa;

  v_prog := public.app_professor_feedback_salvar(v_aluno, 'amarelo');
  insert into _res values ('so o coracao NAO conta como respondido',
    v_antes::text, v_prog->>'respondidos');

  -- `now()` fica CONGELADO no início da transação — comparar respondido_em
  -- contra o valor que a 1a chamada gravou nunca divergiria, nem sob um
  -- mutante que passasse a reescrever (o `excluded.respondido_em` da 2a
  -- chamada seria o MESMO `now()` congelado). E `origem` é literal fixo na
  -- função — comparar contra 'la_teacher' depois da 2a chamada também nunca
  -- divergiria, com ou sem o bug. Planta sentinelas manuais (bem longe de
  -- qualquer valor que a função escreveria sozinha) pra provar de verdade
  -- que a 2a escrita NÃO toca em origem/respondido_em.
  update public.aluno_feedback_professor
     set origem        = 'sentinela_nao_deveria_mudar',
         respondido_em = now() - interval '30 days'
   where aluno_id = v_aluno and professor_id = v_prof and competencia = v_comp;

  select origem, respondido_em into v_origem_antes, v_respondido_antes
    from public.aluno_feedback_professor
   where aluno_id = v_aluno and professor_id = v_prof and competencia = v_comp;

  v_prog := public.app_professor_feedback_salvar(
    v_aluno, 'amarelo', 'as_vezes', 'parado', 'neutro', 'observacao de teste');
  insert into _res values ('coracao + as 3 perguntas conta como respondido',
    (v_antes + 1)::text, v_prog->>'respondidos');

  -- A 2a escrita é update (a linha já existe): origem/respondido_em não
  -- entram no SET da migration, então a sentinela plantada acima tem que
  -- sobreviver — se um mutante mover os dois pro SET, `excluded.origem`
  -- vira 'la_teacher' de novo e `excluded.respondido_em` vira o `now()`
  -- congelado (bem diferente dos "30 dias atrás" plantados), e as duas
  -- linhas abaixo divergem.
  insert into _res
  select 'a 2a escrita NAO reescreve origem', v_origem_antes, f.origem
    from public.aluno_feedback_professor f
   where f.aluno_id = v_aluno and f.professor_id = v_prof and f.competencia = v_comp;

  insert into _res
  select 'a 2a escrita NAO reescreve respondido_em',
         v_respondido_antes::text, f.respondido_em::text
    from public.aluno_feedback_professor f
   where f.aluno_id = v_aluno and f.professor_id = v_prof and f.competencia = v_comp;
end $$;

-- ─── Arquivado sai da mesa (arquivado dentro da transação) ──────────────────
do $$
declare v_aluno int; v_total_antes int; v_total_depois int;
begin
  select (j->>'total')::int into v_total_antes from _mesa;
  select (a->>'aluno_id')::int into v_aluno
    from _mesa, lateral jsonb_array_elements(j->'alunos') a limit 1;

  update public.alunos set arquivado_em = now() where id = v_aluno;
  select (public.app_professor_feedback_mesa(null)->>'total')::int into v_total_depois;

  insert into _res values ('arquivar um aluno tira ele do denominador',
    (v_total_antes - 1)::text, v_total_depois::text);

  update public.alunos set arquivado_em = null where id = v_aluno;
end $$;

-- ─── A porta ────────────────────────────────────────────────────────────────
insert into _res
select 'anon NAO executa a mesa', 'sim',
  case when has_function_privilege('anon',
        'public.app_professor_feedback_mesa(date)', 'execute')
       then 'NAO — anon executa' else 'sim' end;

insert into _res
select 'anon NAO executa o salvar', 'sim',
  case when has_function_privilege('anon',
        'public.app_professor_feedback_salvar(integer, text, text, text, text, text, date)', 'execute')
       then 'NAO — anon executa' else 'sim' end;

-- ─── A fronteira: a RLS deixou de ser escancarada ───────────────────────────
insert into _res
select 'nenhuma policy solta por auth.role() sobrou', 'sim',
  case when count(*) = 0 then 'sim' else 'NAO — ' || string_agg(policyname, ', ') end
from pg_policies
where schemaname = 'public' and tablename = 'aluno_feedback_professor'
  and coalesce(qual, '') like '%auth.role()%';

-- ─── A fronteira family-safe: observação nunca sai pra quem alimenta a família
-- Mutante 4 do plano ("observacao passa a ser selecionada num caminho
-- family-safe") não tinha prova em lugar nenhum — nem 073/074/075/076 nem os
-- 4 scripts/mutantes-0NN.mjs cobriam isso. V11 (RLS) protege professor A de
-- ler o texto de professor B; isto aqui é outra fronteira: um caminho que já
-- RODA como service_role e legitimamente devolve dado pra um responsável não
-- pode devolver o texto que o professor escreveu pra coordenação.
--
-- O conjunto é medido NO CATÁLOGO (padrão de nome), não uma lista digitada —
-- task-10-report.md tem a evidência de cada família:
--   • '%devolutiva%'  — fabio_devolutiva_* / app_devolutiva_* / fn_devolutiva_fonte.
--     020c já documenta a fronteira ("o worker não vê campos crus") — este
--     passo é a prova automatizada dessa frase.
--   • '%pedagogico%'  — get_relatorio_pedagogico_aluno[_interno_20260712] e
--     get_historico_pedagogico_aluno[_interno_20260712]. Confirmado na FONTE
--     da edge function gerar-relatorio-pedagogico (fora deste repo, não
--     testável em SQL): o prompt da IA diz literalmente "relatório
--     pedagógico... destinado ao responsável/familiar".
--   • '%responsavel%' — nenhum objeto usa esse nome hoje; mantido como rede
--     porque é o nome que o próprio plano cita como candidato.
--   • '%anamnese%'    — a ficha que a família preenche/lê por token público
--     (get_anamnese_publica, get_convite_anamnese, salvar_anamnese_online...).
-- NÃO uso '%relatorio%' sozinho: pegaria ~30 relatórios gerenciais / comerciais
-- / admin (get_dados_relatorio_gerencial, montar_relatorio_coordenacao_payload_v3,
-- capturar_relatorio_coordenacao_canonico_v2...) que são STAFF-facing, não
-- família. Também não uso '%ficha%' nem '%aluno%' soltos: pegariam
-- app_aluno_ficha (ficha do PROFESSOR sobre o aluno, gated por
-- fn_professor_do_usuario — não é família) e vw_aluno_sucesso_lista (CRM da
-- coordenação, que JÁ seleciona fb.observacao hoje — de propósito, é a
-- exceção que a própria 074 sanciona via policy feedback_coordenacao_le). Um
-- padrão largo teria acusado um caminho são.
--
-- Marcador DUPLO — não só 'observacao' sozinho — é o que separa isto de falso
-- positivo: só acusa quando a MESMA definição cita 'aluno_feedback_professor'
-- (prova que a rotina toca a tabela) E 'observacao' (singular). Sem o duplo,
-- qualquer rotina family-facing que mencionasse "observação" só em texto de
-- erro/comentário já reprovaria à toa. E o singular importa: fn_professor_do_
-- usuario e afins nunca entram aqui, mas se entrassem, 'professores.observacoes'
-- (plural) NUNCA bate '%observacao%' — o 9º caractere diverge (observaç[o]es
-- vs observaç[ã]o) — então a coluna homônima de outra tabela (professores,
-- aluno_transferencias, pesquisa_evasao_desfechos...) não derruba este passo
-- sozinha; ela só pesa se a MESMA rotina family-facing TAMBÉM mencionar
-- aluno_feedback_professor, o que hoje nenhuma menciona.
--
-- NULL-safe por construção, não por coalesce residual: count(*) nunca é NULL
-- (zero linhas = 0, não NULL), e os dois ilike comparam contra
-- coalesce(pg_get_functiondef(...), '')/coalesce(definition, '') — um corpo
-- ilegível não vira NULL silencioso que escaparia do ilike e do WHERE.
insert into _res
select 'nenhuma rotina family-facing (devolutiva/pedagogico/responsavel/anamnese) seleciona observacao de aluno_feedback_professor',
       'sim',
       case when count(*) = 0 then 'sim' else 'NAO — ' || string_agg(nome, ', ') end
from (
  select p.proname as nome, coalesce(pg_get_functiondef(p.oid), '') as def
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname ilike any (array['%devolutiva%', '%pedagogico%', '%responsavel%', '%anamnese%'])
  union all
  select v.viewname, coalesce(v.definition, '')
    from pg_views v
   where v.schemaname = 'public'
     and v.viewname ilike any (array['%devolutiva%', '%pedagogico%', '%responsavel%', '%anamnese%'])
) alvo
where def ilike '%aluno_feedback_professor%'
  and def ilike '%observacao%';

-- ─── Veredito ───────────────────────────────────────────────────────────────
-- Alias `resumo` com `falhas` NUMÉRICO: é o contrato que
-- `scripts/rodar-teste-sql.mjs` exige (`typeof resumo.falhas !== 'number'`) e
-- que os 54 `.test.sql` do repo usam. Um alias diferente faz o harness dizer
-- "não veio resumo estruturado" e reprovar sem explicar.
select json_build_object(
  'falhas',  (select count(*) from _res where esperado is distinct from obtido),
  'detalhe', (select coalesce(json_agg(json_build_object(
                       'passo', passo, 'esperado', esperado, 'obtido', obtido)), '[]'::json)
                from _res where esperado is distinct from obtido)
) as resumo;
