-- 020c-contexto-da-devolutiva.sql
--
-- ⚠️ Esta migration foi APLICADA em produção em 03/08/2026 e só foi versionada
--    depois, na auditoria do Alfredo. Produção ficou divergente da fonte por
--    algumas horas — sem arquivo não dá pra reproduzir, revisar nem reverter.
--    O conteúdo abaixo foi extraído de `pg_get_functiondef` do que está no ar,
--    então é a definição real, não uma reconstrução de memória.
--
-- O worker recebe o contexto JÁ FILTRADO.
--
-- Se o worker lesse `campos` cru pra montar o prompt, a fronteira family-safe
-- passaria a depender de ele LEMBRAR de chamar fn_devolutiva_fonte. Fronteira
-- que depende de disciplina não é fronteira. Aqui ele não tem acesso ao campo
-- de observação nem se quiser: o que sai desta RPC já é o que pode sair.
--
-- Também devolve o que decide o destinatário (nascimento, responsável) e a
-- skill ativa, pra não virar três roundtrips.

create or replace function public.fabio_devolutiva_contexto(p_devolutiva_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
stable
as $function$
declare
  d public.fabio_devolutivas%rowtype;
  r public.fabio_registros_aula%rowtype;
  t public.fabio_registros_aula%rowtype;
  a public.alunos%rowtype;
  v_skill public.fabio_skills%rowtype;
  v_idade integer;
begin
  select * into d from public.fabio_devolutivas where id = p_devolutiva_id;
  if not found then return jsonb_build_object('ok', false, 'erro', 'devolutiva não encontrada'); end if;

  select * into r from public.fabio_registros_aula where id = d.registro_fatia_id;
  if not found then return jsonb_build_object('ok', false, 'erro', 'registro não encontrado'); end if;

  -- tronco: só existe quando é fatia de turma
  if r.parent_id is not null then
    select * into t from public.fabio_registros_aula where id = r.parent_id;
  end if;

  select * into a from public.alunos where id = d.aluno_id;
  select * into v_skill from public.fabio_skills where nome = 'devolutiva_aula' and ativa;

  -- Idade da DATA DE NASCIMENTO, sempre. alunos.idade_atual é cache e envelhece
  -- errado (fica parado enquanto o aluno faz aniversário).
  if a.data_nascimento is not null then
    v_idade := date_part('year', age(a.data_nascimento))::integer;
  end if;

  return jsonb_build_object(
    'ok', true,
    'devolutiva_id', d.id,
    'professor_id', d.professor_id,
    'professor_nome', (select p.nome from public.professores p where p.id = d.professor_id),
    -- AQUI mora a fronteira: nada de observacao/obs_gerais/materiais.
    'fonte', public.fn_devolutiva_fonte(coalesce(t.campos, '{}'::jsonb), coalesce(r.campos, '{}'::jsonb)),
    'aluno', jsonb_build_object(
      'id', a.id,
      'nome', a.nome,
      'primeiro_nome', split_part(btrim(a.nome), ' ', 1),
      'data_nascimento', a.data_nascimento,
      'idade', v_idade,
      'responsavel_nome', nullif(btrim(coalesce(a.responsavel_nome,'')), ''),
      'curso', (select c.nome from public.cursos c where c.id = a.curso_id)),
    'skill', case when v_skill.id is null then null else jsonb_build_object(
      'id', v_skill.id, 'versao', v_skill.versao, 'conteudo', v_skill.conteudo) end,
    'destinatario_override', d.destinatario_override
  );
end $function$;

comment on function public.fabio_devolutiva_contexto is
  'Contexto da devolutiva com a fonte JÁ filtrada por fn_devolutiva_fonte. O worker não vê campos crus — a fronteira não depende de ele lembrar (migration 020c).';

revoke all on function public.fabio_devolutiva_contexto(uuid) from public, anon, authenticated;
grant execute on function public.fabio_devolutiva_contexto(uuid) to service_role, fabio_agent;
