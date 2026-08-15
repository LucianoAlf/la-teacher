-- A experimental SEM ALUNO não entra pela porta do aluno — e não morre calada.
--
-- 15/08/2026. Cinco áudios de professor não viraram registro nenhum. O erro
-- gravado na fila dizia `normalizacao_invalida`, e a investigação inicial foi
-- atrás de "roster divergente" por causa de um texto no campo `erro` que
-- PARECIA diagnóstico do sistema — e era explicação inventada por um agente
-- (ver o conserto do `codigo` em `fabio_registro_aula_tool.py`).
--
-- A causa real, medida rodando `_buscar_roster_aula` no código vivo:
-- `qtd_contexto: 1, qtd_roster: 0`. Roster **vazio**, não divergente.
--
-- Por quê: aula experimental tem LEAD, não aluno. Em `aula_alunos_emusys` a
-- linha existe, com o nome, e `aluno_id` NULO — porque quem veio experimentar
-- ainda não é aluno. O contrato então recusa, e **recusar é o certo**: ele se
-- nega a inventar um `aluno_id`. O defeito nunca esteve no contrato.
--
-- O defeito é de ROTEAMENTO. A experimental tem porta própria
-- (`app_enfileirar_audio_experimental`, que recebe `vinculo_id`), e a agenda
-- tem duas entradas para a mesma linha:
--
--   clicar na LINHA      -> `abrirSessao` ramifica e vai pra porta certa
--   clicar no MICROFONE  -> `gravarAula` não ramificava: caía aqui, na porta
--                           do aluno, e o áudio morria em silêncio
--
-- Esta migration é a rede embaixo do conserto do cliente. Sem ela, professor
-- com bundle antigo em cache (é PWA) continuaria perdendo áudio por dias
-- depois do deploy.
--
-- POR QUE A GUARDA É `experimental` **E** `sem aluno`, e não só `experimental`:
--
-- Medido contra o histórico inteiro da fila (`vinculo_id is null`), antes de
-- escrever uma linha:
--
--   experimental · sem aluno · gerou registro?  NÃO  ->  5   (os fracassos)
--   experimental · com aluno · gerou registro?  SIM  ->  1   (funciona!)
--   normal       · sem aluno · gerou registro?  SIM  ->  1   (funciona!)
--
-- Uma experimental cujo lead já virou aluno passa por aqui e **funciona** —
-- bloquear por `categoria` sozinha quebraria esse caso. E existe aula normal
-- com `aula_alunos_emusys` vazia que mesmo assim gera registro, porque o tool
-- tem fallback pela carteira do professor; por isso a guarda **não** tenta
-- reimplementar a resolução de roster do contrato, que tem regra própria.
-- Ela mira só na interseção provadamente quebrada, com zero falso positivo
-- contra tudo que já aconteceu.
--
-- Fica aberto de propósito: aula NORMAL com roster vazio é outra investigação.
-- Não é esta.

