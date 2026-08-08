-- Teste da 056 — o código de acesso do professor
--
-- Os dois passos que eu mais quero ver verdes são os que NÃO são sobre o caminho
-- feliz:
--
--   • "as quatro formas do mesmo numero acham a mesma pessoa" — porque a falha
--     aqui é silenciosa: a tela diz "não consegui enviar" e todo mundo vai
--     procurar defeito no WhatsApp, não no `=` do SQL.
--
--   • "professor nao liberado responde IGUAL a numero desconhecido" — se as
--     duas respostas diferirem, qualquer um descobre, um número por vez, quem
--     trabalha na escola.

create temp table _res(passo text, esperado text, obtido text) on commit drop;

-- Um usuário por professor: `ux_professores_usuario` é único, e é essa regra
-- que impede duas pessoas compartilharem o mesmo login.
insert into public.usuarios (id, nome, email, auth_user_id, perfil, ativo) values
  (-56901, 'ZZTESTE Dono 056', 'zz-dono-056@exemplo.invalido',
   '00000000-0000-4000-8000-000000056901', 'professor', true),
  (-56903, 'ZZTESTE Inativo 056', 'zz-inativo-056@exemplo.invalido',
   '00000000-0000-4000-8000-000000056903', 'professor', true);

insert into public.professores (id, nome, nome_preferido, telefone_whatsapp, usuario_id, ativo) values
  -- liberado, cadastrado COM 55 e COM o 9
  (-56001, 'ZZTESTE Ana Liberada 056', 'Aninha', '5521998887766', -56901, true),
  -- ativo mas SEM login: existe e não pode entrar
  (-56002, 'ZZTESTE Bruno Sem Acesso 056', null, '5521997776655', null, true),
  -- liberado porém INATIVO
  (-56003, 'ZZTESTE Caio Inativo 056', null, '5521996665544', -56903, false);

-- ── As variantes ────────────────────────────────────────────────────────────
insert into _res select 'a variante com 55 e com 9 gera as quatro formas', 'sim',
  (select case when public.fn_variantes_telefone_br('5521998887766') @> array[
                    '5521998887766', '21998887766', '552198887766', '2198887766']
          then 'sim' else 'nao' end);

insert into _res select 'numero curto demais nao vira lista', '1',
  (select coalesce(array_length(public.fn_variantes_telefone_br('219988'), 1), 1)::text);

-- O passo que importa: as quatro formas de digitar acham a MESMA pessoa.
create temp table _formas(forma text, achou integer) on commit drop;
insert into _formas
select f, (public.fn_pedir_codigo_de_acesso(f) ->> 'professor_id')::integer
  from (values ('5521998887766'), ('21998887766'), ('552198887766'),
               ('(21) 99888-7766'), ('21 99888 7766')) as v(f);

insert into _res select 'as quatro formas do mesmo numero acham a mesma pessoa', '5',
  (select count(*)::text from _formas where achou = -56001);

-- ── O que o caminho feliz devolve ───────────────────────────────────────────
insert into _res select 'devolve o apelido quando existe', 'Aninha',
  (select public.fn_pedir_codigo_de_acesso('21998887766') ->> 'primeiro_nome');

-- O telefone que volta é o do CADASTRO, não o digitado: é pra ele que a
-- mensagem vai, e é ele que o UAZAPI sabe entregar.
insert into _res select 'devolve o telefone do cadastro, nao o digitado', '5521998887766',
  (select public.fn_pedir_codigo_de_acesso('2198887766') ->> 'telefone');

-- ── Quem NÃO pode ───────────────────────────────────────────────────────────
insert into _res select 'numero desconhecido nao entra', 'nao_encontrado',
  (select public.fn_pedir_codigo_de_acesso('5521900000000') ->> 'motivo');

insert into _res select 'professor nao liberado responde IGUAL a numero desconhecido', 'nao_encontrado',
  (select public.fn_pedir_codigo_de_acesso('5521997776655') ->> 'motivo');

