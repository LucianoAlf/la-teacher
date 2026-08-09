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
declare v_aluno int; v_prog jsonb; v_antes int;
begin
  select (a->>'aluno_id')::int into v_aluno
    from _mesa, lateral jsonb_array_elements(j->'alunos') a limit 1;
  select (j->>'respondidos')::int into v_antes from _mesa;

  v_prog := public.app_professor_feedback_salvar(v_aluno, 'amarelo');
  insert into _res values ('so o coracao NAO conta como respondido',
    v_antes::text, v_prog->>'respondidos');

  v_prog := public.app_professor_feedback_salvar(
    v_aluno, 'amarelo', 'as_vezes', 'parado', 'neutro', 'observacao de teste');
  insert into _res values ('coracao + as 3 perguntas conta como respondido',
    (v_antes + 1)::text, v_prog->>'respondidos');
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
