# Devolutiva de aula — design

**Data:** 03/08/2026
**Status:** design aprovado pelo Alf (seções 1–3 validadas em conversa); spec aguardando review
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

**Predicado correto:** fatia com `parent_id is not null` **e** `status = 'gravado_emusys'` **e** `confirmado_em is not null`.

*Nota de nomenclatura:* `gravado_emusys` hoje mente — o texto do Fábio não chega ao campo `anotacoes` do Emusys (auditoria pendente, thread separada). Isso não afeta este design: o que o predicado usa é "o professor confirmou e havia conteúdo", e disso o status é prova. Se o nome do status for corrigido depois, este é um dos pontos a atualizar junto.

### 2.3 Estado hoje

15 fatias já passaram por esse caminho (13–17/07/2026), todas terminando em `gravado_emusys`. Nenhuma fatia jamais terminou em `confirmado` — o ramo do aluno ausente **nunca rodou em produção** e precisa de teste explícito.

### 2.4 O gancho não pode quebrar a confirmação

`app_confirmar_registro` já chama `fabio_emitir_presenca_por_registro` dentro de `begin/exception when others`. A devolutiva segue a mesma disciplina: **enfileira, não gera.** A RPC de confirmação insere uma linha em `fabio_devolutivas` com `status = 'pendente'` e volta. A geração do texto (que envolve LLM) acontece fora, no worker. Confirmar registro nunca pode falhar porque a devolutiva falhou.

---

## 3. De onde sai o conteúdo

### 3.1 A fonte é a mesma do prontuário

`fn_compor_texto_prontuario(tronco.campos, fatia.campos)` já é a função que mescla o contexto da aula (tronco) com o que é daquele aluno (fatia). É o texto que vai para o prontuário.

**A devolutiva lê exatamente essa composição.** Não relê os `campos` por conta própria e não reinterpreta o áudio. Motivo: se o professor confirmou aquele texto, é aquele texto que ele endossou. Uma segunda leitura independente abriria espaço para a devolutiva dizer algo que o prontuário não diz — e o professor descobriria isso na frente do responsável.

### 3.2 Os campos variam por molde

Hoje só existe o molde `C`, e as chaves que aparecem nas fatias são: `progresso`, `proximo_passo`, `observacao`, `repertorio`, `dever_casa` — mais chaves específicas de molde (`eixos`, `marco_ref`, `atividades`, `materiais`, `objetivo`, `obs_gerais`).

**O gerador é tolerante a molde:** trabalha com o texto composto e com as chaves que existirem, nunca com uma lista fixa. Molde novo não pode quebrar devolutiva.

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
| Menores de 15 **sem** `responsavel_nome` | **6 (0,5%)** |

A regra cobre a base inteira, e o caminho do responsável é a maioria — não a exceção.

### 4.3 Idade vem de `data_nascimento`, não de `idade_atual`

`alunos.idade_atual` é um número guardado; ele envelhece errado (fica parado enquanto o aluno faz aniversário). Hoje 3 alunos ativos já divergem do cálculo — nenhum deles cruzando os 15 anos, mas é questão de tempo.

**A idade é calculada de `data_nascimento` no momento da geração.** O custo é zero e elimina a classe inteira de bug "o aluno virou 15 e o texto continuou falando com a mãe".

### 4.4 Os 6 sem nome do responsável

Sem `responsavel_nome`, o texto fala com a família **sem vocativo nominal** ("Passando pra contar como foi a aula do Gustavo hoje…") e o Fábio avisa o professor na entrega: *"não tenho o nome do responsável do Gustavo — se quiser, me fala que eu ajusto."* Nunca inventa nome, nunca escreve "Sr(a). Responsável".

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
| `status` | text | `pendente` \| `gerada` \| `entregue` \| `falhou` \| `descartada` |
| `erro` | text | quando `falhou` |
| `tentativas` | integer | backoff do worker |
| `entregue_em` | timestamptz | quando o Fábio ofereceu ao professor |
| `criado_em` / `atualizado_em` | timestamptz | |

**Índice único em `registro_fatia_id`.** Uma fatia gera uma devolutiva; reconfirmar não duplica.

> ⚠️ Índice único e `ON CONFLICT` são **um contrato só**. Quem mexer num, mexe no outro na mesma leva. Em 03/08/2026 o briefing matinal parou inteiro (`42P10`) porque o índice mudou e a RPC ficou apontando para a chave antiga.

`idade_na_geracao` é congelada de propósito: daqui a um ano, olhando um texto que fala com a mãe, dá pra saber que na época estava certo.

### 7.2 `fabio_skills`

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
        │                        só para fatia status='gravado_emusys'
        │                        (nunca para ausente)
        ▼
fabio_devolutiva_worker.py (VPS, timer systemd user)
  ├─ lê a fatia + tronco via fn_compor_texto_prontuario
  ├─ calcula idade de data_nascimento → destinatário
  ├─ carrega fabio_skills ativa de devolutiva_aula
  ├─ gera as DUAS versões numa chamada
  └─ status='gerada', skill_versao=N
        │
        ▼
Fábio oferece ao professor (chat do app + WhatsApp, conforme canal_preferido)
  "Terminei o registro do Gustavo. Quer a devolutiva pra mandar pra mãe dele?"
        │
        ▼
professor lê, ajusta por áudio ou texto se quiser, encaminha
        └─ status='entregue'
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
| Gatilho pegar aluno ausente | Predicado exige `status='gravado_emusys'`; teste explícito do ramo ausente (nunca rodou em produção) |
| Texto sair acusatório | Regra escrita na skill + revisão do Alf antes de ligar para qualquer professor além do piloto |
| LLM inventar fato que não estava no registro | Fonte é `fn_compor_texto_prontuario`; a skill proíbe acrescentar conteúdo |
| Devolutiva quebrar a confirmação do registro | Confirmação só enfileira; geração roda fora, no worker |
| Duplicar devolutiva em reconfirmação | Único em `registro_fatia_id` |
| Professor achar que o Fábio já mandou pra família | Texto do oferecimento diz explicitamente "pra você mandar" |

---

## 11. Como saber se funcionou

Piloto com o Matheus, mesmo professor do briefing matinal.

1. Uma fatia confirmada gera exatamente uma devolutiva, nas duas versões.
2. Aluno de 8 anos → texto fala com o responsável, pelo nome. Aluno de 16 → fala com o aluno.
3. Aluno marcado ausente → **nenhuma** devolutiva.
4. O Alf lê os primeiros textos e aprova o tom antes de qualquer professor além do Matheus.
5. O professor encaminha sem editar em pelo menos metade dos casos — se ele reescreve sempre, o texto está errado, não o professor.
