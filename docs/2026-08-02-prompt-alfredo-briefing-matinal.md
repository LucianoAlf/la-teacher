# Prompt pro Alfredo — ligar o Briefing Matinal do Fábio (véspera da volta às aulas)

_2026-08-02 (domingo) · Alf → Alfredo · **meta: amanhã 03/08 às 8h o Matheus recebe "Bom dia, Matheus"**_

---

Fala, Alfredo! Voltando ao Fábio depois de um tempo — te trago **o diagnóstico já feito**, pra você não ter que redescobrir nada.

## 1. Onde paramos (19/jul)

Você entregou o **preview-first inerte**: MCP `fabio_presence_governance` registrado no Hermes, com `fabio_buscar_presencas_pendentes_professor` e `fabio_preview_governanca_presenca_professor`. Zero envio, zero schedule — exatamente como combinado. **Continua tudo vivo na VPS** (conferi hoje: gateway + `fabio_chat_bridge.py` + `fabio_presence_mcp.py` rodando desde 19/jul).

## 2. O que mudou no banco desde então (não te pega de surpresa)

- **Auditoria cruzada com o Codex (22/jul).** Confirmou que a promoção da migration 009 já resolvia o conflito "Emusys escreveu primeiro, professor depois" — o P0 estava fechado antes de a gente perceber.
- **`fn_presenca_e_forte` virou a MATRIZ ÚNICA oficial** de todo o ecossistema: LA Teacher, LA Report, Fábio e Sol leem a mesma régua. Ela já conhece `fabio_audio` e `professor_whatsapp`.
- **Camada semântica v1.3** (`vw_aluno_presenca_semantica_v1`): estados `presente`, `falta_confirmada`, `falta_provavel`, `indeterminado`, `aula_justificada`, `aula_cancelada`. **Nada de inferir falta por texto** — o Fábio deve ler daqui.
- **Ficha do aluno no app** já mostra a presença semântica (falta confirmada ≠ "não conferida").
- **Decisão do Alf:** professor **não** corrige a própria chamada; retificação é só da coordenação.

## 3. Diagnóstico da VPS (feito hoje, read-only)

**Está rodando:**
```
hermes_cli.main gateway run --replace --force --accept-hooks   (PID 707176, desde 19/07)
fabio_chat_bridge.py                                           (PID 705443)
fabio_presence_mcp.py                                          (PID 707188)  ← teu MCP, vivo
postgres-mcp --access-mode=unrestricted                        (PID 707186)
```

**NÃO existe (é o gap):**
- `crontab -l` → *"no crontab for fabio"*
- `systemctl --user list-timers` → só `launchpadlib-cache-clean` (lixo do Ubuntu)
- **Nenhuma função de briefing/digest/matinal** no `fabio_chat_bridge.py` (grep vazio)

→ **Tradução: o Fábio hoje é 100% reativo.** Ele responde quando falam com ele, mas **não inicia nada sozinho**. O briefing matinal bonito que o Alf validou foi gerado à mão numa conversa — nunca virou rotina.

## 4. A boa notícia: os dados e a idempotência JÁ EXISTEM

Não precisa construir nada de banco. Já está no ar, com grant pra `fabio_agent` **e** `service_role`:

| RPC | Pra quê |
|---|---|
| **`fabio_briefing_matinal(p_professor_id int, p_data date)`** | **A agenda do dia + resumo da última aula de cada aluno.** Já lê da semântica v1.3. |
| `fabio_claim_notificacao(professor_id, tipo, categoria, canal, corpo, titulo)` | **Claim com dedupe** — garante que não manda 2× a mesma notificação |
| `fabio_marcar_notificacao_enviada(notificacao_id)` | fecha o ciclo no sucesso |
| `fabio_marcar_notificacao_falhou(notificacao_id, erro)` | fecha o ciclo no erro |
| `fabio_pendencias_professor(prof)` · `fabio_presencas_pendentes_professor(prof)` | pendências (registro / presença) |
| `fabio_preferencias_professor(prof)` · `fabio_identidade_whatsapp(telefone)` | preferências e identidade |

**Teste real que rodei agora** — `fabio_briefing_matinal(25, '2026-08-03')` devolve a segunda do Matheus:
```
11:00 Canto                      → Valentina  (resumo da última aula ✓)
15:00 Canto                      → Amanda     (resumo ✓)
17:00 Musicalização Preparatória → Gustavo, Maria Isabel (resumo ✓)
18:00 Musicalização Preparatória → Arthur     (resumo ✓)
```

## 5. O pedido (o que falta pra amanhã)

**Construir a rotina de envio + agendar. Só isso.**

1. **Rotina `briefing_matinal`** no lado do Hermes:
   - chama `fabio_briefing_matinal(professor_id, hoje)`;
   - **se `aulas` vier vazio, não manda nada** (dia sem aula = silêncio);
   - formata no padrão validado (§6);
   - `fabio_claim_notificacao(...)` **antes** de enviar (dedupe: se já foi hoje, aborta);
   - envia via UAZAPI pro WhatsApp do professor;
   - `fabio_marcar_notificacao_enviada` / `..._falhou`.
2. **Agendar às 08:00 (America/Sao_Paulo)** — systemd --user timer ou cron do usuário, o que preferir. Atenção ao TZ: a VPS está em **UTC** (agora 14:40 UTC = 11:40 BRT), então 8h BRT = **11:00 UTC**.
3. **Piloto: SÓ o professor 25 (Matheus)** por enquanto. O Alf libera os outros aos poucos.

