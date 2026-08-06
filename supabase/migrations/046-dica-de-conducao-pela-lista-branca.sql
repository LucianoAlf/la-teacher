-- 046 — a dica de conducao entra pela lista branca
--
-- A 045 abriu a chave `como_conduzir` no contrato da RPC, mas lendo do
-- contexto_ia CRU — era o unico campo daquela funcao que passava por fora da
-- lista branca da 028. Funcionava, e era exatamente o tipo de atalho que vira
-- buraco quando o campo deixa de ser uma string simples.
--
-- Agora ela entra em fn_experimental_contexto_seguro junto com os outros, com
-- `->>` forcando texto: se o LLM devolver objeto, ele vira string em vez de
-- atravessar com as chaves que resolveu inventar. Mesma defesa do campo a
-- campo dos alertas.
--
-- Quem GERA a dica e o extrator (supabase/functions/extrair-contexto-experimental),
-- que ja le a conversa da recepcao e ja produz ganchos_de_conexao "pra o
-- professor puxar na aula". A dica e a sintese disso em conduta.
--
-- Teste: 046-dica-de-conducao-pela-lista-branca.test.sql
-- Mutantes: scripts/mutantes-046.mjs

CREATE OR REPLACE FUNCTION public.fn_experimental_contexto_seguro(p_contexto jsonb)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  select case when p_contexto is null then null else
    jsonb_strip_nulls(jsonb_build_object(
      'recepcao', jsonb_build_object(
        'responsavel', p_contexto -> 'recepcao' ->> 'responsavel',
        'aluno',       p_contexto -> 'recepcao' ->> 'aluno',
        'junto_com',   p_contexto -> 'recepcao' ->> 'junto_com'),
      -- Idade SEMPRE calculada, nunca lida do texto: a observação da Isadora diz
      -- "6 meses" porque foi escrita em nov/2025. Ela entra AQUI dentro, e não
      -- como coluna solta da view, porque a 028 devolvia `idade` numa coluna que
      -- o prontuário nunca lia — o Fábio nunca recebeu essa idade.
      'idade', (select extract(year from age(current_date, d))::integer
                  from public.fn_texto_para_data(p_contexto -> 'recepcao' ->> 'data_nascimento') d
                 where d is not null),
      'quem_e_esse_aluno', jsonb_build_object(
        'nivel_declarado', p_contexto -> 'quem_e_esse_aluno' ->> 'nivel_declarado',
        'historia',        p_contexto -> 'quem_e_esse_aluno' ->> 'historia',
        'de_quem_partiu',  p_contexto -> 'quem_e_esse_aluno' ->> 'de_quem_partiu'),
      'ganchos_de_conexao', p_contexto -> 'ganchos_de_conexao',
      -- A dica de conducao entra AQUI, na lista branca que ja existe, e nao
      -- por um caminho proprio: duas listas brancas sobre o mesmo dado
      -- divergem no primeiro campo novo, e a que ninguem lembrou vira o
      -- vazamento.
      -- `->>` de proposito: forca TEXTO. Se o LLM devolver um objeto, ele
      -- vira string em vez de entrar com as chaves que ele resolveu inventar
      -- — a mesma razao do campo a campo dos alertas, logo abaixo.
      'como_conduzir', p_contexto ->> 'como_conduzir',
      'para_a_devolutiva', jsonb_build_object(
        'o_que_a_familia_espera', p_contexto -> 'para_a_devolutiva' ->> 'o_que_a_familia_espera',
        'atencao_conversao',      p_contexto -> 'para_a_devolutiva' ->> 'atencao_conversao'),
        -- `porque` fica de fora de propósito: é onde mora a frase sobre preço.
        -- O professor recebe o sinal, não o motivo financeiro.
      'apoio_declarado', p_contexto ->> 'apoio_declarado',
      -- Alerta também é lista de permissão, campo a campo. Passar o objeto cru
      -- abriria no meio da fronteira exatamente o buraco que ela existe para
      -- fechar: um objeto escrito por LLM, com as chaves que ele resolver
      -- inventar, indo inteiro para o professor.
      'alertas', (select jsonb_agg(jsonb_build_object('tipo',  al ->> 'tipo',
                                                      'texto', al ->> 'texto'))
                    from jsonb_array_elements(
                           case when jsonb_typeof(p_contexto -> 'alertas') = 'array'
                                then p_contexto -> 'alertas'
                                else '[]'::jsonb end) as al),
      'extraido_em', p_contexto -> 'procedencia' ->> 'extraido_em'
    )) end;
