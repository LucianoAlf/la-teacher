-- O professor não pode lançar presença de novo quando a secretaria já lançou.
--
-- Relato do Valdo (15/08/2026): "como atualizou o aplicativo, eu já tinha feito
-- a chamada dos alunos, e eu tô tendo que meio que dar presença de novo na hora
-- que eu vou gravar o relatório". Medido: a AGENDA já mostra a presença lançada
-- (`app_minha_agenda_sessao` lê `aluno_presenca` desde sempre), mas as telas de
-- REGISTRO não — `app_registro_completo` montava a fatia só com `to_jsonb(r)`,
-- isto é, com a presença que o Fábio inferiu do ÁUDIO, sem nunca perguntar o
-- que a secretaria já tinha lançado. O professor caía numa tela pedindo
-- presença que já existia, mexia nela, e o que ele mexia não valia nada (e nem
-- devia valer — ver a regra abaixo).
--
-- A REGRA DA CASA (Alf, 15/08/2026): quem dá presença é a SECRETARIA (lança no
-- Emusys / LA Report) e é ela que prevalece. O professor lança CONTEÚDO. Se a
-- presença já está dada, ela aparece com o CARIMBO da secretaria e o professor
-- NÃO mexe; se discorda, fala com a secretaria e elas corrigem na fonte.
--
-- Esta migration é só EXIBIÇÃO — não toca em precedência, nem em quem escreve.
-- `app_abrir_rascunho_manual` delega para cá, então a ficha manual ganha o
-- mesmo dado sem precisar ser alterada.
--
-- A régua de "já está dada" é a canônica que já existe: `fn_presenca_fecha_
-- chamada` — fonte humana forte OU emusys='presente'. O `ausente` do Emusys
-- NÃO fecha, de propósito: ele é ambíguo (a falta fantasma da migração), então
-- nesse caso o professor continua podendo lançar.
--
-- A presença é procurada na aula ÂNCORA e na aula individual do aluno (os
-- gêmeos), preferindo a que fecha a chamada — é a mesma leitura que a agenda
-- faz, e evita depender de qual das duas linhas o sincronizador tocou por
-- último.
--
-- Teste: 20260815030000_o_registro_mostra_a_presenca_ja_lancada.test.sql

create or replace function public.app_registro_completo(p_registro_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_prof   integer := public.fn_professor_do_usuario();
  v_tronco jsonb;
  v_fatias jsonb;
  v_aula   jsonb;
  v_ja     jsonb;
  v_aula_id integer;
begin
  if v_prof is null then return jsonb_build_object('erro','sem_professor'); end if;

  select to_jsonb(r) into v_tronco from public.fabio_registros_aula r
   where r.id = p_registro_id and r.parent_id is null and r.professor_id = v_prof;
  if v_tronco is null then return jsonb_build_object('erro','nao_encontrado'); end if;

  v_aula_id := (v_tronco->>'aula_id')::integer;

  select coalesce(jsonb_agg(
           to_jsonb(r)
           || jsonb_build_object(
                'aluno_nome',          a.nome,
                'aluno_primeiro_nome', split_part(btrim(a.nome), ' ', 1),
                'aluno_foto_url',      a.foto_url,
                'aula_id_alvo',        case when r.aluno_id is not null
                                            then public.fn_aula_individual_do_aluno(r.aula_id, r.aluno_id) end,
                -- Presença JÁ lançada (secretaria/Emusys/professor). Só leitura:
                -- o cliente mostra com carimbo e bloqueia a edição quando
                -- `presenca_travada` é true.
                'presenca_lancada',    pres.presenca,
                'presenca_fonte',      pres.respondido_por,
                'presenca_travada',    coalesce(pres.fecha_chamada, false)
              )
           order by a.nome), '[]'::jsonb)
    into v_fatias
    from public.fabio_registros_aula r
    left join public.alunos a on a.id = r.aluno_id
    left join lateral (
      select
        coalesce(ap.status_presenca,
          case ap.status when 'presente' then 'presente'
                         when 'ausente'  then 'falta' end) as presenca,
        ap.respondido_por,
        public.fn_presenca_fecha_chamada(
          coalesce(ap.status_presenca,
            case ap.status when 'presente' then 'presente'
                           when 'ausente'  then 'falta' end),
          ap.respondido_por) as fecha_chamada
        from public.aluno_presenca ap
       where r.aluno_id is not null
         and ap.aluno_id = r.aluno_id
         and ap.aula_emusys_id in (v_aula_id, r.aula_id)
       order by public.fn_presenca_fecha_chamada(
                  coalesce(ap.status_presenca,
                    case ap.status when 'presente' then 'presente'
                                   when 'ausente'  then 'falta' end),
                  ap.respondido_por) desc,
                ap.respondido_em desc nulls last,
                ap.aula_emusys_id
       limit 1
    ) pres on true
   where r.parent_id = p_registro_id;

  select jsonb_build_object(
           'data_aula', v.data_aula, 'hora', v.horario_inicio_brt,
           'turma', v.turma_nome, 'curso', v.curso_nome, 'tipo', v.aula_tipo)
    into v_aula
    from public.vw_fabio_aulas_contexto v
   where v.aula_local_id = v_aula_id limit 1;

  v_ja := public.fn_aula_ja_registrada(v_aula_id);

  return jsonb_build_object(
    'tronco', v_tronco,
    'fatias', v_fatias,
    'aula',   v_aula,
    'aula_ja_registrada', (jsonb_array_length(v_ja) > 0),
    'ja_registrados', v_ja,
    -- o front DEVE mandar 'substituir' ou 'complementar' quando aula_ja_registrada = true.
    -- Se mandar 'novo', o banco recusa (nao destroi o trabalho do professor).
    'modo_exigido', case when jsonb_array_length(v_ja) > 0 then 'substituir|complementar' else 'novo' end
  );
end $function$;
