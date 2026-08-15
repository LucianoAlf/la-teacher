-- O trecho executavel remotamente e um contrato de catalogo: nao cria fixtures
-- nem escreve em public. O bloco Docker no fim fica comentado de proposito e o
-- mutante o extrai para um PostgreSQL efemero, onde a selecao roda de verdade.

create temporary table pg_temp._sem_roster_res (
  caso text,
  ok boolean,
  detalhe text
) on commit drop;

create or replace function pg_temp.checar_sem_roster(
  p_caso text,
  p_ok boolean,
  p_detalhe text
) returns void
language plpgsql
as $function$
begin
  insert into pg_temp._sem_roster_res(caso, ok, detalhe)
  values (p_caso, coalesce(p_ok, false), p_detalhe);
end
$function$;

do $function$
declare
  v_view oid := to_regclass('public.vw_fila_audio_sem_roster');
  v_avisar regprocedure := to_regprocedure('public.fabio_fila_sem_roster_a_avisar(integer,integer,integer)');
  v_retomar regprocedure := to_regprocedure('public.fn_fila_audio_retomar_por_roster(integer)');
  v_def text;
  v_norm text;
begin
  perform pg_temp.checar_sem_roster('a view existe', v_view is not null, coalesce(v_view::text, '<ausente>'));
  perform pg_temp.checar_sem_roster('a porta do aviso existe', v_avisar is not null, coalesce(v_avisar::text, '<ausente>'));
  perform pg_temp.checar_sem_roster('a porta da retomada existe', v_retomar is not null, coalesce(v_retomar::text, '<ausente>'));

  if v_view is not null then
    v_norm := lower(regexp_replace(pg_get_viewdef(v_view), '\s+', ' ', 'g'));

    -- O CORACAO da regua: fato de banco, nao o texto do campo `erro`. Aquele
    -- campo e escrito pelo AGENTE e ja mandou duas investigacoes pro lado
    -- errado -- se um dia alguem trocar a regua por `erro ilike '%roster%'`,
    -- esta assercao cai.
    perform pg_temp.checar_sem_roster(
      'a regua e a ausencia de linha em aula_alunos_emusys',
      v_norm like '%aula_alunos_emusys%' and v_norm like '%not (exists%',
      substring(v_norm from 1 for 900)
    );
    perform pg_temp.checar_sem_roster(
      'a view NAO le o campo erro (texto de agente nao e regua)',
      v_norm not like '%f.erro%' and v_norm not like '%erro ~~%' and v_norm not like '%erro like%',
      substring(v_norm from 1 for 900)
    );
    perform pg_temp.checar_sem_roster(
      'a view respeita a fronteira do worker da experimental',
      v_norm like '%vinculo_id is null%',
      substring(v_norm from 1 for 900)
    );
    perform pg_temp.checar_sem_roster(
      'a view ancora no resolvedor operacional, nao no aula_id cru',
      v_norm like '%fn_aula_operacional_id%',
      substring(v_norm from 1 for 900)
    );
  end if;

  if v_retomar is not null then
    v_def := pg_get_functiondef(v_retomar);
    v_norm := lower(regexp_replace(v_def, '\s+', ' ', 'g'));
    perform pg_temp.checar_sem_roster(
      'a retomada grava audit_log antes de mexer na fila',
      v_norm like '%insert into public.audit_log%',
      substring(v_norm from 1 for 900)
    );
    perform pg_temp.checar_sem_roster(
      'a retomada dispara a edge (nao so marca pendente)',
      v_norm like '%fn_fabio_chama_edge%',
      substring(v_norm from 1 for 900)
    );
  end if;

  -- Porta fechada: isto e maquinario de worker.
  perform pg_temp.checar_sem_roster(
    'authenticated/anon nao executam as portas novas',
    not exists (
      select 1
        from pg_proc p
        join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public'
         and p.proname in ('fabio_fila_sem_roster_a_avisar', 'fn_fila_audio_retomar_por_roster')
         and (has_function_privilege('authenticated', p.oid, 'execute')
              or has_function_privilege('anon', p.oid, 'execute'))
    ),
    'execute publico'
  );
end
$function$;

-- Resumo do contrato de catalogo (execucao remota). O bloco Docker abaixo
-- fecha com o SEU proprio resumo: sem isso, o mutante leria este resumo aqui,
-- calculado ANTES das asercoes DML, e um mutante vivo passaria por morto.
select json_build_object(
  'falhas', (select count(*) from pg_temp._sem_roster_res where not ok),
  'detalhe', coalesce((
    select json_agg(json_build_object('passo', caso, 'esperado', 'true', 'obtido', detalhe) order by caso)
      from pg_temp._sem_roster_res where not ok
  ), '[]'::json)
) as resumo;

