-- 045 — o professor abre a experimental dele no app
--
-- Ate aqui o ciclo inteiro existia sem porta de entrada: eu provei o fim a fim
-- chamando as funcoes na mao. O Matheus nao tem tela porque nao ha RPC que o
-- app possa chamar.
--
-- REUSA a lista branca que ja existe (fn_experimental_contexto_seguro, da 028)
-- em vez de escrever outra. Duas listas brancas sobre o mesmo dado divergem no
-- primeiro campo novo, e a que ninguem lembrou vira o vazamento.
--
-- O QUE O PROFESSOR NAO VE: `atencao_conversao`.
-- A lista branca da 028 deixa passar, porque la o consumidor e o Fabio
-- montando a devolutiva. Aqui o consumidor e quem vai dar a aula — e saber que
-- "a familia esta quente" muda a aula, pro lado errado. O professor conduz
-- melhor sabendo que o menino gosta de batalha de rima; nao sabendo que a mae
-- ja perguntou o preco. Fronteira nova, e por isso tem mutante proprio.

create or replace function public.app_experimental_do_professor(
  p_vinculo_id bigint
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
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
                   #- '{para_a_devolutiva,atencao_conversao}'),

    -- A dica de conducao. Ainda nao e gerada por ninguem — a chave existe pra
    -- a tela poder ser construida agora e o gerador plugar depois SEM mudar o
    -- contrato. Vem nula ate la, e nula a tela sabe esconder.
    'como_conduzir',         le.contexto_ia -> 'como_conduzir',

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

revoke all on function public.app_experimental_do_professor(bigint) from public, anon;
grant execute on function public.app_experimental_do_professor(bigint) to service_role, authenticated;

comment on function public.app_experimental_do_professor(bigint) is
'A experimental como o professor dono dela ve: dados da aula, contexto pela lista branca da 028 SEM o sinal comercial (atencao_conversao), a dica de conducao e o registro em andamento. Aula de outro professor nao devolve linha.';
