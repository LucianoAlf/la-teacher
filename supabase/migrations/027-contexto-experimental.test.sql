-- Teste da 027 — colunas e guardas do contexto da experimental.
-- Rodar com: npm run teste:027
--
-- O runner abre a transação e dá ROLLBACK: nada do que este teste escreve
-- sobrevive.
--
-- ── Por que os casos são SEMEADOS ────────────────────────────────────────────
-- A primeira versão pegava "a primeira experimental futura" de produção e
-- escrevia nela. Isso ia quebrar sozinho: quando a extração de verdade rodar,
-- essa linha ganha um `contexto_ia` com id de mensagem do Chatwoot (muito maior
-- que os ids deste teste), a guarda de recência passa a recusar as gravações do
-- passo 4 em diante, e vários passos caem em cascata sem que nada tenha
-- regredido no código. Teste que depende de estado de produção que ele não
-- controla mede a produção, não o código. Aqui cada caso nasce dentro da
-- transação, com o estado exato que o passo precisa.

create temp table _falhas(passo text, esperado text, obtido text) on commit drop;
create function pg_temp.checar(p text, e text, o text) returns void language plpgsql as $c$
begin if e is distinct from o then insert into _falhas values (p, coalesce(e,'(null)'), coalesce(o,'(null)')); end if; end $c$;

do $t$
declare
  v_id integer;
  v_virgem integer;
  v_ok boolean;
  v_lido jsonb;
  v_unidade uuid;
  v_obs_antes text;
  v_base jsonb := jsonb_build_object(
    'recepcao', jsonb_build_object('responsavel','Melissa','aluno','Daniela',
                                   'data_nascimento','2013-07-25'),
    'quem_e_esse_aluno', jsonb_build_object('nivel_declarado','ja_tocava'),
    'ganchos_de_conexao', jsonb_build_array('ja se interessou por canto'),
    'procedencia', jsonb_build_object('ultima_mensagem_id','1000','modelo','gemini-3.6-flash')
  );
