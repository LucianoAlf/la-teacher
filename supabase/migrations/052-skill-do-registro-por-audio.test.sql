-- Teste da 052 — a skill do registro por áudio
--
-- Teste de conteúdo, não de código. O que ele guarda são as três promessas que
-- o texto faz e que o worker não tem como impor sozinho:
--
--   1. existe UMA ativa (duas fariam o worker escolher por sorte de ordenação);
--   2. a instrução de devolver NULO está escrita (sem ela o modelo preenche
--      buraco com o que soa bem, e o campo inventado passa por verdade);
--   3. a fronteira do dinheiro está escrita e nomeia o campo onde ele pode.
--
-- Asserção sobre prosa envelhece com facilidade: quem reescrever a skill tem
-- que reescrever o teste junto, DE PROPÓSITO — é o pedágio pra mexer na única
-- barreira que separa o pedagógico do comercial neste caminho.

create temp table _res(passo text, esperado text, obtido text) on commit drop;

insert into _res select 'existe exatamente uma skill ativa com esse nome', '1',
  (select count(*)::text from public.fabio_skills
    where nome = 'registro_experimental_audio' and ativa);

insert into _res select 'a versao ativa e a mais alta', 'sim',
  (select case when s.versao = (select max(versao) from public.fabio_skills
                                 where nome = 'registro_experimental_audio')
          then 'sim' else 'nao' end
     from public.fabio_skills s
    where s.nome = 'registro_experimental_audio' and s.ativa);

-- Os quatro campos precisam estar nomeados nos DOIS lugares: na lista que
-- explica cada um e no molde do JSON de saída. E a conferência é por prefixo
-- exato (`- campo —` e `"campo":`), não por "contém o nome" — a primeira
-- versão deste passo usava `like '%proximos_passos%'`, e um mutante que
-- rebatizou o campo pra `proximos_passos_do_aluno` passou por ele: o nome
-- novo contém o antigo. Teste que casa por substring aprova o que veio
-- pregado no que ele procurava.
insert into _res select 'a skill nomeia os quatro campos na lista', '4',
  (select ((conteudo like '%- anotacao_pedagogica —%')::int
         + (conteudo like '%- devolutiva_familia —%')::int
         + (conteudo like '%- proximos_passos —%')::int
         + (conteudo like '%- leitura_de_conversao —%')::int)::text
     from public.fabio_skills
    where nome = 'registro_experimental_audio' and ativa);

insert into _res select 'e as mesmas quatro chaves no molde do JSON', '4',
  (select ((conteudo like '%"anotacao_pedagogica":%')::int
         + (conteudo like '%"devolutiva_familia":%')::int
         + (conteudo like '%"proximos_passos":%')::int
         + (conteudo like '%"leitura_de_conversao":%')::int)::text
     from public.fabio_skills
    where nome = 'registro_experimental_audio' and ativa);

insert into _res select 'a skill manda devolver NULO no que nao foi dito', 'sim',
  (select case when conteudo like '%null%' and conteudo like '%não falou%'
          then 'sim' else 'nao' end
     from public.fabio_skills
    where nome = 'registro_experimental_audio' and ativa);

insert into _res select 'a skill proibe dinheiro fora da leitura de conversao', 'sim',
  (select case when conteudo like '%mensalidade%'
                 and conteudo like '%matrícula%'
                 and conteudo like '%só podem aparecer em leitura_de_conversao%'
          then 'sim' else 'nao' end
     from public.fabio_skills
    where nome = 'registro_experimental_audio' and ativa);

insert into _res select 'a skill diz que nao e pra inventar', 'sim',
  (select case when conteudo like '%Não invente%' then 'sim' else 'nao' end
     from public.fabio_skills
    where nome = 'registro_experimental_audio' and ativa);

-- A skill da devolutiva não pode ter sido atropelada: as duas convivem.
insert into _res select 'a skill da devolutiva continua ativa', '1',
  (select count(*)::text from public.fabio_skills
    where nome = 'devolutiva_aula' and ativa);

select json_build_object(
  'falhas',  (select count(*) from _res where esperado is distinct from obtido),
  'detalhe', (select coalesce(json_agg(json_build_object(
                       'passo', passo, 'esperado', esperado, 'obtido', obtido)), '[]'::json)
                from _res where esperado is distinct from obtido)
) as resumo;
