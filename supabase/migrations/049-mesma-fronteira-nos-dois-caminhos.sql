-- 049 — a mesma fronteira nos dois caminhos do professor
--
-- INCOERENCIA QUE EU CRIEI E ESTOU FECHANDO.
--
-- Na 045 eu tirei `atencao_conversao` da tela do professor, com o argumento de
-- que ele conduz melhor sabendo que a menina canta no chuveiro e conduz
-- DIFERENTE sabendo que a mae ja perguntou o preco.
--
-- So que o professor tem DOIS caminhos pro mesmo dado: a tela (045) e o Fabio
-- no WhatsApp (fabio_experimentais_do_professor). Eu mexi num e nao no outro.
-- Medido em 07/08/2026: a tela nao mostra o sinal, o Fabio mostra "alta".
-- Mesma pessoa, mesma aula, duas respostas — que e exatamente o defeito que a
-- lista branca unica existe pra evitar, aparecendo um andar acima dela.
--
-- Fronteira que vale num caminho e nao no outro nao e fronteira: e sorte de
-- por onde a pergunta entrou.
--
-- O `porque` (onde mora a frase do preco) ja era barrado pela 028 nos dois.
--
-- Teste: 049-mesma-fronteira-nos-dois-caminhos.test.sql
-- Mutantes: scripts/mutantes-049.mjs

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
           'contexto',             (e.contexto #- '{para_a_devolutiva,atencao_conversao}')
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
