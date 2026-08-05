-- Teste da 028 — a fronteira do contexto da experimental.
-- Rodar com: npm run teste:028
--
-- Hoje NÃO existe nenhum `contexto_ia` gravado em produção (o extrator roda em
-- modo sombra). Verificação sobre conjunto vazio passa sempre, então o ensaio
-- SEMEIA o contexto dentro da própria transação — que o runner descarta.

create temp table _falhas(passo text, esperado text, obtido text) on commit drop;
-- `_passos` existe porque verificacao sobre conjunto vazio passa sempre: se o
-- setup nao achar dado e sair pela porta dos fundos, o resumo diz "0 falhas".
-- O ultimo bloco confere que as 28 verificacoes REALMENTE rodaram.
create temp table _passos(passo text) on commit drop;
create function pg_temp.checar(p text, e text, o text) returns void language plpgsql as $c$
begin
  insert into _passos values (p);
  if e is distinct from o then insert into _falhas values (p, coalesce(e,'(null)'), coalesce(o,'(null)')); end if;
end $c$;

-- O alvo é escolhido pela MESMA consulta ordenada nos dois blocos: sem
-- `order by`, dois `limit 1` podem falar de alunos diferentes e o segundo bloco
-- testaria outra coisa sem ninguém perceber. O professor precisa de mais de um
-- aluno porque o passo 22 usa o segundo para provar que o bloco não vaza.
create function pg_temp.alvo() returns table(aluno_id integer, professor_id integer)
language sql stable as $a$
  select k.aluno_id, k.professor_id
    from vw_fabio_carteira_professor k
   where (select count(*) from vw_fabio_carteira_professor k2
           where k2.professor_id = k.professor_id) > 1
   order by k.professor_id, k.aluno_id
   limit 1;
$a$;

do $t$
declare
  v_le integer; v_lead integer; v_aluno integer; v_prof integer;
  v_ctx jsonb; v_idade integer;
