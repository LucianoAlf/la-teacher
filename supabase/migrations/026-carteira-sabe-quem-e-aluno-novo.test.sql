-- Teste da 026 — a carteira sabe ha quanto tempo o aluno esta na casa.
--
-- Rodar com: npm run teste:026
--
-- O caso que originou tudo: o Matheus perguntou "essa Fernanda, quem e?" e o
-- Fabio nao soube dizer que era aluna nova, com data_matricula do dia anterior
-- gravada no banco. O passo 1 usa a PROPRIA Fernanda como caso real.
--
-- E o risco de mexer numa view compartilhada: quebrar quem ja consome. Os
-- passos 6 e 7 medem isso -- todas as 28 colunas antigas continuam existindo,
-- e a contagem de linhas nao muda.

create temp table _falhas(passo text, esperado text, obtido text) on commit drop;
create function pg_temp.checar(p text, e text, o text) returns void language plpgsql as $c$
begin if e is distinct from o then insert into _falhas values (p, coalesce(e,'(null)'), coalesce(o,'(null)')); end if; end $c$;

do $t$
declare
  v_aluno_novo integer; v_aluno_velho integer; v_reg uuid;
  v_aula integer; v_unidade uuid;
  v_faltando text;
begin
  -- ===== 1. o caso real: a Fernanda =====
  perform pg_temp.checar('1. a Fernanda aparece como aluna NOVA','true',
    (select e_aluno_novo::text from public.vw_fabio_carteira_professor
      where aluno_id = 1897 limit 1));
  perform pg_temp.checar('2. e o Fabio sabe de quando','2026-08-03',
    (select data_matricula::text from public.vw_fabio_carteira_professor
      where aluno_id = 1897 limit 1));
  -- Este passo dizia '0' fixo: "a Fernanda ainda não tem aula registrada".
  -- Era verdade em 03/08/2026 e deixou de ser quando ela teve aula — o teste
  -- ficou vermelho sem que nada tivesse quebrado. Fixture que é uma PESSOA DE
  -- VERDADE envelhece junto com a vida dela.
  --
  -- O que interessa aqui não é o número, é a coerência: a carteira conta
  -- exatamente os registros confirmados dela, nem um a mais. Isso continua
  -- valendo na semana que vem e pega o defeito real (contagem inflada por
  -- rascunho, ou zerada por join errado).
  perform pg_temp.checar('3. a contagem de aulas bate com os registros confirmados',
    (select count(*)::text from public.fabio_registros_aula r
      where r.aluno_id = 1897 and r.status in ('confirmado','gravado_emusys')),
    (select aulas_registradas::text from public.vw_fabio_carteira_professor
      where aluno_id = 1897 limit 1));

  -- ===== 4. quem entrou ha muito tempo NAO e novo =====
  select aluno_id into v_aluno_velho
    from public.vw_fabio_carteira_professor
   where data_matricula is not null and data_matricula < current_date - 200
   limit 1;
  if v_aluno_velho is null then
    insert into _falhas values ('4. setup','um aluno antigo','nenhum');
  else
    perform pg_temp.checar('4. aluno antigo NAO e novo','false',
      (select e_aluno_novo::text from public.vw_fabio_carteira_professor
        where aluno_id = v_aluno_velho limit 1));
  end if;

  -- ===== 5. sem data_matricula NAO vira "novo" =====
  -- Fail closed: "nao sei quando entrou" nao pode ser lido como "chegou agora".
  --
  -- O caso e CRIADO aqui de proposito. Hoje 1.202 de 1.202 alunos da carteira
  -- tem data_matricula, entao so consultar deixaria este passo rodando sobre
  -- conjunto vazio -- e verificacao sobre conjunto vazio passa sempre. Foi o
  -- que aconteceu na primeira rodada: o mutante que troca o false por true
  -- SOBREVIVEU. O runner da ROLLBACK, entao o aluno volta ao normal.
  update public.alunos set data_matricula = null where id = v_aluno_velho;
  perform pg_temp.checar('5. sem data_matricula NAO e novo','false',
    (select e_aluno_novo::text from public.vw_fabio_carteira_professor
      where aluno_id = v_aluno_velho limit 1));

  -- ===== 6/7. nao quebrei quem ja consome =====
  -- As 28 colunas de antes da 026, uma a uma. Se alguma sumir ou trocar de
  -- nome, o bridge para de ler a carteira e o Fabio fica sem contexto.
  select string_agg(c, ', ') into v_faltando
    from unnest(array[
      'unidade_id','unidade_codigo','unidade_nome','professor_id','professor_nome',
      'professores_unidade_id','emusys_professor_id','professor_emusys_validacao_status',
      'aluno_id','aluno_nome','emusys_student_id','emusys_matricula_id','aluno_status',
      'curso_id','curso_nome','tipo_matricula_codigo','tipo_matricula_nome','dia_aula',
      'horario_aula','telefone','whatsapp','email','responsavel_nome','responsavel_telefone',
      'valor_parcela','qualidade_contexto','jornada_id','emusys_matricula_disciplina_id'
    ]) c
   where not exists (select 1 from information_schema.columns
                      where table_schema='public'
                        and table_name='vw_fabio_carteira_professor'
                        and column_name = c);
  -- coalesce dos DOIS lados: comparar a string '(null)' com um NULL de verdade
  -- da falso-positivo, e foi o que aconteceu na primeira rodada deste teste.
  perform pg_temp.checar('6. nenhuma coluna antiga sumiu','nenhuma', coalesce(v_faltando,'nenhuma'));

  perform pg_temp.checar('7. a view continua entregando linhas','true',
    (select (count(*) > 1000)::text from public.vw_fabio_carteira_professor));

  -- ===== 8. aulas_registradas conta o que existe =====
  select a2.id, a2.unidade_id into v_aula, v_unidade
    from public.aulas_emusys a2 where a2.professor_id=25 order by a2.id desc limit 1;
  select aluno_id into v_aluno_novo
    from public.vw_fabio_carteira_professor where professor_id = 25 and aulas_registradas = 0 limit 1;
  if v_aluno_novo is null or v_aula is null then
    insert into _falhas values ('8. setup','aluno sem registro + aula do prof 25','faltou');
  else
    insert into public.fabio_registros_aula
      (aula_id, unidade_id, professor_id, aluno_id, parent_id, molde, campos, status, origem, confirmado_em)
    values (v_aula, v_unidade, 25, v_aluno_novo, null, 'C',
            '{"progresso":"primeira aula","presenca":"presente"}'::jsonb, 'gravado_emusys','app', now())
    returning id into v_reg;
    perform pg_temp.checar('8. registro novo aparece na contagem','1',
      (select aulas_registradas::text from public.vw_fabio_carteira_professor
        where aluno_id = v_aluno_novo limit 1));

    -- rascunho NAO conta: nao e aula dada
    update public.fabio_registros_aula set status='rascunho' where id = v_reg;
    perform pg_temp.checar('9. rascunho NAO conta como aula registrada','0',
      (select aulas_registradas::text from public.vw_fabio_carteira_professor
        where aluno_id = v_aluno_novo limit 1));

    update public.fabio_registros_aula set status='descartado' where id = v_reg;
    perform pg_temp.checar('10. descartado NAO conta','0',
      (select aulas_registradas::text from public.vw_fabio_carteira_professor
        where aluno_id = v_aluno_novo limit 1));
  end if;

