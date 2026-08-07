-- 050 — a fila de áudio aprende a rotear
--
-- O QUE ESTAVA PRA ACONTECER SE EU NÃO OLHASSE.
--
-- `fabio_fila_audios` tem um gatilho AFTER INSERT (`trg_fabio_fila_novo`) que
-- chama a edge do Hermes pra TODA linha `pendente`. Do outro lado, o agente
-- monta o registro pelo ROSTER da aula: busca os alunos, fatia a narração por
-- aluno, grava um tronco e as fatias.
--
-- A experimental não tem aluno. Ela tem um LEAD. O roster vem vazio.
--
-- Ou seja: bastava eu enfileirar o áudio da experimental pela RPC que já
-- existe — que aceitaria, porque a aula existe e é do professor — pro agente
-- receber um áudio pedagógico legítimo e não ter onde pendurar. Áudio gravado,
-- fila verde, e nada no lugar certo.
--
-- Então o roteamento nasce junto com o caminho: uma COLUNA, não um combinado.
-- `vinculo_id` preenchido = é experimental, o Hermes não é chamado, e quem
-- atende é o worker próprio (051). Coluna nula = tudo como sempre foi.
--
-- Roteamento por coluna é conferível numa consulta; roteamento por prompt eu
-- já vi ficar mudo sem levantar erro (o gatilho da bridge, ontem).
--
-- Teste: 050-fila-de-audio-aprende-a-rotear.test.sql
-- Mutantes: scripts/mutantes-050.mjs

-- ── 1) A coluna que roteia ──────────────────────────────────────────────────
alter table public.fabio_fila_audios
  add column if not exists vinculo_id bigint references public.lead_experimental_aulas(id);

comment on column public.fabio_fila_audios.vinculo_id is
  'Não nulo = áudio de aula EXPERIMENTAL. O gatilho não chama a edge do Hermes '
  '(o agente monta registro pelo roster de alunos, que a experimental não tem); '
  'quem atende é fabio_claim_audio_experimental. Nulo = aula comum, caminho de sempre.';

-- O worker varre por (vinculo_id not null, status). Índice parcial porque a
-- fatia experimental é minúscula perto da fila inteira.
create index if not exists ix_fabio_fila_audios_experimental
  on public.fabio_fila_audios (status, criado_em)
  where vinculo_id is not null;

-- ── 2) O gatilho passa a olhar pra quem é ───────────────────────────────────
create or replace function public.trg_fabio_fila_dispara()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  -- Só a aula comum vai pro Hermes. A experimental tem worker próprio, e
  -- mandar as duas pro mesmo lugar não dá erro: dá registro no lugar errado.
  if new.vinculo_id is null then
    perform public.fn_fabio_chama_edge(new.id);
  end if;
  return new;
end $function$;

-- ── 3) A porta do professor ─────────────────────────────────────────────────
create or replace function public.app_enfileirar_audio_experimental(
  p_vinculo_id       bigint,
  p_storage_path     text,
  p_duracao_segundos integer
) returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_prof    integer := public.fn_professor_do_usuario();
  v_vinculo record;
  v_aula    public.aulas_emusys%rowtype;
  v_id      uuid;
begin
  if v_prof is null then
    raise exception 'sem_professor_vinculado';
  end if;
  if p_storage_path is null or btrim(p_storage_path) = '' then
    raise exception 'storage_path obrigatório';
  end if;

  select v.id, v.estado, v.aula_local_id
    into v_vinculo
    from public.lead_experimental_aulas v
   where v.id = p_vinculo_id and v.substituido_em is null;

  if not found then
    raise exception 'vinculo_inexistente_ou_sem_aula: %', p_vinculo_id;
  end if;

  -- As MESMAS travas de estado do formulário (fn_registrar_experimental_interno).
  -- Falhar aqui é falhar antes: descobrir que a aula não aceita registro depois
  -- de o professor falar dois minutos é a pior hora possível.
  if v_vinculo.estado = 'pendente' then
    raise exception 'experimental_sem_aula_vinculada';
  elsif v_vinculo.estado = 'faltou' then
    raise exception 'experimental_faltou_nao_tem_registro';
  elsif v_vinculo.estado = 'cancelado' then
    raise exception 'experimental_cancelada';
  end if;

  select * into v_aula from public.aulas_emusys where id = v_vinculo.aula_local_id;
  if not found then
    raise exception 'vinculo_inexistente_ou_sem_aula: %', p_vinculo_id;
  end if;

  -- A posse mora aqui, e é `=` de propósito: com `is not distinct from`, aula
  -- órfã + professor órfão dariam null = null = verdadeiro, e a guarda abriria.
  if v_aula.professor_id is distinct from v_prof then
    raise exception 'aula_de_outro_professor';
  end if;
  if coalesce(v_aula.cancelada, false) then
    raise exception 'aula_cancelada';
  end if;
  if v_aula.data_hora_inicio > now() + interval '15 minutes' then
    raise exception 'gravacao_ainda_nao_disponivel';
  end if;
  if coalesce(v_aula.data_hora_fim, v_aula.data_hora_inicio) < now() - interval '3 days' then
    raise exception 'janela_de_gravacao_encerrada';
  end if;

  insert into public.fabio_fila_audios
    (professor_id, unidade_id, aula_id, vinculo_id, storage_path, duracao_segundos, origem, status)
  values
    (v_prof, v_aula.unidade_id, v_aula.id, p_vinculo_id, p_storage_path, p_duracao_segundos, 'app', 'pendente')
  returning id into v_id;

  return jsonb_build_object('audio_id', v_id, 'status', 'pendente', 'vinculo_id', p_vinculo_id);
end
$function$;

comment on function public.app_enfileirar_audio_experimental(bigint, text, integer) is
  'Enfileira o áudio de uma aula experimental. O professor nunca passa o próprio '
  'id: quem resolve é auth.uid(). Repete as travas de estado do formulário pra '
  'recusar ANTES da gravação, não depois.';

revoke all on function public.app_enfileirar_audio_experimental(bigint, text, integer) from public, anon;
grant execute on function public.app_enfileirar_audio_experimental(bigint, text, integer) to authenticated;