/* SEM-ROSTER-DOCKER-DML-TESTS-INICIO
-- Roda so no PostgreSQL efemero do mutante: aqui a selecao acontece de
-- verdade contra linhas reais, e cada mutante do fix precisa matar um caso.

do $docker$
declare
  v_unidade uuid := gen_random_uuid();
  v_vazia integer := 101;          -- turma sem nenhum aluno: o caso do prof 35
  v_com_roster integer := 102;     -- turma com aluno: nao e problema
  v_vazia_com_gemeo integer := 103;-- turma velha vazia, no MESMO slot de 106
  v_ja_registrada integer := 104;  -- sem aluno, mas o professor ja registrou na mao
  v_vai_ganhar_roster integer := 105;
  v_gemeo_com_roster integer := 106;
  f_vazia uuid; f_com_roster uuid; f_gemeo uuid; f_registrada uuid;
  f_experimental uuid; f_recente uuid; f_avisada uuid; f_terminal_outro uuid;
  v_avisados uuid[];
  v_retomados integer;
begin
  create or replace function public.fn_fabio_chama_edge(p_audio_id uuid)
  returns void language plpgsql as $noop$
  begin
    insert into pg_temp._sem_roster_disparados(id) values (p_audio_id);
  end $noop$;
  create temporary table if not exists pg_temp._sem_roster_disparados (id uuid);
  delete from pg_temp._sem_roster_disparados;

  insert into public.unidades(id, nome) values (v_unidade, 'Campo Grande');

  insert into public.aulas_emusys
    (id, professor_id, unidade_id, tipo, categoria, turma_nome, curso_nome,
     qtd_alunos, cancelada, data_hora_inicio, data_hora_fim)
  values
    -- Slots diferentes de proposito: so 103 e 106 dividem o MESMO slot, que e o
    -- unico par onde o resolvedor tem escolha a fazer.
    (v_vazia, 35, v_unidade, 'turma', 'normal', 'G_Seg_17', 'Guitarra T', 0, false,
     now() - interval '5 days' + interval '17 hours',
     now() - interval '5 days' + interval '17 hours 50 minutes'),
    (v_com_roster, 35, v_unidade, 'turma', 'normal', 'G_Seg_18', 'Guitarra T', 3, false,
     now() - interval '5 days' + interval '18 hours',
     now() - interval '5 days' + interval '18 hours 50 minutes'),
    (v_vazia_com_gemeo, 39, v_unidade, 'turma', 'normal', 'V_Ter_14_velha', 'Violao T', 0, false,
     now() - interval '5 days' + interval '14 hours',
     now() - interval '5 days' + interval '14 hours 50 minutes'),
    (v_gemeo_com_roster, 39, v_unidade, 'turma', 'normal', 'V_Ter_14', 'Violao T', 2, false,
     now() - interval '5 days' + interval '14 hours',
     now() - interval '5 days' + interval '14 hours 50 minutes'),
    (v_ja_registrada, 37, v_unidade, 'turma', 'normal', 'B_Qua_11', 'Bateria T', 0, false,
     now() - interval '5 days' + interval '11 hours',
     now() - interval '5 days' + interval '11 hours 50 minutes'),
    (v_vai_ganhar_roster, 38, v_unidade, 'turma', 'normal', 'P_Qui_12', 'Piano T', 0, false,
     now() - interval '4 days' + interval '9 hours',
     now() - interval '4 days' + interval '9 hours 50 minutes');

  insert into public.aula_alunos_emusys(aula_emusys_id, unidade_id, aluno_id)
  values (v_com_roster, v_unidade, 900),
         (v_gemeo_com_roster, v_unidade, 902);

  insert into public.fabio_registros_aula(aula_id, unidade_id, professor_id, parent_id, status)
  values (v_ja_registrada, v_unidade, 37, null, 'confirmado');

  -- 1. O caso do prof 35: turma vazia, erro terminal, ninguem avisou.
  insert into public.fabio_fila_audios
    (professor_id, unidade_id, aula_id, storage_path, status, origem, erro_tipo,
     tentativas, vinculo_id, criado_em, atualizado_em, transcricao)
  values (35, v_unidade, v_vazia, 'app/35/aula.webm', 'erro_terminal', 'app',
          'semantico_terminal', 46, null, now() - interval '5 days', now() - interval '5 days',
          'trabalhamos escala pentatonica')
  returning id into f_vazia;

  -- 2. Turma COM aluno parada por outro motivo: nao e deste aviso.
  insert into public.fabio_fila_audios
    (professor_id, unidade_id, aula_id, storage_path, status, origem, erro_tipo,
     tentativas, vinculo_id, criado_em, atualizado_em)
  values (35, v_unidade, v_com_roster, 'app/35/outra.webm', 'erro_terminal', 'app',
          'semantico_terminal', 3, null, now() - interval '5 days', now() - interval '5 days')
  returning id into f_com_roster;

  -- 3. Turma velha vazia com GEMEO com roster no mesmo slot: o resolvedor ja
  --    resolve isto sozinho (37 das 129 medidas em 15/08). Nao e assunto deste
  --    aviso -- se aparecer aqui, a view esta ancorando no aula_id cru.
  insert into public.fabio_fila_audios
    (professor_id, unidade_id, aula_id, storage_path, status, origem, erro_tipo,
     tentativas, vinculo_id, criado_em, atualizado_em)
  values (39, v_unidade, v_vazia_com_gemeo, 'app/39/gemeo.webm', 'erro_terminal', 'app',
          'semantico_terminal', 3, null, now() - interval '5 days', now() - interval '5 days')
  returning id into f_gemeo;

  -- 4. Ja registrada na mao: avisar agora seria ruido.
  insert into public.fabio_fila_audios
    (professor_id, unidade_id, aula_id, storage_path, status, origem, erro_tipo,
     tentativas, vinculo_id, criado_em, atualizado_em)
  values (37, v_unidade, v_ja_registrada, 'app/37/ja.webm', 'erro_terminal', 'app',
          'semantico_terminal', 3, null, now() - interval '5 days', now() - interval '5 days')
  returning id into f_registrada;

  -- 5. Experimental sobre turma vazia: tem worker e porta proprios.
  insert into public.fabio_fila_audios
    (professor_id, unidade_id, aula_id, storage_path, status, origem, erro_tipo,
     tentativas, vinculo_id, criado_em, atualizado_em)
  values (35, v_unidade, v_vazia, 'app/35/exp.webm', 'erro_terminal', 'app',
          'semantico_terminal', 3, 7777, now() - interval '5 days', now() - interval '5 days')
  returning id into f_experimental;

  -- 6. Falhou ha 2 minutos: a secretaria pode estar lancando a turma AGORA.
  insert into public.fabio_fila_audios
    (professor_id, unidade_id, aula_id, storage_path, status, origem, erro_tipo,
     tentativas, vinculo_id, criado_em, atualizado_em)
  values (35, v_unidade, v_vazia, 'app/35/agora.webm', 'erro', 'app',
          'transitorio', 1, null, now() - interval '10 minutes', now() - interval '2 minutes')
  returning id into f_recente;

  -- 7. Ja avisado e o roster APARECEU: e este que a retomada tem que religar.
  insert into public.fabio_fila_audios
    (professor_id, unidade_id, aula_id, storage_path, status, origem, erro_tipo,
     tentativas, vinculo_id, criado_em, atualizado_em, transcricao)
  values (38, v_unidade, v_vai_ganhar_roster, 'app/38/promessa.webm', 'erro_terminal', 'app',
          'semantico_terminal', 9, null, now() - interval '4 days', now() - interval '4 days',
          'revisamos a peca inteira')
  returning id into f_avisada;
  insert into public.fabio_notificacoes
    (professor_id, tipo, categoria, canal, corpo, referencia_tipo, referencia_id, status)
  values (38, 'registro_sem_roster', 'informativa', 'whatsapp', 'corpo',
          'fila_audio_sem_roster', f_avisada::text, 'enviada');

  -- 8. Terminal por OUTRO motivo semantico, aula com aluno, ninguem prometeu
  --    nada: religar isto seria religar as cegas -- vai morrer de novo.
  insert into public.fabio_fila_audios
    (professor_id, unidade_id, aula_id, storage_path, status, origem, erro_tipo,
     tentativas, vinculo_id, criado_em, atualizado_em)
  values (35, v_unidade, v_com_roster, 'app/35/outro-motivo.webm', 'erro_terminal', 'app',
          'semantico_terminal', 12, null, now() - interval '4 days', now() - interval '4 days')
  returning id into f_terminal_outro;

  -- ── Quem o professor precisa saber ────────────────────────────────────────
  select array_agg(fila_id) into v_avisados
    from public.fabio_fila_sem_roster_a_avisar(50, 30, 7);

  perform pg_temp.checar_sem_roster(
    'o audio morto por turma vazia entra no aviso (o caso do prof 35)',
    f_vazia = any(coalesce(v_avisados, '{}')),
    coalesce(array_to_string(v_avisados, ','), '<nenhum>'));

  perform pg_temp.checar_sem_roster(
    'aula COM aluno nao entra (o problema dela e outro)',
    not (f_com_roster = any(coalesce(v_avisados, '{}'))),
    coalesce(array_to_string(v_avisados, ','), '<nenhum>'));

  perform pg_temp.checar_sem_roster(
    'turma vazia com gemeo COM roster nao entra (o resolvedor ja salvou)',
    not (f_gemeo = any(coalesce(v_avisados, '{}'))),
    coalesce(array_to_string(v_avisados, ','), '<nenhum>'));

  perform pg_temp.checar_sem_roster(
    'aula ja registrada na mao nao gera ruido',
    not (f_registrada = any(coalesce(v_avisados, '{}'))),
    coalesce(array_to_string(v_avisados, ','), '<nenhum>'));

  perform pg_temp.checar_sem_roster(
    'experimental nao e roubada por este aviso',
    not (f_experimental = any(coalesce(v_avisados, '{}'))),
    coalesce(array_to_string(v_avisados, ','), '<nenhum>'));

  perform pg_temp.checar_sem_roster(
    'falha de 2 minutos espera a janela de folga',
    not (f_recente = any(coalesce(v_avisados, '{}'))),
    coalesce(array_to_string(v_avisados, ','), '<nenhum>'));

  perform pg_temp.checar_sem_roster(
    'quem ja recebeu o aviso nao recebe de novo',
    not (f_avisada = any(coalesce(v_avisados, '{}'))),
    coalesce(array_to_string(v_avisados, ','), '<nenhum>'));

  -- ── A promessa cumprida ───────────────────────────────────────────────────
  -- A secretaria lanca o aluno da turma do professor 38.
  insert into public.aula_alunos_emusys(aula_emusys_id, unidade_id, aluno_id)
  values (v_vai_ganhar_roster, v_unidade, 901);

  v_retomados := public.fn_fila_audio_retomar_por_roster(50);

  perform pg_temp.checar_sem_roster(
    'o audio prometido volta pra fila quando o roster aparece',
    (select status = 'pendente' and erro_tipo = 'transitorio' and tentativas = 0
       from public.fabio_fila_audios where id = f_avisada),
    (select status || '/' || erro_tipo || '/' || tentativas
       from public.fabio_fila_audios where id = f_avisada));

  perform pg_temp.checar_sem_roster(
    'a retomada dispara a edge (senao a linha so troca de cor)',
    exists (select 1 from pg_temp._sem_roster_disparados where id = f_avisada),
    coalesce((select string_agg(id::text, ',') from pg_temp._sem_roster_disparados), '<nenhum>'));

  perform pg_temp.checar_sem_roster(
    'a retomada deixa rastro no audit_log',
    exists (select 1 from public.audit_log
             where tabela = 'fabio_fila_audios'
               and registro_id_text = f_avisada::text
               and acao = 'retomada_por_roster'),
    'audit_log');

  perform pg_temp.checar_sem_roster(
    'terminal por outro motivo NAO e religado as cegas',
    (select status from public.fabio_fila_audios where id = f_terminal_outro) = 'erro_terminal',
    (select status from public.fabio_fila_audios where id = f_terminal_outro));

  perform pg_temp.checar_sem_roster(
    'a turma que continua vazia nao e religada',
    (select status from public.fabio_fila_audios where id = f_vazia) = 'erro_terminal',
    (select status from public.fabio_fila_audios where id = f_vazia));

  perform pg_temp.checar_sem_roster(
    'a retomada contou exatamente o que religou',
    v_retomados = 1,
    v_retomados::text);
end
$docker$;

select json_build_object(
  'falhas', (select count(*) from pg_temp._sem_roster_res where not ok),
  'detalhe', coalesce((
    select json_agg(json_build_object('passo', caso, 'esperado', 'true', 'obtido', detalhe) order by caso)
      from pg_temp._sem_roster_res where not ok
  ), '[]'::json)
) as resumo;
SEM-ROSTER-DOCKER-DML-TESTS-FIM */
