# Devolutiva de aula — design

**Data:** 03/08/2026
**Status:** design aprovado pelo Alf. Duas rodadas de auditoria do Alfredo incorporadas — 1ª: gatilho 1:1, `oferecida` vs `entregue`, lease, projeção family-safe. 2ª: conserto na origem (§2.6), fencing do lease (§7.2), `aguardando_destinatario` (§4.5), outbox atômico + recibo (§7.4). Achados próprios na conferência: o ramo 1:1 não checa ausência (§2.5), 100% dos registros não têm a chave `presenca` (§2.6) e o conserto pode travar o piloto se subir fora de ordem (§2.7). Aguardando auditoria do diff antes da migration.
**Escopo:** primeira fatia do sistema de relatórios do Fábio. As outras três (relatório completo do período, versão pra colar no Emusys, painel de coordenação) ficam para specs próprias.

---

## 1. O que é

Depois que o professor confirma o registro da aula, o Fábio oferece um texto curto e pronto **para o professor mandar para a família ou para o aluno**. Não é relatório de período, não é boletim: é a devolutiva daquela aula, no mesmo dia, enquanto a aula ainda está fresca.

**O Fábio nunca fala com a família.** Ele entrega o texto ao professor, que lê, ajusta se quiser e encaminha. Isso é decisão de produto, não limitação técnica: quem tem relação com a família é o professor, e é o nome dele que assina.

### Por que essa fatia primeiro

O motor do relatório de período (`gerar-relatorio-pedagogico`) já existe e já produz PDF bonito. O que não existe é o hábito: o professor precisa **querer** registrar a aula. A devolutiva é a recompensa imediata do registro — ele grava um áudio de 40 segundos e recebe de volta algo que ele mandaria para o responsável de qualquer jeito. O relatório de período colhe o que a devolutiva planta.

---

## 2. O gatilho

### 2.1 Onde nasce

A devolutiva nasce da confirmação do registro, em `app_confirmar_registro(p_registro_id, p_modo)`. É o único ponto do sistema onde o professor diz "esse texto está certo".

### 2.2 A pegadinha do status `confirmado`

`app_confirmar_registro` escreve `confirmado_em` em toda fatia que ela toca, mas o status final **diverge conforme o aluno esteve presente**:

| Situação da fatia | Status final | Grava no prontuário? |
|---|---|---|
| Presente, com conteúdo | `gravado_emusys` | sim |
| **Ausente** (`campos->>'presenca' = 'ausente'`) | **`confirmado`** | não — é pulada |
| Sem aula, sem aluno ou sem texto | *não muda* | não — vira pendência |

Ou seja: **`status = 'confirmado'` é exatamente o caso do aluno que faltou.** Um gatilho ingênuo em `status = 'confirmado'` geraria devolutiva só para quem não teve aula — o pior erro possível deste produto.

### 2.3 A aula 1:1 não tem fatia

`app_confirmar_registro` tem **dois ramos**, e eles se comportam diferente:

- **Turma:** o tronco (`aluno_id is null`) tem fatias filhas, uma por aluno.
- **Individual:** o registro **raiz** já tem `aluno_id` preenchido e **não tem fatia nenhuma**. Ele mesmo vira `gravado_emusys`.

Amarrar o gatilho em `parent_id is not null` recortaria **toda aula individual** do produto. Hoje o banco tem 0 raízes 1:1 — mas a RPC viva já suporta esse caminho, então o dia em que ele começar a ser usado, a devolutiva simplesmente não apareceria, sem erro nenhum para avisar.

### 2.4 Predicado correto

```sql
aluno_id     is not null                                   -- fatia OU raiz 1:1; nunca o tronco de turma
and status    = 'gravado_emusys'
and confirmado_em is not null
and coalesce(campos->>'presenca', 'presente') <> 'ausente' -- ver 2.5
```

`aluno_id is not null` é o discriminador certo porque **é ele que separa "registro de um aluno" de "cabeçalho de turma"**, em vez de depender do formato da árvore. Fatia sem `aluno_id` nunca chega a `gravado_emusys` (vira pendência), então o predicado não perde nada por esse lado.

### 2.5 O status não prova presença na aula individual

Conferindo o ramo 1:1 da RPC apareceu um buraco que o ramo de turma não tem:

