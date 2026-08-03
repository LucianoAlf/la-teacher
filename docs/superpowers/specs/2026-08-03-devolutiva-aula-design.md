# Devolutiva de aula — design

**Data:** 03/08/2026
**Status:** design aprovado pelo Alf; **liberado para implementação** após a 5ª rodada. 5ª: o claim da entrega ganhou casa no schema (§7.5) — ao procurar o lease de `fabio_notificacoes` para apontar, descobriu-se que ele não existe: claim por status, janela medindo `criado_em` em vez da hora do claim, sem token, e `ON CONFLICT` que não cobre tipo novo. Cinco rodadas de auditoria do Alfredo incorporadas — 4ª (relatório `fabio-devolutiva-auditoria-2026-08-03.md`): predicado passa a **falhar fechado** (§2.4 — a versão anterior carregava o mesmo `coalesce` que a spec condena), enum obrigatório no produtor e pendência com contrato genérico por alvo (§2.8), claim na entrega + `entrega_incerta` em vez de reenvio automático (§7.4c), `destinatario_override` separado da inferência (§4.5). 3ª: o cliente repete a mentira da presença (§2.7), a pendência não tem resposta possível na tela (§2.8), idempotência entre envio e recibo (§7.4c), saída durável de `aguardando_destinatario` (§4.5). Anteriores — 1ª: gatilho 1:1, `oferecida` vs `entregue`, lease, projeção family-safe. 2ª: conserto na origem (§2.6), fencing do lease (§7.2), `aguardando_destinatario` (§4.5), outbox atômico + recibo (§7.4). Achados próprios na conferência: o ramo 1:1 não checa ausência (§2.5), 100% dos registros não têm a chave `presenca` (§2.6) e o conserto pode travar o piloto se subir fora de ordem (§2.7). Aguardando auditoria do diff antes da migration.
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
aluno_id      is not null            -- fatia OU raiz 1:1; nunca o tronco de turma
and status     = 'gravado_emusys'
and confirmado_em is not null
and campos->>'presenca' = 'presente' -- afirmação, não ausência de negativa (ver 2.5)
```

`aluno_id is not null` é o discriminador certo porque **é ele que separa "registro de um aluno" de "cabeçalho de turma"**, em vez de depender do formato da árvore. Fatia sem `aluno_id` nunca chega a `gravado_emusys` (vira pendência), então o predicado não perde nada por esse lado.

#### Falha fechada: `= 'presente'`, nunca `<> 'ausente'`

A primeira versão desta spec escrevia `coalesce(campos->>'presenca','presente') <> 'ausente'` — **o mesmo `coalesce` que este documento passa três seções condenando**, escrito por mim, na linha que define quem recebe mensagem. Chave faltando passaria no filtro. Considerando que hoje **31 de 31** registros não têm a chave (§2.6), esse predicado liberaria devolutiva para *todo mundo*, inclusive para quem faltou, exatamente pelo motivo que ele existia para impedir.

A regra é: **só é elegível quem foi afirmado presente.** `ausente` não enfileira, e `ausência de dado` também não. Um filtro de segurança que trata desconhecido como permitido não é filtro — é enfeite.

Vale para o predicado **e** para o outbox: os dois checam a mesma coisa, do mesmo jeito.

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

### 2.7 O app mente igual — e mente na cara do professor

Consertar só o banco não resolve, porque o cliente repete a mesma regra. Em `src/features/registro/texto.ts`:

```ts
export function presencaDaFatia(f: RegistroRow): 'presente' | 'ausente' {
  return (f.campos.presenca as string) === 'ausente' ? 'ausente' : 'presente'
}
```

O tipo de retorno **não tem o terceiro caso**. Chave faltando → `'presente'`. E isso não fica escondido numa variável: é o que desenha o **selo verde "presente"** no card do aluno na tela de Confirmar (`Confirmar.tsx:316-319`), e o que decide quais fatias entram na gravação (linhas 82 e 118).

Isso é pior que o default do banco. No banco é uma suposição silenciosa; **na tela é uma afirmação exibida.** O professor lê "presente", entende que o sistema sabe disso, e confirma. Ele está endossando um fato que ninguém apurou — e não tem como perceber, porque a tela não distingue "ele estava lá" de "ninguém disse".

Enquanto isso existir, apertar "Confirmar" não significa o que a gente acha que significa. **`presencaDaFatia` ganha o terceiro estado `'nao_informada'`, e o selo passa a dizer isso.**

### 2.8 A pendência tem que ter resposta na tela — hoje não tem

Eu tinha escrito "vira pendência, e o app pede ao professor que marque". Fui ver o app: **a pendência não pede nada.** É texto morto (`Confirmar.tsx:231-247`) — uma lista `<li>` com nome e motivo, sem botão, sem ação, sem caminho de volta.

E ela é indexada por fatia:

```ts
const nome = (fatias.find((f) => f.id === p.fatia_id)?.aluno_nome) ?? 'Aluno'
```

Numa aula 1:1 **não existe fatia**. O `find` não acha nada, e o professor lê **"Aluno: presença não informada"** — sem nome, sem botão, sem saída. A tela não trava por bug; ela trava porque não foi feita pra responder.

Hoje isso quase não aparece (os motivos atuais são estruturais e raros). Transformar presença faltante em pendência tornaria esse beco **o caminho normal** — e, dado o §2.6, o caminho de **100%** dos registros.

**O contrato do conserto — produtor, banco e app na mesma leva:**

1. **Presença é enum obrigatório no produtor.** `presente` ou `ausente`, sem terceira opção implícita. Quem produz registro (Alma/Hermes, chamada manual, app) declara; ninguém deduz. Enquanto não vier, o valor é `nao_informada` **explícito** — que é diferente de vazio, porque vazio se confunde com "esqueci de olhar".
2. **Ramo 1:1 checa ausência** igual ao de turma: não grava no prontuário, não vira `gravado_emusys`, não enfileira devolutiva.
3. **Some o `coalesce` do banco e do cliente.** `presencaDaFatia` passa a devolver `'presente' | 'ausente' | 'nao_informada'`, e o selo diz o que é.
4. **A pendência passa a ser respondível, com contrato genérico por alvo** — não por fatia:

   | Campo | Serve pra quê |
   |---|---|
   | `registro_alvo_id` | a linha, seja fatia ou raiz 1:1 |
   | `tipo_alvo` | `raiz` \| `fatia` — a tela não precisa adivinhar procurando na lista |
   | `aluno_id` / `aluno_nome` | pra falar o nome do aluno, não "Aluno" |
   | `campo_obrigatorio` | `presenca` hoje; amanhã outro campo entra sem redesenhar nada |
   | `valores_permitidos` | `['presente','ausente']` — a tela desenha os botões a partir do contrato |

   Mais uma RPC que **grava a escolha e reenvia a confirmação**, para o professor não ter que refazer o caminho.

5. **Perguntar antes, não depois.** O lugar certo da pergunta é o card do aluno, junto do selo, **antes** de o professor apertar Confirmar — não numa lista de erro depois que a gravação falhou. Pendência é a rede de segurança; o fluxo normal é responder onde ele já está olhando.

Com o item 5 no lugar, o item 4 vira exceção rara em vez de porta de entrada.

#### Sobre o gate que eu tinha proposto e depois derrubei

Na rodada anterior eu escrevi um gate ("só sobe a regra depois de ver um registro pós-patch com a chave") e na seguinte derrubei ele, argumentando que a tela pergunta. As duas versões estavam erradas pelo mesmo motivo: **um registro observado prova que aquele caminho funcionou uma vez, não que todos os ingressos produzem presença válida.**

O que fica no lugar não é gate de calendário, é prova de cobertura: **os dois formatos — turma e 1:1 — passam ponta a ponta pelo ingresso que o Matheus usa de verdade**, com presença chegando declarada. Enquanto isso não estiver provado, a tela perguntando é a rede, e o predicado que falha fechado (§2.4) é o fundo do poço. Nenhum dos dois substitui a prova.

### 2.9 Estado hoje

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

Por isso existe o estado `aguardando_destinatario`: o worker resolve o destinatário **antes** de montar o prompt, e se não conseguir decidir, para ali. Nada de texto gerado no escuro.

#### A saída desse estado precisa ser durável

"O Fábio pergunta ao professor" era intenção minha, não contrato. Um estado sem saída definida é onde as coisas somem: ninguém consulta, ninguém é cobrado, e a devolutiva fica parada para sempre sem nunca aparecer como problema. **Estado de espera sem dono é vazamento com aparência de fila.**

O contrato:

1. **A pergunta é uma entrega, não um recado solto.** Ela passa pelo mesmo caminho de §7.4 — outbox atômico com a entrada em `aguardando_destinatario`, ida ao canal com recibo. Se o Fábio não conseguiu perguntar, isso fica registrado; a linha não fica "esperando" uma pergunta que nunca saiu.
2. **A resposta escreve na linha, com origem, e devolve à fila.** E ela não escreve no mesmo campo que a inferência: entra em **`destinatario_override`**, separado de `destinatario`.

   | Campo | Papel |
   |---|---|
   | `destinatario` | o que o sistema inferiu da idade |
   | `destinatario_override` | o que o **professor decidiu**; quando existe, **manda** |
   | `destinatario_origem` | `idade` \| `professor` — de onde veio a decisão vigente |
   | `destinatario_decidido_por` / `_em` | quem respondeu e quando: o recibo da escolha |

   Campo separado porque, se a resposta humana caísse por cima de `destinatario`, qualquer reprocessamento futuro a sobrescreveria com a inferência de novo — e ninguém notaria, porque o campo pareceria "só preenchido". **É o `destinatario_override` que destrava a geração**, e é ele que o worker lê primeiro.
3. **Existe prazo.** Passados 7 dias sem resposta, a linha vai para `descartada` com motivo `sem destinatario definido`. Devolutiva de aula tem validade: uma que chega três semanas depois não serve pra ninguém, e é mais honesto encerrar do que manter viva uma promessa parada.
4. **Existe visibilidade.** As linhas em `aguardando_destinatario` aparecem na auditoria do Fábio, junto com `falhou` — porque as duas dizem a mesma coisa para quem cuida do sistema: **tem devolutiva que não chegou em ninguém.**

`aguardando_desde` (timestamptz) entra na tabela para sustentar os itens 3 e 4.

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
| `destinatario` | text | `responsavel` \| `aluno` — o que a **idade** inferiu |
| `destinatario_override` | text | o que o **professor decidiu**; quando existe, manda (§4.5) |
| `destinatario_origem` | text | `idade` \| `professor` — de onde veio a decisão vigente |
| `destinatario_decidido_por` | integer | quem respondeu, quando veio do professor |
| `destinatario_decidido_em` | timestamptz | recibo da escolha |
| `destinatario_nome` | text | nome usado no vocativo, ou null quando não há responsável cadastrado |
| `idade_na_geracao` | integer | a idade que decidiu o destinatário, congelada |
| `texto_normal` | text | versão 1 |
| `texto_apoio_casa` | text | versão 2 |
| `skill_id` | uuid → `fabio_skills(id)` | quem escreveu |
| `skill_versao` | integer | cópia do número da versão, para ler sem join |
| `status` | text | `pendente` \| `gerando` \| `aguardando_destinatario` \| `gerada` \| `oferecida` \| `entrega_incerta` \| `falhou` \| `descartada` |
| `lease_token` | uuid | dono da **geração** (`gerando`); toda escrita exige (§7.2). O lease da **entrega** mora em `fabio_notificacoes` (§7.5) |
| `lease_expira_em` | timestamptz | prazo do lease |
| `proxima_tentativa_em` | timestamptz | backoff real; o claim ignora quem ainda não venceu (§7.2) |
| `aguardando_desde` | timestamptz | quando entrou em `aguardando_destinatario`; sustenta o prazo de 7 dias (§4.5) |
| `envio_chave` | text | chave de idempotência reservada **antes** de chamar o canal (§7.4c) |
| `envio_recibo` | text | id da mensagem devolvido pelo canal; é ele que prova que saiu (§7.4c) |
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

#### c) Entre o envio e o recibo existe uma janela — e ela duplica

"Só marca depois do recibo" resolve o otimismo e cria um pessimismo:

```
10:00:00  worker manda pro WhatsApp        → chegou no professor
10:00:01  worker tenta gravar 'oferecida'  → conexão cai
10:05:00  retry: a linha ainda está 'gerada'
          → manda DE NOVO
