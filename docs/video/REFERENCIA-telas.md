# Referência visual do LA Teacher — para o estúdio de vídeo

_Auditoria de 02/08/2026 · lida direto do código-fonte · **fonte da verdade pra montar as telas no Remotion**_

Este doc existe pra não recriar tela "de olho". Toda medida aqui saiu do código.
Ao mudar o app, atualizar aqui.

## Fundação

- **Moldura:** `max-w-430px`, `h-svh`, borda lateral 1px `#1E2A26`. Documento não rola; só o miolo.
- **Tema padrão: dark.** Fonte UI **Inter** (400–800); **Prompt 900** só na marca do login.
- **Ícones:** Font Awesome 6.4 (`fa-solid`) + Lucide em 3 pontos (Sun/Moon 14, ListPlus 19).
- ⚠️ **Raios sobrescritos:** `sm`=8 · `md`=12 · `lg`=16 · `xl`=24. Não são os defaults do Tailwind.
- ⚠️ **No dark, `--bg-inset` = `--bg-app`** (`#0A0F0E`) e `--shadow-card: none` → cards se separam **só pela borda**.
- ⚠️ **`--on-brand` é escuro** (`#0A0F0E`): texto sobre teal é quase preto, nunca branco.

### Cores (dark)
| | |
|---|---|
| bg-app / bg-inset | `#0A0F0E` |
| bg-surface | `#111916` |
| bg-hover | `#1A2421` |
| text-primary | `#F5F5F5` |
| text-secondary | `#9CA3AF` |
| text-muted | `rgba(245,245,245,.45)` |
| border-subtle / strong | `#1E2A26` / `#2C3B36` |
| brand | `#2A9D8F` · soft `rgba(42,157,143,.15)` · border `rgba(42,157,143,.30)` |
| success | `#22C55E` · text `#4ADE80` · soft `rgba(34,197,94,.12)` |
| danger | `#EF4444` · text `#F87171` · soft `rgba(239,68,68,.12)` |
| warning | `#EAB308` · text `#FACC15` · soft `rgba(234,179,8,.12)` |
| la-pink (marca) | `#E91451` |
| focus-ring | `0 0 0 2px #0A0F0E, 0 0 0 4px #48BFB3` |
| avatar-grad | `linear-gradient(135deg,#2A9D8F,#1B6E64)` |
| shadow-fab | `0 10px 25px -5px rgba(42,157,143,.45)` |

### Animações
| classe | o quê | timing |
|---|---|---|
| `bob` | translateY 0 → −7px → 0 | 2.2s ease-in-out ∞ |
| `wave` | height 10 → 56 → 10px | 1s ease-in-out ∞ |
| `pulse-soft` | opacity 1 → .45 → 1 | 1.6s ∞ |
| `pop` | scale .4 → 1 (overshoot) | .45s cubic-bezier(.2,1.6,.4,1) |
| `fall` (confete) | translateY 0→72vh, rotate 0→560° | 2.6s ease-in |
| `fade-up` | +10px → 0, opacity 0→1 | .5s |

## ⚠️ Os DOIS Fábios (erro clássico)

1. **`FabioAvatar` — o personagem colorido.** `<img src="/brand/fabio-avatar.svg">`, 98KB, 71 paths, razão 1.0616:1. Paleta coral/laranja (`#E97B55` dominante), topo terracota `#A45D53`, acentos teal `#336666`/`#669999`. **Usar o SVG original** — reconstruir à mão é inviável.
   Aparece: header 44px · chat header 40px · chat vazio 80px · **processando 112px com bob** · login 120px com glow rosa · intro 150px com bob.
2. **`FabioIcon` — o robozinho bicolor**, SVG inline theme-aware (`--fabio-fill` / `--fabio-traco`).
   Aparece: **FAB central 32px** (fill `#F5F5F5`, traço `#1B6E64`) · FabioCard 19px · **"digitando" 18px**.

## Medidas recorrentes

| Elemento | px |
|---|---|
| Frame do app | 430 |
| TabBar | 72 + safe-area |
| FAB central / direito | 64, ícone 23 |
| Mic gigante (gravar) | **88**, ícone 30 |
| Stop (gravar) | **74**, ícone 24 |
| Check de sucesso | **92**, ícone 36, borda 2 |
| Fábio processando | **112** |
| Avatar Fábio (header) | 44 |
| Foto do professor | 40 |
| Avatar aluno (chamada) | 36 · (fatia) 34 |
| Quadrado de contexto | 38, raio 12 |
| Círculo EmptyState | 56, ícone 20 |
| Botão voltar / setas | 36 |
| Toggle de tema | 32 |

## Telas — o essencial de cada uma