## 6. Formato validado pelo Alf (usar este)

```
Bom dia, Matheus! 🎵

Hoje você tem *4 aulas* com *5 alunos*.

*Agenda de hoje:*

• *11:00 — Canto*
  Aluna: Valentina
  *Última aula:* trabalhou "Temos que Pegar" (Pokémon), foco em pegar e decorar a letra.

• *17:00 — Musicalização Preparatória*
  Alunos: Gustavo e Maria Isabel
  *Última aula:* atividade com bambolês, bolinha e sino — nota correspondente.

Se quiser preparar alguma aula específica, me manda o nome do aluno.
```

Regras de tom (contrato de alerta v1): parceiro de sala, **sem cobrança policial**; se não houver conteúdo, escreve *"Sem conteúdo registrado da última aula."* — **nunca inventa**.

⚠️ **Ponto de atenção:** o `resumo_ultima_aula` vem como texto corrido truncado (~110 caracteres). Se quiser o formato rico do Alf (**Foco / Trabalho feito / Música**) em campos separados, tem 2 caminhos: (a) a Alma formata a partir do texto agora, ou (b) eu amplio a RPC pra devolver os campos estruturados do registro (`objetivo`, `conteudo`, `repertorio`…). **Me fala qual você prefere que eu faço a (b) hoje mesmo.**

## 7. O outro ponto crítico de amanhã — presença por áudio

O Alf quer confirmar: **"quando o professor grava o conteúdo, já dá presença automaticamente"**. Estado real, hoje:

- presenças com fonte `fabio_audio` no banco: **0**
- registros com `campos.presenca`: **0**
- último áudio real processado: **17/07** — *um dia antes* do teu patch `ba1ca01`

Ou seja: **o caminho nunca rodou com áudio real depois da correção.** A guarda `sem_sinal_de_presenca_no_registro` faz um no-op seguro (não marca ninguém errado, não trava a chamada manual), mas também não emite a presença se o Hermes não mandar `campos.presenca` nas fatias.

→ **Pedido:** quando o Matheus gravar o primeiro áudio amanhã, me avisa que eu acompanho no banco os 5 passos (fila → registro → `campos.presenca` → emissão → linha `fabio_audio`). Se travar, o diagnóstico é rápido.

## 7.1 ⚠️ GOVERNANÇA — a régua certa é CONTEÚDO, nunca presença

Decisão do Alf (reafirmada hoje): **o Fábio NÃO cobra presença do professor.** O áudio/conteúdo já emite a presença — não existem duas camadas. Cobrar as duas coisas seria pedir trabalho dobrado por algo que o sistema resolve sozinho.

**E os números provam que isso não é filosofia — é proteção.** Rodei as duas filas do prof 25 hoje:

| Fila | RPC | Resultado (prof 25) |
|---|---|---|
| **CONTEÚDO** (registro) | `fabio_pendencias_professor(25)` | **0 pendências** — tudo em dia ✅ |
| PRESENÇA | `fabio_presencas_pendentes_professor(25)` | **18 aulas** p/ escalar (16–34 dias) 🚩 |

Se a cobrança saísse pela fila de presença, o Matheus levaria uma escalada pra coordenação **tendo feito tudo certo** — a presença não saiu por causa do bug do `campos.presenca` (corrigido no teu `ba1ca01`), não por culpa dele. **Queimaria a confiança no dia 1.**

→ **Regra: a cobrança ao professor sai SEMPRE de `fabio_pendencias_professor` (conteúdo).** A fila de presença serve pra Sol/ADM e pra coordenação enxergarem o buraco de registro — **nunca** pra cutucar professor.

**A régua de tempo (confirmada na migration 014):**
- **Dias 1 a 3** → o Fábio lembra o professor, direto, leve, todo dia.
- **> 3 dias** → o Fábio **para de cutucar** e a bola sobe pro grupo COORDENACAO PEDAGÓGICA (JID `120363304349910605@g.us`, já allowlistado: `agente='fabio'`, escopo `governanca_presenca`, modo `so_registrar`).

**Tom (o Alf ditou hoje):** parceiro, nunca chato. Algo como:
> *"Fala, Matheus, tudo bem? Passando aqui pra você mandar rapidinho o conteúdo dos seus alunos de ontem. Não demora não, cara — senão daqui a dois dias isso tem que ir pra coordenação, e aí eles vão te encher. 😉"*

Ou seja: o Fábio **avisa do prazo como quem protege o professor**, não como quem ameaça.

## 8. Checklist antes de dormir hoje

- [ ] Rotina do briefing implementada (com claim/dedupe)
- [ ] Timer/cron às **11:00 UTC** (= 8h BRT), só prof 25
- [ ] **Dry-run manual**: rodar a rotina agora e mandar o preview pro Alf aprovar o texto
- [ ] Confirmar o número do WhatsApp do Matheus na `fabio_identidade_whatsapp`
- [ ] Nada de envio pra outros professores (piloto de 1)
- [ ] **Cobrança de pendência sai por `fabio_pendencias_professor` (conteúdo), nunca pela de presença** (§7.1)
- [ ] Escala > 3 dias aponta pro grupo da coordenação (já allowlistado), mas **só depois de o Alf aprovar o texto**

Qualquer coisa que precise de banco (RPC nova, campo a mais, grant), me chama que eu faço hoje — o Alf está de plantão pra aprovar.

Abraço!