exception when others then
  insert into _falhas values ('excecao','sem excecao', sqlerrm);
end $t$;

select json_build_object('teste','026-carteira-sabe-quem-e-aluno-novo',
  'falhas',(select count(*) from _falhas),
  'detalhe', coalesce((select json_agg(json_build_object('passo',passo,'esperado',esperado,'obtido',obtido)) from _falhas),'[]'::json)) as resumo;

-- ===== o prontuario agora responde "quem e essa aluna?" =====
do $t2$
declare v_p jsonb;
begin
  v_p := public.fabio_prontuario_aluno(1897, 25, 5);
  perform pg_temp.checar('11. prontuario traz o bloco cadastro','true',
    (v_p ? 'cadastro')::text);
  perform pg_temp.checar('12. e diz que ela e nova','true',
    (v_p->'cadastro'->>'e_aluno_novo'));
  perform pg_temp.checar('13. com a data','2026-08-03',
    (v_p->'cadastro'->>'data_matricula'));
  perform pg_temp.checar('14. e o nome do responsavel','Daniele Gonçalves da Gama Freire',
    (v_p->'cadastro'->>'responsavel_nome'));
  perform pg_temp.checar('15. a linha do tempo continua vindo','true',
    (v_p ? 'linha_do_tempo')::text);
  -- O guard de carteira nao pode ter afrouxado: aluno de outro professor
  -- continua barrado, agora que o prontuario le a carteira tambem.
  begin
    perform public.fabio_prontuario_aluno(1897, 1, 5);
    insert into _falhas values ('16. aluno de OUTRO professor barrado','excecao','passou');
  exception when others then null;
  end;
exception when others then
  insert into _falhas values ('excecao prontuario','sem excecao', sqlerrm);
end $t2$;

select json_build_object('teste','026-prontuario-com-cadastro',
  'falhas',(select count(*) from _falhas),
  'detalhe', coalesce((select json_agg(json_build_object('passo',passo,'esperado',esperado,'obtido',obtido)) from _falhas),'[]'::json)) as resumo;
