-- A régua do veredito vira função: uma fonte só pra "o aluno tem resposta?".
--
-- O PROBLEMA, medido em 13/08/2026. A casa tinha DUAS réguas de presença
-- rodando ao mesmo tempo, e elas discordavam em 925 pares só em agosto:
--
--   `fn_presenca_e_forte(fonte)`  -> 5 fontes humanas. Emusys NUNCA conta.
--       Cobertura de agosto por ela: **44,4%**
--   predicado inline da pendência -> as 5 fontes **+ Emusys quando é
--       'presente'**. Cobertura de agosto por ele: **95,4%**
--
-- A equipe estava marcando ~100% e o número não subia porque quem media
-- olhava a régua estrita. Eu mesmo caí nisso e reportei 44,4% pro Alf.
--
-- POR QUE A DIVERGÊNCIA EXISTIA (e não era descuido). `fn_presenca_e_forte`
-- recebe só a FONTE. Com um argumento só é impossível dizer "Emusys presente
-- vale, Emusys ausente não" -- a regra depende do STATUS. Quem precisava da
-- regra completa não tinha como perguntar, e copiou inline. Régua que não cabe
-- na assinatura vira régua duplicada.
--
-- A DECISÃO DO ALF, 13/08/2026, textual: *"Presente do Emusys vale! Presente
-- da equipe vale! Preenchimento do professor no aplicativo vale como presença!
-- Ausente do Emusys não vale nada!"* — o ausente do Emusys continua sendo
-- pendência, e é isso que cobra a equipe no dia seguinte.
--
-- DUAS PERGUNTAS, DUAS FUNÇÕES -- e elas NÃO se fundem:
--
--   `fn_presenca_e_forte(fonte)`      -> "isto pode ser sobrescrito?"
--        Protege decisão humana de ser pisada por sincronização. Emusys pode
--        ser pisado, e deve. **Continua exatamente como está.**
--
--   `fn_presenca_e_resposta(...)`     -> "o aluno tem veredito?"  <- NOVA
--        Alimenta contagem, cobrança e selo. Aqui o Emusys-presente conta.
--
-- Fundir as duas faria o Emusys virar fonte forte e parar de ser corrigível
-- pela equipe -- o oposto do que o Alf pediu.
--
-- CUSTO: ZERO, e isso é medido, não prometido. As duas são `sql` puro,
-- IMMUTABLE, sem acesso a tabela -- o formato que o planejador INLINA. No
-- plano elas somem e viram a lista literal. O teste tem passo pra isso: se
-- alguém trocar por plpgsql ou fizer a função ler tabela, ela deixa de ser
-- inlinada e o teste reprova. (Não é teoria: hoje mesmo uma função que LIA
-- tabela dentro de um filtro custou 97,6% dos buffers da pendência.)
--
-- O QUE ESTA MIGRATION NÃO FAZ: não muda view nenhuma e não muda o selo. Ela
-- publica a régua. Trocar o selo muda o que o professor vê na agenda -- é
-- decisão de produto e vai separada, com o Alf olhando.

-- O status efetivo, com o fallback que já existe em produção.
-- `status_presenca` é a coluna nova; `status` é a antiga. Linhas antigas (e a
-- sincronização do Emusys) ainda chegam só com `status`, então quem lê
-- precisa das duas. Sem este fallback, 10 linhas de agosto com
-- `status='presente'` e `status_presenca` nulo sumiriam da conta.
create or replace function public.fn_presenca_status_efetivo(
  p_status_presenca text,
  p_status text
)
returns text
language sql
immutable
parallel safe
as $function$
  select coalesce(
    p_status_presenca,
    case p_status
      when 'presente' then 'presente'
      when 'ausente'  then 'falta'
      else null
    end
  )
$function$;

comment on function public.fn_presenca_status_efetivo(text, text) is
  'Status de presenca com o fallback da coluna antiga `status`. Existe porque '
  'a sincronizacao do Emusys ainda escreve so em `status` -- sem ele, linhas '
  'reais somem da contagem.';

-- A RÉGUA DO VEREDITO. "Este registro responde se o aluno veio?"
create or replace function public.fn_presenca_e_resposta(
  p_respondido_por text,
  p_status_presenca text,
  p_status text
)
returns boolean
language sql
immutable
parallel safe
as $function$
  select coalesce(
    -- 1) Tem que haver veredito. `null` e qualquer estado fora destes tres
    --    significam "ninguem respondeu" -- ausencia de resposta nao e falta.
    public.fn_presenca_status_efetivo(p_status_presenca, p_status)
      in ('presente', 'falta', 'falta_justificada')
    and (
      -- 2a) Fonte humana vale sempre, inclusive quando diz falta.
      public.fn_presenca_e_forte(p_respondido_por)
      -- 2b) Emusys vale SO quando afirma presenca. O 'ausente' dele e
      --     ambiguo: pode ser falta de verdade ou so ninguem ter lancado.
      --     Por decisao do Alf ele nao vira falta -- vira pendencia, e a
      --     pendencia cobra a equipe no dia seguinte.
      or (
        p_respondido_por = 'emusys'
        and public.fn_presenca_status_efetivo(p_status_presenca, p_status) = 'presente'
      )
    ),
    false
  )
$function$;

comment on function public.fn_presenca_e_resposta(text, text, text) is
  'REGUA CANONICA do veredito de presenca (decisao do Alf, 13/08/2026): '
  'fonte humana vale sempre; Emusys vale so quando afirma PRESENTE; ausente '
  'do Emusys nao e falta, e pendencia. NAO confundir com fn_presenca_e_forte, '
  'que responde outra pergunta -- "isto pode ser sobrescrito?" -- e continua '
  'excluindo o Emusys de proposito, para a equipe poder corrigir a '
  'sincronizacao. Quem quer LER presenca usa a view '
  'vw_aluno_presenca_semantica_v1; esta funcao e a regra dentro dela.';

-- Leitura pura, sem dado sensivel: qualquer papel que ja alcanca as views de
-- presenca pode avaliar a regra.
grant execute on function public.fn_presenca_status_efetivo(text, text)
  to anon, authenticated, service_role, fabio_agent;
grant execute on function public.fn_presenca_e_resposta(text, text, text)
  to anon, authenticated, service_role, fabio_agent;
