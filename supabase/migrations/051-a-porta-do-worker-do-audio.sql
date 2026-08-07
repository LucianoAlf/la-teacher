-- 051 — a porta do worker do áudio da experimental
--
-- Três funções, uma tarefa cada: pegar da fila, gravar o resultado, e desistir
-- avisando. O worker que mora na VPS (fabio_audio_experimental_worker.py) não
-- escreve em tabela: ele só passa por estas portas.
--
-- ── Duas decisões que valem mais que o código ──────────────────────────────
--
-- 1. O CLAIM NÃO MANDA O CONTEXTO PEDAGÓGICO.
--    Seria fácil (e tentador) devolver o `contexto_ia` da experimental junto,
--    "pro modelo entender melhor". Mas o trabalho deste worker é registrar o
--    que o PROFESSOR disse — e um modelo com o briefing na mão preenche buraco
--    com o briefing. O nome e o curso bastam pra escrever em português; o
--    resto do texto tem que vir do áudio ou não vir.
--
-- 2. GRAVAR NÃO APAGA O QUE O PROFESSOR JÁ TINHA ESCRITO.
--    Campo que o áudio não cobriu fica como estava. Se ele digitou os quatro e
--    depois gravou falando só de como foi a aula, os outros três sobrevivem —
--    apagar seria a mesma perda de texto que a tela de registrar já toma o
--    cuidado de evitar ao reabrir.
--
-- A fila tem retomada: linha presa em `transcrevendo` há mais de 15 minutos
-- volta pro sorteio (o worker pode ter morrido no meio). Depois de 3 tentativas
-- ela vira `erro` e para de circular — fila que retenta pra sempre é fila que
-- nunca acusa problema.
--
-- Teste: 051-a-porta-do-worker-do-audio.test.sql
-- Mutantes: scripts/mutantes-051.mjs

-- ── 1) Pegar da fila ────────────────────────────────────────────────────────
create or replace function public.fabio_claim_audio_experimental(p_max integer default 1)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_out jsonb;
begin
  -- Antes de sortear: quem já gastou as três tentativas sai de circulação.
  -- Sem isto, um áudio que o transcritor nunca consegue ler ocupa a fila
  -- pra sempre e nada nunca aparece como quebrado.
  update public.fabio_fila_audios f
     set status = 'erro',
         erro   = coalesce(f.erro, 'tentativas_esgotadas')
   where f.vinculo_id is not null
     and f.status = 'transcrevendo'
     and f.tentativas >= 3
     and f.atualizado_em < now() - interval '15 minutes';

  with alvo as (
    select f.id
      from public.fabio_fila_audios f
     where f.vinculo_id is not null
       and (
         f.status = 'pendente'
         -- Retomada: o worker pode ter morrido com a linha na mão.
         or (f.status = 'transcrevendo' and f.atualizado_em < now() - interval '15 minutes')
       )
     order by f.criado_em
     limit greatest(coalesce(p_max, 1), 1)
     for update skip locked
  ), tomado as (
    update public.fabio_fila_audios f
       set status     = 'transcrevendo',
           tentativas = f.tentativas + 1
      from alvo
     where f.id = alvo.id
    returning f.*
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'audio_id',          t.id,
           'vinculo_id',        t.vinculo_id,
           'storage_path',      t.storage_path,
           'duracao_segundos',  t.duracao_segundos,
           'tentativa',         t.tentativas,
           'professor_id',      t.professor_id,
           'professor_nome',    p.nome,
           -- Só o suficiente pra escrever em português. O briefing pedagógico
           -- fica de fora de propósito (ver cabeçalho).
           'nome_aluno',        le.nome_aluno,
           'curso',             ae.curso_nome,
           -- O que já existe, pra o worker saber o que NÃO pode apagar.
           'ja_escrito', jsonb_build_object(
             'anotacao_pedagogica',  r.anotacao_pedagogica,
             'devolutiva_familia',   r.devolutiva_familia,
             'proximos_passos',      r.proximos_passos,
             'leitura_de_conversao', r.leitura_de_conversao)
         ) order by t.criado_em), '[]'::jsonb)
    into v_out
    from tomado t
    join public.lead_experimental_aulas v on v.id = t.vinculo_id
    join public.lead_experimentais le on le.id = v.lead_experimental_id
    left join public.aulas_emusys ae on ae.id = t.aula_id
    left join public.professores p on p.id = t.professor_id
    left join public.lead_experimental_registros r
           on r.vinculo_id = t.vinculo_id and r.status <> 'descartado';

  return v_out;
end
$function$;

comment on function public.fabio_claim_audio_experimental(integer) is
  'Fila do áudio da experimental. Marca transcrevendo, conta a tentativa, e '
  'devolve só o mínimo pro worker escrever em português — o contexto pedagógico '
  'NÃO vai junto de propósito: o registro tem que sair do que o professor falou.';

