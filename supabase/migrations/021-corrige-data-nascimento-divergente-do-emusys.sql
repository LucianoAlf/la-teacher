-- 021 — data de nascimento: alinha `alunos` à fonte canônica (Emusys)
--
-- POR QUE ISSO EXISTE
-- O Alf mandou corrigir a data do Tiago (id 1457), que estava como
-- 2026-02-18 — um bebê de 5 meses matriculado em Canto. Ao procurar se o
-- problema era só dele, a comparação com o payload bruto do Emusys
-- (emusys_api_payload.payload->'aluno'->>'data_nascimento') achou 11
-- divergências em 1.502 alunos com fonte. Só 2 eram visíveis a olho nu:
-- as outras 9 têm datas plausíveis e ninguém detectaria olhando.
--
-- O QUE ISSO QUEBRA HOJE
-- 1. DEVOLUTIVA — o destinatário é decidido pela idade: abaixo de 15 fala
--    com o responsável, acima fala com o aluno. Três CRIANÇAS estão
--    gravadas como adultos de 40+ (Milena 9,6 / Heitor 7,5 / Laiane 11,7).
--    Uma devolutiva sobre a Milena iria direto pra ela em vez da mãe.
-- 2. CLASSIFICAÇÃO — o trigger trg_alunos_calcular_campos deriva
--    idade_atual e classificacao (LAMK < 12, EMLA >= 12) da data. Com a
--    data errada, a Milena de 9 anos conta como EMLA em todo relatório.
--    Não precisa mexer nesses campos aqui: o trigger recalcula sozinho.
--
-- FONTE
-- emusys_api_payload, endpoint `matriculas`, chave payload->'aluno'. É a
-- mesma origem que alimenta o cadastro; o `alunos` é que saiu de sincronia.
-- As datas erradas caem ~1 semana antes do created_at do registro, o que
-- sugere preenchimento por proximidade quando o sync não trouxe a data.
--
-- REVERSÍVEL
-- Cada linha traz o valor ANTIGO explícito. O UPDATE só toca a linha se o
-- nome e o valor atual baterem com o esperado — se alguém já mexeu, a
-- linha é pulada e a verificação no fim aborta a migration inteira.
--
-- EFEITO EXTERNO DECLARADO
-- trg_enqueue_sync_student_studio dispara net.http_post para a edge
-- function sync-students-studio a cada data alterada. São 11 chamadas,
-- propagando a data CORRETA. É o comportamento desejado, mas é escrita
-- fora deste banco e por isso está escrito aqui.

with correcao (aluno_id, nome_esperado, de, para) as (
  values
    -- criança gravada como adulta — cruza a fronteira dos 15 anos
    (1669, 'Milena Americo Paiva',                      date '1977-07-24', date '2016-12-22'),
    (1466, 'Heitor Muniz Martis Da Silva',              date '1983-04-21', date '2019-02-09'),
    (1469, 'Laiane Marins Lazaro',                      date '1980-12-16', date '2014-11-03'),
    -- adulto gravado como bebê — também cruza a fronteira
    (1457, 'Tiago Dos Santos Manoel',                   date '2026-02-18', date '1989-02-18'),
    -- erram a idade sem cruzar a fronteira dos 15
    (1585, 'Matheus Lopes de Medeiros',                 date '2026-03-24', date '2021-06-04'),
    (1551, 'Matheus Lopes de Medeiros',                 date '2018-06-04', date '2021-06-04'),
    (1518, 'Giselle Gomes Marques',                     date '1989-06-11', date '1986-07-16'),
    (1089, 'Claudio Luiz de Carvalho Mascarenhas Neto', date '2013-01-25', date '2013-05-21'),
    ( 730, 'Beatriz Dolavale Assed',                    date '2023-02-20', date '2022-12-22'),
    ( 955, 'Bruno Ricardo da Silva',                    date '1982-02-03', date '1982-03-03'),
    ( 956, 'Dante Custódio de Almeida Marques',         date '2012-07-13', date '2012-07-31')
)
update alunos a
   set data_nascimento = c.para
  from correcao c
 where a.id = c.aluno_id
   and a.nome = c.nome_esperado
   and a.data_nascimento = c.de;

-- Medir o resultado, não confiar em "o update não deu erro".
do $$
declare
  v_divergentes integer;
  v_criancas_como_adultos integer;
begin
  with emusys as (
    select distinct on (p.emusys_student_id, p.aluno_nome)
           p.emusys_student_id, p.aluno_nome,
           (p.payload->'aluno'->>'data_nascimento')::date as data_emusys
      from emusys_api_payload p
     where p.payload->'aluno'->>'data_nascimento' ~ '^\d{4}-\d{2}-\d{2}$'
     order by p.emusys_student_id, p.aluno_nome, p.synced_at desc
  )
  select count(*) into v_divergentes
    from alunos a
    join emusys e
      on e.emusys_student_id::text = a.emusys_student_id
     and e.aluno_nome = a.nome
   where a.data_nascimento is distinct from e.data_emusys;

  if v_divergentes <> 0 then
    raise exception 'ABORTADO: restam % divergencia(s) de data contra o Emusys', v_divergentes;
  end if;

  -- A garantia que importa pra devolutiva, medida diretamente: ninguém com
  -- responsável cadastrado pode estar aparecendo como maior de 15 anos por
  -- causa de data errada.
  select count(*) into v_criancas_como_adultos
    from alunos
   where responsavel_nome is not null
     and data_nascimento is not null
     and data_nascimento < current_date - interval '15 years'
     and data_nascimento < date '1995-01-01';

  raise notice 'OK: zero divergencia contra o Emusys. Cadastros com responsavel e nascimento anterior a 1995 (revisar depois): %', v_criancas_como_adultos;
end $$;