| Ramo | Checa `presenca = 'ausente'`? |
|---|---|
| Turma (fatia) | **sim** — pula a fatia e marca `confirmado` |
| **Individual (raiz)** | **não** — grava direto como `gravado_emusys` |

Ou seja: numa aula 1:1, um aluno marcado ausente **termina em `gravado_emusys` do mesmo jeito**. Para a turma, o status já carrega a presença; para o 1:1, não carrega. Por isso o predicado checa `campos->>'presenca'` **explicitamente**, e não confia no status. Sem essa linha, o primeiro aluno individual que faltasse ganharia uma devolutiva contando a aula que ele não teve.

*Nota de nomenclatura:* `gravado_emusys` hoje mente — o texto do Fábio não chega ao campo `anotacoes` do Emusys (auditoria pendente, thread separada). Isso não afeta este design: o que o predicado usa é "o professor confirmou e havia conteúdo", e disso o status é prova. Se o nome do status for corrigido depois, este é um dos pontos a atualizar junto.

### 2.6 O conserto na origem vem antes da devolutiva

O predicado do §2.4 protege **a devolutiva**. Ele não conserta o problema — só desvia dele. Na origem continuam duas coisas erradas, e as duas são pré-requisito deste projeto, não consequência dele:

**a) A aula 1:1 do aluno ausente é gravada como aula dada.** O ramo individual da RPC não olha presença: manda para `registrar_aula_fabio` e marca `gravado_emusys`. Uma aula que não aconteceu vira registro pedagógico. A devolutiva não sairia — mas o prontuário do aluno já teria mentido.

**b) Presença faltando vira "presente" por omissão.** Os dois ramos usam `coalesce(campos->>'presenca', 'presente')`. Campo ausente não é tratado como desconhecido: é tratado como presença afirmada.

E o dado é mais duro do que parece:

| Forma | Registros | Com a chave `presenca` |
|---|---|---|
| Tronco | 12 | **0** |
| Fatia | 19 | **0** |

**31 de 31 registros, 100%, nunca tiveram a chave.** Todo `presente` que esse sistema já afirmou foi por `coalesce`, nenhum por evidência. Os 31 são todos anteriores ao patch `ba1ca01` do normalizador do Hermes (13–18/07; nenhum registro novo desde então, férias). Ou seja: **não existe uma única prova em produção de que `campos.presenca` chegue preenchido.** O default nunca foi exercitado contra um registro que carregasse a chave de verdade.

Isso é a mesma família do problema que a gente já matou na presença — lá "não-marcado" virava falta fantasma; aqui "não-informado" vira presença fantasma. Mesma raiz: **ausência de dado sendo lida como afirmação.**

**O contrato do conserto:**

1. Ramo 1:1 passa a checar `presenca = 'ausente'` igual ao de turma: não grava no prontuário, não vira `gravado_emusys`, não enfileira devolutiva.
2. Chave `presenca` **ausente** deixa de virar `presente`. Vira pendência — o mesmo mecanismo que a turma já usa para fatia sem aluno ou sem texto — com motivo `presença não informada`, e o app pede ao professor que marque.
3. O ramo 1:1 hoje não tem mecanismo de pendência (ele levanta exceção). Ganha um.

### 2.7 Sequência: esse conserto pode brickar o Confirmar

Se a regra 2 subir antes de existir prova de que o Hermes preenche `campos.presenca`, **toda confirmação vira pendência** — e o Matheus, no piloto, aperta "Confirmar" e não acontece nada. A gente teria trocado um erro silencioso por uma parada barulhenta em cima do único professor que está usando o produto.

**Gate obrigatório:** a regra 2 só sobe depois de um registro real, pós-patch, ser observado com `campos ? 'presenca'` verdadeiro. Até lá sobem só as regras 1 e 3, que não dependem do preenchimento.

Isso não é cautela genérica: é a única parte deste plano que pode derrubar o piloto.

### 2.8 Estado hoje

15 fatias já passaram por esse caminho (13–17/07/2026), todas terminando em `gravado_emusys`. **Zero** raízes 1:1 e **zero** fatias em `confirmado` — ou seja, nem o caminho da aula individual nem o do aluno ausente jamais rodaram em produção. Os dois precisam de teste explícito, não de confiança.

### 2.4 O gancho não pode quebrar a confirmação

