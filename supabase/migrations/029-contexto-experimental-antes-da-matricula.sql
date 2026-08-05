-- 029 — o contexto da experimental só chegava DEPOIS da matrícula
--
-- Lead não é aluno. Aluno é quem matriculou. A experimental acontece ANTES da
-- matrícula — é ela que decide se vai haver matrícula. Mas a 028 pendurou a
-- entrega no `l.aluno_id is not null`, então o contexto só ficava visível
-- depois que já não servia para preparar a aula.
--
-- Medido em 05/08/2026: das 16 experimentais dos próximos 7 dias, UMA tinha
-- aluno_id. Quinze professores iam dar aula experimental sem enxergar um
-- contexto que já estava extraído e gravado.
--
-- A CHAVE ESTAVA NA PRÓPRIA TABELA: `lead_experimentais.professor_experimental_id`
-- está preenchido em 16 de 16. Quem vai dar a aula já é sabido, então o guard
-- não precisa de aluno nem de agenda — o professor da experimental É o dono
-- daquela experimental. Eu tinha suposto que isto dependia da experimental
-- aparecer na agenda (o emusys_aula_id); não depende.
--
-- Uso `coalesce(le.professor_experimental_id, l.professor_experimental_id)`
-- porque os dois divergem: no lead 1351 a experimental é do professor 55 e o
-- lead aponta 15. Quem manda é o da experimental — o do lead pode ser de outra
-- tentativa anterior.
--
-- ─────────────────────────────────────────────────────────────────────────
-- A FRONTEIRA VIRA FUNÇÃO, E ISSO É O PONTO MAIS IMPORTANTE DESTE ARQUIVO
--
-- Agora existem DUAS portas para o mesmo contexto (o aluno matriculado e o
-- lead pré-matrícula). Copiar a lista de permissão nas duas é como ela se abre
-- num lado e não no outro: alguém acrescenta um campo numa e esquece a outra, e
-- o vazamento nasce da divergência, não de uma decisão. Uma função só, usada
-- pelas duas.

create or replace function public.fn_experimental_contexto_seguro(p_contexto jsonb)
returns jsonb
language sql
stable
set search_path to 'public'
as $function$
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

revoke all on function public.fn_experimental_contexto_seguro(jsonb) from public, anon, authenticated;
grant execute on function public.fn_experimental_contexto_seguro(jsonb) to service_role, fabio_agent;

comment on function public.fn_experimental_contexto_seguro(jsonb) is
'Lista de permissao do contexto de experimental, em UM lugar so. Dinheiro, negociacao e recado interno nao atravessam. Usada pelas duas portas: aluno matriculado e lead pre-matricula.';

-- ─────────────────────────────────────────────────────────────────────────
-- A view antiga passa a usar a função (mesmas colunas, mesmo contrato)

create or replace view public.vw_fabio_contexto_experimental as
 select l.aluno_id,
        le.id                     as lead_experimental_id,
        le.data_experimental,
        c.nome::text              as curso,
        (public.fn_experimental_contexto_seguro(le.contexto_ia) ->> 'idade')::integer as idade,
        public.fn_experimental_contexto_seguro(le.contexto_ia) as contexto
   from lead_experimentais le
   join leads l on l.id = le.lead_id
   left join cursos c on c.id = le.curso_interesse_id
  where le.contexto_ia is not null
    and l.aluno_id is not null;

revoke all on table public.vw_fabio_contexto_experimental from public, anon, authenticated;
grant select on table public.vw_fabio_contexto_experimental to service_role;

-- ─────────────────────────────────────────────────────────────────────────
-- A porta nova: a experimental AGENDADA, do professor que vai dá-la

create or replace view public.vw_fabio_experimental_agendada as
 select coalesce(le.professor_experimental_id, l.professor_experimental_id) as professor_id,
        le.id                     as lead_experimental_id,
        le.nome_aluno::text       as nome_aluno,
        le.data_experimental,
        le.horario_experimental,
        c.nome::text              as curso,
        l.aluno_id,                          -- null enquanto for lead; vira id ao matricular
        public.fn_experimental_contexto_seguro(le.contexto_ia) as contexto
   from lead_experimentais le
   left join leads l on l.id = le.lead_id
   left join cursos c on c.id = le.curso_interesse_id
  where le.contexto_ia is not null
    -- Mesma lista de permissão de status do extrator (027c): o que não está
    -- agendado nem reagendado fica de fora. Cancelada não vira preparação de
    -- aula, e depois da aula quem manda é o registro do professor.
    and le.status in ('experimental_agendada', 'experimental_reagendada')
    and coalesce(le.professor_experimental_id, l.professor_experimental_id) is not null;

revoke all on table public.vw_fabio_experimental_agendada from public, anon, authenticated;
grant select on table public.vw_fabio_experimental_agendada to service_role;

comment on view public.vw_fabio_experimental_agendada is
'Experimentais agendadas com contexto extraido, por professor que vai dar a aula. Nao exige matricula: lead pre-matricula aparece aqui.';

-- ─────────────────────────────────────────────────────────────────────────
-- A RPC, que é a porta de verdade
--
-- View não recebe parâmetro, então não sabe quem está perguntando. Confiar no
-- chamador filtrar foi como o selo verde de presença mentiu por meses, e RLS
-- não vale aqui porque o bridge conecta com service_role. O guard mora na
-- função, e ela recusa em vez de devolver tudo quando o professor vem nulo.

create or replace function public.fabio_experimentais_do_professor(
  p_professor_id integer,
  p_dias         integer default 7
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
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
           'contexto',             e.contexto
         ) order by e.data_experimental, e.horario_experimental), '[]'::jsonb)
    into v_saida
    from vw_fabio_experimental_agendada e
   where e.professor_id = p_professor_id
     -- Fuso de Sao Paulo, como no extrator: `current_date` e UTC e às 21h ja
     -- descarta a experimental de hoje. Esse defeito ja custou uma rodada.
     and e.data_experimental between (now() at time zone 'America/Sao_Paulo')::date
                                 and (now() at time zone 'America/Sao_Paulo')::date + p_dias;

  return v_saida;
end
$function$;

revoke all on function public.fabio_experimentais_do_professor(integer, integer) from public, anon, authenticated;
grant execute on function public.fabio_experimentais_do_professor(integer, integer) to service_role, fabio_agent;

comment on function public.fabio_experimentais_do_professor(integer, integer) is
'Experimentais agendadas DESTE professor nos proximos p_dias, com o contexto ja filtrado pela fronteira. Funciona antes da matricula: e a porta do lead.';
