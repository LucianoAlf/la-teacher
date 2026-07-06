-- ============================================================
-- AUDITORIA LA REPORT · Fase 2 — Contratos + Qualidade de dados
-- Projeto: ouqwbbermlzqqvtqwlul · Rodar no SQL Editor
-- Copiar o resultado (Export CSV) e anexar no chat.
-- 100% leitura — não altera nada.
-- ============================================================

-- A · Corpo completo das funções do Fábio
select 'A_FUNCAO_FABIO' as secao, p.proname as item,
       pg_get_functiondef(p.oid) as detalhe
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('registrar_aula_fabio','get_fabio_aulas_do_professor')

-- B · Definição completa das views do Fábio
union all
select 'B_VIEW_FABIO', viewname,
       pg_get_viewdef(('public.'||viewname)::regclass, true)
from pg_views
where viewname in ('vw_fabio_aulas_contexto','vw_fabio_carteira_professor')

-- C · Qualidade: campos críticos de alunos (estudo do Hugo)
union all select 'C_ALUNOS','total', count(*)::text from alunos
union all select 'C_ALUNOS','ex_alunos (is_ex_aluno)', count(*) filter (where is_ex_aluno)::text from alunos
union all select 'C_ALUNOS','ex c/ data_saida', count(data_saida) filter (where is_ex_aluno)::text from alunos
union all select 'C_ALUNOS','ex c/ motivo_saida_id', count(motivo_saida_id) filter (where is_ex_aluno)::text from alunos
union all select 'C_ALUNOS','ex c/ tipo_saida_id', count(tipo_saida_id) filter (where is_ex_aluno)::text from alunos
union all select 'C_ALUNOS','todos c/ canal_origem_id', count(canal_origem_id)::text from alunos
union all select 'C_ALUNOS','todos c/ anamnese_preenchida', count(*) filter (where anamnese_preenchida)::text from alunos
union all select 'C_ALUNOS','status distintos',
       (select string_agg(s||'('||c||')', ' · ') from (select status s, count(*) c from alunos group by 1 order by 2 desc limit 12) x)
union all select 'C_ALUNOS','health_score distintos',
       (select string_agg(coalesce(health_score,'NULL')||'('||c||')', ' · ') from (select health_score, count(*) c from alunos group by 1 order by 2 desc) x)

-- D · Evasões e pesquisa de saída
union all select 'D_EVASAO','evasoes_v2 total', count(*)::text from evasoes_v2
union all select 'D_EVASAO','evasoes_v2 c/ motivo_saida_id', count(motivo_saida_id)::text from evasoes_v2
union all select 'D_EVASAO','evasoes_v2 periodo', min(data_evasao)::text||' → '||max(data_evasao)::text from evasoes_v2
union all select 'D_EVASAO','pesquisa_evasao por status',
       (select string_agg(coalesce(status,'NULL')||'('||c||')', ' · ') from (select status, count(*) c from pesquisa_evasao group by 1) x)
union all select 'D_EVASAO','pesquisa_evasao respondidas c/ audio', count(resposta_audio_url)::text from pesquisa_evasao
union all select 'D_EVASAO','motivos_saida (lookup)',
       (select string_agg(id||':'||nome||'['||coalesce(categoria,'-')||']', ' · ' order by ordem nulls last, id) from motivos_saida where ativo)

-- E · Aulas: taxa de registro atual (baseline da North Star!) e nr_da_aula
union all select 'E_AULAS','total', count(*)::text from aulas_emusys
union all select 'E_AULAS','canceladas', count(*) filter (where cancelada)::text from aulas_emusys
union all select 'E_AULAS','c/ anotacoes (Emusys)', count(*) filter (where anotacoes is not null and length(trim(anotacoes))>0)::text from aulas_emusys
union all select 'E_AULAS','c/ anotacoes_fabio', count(anotacoes_fabio)::text from aulas_emusys
union all select 'E_AULAS','periodo', min(data_aula)::text||' → '||max(data_aula)::text from aulas_emusys
union all select 'E_AULAS','ultimos 90d: total | c/ anotacoes',
       (select count(*)::text||' | '||count(*) filter (where anotacoes is not null and length(trim(anotacoes))>0)::text
        from aulas_emusys where data_aula >= current_date-90 and not cancelada)
union all select 'E_AULAS','nr_da_aula: preenchidas | min | max',
       (select count(nr_da_aula)::text||' | '||min(nr_da_aula)::text||' | '||max(nr_da_aula)::text from aulas_emusys)
union all select 'E_AULAS','tipos distintos',
       (select string_agg(tipo||'('||c||')', ' · ') from (select tipo, count(*) c from aulas_emusys group by 1 order by 2 desc limit 10) x)

-- F · Presença: distribuição e recência
union all select 'F_PRESENCA','por status',
       (select string_agg(status||'('||c||')', ' · ') from (select status, count(*) c from aluno_presenca group by 1 order by 2 desc) x)
union all select 'F_PRESENCA','ultimos 6 meses',
       (select string_agg(mes||'('||c||')', ' · ' order by mes desc) from (select to_char(date_trunc('month',data_aula),'YYYY-MM') mes, count(*) c from aluno_presenca where data_aula >= current_date - interval '6 months' group by 1) x)

-- G · Infra de agentes e governança
union all select 'G_AGENTES','registro(s) em agentes',
       (select string_agg(nome||' ['||coalesce(provider,'-')||'/'||coalesce(modelo,'-')||' · ativo='||is_active||']', ' · ') from agentes)
union all select 'G_AGENTES','governanca.agente_grupos',
       (select string_agg(coalesce(g::text,''), ' | ') from (select row_to_json(t) g from governanca.agente_grupos t limit 9) x)
union all
select 'G_AGENTES','colunas governanca.'||table_name,
       string_agg(column_name||':'||data_type, ', ' order by ordinal_position)
from information_schema.columns where table_schema='governanca' group by table_name

-- H · Relatórios pedagógicos: formato a herdar
union all select 'H_RELPED','periodo_tipo × status',
       (select string_agg(periodo_tipo||'/'||coalesce(status,'-')||'('||c||')', ' · ') from (select periodo_tipo, status, count(*) c from relatorios_pedagogicos group by 1,2) x)
union all select 'H_RELPED','chaves do conteudo_json',
       (select string_agg(distinct k, ', ') from relatorios_pedagogicos, lateral jsonb_object_keys(conteudo_json) k where conteudo_json is not null)

-- I · Identidade: quem loga hoje
union all select 'I_ACESSO','usuarios por perfil',
       (select string_agg(coalesce(perfil,'NULL')||'('||c||')', ' · ') from (select perfil, count(*) c from usuarios group by 1 order by 2 desc) x)
union all select 'I_ACESSO','usuarios c/ auth_user_id', count(auth_user_id)::text from usuarios
union all select 'I_ACESSO','professores ativos | c/ whatsapp | c/ emusys_id',
       (select count(*) filter (where ativo)::text||' | '||count(telefone_whatsapp)::text||' | '||count(emusys_id)::text from professores)

order by 1, 2;