`app_confirmar_registro` já chama `fabio_emitir_presenca_por_registro` dentro de `begin/exception when others`. A devolutiva segue a mesma disciplina: **enfileira, não gera.** A RPC de confirmação insere uma linha em `fabio_devolutivas` com `status = 'pendente'` e volta. A geração do texto (que envolve LLM) acontece fora, no worker. Confirmar registro nunca pode falhar porque a devolutiva falhou.

---

## 3. De onde sai o conteúdo

### 3.1 Prontuário não é texto para a família

`fn_compor_texto_prontuario(tronco.campos, fatia.campos)` é a função que mescla o contexto da aula com o que é daquele aluno. Ela é a fonte certa do **conteúdo pedagógico** — mas ela **não** é segura para sair da escola. Ela monta oito rótulos, e dois deles são material interno:

| # | Rótulo | Vem de | Sai para a família? |
|---|---|---|---|
| 1 | Objetivo | `objetivo` | sim |
| 2 | Conteúdo | `atividades` | sim |
| 3 | Progresso | `progresso` | sim |
| 4 | Próximo passo | `proximo_passo` | sim |
| 5 | **Observação** | `observacao` / `obs_gerais` | **não** |
| 6 | Repertório | `repertorio` | sim |
| 7 | **Materiais** | `materiais` | **não** |
| 8 | Dever de casa | `dever_casa` | sim |

"Observação" é onde o professor escreve o que ele não diria para a mãe: que a criança chorou, que o pai reclamou da mensalidade, uma suspeita sobre o aluno. **É literalmente o campo de recado interno**, e o prontuário o inclui na íntegra.

### 3.2 Proibir na skill não basta

A tentação é escrever na skill "não use a Observação". Isso não é controle: o texto continua **entrando no prompt**, e a única coisa entre ele e o WhatsApp da mãe é a boa vontade do modelo naquela geração. Uma instrução no prompt não é uma fronteira.

**A fronteira é uma projeção explícita.** Uma função nova, `fn_devolutiva_fonte(p_tronco jsonb, p_fatia jsonb) returns jsonb`, devolve **só** os campos liberados — os seis marcados "sim" na tabela acima. A devolutiva nunca vê `observacao` nem `obs_gerais`; eles não chegam ao worker, quanto mais ao LLM.

**É lista de permissão, não de bloqueio.** Campo de molde novo fica **de fora por padrão**, até alguém olhar e liberar. O contrário — bloquear o que se conhece — vaza silenciosamente no dia em que um molde novo trouxer `nota_interna` ou `alerta_coordenacao`.

`fn_devolutiva_fonte` devolve **jsonb estruturado**, não texto colado, para que a skill saiba o que é progresso e o que é dever de casa em vez de reparsear parágrafo.

### 3.3 A devolutiva não reinterpreta o áudio

Dentro do que é permitido, a devolutiva usa **o que o professor confirmou** — não uma segunda leitura da transcrição. Se ele endossou aquele texto, é dele que a devolutiva fala. Uma leitura independente abriria espaço para a mensagem dizer algo que o prontuário não diz, e o professor descobriria isso na frente do responsável.

### 3.4 Os campos variam por molde

Hoje só existe o molde `C`, e as chaves que aparecem nas fatias são: `progresso`, `proximo_passo`, `observacao`, `repertorio`, `dever_casa` — mais chaves específicas de molde (`eixos`, `marco_ref`, `atividades`, `materiais`, `objetivo`, `obs_gerais`).

**O gerador é tolerante a molde:** trabalha com as chaves que `fn_devolutiva_fonte` devolver, sem exigir que todas existam. Molde novo não pode quebrar devolutiva — e, pela regra da lista de permissão (§3.2), também não pode vazar campo novo sem alguém liberar.

---

## 4. Para quem o texto fala

### 4.1 A regra da idade

- **< 15 anos:** o texto fala com o **responsável**, chamando pelo nome (`alunos.responsavel_nome`) e falando do aluno em terceira pessoa.
- **≥ 15 anos:** o texto fala com o **próprio aluno**, em segunda pessoa.

### 4.2 A regra é executável — conferido

| | |
|---|---|
| Alunos ativos | 1.185 |
| Com `data_nascimento` preenchida | **1.185 (100%)** |
| Menores de 15 | 764 (64%) |
| Menores de 15 **sem** `responsavel_nome` (antes da correção) | 6 (0,5%) |
| Menores de 15 **sem** `responsavel_nome` (03/08, após puxar do Emusys) | **0** |

A regra cobre a base inteira, e o caminho do responsável é a maioria — não a exceção.

