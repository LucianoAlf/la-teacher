-- Teste da 049 — a fronteira vale nos DOIS caminhos do professor
--
-- O teste compara os dois caminhos SOBRE A MESMA EXPERIMENTAL, em vez de
-- conferir cada um por si. Foi assim que a divergência apareceu: os dois
-- passavam nos seus próprios testes, e ninguém tinha posto os dois lado a
-- lado. Fronteira que vale num caminho e não no outro não é fronteira — é
-- sorte de por onde a pergunta entrou.

create temp table _res(passo text, esperado text, obtido text) on commit drop;

insert into public.unidades (id, nome, codigo) values
  ('00000000-0000-4000-8000-000000000490', 'ZZTESTE unidade 049', 'ZZTESTE049')
on conflict (id) do nothing;
insert into public.usuarios (id, nome, email, auth_user_id) values
  (-49901, 'ZZTESTE Dono 049', 'zz-dono-049@exemplo.invalido', '00000000-0000-4000-8000-000000049901');
insert into public.professores (id, nome, usuario_id) values (-49001, 'ZZTESTE Professor 049', -49901);
insert into public.leads (id, unidade_id, whatsapp, status) values
  (-49001, '00000000-0000-4000-8000-000000000490', '5521999490001', 'novo');

insert into public.lead_experimentais
  (id, lead_id, nome_aluno, unidade_id, data_experimental, horario_experimental,
   status, professor_experimental_id, contexto_ia)
values (-49001, -49001, 'ZZTESTE Helena 049', '00000000-0000-4000-8000-000000000490',
  (now() at time zone 'America/Sao_Paulo')::date, '16:00', 'experimental_agendada', -49001,
  jsonb_build_object(
    'recepcao', jsonb_build_object('aluno','ZZTESTE Helena','responsavel','ZZTESTE Mae'),
    'quem_e_esse_aluno', jsonb_build_object('historia','CANTA NO CHUVEIRO','nivel_declarado','iniciante'),
    'ganchos_de_conexao', jsonb_build_array('GOSTA DE POP'),
    'para_a_devolutiva', jsonb_build_object(
       'o_que_a_familia_espera','GANHAR CONFIANCA',
       'atencao_conversao','alta',
       'porque','MAE PERGUNTOU O PRECO 3X'),
    'como_conduzir','DEIXE ELA ESCOLHER A MUSICA'));

insert into public.aulas_emusys
  (id, emusys_id, unidade_id, data_aula, data_hora_inicio, categoria, curso_nome, professor_id, cancelada)
values (-49001, -949001, '00000000-0000-4000-8000-000000000490',
  (now() at time zone 'America/Sao_Paulo')::date,
  ((now() at time zone 'America/Sao_Paulo')::date + time '16:00') at time zone 'America/Sao_Paulo',
  'experimental', 'ZZTESTE Canto', -49001, false);
insert into public.lead_experimental_aulas (lead_experimental_id, aula_local_id, estado, casado_por)
values (-49001, -49001, 'vinculado', 'chave_natural');

create temp table _c(caminho text, j jsonb) on commit drop;

-- caminho 1: a TELA (045)
do $$
declare v_id bigint; v_out jsonb;
begin
  select id into v_id from lead_experimental_aulas where lead_experimental_id=-49001;
  set local role authenticated;
  perform set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000049901"}',true);
  select public.app_experimental_do_professor(v_id) into v_out;
  reset role;
  insert into _c values ('tela', v_out);
end $$;

-- caminho 2: o FÁBIO no WhatsApp
insert into _c
select 'fabio', j from (
  select value as j from jsonb_array_elements(public.fabio_experimentais_do_professor(-49001, 7))
   where (value->>'lead_experimental_id')::integer = -49001) s;

-- ── Os dois caminhos entregam a experimental ──────────────────────────────
insert into _res select 'a tela acha a experimental', '1',
  (select count(*)::text from _c where caminho='tela' and j ? 'nome_aluno');
insert into _res select 'o Fabio acha a mesma experimental', '1',
  (select count(*)::text from _c where caminho='fabio' and j ? 'nome_aluno');

-- ── E os DOIS barram o sinal comercial ────────────────────────────────────
insert into _res select 'a tela barra o sinal de conversao', 'barrado',
  (select case when j::text like '%atencao_conversao%' then 'VAZOU' else 'barrado' end
     from _c where caminho='tela');
insert into _res select 'o Fabio TAMBEM barra o sinal de conversao', 'barrado',
  (select case when j::text like '%atencao_conversao%' then 'VAZOU' else 'barrado' end
     from _c where caminho='fabio');

-- A comparação direta: é ela que teria pegado a divergência.
insert into _res select 'os dois caminhos concordam sobre o sinal', 'concordam',
  (select case when
     ((select j::text like '%atencao_conversao%' from _c where caminho='tela')
      = (select j::text like '%atencao_conversao%' from _c where caminho='fabio'))
   then 'concordam' else 'DIVERGEM — vale por onde a pergunta entrou' end);

insert into _res select 'e nenhum dos dois leva o preco', 'barrado',
  (select case when bool_or(j::text like '%PRECO 3X%') then 'VAZOU' else 'barrado' end from _c);

-- ── O pedagógico chega nos dois ───────────────────────────────────────────
insert into _res select 'a tela leva a dica de conducao', 'sim',
  (select case when j::text like '%DEIXE ELA ESCOLHER A MUSICA%' then 'sim' else 'nao' end
     from _c where caminho='tela');
insert into _res select 'o Fabio leva a dica de conducao', 'sim',
  (select case when j::text like '%DEIXE ELA ESCOLHER A MUSICA%' then 'sim' else 'nao' end
     from _c where caminho='fabio');
insert into _res select 'e os dois levam o gancho', '2',
  (select count(*)::text from _c where j::text like '%GOSTA DE POP%');
insert into _res select 'e os dois levam o que a familia espera', '2',
  (select count(*)::text from _c where j::text like '%GANHAR CONFIANCA%');

select json_build_object(
  'falhas',  (select count(*) from _res where esperado is distinct from obtido),
  'detalhe', (select coalesce(json_agg(json_build_object(
                       'passo', passo, 'esperado', esperado, 'obtido', obtido)), '[]'::json)
                from _res where esperado is distinct from obtido)
) as resumo;
