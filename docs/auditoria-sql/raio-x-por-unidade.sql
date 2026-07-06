-- ============================================================
-- RAIO-X POR UNIDADE · Campo Grande × Recreio × Barra
-- Projeto: ouqwbbermlzqqvtqwlul · SQL Editor · Export CSV
-- 100% leitura. Quebra os números da auditoria por unidade.
-- ============================================================

-- A · Base de alunos + semáforo
select 'A_ALUNOS' as secao, u.nome as item,
       'ativos='||count(*) filter (where a.status='ativo')
       ||' · saudavel='||count(*) filter (where a.status='ativo' and a.health_score='saudavel')
       ||' · atencao='||count(*) filter (where a.status='ativo' and a.health_score='atencao')
       ||' · critico='||count(*) filter (where a.status='ativo' and a.health_score='critico')
       ||' · sem_score='||count(*) filter (where a.status='ativo' and a.health_score is null) as detalhe
from alunos a join unidades u on u.id = a.unidade_id
group by u.nome

-- B · Taxa de registro de aulas (90d) — a North Star por unidade
union all
select 'B_REGISTRO_90D', u.nome,
       'aulas='||count(*)
       ||' · com_anotacao='||count(*) filter (where ae.anotacoes is not null and length(btrim(ae.anotacoes))>0)
       ||' · taxa='||round(100.0*count(*) filter (where ae.anotacoes is not null and length(btrim(ae.anotacoes))>0)/nullif(count(*),0),1)||'%'
from aulas_emusys ae join unidades u on u.id = ae.unidade_id
where ae.data_aula >= current_date-90 and not ae.cancelada
group by u.nome

-- C · Presença (90d)
union all
select 'C_PRESENCA_90D', u.nome,
       'lancamentos='||count(ap.id)
       ||' · presentes='||count(*) filter (where ap.status='presente')
       ||' · taxa='||round(100.0*count(*) filter (where ap.status='presente')/nullif(count(ap.id),0),1)||'%'
from aluno_presenca ap
join aulas_emusys ae on ae.id = ap.aula_emusys_id
join unidades u on u.id = ae.unidade_id
where ae.data_aula >= current_date-90
group by u.nome

-- D · Evasões 2026 (fonte canônica: movimentacoes_admin)
union all
select 'D_EVASOES_2026', u.nome,
       'total='||count(*)
       ||' · mai='||count(*) filter (where date_trunc('month',m.data)='2026-05-01')
       ||' · jun='||count(*) filter (where date_trunc('month',m.data)='2026-06-01')
       ||' · jul='||count(*) filter (where date_trunc('month',m.data)='2026-07-01')
       ||' · com_motivo='||count(m.motivo_saida_id)
from movimentacoes_admin m join unidades u on u.id = m.unidade_id
where (m.tipo ilike '%evas%' or m.tipo_evasao is not null)
  and m.data >= '2026-01-01'
group by u.nome

-- E · Anamnese (adoção por unidade)
union all
select 'E_ANAMNESE', u.nome,
       'alunos='||count(*) filter (where a.status='ativo')
       ||' · com_anamnese='||count(*) filter (where a.status='ativo' and a.anamnese_preenchida)
from alunos a join unidades u on u.id = a.unidade_id
group by u.nome

order by 1, 2;