Os 6 buracos foram fechados em 03/08/2026: 5 tinham responsável cadastrado no Emusys e foram preenchidos (`updated_by = 'sistema-emusys-responsavel-2026-08-03'`). O sexto não era menor de idade — era data de nascimento corrompida na importação (§4.5).

### 4.3 Idade vem de `data_nascimento`, não de `idade_atual`

`alunos.idade_atual` é um número guardado; ele envelhece errado (fica parado enquanto o aluno faz aniversário). Hoje 3 alunos ativos já divergem do cálculo — nenhum deles cruzando os 15 anos, mas é questão de tempo.

**A idade é calculada de `data_nascimento` no momento da geração.** O custo é zero e elimina a classe inteira de bug "o aluno virou 15 e o texto continuou falando com a mãe".

### 4.4 Quando não houver nome do responsável

Hoje não há nenhum caso, mas aluno novo entra sem responsável a qualquer momento — o fallback é parte do contrato, não contingência.

Sem `responsavel_nome`, o texto fala com a família **sem vocativo nominal** ("Passando pra contar como foi a aula do Gustavo hoje…") e o Fábio avisa o professor na oferta: *"não tenho o nome do responsável do Gustavo — se quiser, me fala que eu ajusto."* Nunca inventa nome, nunca escreve "Sr(a). Responsável".

### 4.5 A idade também pode estar corrompida

Ao puxar os 6 do Emusys apareceu um caso que o desenho não previa: **Tiago Dos Santos Manoel** estava no LA com nascimento em **18/02/2026** — um bebê de 5 meses matriculado em Canto. No Emusys a data é **18/02/1989**: um adulto de 37 anos. O ano se perdeu na importação.

A lição para este design: `data_nascimento` é confiável para **decidir o destinatário**, mas não é imune a lixo. Idade impossível para o contexto — abaixo de 2 anos, acima de 100 — **não escolhe destinatário sozinha**.

**E isso tem que barrar antes do LLM, não depois.** Se a devolutiva fosse gerada e só então alguém perguntasse para quem ela vai, o texto já teria sido escrito com um vocativo inventado ("Oi, mãe do Tiago") — e o professor receberia uma mensagem pronta que só piora se ele mandar. Pior: cada tentativa queima uma chamada de LLM para produzir algo inútil.

Por isso existe o estado `aguardando_destinatario`: o worker resolve o destinatário **antes** de montar o prompt, e se não conseguir decidir, para ali. O Fábio pergunta ao professor para quem é, e a linha só volta para `pendente` com a resposta. Nada de texto gerado no escuro.

---

## 5. As duas versões

Toda devolutiva é gerada em **duas versões, juntas, na mesma chamada**:

1. **Normal** — o padrão.
2. **Com pedido de apoio em casa** — para quando o aluno não está praticando fora da aula.

O professor escolhe qual manda. Gerar as duas de uma vez (em vez de o professor pedir a segunda) existe porque o momento de decidir isso é o momento de mandar — se ele tiver que pedir, ele manda a normal.

### 5.1 A regra de texto: pedir, nunca acusar

A versão de apoio **não relata que o aluno não praticou**. Ela pede parceria.

| Não escrever | Escrever |
|---|---|
| "O Gustavo não praticou em casa esta semana." | "Um pouquinho de prática em casa, uns 10 minutos por dia, ajudaria muito o Gustavo a fixar o que ele já conseguiu na aula." |
| "Ele veio sem estudar de novo." | "Se der pra reservar um tempinho durante a semana, ele chega na próxima aula com muito mais segurança." |

O responsável não pode terminar de ler com a sensação de que levou bronca — nem ele, nem o filho. **Empatia e cuidado são valores da casa, e o texto é onde eles aparecem.**

### 5.2 Só o que é positivo e prático

A devolutiva diz o que a criança **fez** e o que vem **depois**. Dificuldade técnica, comparação com outros alunos, diagnóstico de comportamento e qualquer coisa que soe como avaliação de valor ficam fora — isso é conversa de professor com coordenação, ou de professor com responsável ao vivo, não de mensagem no WhatsApp.

### 5.3 Recital só se existir data

Recital, apresentação e evento só entram no texto **se houver data real cadastrada**. Sem data, o assunto não aparece. Promessa vaga de evento é dívida que a escola paga depois.

---

## 6. A skill

