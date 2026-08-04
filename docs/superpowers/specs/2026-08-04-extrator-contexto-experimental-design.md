# Extrator de contexto da aula experimental — design

**Data:** 04/08/2026 · **Autor:** Claude, com Alf · **Estado:** aprovado, pronto para plano

## O problema, com evidência

O professor entra numa aula experimental sem saber nada de quem vai receber. A
informação existe — só não chega nele.

A conversa da Mila com a família tem **35 a 56 mensagens** e cobre nome do
responsável, idade, nível, gosto musical e motivação. O que sobrevive disso é o
campo `observacoes` do Emusys: no melhor caso, oito palavras que alguém digitou
com pressa. Nos Andrade, o campo está **vazio** — e a conversa tinha que os dois
filhos já tocavam piano em Portugal e pediram para voltar.

Levantamento de 04/08 (`docs/experimentais-expectativa-chatwoot-2026-08-04.md`):

| | |
|---|---|
| Experimentais futuras | 17 |
| Com observação no Emusys | 10 (2 são a mesma aluna duplicada) |
| **Com qualificação real na conversa** | **6 de 7 das que estavam vazias** |
| Experimentais que já viraram aluno | **319** |
| Desses, na carteira de um professor hoje | **73** |
| Alunos com anamnese hoje | 21 |

Os 73 são o argumento: **o contexto da experimental cobriria mais que o triplo do
que a anamnese cobre**, e são pessoas em aula agora.

E o dado da conversa é mais fresco que o do banco. Em 04/08 o banco dizia que os
Andrade tinham aula às 17h; a conversa daquela manhã dizia que a família cancelou.

## O que este projeto faz

Um extrator lê a conversa inteira da Mila, trata com LLM e grava um bloco
estruturado em `lead_experimentais`. O Fábio lê esse bloco pela mesma porta por
onde já lê o resto do prontuário.

**Não faz parte deste projeto** (cada um é sua própria spec): a skill de condução
da aula experimental, a exibição na agenda do professor, e o aviso proativo.

---

## Arquitetura

### Onde roda

**Edge function no Supabase**, projeto `ouqwbbermlzqqvtqwlul`. Não na VPS do
Fábio.

Três razões: é o padrão da casa (`pg_cron` → `net.http_post` → edge function, e o
`debug-webhook-emusys-observador` do Hugo já é assim); a `GEMINI_API_KEY` já está
nos secrets de lá, usada pela `notificar-anamnese`; e isto é **dado comercial** —
manter o extrator do lado do LA Report deixa a fronteira onde ela já está. A VPS
é o território do Fábio, que fala com professor.

### Gatilho

`pg_cron` de hora em hora chama a edge function. Ela seleciona as experimentais
que atendem **todas** estas condições:

- `data_experimental` entre hoje e hoje + 7 dias
- e (`contexto_ia is null` **ou** a maior `id` de mensagem da conversa é maior que
  `contexto_ia->'procedencia'->>'ultima_mensagem_id'`)

A comparação é por **id de mensagem, não por data**: mensagens do mesmo dia
levariam o extrator a se considerar atualizado e perder o que chegou depois.

Não é varredura cega. A releitura por mensagem nova é obrigatória porque a
conversa continua depois do agendamento: o Rafael remarcou cinco dias depois, os
Andrade cancelaram no dia.

### O que lê — duas fontes, sempre

**1. A conversa no Chatwoot** (conta 5, `crmchat.agenticflowio.com.br`).
Caminho: `contacts/search?q=<telefone>` → `contacts/:id/conversations` →
`conversations/:id/messages`, **paginando com `before=<menor_id>` até o início**.

> ⚠️ **A paginação não é detalhe, é o requisito.** A API devolve as ~20 mensagens
> mais recentes por padrão, e a qualificação da Mila está sempre nas **primeiras**.
> Um extrator que leia só a última página captura "pode ser quarta?" e perde tudo
> que importa. Este documento existe porque foi exatamente esse o erro cometido na
> primeira apuração.

As inboxes da Mila são `Mila_Barra` (147), `Mila_Recreio` (148) e `Mila_CG` (155),
distintas das de secretaria. A conversa pode conter mensagens da Mila (bot) e de
humano que assumiu — **as duas entram**, porque a qualificação é da Mila e a
negociação de horário é do humano.

**2. O campo `observacoes`** de `lead_experimentais` (o que a recepção digitou).

Nenhuma das duas cobre sozinha: a conversa da Isadora tinha "músicas infantis e
sertanejo"; o campo do Bernardo tinha "mãe ex-aluna", que não está na conversa.

### O que escreve

Duas colunas novas em `lead_experimentais`:

```sql
alter table lead_experimentais
  add column contexto_ia     jsonb,
  add column contexto_ia_em  timestamptz;
```

**Nunca escrever em `observacoes`.** Aquele campo tem dono: o Emusys o envia a
cada webhook e o backfill do Hugo veio de lá. Dois donos no mesmo campo significa
que a extração some no próximo evento e ninguém sabe quem escreveu o quê.

