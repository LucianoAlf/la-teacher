-- ============================================================================
-- LA TEACHER · MIGRAÇÃO 008 — CARTEIRA NA FONTE ÚNICA (jornada canônica)
-- Aplicada no banco como: la_teacher_009_carteira_fonte_unica (09/07/2026).
--
-- POR QUÊ (refatoração da colisão — docs/arquitetura-jornada-aluno.md, §15):
-- a carteira do app vinha de vw_fabio_carteira_professor, que tem LÓGICA
-- PRÓPRIA (select em alunos.professor_atual_id, grão aluno). A verdade da
-- carteira é a jornada canônica (aluno_jornada_matricula_disciplina →
-- vw_jornada_professor_atual, grão matrícula/disciplina). No prof-piloto
-- hoje bate 19=19 por coincidência; divergiriam com o tempo (espelho
-- professor_atual_id dessincroniza do webhook + grão diferente).
--
-- O QUE FAZ:
--   · app_minha_carteira REESCRITA como SELECT GUARDADO sobre
--     vw_jornada_professor_atual. Não é wrapper de lógica (puxadinho): a view
--     canônica é a única fonte; a função só faz o guard
--     (fn_professor_do_usuario) e a projeção — necessário porque
--     get_jornada_professor NÃO tem guard (recebe p_professor_id de fora;
--     o app não pode chamá-la direto).
--   · Projeção SEM contato — telefone/whatsapp/responsavel_telefone ficam
--     FORA (fundação 001: zero contato/financeiro no app do professor;
--     reafirmado pelo Alf em 09/07/2026 — comunicação com pai/aluno será
--     mediada por dentro do app, o professor não depende de ter número).
--   · A carteira GANHA a régua da jornada: jornada_label ("Aula 20/40"),
--     nr_aulas_passadas/contratadas, percentual de presença do contrato e
--     unidade (professor multiunidade; seletor de unidade é passo futuro).
--   · DROP de app_minha_agenda (P3): órfã — a UI usa app_minha_agenda_sessao
--     desde o contrato v3 (zero consumidores no cliente).
--
-- O QUE NÃO TOCA (de propósito):
--   · vw_fabio_carteira_professor — a agente Maria depende dela
--     (maria_lareport_professor_carteira); aposentá-la é pauta do lado LAHQ.
--   · app_minha_agenda_mes — do Hugo (sync), consumidor próprio.
--   · app_minha_agenda_sessao — agenda é grade+presença (aulas_emusys +
--     aluno_presenca), não é carteira; segue como está.
--
-- Campo `qualidade`: derivado dos vínculos da própria canônica (id local /
-- id Emusys / curso mapeado). Mantém os códigos que a UI já traduz em
-- src/features/alunos/carteira.ts (qualidadeLabel).
-- ============================================================================

create or replace function public.app_minha_carteira()
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to 'public'
as $function$
declare v_prof integer := public.fn_professor_do_usuario();
begin
  if v_prof is null then
    return jsonb_build_object('erro','sem_professor_vinculado');
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object(
      'aluno_id', c.aluno_id,
      'aluno_nome', c.aluno_nome,
      'curso', c.curso_nome,
      'status_matricula', c.status_matricula,
      'dia_aula', c.dia_semana,
      'horario_aula', c.horario,
      'unidade', c.unidade_nome,
      'jornada_label', c.jornada_label,
      'nr_aulas_passadas', c.nr_aulas_passadas,
      'nr_aulas_contratadas', c.nr_aulas_contratadas,
      'percentual_presenca_contrato', c.percentual_presenca_contrato,
      'qualidade', case
        when c.aluno_id is null or c.emusys_aluno_id is null then 'aluno_sem_id_emusys'
        when c.curso_id is null then 'sem_contexto'
        else 'ok'
      end
    ) order by c.aluno_nome), '[]'::jsonb)
    from public.vw_jornada_professor_atual c
    where c.professor_id = v_prof
  );
end $function$;

revoke all on function public.app_minha_carteira() from public, anon;
grant execute on function public.app_minha_carteira() to authenticated;

-- A agenda "crua" do P3 — substituída pela agenda por sessão (contrato v3).
drop function if exists public.app_minha_agenda(date);
