-- SUPERADA POR: 20260812163000_recibo_so_whatsapp_e_fila_ativa.sql
--
-- O teste `099-presenca-json-null-confirmation.test.sql` cobra recibo para
-- registro com `origem='app'`. A 20260812163000 mudou isso de proposito, e a
-- resposta viva hoje e literalmente `{"motivo":"origem_app","skipped":true}` --
-- o comportamento novo e correto. Nao e defeito; e contrato substituido.
--
-- As guardas de ACL que aquele teste protegia foram resgatadas para
-- `20260813170000_guardas_resgatadas_da_presenca.sql`, com 4/4 mutantes
-- mortos.
-- `presenca: null` e semanticamente igual a presenca ainda nao informada.
-- O normalizador do app pode persistir a chave com JSON null, portanto testar
-- apenas a existencia da chave deixa a confirmacao parcial: a chamada e
-- emitida, mas o conteudo do aluno continua pendente. A fonte unica dessa
-- leitura ja e fn_presenca_declarada; a materializacao deve usar a mesma regra.

create or replace function public.fn_materializar_presenca_padrao(
  p_registro_id uuid,
  p_professor_id integer
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_raiz public.fabio_registros_aula%rowtype;
  v_alterados jsonb;
begin
  if p_registro_id is null or p_professor_id is null then
    raise exception 'registro_e_professor_obrigatorios';
  end if;

  select * into v_raiz
    from public.fabio_registros_aula
   where id = p_registro_id
     and parent_id is null;
  if not found then
    raise exception 'Registro % nao encontrado', p_registro_id;
  end if;
  if v_raiz.professor_id is distinct from p_professor_id then
    raise exception 'Registro nao pertence a este professor';
  end if;

  with alteradas as (
    update public.fabio_registros_aula f
       set campos = coalesce(f.campos, '{}'::jsonb)
                    || jsonb_build_object('presenca', 'presente'),
           atualizado_em = now()
     where coalesce(f.professor_id, v_raiz.professor_id) = p_professor_id
       and (
         (v_raiz.aluno_id is null and f.parent_id = v_raiz.id)
         or (v_raiz.aluno_id is not null and f.id = v_raiz.id)
       )
       and public.fn_presenca_declarada(coalesce(f.campos, '{}'::jsonb)) = 'nao_informada'
    returning f.id
  )
  select coalesce(jsonb_agg(id order by id), '[]'::jsonb)
    into v_alterados
    from alteradas;

  return jsonb_build_object(
    'registro_id', p_registro_id,
    'alterados', v_alterados,
    'quantidade_alterada', jsonb_array_length(v_alterados)
  );
end
$function$;

-- create or replace preserva ACLs, mas a migration torna a fronteira explicita
-- para nao depender de privilegios historicos do objeto.
revoke all on function public.fn_materializar_presenca_padrao(uuid, integer)
  from public, anon, authenticated, service_role;

comment on function public.fn_materializar_presenca_padrao(uuid, integer) is
  'Na confirmacao, materializa presente para toda presenca semanticamente nao informada, inclusive JSON null; preserva presente/ausente explicitos.';