### Como o Fábio consome

`vw_fabio_contexto_experimental` aplica a fronteira (só as chaves permitidas) e
resolve o vínculo com o aluno. `fabio_prontuario_aluno` compõe o bloco
`experimental` junto de `cadastro`, `anamnese` e `linha_do_tempo`, fazendo o
guard de professor **uma vez só**, como já faz desde a migration 026.

**A porta é a função, não a view.** View não recebe parâmetro e por isso não sabe
quem está perguntando. As duas alternativas seriam confiar no chamador filtrar
(foi assim que o selo verde de presença mentiu por meses) ou RLS via JWT — que
não funciona aqui, porque o bridge conecta com `service_role` e passa por cima.

> **O vínculo com o aluno é por `leads.aluno_id`, não por
> `lead_experimentais.aluno_id`.** O primeiro tem 319 preenchidos, o segundo 81.
> Quem usar o campo de nome óbvio perde três quartos dos casos.

---

## O formato de saída

O JSON segue os **cinco momentos da aula experimental** do material da LA
(recepção → aquecimento → conexão → encerramento → devolutiva), para o professor
ler na ordem em que vai usar.

```json
{
  "recepcao": {
    "responsavel": "Melissa",
    "aluno": "Daniela",
    "data_nascimento": "2013-07-25",
    "junto_com": "irmão Pedro, 9 anos, na aula seguinte às 17h30"
  },
  "quem_e_esse_aluno": {
    "nivel_declarado": "ja_tocava",
    "historia": "Fazia aulas de piano em Portugal e pediu para voltar.",
    "de_quem_partiu": "do aluno"
  },
  "ganchos_de_conexao": [
    "já se interessou por canto — hoje pede piano",
    "a mãe topa experimentar outro instrumento além do piano"
  ],
  "para_a_devolutiva": {
    "o_que_a_familia_espera": "continuidade do que os filhos já faziam",
    "atencao_conversao": "alta",
    "porque": "perguntou preço no início e não foi respondida"
  },
  "apoio_declarado": null,
  "alertas": [
    { "tipo": "agenda", "texto": "cancelou 04/08 por motivo familiar; remarcar" }
  ],
  "procedencia": {
    "fonte": "conversa Mila + recepção",
    "contato_id": 264187,
    "conversa_id": 18742,
    "ultima_mensagem_id": 9931455,
    "ultima_mensagem_em": "2026-08-04",
    "mensagens_lidas": 51,
    "modelo": "gemini-3.6-flash",
    "extraido_em": "2026-08-04T20:15:00Z"
  }
}
```

### Vocabulário fechado

- `nivel_declarado`: `iniciante` | `ja_tocava` | `nao_informado`
- `de_quem_partiu`: `do aluno` | `dos pais` | `de terceiro` | `nao_informado`
- `atencao_conversao`: `alta` | `normal` | `nao_informado`
- `alertas[].tipo`: `agenda` | `saude_agenda` | `acessibilidade`

Campo sem informação vem `null` ou `nao_informado` — **nunca inventado**. Vazio
honesto é resposta; vazio preenchido por palpite é ruído que o professor não tem
como conferir.

### Quatro decisões dentro do formato

**`data_nascimento`, não `idade`.** A idade sai de `age(data_nascimento)` na
view, sempre recalculada. A observação da Isadora dizia "6 meses" porque foi
escrita em novembro/2025 a partir da conversa daquela época; a aula é 15/08/2026
e ela tem 1 ano e 3 meses. Em musicalização para bebês isso é outra aula.
**O texto guarda intenção — "a pediatra indicou" não envelhece. A idade é fato
datado e se recalcula.**

**`atencao_conversao` sem número.** O professor não vê preço, forma de pagamento
nem negociação — ele não decide nada disso e saber que a família pechinchou muda
como ele olha a criança sem ajudar ninguém. Mas ele **precisa saber que tem de
mostrar valor na devolutiva**. O sinal chega, o bolso da família não.

**`apoio_declarado` em linguagem de condução.** Neurodivergência e necessidade de
apoio são relevantes — o professor precisa. Mas o texto é *"responde melhor a
instrução curta, uma coisa de cada vez; os pais relataram suporte nível 1"*, e
não um rótulo solto. O que muda a aula, com a origem preservada.

**`ganchos_de_conexao` é lista.** O momento 3 da aula é criar vínculo; o
professor quer duas ou três coisas concretas para puxar, não um parágrafo para
interpretar no corredor.

---

## Fronteira

**A estrutura é a fronteira, não o prompt.** Campos de dinheiro, negociação e
recado interno **não existem no schema de saída** — não há onde escrevê-los. A
view valida chave por chave e descarta o que não estiver na lista.

