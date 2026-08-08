-- Teste da 057 — liberar o acesso de um professor
--
-- O passo que eu mais quero verde é "liberar de novo NAO reescreve o vinculo".
-- É o clique mais provável do mundo — o admin não lembra se já mandou — e a
-- falha seria invisível na hora: o professor que estava logado perderia a
-- sessão e o vínculo apontaria pra um usuário órfão. Ninguém liga uma coisa à
-- outra na segunda-feira.

create temp table _res(passo text, esperado text, obtido text) on commit drop;
create temp table _erros(passo text, msg text) on commit drop;
grant select, insert on _erros to authenticated, anon;

insert into public.usuarios (id, nome, email, auth_user_id, perfil, ativo) values
  (-57901, 'ZZTESTE Admin 057', 'zz-admin-057@exemplo.invalido',
   '00000000-0000-4000-8000-000000057901', 'admin', true),
  (-57902, 'ZZTESTE Ja Tinha 057', 'zz-jatinha-057@exemplo.invalido',
   '00000000-0000-4000-8000-000000057902', 'professor', true),
  (-57903, 'ZZTESTE Nao Admin 057', 'zz-naoadmin-057@exemplo.invalido',
   '00000000-0000-4000-8000-000000057903', 'professor', true);

insert into public.professores (id, nome, nome_preferido, telefone_whatsapp, usuario_id, ativo) values
  (-57001, 'ZZTESTE Ana Sem Acesso 057', 'Aninha', '5521995554433', null,   true),
  (-57002, 'ZZTESTE Bruno Ja Liberado 057', null,  '5521994443322', -57902, true),
  (-57003, 'ZZTESTE Caio Inativo 057', null,       '5521993332211', null,   false),
  (-57004, 'ZZTESTE Dora Sem Zap 057', null,        null,           null,   true);

-- ── Liberar pela primeira vez ───────────────────────────────────────────────
create temp table _saida(rotulo text, j jsonb) on commit drop;
insert into _saida select 'primeira', public.fn_liberar_acesso_professor(
  -57001, '00000000-0000-4000-8000-0000000570a1', 'ZZ-Ana@Exemplo.Invalido');

insert into _res select 'a liberacao diz que e a primeira', 'false',
  (select j ->> 'ja_liberado' from _saida where rotulo='primeira');

insert into _res select 'o professor passa a ter usuario', 'sim',
  (select case when usuario_id is not null then 'sim' else 'nao' end
     from public.professores where id = -57001);

insert into _res select 'o usuario nasce com perfil de professor', 'professor|Professor|true',
  (select u.perfil || '|' || u.cargo || '|' || u.ativo::text
     from public.usuarios u join public.professores p on p.usuario_id = u.id
    where p.id = -57001);

-- E-mail em minúsculas: o Supabase Auth guarda assim, e comparar com o que o
-- admin digitou quebraria no primeiro nome com maiúscula.
insert into _res select 'o e-mail e guardado em minusculas', 'zz-ana@exemplo.invalido',
  (select u.email from public.usuarios u join public.professores p on p.usuario_id = u.id
    where p.id = -57001);

insert into _res select 'e o whatsapp do cadastro vai junto', '5521995554433',
  (select u.telefone from public.usuarios u join public.professores p on p.usuario_id = u.id
    where p.id = -57001);

-- ── O clique repetido ───────────────────────────────────────────────────────
insert into _saida select 'repetida', public.fn_liberar_acesso_professor(
  -57002, '00000000-0000-4000-8000-0000000570b9', 'outro@exemplo.invalido');

insert into _res select 'liberar de novo se anuncia como ja liberado', 'true',
  (select j ->> 'ja_liberado' from _saida where rotulo='repetida');

insert into _res select 'liberar de novo NAO reescreve o vinculo', '-57902',
  (select usuario_id::text from public.professores where id = -57002);

insert into _res select 'e nao troca o auth_user_id de quem ja entrava', '00000000-0000-4000-8000-000000057902',
  (select auth_user_id::text from public.usuarios where id = -57902);

-- ── Recusas ─────────────────────────────────────────────────────────────────
do $$
begin
  begin
    perform public.fn_liberar_acesso_professor(-57003, '00000000-0000-4000-8000-0000000570c1', 'c@e.invalido');
    insert into _erros values ('inativo', 'NAO LEVANTOU');
  exception when others then insert into _erros values ('inativo', sqlerrm);
  end;
  begin
    perform public.fn_liberar_acesso_professor(-57004, '00000000-0000-4000-8000-0000000570d1', 'd@e.invalido');
    insert into _erros values ('sem zap', 'NAO LEVANTOU');
  exception when others then insert into _erros values ('sem zap', sqlerrm);
  end;
  begin
    perform public.fn_liberar_acesso_professor(-57999, '00000000-0000-4000-8000-0000000570e1', 'e@e.invalido');
    insert into _erros values ('inexistente', 'NAO LEVANTOU');
  exception when others then insert into _erros values ('inexistente', sqlerrm);
  end;
end $$;

insert into _res select 'professor inativo nao e liberado', 'professor_inativo',
  (select case when msg like '%professor_inativo%' then 'professor_inativo' else msg end
     from _erros where passo='inativo');

-- Sem WhatsApp o acesso nasce inutilizável: nem convite nem código chegam.
insert into _res select 'professor sem whatsapp nao e liberado', 'professor_sem_whatsapp',
  (select case when msg like '%professor_sem_whatsapp%' then 'professor_sem_whatsapp' else msg end
     from _erros where passo='sem zap');