```

O professor recebe a mesma devolutiva duas vezes. Marcar antes duplicaria a contagem; marcar depois duplica a **mensagem** — que é o dano pior, porque quem vê é ele.

**A saída é a reserva antes do envio.** A tentativa de entrega tem **claim e token próprios**, iguais aos da geração (§7.2) — não basta o token de quem gerou, porque gerar e entregar são trabalhos diferentes e falham em momentos diferentes. O worker escreve uma **chave de idempotência** na linha *antes* de chamar o canal (`envio_chave`, uma por `devolutiva_id`). O envio carrega essa chave quando o canal aceita chave; o recibo do canal (`wa_message_id`, que `fabio_chat_mensagens` já guarda) volta para a linha.

No retry:

1. **recibo gravado** → não reenvia; só completa a transição para `oferecida`;
2. **chave reservada sem recibo** → a entrega é **incerta**: pode ter chegado ou não;
3. **sem chave** → primeira vez, envia.

#### O caso 2 é o honesto, e ele não vira "exactly once"

O WhatsApp não devolve garantia de que uma mensagem que a gente não conseguiu anotar não chegou. Prometer entrega exatamente uma vez em cima de um transporte que não prova isso seria mentira de arquitetura — o mesmo tipo de mentira que o `gravado_emusys` conta hoje.

Então o sistema **não reenvia sozinho** no caso 2. A linha vai para `entrega_incerta` e aparece na auditoria junto com `falhou`. Um humano decide, porque só ele pode olhar a conversa e ver se chegou.

A escolha é deliberada: **entre mandar duas vezes a mesma devolutiva pro professor e assumir que não sei, prefiro assumir que não sei.** Reenvio automático transforma uma dúvida em uma certeza errada, e quem paga é o professor, que passa a desconfiar do que o Fábio manda. Dúvida visível é barata; mensagem duplicada corrói confiança.

A garantia que este desenho oferece, escrita sem enfeite: **no máximo um envio por reserva; toda ambiguidade fica visível e nomeada.** Não é exactly-once, e não vai ser chamada assim em lugar nenhum.

Sem isso, `oferecida` só descreve o que a gente **conseguiu anotar** — não o que o professor **recebeu**. As duas coisas divergem exatamente nas falhas, que é quando a informação importa.

### 7.5 O claim da entrega: onde ele mora de verdade

A auditoria pediu para o claim/token da entrega ficar explícito no schema **ou** apontar para o lease que já existe em `fabio_notificacoes`. Fui conferir se dava pra apontar. **Não dá: não existe lease lá.**

`fabio_claim_notificacao` reivindica por **troca de status** (`'processando'`), e a janela de reivindicação é esta:

```sql
or (fabio_notificacoes.status = 'processando'
    and fabio_notificacoes.criado_em < now() - interval '10 minutes')