revoke all on function public.fabio_claim_audio_experimental(integer) from public, anon, authenticated;
grant execute on function public.fabio_claim_audio_experimental(integer) to service_role;

-- ── 2) Gravar o resultado ───────────────────────────────────────────────────
create or replace function public.fabio_gravar_registro_experimental_de_audio(
  p_audio_id    uuid,
  p_transcricao text,
  p_campos      jsonb
) returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_audio    public.fabio_fila_audios%rowtype;
  v_ja       public.lead_experimental_registros%rowtype;
  v_registro uuid;
  v_texto    text;
begin
  select * into v_audio from public.fabio_fila_audios where id = p_audio_id for update;
  if not found then
    raise exception 'audio_inexistente: %', p_audio_id;
  end if;
  if v_audio.vinculo_id is null then
    raise exception 'audio_nao_e_de_experimental: %', p_audio_id;
  end if;

  -- Auditoria (AGENTS.md): `normalizado` com transcrição nula é bug — a
  -- transcrição é a evidência do que o professor falou, e sem ela não dá pra
  -- conferir depois se o registro traduziu ou inventou.
  v_texto := nullif(btrim(coalesce(p_transcricao, '')), '');
  if v_texto is null then
    raise exception 'transcricao_obrigatoria';
  end if;

  select * into v_ja
    from public.lead_experimental_registros
   where vinculo_id = v_audio.vinculo_id and status <> 'descartado';

  -- Lista branca: só estes quatro campos entram, e cada um só sobrescreve se
  -- o áudio trouxe algo. Campo vazio preserva o que o professor digitou.
  select public.fn_registrar_experimental_interno(
           v_audio.vinculo_id,
           coalesce(nullif(btrim(coalesce(p_campos ->> 'anotacao_pedagogica',  '')), ''), v_ja.anotacao_pedagogica),
           coalesce(nullif(btrim(coalesce(p_campos ->> 'devolutiva_familia',   '')), ''), v_ja.devolutiva_familia),
           coalesce(nullif(btrim(coalesce(p_campos ->> 'proximos_passos',      '')), ''), v_ja.proximos_passos),
           coalesce(nullif(btrim(coalesce(p_campos ->> 'leitura_de_conversao', '')), ''), v_ja.leitura_de_conversao),
           'app')
    into v_registro;

  -- O carimbo do áudio é o que distingue "o Fábio organizou" de "eu digitei",
  -- e aponta pra evidência: `origem` só sabe dizer app/whatsapp.
  update public.lead_experimental_registros
     set audio_id = p_audio_id, atualizado_em = now()
   where id = v_registro;

  update public.fabio_fila_audios
     set status = 'normalizado', transcricao = v_texto, erro = null
   where id = p_audio_id;

  return jsonb_build_object(
    'registro_id', v_registro,
    'audio_id',    p_audio_id,
    'vinculo_id',  v_audio.vinculo_id,
    'status',      (select status from public.lead_experimental_registros where id = v_registro));
end
$function$;

comment on function public.fabio_gravar_registro_experimental_de_audio(uuid, text, jsonb) is
  'Grava os quatro campos vindos do áudio. Campo que o áudio não cobriu PRESERVA '
  'o que o professor já tinha escrito. Exige transcrição: normalizado sem '
  'evidência é bug de auditoria.';

revoke all on function public.fabio_gravar_registro_experimental_de_audio(uuid, text, jsonb) from public, anon, authenticated;
grant execute on function public.fabio_gravar_registro_experimental_de_audio(uuid, text, jsonb) to service_role;

-- ── 3) Desistir avisando ────────────────────────────────────────────────────
create or replace function public.fabio_falhou_audio_experimental(
  p_audio_id uuid,
  p_erro     text
) returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare v_novo text; v_tent integer;
begin
  select tentativas into v_tent from public.fabio_fila_audios
   where id = p_audio_id and vinculo_id is not null;
  if not found then
    raise exception 'audio_inexistente_ou_nao_e_de_experimental: %', p_audio_id;
  end if;

  -- Falha de rede merece outra chance; a terceira não. Voltar pra 'pendente'
  -- deixa o próximo ciclo pegar sem esperar os 15 minutos da retomada.
  v_novo := case when v_tent >= 3 then 'erro' else 'pendente' end;

  update public.fabio_fila_audios
     set status = v_novo, erro = left(coalesce(p_erro, 'sem_motivo'), 2000)
   where id = p_audio_id;

  return jsonb_build_object('audio_id', p_audio_id, 'status', v_novo, 'tentativas', v_tent);
end
$function$;

revoke all on function public.fabio_falhou_audio_experimental(uuid, text) from public, anon, authenticated;
grant execute on function public.fabio_falhou_audio_experimental(uuid, text) to service_role;
