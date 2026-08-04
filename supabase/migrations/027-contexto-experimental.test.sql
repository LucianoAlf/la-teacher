-- Teste da 027 — colunas e guardas do contexto da experimental.
-- Rodar com: npm run teste:027
--
-- O runner abre a transação e dá ROLLBACK: nada do que este teste escreve
-- sobrevive.

create temp table _falhas(passo text, esperado text, obtido text) on commit drop;
create function pg_temp.checar(p text, e text, o text) returns void language plpgsql as $c$
begin if e is distinct from o then insert into _falhas values (p, coalesce(e,'(null)'), coalesce(o,'(null)')); end if; end $c$;

do $t$
declare
  v_id integer;
  v_ok boolean;
  v_lido jsonb;
  v_obs_antes text;
  v_base jsonb := jsonb_build_object(
    'recepcao', jsonb_build_object('responsavel','Melissa','aluno','Daniela',
                                   'data_nascimento','2013-07-25'),
    'quem_e_esse_aluno', jsonb_build_object('nivel_declarado','ja_tocava'),
    'ganchos_de_conexao', jsonb_build_array('ja se interessou por canto'),
    'procedencia', jsonb_build_object('ultima_mensagem_id','1000','modelo','gemini-3.6-flash')
  );
begin
  -- ===== 1. as colunas existem =====
  perform pg_temp.checar('1. coluna contexto_ia existe','true',
    (select exists(select 1 from information_schema.columns
       where table_schema='public' and table_name='lead_experimentais'
         and column_name='contexto_ia' and data_type='jsonb')::text));
  perform pg_temp.checar('2. coluna contexto_ia_em existe','true',
    (select exists(select 1 from information_schema.columns
       where table_schema='public' and table_name='lead_experimentais'
         and column_name='contexto_ia_em')::text));

  -- ===== 3. um caso real para trabalhar =====
  select id into v_id from lead_experimentais
   where data_experimental >= current_date order by id limit 1;
  if v_id is null then
    insert into _falhas values ('3. setup','uma experimental futura','nenhuma');
    return;
  end if;
  select observacoes into v_obs_antes from lead_experimentais where id = v_id;

  -- ===== 4. grava o que tem conteúdo =====
  v_ok := public.fabio_gravar_contexto_experimental(v_id, v_base);
  perform pg_temp.checar('4. grava contexto com conteudo','true', v_ok::text);
  select contexto_ia into v_lido from lead_experimentais where id = v_id;
  perform pg_temp.checar('5. e o conteudo esta la','ja_tocava',
    v_lido -> 'quem_e_esse_aluno' ->> 'nivel_declarado');
  perform pg_temp.checar('6. carimba contexto_ia_em','true',
    (select (contexto_ia_em is not null)::text from lead_experimentais where id=v_id));

  -- ===== 7. vazio NAO apaga o que ja existe =====
  -- O caso real: o Gemini falha ou a conversa nao tem nada. A extracao ruim
  -- nao pode passar por cima da boa.
  v_ok := public.fabio_gravar_contexto_experimental(v_id,
            jsonb_build_object('procedencia', jsonb_build_object('ultima_mensagem_id','9999')));
  perform pg_temp.checar('7. payload so com procedencia e recusado','false', v_ok::text);
  select contexto_ia into v_lido from lead_experimentais where id = v_id;
  perform pg_temp.checar('8. e o conteudo bom continua la','ja_tocava',
    v_lido -> 'quem_e_esse_aluno' ->> 'nivel_declarado');

  -- ===== 9. null e nao-objeto sao recusados =====
  perform pg_temp.checar('9. null e recusado','false',
    public.fabio_gravar_contexto_experimental(v_id, null)::text);
  perform pg_temp.checar('10. array e recusado','false',
    public.fabio_gravar_contexto_experimental(v_id, '[]'::jsonb)::text);

  -- ===== 11. leitura mais VELHA nao sobrescreve =====
  v_ok := public.fabio_gravar_contexto_experimental(v_id,
            jsonb_set(v_base, '{procedencia,ultima_mensagem_id}', '"500"'));
  perform pg_temp.checar('11. mensagem mais velha e recusada','false', v_ok::text);

  -- ===== 12. leitura mais NOVA sobrescreve =====
  v_ok := public.fabio_gravar_contexto_experimental(v_id,
            jsonb_set(jsonb_set(v_base, '{procedencia,ultima_mensagem_id}', '"2000"'),
                      '{quem_e_esse_aluno,nivel_declarado}', '"iniciante"'));
  perform pg_temp.checar('12. mensagem mais nova grava','true', v_ok::text);
  select contexto_ia into v_lido from lead_experimentais where id = v_id;
  perform pg_temp.checar('13. e o valor foi atualizado','iniciante',
    v_lido -> 'quem_e_esse_aluno' ->> 'nivel_declarado');

  -- ===== 14. sem procedencia.ultima_mensagem_id e recusado =====
  perform pg_temp.checar('14. sem ultima_mensagem_id e recusado','false',
    public.fabio_gravar_contexto_experimental(v_id, v_base - 'procedencia')::text);

  -- ===== 15. o campo do Emusys NAO foi tocado =====
  -- A regra que nao pode ser afrouxada: observacoes tem dono. Compara com o
  -- valor capturado ANTES de qualquer chamada a fabio_gravar_contexto_experimental
  -- -- comparar a coluna com ela mesma no MESMO instante sempre daria "true".
  perform pg_temp.checar('15. observacoes intacto','true',
    (v_obs_antes is not distinct from
       (select observacoes from lead_experimentais where id=v_id))::text);