begin
  -- ===== setup: um aluno de verdade, da carteira de um professor de verdade =====
  select a.aluno_id, a.professor_id into v_aluno, v_prof from pg_temp.alvo() a;
  if v_aluno is null then
    insert into _falhas values ('setup','um aluno na carteira','nenhum'); return;
  end if;

  -- Amarra esse aluno a um lead e a uma experimental que JÁ EXISTEM. Inserir uma
  -- experimental nova exigiria `unidade_id` (NOT NULL, sem default) e esbarraria
  -- em dois índices únicos parciais — trabalho para reproduzir o que já existe.
  select le.id, le.lead_id into v_le, v_lead
    from lead_experimentais le
    join leads l on l.id = le.lead_id
   order by le.id desc
   limit 1;
  if v_le is null then
    insert into _falhas values ('setup','uma experimental com lead','nenhuma'); return;
  end if;

  update leads set aluno_id = v_aluno where id = v_lead;

  -- Contexto COM lixo que não pode atravessar.
  -- `aluno_id` da experimental fica NULL de propósito: é o caso da maioria (238
  -- de 319). O vínculo que a view usa é `leads.aluno_id`.
  update lead_experimentais
     set aluno_id = null,
         contexto_ia = jsonb_build_object(
       -- `idade_declarada` e a idade que valia quando a conversa aconteceu, e e
       -- um numero redondo de propósito: se a view ler dali, ela responde 1 em
       -- vez de 13 -- erra o VALOR, sem levantar excecao nenhuma. Idade errada
       -- que nao reclama e pior que idade que explode.
       'recepcao', jsonb_build_object('responsavel','Melissa','aluno','Daniela',
                                      'data_nascimento','2013-07-25',
                                      'idade_declarada','1'),
       'quem_e_esse_aluno', jsonb_build_object('nivel_declarado','ja_tocava',
                                               'historia','Tocava piano em Portugal'),
       'ganchos_de_conexao', jsonb_build_array('gosta de canto'),
       'para_a_devolutiva', jsonb_build_object('atencao_conversao','alta',
                                               'porque','perguntou o preco tres vezes'),
       'alertas', jsonb_build_array(jsonb_build_object('tipo','agenda','texto','cancelou 04/08',
                                                      'valor_negociado','R$ 380')),
       'valor_mensalidade', 'R$ 450',
       'observacao_interna', 'ajustar data de nascimento, lancamento ficticio',
       'procedencia', jsonb_build_object('ultima_mensagem_id','1','extraido_em','2026-08-04T20:00:00Z'))
   where id = v_le;

  select contexto, idade into v_ctx, v_idade
    from vw_fabio_contexto_experimental where lead_experimental_id = v_le;

  -- ===== o util atravessa =====
  perform pg_temp.checar('1. traz o nivel','ja_tocava',
    v_ctx -> 'quem_e_esse_aluno' ->> 'nivel_declarado');
  perform pg_temp.checar('2. traz o responsavel','Melissa',
    v_ctx -> 'recepcao' ->> 'responsavel');
  perform pg_temp.checar('3. traz o gancho','true',
    (jsonb_array_length(v_ctx -> 'ganchos_de_conexao') = 1)::text);
  perform pg_temp.checar('4. traz o alerta de agenda','agenda',
    v_ctx -> 'alertas' -> 0 ->> 'tipo');
  perform pg_temp.checar('5. traz o texto do alerta','cancelou 04/08',
    v_ctx -> 'alertas' -> 0 ->> 'texto');
  perform pg_temp.checar('6. traz o sinal de conversao','alta',
    v_ctx -> 'para_a_devolutiva' ->> 'atencao_conversao');

  -- ===== o que NAO pode atravessar =====
  perform pg_temp.checar('7. valor de mensalidade NAO atravessa','false',
    (v_ctx ? 'valor_mensalidade')::text);
  perform pg_temp.checar('8. observacao interna NAO atravessa','false',
    (v_ctx ? 'observacao_interna')::text);
  perform pg_temp.checar('9. o PORQUE do sinal de conversao NAO atravessa','false',
    (v_ctx -> 'para_a_devolutiva' ? 'porque')::text);
  perform pg_temp.checar('10. data_nascimento crua NAO atravessa','false',
    (v_ctx -> 'recepcao' ? 'data_nascimento')::text);
  perform pg_temp.checar('11. idade declarada em texto NAO atravessa','false',
    (v_ctx -> 'recepcao' ? 'idade_declarada')::text);
  -- Alerta é objeto escrito por LLM: se o objeto passar cru, qualquer chave que
  -- ele inventar entra junto. A fronteira vale DENTRO do alerta também.
  perform pg_temp.checar('12. chave estranha dentro do alerta NAO atravessa','false',
    (v_ctx -> 'alertas' -> 0 ? 'valor_negociado')::text);

  -- ===== a idade e CALCULADA =====
  -- O JSON tem 'idade_declarada' = "1 ano" (o texto envelhecido). A view tem que
  -- responder a idade da DATA, nao a do texto.
  perform pg_temp.checar('13. idade calculada da data, nao do texto',
    extract(year from age(current_date, date '2013-07-25'))::integer::text, v_idade::text);

  -- ===== data invalida nao quebra a view =====
  update lead_experimentais
     set contexto_ia = jsonb_set(contexto_ia, '{recepcao,data_nascimento}', '"6 meses"')
   where id = v_le;
  select idade into v_idade from vw_fabio_contexto_experimental where lead_experimental_id = v_le;
  perform pg_temp.checar('14. texto no lugar da data vira null, nao explode','(null)',
    coalesce(v_idade::text,'(null)'));

  -- Formato certo, data que nao existe. Passa por qualquer regex e mesmo assim
  -- derrubaria a view inteira num cast cru -- e a view inteira e todo mundo.
  update lead_experimentais
     set contexto_ia = jsonb_set(contexto_ia, '{recepcao,data_nascimento}', '"2013-02-30"')
   where id = v_le;
  select idade into v_idade from vw_fabio_contexto_experimental where lead_experimental_id = v_le;
  perform pg_temp.checar('15. data impossivel tambem vira null, nao explode','(null)',
    coalesce(v_idade::text,'(null)'));

  -- devolve a data boa para o bloco do prontuario
  update lead_experimentais
     set contexto_ia = jsonb_set(contexto_ia, '{recepcao,data_nascimento}', '"2013-07-25"')
   where id = v_le;

exception when others then
  insert into _falhas values ('excecao','sem excecao', sqlerrm);
end $t$;

select json_build_object('teste','028-fronteira',
  'falhas',(select count(*) from _falhas),
  'detalhe', coalesce((select json_agg(json_build_object('passo',passo,'esperado',esperado,'obtido',obtido)) from _falhas),'[]'::json)) as resumo;

-- ===== o prontuario compoe o bloco =====
do $t2$
declare
  v_aluno integer; v_prof integer; v_outro integer; v_aluno2 integer; v_p jsonb;
  v_barrado text := 'nao';