insert into _res select 'professor inexistente levanta', 'professor_inexistente',
  (select case when msg like '%professor_inexistente%' then 'professor_inexistente' else msg end
     from _erros where passo='inexistente');

-- ── O e-mail interno só preenche vazio ──────────────────────────────────────
-- Esvaziar antes é o ponto: a liberação já grava um e-mail, então o caso que
-- esta função existe pra atender é o usuário de cadastro ANTIGO, sem e-mail.
--
-- E é VAZIO, não nulo: `usuarios.email` é NOT NULL — descobri isso aqui, com o
-- teste estourando. Por isso a guarda da função usa `nullif(btrim(...), '')` e
-- não `email is null`: a segunda nunca seria verdadeira nesta tabela, e a
-- função inteira seria código morto passando por proteção.
update public.usuarios set email = ''
 where id = (select usuario_id from public.professores where id = -57001);

insert into _res select 'amarrar e-mail preenche quem estava sem', 'true',
  (public.fn_amarrar_email_do_professor(-57001, 'novo@interno.invalido'))::text;

insert into _res select 'e o e-mail fica gravado', 'novo@interno.invalido',
  (select u.email from public.usuarios u join public.professores p on p.usuario_id = u.id
    where p.id = -57001);

-- E-mail já existe: não pode ser trocado por um interno, senão a pessoa perde
-- o caminho de recuperação que tinha.
--
-- A chamada vem ANTES do SELECT, em statement próprio. Na primeira versão ela
-- estava dentro do WHERE — e aí o passo virava decoração: o UPDATE da função
-- acontece depois do snapshot da consulta, então o SELECT lia o valor antigo e
-- passava mesmo com o mutante que sobrescreve. Foi assim que o W8 sobreviveu.
-- Mesma armadilha do rastro de código na 056, duas horas antes.
update public.usuarios set email = 'real@lamusic.com.br' where id = -57902;
do $$ begin
  perform public.fn_amarrar_email_do_professor(-57002, '5521994443322@la.internal');
end $$;

insert into _res select 'e NAO sobrescreve e-mail de verdade', 'real@lamusic.com.br',
  (select u.email from public.usuarios u where u.id = -57902);

-- ── O painel ────────────────────────────────────────────────────────────────
create temp table _painel(j jsonb) on commit drop;
grant select, insert on _painel to authenticated;

do $$
begin
  set local role authenticated;
  perform set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000057901"}',true);
  insert into _painel select public.app_professores_para_liberar();
  reset role;
end $$;

insert into _res select 'o admin ve a lista com quem falta liberar', 'sim',
  (select case when j::text like '%ZZTESTE Ana Sem Acesso 057%' then 'sim' else 'nao' end from _painel);

insert into _res select 'e nao lista professor inativo', 'nao',
  (select case when j::text like '%ZZTESTE Caio Inativo 057%' then 'sim' else 'nao' end from _painel);

insert into _res select 'quem esta sem whatsapp vem marcado', 'sim',
  (select case when count(*) = 1 then 'sim' else 'nao' end
     from jsonb_array_elements((select j from _painel)) e
    where (e.value ->> 'professor_id')::integer = -57004
      and (e.value ->> 'tem_whatsapp')::boolean = false);

do $$
begin
  set local role authenticated;
  perform set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000057903"}',true);
  begin
    perform public.app_professores_para_liberar();
    insert into _erros values ('nao admin', 'NAO LEVANTOU');
  exception when others then insert into _erros values ('nao admin', sqlerrm);
  end;
  reset role;

  set local role anon;
  begin
    perform public.app_professores_para_liberar();
    insert into _erros values ('anon painel', 'NAO LEVANTOU');
  exception when others then insert into _erros values ('anon painel', sqlerrm);
  end;
  reset role;
end $$;

insert into _res select 'professor comum nao ve o painel', 'apenas_admin',
  (select case when msg like '%apenas_admin%' then 'apenas_admin' else msg end
     from _erros where passo='nao admin');

insert into _res select 'anonimo tambem nao', 'barrado',
  (select case when msg = 'NAO LEVANTOU' then 'PASSOU' else 'barrado' end
     from _erros where passo='anon painel');

-- ── Quem NÃO pode liberar ───────────────────────────────────────────────────
do $$
begin
  set local role authenticated;
  perform set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000057901"}',true);
  begin
    perform public.fn_liberar_acesso_professor(-57001, '00000000-0000-4000-8000-0000000570f1', 'x@e.invalido');
    insert into _erros values ('liberar direto', 'NAO LEVANTOU');
  exception when others then insert into _erros values ('liberar direto', sqlerrm);
  end;
  reset role;
end $$;

-- Nem o admin chama a liberação direto: ela cria usuário no Auth, e isso só
-- acontece pela edge function, que é quem sabe desfazer se o meio falhar.
insert into _res select 'nem o admin libera direto pelo banco', 'barrado',
  (select case when msg = 'NAO LEVANTOU' then 'PASSOU' else 'barrado' end
     from _erros where passo='liberar direto');

select json_build_object(
  'falhas',  (select count(*) from _res where esperado is distinct from obtido),
  'detalhe', (select coalesce(json_agg(json_build_object(
                       'passo', passo, 'esperado', esperado, 'obtido', obtido)), '[]'::json)
                from _res where esperado is distinct from obtido)
) as resumo;