### 6.1 O texto do Fábio mora em tabela, com histórico

O que define *como* o Fábio escreve uma devolutiva é uma skill versionada em `fabio_skills` — não código, não prompt embutido no worker.

Motivo, nas palavras do Alf: *"a gente não pode colocar uma algema no Fábio."* O tom vai ser ajustado dezenas de vezes nos primeiros meses, e cada ajuste não pode custar um deploy. Ao mesmo tempo, mudança de tom sem rastro é como se perde a memória do que já foi decidido.

### 6.2 Cada devolutiva registra qual versão a escreveu

`fabio_devolutivas.skill_versao` guarda a versão da skill usada. Isso responde a pergunta que sempre aparece depois de um ajuste: *"esse texto esquisito é da versão nova ou já era assim antes?"* Sem esse campo, a resposta é chute.

### 6.3 Relação com as skills do Hermes

A VPS já tem sistema de skills em arquivo (`~/.hermes/skills/`, a da casa é `la-music`), montado em `.skills_prompt_snapshot.json`. A skill de devolutiva **não** entra ali: ela é dado operacional que muda em produção sem deploy, e o snapshot é montado na subida do gateway. O worker lê a skill do banco na hora de gerar.

---

## 7. Modelo de dados

### 7.1 `fabio_devolutivas`

Uma linha por fatia confirmada.

| Coluna | Tipo | Papel |
|---|---|---|
| `id` | uuid pk | |
| `registro_fatia_id` | uuid → `fabio_registros_aula(id)` | a fatia que originou. **Único** |
| `aluno_id` | integer | denormalizado para consulta |
| `professor_id` | integer | dono da entrega |
| `destinatario` | text | `responsavel` \| `aluno` — decidido na geração |
| `destinatario_nome` | text | nome usado no vocativo, ou null nos 6 casos sem responsável |
| `idade_na_geracao` | integer | a idade que decidiu o destinatário, congelada |
| `texto_normal` | text | versão 1 |
| `texto_apoio_casa` | text | versão 2 |
| `skill_id` | uuid → `fabio_skills(id)` | quem escreveu |
| `skill_versao` | integer | cópia do número da versão, para ler sem join |
| `status` | text | `pendente` \| `gerando` \| `aguardando_destinatario` \| `gerada` \| `oferecida` \| `falhou` \| `descartada` |
| `lease_token` | uuid | dono do trabalho em `gerando`; **toda** escrita exige (§7.2) |
| `lease_expira_em` | timestamptz | prazo do lease |
| `proxima_tentativa_em` | timestamptz | backoff real; o claim ignora quem ainda não venceu (§7.2) |
| `erro` | text | quando `falhou` |
| `tentativas` | integer | contador do backoff |
| `oferecida_em` | timestamptz | quando o Fábio ofereceu **ao professor** |
| `copiada_em` | timestamptz | professor copiou o texto |
| `editada_em` | timestamptz | professor editou antes de mandar (primeira edição) |
| `compartilhada_em` | timestamptz | professor acionou o compartilhar |
| `envio_confirmado_em` | timestamptz | professor marcou "mandei" |
| `criado_em` / `atualizado_em` | timestamptz | |

**Índice único em `registro_fatia_id`.** Uma fatia gera uma devolutiva; reconfirmar não duplica.

> ⚠️ Índice único e `ON CONFLICT` são **um contrato só**. Quem mexer num, mexe no outro na mesma leva. Em 03/08/2026 o briefing matinal parou inteiro (`42P10`) porque o índice mudou e a RPC ficou apontando para a chave antiga.

`idade_na_geracao` é congelada de propósito: daqui a um ano, olhando um texto que fala com a mãe, dá pra saber que na época estava certo.

**`oferecida`, não `entregue`.** O Fábio entrega ao professor; quem entrega à família é o professor. Um status chamado `entregue` viraria, seis meses depois, um número em painel dizendo "1.200 devolutivas entregues às famílias" — e seria mentira. O nome do estado tem que dizer o que de fato aconteceu, porque é dele que a métrica vai nascer.

**Os quatro carimbos de ação existem porque sem eles não dá para saber se o texto presta.** "O professor encaminhou sem editar" é o sinal mais honesto de qualidade que esse produto tem, e ele não é observável em lugar nenhum hoje. Quatro colunas resolvem sem inventar tabela; se um dia a trilha completa importar (quantas vezes editou, quando), aí vira tabela de eventos.