begin
  select a.aluno_id, a.professor_id into v_aluno, v_prof from pg_temp.alvo() a;

  v_p := public.fabio_prontuario_aluno(v_aluno, v_prof, 5);
  perform pg_temp.checar('16. prontuario traz a chave experimental','true', (v_p ? 'experimental')::text);
  perform pg_temp.checar('17. e continua trazendo cadastro','true', (v_p ? 'cadastro')::text);
  perform pg_temp.checar('18. e a linha do tempo','true', (v_p ? 'linha_do_tempo')::text);
  -- A chave existir nao prova nada: `coalesce(..., '{}')` sempre cria a chave.
  -- O que prova e o conteudo do aluno certo estar la dentro.
  perform pg_temp.checar('19. o bloco experimental e o DESTE aluno','Melissa',
    v_p -> 'experimental' -> 'recepcao' ->> 'responsavel');
  perform pg_temp.checar('20. dinheiro NAO atravessa no prontuario','false',
    (v_p -> 'experimental' ? 'valor_mensalidade')::text);

  -- aluno de OUTRO professor continua barrado
  select k.professor_id into v_outro
    from vw_fabio_carteira_professor k
   where k.professor_id <> v_prof
     and not exists (
       select 1
         from vw_jornada_professor_atual j
         join alunos a2 on a2.id = j.aluno_id
         join alunos a1 on a1.id = v_aluno
        where j.professor_id = k.professor_id
          and (j.aluno_id = v_aluno
               or (a1.emusys_student_id is not null
                   and a2.unidade_id = a1.unidade_id
                   and a2.emusys_student_id = a1.emusys_student_id)))
   order by k.professor_id
   limit 1;
  if v_outro is null then
    insert into _falhas values ('21. aluno de outro professor barrado','um professor sem esse aluno','nenhum');
  else
    begin
      perform public.fabio_prontuario_aluno(v_aluno, v_outro, 5);
    exception when others then v_barrado := 'sim';
    end;
    perform pg_temp.checar('21. aluno de outro professor barrado','sim', v_barrado);
  end if;

  -- O bloco tem que ser DO aluno perguntado. Sem o filtro, o contexto de uma
  -- familia chega no prontuario de outra -- silenciosamente, porque o professor
  -- nao tem como saber que aquilo nao e do aluno dele.
  select k.aluno_id into v_aluno2
    from vw_fabio_carteira_professor k
   where k.professor_id = v_prof
     and k.aluno_id <> v_aluno
     and exists (select 1 from vw_jornada_professor_atual j
                  where j.professor_id = v_prof and j.aluno_id = k.aluno_id)
   order by k.aluno_id
   limit 1;
  if v_aluno2 is null then
    insert into _falhas values ('22. aluno sem experimental recebe bloco vazio','um segundo aluno do professor','nenhum');
  else
    v_p := public.fabio_prontuario_aluno(v_aluno2, v_prof, 5);
    perform pg_temp.checar('22. aluno sem experimental recebe bloco vazio','{}',
      (v_p -> 'experimental')::text);
  end if;

exception when others then
  insert into _falhas values ('excecao prontuario','sem excecao', sqlerrm);
end $t2$;

select json_build_object('teste','028-prontuario-com-experimental',
  'falhas',(select count(*) from _falhas),
  'detalhe', coalesce((select json_agg(json_build_object('passo',passo,'esperado',esperado,'obtido',obtido)) from _falhas),'[]'::json)) as resumo;

-- ===== a porta e a funcao, nao a view =====
do $t3$
begin
  -- O ALTER DEFAULT PRIVILEGES do projeto concede SELECT em view nova para anon
  -- E para authenticated. Conferir so o anon deixaria passar um mutante que
  -- removesse apenas `, authenticated` do revoke -- e o revoke de `public`
  -- sozinho nao alcanca nenhum dos dois.
  perform pg_temp.checar('23. anon nao le a view','false',
    has_table_privilege('anon','public.vw_fabio_contexto_experimental','SELECT')::text);
  perform pg_temp.checar('24. authenticated nao le a view','false',
    has_table_privilege('authenticated','public.vw_fabio_contexto_experimental','SELECT')::text);
  perform pg_temp.checar('25. service_role le a view','true',
    has_table_privilege('service_role','public.vw_fabio_contexto_experimental','SELECT')::text);

  perform pg_temp.checar('26. anon nao executa o prontuario','false',
    has_function_privilege('anon','public.fabio_prontuario_aluno(integer,integer,integer)','EXECUTE')::text);
  perform pg_temp.checar('27. authenticated nao executa o prontuario','false',
    has_function_privilege('authenticated','public.fabio_prontuario_aluno(integer,integer,integer)','EXECUTE')::text);
  perform pg_temp.checar('28. service_role executa o prontuario','true',
    has_function_privilege('service_role','public.fabio_prontuario_aluno(integer,integer,integer)','EXECUTE')::text);

exception when others then
  insert into _falhas values ('excecao acl','sem excecao', sqlerrm);
end $t3$;

-- ===== o teste tem que ter RODADO =====
do $t4$
declare v_n integer;
begin
  select count(*) into v_n from _passos;
  if v_n <> 28 then
    insert into _falhas values ('cobertura: as 28 verificacoes rodaram','28', v_n::text);
  end if;
end $t4$;

select json_build_object('teste','028-fronteira-fechada',
  'falhas',(select count(*) from _falhas),
  'detalhe', coalesce((select json_agg(json_build_object('passo',passo,'esperado',esperado,'obtido',obtido)) from _falhas),'[]'::json)) as resumo;