begin
  -- ===== 1/2. as colunas existem =====
  perform pg_temp.checar('1. coluna contexto_ia existe','true',
    (select exists(select 1 from information_schema.columns
       where table_schema='public' and table_name='lead_experimentais'
         and column_name='contexto_ia' and data_type='jsonb')::text));
  perform pg_temp.checar('2. coluna contexto_ia_em existe','true',
    (select exists(select 1 from information_schema.columns
       where table_schema='public' and table_name='lead_experimentais'
         and column_name='contexto_ia_em')::text));

  -- ===== 3. o caso de trabalho, semeado aqui =====
  -- `observacoes` recebe um valor conhecido de propósito: é ele que o passo 21
  -- compara para provar que o campo do Emusys não foi tocado.
  select unidade_id into v_unidade
    from public.lead_experimentais where unidade_id is not null limit 1;
  if v_unidade is null then
    insert into _falhas values ('3. setup','uma unidade para semear','nenhuma');
    return;
  end if;
  insert into public.lead_experimentais
    (nome_aluno, unidade_id, lead_id, data_experimental, observacoes)
  values ('Teste 027 guarda de gravacao', v_unidade, null, current_date + 2,
          'observacao escrita pelo Emusys')
  returning id into v_id;
  select observacoes into v_obs_antes from lead_experimentais where id = v_id;

  -- ===== 4. grava o que tem conteúdo =====
  v_ok := public.fabio_gravar_contexto_experimental(v_id, v_base);
  perform pg_temp.checar('4. grava contexto com conteudo','true', v_ok::text);
  select contexto_ia into v_lido from lead_experimentais where id = v_id;
  perform pg_temp.checar('5. e o conteudo esta la','ja_tocava',
    v_lido -> 'quem_e_esse_aluno' ->> 'nivel_declarado');
  perform pg_temp.checar('6. carimba contexto_ia_em','true',
    (select (contexto_ia_em is not null)::text from lead_experimentais where id=v_id));

  -- ===== 7/8. vazio NAO apaga o que ja existe =====
  -- O caso real: o Gemini falha ou a conversa nao tem nada. A extracao ruim
  -- nao pode passar por cima da boa.
  v_ok := public.fabio_gravar_contexto_experimental(v_id,
            jsonb_build_object('procedencia', jsonb_build_object('ultima_mensagem_id','9999')));
  perform pg_temp.checar('7. payload so com procedencia e recusado','false', v_ok::text);
  select contexto_ia into v_lido from lead_experimentais where id = v_id;
  perform pg_temp.checar('8. e o conteudo bom continua la','ja_tocava',
    v_lido -> 'quem_e_esse_aluno' ->> 'nivel_declarado');

  -- ===== 9/10. o ESQUELETO do schema é recusado =====
  -- O modo de falha mais provável de um LLM: devolver as chaves certas com
  -- tudo vazio, em vez de não devolver nada. A guarda antiga olhava só se a
  -- chave existia, então isto passava e apagava a extração boa.
  --
  -- O id 9999 é MAIS NOVO que o gravado (1000) de propósito: se fosse mais
  -- velho, a recusa poderia vir da guarda de recência e este passo passaria
  -- pelo motivo errado -- o mutante da guarda de conteúdo sobreviveria.
  v_ok := public.fabio_gravar_contexto_experimental(v_id, jsonb_build_object(
            'recepcao',          '{}'::jsonb,
            'quem_e_esse_aluno', '{}'::jsonb,
            'procedencia', jsonb_build_object('ultima_mensagem_id','9999')));
  perform pg_temp.checar('9. esqueleto de objetos vazios e recusado','false', v_ok::text);
  select contexto_ia into v_lido from lead_experimentais where id = v_id;
  perform pg_temp.checar('10. e o conteudo bom continua la depois do esqueleto','ja_tocava',
    v_lido -> 'quem_e_esse_aluno' ->> 'nivel_declarado');

  -- ===== 11/12. esqueleto com os CAMPOS preenchidos de nada =====
  -- Um nível mais fundo: as chaves internas existem, os valores é que são
  -- null/vazio. Tão inútil quanto o objeto vazio, e igualmente destrutivo.
  v_ok := public.fabio_gravar_contexto_experimental(v_id, jsonb_build_object(
            'recepcao',           jsonb_build_object('responsavel', null, 'aluno', null),
            'quem_e_esse_aluno',  jsonb_build_object('nivel_declarado', ''),
            'ganchos_de_conexao', '[]'::jsonb,
            'procedencia', jsonb_build_object('ultima_mensagem_id','9999')));
  perform pg_temp.checar('11. esqueleto com campos vazios e recusado','false', v_ok::text);
  select contexto_ia into v_lido from lead_experimentais where id = v_id;
  perform pg_temp.checar('12. e o conteudo bom continua la depois dos campos vazios','ja_tocava',
    v_lido -> 'quem_e_esse_aluno' ->> 'nivel_declarado');

  -- ===== 13. bloco que veio como string vazia =====
  perform pg_temp.checar('13. recepcao string vazia e recusada','false',
    public.fabio_gravar_contexto_experimental(v_id, jsonb_build_object(
      'recepcao', '',
      'procedencia', jsonb_build_object('ultima_mensagem_id','9999')))::text);

  -- ===== 14/15. null e nao-objeto sao recusados =====
  perform pg_temp.checar('14. null e recusado','false',
    public.fabio_gravar_contexto_experimental(v_id, null)::text);
  perform pg_temp.checar('15. array e recusado','false',
    public.fabio_gravar_contexto_experimental(v_id, '[]'::jsonb)::text);

  -- ===== 16. leitura mais VELHA nao sobrescreve =====
  v_ok := public.fabio_gravar_contexto_experimental(v_id,
            jsonb_set(v_base, '{procedencia,ultima_mensagem_id}', '"500"'));
  perform pg_temp.checar('16. mensagem mais velha e recusada','false', v_ok::text);

  -- ===== 17/18. leitura mais NOVA sobrescreve =====
  v_ok := public.fabio_gravar_contexto_experimental(v_id,
            jsonb_set(jsonb_set(v_base, '{procedencia,ultima_mensagem_id}', '"2000"'),
                      '{quem_e_esse_aluno,nivel_declarado}', '"iniciante"'));
  perform pg_temp.checar('17. mensagem mais nova grava','true', v_ok::text);
  select contexto_ia into v_lido from lead_experimentais where id = v_id;
  perform pg_temp.checar('18. e o valor foi atualizado','iniciante',
    v_lido -> 'quem_e_esse_aluno' ->> 'nivel_declarado');

  -- ===== 19. sem procedencia.ultima_mensagem_id e recusado =====
  perform pg_temp.checar('19. sem ultima_mensagem_id e recusado','false',
    public.fabio_gravar_contexto_experimental(v_id, v_base - 'procedencia')::text);

  -- ===== 20/21. e recusado TAMBEM na linha que ainda nao tem contexto =====
  -- O passo 19 sozinho nao prova nada: naquela linha ja existe um id gravado
  -- (2000), entao a guarda de RECENCIA recusaria o payload de qualquer jeito e
  -- o passo passaria mesmo sem a guarda de procedencia. Foi assim que o mutante
  -- "aceita payload sem procedencia" sobreviveu a primeira rodada.
  --
  -- A linha virgem e o caso que so a guarda de procedencia segura: sem id
  -- gravado, a recencia deixa passar. E o estrago e silencioso -- o contexto
  -- entra sem rastro de ate onde foi lido, extraido_ate_id fica NULL para
  -- sempre, e a edge function rele a conversa inteira toda rodada.
  insert into public.lead_experimentais
    (nome_aluno, unidade_id, lead_id, data_experimental)
  values ('Teste 027 linha virgem', v_unidade, null, current_date + 2)
  returning id into v_virgem;

  perform pg_temp.checar('20. sem ultima_mensagem_id e recusado em linha virgem','false',
    public.fabio_gravar_contexto_experimental(v_virgem, v_base - 'procedencia')::text);
  perform pg_temp.checar('21. e a linha virgem continua sem contexto','true',
    (select (contexto_ia is null)::text from lead_experimentais where id = v_virgem));

  -- ===== 22. id NAO-NUMERICO devolve false, nao levanta excecao =====
  -- `'abc'::bigint` estoura invalid_text_representation. Uma funcao que promete
  -- `returns boolean` nao pode quebrar o contrato porque o LLM escreveu bobagem
  -- no id -- a edge function receberia um erro, nao um "nao gravei".
  -- Se este passo levantar, o handler la embaixo registra 'excecao' e o teste
  -- reprova: e exatamente esse o sinal.
  perform pg_temp.checar('22. id nao-numerico e recusado sem excecao','false',
    public.fabio_gravar_contexto_experimental(v_id,
      jsonb_set(v_base, '{procedencia,ultima_mensagem_id}', '"abc"'))::text);

  -- ===== 23. o campo do Emusys NAO foi tocado =====
  -- A regra que nao pode ser afrouxada: observacoes tem dono. Compara com o
  -- valor capturado ANTES de qualquer chamada a fabio_gravar_contexto_experimental
  -- -- comparar a coluna com ela mesma no MESMO instante sempre daria "true".
  perform pg_temp.checar('23. observacoes intacto','true',
    (v_obs_antes is not distinct from
       (select observacoes from lead_experimentais where id=v_id))::text);

