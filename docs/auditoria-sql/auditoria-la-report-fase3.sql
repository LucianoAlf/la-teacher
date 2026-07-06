-- ============================================================
-- AUDITORIA LA REPORT · Fase 3 — Cadeia da evasão + residuais
-- Projeto: ouqwbbermlzqqvtqwlul · Rodar no SQL Editor · Export CSV
-- 100% leitura. Objetivo: achar a fonte CANÔNICA atual de evasão
-- (evasoes_v2 é legada) e fechar as medições que faltam.
-- ============================================================

-- A · Quem ainda depende da tabela legada (KPIs congelados?)
select 'A_DEPENDENCIAS' as secao, 'views que leem evasoes_v2' as item,
       coalesce(string_agg(viewname, ' · '), 'nenhuma') as detalhe
from pg_views where schemaname='public' and definition ilike '%evasoes_v2%'

union all
select 'A_DEPENDENCIAS', 'functions que leem evasoes_v2',
       coalesce(string_agg(p.proname, ' · '), 'nenhuma')
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public' and p.prosrc ilike '%evasoes_v2%'

union all
select 'A_DEPENDENCIAS', 'views que leem movimentacoes_admin',
       coalesce(string_agg(viewname, ' · '), 'nenhuma')
from pg_views where schemaname='public' and definition ilike '%movimentacoes_admin%'

-- B · movimentacoes_admin como candidata canônica (evasões vivas?)
union all
select 'B_MOV_ADMIN', 'tipos distintos',
       (select string_agg(tipo||'('||c||')', ' · ' order by c desc)
        from (select tipo, count(*) c from movimentacoes_admin group by 1) x)
union all
select 'B_MOV_ADMIN', 'registros por mês (8m)',
       (select string_agg(m||'('||c||')', ' · ' order by m desc)
        from (select to_char(date_trunc('month',data),'YYYY-MM') m, count(*) c
              from movimentacoes_admin
              where data >= current_date - interval '8 months' group by 1) x)
union all
select 'B_MOV_ADMIN', 'evasões: total | c/ motivo_saida_id | c/ motivo texto',
       (select count(*)::text||' | '||count(motivo_saida_id)::text||' | '||
               count(*) filter (where motivo is not null and btrim(motivo)<>'')::text
        from movimentacoes_admin
        where tipo ilike '%evas%' or tipo_evasao is not null)
union all
select 'B_MOV_ADMIN', 'evasões por mês (2026)',
       (select coalesce(string_agg(m||'('||c||')', ' · ' order by m desc),'zero em 2026')
        from (select to_char(date_trunc('month',data),'YYYY-MM') m, count(*) c
              from movimentacoes_admin
              where (tipo ilike '%evas%' or tipo_evasao is not null)
                and data >= '2026-01-01' group by 1) x)
union all
select 'B_MOV_ADMIN', 'tipo_evasao distintos',
       (select coalesce(string_agg(tipo_evasao||'('||c||')', ' · '),'—')
        from (select tipo_evasao, count(*) c from movimentacoes_admin
              where tipo_evasao is not null group by 1) x)

-- C · alunos_historico (saídas históricas)
union all
select 'C_HISTORICO', 'por categoria_saida',
       (select coalesce(string_agg(coalesce(categoria_saida,'NULL')||'('||c||')', ' · '),'—')
        from (select categoria_saida, count(*) c from alunos_historico
              where coalesce(anulado,false)=false group by 1 order by 2 desc limit 10) x)
union all
select 'C_HISTORICO', 'periodo (data_saida) | c/ motivo_saida',
       (select coalesce(min(data_saida)::text,'?')||' → '||coalesce(max(data_saida)::text,'?')
               ||' | '||count(*) filter (where motivo_saida is not null)::text
        from alunos_historico where coalesce(anulado,false)=false)

-- D · Medição CORRIGIDA por status (o flag is_ex_aluno cegou a Fase 2)
union all
select 'D_ALUNOS_STATUS', 'status='||s.status||': n | c/ data_saida | c/ motivo_id | c/ tipo_id | c/ nps_saida',
       s.n::text||' | '||s.ds::text||' | '||s.ms::text||' | '||s.ts::text||' | '||s.nps::text
from (select status, count(*) n, count(data_saida) ds, count(motivo_saida_id) ms,
             count(tipo_saida_id) ts, count(nps_saida) nps
      from alunos where status in ('inativo','evadido','trancado')
      group by status) s

-- E · Semântica do nr_da_aula (sequencial por turma?)
union all
select 'E_NR_AULA', 'turma exemplo: '||t.turma_nome,
       (select string_agg(to_char(a.data_aula,'MM-DD')||'→'||a.nr_da_aula, ' · ' order by a.data_aula desc)
        from (select data_aula, nr_da_aula from aulas_emusys
              where turma_nome = t.turma_nome and nr_da_aula is not null
              order by data_aula desc limit 12) a)
from (select turma_nome, count(*) c from aulas_emusys
      where turma_nome is not null and tipo='turma'
      group by 1 order by 2 desc limit 2) t

-- F · Presença fina (metodologia do 66%)
union all
select 'F_PRESENCA', 'status × respondida (humano) vs automática',
       (select string_agg(status||': resp='||resp||' auto='||auto, ' · ')
        from (select status,
                     count(*) filter (where respondido_em is not null) resp,
                     count(*) filter (where respondido_em is null) auto
              from aluno_presenca group by status) x)
union all
select 'F_PRESENCA', 'cobertura: % de aulas (90d, não canceladas) com presença lançada',
       (select round(100.0*count(distinct ap.aula_emusys_id)/nullif(count(distinct ae.id),0),1)::text||'%'
        from aulas_emusys ae
        left join aluno_presenca ap on ap.aula_emusys_id = ae.id
        where ae.data_aula >= current_date-90 and not ae.cancelada)

order by 1, 2;