### 7.2 Lease: por que status sozinho não segura

Gerar a devolutiva é chamada de LLM: leva segundos e roda **fora** da transação. Se o worker só marcasse `gerada` no fim, dois disparos do timer — ou um retry depois de timeout — pegariam a mesma linha `pendente` e gerariam duas vezes. O professor receberia a mesma devolutiva duas vezes, ou pior, duas versões diferentes da mesma aula.

O ciclo é:

```
pendente ──claim──► gerando ──sucesso──► gerada ──recibo do canal──► oferecida
   ▲                   │                    
   │                   ├── falhou ──► pendente, tentativas++, proxima_tentativa_em = now()+backoff
   │                   │
   │                   └── idade impossível ──► aguardando_destinatario (§4.5)
   └── lease expirou (o token velho já não vale nada)
```

`fabio_devolutiva_claim(p_worker text, p_lote int)` pega N linhas com `for update skip locked`, marca `gerando`, grava um `lease_token` **novo** e `lease_expira_em = now() + interval '5 minutes'`, e devolve as linhas com o token. Mesmo desenho de `fabio_claim_notificacao`, que já roda em produção.

#### O lease sozinho não basta — precisa cercar

Expirar o lease libera a linha, mas **não desarma o worker velho**. O roteiro que quebra:

```
10:00  worker A dá claim, começa a gerar
10:05  lease de A expira (A travou numa chamada lenta de LLM)
10:06  worker B dá claim, gera, grava 'gerada'
10:07  worker A volta do timeout e grava o texto DELE por cima
```

O professor recebe um texto que ninguém revisou, produzido por uma execução que o sistema já tinha dado como perdida. E não sobra rastro: os dois escreveram na mesma linha.

**Cerca (fencing):** `claim`, `finish` e `fail` **todos** exigem o `lease_token`. A escrita final é condicional:

```sql
update fabio_devolutivas
   set status = 'gerada', ...
 where id = p_id
   and lease_token = p_token          -- é meu?
   and lease_expira_em > now()        -- ainda estou no prazo?
   and status = 'gerando'
```

Zero linhas afetadas = **o trabalho não é mais meu**. O worker descarta o que gerou e segue — não tenta de novo, não força. Sem essas três condições juntas, o lease é decoração: ele avisa que o tempo acabou e não impede nada.

#### `proxima_tentativa_em`, senão o backoff é ficção

`tentativas++` sozinho não espaça nada: o próximo tick do timer pega a mesma linha imediatamente e a gente tem uma linha quebrada consumindo LLM a cada minuto. O claim só considera linhas com `proxima_tentativa_em is null or proxima_tentativa_em <= now()`, e o `fail` escreve `now() + backoff(tentativas)`. Passado o teto de tentativas, a linha vai para `falhou` e para de ser reivindicada.

**A oferta tem chave própria.** A notificação da devolutiva usa `referencia_tipo='devolutiva'` + `referencia_id=<devolutiva_id>`, com índice único **por devolutiva**, não por dia. O índice único que existe hoje em `fabio_notificacoes` é `(professor_id, tipo, dia_referencia, canal)` — errado para isto, porque um professor tem várias devolutivas no mesmo dia e o segundo aluno seria engolido pelo primeiro.

> ⚠️ Índice novo = `ON CONFLICT` novo, na mesma leva. Ver o aviso em 7.1.

### 7.4 A oferta nasce junto com o texto, e só conta quando chega

Duas coisas separadas, as duas erradas se ficarem soltas:

**a) O outbox é atômico com `gerada`.** Se o worker marcasse `gerada` e só depois inserisse a notificação, uma queda entre as duas deixaria a devolutiva **pronta e órfã**: texto gerado, ninguém avisado, e nada na fila para reparar — porque `gerada` é estado terminal do worker de geração. Ela sumiria em silêncio, que é o pior jeito de falhar. Então: `status='gerada'` **e** a linha em `fabio_notificacoes` entram **na mesma transação**. Ou existem as duas, ou nenhuma.

**b) `oferecida` só depois do recibo do canal.** Enfileirar não é entregar. `oferecida`/`oferecida_em` são escritos quando o canal confirma o envio — o mesmo recibo que o worker de notificação já usa hoje para escrever `enviada`. Enquanto o WhatsApp não confirmou, o estado é `gerada`, e a fila continua responsável por ela.