create or replace function public.fn_enfileirar_audio_core(
  p_aula_id integer,
  p_storage_path text,
  p_duracao_segundos integer,
  p_registro_id uuid,
  p_origem text,
  p_professor_id integer
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $function$
declare
  v_aula public.aulas_emusys%rowtype;
  v_existente public.fabio_fila_audios%rowtype;
  v_fila_viva public.fabio_fila_audios%rowtype;
  v_rascunho public.fabio_registros_aula%rowtype;
  v_unidade uuid;
  v_id uuid;
  v_ja jsonb;
  v_qtd_ja integer := 0;
  v_storage_path text := nullif(btrim(p_storage_path), '');
begin
  if p_professor_id is null then raise exception 'sem_professor_vinculado'; end if;
  if p_origem not in ('app', 'whatsapp') then
    raise exception 'origem_invalida: %', p_origem;
  end if;
  if v_storage_path is null then
    raise exception 'storage_path obrigatorio';
  end if;

  select * into v_aula
    from public.aulas_emusys
   where id = public.fn_aula_operacional_id(p_aula_id);
  if not found then raise exception 'Aula % nao encontrada', p_aula_id; end if;
  p_aula_id := v_aula.id;
  if v_aula.professor_id is distinct from p_professor_id then
    raise exception 'aula_nao_pertence_ao_professor';
  end if;
  if coalesce(v_aula.cancelada, false) then raise exception 'aula_cancelada'; end if;

  -- A PORTA ERRADA. Experimental cujo lead ainda não virou aluno não tem em
  -- quem pendurar a fatia; aceitar aqui é aceitar para perder depois, calado.
  -- Recusar na entrada devolve o erro enquanto o professor ainda está na tela,
  -- em vez de deixá-lo esperando um resumo que nunca chega.
  if v_aula.categoria = 'experimental'
     and not exists (
       select 1
         from public.aula_alunos_emusys r
        where r.aula_emusys_id = p_aula_id
          and r.aluno_id is not null
     ) then
    raise exception 'aula_experimental_usa_porta_propria';
  end if;

  if v_aula.data_hora_inicio > now() + interval '15 minutes' then
    raise exception 'gravacao_ainda_nao_disponivel';
  end if;
  if coalesce(v_aula.data_hora_fim, v_aula.data_hora_inicio)
      < now() - (public.fn_janela_registro_dias() || ' days')::interval then
    raise exception 'janela_de_gravacao_encerrada';
  end if;

  v_unidade := v_aula.unidade_id;
  if p_registro_id is not null then
    perform 1 from public.fabio_registros_aula
     where id = p_registro_id and professor_id = p_professor_id
       and status in ('rascunho', 'aguardando_confirmacao');
    if not found then
      raise exception 'Registro % nao encontrado/permitido para complemento', p_registro_id;
    end if;
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'aluno_id', x.aluno_id, 'aluno_nome', x.nome, 'aula_id', x.aula_id,
           'registrado_em', x.criado_em, 'previa', left(x.texto, 120)
         ) order by x.nome), '[]'::jsonb), count(*)
    into v_ja, v_qtd_ja
  from (
    select distinct on (r.aluno_id)
           r.aluno_id, a.nome, alvo.id as aula_id,
           alvo.anotacoes_fabio as texto,
           (select max(l.criado_em) from public.aula_registros_fabio_log l
             where l.aula_id = alvo.id) as criado_em
      from public.aula_alunos_emusys r
      join public.alunos a on a.id = r.aluno_id
      join lateral (select ae2.* from public.aulas_emusys ae2
                     where ae2.id = public.fn_aula_individual_do_aluno(p_aula_id, r.aluno_id)) alvo on true
     where r.aula_emusys_id = p_aula_id
       and nullif(btrim(coalesce(alvo.anotacoes_fabio, '')), '') is not null
     order by r.aluno_id, alvo.id
  ) x;

  if p_registro_id is null then
    perform pg_advisory_xact_lock(hashtextextended(
      'fabio-fila-audio-aula:' || p_professor_id::text || ':' || p_aula_id::text, 0
    ));
  end if;

  -- A chave por path preserva a idempotencia de reenvio do mesmo blob. Para
  -- gravacoes novas, a chave adicional por aula serializa o bloqueio abaixo e
  -- impede duas filas com paths distintos na mesma aula.
  perform pg_advisory_xact_lock(hashtextextended(
    'fabio-fila-audio:' || p_professor_id::text || ':' || v_storage_path, 0
  ));
  select * into v_existente
    from public.fabio_fila_audios
   where professor_id = p_professor_id
     and storage_path = v_storage_path
   order by id
   limit 1;
  if found then
    if v_existente.aula_id is distinct from p_aula_id then
      raise exception 'storage_path_reutilizado_para_outra_aula';
    end if;
    return jsonb_build_object(
      'audio_id', v_existente.id,
      'status', v_existente.status,
      'modo', case when p_registro_id is null then 'novo' else 'complementar' end,
      'registro_id', p_registro_id,
      'deduplicado', true,
      'aula_ja_registrada', v_qtd_ja > 0,
      'ja_registrados', v_ja
    );
  end if;

  if p_registro_id is null then
    select * into v_fila_viva
      from public.fabio_fila_audios f
     where f.professor_id = p_professor_id
       and f.aula_id = p_aula_id
       and f.status in ('pendente', 'transcrevendo', 'transcrito', 'erro')
     order by f.criado_em, f.id
     limit 1;
    if found then
      return jsonb_build_object(
        'audio_id', v_fila_viva.id,
        'status', v_fila_viva.status,
        'modo', 'novo',
        'registro_id', null,
        'deduplicado', false,
        'ja_em_processamento', true,
        'aula_ja_registrada', v_qtd_ja > 0,
        'ja_registrados', v_ja
      );
    end if;

    -- So um rascunho de AUDIO retoma a confirmacao. A ficha manual e uma trilha
    -- separada e coexistente (ver app_abrir_rascunho_manual): ela nunca pode
    -- sequestrar e engolir uma nova gravacao por audio.
    select * into v_rascunho
      from public.fabio_registros_aula r
     where r.professor_id = p_professor_id
       and r.aula_id = p_aula_id
       and r.parent_id is null
       and r.modo_entrada = 'audio'
       and r.status in ('rascunho', 'aguardando_confirmacao')
     order by r.criado_em desc, r.id
     limit 1;
    if found then
      return jsonb_build_object(
        'modo', 'novo',
        'registro_id', v_rascunho.id,
        'deduplicado', false,
        'rascunho_existente', true,
        'aula_ja_registrada', v_qtd_ja > 0,
        'ja_registrados', v_ja
      );
    end if;
  end if;

  insert into public.fabio_fila_audios(
    professor_id, unidade_id, aula_id, storage_path, duracao_segundos, origem, status
  ) values (
    p_professor_id, v_unidade, p_aula_id, v_storage_path,
    p_duracao_segundos, p_origem, 'pendente'
  ) returning id into v_id;

  if p_registro_id is not null then
    update public.fabio_registros_aula
       set campos = campos || jsonb_build_object('audio_complemento_id', v_id)
     where id = p_registro_id;
  end if;

  return jsonb_build_object(
    'audio_id', v_id, 'status', 'pendente',
    'modo', case when p_registro_id is null then 'novo' else 'complementar' end,
    'registro_id', p_registro_id, 'deduplicado', false,
    'aula_ja_registrada', v_qtd_ja > 0,
    'ja_registrados', v_ja
  );
end
$function$;
