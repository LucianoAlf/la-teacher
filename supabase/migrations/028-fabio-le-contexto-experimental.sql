-- 028 — o Fábio passa a saber como o aluno chegou
--
-- A view é a FRONTEIRA: ela devolve chave por chave, da lista de permissão. Se
-- um dia o extrator gravar valor de mensalidade no JSON por engano, o campo não
-- atravessa — porque não está listado aqui.
--
-- Instrução em prompt não é fronteira. A notificar-anamnese tem "foque em
-- adaptação, não em rótulos de diagnóstico" escrito no prompt do Gemini e mesmo
-- assim manda diagnóstico cru para o WhatsApp do professor, porque a parte fixa
-- da mensagem não passa por IA nenhuma.

-- ─────────────────────────────────────────────────────────────────────────
-- Cast protegido de data, irmão do `fn_texto_para_bigint` da 027
--
-- `data_nascimento` chega como TEXTO dentro de um JSON escrito por um LLM. Um
-- cast cru (`::date`) levanta exceção — e numa VIEW isso não estraga só a linha
-- suja: derruba a consulta inteira, e ninguém mais tem contexto. É o mesmo
-- defeito que o mutante 10 da 027 pegou na seleção do extrator.
--
-- Duas famílias de lixo entram na mesma rede:
--   • `invalid_datetime_format`  — "6 meses", "não informado", "2013/07/25"
--   • `datetime_field_overflow`  — "2013-02-30", "2013-13-45": passam por
--     qualquer regex de formato e mesmo assim não são data nenhuma.
-- Lixo vira NULL, que é a resposta honesta: "não sei a idade".

create or replace function public.fn_texto_para_data(p_texto text)
returns date
language plpgsql
immutable
parallel safe
set search_path to 'public'
as $function$
begin
  return nullif(btrim(p_texto), '')::date;
exception when invalid_datetime_format or datetime_field_overflow then
  return null;
end
$function$;

revoke all on function public.fn_texto_para_data(text) from public, anon, authenticated;
grant execute on function public.fn_texto_para_data(text) to service_role;

comment on function public.fn_texto_para_data(text) is
'Cast text->date que devolve NULL em vez de levantar excecao. Existe porque data_nascimento vem de JSON de LLM e uma linha suja derrubaria a view inteira.';

-- ─────────────────────────────────────────────────────────────────────────
-- A fronteira

create or replace view public.vw_fabio_contexto_experimental as
 select l.aluno_id,
        le.id                     as lead_experimental_id,
        le.data_experimental,
        c.nome::text              as curso,
        -- idade SEMPRE calculada, nunca lida do texto. A observação da Isadora
        -- diz "6 meses" porque foi escrita em nov/2025; a aula é 15/08/2026 e
        -- ela tem 1 ano e 3 meses.
        case when public.fn_texto_para_data(le.contexto_ia -> 'recepcao' ->> 'data_nascimento') is not null
             then extract(year from age(current_date,
                    public.fn_texto_para_data(le.contexto_ia -> 'recepcao' ->> 'data_nascimento')))::integer
        end                       as idade,
        jsonb_strip_nulls(jsonb_build_object(
          'recepcao', jsonb_build_object(
            'responsavel', le.contexto_ia -> 'recepcao' ->> 'responsavel',
            'aluno',       le.contexto_ia -> 'recepcao' ->> 'aluno',
            'junto_com',   le.contexto_ia -> 'recepcao' ->> 'junto_com'),
          'quem_e_esse_aluno', jsonb_build_object(
            'nivel_declarado', le.contexto_ia -> 'quem_e_esse_aluno' ->> 'nivel_declarado',
            'historia',        le.contexto_ia -> 'quem_e_esse_aluno' ->> 'historia',
            'de_quem_partiu',  le.contexto_ia -> 'quem_e_esse_aluno' ->> 'de_quem_partiu'),
          'ganchos_de_conexao', le.contexto_ia -> 'ganchos_de_conexao',
          'para_a_devolutiva', jsonb_build_object(
            'o_que_a_familia_espera', le.contexto_ia -> 'para_a_devolutiva' ->> 'o_que_a_familia_espera',
            'atencao_conversao',      le.contexto_ia -> 'para_a_devolutiva' ->> 'atencao_conversao'),
            -- `porque` fica de fora de propósito: é onde mora a frase sobre
            -- preço. O professor recebe o sinal, não o motivo financeiro.
          'apoio_declarado', le.contexto_ia ->> 'apoio_declarado',
          -- Alerta também é lista de permissão, campo a campo. Passar o objeto
          -- cru abriria no meio da fronteira exatamente o buraco que ela existe
          -- para fechar: um objeto escrito por LLM, com as chaves que ele
          -- resolver inventar, indo inteiro para o professor.
          'alertas', (select jsonb_agg(jsonb_build_object('tipo',  al ->> 'tipo',
                                                          'texto', al ->> 'texto'))
                        from jsonb_array_elements(
                               case when jsonb_typeof(le.contexto_ia -> 'alertas') = 'array'
                                    then le.contexto_ia -> 'alertas'
                                    else '[]'::jsonb end) as al),
          'extraido_em',     le.contexto_ia -> 'procedencia' ->> 'extraido_em'
        ))                        as contexto
   from lead_experimentais le
   join leads l on l.id = le.lead_id      -- leads.aluno_id (319), NAO
                                          -- lead_experimentais.aluno_id (81)
   left join cursos c on c.id = le.curso_interesse_id
  where le.contexto_ia is not null
    and l.aluno_id is not null;

