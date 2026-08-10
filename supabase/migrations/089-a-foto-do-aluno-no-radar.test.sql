-- Teste da 089 — a foto do aluno no Radar.
--
-- Três coisas que este teste existe pra impedir, todas da mesma família ("a
-- tela mostra menos do que o banco tem, e ninguém percebe"):
--
-- 1. LER A COLUNA ERRADA. `alunos` tem `foto_url` (1.447 preenchidas) e
--    `photo_url` (ZERO). Trocar uma pela outra não quebra nada: dá uma tela
--    inteira de iniciais, com cara de "esses alunos não têm foto".
-- 2. FOTO AUSENTE VIRAR STRING VAZIA. `''` faz o Avatar tentar `<img src="">`
--    em vez de cair nas iniciais — quadrado quebrado no lugar da inicial.
-- 3. A REAPLICAÇÃO COMER CAMPO DA 088. `create or replace function` troca o
--    corpo inteiro; a 089 recolou a RPC inteira, então faltas_consecutivas
--    poderia ter sumido no caminho sem ninguém notar.
--
-- Cada passo de igualdade tem ao lado um passo de COBERTURA (o passo 2), senão
-- "0 divergências entre view e banco" passaria também com a coorte vazia.
create temporary table _res(caso text, ok boolean, detalhe text) on commit drop;

do $$
declare
  v_coord    uuid;
  v_r        jsonb;
  v_com_foto int;
  v_divergem int;
begin
  select u.auth_user_id into v_coord
    from public.la_teacher_coordenacao c
    join public.usuarios u on u.id = c.usuario_id
   where u.auth_user_id is not null and coalesce(u.ativo, true) limit 1;

  -- ── 1. A view traz a foto DE alunos.foto_url ────────────────────────────
  select count(*) into v_divergem
    from public.vw_radar_aluno_sinais r
    join public.alunos a on a.id = r.aluno_id
   where r.aluno_foto_url is distinct from a.foto_url;
  insert into _res values ('a foto da view e a mesma de alunos.foto_url',
    v_divergem = 0, format('%s linha(s) divergem', v_divergem));

  -- ── 2. COBERTURA: sem isto, o passo 1 passa com a coorte toda sem foto ──
  select count(r.aluno_foto_url) into v_com_foto from public.vw_radar_aluno_sinais r;
  insert into _res values ('a coorte tem foto de verdade (o passo acima e falsificavel)',
    v_com_foto > 0, format('%s aluno(s) com foto na view', v_com_foto));

  perform set_config('request.jwt.claim.sub', v_coord::text, true);
  v_r := public.app_coordenacao_radar();

  -- ── 3. A RPC entrega a chave em TODA linha (nulo é resposta, ausência não)
  insert into _res values ('toda linha da RPC tem a chave foto',
    not exists (select 1 from jsonb_array_elements(v_r -> 'linhas') l where not l ? 'foto'),
    format('%s linha(s) sem a chave',
      (select count(*) from jsonb_array_elements(v_r -> 'linhas') l where not l ? 'foto')));

  -- ── 4. E o valor bate com o banco, linha por linha ──────────────────────
  insert into _res values ('a foto da linha bate com o banco',
    not exists (
      select 1 from jsonb_array_elements(v_r -> 'linhas') l
        join public.alunos a on a.id = (l ->> 'aluno_id')::bigint
       where (l ->> 'foto') is distinct from a.foto_url),
    coalesce((select format('aluno %s: RPC=%s banco=%s', l ->> 'aluno_id',
                     coalesce(left(l ->> 'foto', 40), '(nulo)'),
                     coalesce(left(a.foto_url, 40), '(nulo)'))
                from jsonb_array_elements(v_r -> 'linhas') l
                join public.alunos a on a.id = (l ->> 'aluno_id')::bigint
               where (l ->> 'foto') is distinct from a.foto_url limit 1), 'ok'));

  -- ── 5. COBERTURA da 4: pelo menos uma linha da RPC com foto ─────────────
  insert into _res values ('a lista da RPC traz foto em pelo menos uma linha',
    exists (select 1 from jsonb_array_elements(v_r -> 'linhas') l
             where (l ->> 'foto') is not null),
    format('%s de %s linha(s) com foto',
      (select count(*) from jsonb_array_elements(v_r -> 'linhas') l
        where (l ->> 'foto') is not null),
      jsonb_array_length(v_r -> 'linhas')));

  -- ── 6. Sem foto = NULO, nunca string vazia ──────────────────────────────
  insert into _res values ('aluno sem foto vem nulo, nunca string vazia',
    not exists (select 1 from jsonb_array_elements(v_r -> 'linhas') l
                 where btrim(coalesce(l ->> 'foto', 'x')) = ''),
    format('%s linha(s) com foto vazia',
      (select count(*) from jsonb_array_elements(v_r -> 'linhas') l
        where btrim(coalesce(l ->> 'foto', 'x')) = '')));

  -- ── 7. A foto é identidade: não vira média nem faceta ───────────────────
  insert into _res values ('a foto nao aparece em medias nem em filtros',
    (v_r -> 'medias')::text not ilike '%foto%'
      and (v_r -> 'filtros')::text not ilike '%foto%', 'ok');

  -- ── 8. REGRESSÃO da reaplicação: o contrato da 087/088 continua ─────────
  insert into _res values ('resumo e lista continuam contando a mesma coisa (080)',
    (v_r #>> '{resumo,alunos}')::int = (v_r ->> 'total_lista')::int,
    format('resumo=%s lista=%s', v_r #>> '{resumo,alunos}', v_r ->> 'total_lista'));

  insert into _res values ('faltas_consecutivas (088) sobreviveu a reaplicacao',
    not exists (select 1 from jsonb_array_elements(v_r -> 'linhas') l
                 where not l ? 'faltas_consecutivas')
      and (v_r #>> '{linhas,0,nota,sinais_totais}')::int = 5,
    format('sinais_totais=%s', v_r #>> '{linhas,0,nota,sinais_totais}'));

  -- ── 9. O guard não afrouxou junto ───────────────────────────────────────
  perform set_config('request.jwt.claim.sub', gen_random_uuid()::text, true);
  begin
    perform public.app_coordenacao_radar();
    insert into _res values ('quem nao e coordenacao continua sem abrir o radar',
      false, 'passou sem guard');
  exception when others then
    insert into _res values ('quem nao e coordenacao continua sem abrir o radar',
      sqlerrm like '%apenas_admin%', sqlerrm);
  end;
end $$;

select json_build_object(
         'falhas', (select count(*) from _res where not ok),
         'detalhe', coalesce((select json_agg(json_build_object(
                                'passo', caso, 'esperado', 'ok', 'obtido', detalhe))
                                from _res where not ok), '[]'::json)
       ) as resumo;