O par resolve os dois lados: (a) impede perder devolutiva pronta, (b) impede contar como oferecida uma que nunca saiu.

### 7.3 `fabio_skills`

| Coluna | Tipo | Papel |
|---|---|---|
| `id` | uuid pk | |
| `nome` | text | `devolutiva_aula` |
| `versao` | integer | incrementa a cada mudança |
| `conteudo` | text | a skill em si (markdown) |
| `ativa` | boolean | uma versão ativa por nome |
| `notas` | text | por que essa versão existe |
| `criado_em` | timestamptz | |
| `criado_por` | text | |

Dois índices: único em `(nome, versao)` e único parcial em `(nome)` onde `ativa` — este último garante uma só versão ativa por skill. Versão antiga nunca é apagada: é o histórico que dá sentido ao `skill_versao` das devolutivas.

---

## 8. Fluxo completo

```
professor confirma o registro no app
        │
        ▼
app_confirmar_registro
  ├─ grava prontuário (comportamento atual, inalterado)
  ├─ emite presença (gancho atual, não-fatal)
  └─ enfileira devolutiva ─────► fabio_devolutivas (status='pendente')
        │                        predicado do §2.4: aluno_id not null,
        │                        gravado_emusys, confirmado, não-ausente
        ▼
fabio_devolutiva_worker.py (VPS, timer systemd user)
  ├─ claim com lease + token ──► status='gerando' (§7.2)
  ├─ resolve o destinatário PRIMEIRO
  │     └─ idade impossível ──► aguardando_destinatario e PARA (§4.5)
  ├─ lê a fonte FILTRADA via fn_devolutiva_fonte  ← sem observação (§3.2)
  ├─ carrega fabio_skills ativa de devolutiva_aula
  ├─ gera as DUAS versões numa chamada
  └─ numa transação só, com o token ainda válido:
        status='gerada' + linha em fabio_notificacoes  (§7.4a)
        │
        ▼
fabio_notification_worker.py, evento devolutiva_pronta
  respeita canal_preferido, silêncio, pausa_ate; único por devolutiva_id
  "Terminei o registro do Gustavo. Quer a devolutiva pra mandar pra mãe dele?"
        │
        └─ recibo do canal ──► status='oferecida', oferecida_em  (§7.4b)
        ▼
professor lê, ajusta se quiser, encaminha
        └─ app carimba copiada_em / editada_em / compartilhada_em / envio_confirmado_em
```

### 8.1 Onde cada peça roda

**Gerar** e **oferecer** são dois trabalhos diferentes e ficam em processos diferentes:

- **`fabio_devolutiva_worker.py`** — script novo em `~/fabio-chat-bridge/`, disparado por timer systemd do usuário `fabio` a cada poucos minutos. Consome a fila (`status='pendente'`), gera as duas versões, marca `gerada`. É fila, não janela de horário.
- **`fabio_notification_worker.py`** — o worker que já existe. Ganha o evento `devolutiva_pronta`, que faz o oferecimento pelo canal do professor e respeita janela de silêncio, `pausa_ate` e `recebe_domingo` como qualquer outra notificação.

Separar existe porque as duas coisas falham por motivos diferentes: geração falha por LLM ou dado faltando (e deve tentar de novo), entrega falha por canal ou preferência (e deve esperar, não repetir).

### 8.2 O oferecimento é proativo, mas educado

O Fábio oferece; não empurra. Vale a preferência que já existe em `fabio_professor_preferences`: `canal_preferido`, janela de silêncio, `pausa_ate`, `recebe_domingo`. Professor em silêncio não recebe oferta de devolutiva — ela fica `gerada` e espera.

---

## 9. O que fica de fora (YAGNI)

| Fora | Por quê |
|---|---|
| Envio direto do Fábio para a família | Decisão de produto: quem fala com a família é o professor |
| Relatório de período / boletim | Motor já existe (`gerar-relatorio-pedagogico`); spec própria |
| Versão para colar no Emusys | Depende da auditoria do `gravado_emusys`; spec própria |
| Ajuste da devolutiva por áudio | Fase 2 — a fase 1 entrega texto pronto e editável pelo professor no app |
| Devolutiva de aula em grupo como peça única | Uma fatia = um aluno = uma devolutiva. Grupo gera N devolutivas |
| Aprovação da coordenação antes do envio | Trava que mata o hábito antes de ele nascer |

