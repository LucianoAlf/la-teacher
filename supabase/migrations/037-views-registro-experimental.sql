-- 037 — duas views, nao um parametro booleano
--
-- Um flag errado vira vazamento; uma view que NAO TEM a coluna nao pode
-- vaza-la. O nome family_safe descreve a GARANTIA (e seguro se chegar a
-- familia), nao o destinatario — nao existe caminho Fabio->familia nesta fase
-- (D1 da spec), e um nome como "_familia" convidaria alguem a criar um depois
-- achando que estava previsto. (Achado do Alfredo na revisao do 4f00e94.)

create or replace view public.vw_experimental_registro_comercial as
select r.id                     as registro_id,
       r.vinculo_id,
       le.id                    as lead_experimental_id,
       le.nome_aluno,
       r.unidade_id,
       r.professor_id,
       ae.data_hora_inicio,
       v.estado                 as estado_vinculo,
       v.presenca_status,
       v.presenca_respondido_por,
       public.fn_presenca_e_forte(v.presenca_respondido_por) as presenca_e_forte,
       r.anotacao_pedagogica,
       r.devolutiva_familia,
       r.proximos_passos,
       r.leitura_de_conversao,   -- INTERNO
       r.status,
       r.criado_em
  from public.lead_experimental_registros r
  join public.lead_experimental_aulas v on v.id = r.vinculo_id
  join public.lead_experimentais le on le.id = v.lead_experimental_id
  left join public.aulas_emusys ae on ae.id = v.aula_local_id
 where r.status <> 'descartado';

create or replace view public.vw_experimental_registro_family_safe as
select r.id                     as registro_id,
       r.vinculo_id,
       le.nome_aluno,
       r.unidade_id,
       ae.data_hora_inicio,
       r.anotacao_pedagogica,
       r.devolutiva_familia,
       r.proximos_passos,
       r.status,
       r.criado_em
       -- leitura_de_conversao NAO entra aqui. Nunca.
  from public.lead_experimental_registros r
  join public.lead_experimental_aulas v on v.id = r.vinculo_id
  join public.lead_experimentais le on le.id = v.lead_experimental_id
  left join public.aulas_emusys ae on ae.id = v.aula_local_id
 where r.status <> 'descartado';

-- As DUAS views ficam so em service_role. "family-safe" descreve o CONTEUDO
-- (nao carrega leitura de conversao), nao autorizacao: a linha ainda tem nome
-- de lead, unidade e horario, e uma view sem filtro por professor entregaria
-- a base inteira de leads a qualquer usuario logado. A primeira versao deste
-- plano dava select a authenticated aqui (achado do Alfredo).
--
-- Quando houver tela de professor lendo isto, o caminho e uma RPC que filtra
-- por fn_professor_do_usuario() — nunca select direto na view.
revoke all on public.vw_experimental_registro_comercial from public, anon, authenticated;
grant select on public.vw_experimental_registro_comercial to service_role;
revoke all on public.vw_experimental_registro_family_safe from public, anon, authenticated;
grant select on public.vw_experimental_registro_family_safe to service_role;

comment on view public.vw_experimental_registro_comercial is
'Registro da experimental para o circulo interno: inclui leitura_de_conversao. So service_role.';
comment on view public.vw_experimental_registro_family_safe is
'Registro da experimental sem NENHUMA coluna de conversao — a garantia e estrutural, nao um flag. So service_role: o nome descreve o conteudo, nao a autorizacao.';
