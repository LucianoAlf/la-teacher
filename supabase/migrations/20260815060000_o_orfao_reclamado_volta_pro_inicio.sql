-- O órfão reclamado volta pro INÍCIO da fila, não pro estado em que morreu.
--
-- Terceiro andar do mesmo caso (prof. Valdo, 15/08/2026). A 20260815040000 fez
-- `fn_fabio_retry_fila` enxergar quem morreu em voo. Medido em produção logo
-- depois, no cron das 14:30: as três linhas órfãs foram despachadas — e a edge
-- devolveu, para as três:
--
--   {"status":"ignorado","motivo":"status transcrito"}
--   {"status":"ignorado","motivo":"status transcrevendo"}
--
-- Porque `fabio-registro-aula/index.ts` só aceita `pendente` e `erro`:
--
--   if (!["pendente","erro"].includes(audio.status))
--     return json({ status: "ignorado", ... })
--
-- A guarda da edge está CERTA — é ela que impede processar duas vezes uma
-- linha que ainda está viva. Errado estava o retry: ele gastava uma tentativa
-- redespachando a linha no estado em que ela morreu, a edge ignorava, e depois
-- de 3 rodadas a linha saía do alcance do retry ainda em silêncio. O conserto
-- anterior, sozinho, era inerte.
--
-- Reclamar um órfão é devolvê-lo ao começo: status volta a `pendente`, que é
-- exatamente o estado em que a fila nasce. Só os dois estados EM VOO são
-- reescritos; `pendente` e `erro` seguem intactos, porque a edge já os aceita.
--
-- Retranscrever um `transcrito` é desperdício aceitável: a alternativa é o
-- registro nunca existir. Não há risco de duplicata — `fabio_criar_registro_aula`
-- devolve "ja_existia" quando o audio_id já tem registro. E não há risco de
-- disparo duplo: `trg_fabio_fila_novo` é AFTER INSERT, não dispara em UPDATE.

create or replace function public.fn_fabio_retry_fila()
returns integer
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $function$
declare
  r record;
  n integer := 0;
begin
  for r in
    select f.id
      from public.fabio_fila_audios f
     where (
             f.status in ('pendente', 'erro')
             -- Morreu em voo: o Hermes carimbou o estado intermediário e a
             -- etapa seguinte falhou sem escrever erro. Sem esta linha, fica
             -- órfã pra sempre.
             or (
               f.status in ('transcrevendo', 'transcrito')
               and f.atualizado_em < now() - interval '15 minutes'
             )
           )
       -- A experimental tem worker próprio e usa 'transcrevendo' também.
       -- Mesma fronteira de trg_fabio_fila_dispara.
       and f.vinculo_id is null
       and f.erro_tipo = 'transitorio'
       and f.status <> 'erro_terminal'
       and f.tentativas < 3
       and f.criado_em > now() - interval '3 days'
       and f.atualizado_em < now() - (least(greatest(f.tentativas, 1), 12) * interval '5 minutes')
     order by f.atualizado_em
     limit 10
  loop
    update public.fabio_fila_audios
       set tentativas = tentativas + 1,
           -- Sem isto a edge responde "ignorado" e a tentativa é queimada à
           -- toa: ela só aceita 'pendente' e 'erro'.
           status = case
                      when status in ('transcrevendo', 'transcrito') then 'pendente'
                      else status
                    end,
           atualizado_em = now()
     where id = r.id;
    perform public.fn_fabio_chama_edge(r.id);
    n := n + 1;
  end loop;
  return n;
end
$function$;

comment on function public.fn_fabio_retry_fila() is
  'Reenfileira áudio do Fábio que falhou OU morreu em voo (transcrevendo/transcrito parados >15min), devolvendo o órfão ao estado pendente — a edge só aceita pendente/erro. Só aula comum: a experimental tem worker próprio (vinculo_id).';
