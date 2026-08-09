-- Teste da 078. Roda dentro de BEGIN/ROLLBACK do rodar-teste-sql.mjs.
--
-- O que precisa ficar provado:
--   1. o semáforo do PRÓPRIO professor chega ao Fábio (com a observação)
--   2. o do COLEGA não chega — é a fronteira de 09/08 aplicada a dado novo
--   3. resolve por PESSOA: resposta gravada na matrícula irmã também aparece
create temporary table _res(caso text, ok boolean, detalhe text) on commit drop;

do $$
declare
  v_prof    int;
  v_aluno   int;
  v_irmao   int;
  v_uni     uuid;
  v_colega  int;
  v_comp    date := public.fn_competencia_feedback(null);
  v_p       jsonb;
  v_sem     jsonb;
begin
  -- Uma PESSOA com duas matrículas no mesmo professor (existe: medido em
  -- 09/08). Sem isso o passo 3 não teria como falhar.
  select v.professor_id, (array_agg(distinct v.aluno_id))[1], (array_agg(distinct v.aluno_id))[2],
         (array_agg(a.unidade_id))[1]
    into v_prof, v_aluno, v_irmao, v_uni
    from public.vw_jornada_professor_atual v
    join public.alunos a on a.id = v.aluno_id
   where a.arquivado_em is null and a.emusys_student_id is not null
   group by v.professor_id, a.unidade_id, a.emusys_student_id
  having count(distinct v.aluno_id) > 1
   limit 1;

  select p.id into v_colega
    from public.professores p where p.id <> v_prof limit 1;

  insert into _res values ('cenario montado',
    v_prof is not null and v_aluno is not null and v_irmao is not null
      and v_colega is not null and v_uni is not null,
    format('prof=%s aluno=%s irmao=%s colega=%s', v_prof, v_aluno, v_irmao, v_colega));

  -- Antes de responder nada: o Fábio não pode inventar semáforo.
  v_p := public.fabio_prontuario_aluno(v_aluno, v_prof, 5);
  insert into _res values ('sem resposta, semaforo vem vazio (e existe a chave)',
    v_p ? 'semaforo' and jsonb_array_length(v_p -> 'semaforo') = 0,
    (v_p -> 'semaforo')::text);

  -- ── O professor responde na matrícula IRMÃ, e o colega responde na outra ──
  insert into public.aluno_feedback_professor
    (aluno_id, professor_id, unidade_id, competencia, feedback,
     pratica_em_casa, evolucao, animo, observacao, respondido_em)
  values
    (v_irmao, v_prof, v_uni, v_comp, 'amarelo', 'as_vezes', 'parado', 'neutro',
     'MARCADOR_078 sumiu duas semanas e voltou travado', now()),
    (v_aluno, v_colega, v_uni, v_comp, 'vermelho', 'nao', 'regredindo', 'desanimado',
     'SEGREDO_078 recado do colega', now());

  v_p := public.fabio_prontuario_aluno(v_aluno, v_prof, 5);
  v_sem := v_p -> 'semaforo';

  -- 1 + 3. Chega, e chega mesmo tendo sido gravado na matrícula irmã.
  insert into _res values ('o semaforo do proprio professor chega (resolvido por pessoa)',
    exists (select 1 from jsonb_array_elements(v_sem) e
             where e ->> 'coracao' = 'amarelo'
               and e ->> 'observacao' = 'MARCADOR_078 sumiu duas semanas e voltou travado'),
    v_sem::text);

  -- As três perguntas vêm junto — coração sozinho não sustenta conversa.
  insert into _res values ('as tres perguntas vem junto do coracao',
    exists (select 1 from jsonb_array_elements(v_sem) e
             where e ->> 'pratica_em_casa' = 'as_vezes'
               and e ->> 'evolucao' = 'parado'
               and e ->> 'animo' = 'neutro'),
    v_sem::text);

  -- 2. FRONTEIRA: nada do colega, nem o coração nem o texto.
  insert into _res values ('o semaforo do colega NAO chega',
    not exists (select 1 from jsonb_array_elements(v_sem) e
                 where e ->> 'observacao' = 'SEGREDO_078 recado do colega')
    and v_p::text not like '%SEGREDO_078%',
    v_sem::text);

  -- E o caminho inverso. Aqui a porta é ainda mais dura do que o filtro do
  -- semáforo: um aluno que não é da carteira do colega nem chega a montar
  -- prontuário. As duas saídas valem — o que não pode é o texto vazar.
  begin
    v_p := public.fabio_prontuario_aluno(v_aluno, v_colega, 5);
    insert into _res values ('do outro lado tambem nao vaza',
      v_p::text not like '%MARCADOR_078%', (v_p -> 'semaforo')::text);
  exception when others then
    insert into _res values ('do outro lado tambem nao vaza',
      sqlerrm like 'aluno_fora_da_carteira%', sqlerrm);
  end;

  -- A porta continua exigindo professor: sem ele não existe escopo.
  begin
    perform public.fabio_prontuario_aluno(v_aluno, null, 5);
    insert into _res values ('sem professor a porta continua fechada', false, 'respondeu');
  exception when others then
    insert into _res values ('sem professor a porta continua fechada',
      sqlerrm like 'professor_id_obrigatorio%', sqlerrm);
  end;
end $$;

select json_build_object(
         'falhas', (select count(*) from _res where not ok),
         'detalhe', coalesce((select json_agg(json_build_object('caso', caso, 'detalhe', detalhe))
                                from _res where not ok), '[]'::json)
       ) as resumo;
