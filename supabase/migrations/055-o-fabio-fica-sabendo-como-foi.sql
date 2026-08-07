-- 055 — o Fábio fica sabendo como a experimental foi
--
-- ACHADO CONVERSANDO, não lendo código. Depois de fechar o ciclo inteiro do
-- Rafael — áudio gravado, quatro campos preenchidos, confirmado, WhatsApp
-- entregue no comercial — eu perguntei ao Fábio "como foi a experimental do
-- Rafael?" e ele respondeu:
--
--     "Não chegou pra mim nenhum relato do que aconteceu nela. Como foi?"
--
-- `fabio_experimentais_do_professor` devolve só o contexto de ANTES da aula.
-- Depois que ela acontece, o Fábio continua vendo a expectativa e nunca o
-- capítulo — e responde negando o que existe, que é o defeito que esta base já
-- me ensinou duas vezes: contexto ausente vira negativa afirmada.
--
-- O estrago não é só chato. O professor pergunta, ouve "não chegou nada", e
-- conclui que o registro não foi — podendo registrar de novo, o que dispara
-- uma CORREÇÃO pro comercial (048) sobre uma aula que já estava certa.
--
-- ── A FRONTEIRA, DE NOVO E UM ANDAR ACIMA ─────────────────────────────────
-- `leitura_de_conversao` NÃO vai. É o mesmo argumento da 049, com um agravante
-- de canal: no app ela mora atrás de um bloco âmbar com cadeado e o aviso "vai
-- só pro consultor — nunca pra família". No WhatsApp não existe bloco nenhum;
-- existe encaminhar. E ela não responde nada que a pergunta pedagógica pediu.
--
-- Os outros três vão: são o que o professor escreveu sobre a aula dele, e
-- negar isso a ele foi justamente o defeito.
--
-- A presença vai junto porque é a resposta mais curta pra "e aí, aconteceu?" —
-- e porque falta declarada (053) é informação que o Fábio precisa ter pra não
-- ficar perguntando de uma aula que não houve.
--
-- Gerado por extração (pg_get_functiondef): a função tem a guarda de posse da
-- 029 e o corte da 049, e transcrever à mão é como uma delas some.
--
-- Teste: 055-o-fabio-fica-sabendo-como-foi.test.sql
-- Mutantes: scripts/mutantes-055.mjs

CREATE OR REPLACE FUNCTION public.fabio_experimentais_do_professor(p_professor_id integer, p_dias integer DEFAULT 7)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_saida jsonb;
begin
  if p_professor_id is null then
    raise exception 'professor_id_obrigatorio: o Fabio so pode mostrar as experimentais DESTE professor.'
      using errcode = '42501';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'lead_experimental_id', e.lead_experimental_id,
           'nome_aluno',           e.nome_aluno,
           'primeiro_nome',        split_part(btrim(e.nome_aluno), ' ', 1),
           'data_experimental',    e.data_experimental,
           'horario',              to_char(e.horario_experimental, 'HH24:MI'),
           'curso',                e.curso,
           'ja_e_aluno',           (e.aluno_id is not null),
           'contexto',             (e.contexto #- '{para_a_devolutiva,atencao_conversao}'),
           -- Depois da aula: o que ele mesmo registrou. Sem isto o Fabio nega
           -- o capitulo que ajudou a escrever.
           'presenca',             v.presenca_status,
           'estado',               v.estado,
           'registro', case when r.id is null then null else jsonb_build_object(
             'status',              r.status,
             'confirmado',          (r.status = 'confirmado'),
             'veio_de_audio',       (r.audio_id is not null),
             'anotacao_pedagogica', r.anotacao_pedagogica,
             'devolutiva_familia',  r.devolutiva_familia,
             'proximos_passos',     r.proximos_passos
             -- leitura_de_conversao fica de fora. Ver cabecalho.
           ) end
         ) order by e.data_experimental, e.horario_experimental), '[]'::jsonb)
    into v_saida
    from vw_fabio_experimental_agendada e
    left join lead_experimental_aulas v
           on v.lead_experimental_id = e.lead_experimental_id
          and v.substituido_em is null
    left join lead_experimental_registros r
           on r.vinculo_id = v.id and r.status <> 'descartado'
   where e.professor_id = p_professor_id
     -- Fuso de Sao Paulo, como no extrator: `current_date` e UTC e às 21h ja
     -- descarta a experimental de hoje. Esse defeito ja custou uma rodada.
     and e.data_experimental between (now() at time zone 'America/Sao_Paulo')::date
                                 and (now() at time zone 'America/Sao_Paulo')::date + p_dias;

  return v_saida;
end
$function$;