---

## 10. Riscos e o que fazer

| Risco | Mitigação |
|---|---|
| **Recado interno vazar para a família** | `fn_devolutiva_fonte` com lista de permissão; `observacao`/`obs_gerais` não chegam ao LLM (§3.2) |
| **Aula 1:1 ficar invisível** | Predicado por `aluno_id is not null`, não por `parent_id` (§2.3); teste obrigatório do caminho individual |
| Gatilho pegar aluno ausente | Predicado checa `campos->>'presenca'` explicitamente — o status não protege no ramo 1:1 (§2.5) |
| **Aula 1:1 do ausente virar registro pedagógico** | Conserto na origem (§2.6) — é pré-requisito, o predicado da devolutiva só desviava |
| **Presença faltando virar "presente"** | `coalesce` sai; ausência vira pendência. **Gate de sequência em §2.7** — pode travar o Confirmar do piloto |
| **Devolutiva gerada duas vezes** | Claim com lease de 5 min (§7.2); worker morto libera a linha sozinho |
| **Worker expirado sobrescrever texto novo** | Fencing: toda escrita exige `lease_token` + lease vivo; zero linhas = o trabalho não é mais meu (§7.2) |
| **Linha quebrada queimar LLM a cada tick** | `proxima_tentativa_em` com backoff; teto de tentativas leva a `falhou` (§7.2) |
| **Devolutiva pronta e órfã** (gerada, ninguém avisado) | Outbox atômico com `gerada` — ou as duas, ou nenhuma (§7.4a) |
| **Contar como oferecida o que não saiu** | `oferecida` só com recibo do canal (§7.4b) |
| **Texto gerado com vocativo inventado** | Destinatário resolvido antes do prompt; `aguardando_destinatario` barra (§4.5) |
| **Oferta repetida ao professor** | Índice único da notificação por `devolutiva_id`, não por dia (§7.2) |
| Texto sair acusatório | Regra escrita na skill + revisão do Alf antes de ligar para qualquer professor além do piloto |
| LLM inventar fato que não estava no registro | Fonte é a projeção do registro confirmado; a skill proíbe acrescentar conteúdo |
| Devolutiva quebrar a confirmação do registro | Confirmação só enfileira; geração roda fora, no worker |
| Duplicar devolutiva em reconfirmação | Único em `registro_fatia_id` |
| Professor achar que o Fábio já mandou pra família | Texto da oferta diz explicitamente "pra você mandar"; estado se chama `oferecida` (§7.1) |
| Data de nascimento corrompida escolher destinatário errado | Idade impossível não decide sozinha: o Fábio pergunta ao professor (§4.5) |

---

## 11. Como saber se funcionou

Piloto com o Matheus, mesmo professor do briefing matinal.

1. Registro confirmado gera **exatamente uma** devolutiva, nas duas versões. Reconfirmar não duplica; dois disparos do timer não duplicam (§7.2).
2. Aluno de 8 anos → texto fala com o responsável, pelo nome. Aluno de 16 → fala com o aluno.
3. Aluno marcado ausente → **nenhuma** devolutiva. Testar **nos dois ramos**: turma e 1:1 (§2.5) — o 1:1 é o que não tem proteção no status.
4. **Aula individual gera devolutiva.** Nunca rodou em produção; sem esse teste, o produto pode nascer cego para metade do formato de aula (§2.3).
5. Um registro com texto na Observação gera devolutiva **sem nenhum traço dele** — comparar o prontuário e a devolutiva lado a lado (§3.2).
6. **Aula 1:1 com aluno ausente não vira registro no prontuário** — o conserto da origem (§2.6), não só o desvio da devolutiva.
7. **Registro sem a chave `presenca` vira pendência, não "presente"** — e o gate do §2.7 foi cumprido: existe registro real pós-patch com a chave preenchida **antes** dessa regra subir.
8. **Fencing:** simular worker expirado voltando depois de outro ter concluído — a escrita velha afeta **zero linhas** e é descartada (§7.2).
9. **Outbox:** derrubar o worker entre gerar e notificar — não existe devolutiva `gerada` sem linha de notificação (§7.4a).
10. O Alf lê os primeiros textos e aprova o tom antes de qualquer professor além do Matheus.
11. Com os carimbos de §7.1: o professor encaminha sem editar em pelo menos metade dos casos. Se ele reescreve sempre, o texto está errado — não o professor.
