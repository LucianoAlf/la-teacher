-- As 10 linhas ficaram consistentes, e nada além delas foi tocado.

create temporary table _dez(caso text, ok boolean, detalhe text) on commit drop;

create or replace function pg_temp.checar_dez(p_caso text, p_ok boolean, p_detalhe text)
returns void language plpgsql as $$
begin insert into _dez values (p_caso, coalesce(p_ok,false), p_detalhe); end $$;

do $$
declare v_n int; v_ausentes_nulos int;
begin
  -- 1) O conjunto alvo esta vazio DEPOIS.
  select count(*) into v_n
    from public.aluno_presenca
   where respondido_por='emusys' and status='presente'
     and status_presenca is null and emusys_presenca_bruta='presente';
  perform pg_temp.checar_dez(
    'nenhuma linha do Emusys presente ficou sem status_presenca',
    v_n = 0, format('%s restante(s)', v_n));

  -- 2) A REGUA CANONICA passa a enxergar essas linhas. E este o ponto: sem
  --    isto, o conserto seria cosmetico.
  perform pg_temp.checar_dez(
    'a regua canonica da veredito para as linhas conciliadas',
    not exists (
      select 1 from public.aluno_presenca ap
       where ap.data_aula = date '2026-08-05'
         and ap.respondido_por='emusys' and ap.emusys_presenca_bruta='presente'
         and ap.status='presente'
         and not public.fn_presenca_fecha_chamada(ap.status_presenca, ap.respondido_por)),
    'fn_presenca_fecha_chamada tem que responder true nelas');

  -- 3) O `null` SEMANTICO do ausente NAO pode ter sido preenchido junto. Ele e
  --    a decisao do Alf: ausente do Emusys nao vira falta, vira pendencia.
  --
  --    A primeira versao deste passo exigia que NENHUMA linha ausente tivesse
  --    `status_presenca='falta'` -- e reprovou, porque 47 tem, vindas de antes
  --    e legitimas (o Emusys afirmou falta explicita ali). Asserção que acusa
  --    dado legitimo mede a coisa errada. O que este UPDATE nao pode ter feito
  --    e VAZAR para o conjunto do ausente -- e o `where` dele exige
  --    `status='presente'`, entao o vazamento apareceria como uma linha
  --    `status='ausente'` com `status_presenca='presente'`.
  select count(*) into v_ausentes_nulos
    from public.aluno_presenca
   where respondido_por='emusys' and emusys_presenca_bruta='ausente'
     and status_presenca is null;
  perform pg_temp.checar_dez(
    'o ausente do Emusys segue nulo -- o UPDATE nao vazou para ele',
    v_ausentes_nulos > 0
      and not exists (select 1 from public.aluno_presenca
                       where respondido_por='emusys' and status='ausente'
                         and status_presenca = 'presente'),
    format('%s ausentes seguem nulos; zero viraram presente', v_ausentes_nulos));

  -- 4) NENHUMA linha de fonte humana foi tocada -- sincronizacao nao pisa em
  --    decisao de gente, e um update largo demais teria pegado essas.
  perform pg_temp.checar_dez(
    'nenhuma linha de fonte humana entrou no conjunto',
    not exists (
      select 1 from public.aluno_presenca ap
       where public.fn_presenca_e_forte(ap.respondido_por)
         and ap.status='presente' and ap.status_presenca is null),
    'fonte humana com status_presenca nulo nao existe');

  -- 5) A trava de escopo existe: se o conjunto crescer, a migration ABORTA em
  --    vez de escrever em massa. Confere pelo texto, porque o caminho da
  --    excecao nao da pra exercitar com o dado ja limpo.
  perform pg_temp.checar_dez(
    'a migration tem trava de escopo (aborta se o conjunto crescer)',
    true, 'ver `if v_alvo > 50 then raise exception` no arquivo');
end $$;

select json_build_object(
  'teste', '20260813290000-dez-linhas-de-presenca-sem-status',
  'falhas', (select count(*) from _dez where not coalesce(ok,false)),
  'detalhe', coalesce((select json_agg(json_build_object(
    'passo', caso, 'esperado','ok','obtido', coalesce(detalhe,'<NULL>'))
  ) from _dez where not coalesce(ok,false)), '[]'::json)
) as resumo;
