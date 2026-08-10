-- 082 — as réguas do Radar
--
-- Pesos, faixas e linhas de alerta são decisão de GESTÃO, não de engenharia.
-- Decisão do Alf (10/08/2026): configuráveis já na Fase 1, mexidas pela
-- coordenação e por ele.
--
-- A RÉGUA NASCE FROUXA E APERTA COM O TEMPO — intenção dele: *"posso querer
-- descer nesse primeiro momento para 30%, e aumentar aos poucos, de acordo com
-- que a equipe vai amadurecendo"*. Isso inverte o instinto de engenharia
-- (começar apertado e afrouxar) e está certo: alerta que dispara em todo mundo
-- no dia 1 é alerta que a equipe aprende a ignorar, e hábito perdido não volta.
--
-- POR ISSO A COLUNA `fabrica` EXISTE E NUNCA MUDA. Ela é a referência do que
-- foi mexido, visível na tela ao lado do valor atual — sem precisar consultar
-- histórico. E a tela NÃO escreve "recomendado" nem "padrão do sistema" ao
-- lado do número: isso transformaria escolha de gestão em regra técnica, e
-- daqui a três meses ninguém mexe porque "o sistema recomenda".
--
-- O HISTÓRICO É PLACAR, NÃO AUDITORIA. O par (linha do alerta × média da
-- escola) ao longo do tempo é o registro do amadurecimento: a linha apertando
-- enquanto a média cai é a prova de que o lançamento melhorou. É o placar da
-- cobrança da Sol e da ferramenta de presença.
create table if not exists public.radar_config (
  chave    text primary key,
  valor    numeric not null,
  fabrica  numeric not null,
  rotulo   text    not null,
  grupo    text    not null,
  ordem    int     not null
);

create table if not exists public.radar_config_historico (
  id              uuid primary key default gen_random_uuid(),
  chave           text        not null references public.radar_config(chave),
  valor_anterior  numeric     not null,
  valor_novo      numeric     not null,
  mudado_por      uuid,
  mudado_em       timestamptz not null default now()
);

create index if not exists radar_config_historico_chave_idx
  on public.radar_config_historico (chave, mudado_em desc);

insert into public.radar_config (chave, valor, fabrica, rotulo, grupo, ordem) values
  ('peso_absenteismo',         40, 40, 'Absenteísmo',                    'pesos',       1),
  ('peso_feedback',            25, 25, 'Feedback do professor',          'pesos',       2),
  ('peso_pratica',             20, 20, 'Pratica em casa',                'pesos',       3),
  ('peso_faltas_mes',          15, 15, 'Faltas do mês',                  'pesos',       4),
  ('faixa_critico',            40, 40, 'Crítico abaixo de',              'faixas',      5),
  ('faixa_saudavel',           70, 70, 'Saudável a partir de',           'faixas',      6),
  ('absenteismo_atencao_pct',  25, 25, 'Atenção a partir de',            'absenteismo', 7),
  ('absenteismo_critico_pct',  50, 50, 'Crítico a partir de',            'absenteismo', 8),
  ('minimo_aulas_para_taxa',    4,  4, 'Mínimo de aulas pra mostrar taxa','base',       9),
  ('minimo_sinais_para_nota',   2,  2, 'Mínimo de sinais pra mostrar nota','base',     10)
on conflict (chave) do nothing;

alter table public.radar_config           enable row level security;
alter table public.radar_config_historico enable row level security;
-- Sem policy: só as RPCs security definer abaixo alcançam as tabelas.
--
-- RLS sem policy já barra a LINHA pra `authenticated`/`anon` (nenhuma bate em
-- USING/WITH CHECK ausente, então SELECT devolve zero linhas). Mas isso NÃO
-- apaga o GRANT — e medido em produção (pg_default_acl, defaclobjtype='r',
-- role postgres) toda tabela nova já nasce com `anon` e `authenticated` tendo
-- select/insert/update/delete concedidos pelo ALTER DEFAULT PRIVILEGES do
-- projeto. Sem o revoke abaixo, `has_table_privilege('authenticated', ...,
-- 'SELECT')` continua TRUE mesmo com RLS ligada — a mesma lição que a 081
-- pagou numa VIEW (`revoke from public` sozinho não alcança `anon` nem
-- `authenticated`; são grants próprios, não herdados de PUBLIC), agora em
-- tabela, e é o padrão de `028-fabio-le-contexto-experimental.sql:99-100`.
revoke all on table public.radar_config           from public, anon, authenticated;
revoke all on table public.radar_config_historico from public, anon, authenticated;

create or replace function public.app_radar_config()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.fn_e_coordenacao_la_teacher() then
    raise exception 'apenas_admin';
  end if;

  return jsonb_build_object(
    'itens', coalesce((
      select jsonb_agg(jsonb_build_object(
               'chave', chave, 'valor', valor, 'fabrica', fabrica,
               'rotulo', rotulo, 'grupo', grupo, 'mexido', valor <> fabrica)
             order by ordem)
        from public.radar_config), '[]'::jsonb));
end $$;

create or replace function public.app_radar_config_salvar(p_chave text, p_valor numeric)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_anterior numeric;
  v_quem     uuid;
begin
  if not public.fn_e_coordenacao_la_teacher() then
    raise exception 'apenas_admin';
  end if;

  select valor into v_anterior from public.radar_config where chave = p_chave;
  if v_anterior is null then
    -- Chave nova não se cria por aqui: config que aceita chave qualquer vira
    -- lixo silencioso que ninguém lê e ninguém apaga.
    raise exception 'chave_desconhecida';
  end if;

  if v_anterior = p_valor then
    return jsonb_build_object('ok', true, 'mudou', false);
  end if;

  begin
    v_quem := nullif(current_setting('request.jwt.claim.sub', true), '')::uuid;
  exception when others then
    v_quem := null;
  end;

  update public.radar_config set valor = p_valor where chave = p_chave;

  insert into public.radar_config_historico (chave, valor_anterior, valor_novo, mudado_por)
  values (p_chave, v_anterior, p_valor, v_quem);

  return jsonb_build_object('ok', true, 'mudou', true,
                            'de', v_anterior, 'para', p_valor);
end $$;

-- `from public` sozinho não fecha `anon`: mesma raiz do grant de tabela lá em
-- cima (ALTER DEFAULT PRIVILEGES do projeto concede EXECUTE em função nova
-- pra `anon` e `authenticated` direto, não por herança de PUBLIC — medido em
-- pg_default_acl, defaclobjtype='f'). O guard (`fn_e_coordenacao_la_teacher`)
-- já barra `anon` por dentro — auth.uid() nulo não bate com ninguém da
-- coordenação —, então isto é reforço, não é o que impede o vazamento; mas é
-- reforço barato e é o padrão mais comum na casa (069, 074 já fazem os dois
-- revokes).
revoke all on function public.app_radar_config()                       from public, anon;
revoke all on function public.app_radar_config_salvar(text, numeric)   from public, anon;
grant execute on function public.app_radar_config()                    to authenticated;
grant execute on function public.app_radar_config_salvar(text, numeric) to authenticated;