**Login:** pontinhos rosa nos 60% do topo (`radial-gradient 1px / 14px`), marca d'água "LA" 470px a −6° em `rgba(245,245,245,.05)`, Fábio 120px com `drop-shadow 24px rgb(233 20 81/.28)`, título Prompt 900/32px ("LA" rosa + "Teacher" off-white), labels `E-MAIL`/`SENHA` 11px uppercase tracking .5, inputs raio 12 sobre `#1A2421`, botão teal 14.5px/700. Placeholder do e-mail: `voce@lamusic.com.br`.

**Home:** header (Fábio 44 + `E aí, {Nome}! 👋` 17px/800 + data 12.5px) · FabioCard (gradiente 150° teal, tag `EM BREVE`) · DateNav em caixa · card `Hoje` com as sessões · Pendências · `Minha semana`. Rodapé: TabBar `[Início][Alunos][vão][Agenda][Mais]` + FAB central (anel 4px cor do fundo) + FAB mic à direita.

**Agenda:** `SemanaStrip` (7 botões flex-1, gap 4, raio 12; selecionado = borda+fundo teal; ponto teal de 5px se tem aula) · DateNav (`Domingo, 2 de agosto de 2026` + `hoje` ou `voltar pra hoje`) · card com `{feitas} de {total} chamadas`.

**SessaoRow:** hora mono 44px fixos · título (`Canto · turma de 4` / nome do aluno) · detalhe (`Ana, Bruno e Carla`) · badges empilhados (**preenchido = gravado; contorno = depende do professor**) · mic 32px ou dot.

**Chamada:** contexto teal no topo · avisos por situação · lista de alunos (avatar 36 teal-soft + nome + pílula). **No rascunho as pílulas são neutras** (`✓ Presente` contorno cinza / `⤫ Faltou` contorno âmbar) — só viram verde/vermelho **depois de gravado**. Rodapé: `{P} presente(s) · {F} falta(s)` + `Enviar chamada` → card `Confirma a chamada?` → `Enviando a chamada…` (nuvem `fa-bounce`) → `Chamada enviada ✓`.

**Gravar:** mic teal 88px + `toque pra começar · máx. 5 min` → `Pedindo acesso ao microfone…` → **18 barras `animate-wave`** (delays `(i%5)*0.15s`, opacidade = 0.55 + nível*0.45) + timer mono 38px + stop vermelho 74px → preview com `AudioPlayer` (32 barras, tocadas em teal) → `Enviar pro Fábio`.

**Processando:** Fábio 112px com bob + `O Fábio está montando seu relatório… 🎼` + trilha de 3 passos (`Na fila do Fábio` → `Transcrevendo seu áudio` → `Organizando por aluno — tronco + fatias`), marcador 26px que vira ✓ verde. Polling 3s; ao ficar pronto **navega sozinho** pra confirmação.

**Confirmar:** selo do Fábio (`Eu nunca invento: campo vazio é convite ✋`) · **tronco** (`O QUE A TURMA TRABALHOU`, campos Atividades/Objetivo/Observações/Dever) · **fatias por aluno** (accordion; presente nasce aberto) · preview do texto final (borda tracejada) · rodapé fixo com gradiente + `Corrigir por voz` / `Confirmar e gravar`. Campo vazio mostra **cutucada em itálico**; ao editar ganha halo teal duplo.

**Sucesso:** 16 confetes caindo (2.6s, 5 cores) + check 92px com `animate-pop` + `Registro gravado! 🎉` + badges (`1 tronco`, `{N} fatias`, `1 dever de casa`) + assinatura mono `registrar_aula_fabio · {N} aulas · origem áudio`.

**Alunos:** busca (`Buscar aluno pelo nome…`) · chips de unidade · cards por curso (título CAIXA ALTA + capelo teal + contador) · linhas (avatar-inicial 36 teal + nome + `Terça · 15h · Aula 20/40` + chevron).

**Ficha do aluno:** identidade (foto 84 + nome 18px + chips `9 anos · Kids`, unidade, `2 anos e 3 meses de casa`) · card de gravar · Responsável · Jornada (barra de progresso teal) · **Presença** (tirinha de bolinhas 11px: verde/vermelho/âmbar/cinza/anel + contagem `2 faltas confirmadas · 3 não conferidas`) · Histórico (selo `ÚLTIMA AULA`, dever em bloco âmbar).

**Chat do Fábio:** header (Fábio colorido 40 + `seu assistente · também no WhatsApp`) · bolhas raio 16 sem rabinho (professor à direita teal-soft, Fábio à esquerda) · separador de dia · **`Fábio está digitando`** com robozinho 18px + 3 pontos defasados 0.25s · barra de envio (input pill + botão teal 40px).