exception when others then
  insert into _falhas values ('excecao','sem excecao', sqlerrm);
end $t$;

-- ===== a selecao de quem extrair =====
do $t2$
declare v_n integer; v_sem_tel integer; v_unidade uuid;
begin
  -- Caso de verdade para o passo 17: uma experimental na janela mas sem
  -- lead vinculado (logo sem telefone/whatsapp). Sem isso, o passo 17 roda
  -- sobre um conjunto que ja nasce sem ninguem sem telefone -- verificacao
  -- sobre conjunto vazio passa sempre, e foi exatamente o que deixou o
  -- mutante "selecao traz quem nao tem telefone" sobreviver na primeira
  -- rodada. A funcao correta CONTINUA filtrando essa linha (e por isso ela
  -- nao aparece nas contagens dos passos 16/18/19); so o mutante que remove
  -- o filtro de telefone deixa ela vazar.
  select unidade_id into v_unidade
    from public.lead_experimentais where unidade_id is not null limit 1;
  insert into public.lead_experimentais (nome_aluno, unidade_id, lead_id, data_experimental)
  values ('Teste mutante sem telefone', v_unidade, null, current_date + 3);

  select count(*) into v_n from public.fn_experimentais_a_extrair(7, 50);
  perform pg_temp.checar('16. a selecao devolve linhas','true', (v_n > 0)::text);

  -- ninguem sem telefone: a edge function nao teria como buscar a conversa
  select count(*) into v_sem_tel from public.fn_experimentais_a_extrair(7, 50)
   where telefone is null or btrim(telefone) = '';
  perform pg_temp.checar('17. ninguem sem telefone','0', v_sem_tel::text);

  -- janela respeitada
  select count(*) into v_sem_tel from public.fn_experimentais_a_extrair(7, 50)
   where data_experimental < current_date or data_experimental > current_date + 7;
  perform pg_temp.checar('18. janela de 7 dias respeitada','0', v_sem_tel::text);

  -- p_dias=0 traz so hoje
  select count(*) into v_sem_tel from public.fn_experimentais_a_extrair(0, 50)
   where data_experimental <> current_date;
  perform pg_temp.checar('19. p_dias=0 traz so hoje','0', v_sem_tel::text);

  -- anon nao executa nenhuma das duas
  perform pg_temp.checar('20. anon nao executa a selecao','false',
    has_function_privilege('anon','public.fn_experimentais_a_extrair(integer,integer)','EXECUTE')::text);
  perform pg_temp.checar('21. anon nao executa a gravacao','false',
    has_function_privilege('anon','public.fabio_gravar_contexto_experimental(integer,jsonb)','EXECUTE')::text);

exception when others then
  insert into _falhas values ('excecao selecao','sem excecao', sqlerrm);
end $t2$;

select json_build_object('teste','027-contexto-experimental',
  'falhas',(select count(*) from _falhas),
  'detalhe', coalesce((select json_agg(json_build_object('passo',passo,'esperado',esperado,'obtido',obtido)) from _falhas),'[]'::json)) as resumo;
