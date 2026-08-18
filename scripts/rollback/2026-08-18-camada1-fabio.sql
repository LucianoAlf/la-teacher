-- CAMINHO DE VOLTA da camada 1 do Fábio (spec 2026-08-18).
--
-- Escrito ANTES de aplicar, com a lista capturada do banco VIVO em 18/08/2026.
-- É por isso que ele existe cedo: a revogação de `PUBLIC` só é reversível se
-- alguém souber exatamente de quais funções o PUBLIC foi tirado. Descobrir isso
-- depois, com a coisa quebrada, é a hora errada.
--
-- As 38 assinaturas abaixo foram geradas pelo próprio catálogo:
--   security definer + aberta ao PUBLIC + com grant nominal para
--   anon/authenticated/service_role  →  exatamente o conjunto que a 130000 fecha.
--
-- Ordem inversa da aplicação. Rodar com `scripts/aplicar-sql.mjs`.

-- ── 1) Devolve o PUBLIC às 38 (desfaz a 130000) ─────────────────────────────
grant execute on function app_falta_professor_cancelar_aulas(integer,date,uuid,text) to public;
grant execute on function dispensar_passagem_bastao(uuid,text) to public;
grant execute on function financeiro_enriquecer_fatura_item(jsonb) to public;
grant execute on function fn_agendar_processamento_pesquisa_evasao() to public;
grant execute on function fn_aplicar_opt_out_pesquisa_evasao() to public;
grant execute on function fn_atribuir_rodada_pesquisa_evasao() to public;
grant execute on function fn_aula_alunos_emusys_casar_aluno() to public;
grant execute on function fn_completar_origem_retificacao_presenca() to public;
grant execute on function fn_fabio_chama_edge(uuid) to public;
grant execute on function fn_presenca_pendencias_do_dia(uuid,date) to public;
grant execute on function fn_reagendar_transcricao_pesquisa_evasao() to public;
grant execute on function fn_registrar_limites_rodada_pesquisa_evasao() to public;
grant execute on function fn_texto_relatorio_presenca(uuid,date) to public;
grant execute on function get_conciliacao_leads_qualidade_v1(uuid,integer,integer,text) to public;
grant execute on function get_convite_anamnese(text) to public;
grant execute on function get_cron_health() to public;
grant execute on function get_faturas_alunos_financeiro_v1(uuid,integer,integer,text,text,date) to public;
grant execute on function get_unidade_usuario() to public;
grant execute on function get_user_unidade_id() to public;
grant execute on function get_user_unidade_ids() to public;
grant execute on function incrementar_respondidos_campanha(uuid) to public;
grant execute on function is_admin_usuario() to public;
grant execute on function is_admin() to public;
grant execute on function listar_meta_source_ids_pendentes() to public;
grant execute on function materializar_projecao_contrato(integer,bigint) to public;
grant execute on function prever_projecao_contrato(uuid,text,date,integer) to public;
grant execute on function recalcular_projecao(integer,bigint,text,jsonb) to public;
grant execute on function responder_passagem_bastao(uuid,text,text) to public;
grant execute on function salvar_anamnese_online(text,jsonb,jsonb) to public;
grant execute on function simular_emenda(uuid,date,integer) to public;
grant execute on function sol_caixa_ator_ok(uuid,text) to public;
grant execute on function sync_caixa_envio_from_fila_sol_hermes() to public;
grant execute on function toggle_relatorio_comercial_cron(uuid,boolean) to public;
grant execute on function trg_atualiza_projecao_por_presenca() to public;
grant execute on function trg_atualiza_projecao_por_reposicao() to public;
grant execute on function trg_fabio_fila_dispara() to public;
grant execute on function trg_marcar_contratos_para_recalculo() to public;
grant execute on function trg_materializar_projecao_jornada() to public;

-- ── 2) Ferramentas letivas (desfaz a 120000) ────────────────────────────────
drop function if exists public.fabio_prof_aulas_periodo(text, date, date, text);
drop function if exists public.fabio_prof_presencas_periodo(text, date, date);

-- ── 3) Papel (desfaz a 110000) ──────────────────────────────────────────────
-- `drop owned by` limpa os grants que sobraram; sem isso o `drop role` recusa.
do $function$
begin
  if exists (select 1 from pg_roles where rolname = 'fabio_professor_agente') then
    execute 'drop owned by fabio_professor_agente';
    execute 'drop role fabio_professor_agente';
  end if;
end
$function$;

-- ── 4) Sessão/capacidade (desfaz a 100000) ──────────────────────────────────
drop function if exists public.fabio_agente_revogar_sessao(uuid);
drop function if exists public.fabio_agente_resolver(text);
drop function if exists public.fabio_agente_cunhar_sessao(integer, uuid, integer, integer);
drop table if exists public.fabio_agente_sessoes;