insert into _res select 'professor inativo tambem nao entra', 'nao_encontrado',
  (select public.fn_pedir_codigo_de_acesso('5521996665544') ->> 'motivo');

insert into _res select 'telefone curto e recusado antes de qualquer busca', 'telefone_invalido',
  (select public.fn_pedir_codigo_de_acesso('9988') ->> 'motivo');

-- ── O limite ────────────────────────────────────────────────────────────────
-- Três envios registrados; o quarto pedido tem que bater na trava.
insert into public.professor_acesso_codigos (professor_id, telefone, status, criado_em)
select -56001, '5521998887766', 'enviado', now() - (i || ' minutes')::interval
  from generate_series(1, 3) i;

insert into _res select 'o quarto pedido em 15min e barrado', 'muitas_tentativas',
  (select public.fn_pedir_codigo_de_acesso('5521998887766') ->> 'motivo');

insert into _res select 'e a tentativa barrada fica registrada', '1',
  (select count(*)::text from public.professor_acesso_codigos
    where telefone = '5521998887766' and status = 'bloqueado');

-- Envio velho não conta: quem voltou no dia seguinte entra normalmente.
update public.professor_acesso_codigos
   set criado_em = now() - interval '2 hours'
 where telefone = '5521998887766' and status = 'enviado';

insert into _res select 'envio de uma hora atras nao conta pro limite', 'true',
  (select (public.fn_pedir_codigo_de_acesso('5521998887766') ->> 'ok'));

-- ── O rastro ────────────────────────────────────────────────────────────────
-- Os ids vêm ANTES da leitura: chamar a função dentro do WHERE do mesmo SELECT
-- não funciona — a linha nasce depois do snapshot da consulta e volta vazia.
create temp table _rastro(rotulo text, id uuid) on commit drop;
insert into _rastro values
  ('enviou', public.fn_registrar_codigo_enviado(-56001, '5521998887766', 'zz@exemplo.invalido', true)),
  ('falhou', public.fn_registrar_codigo_enviado(-56001, '5521998887766', 'zz@exemplo.invalido', false));

insert into _res select 'registrar envio deixa rastro com validade', 'enviado|sim',
  (select c.status || '|' || case when c.expira_em > now() then 'sim' else 'nao' end
     from public.professor_acesso_codigos c
     join _rastro r on r.id = c.id and r.rotulo = 'enviou');

insert into _res select 'e falha de envio fica com status proprio', 'falhou',
  (select c.status from public.professor_acesso_codigos c
     join _rastro r on r.id = c.id and r.rotulo = 'falhou');

-- ── Permissões ──────────────────────────────────────────────────────────────
create temp table _erros(passo text, msg text) on commit drop;
grant select, insert on _erros to authenticated, anon;

do $$
begin
  set local role authenticated;
  begin
    perform public.fn_pedir_codigo_de_acesso('5521998887766');
    insert into _erros values ('pedir', 'NAO LEVANTOU');
  exception when others then insert into _erros values ('pedir', sqlerrm);
  end;
  begin
    perform 1 from public.professor_acesso_codigos limit 1;
    insert into _erros values ('ler tabela', 'NAO LEVANTOU');
  exception when others then insert into _erros values ('ler tabela', sqlerrm);
  end;
  reset role;
end $$;

insert into _res select 'autenticado nao pede codigo pra ninguem', 'barrado',
  (select case when msg = 'NAO LEVANTOU' then 'PASSOU' else 'barrado' end
     from _erros where passo='pedir');

insert into _res select 'e nao le a tabela de codigos', 'barrado',
  (select case when msg = 'NAO LEVANTOU' then 'PASSOU' else 'barrado' end
     from _erros where passo='ler tabela');

select json_build_object(
  'falhas',  (select count(*) from _res where esperado is distinct from obtido),
  'detalhe', (select coalesce(json_agg(json_build_object(
                       'passo', passo, 'esperado', esperado, 'obtido', obtido)), '[]'::json)
                from _res where esperado is distinct from obtido)
) as resumo;
