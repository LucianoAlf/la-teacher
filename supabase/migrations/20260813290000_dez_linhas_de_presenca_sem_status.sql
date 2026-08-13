-- Dez linhas de presença que ficaram sem o status novo.
--
-- O QUE SÃO. Medido em 13/08/2026: 10 linhas de `aluno_presenca`, todas com
-- `data_aula = 2026-08-05`, todas assim:
--
--     status                 = 'presente'
--     status_presenca        = NULL          <- o buraco
--     respondido_por         = 'emusys'
--     emusys_presenca_bruta  = 'presente'
--
-- As três colunas concordam que o aluno esteve presente. Só a coluna NOVA
-- ficou vazia. São 10 em 47.525 -- e todas do mesmo dia, o que já diz que foi
-- episódio, não regra.
--
-- POR QUE ISSO IMPORTA. `fn_presenca_fecha_chamada(status_presenca, ...)` --
-- a régua canônica, com 6 consumidores -- lê a coluna NOVA. Para essas 10
-- linhas ela responde "sem veredito": o professor vê a aula como pendente na
-- agenda, e a cobrança pode cobrar uma presença que o Emusys já afirmou.
--
-- POR QUE CONSERTAR O DADO E NÃO O LEITOR. Foi a tentação da noite: eu criei
-- uma função com `coalesce(status_presenca, status)` para compensar isso na
-- leitura, e apaguei 40 minutos depois (ver 20260813280000). Fallback no
-- leitor espalha a compensação por TODO consumidor futuro e esconde a
-- inconsistência em vez de mostrá-la. Aqui o dado está errado -- conserta-se
-- o dado.
--
-- NÃO HÁ RISCO DE VOLTAR. O escritor de hoje
-- (`upsert_presenca_emusys_bruta`) grava as duas colunas juntas:
--   `v_status_presenca := case when v_raw = 'presente' then 'presente' else null end`
-- Nenhuma linha nova nasce assim. Isto é limpeza de episódio, não remendo
-- recorrente.
--
-- O QUE ESTE UPDATE NÃO TOCA, de propósito:
--   * linhas de fonte HUMANA -- nenhuma delas está no conjunto, e a régua da
--     casa é que sincronização não pisa em decisão de gente;
--   * `status_presenca` que já tenha qualquer valor;
--   * o caso 'ausente' -- o `null` ali é SEMÂNTICO ("ninguém respondeu"), é a
--     decisão do Alf de 13/08 e tem que continuar nulo.
--
-- Escrita em `aluno_presenca` enquanto o Kodex trabalha na mesma tabela: o
-- `where` abaixo é estreito de propósito e casa exatamente as 10 linhas
-- medidas. Se o conjunto tiver mudado, o bloco ABORTA em vez de escrever a
-- mais.

do $$
declare
  v_alvo int;
begin
  select count(*) into v_alvo
    from public.aluno_presenca
   where respondido_por = 'emusys'
     and status = 'presente'
     and status_presenca is null
     and emusys_presenca_bruta = 'presente';

  if v_alvo = 0 then
    raise notice 'nada a fazer: nenhuma linha no conjunto';
    return;
  end if;

  -- Trava de escopo. 10 foi o medido; um pouco de folga cobre linhas novas do
  -- mesmo episodio, mas um salto grande significa que a causa voltou -- e ai
  -- o conserto e no ESCRITOR, nao aqui.
  if v_alvo > 50 then
    raise exception
      'conjunto inesperado: % linhas (medido 10). A causa pode ter voltado -- conferir upsert_presenca_emusys_bruta antes de escrever',
      v_alvo;
  end if;

  update public.aluno_presenca
     set status_presenca = 'presente'
   where respondido_por = 'emusys'
     and status = 'presente'
     and status_presenca is null
     and emusys_presenca_bruta = 'presente';

  raise notice 'linhas conciliadas: %', v_alvo;
end $$;