```

Três problemas, em ordem de gravidade:

**a) O relógio está errado.** A janela mede `criado_em` — quando a **linha nasceu** — e não quando ela foi reivindicada. Uma notificação criada há 11 minutos e reivindicada há 5 segundos já é considerada abandonada: o worker seguinte a rouba na hora, com o primeiro ainda enviando. Não é uma corrida improvável, é o comportamento normal de qualquer linha que passou dez minutos na fila.

**b) Não há token, então não há cerca.** Nada impede o worker antigo de escrever `enviada` depois que o novo já enviou. Os dois escrevem na mesma linha e não sobra rastro — é o mesmo defeito que a auditoria da rodada 2 apontou na devolutiva, vivo aqui desde sempre.

**c) A chave de deduplicação não cobre um tipo novo.** O `on conflict` mira o índice parcial `where tipo in ('briefing_matinal','pendencia_registro')`. Uma linha `devolutiva_pronta` simplesmente **nunca conflita** — insere de novo a cada tentativa, sem dedupe nenhum.

Ou seja: a promessa do §7.4c não tinha casa, e a casa que eu ia apontar tem o mesmo buraco.

#### O contrato

**Uma dona só do fato "esta entrega está sendo tentada": `fabio_notificacoes`.** É lá que a entrega acontece; duplicar lease em `fabio_devolutivas` criaria dois donos da mesma verdade, que é como se perde a coerência.

Colunas novas em `fabio_notificacoes` (aditivas, nenhuma quebra):

| Coluna | Papel |
|---|---|
| `lease_token` | uuid do dono da tentativa; **toda** escrita de conclusão exige |
| `lease_expira_em` | prazo real — carimbado **na reivindicação**, não na criação |
| `proxima_tentativa_em` | backoff; o claim ignora quem ainda não venceu |
| `envio_recibo` | id da mensagem devolvido pelo canal (§7.4c) |

E os índices/RPCs:

1. **Índice único parcial novo** para notificação de referência: `(referencia_tipo, referencia_id, canal) where referencia_tipo = 'devolutiva'`. A chave atual é por dia, e um professor tem várias devolutivas no mesmo dia.
2. **RPC própria** `fabio_claim_notificacao_por_referencia(...)`, com `ON CONFLICT` nesse índice. Não dá pra reaproveitar a RPC atual: **um `INSERT` só tem um alvo de conflito**, e os dois tipos de chave são incompatíveis.
3. **`fabio_claim_notificacao` é corrigida na mesma leva** — `lease_expira_em` no lugar de `criado_em`, token exigido na conclusão. O briefing sofre do mesmo defeito hoje, e já caiu uma vez por conta de contrato de chave (03/08). Consertar só o caminho novo deixaria o caminho antigo quebrado com a desculpa de que "sempre foi assim".

> ⚠️ Índice novo = `ON CONFLICT` novo, **na mesma leva**. Já custou o briefing inteiro uma vez (`42P10`). E a mudança de `fabio_claim_notificacao` roda no harness de `BEGIN; … ROLLBACK;` com duas conexões simultâneas antes de ser aplicada — claim é código de concorrência, e concorrência não se testa lendo.

`fabio_devolutivas.envio_chave` continua onde está: ela é a chave de idempotência **daquela devolutiva**, o que a linha de notificação não pode saber. O recibo mora nas duas: em `fabio_notificacoes` como fato do transporte, e espelhado em `fabio_devolutivas.envio_recibo` como prova ligada à devolutiva.

### 7.6 `fabio_skills`

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
| **Presença faltando virar "presente"** | `coalesce` sai do banco **e** do cliente; vira `nao_informada` visível (§2.7) |
| **Professor endossar presença que ninguém apurou** | O selo para de dizer "presente" sem evidência; a pergunta vai pro card do aluno, antes do Confirmar (§2.7, §2.8) |
| **Pendência sem resposta possível na tela** | Payload por `registro_id` (serve fatia e 1:1) + ação Esteve/Faltou; hoje é `<li>` sem botão (§2.8) |
| **Predicado deixar passar quem nunca foi marcado presente** | `= 'presente'`, nunca `<> 'ausente'`. Falha fechada no predicado **e** no outbox (§2.4) |
| **Mesma devolutiva enviada duas vezes** | Claim/token na entrega, com colunas reais em `fabio_notificacoes` (§7.5) + chave reservada antes do envio; ambiguidade vira `entrega_incerta`, não reenvio (§7.4c) |
| **Worker roubar entrega que outro está fazendo** | Hoje a janela de reivindicação mede `criado_em`, não a hora do claim — qualquer linha com mais de 10 min é roubável na hora. Passa a medir `lease_expira_em` (§7.5a) |
| **Notificação de devolutiva sem deduplicação** | O `ON CONFLICT` atual só cobre `briefing_matinal`/`pendencia_registro`; um tipo novo nunca conflita e insere a cada tentativa. Índice parcial + RPC próprios (§7.5c) |
| **Decisão do professor sobre destinatário ser sobrescrita** | `destinatario_override` em campo separado da inferência, com origem e recibo (§4.5) |
| **Devolutiva presa em `aguardando_destinatario` pra sempre** | Pergunta com recibo, resposta que grava decisão, prazo de 7 dias e visibilidade na auditoria (§4.5) |
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
7. **Registro sem a chave `presenca` não mostra "presente" em lugar nenhum** — nem no selo do card, nem no banco. A tela pergunta antes do Confirmar, e a resposta grava (§2.7, §2.8).
7b. **Pendência de aula 1:1 aparece com o nome do aluno e um botão que resolve** — hoje aparece "Aluno" e nada (§2.8).
7b2. **Cobertura do ingresso:** turma **e** 1:1 passam ponta a ponta pelo caminho que o Matheus usa de verdade, com presença chegando **declarada** — não um registro observado, os dois formatos (§2.8).
7c. **Registro sem presença declarada não enfileira devolutiva** — nem com a chave ausente, nem com valor estranho. Só `= 'presente'` passa (§2.4).
7d0. **Enviar e falhar ao anotar não duplica a mensagem:** matar o worker entre o envio e a escrita de `oferecida`; no retry o professor **não** recebe de novo — a linha vira `entrega_incerta` e aparece na auditoria (§7.4c).
7d. **`aguardando_destinatario` tem saída:** a pergunta sai com recibo, a resposta devolve à fila, e passados 7 dias sem resposta a linha vira `descartada` — nunca fica parada em silêncio (§4.5).
8. **Fencing da geração:** simular worker expirado voltando depois de outro ter concluído — a escrita velha afeta **zero linhas** e é descartada (§7.2).
8b. **Fencing da entrega, com duas conexões de verdade:** `BEGIN; … ROLLBACK;` em duas sessões simultâneas provando que (i) o segundo worker **não** rouba uma linha reivindicada há segundos, mesmo que a linha tenha nascido há mais de 10 minutos; (ii) o worker velho não consegue escrever conclusão sem o token vigente (§7.5). Claim é código de concorrência — ler o SQL não prova nada.
9. **Outbox:** derrubar o worker entre gerar e notificar — não existe devolutiva `gerada` sem linha de notificação (§7.4a).
10. O Alf lê os primeiros textos e aprova o tom antes de qualquer professor além do Matheus.
11. Com os carimbos de §7.1: o professor encaminha sem editar em pelo menos metade dos casos. Se ele reescreve sempre, o texto está errado — não o professor.
