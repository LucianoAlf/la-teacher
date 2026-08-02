# Handoff — Claude Code assume o Fábio (Alf → Alfredo)

_2026-08-02 · decisão do Alf: liberar o Alfredo para a frente do Tom/LA Organizer_

---

Fala, Alfredo!

Primeiro: **o que você entregou hoje ficou redondo.** Conferi na VPS e está tudo de pé — `fabio-briefing-matheus.timer` armado pra **03/08 11:00 UTC (8h BRT)**, o `fabio_notification_worker.py` novo, o service sem `Persistent=true` (nada de disparo acidental hoje), e o `nothing_due` retornando certinho fora da janela. Trabalho limpo.

## O que muda a partir de agora

O Alf precisa de você numa frente mais pesada — **o Tom / LA Organizer**, que tem coisa quebrada e vai passar por auditoria (e possivelmente migrar pro Hermes). Pra não te deixar dividido, **o Claude Code assume o Fábio daqui em diante**: testes, ajustes, configuração e o acompanhamento do piloto.

Não é mudança de acesso — eu já entrava na VPS como o usuário `fabio`. É mudança de **papel**: a regra antiga era "Claude aponta, Alfredo aplica"; agora eu aplico direto no Fábio.

## Quem mexe em quê (o combinado)

**Passa a ser meu:**
- `~/fabio-chat-bridge/` — bridge, `fabio_presence_mcp.py`, `fabio_notification_worker.py`, o formatador do briefing
- Os units/timers do usuário `fabio` (`fabio-briefing-matheus`, `fabio-notification-worker`, `fabio-chat-bridge`, `fabio-hermes-gateway`)
- O banco (RPCs `fabio_*`, migrations) — já era

**Continua seu, não encosto:**
- A arquitetura do Hermes em si
- **Julia, Lia, Mila** — nem chego perto
- Qualquer coisa que precise de root
- Tom / LA Organizer (tua nova frente)

**A única regra que exige acordo:** o bridge tem 69KB e é teu. **Se você precisar mexer em qualquer coisa do Fábio, me avisa antes** — senão a gente se sobrescreve. Eu faço o mesmo: mantenho teu padrão de backup (`.bak.<timestamp>`) e registro o que mudei.

## 3 coisas que preciso de você (rápidas)

1. **`~/.hermes/` é compartilhado com Julia/Lia/Mila ou é instalação exclusiva do Fábio?** Isso define se eu posso tocar em `~/.hermes/hermes-agent/tools/` (onde vive o `fabio_registro_aula_tool.py` que você corrigiu no `ba1ca01`) sem risco de respingar nos outros agentes. **É o item mais importante da lista.**
2. **O backup `backup/briefing-matheus-20260802`** — em qual repositório está? Quero saber onde procurar se precisar comparar algo.
3. **Alguma armadilha que só você sabe?** Coisa que parece errada mas é proposital, dependência escondida, algo que quebra se mexer. Vale mais do que qualquer documentação.

## O que eu assumo a partir de amanhã

- **8h BRT:** acompanho o disparo do briefing do Matheus e confirmo que chegou.
- **1º áudio real:** sigo o pipeline no banco (fila → registro → `campos.presenca` → emissão → linha `fabio_audio`) — é o teste que nunca rodou depois do teu patch.
- **Governança:** ligar a cobrança de conteúdo (dias 1–3) e a escala pra coordenação (>3 dias), sempre com aprovação do Alf antes de qualquer envio real.
- **Liberação gradual** dos outros professores, conforme o Alf for abrindo.

## Ajuste que já entrou hoje (pra você saber)

Achei um bug no teu preview: a **Amanda** aparecia como *"Sem conteúdo registrado"*, mas ela **tem** registro — só em formato antigo (texto consolidado, sem campos estruturados). O `ultima_aula` vinha só com `data`.

Consertei na fonte (migration **017**): `trabalho_feito` agora cai pro texto legado quando não há campos estruturados. **Você não precisa mudar nada** — é só rodar o dry-run de novo que já vem certo. O que ia se perder: *"Amanda cantou 'Cups', 'Just the Way You Are' e 'Beautiful Things'"*.

Decisão do Alf sobre o formato: **fica como está.** Nada de compactar por enquanto — se o professor reclamar em produção, a gente ajusta com base no que ele disser.

---

Valeu por tudo no Fábio, cara — a base ficou sólida e é por isso que dá pra tocar daqui. Qualquer coisa do Fábio que você precise, é só chamar. Boa sorte no Tom! 🎩
