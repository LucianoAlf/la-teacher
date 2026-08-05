-- Teste da 029 — o lead pré-matrícula chega ao professor certo, e só a ele
--
-- Semeia UM lead sem aluno_id (o caso que a 028 escondia), com um contexto que
-- carrega a frase sobre preço, e pergunta pelas duas pontas: o professor dono
-- da experimental e um estranho.

create temp table _res(passo text, esperado text, obtido text) on commit drop;

insert into public.unidades (id, nome, codigo)
values ('00000000-0000-4000-8000-000000000290', 'ZZTESTE unidade 029', 'ZZTESTE029')
on conflict (id) do nothing;

-- Dois professores: o dono da experimental e um estranho.
insert into public.professores (id, nome)
values (-29901, 'ZZTESTE Professor Dono'), (-29902, 'ZZTESTE Professor Estranho');

-- Lead SEM aluno_id: é exatamente quem some pela regra da 028.
insert into public.leads (id, unidade_id, whatsapp, status, aluno_id)
values (-29001, '00000000-0000-4000-8000-000000000290', '5521999990001', 'novo', null);

insert into public.lead_experimentais
  (id, lead_id, nome_aluno, unidade_id, data_experimental, horario_experimental,
   status, professor_experimental_id, contexto_ia, contexto_ia_em)
values
  (-29011, -29001, 'ZZTESTE Arthur Pré Matricula',
   '00000000-0000-4000-8000-000000000290',
   (now() at time zone 'America/Sao_Paulo')::date + 1, '15:00',
   'experimental_agendada', -29901,
   jsonb_build_object(
     'recepcao', jsonb_build_object('responsavel','Mae ZZ','aluno','Arthur',
                                    'data_nascimento','2016-08-05'),
     'quem_e_esse_aluno', jsonb_build_object('nivel_declarado','iniciante'),
     'ganchos_de_conexao', jsonb_build_array('rock'),
     'para_a_devolutiva', jsonb_build_object(
        'o_que_a_familia_espera','ver o filho tocando',
        'atencao_conversao','alta',
        'porque','a familia reclamou tres vezes do valor da mensalidade'),
     'alertas', jsonb_build_array(jsonb_build_object('tipo','agenda','texto','remarcado',
                                                    'interno','nao mostrar')),
     'procedencia', jsonb_build_object('extraido_em','2026-08-05T00:00:00Z')),
   now()),
  -- Cancelada do MESMO professor: a lista de permissão de status tem que segurar.
  (-29012, -29001, 'ZZTESTE Cancelada',
   '00000000-0000-4000-8000-000000000290',
   (now() at time zone 'America/Sao_Paulo')::date + 1, '16:00',
   'cancelada', -29901,
   '{"recepcao":{"aluno":"Nao deveria aparecer"}}'::jsonb, now());

-- ── Passo 1: o professor DONO enxerga o lead que ainda não é aluno ─────────
insert into _res
select 'lead pre-matricula visivel',
       'visivel',
       coalesce((select 'visivel'
                   from jsonb_array_elements(public.fabio_experimentais_do_professor(-29901, 7)) e
                  where e ->> 'lead_experimental_id' = '-29011' limit 1), 'sumiu');

-- ── Passo 2: e vem marcado como ainda-não-aluno ───────────────────────────
insert into _res
select 'ja_e_aluno = false',
       'false',
       coalesce((select e ->> 'ja_e_aluno'
                   from jsonb_array_elements(public.fabio_experimentais_do_professor(-29901, 7)) e
                  where e ->> 'lead_experimental_id' = '-29011' limit 1), '(nao veio)');

-- ── Passo 3: professor ESTRANHO não vê nada ───────────────────────────────
insert into _res
select 'estranho nao ve',
       '0',
       jsonb_array_length(public.fabio_experimentais_do_professor(-29902, 7))::text;

-- ── Passo 4: a frase sobre PREÇO não atravessa ────────────────────────────
-- O texto inteiro da resposta é varrido, não só a chave: se o `porque` for
-- parar em outro campo por descuido, procurar só pela chave não acusaria.
insert into _res
select 'preco nao atravessa',
       'ausente',
       case when public.fabio_experimentais_do_professor(-29901, 7)::text
              ilike '%mensalidade%' then 'VAZOU' else 'ausente' end;

-- ── Passo 5: chave interna do alerta também não atravessa ─────────────────
insert into _res
select 'alerta e lista de permissao',
       'ausente',
       case when public.fabio_experimentais_do_professor(-29901, 7)::text
              ilike '%nao mostrar%' then 'VAZOU' else 'ausente' end;

-- ── Passo 6: cancelada fica de fora ───────────────────────────────────────
insert into _res
select 'cancelada fora',
       'fora',
       coalesce((select 'dentro'
                   from jsonb_array_elements(public.fabio_experimentais_do_professor(-29901, 7)) e
                  where e ->> 'lead_experimental_id' = '-29012' limit 1), 'fora');

-- ── Passo 7: professor nulo é recusa, não "devolve tudo" ──────────────────
-- Sem guard, `professor_id = null` casa com nada e a função devolveria `[]` —
-- que parece inofensivo e é pior: silencia em vez de acusar chamada errada.
do $$
declare v text;
begin
  begin
    perform public.fabio_experimentais_do_professor(null, 7);
    v := 'devolveu sem guard';
  exception
    when sqlstate '42501' then v := 'recusou';
    when others          then v := 'erro outro: ' || sqlerrm;
  end;
  insert into _res values ('professor nulo recusa', 'recusou', v);
end $$;

-- ── Passo 8: a idade é CALCULADA, não copiada do texto ────────────────────
-- Nascido em 05/08/2016; em 05/08/2026 tem 10.
insert into _res
select 'idade calculada',
       '10',
       coalesce((select e -> 'contexto' ->> 'idade'
                   from jsonb_array_elements(public.fabio_experimentais_do_professor(-29901, 7)) e
                  where e ->> 'lead_experimental_id' = '-29011' limit 1), '(nao veio)');

select json_build_object(
  'falhas',  (select count(*) from _res where esperado is distinct from obtido),
  'detalhe', (select coalesce(json_agg(json_build_object(
                       'passo', passo, 'esperado', esperado, 'obtido', obtido)), '[]'::json)
                from _res where esperado is distinct from obtido)
) as resumo;