-- Sem isto a view nasce legível pelo `anon` e pelo `authenticated`: o
-- ALTER DEFAULT PRIVILEGES do projeto concede SELECT nos dois. `revoke from
-- public` sozinho não alcança nenhum deles. A porta é a função, não a view.
revoke all on table public.vw_fabio_contexto_experimental from public, anon, authenticated;
grant select on table public.vw_fabio_contexto_experimental to service_role;

comment on view public.vw_fabio_contexto_experimental is
'Contexto da experimental que o Fabio pode ver. Lista de permissao: dinheiro, negociacao e recado interno nao atravessam. Idade sempre calculada de data_nascimento.';

-- ─────────────────────────────────────────────────────────────────────────
-- O prontuário ganha o bloco `experimental`
--
-- A porta continua sendo a função, que recebe quem está perguntando e faz o
-- guard uma vez. View não recebe parâmetro: confiar no chamador filtrar foi
-- como o selo verde de presença mentiu por meses, e RLS não vale aqui porque o
-- bridge conecta com service_role.

create or replace function public.fabio_prontuario_aluno(
  p_aluno_id integer,
  p_professor_id integer,
  p_limite integer default 40
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_base jsonb;
  v_cadastro jsonb;
  v_experimental jsonb;
begin
  if p_professor_id is null then
    raise exception 'professor_id_obrigatorio: o Fabio fala com professor e so pode ler os cursos DELE com este aluno.'
      using errcode = '42501';
  end if;

  v_base := public.fn_prontuario_aluno_interno(p_aluno_id, p_professor_id, p_limite);

  select jsonb_build_object(
           'nome',                 k.aluno_nome,
           'primeiro_nome',        split_part(btrim(k.aluno_nome), ' ', 1),
           'curso',                k.curso_nome,
           'dia_aula',             k.dia_aula,
           'horario_aula',         k.horario_aula,
           'idade',                a.idade_atual,
           'responsavel_nome',     k.responsavel_nome,
           'data_matricula',       k.data_matricula,
           'dias_desde_matricula', k.dias_desde_matricula,
           'e_aluno_novo',         k.e_aluno_novo,
           'aulas_registradas',    k.aulas_registradas
         )
    into v_cadastro
    from vw_fabio_carteira_professor k
    join alunos a on a.id = k.aluno_id
   where k.aluno_id = p_aluno_id
     and k.professor_id = p_professor_id
   limit 1;

  -- Só entra se o aluno for da carteira DESTE professor. O guard de cima já
  -- garante isso, mas a checagem aqui evita que uma mudança futura no
  -- fn_prontuario_aluno_interno abra a porta sem ninguém notar.
  if v_cadastro is not null then
    select e.contexto || jsonb_build_object('data_experimental', e.data_experimental,
                                            'curso_experimental', e.curso)
      into v_experimental
      from vw_fabio_contexto_experimental e
     where e.aluno_id = p_aluno_id
     order by e.data_experimental desc
     limit 1;
  end if;

  return v_base
      || jsonb_build_object('cadastro',     coalesce(v_cadastro, '{}'::jsonb))
      || jsonb_build_object('experimental', coalesce(v_experimental, '{}'::jsonb));
end
$function$;

-- `create or replace` preserva o ACL que já existe (inclusive o EXECUTE do
-- fabio_agent). Reafirmar o revoke é barato e deixa a intenção no arquivo.
revoke all on function public.fabio_prontuario_aluno(integer, integer, integer) from public, anon, authenticated;
grant execute on function public.fabio_prontuario_aluno(integer, integer, integer) to service_role;

comment on function public.fabio_prontuario_aluno(integer, integer, integer) is
'Prontuario do aluno para o professor. Blocos: cadastro (026), experimental (028) e linha do tempo.';
