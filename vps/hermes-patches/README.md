# Patches locais do Hermes (NousResearch/hermes-agent)

Patches que a gente mantém em cima do Hermes até o upstream corrigir. **Não é
código do Fábio — é da VERSÃO do Hermes.** Todo agente na mesma versão precisa
do mesmo patch.

## Por que isto existe (o problema que ele resolve)

O updater do Hermes atualiza assim:

```
git stash --include-untracked   # guarda mudanças locais
reset --hard origin/main        # (quando o fast-forward não é possível)
git stash pop                    # tenta restaurar as mudanças
```

Quando a versão nova toca o mesmo arquivo que a gente patchou, o `stash pop`
**conflita e o patch se perde** (aconteceu na Lia em 21/08/2026). Ou seja: patch
não-versionado dentro do checkout do Hermes some no próximo update — **em
silêncio**. Por isso o patch vive AQUI (versionado) e é **reaplicado** por
`apply.sh` depois de cada update.

## Agentes afetados

Todos os que estão na versão do Hermes com o bug. Em **21/08/2026**: **Fábio,
Mila e Lia** — os três em **v0.20.5**, com o mesmo `agent/conversation_compression.py`.
Cada um roda como um usuário separado no host `la-hq` (`fabio`, `mila`, `lia`);
`apply.sh` roda **uma vez por usuário** (ele não enxerga o `~/.hermes` dos outros).

| Agente | Usuário | Rodar |
|---|---|---|
| Fábio | `fabio` | `./apply.sh` (como fabio) |
| Mila  | `mila`  | `./apply.sh` (como mila)  |
| Lia   | `lia`   | `./apply.sh` (como lia)   |

## Os patches

### `conversation_compression-lazy-import.patch`

**Bug (estrutural, no grafo de imports — v0.20.5):** `conversation_compression.py`
importava `AuxiliaryExplicitCancellation` de `auxiliary_client` **no topo do
módulo**. `auxiliary_client` é enorme; quando `conversation_compression` é
importado pela 1ª vez pela via `_replay_compression_warning` (run_agent.py) — o
que acontece quando a **compressão de contexto** é acionada — o `auxiliary_client`
pode estar meio-carregado, e o nome ainda não existe → `ImportError: cannot import
name 'AuxiliaryExplicitCancellation'`. A classe EXISTE; é re-entrância de import,
não classe faltando (import isolado funciona).

**Sintoma medido (Fábio, 21/08/2026):** turno de registro por áudio com
`prompt_len ~31.7K` (tamanho de todo registro-aula) aciona a compressão e o
gateway responde `Sorry, I encountered an error (ImportError)`; o áudio fica preso
em `transcrevendo`/`transcrito` e não vira registro — **falha silenciosa**.

**Fix:** mover o import para **lazy, dentro de `compress_context`** (único uso).
Em runtime `auxiliary_client` já está 100% carregado → classe REAL (mesma
identidade para `raise`/`except`; um stand-in quebraria o `except`).

> Nota sobre a issue upstream **#88274**: NÃO é o mesmo bug. Ela é `ImportError`
> por **`.pyc` velho no `__pycache__`** durante o cleanup do dashboard (problema de
> CACHE). Referência só lateral: por isso o `apply.sh` também **limpa
> `__pycache__`** depois do `reset --hard` (o reset pode deixar bytecode
> dessincronizado).

## Como usar (depois de CADA update do Hermes)

```bash
# como o usuário do agente (fabio / mila / lia):
cd <clone do la-teacher>/vps/hermes-patches
./apply.sh
```

`apply.sh`: limpa `__pycache__` → se já corrigido (nosso patch ou upstream), sai
0 → senão aplica → se **não aplicar limpo** (a versão nova mudou o arquivo), sai
**3 e GRITA** ("o bug pode ter voltado, não confie no áudio até revisar") →
verifica AST + marcador → reinicia o gateway.

⚠️ **É fácil esquecer o passo pós-update** (o update é interativo e barulhento).
Por isso existe a **rede de segurança por cron** (abaixo) — ela não é opcional.

## A rede de segurança (a trava que falha alto)

O modo de falha é **silencioso** (áudio quebra, professor reclama dias depois).
A trava que **falha alto** vale mais que o patch. São duas camadas, ambas caindo
no **mesmo WhatsApp** que a coordenação já olha (Luciano, 5521966583325):

**(a) `monitor-saude-fabio`** — edge function nova (neste repo,
`supabase/functions/monitor-saude-fabio/`), cron `monitor-saude-fabio` a cada
10min. Checa **áudio empacado** (gravações presas em `transcrevendo`/`transcrito`
há >30min = gateway crashando) e **lê `hermes_patch_status`** (abaixo), alertando
se algum agente está sem patch ou se o guard root parou de rodar.

> Feita separada de propósito, não editando o `monitor-saude-webhook`: aquele mora
> no repo do LA Report, que estava 167 commits atrás e com a versão deployada
> diferente da local — editar de cópia velha regride a função. A irmã aqui usa o
> MESMO canal de alerta, sem esse risco.

**(b) `hermes-patch-guard.sh`** — script que **roda como ROOT** (cron), varre
`/home/*/.hermes/.../conversation_compression.py` de TODOS os agentes e grava o
estado do patch em `public.hermes_patch_status`. É o que cobre Mila/Lia/os 7: o
`apply.sh` é por-usuário e o usuário de um agente não lê o `~/.hermes` dos outros.
Só root cobre todos. **Precisa ser instalado no cron root por você/Hugo** (eu não
tenho root) — enquanto não estiver, a cobertura cross-agente não existe e a
`hermes_patch_status` fica vazia (o `monitor-saude-fabio` não alarma vazio, só
quando há linhas).

Fluxo: `guard root (varre) -> hermes_patch_status -> monitor-saude-fabio (lê + alerta)`.

## Aposentar um patch

Quando o upstream corrigir (o `apply.sh` avisa quando o import de topo sumiu SEM
o nosso marcador = provável fix upstream): confirmar que o fix upstream está
correto, apagar o `.patch` daqui e o registro deste README, e conferir que o
`apply.sh` vira no-op.

## Reportado upstream

- (a preencher) issue em `github.com/NousResearch/hermes-agent` sobre o import
  re-entrante em `conversation_compression.py` + o fix lazy.