exception when others then
  insert into _falhas values ('excecao','sem excecao', sqlerrm);
end $t$;

-- ===== a selecao de quem extrair =====
do $t2$
declare
  v_n integer; v_sem_tel integer; v_unidade uuid; v_lead integer;
  v_com_ctx integer; v_sem_ctx integer; v_lixo integer;
  v_ate bigint; v_ok boolean;
  v_base jsonb := jsonb_build_object(
    'recepcao', jsonb_build_object('responsavel','Melissa','aluno','Daniela'),
    'quem_e_esse_aluno', jsonb_build_object('nivel_declarado','ja_tocava'),
    'procedencia', jsonb_build_object('ultima_mensagem_id','1000')
  );
begin
  select unidade_id into v_unidade
    from public.lead_experimentais where unidade_id is not null limit 1;
  select id into v_lead from public.leads
   where coalesce(nullif(btrim(whatsapp), ''), nullif(btrim(telefone), '')) is not null
   order by id limit 1;
  if v_unidade is null or v_lead is null then
    insert into _falhas values ('setup selecao','unidade + lead com telefone','faltou');
    return;
  end if;

  -- Caso de verdade para o passo 25: uma experimental na janela mas sem lead
  -- vinculado (logo sem telefone/whatsapp). Sem isso, o passo 25 roda sobre um
  -- conjunto que ja nasce sem ninguem sem telefone -- verificacao sobre
  -- conjunto vazio passa sempre, e foi exatamente o que deixou o mutante
  -- "selecao traz quem nao tem telefone" sobreviver na primeira rodada. A
  -- funcao correta CONTINUA filtrando essa linha; so o mutante que remove o
  -- filtro de telefone deixa ela vazar.
  insert into public.lead_experimentais (nome_aluno, unidade_id, lead_id, data_experimental)
  values ('Teste 027 sem telefone', v_unidade, null, current_date + 3);

  -- Tres casos COM telefone, cada um com um estado diferente de contexto_ia:
  -- gravado, ausente, e com lixo no id. Os tres precisam existir de verdade --
  -- e por isso cada passo abaixo confere primeiro que a linha APARECE na
  -- selecao antes de olhar o valor de extraido_ate_id.
  insert into public.lead_experimentais (nome_aluno, unidade_id, lead_id, data_experimental)
  values ('Teste 027 com contexto', v_unidade, v_lead, current_date + 2)
  returning id into v_com_ctx;

  insert into public.lead_experimentais (nome_aluno, unidade_id, lead_id, data_experimental)
  values ('Teste 027 sem contexto', v_unidade, v_lead, current_date + 2)
  returning id into v_sem_ctx;

  insert into public.lead_experimentais (nome_aluno, unidade_id, lead_id, data_experimental)
  values ('Teste 027 contexto com lixo', v_unidade, v_lead, current_date + 2)
  returning id into v_lixo;

  -- Lixo gravado DIRETO na coluna, de proposito: a guarda da funcao de
  -- gravacao recusaria isso. O que se mede aqui e a resiliencia da SELECAO a
  -- uma linha ja suja -- que pode chegar por outro caminho (import, correcao
  -- manual, versao anterior da edge function).
  update public.lead_experimentais
     set contexto_ia = jsonb_build_object('procedencia',
                         jsonb_build_object('ultima_mensagem_id','nao-e-numero'))
   where id = v_lixo;

  -- ===== 24. a selecao devolve linhas =====
  -- Roda DEPOIS da linha com lixo existir: se o cast voltar a ser cru, esta
  -- consulta levanta invalid_text_representation e derruba a selecao inteira.
  select count(*) into v_n from public.fn_experimentais_a_extrair(7, 50);
  perform pg_temp.checar('24. a selecao devolve linhas','true', (v_n > 0)::text);

  -- ninguem sem telefone: a edge function nao teria como buscar a conversa
  select count(*) into v_sem_tel from public.fn_experimentais_a_extrair(7, 50)
   where telefone is null or btrim(telefone) = '';
  perform pg_temp.checar('25. ninguem sem telefone','0', v_sem_tel::text);

  -- janela respeitada
  select count(*) into v_sem_tel from public.fn_experimentais_a_extrair(7, 50)
   where data_experimental < current_date or data_experimental > current_date + 7;
  perform pg_temp.checar('26. janela de 7 dias respeitada','0', v_sem_tel::text);

  -- p_dias=0 traz so hoje
  select count(*) into v_sem_tel from public.fn_experimentais_a_extrair(0, 50)
   where data_experimental <> current_date;
  perform pg_temp.checar('27. p_dias=0 traz so hoje','0', v_sem_tel::text);

  -- ===== 28..32. extraido_ate_id: o mecanismo da releitura =====
  -- E o campo que decide se a edge function relê a conversa inteira ou so o
  -- que chegou depois. Se ele voltar sempre NULL, a releitura vira integral
  -- para sempre e ninguem percebe -- nao ha erro, so desperdicio silencioso.
  v_ok := public.fabio_gravar_contexto_experimental(v_com_ctx,
            jsonb_set(v_base, '{procedencia,ultima_mensagem_id}', '"4242"'));
  perform pg_temp.checar('28. gravou o contexto do caso de releitura','true', v_ok::text);

  select count(*) into v_n from public.fn_experimentais_a_extrair(7, 50)
   where lead_experimental_id = v_com_ctx;
  perform pg_temp.checar('29. o caso com contexto aparece na selecao','1', v_n::text);
  select extraido_ate_id into v_ate from public.fn_experimentais_a_extrair(7, 50)
   where lead_experimental_id = v_com_ctx;
  perform pg_temp.checar('30. extraido_ate_id devolve o id da ultima mensagem lida','4242',
    coalesce(v_ate::text,'(null)'));

  -- o oposto: quem nunca foi extraido tem que vir NULL, senao a edge function
  -- pularia a leitura inicial. Sem este passo, um mutante que devolvesse uma
  -- constante passaria pelo passo 30.
  select count(*) into v_n from public.fn_experimentais_a_extrair(7, 50)
   where lead_experimental_id = v_sem_ctx;
  perform pg_temp.checar('31. o caso sem contexto aparece na selecao','1', v_n::text);
  select extraido_ate_id into v_ate from public.fn_experimentais_a_extrair(7, 50)
   where lead_experimental_id = v_sem_ctx;
  perform pg_temp.checar('32. sem contexto, extraido_ate_id vem null','(null)',
    coalesce(v_ate::text,'(null)'));

  -- ===== 33/34. id nao-numerico ja gravado nao derruba a selecao =====
  select count(*) into v_n from public.fn_experimentais_a_extrair(7, 50)
   where lead_experimental_id = v_lixo;
  perform pg_temp.checar('33. o caso com lixo aparece na selecao','1', v_n::text);
  select extraido_ate_id into v_ate from public.fn_experimentais_a_extrair(7, 50)
   where lead_experimental_id = v_lixo;
  perform pg_temp.checar('34. id nao-numerico vira null, nao excecao','(null)',
    coalesce(v_ate::text,'(null)'));

  -- ===== 35..40. ACL: quem NAO executa, e quem PRECISA executar =====
  -- O revoke e "from public, anon, authenticated". Conferir so o anon deixaria
  -- passar um mutante que removesse apenas `, authenticated` da lista -- e o
  -- Supabase concede EXECUTE explicitamente aos tres papeis por default, entao
  -- o revoke de public sozinho nao alcanca o authenticated.
  perform pg_temp.checar('35. anon nao executa a selecao','false',
    has_function_privilege('anon','public.fn_experimentais_a_extrair(integer,integer)','EXECUTE')::text);
  perform pg_temp.checar('36. anon nao executa a gravacao','false',
    has_function_privilege('anon','public.fabio_gravar_contexto_experimental(integer,jsonb)','EXECUTE')::text);
  perform pg_temp.checar('37. authenticated nao executa a selecao','false',
    has_function_privilege('authenticated','public.fn_experimentais_a_extrair(integer,integer)','EXECUTE')::text);
  perform pg_temp.checar('38. authenticated nao executa a gravacao','false',
    has_function_privilege('authenticated','public.fabio_gravar_contexto_experimental(integer,jsonb)','EXECUTE')::text);

  -- O positivo importa tanto quanto: um revoke que tirasse de todo mundo
  -- passaria nos quatro passos acima e deixaria a edge function sem acesso.
  perform pg_temp.checar('39. service_role executa a selecao','true',
    has_function_privilege('service_role','public.fn_experimentais_a_extrair(integer,integer)','EXECUTE')::text);
  perform pg_temp.checar('40. service_role executa a gravacao','true',
    has_function_privilege('service_role','public.fabio_gravar_contexto_experimental(integer,jsonb)','EXECUTE')::text);

exception when others then
  insert into _falhas values ('excecao selecao','sem excecao', sqlerrm);
end $t2$;

select json_build_object('teste','027-contexto-experimental',
  'falhas',(select count(*) from _falhas),
  'detalhe', coalesce((select json_agg(json_build_object('passo',passo,'esperado',esperado,'obtido',obtido)) from _falhas),'[]'::json)) as resumo;
