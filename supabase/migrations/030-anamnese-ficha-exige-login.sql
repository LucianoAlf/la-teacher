-- 030 — a ficha da anamnese deixa de ser publica
--
-- Tirar o link do WhatsApp (05/08, decisao do Alf) fechou o caminho mais
-- provavel, nao a porta. A porta e esta: `get_anamnese_publica` e
-- `get_anamnese_by_token` sao SECURITY DEFINER com EXECUTE para `anon`, e
-- SECURITY DEFINER passa por cima da RLS da tabela `anamneses` por definicao.
--
-- Provado com a chave publica e sem login nenhum: HTTP 200 devolvendo 42 e 49
-- campos, com `diagnosticos`, `cuidado_medico`, `medicacao_continua` e
-- `necessidade_apoio` de uma crianca.
--
-- QUEM USA DE VERDADE (pg_stat_statements, antes de mexer):
--
--   get_anamnese_publica     50 chamadas como anon,  8 como authenticated
--   get_anamnese_by_token     1 chamada  como anon   ← e essa fui eu, testando
--
-- Entao:
--
--   `get_anamnese_by_token` nao e usada por ninguem. Nao aparece em nenhum dos
--   tres repos (anamnese, la-teacher, la-journey) fora dos tipos gerados. Perde
--   o EXECUTE dos dois papeis. Fica existindo em vez de ser dropada: se algum
--   consumidor que eu nao achei existir, ele volta com um GRANT de uma linha,
--   em vez de um restore.
--
--   `get_anamnese_publica` perde so o `anon`. As 8 chamadas autenticadas sao a
--   coordenacao com sessao aberta no app — essas continuam. As 50 anonimas sao
--   justamente o que se quer cortar: alguem abrindo o link sem ser ninguem.
--
-- O `share_token` continua sendo a chave que diz QUAL ficha. O que muda e que
-- ele deixa de ser suficiente sozinho: agora precisa token E conta.
--
-- ⚠️ ISTO SOZINHO QUEBRA A TELA. A rota /perfil/:token do app anamnese-la-music
-- fica fora do gate de login (main.tsx a registra como irma do App, nao como
-- filha). Sem a mudanca no app, quem abrir sem sessao ve erro cru em vez da
-- tela de login. As duas partes vao juntas.

-- ⚠️ O `revoke ... from anon` SOZINHO NAO FAZ NADA, e a primeira versao desta
-- migration caiu nisso. O ACL das duas funcoes comeca com `=X/postgres`: o
-- primeiro campo vazio e o PUBLIC, e PUBLIC tem EXECUTE. Como todo papel herda
-- de PUBLIC, o `anon` continuava executando por baixo e o teste continuou
-- vermelho DEPOIS da migration — que e exatamente o motivo de existir teste.
--
-- Entao: revoga de PUBLIC (que e quem realmente concede) e devolve o EXECUTE,
-- nominalmente, so a quem deve ter. Lista de permissao, como em todo o resto
-- deste projeto.
revoke execute on function public.get_anamnese_by_token(character varying) from public, anon, authenticated;
revoke execute on function public.get_anamnese_publica(text)               from public, anon, authenticated;

-- `service_role` e o backend (a edge function notificar-anamnese conecta com
-- ele). `authenticated` e a coordenacao com sessao — as 8 chamadas legitimas.
grant execute on function public.get_anamnese_publica(text) to authenticated, service_role;
grant execute on function public.get_anamnese_by_token(character varying) to service_role;

comment on function public.get_anamnese_publica(text) is
'Ficha da anamnese por share_token. EXIGE usuario autenticado desde 05/08/2026 — o token sozinho nao basta, porque a ficha carrega dado de saude de menor. Ver migration 030.';

comment on function public.get_anamnese_by_token(character varying) is
'SEM CONSUMIDOR conhecido (1 unica chamada registrada, de um teste). EXECUTE revogado de anon e authenticated em 05/08/2026. Se algo quebrar por causa disto, o conserto e um GRANT — mas confira antes se nao e melhor apontar para get_anamnese_publica.';