$function$;

CREATE OR REPLACE FUNCTION public.app_experimental_do_professor(p_vinculo_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_prof integer := public.fn_professor_do_usuario();
  v_out  jsonb;
begin
  if v_prof is null then
    raise exception 'sem_professor_vinculado';
  end if;

  select jsonb_build_object(
    'vinculo_id',            v.id,
    'lead_experimental_id',  le.id,
    'nome_aluno',            le.nome_aluno,
    'curso',                 coalesce(c.nome::text, ae.curso_nome::text, ae.turma_nome::text),
    'unidade_nome',          u.nome,
    'data_hora_inicio',      ae.data_hora_inicio,
    'hora',                  to_char(ae.data_hora_inicio at time zone 'America/Sao_Paulo','HH24:MI'),
    'estado',                v.estado,
    'presenca_status',       v.presenca_status,
    'presenca_e_forte',      public.fn_presenca_e_forte(v.presenca_respondido_por),

    -- Contexto pela MESMA lista branca da 028, menos o sinal comercial.
    -- `-` em jsonb remove a chave; se ela nunca vier, remover nao quebra.
    'contexto', (public.fn_experimental_contexto_seguro(le.contexto_ia)
                   #- '{para_a_devolutiva,atencao_conversao}'
                   #- '{como_conduzir}'),

    -- A dica de conducao. Ainda nao e gerada por ninguem — a chave existe pra
    -- a tela poder ser construida agora e o gerador plugar depois SEM mudar o
    -- contrato. Vem nula ate la, e nula a tela sabe esconder.
    -- Vem da lista branca, nao do contexto_ia cru: era o unico campo desta
    -- RPC que passava por fora dela. Sai do bloco `contexto` (acima) pra nao
    -- viver em dois lugares no mesmo payload.
    'como_conduzir', (public.fn_experimental_contexto_seguro(le.contexto_ia) ->> 'como_conduzir'),

    -- Se ja registrou, devolve o que ele escreveu — a tela reabre pra revisao
    -- em vez de comecar do zero e perder o trabalho.
    'registro', (
      select jsonb_build_object(
               'id',                   r.id,
               'status',               r.status,
               'anotacao_pedagogica',  r.anotacao_pedagogica,
               'devolutiva_familia',   r.devolutiva_familia,
               'proximos_passos',      r.proximos_passos,
               'leitura_de_conversao', r.leitura_de_conversao,
               'confirmado_em',        r.confirmado_em)
        from lead_experimental_registros r
       where r.vinculo_id = v.id and r.status <> 'descartado'
       order by r.criado_em desc limit 1)
  )
  into v_out
  from lead_experimental_aulas v
  join lead_experimentais le on le.id = v.lead_experimental_id
  join aulas_emusys ae       on ae.id = v.aula_local_id
  left join unidades u       on u.id  = le.unidade_id
  left join cursos c         on c.id  = le.curso_interesse_id
  -- A posse mora no JOIN, nao num if depois: aula de outro professor nao
  -- devolve linha, entao nao ha caminho em que o nome do lead escapa antes da
  -- checagem. E `= v_prof` (nao `is not distinct from`) porque aula sem
  -- professor existe em producao — com sessao tambem sem professor,
  -- `null is not distinct from null` daria TRUE e abriria a porta. Foi o
  -- buraco que a 035 expos e a 038 repetiu.
  where v.id = p_vinculo_id
    and ae.professor_id = v_prof;

  if v_out is null then
    raise exception 'experimental_nao_encontrada_ou_de_outro_professor';
  end if;

  return v_out;
end
$function$;