Isso vem de erro real: a `notificar-anamnese` tem a regra *"foque em adaptação,
não em rótulos de diagnóstico"* no prompt do Gemini, e mesmo assim manda
diagnóstico cru para o WhatsApp do professor — porque a parte fixa da mensagem
não passa por IA nenhuma. **Instrução em prompt não é fronteira.** É a mesma
lição da `fn_devolutiva_fonte`, que é lista de permissão no banco.

Fica de fora, explicitamente: valor da mensalidade, condição de pagamento,
"achei caro", estágio de negociação, e recado operacional da recepção (o campo
`observacoes` da Amelie termina com *"Ajustar data de nascimento, lançamento
fictício para concluir cadastro"*).

Fica de dentro, traduzido: motivo de saúde **como aviso de agenda**
(*"pediu remarcar por motivo de saúde"*), nunca como diagnóstico da criança.

---

## Erros, reprocessamento e credenciais

**Falha não apaga o que existe.** Se o Gemini falhar ou devolver JSON inválido,
o `contexto_ia` anterior permanece e a linha é reprocessada na próxima rodada.
Extração vazia nunca sobrescreve extração boa.

**Toda rodada registra em `automacao_log`** (`evento: contexto_experimental`),
com o resultado ou o motivo da falha. O padrão de falha silenciosa com HTTP 200
já custou caro duas vezes neste projeto: o Fábio surdo a áudio e a
`notificar-anamnese`, que está com o canal morto desde 11/07 e ninguém soube
porque o erro só ia para o log sem alerta.

**Modo sombra é o estado inicial.** `EXTRATOR_DRY_RUN=true` por padrão: extrai,
grava em `contexto_ia`, e ninguém lê. A view e a composição no prontuário só
entram depois de conferirmos a qualidade sobre as 17 futuras e uma amostra das
319 antigas.

**Credencial:** o token de bot do Chatwoot não serve — a API v1 responde
`401 not authorized for bots`. O token admin funciona e foi validado (56/56
mensagens recuperadas com paginação). **Pedir ao Hugo um usuário com papel apenas
de leitura antes de ir para produção**: uma extração rodando com credencial de
escrita fica a um bug de prompt de enviar mensagem a cliente. O token vai para os
secrets do Supabase, nunca para o código — a `notificar-anamnese` tem a chave do
WhatsApp hardcoded e isso não se repete.

---

## Como se prova que funciona

**Teste de SQL com mutantes** no padrão da casa — migration `027`, com
`027-*.test.sql` e `npm run teste:027` (a última aplicada é a 026). Mutantes
obrigatórios, cada um matando um erro já cometido:

1. idade lida do texto em vez de calculada da data → morre no caso Isadora
2. extrator lê só a última página da conversa → morre porque a qualificação some
3. campo de dinheiro atravessa a view → morre na fronteira
4. extração vazia sobrescreve extração boa → morre no reprocessamento
5. join por `lead_experimentais.aluno_id` em vez de `leads.aluno_id` → morre por
   perder 238 dos 319 vínculos
6. `contexto_ia` gravado em `observacoes` → morre por colisão com o Emusys

**Casos reais como fixture**, não sintéticos: Andrade (dois irmãos, já tocavam,
cancelamento), Isadora (idade congelada, pediatra), Davi (conversa sem resposta
do cliente — o extrator tem de devolver vazio honesto).

**E conversar com o Fábio no fim.** `falar_com_fabio.py --sem-historico`,
perguntando sobre um aluno que veio de experimental, antes e depois. Se o prompt
inchar e a resposta piorar, corta. Hoje o turno dele já roda com ~26 mil tokens;
mais contexto não é mais qualidade.

---

## Riscos conhecidos que este projeto não resolve

- **`emusys_aula_id` é id de evento, não da aula.** O mesmo agendamento da Amelie
  chegou como 73172 no n8n e 73173 no observador. Consequências já visíveis:
  Beatriz Romero duplicada (ids 1312 e 1314, mesmo lead, mesma data e hora) e a
  experimental fantasma do Rafael em 05/08, remarcada para 12/08 sem encerrar a
  antiga. O extrator convive com isso — a chave que casa 17/17 é
  `emusys_lead_id` + `data_experimental` — mas a duplicata continua existindo.
- **O Chatwoot pode ficar fora do ar.** A falha é registrada e reprocessada; o
  prontuário simplesmente não traz o bloco.
- **Nem todo lead tem conversa.** O Davi tem duas mensagens e o cliente nunca
  respondeu; agendou por outro caminho. O extrator devolve vazio, e está certo.

## Ordem de construção

1. Migração das duas colunas + teste com mutantes
2. Edge function em modo sombra + cron
3. Conferência da qualidade sobre as 17 futuras e amostra das 319 antigas
4. View com a fronteira + composição no `fabio_prontuario_aluno`
5. Verificação conversando com o Fábio

A view só nasce depois do passo 3. Fronteira se desenha sobre o que realmente
sai, não sobre o que se imagina que vai sair.
