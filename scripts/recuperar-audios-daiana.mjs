// Recupera os relatos de aula que a professora Daiana (professor 3) mandou pro
// Fábio no WhatsApp em 08 e 10/08/2026 e que se perderam — passando pelo MESMO
// motor do app, não por texto colado à mão.
//
// POR QUE ASSIM. O Alf, em 10/08: "a gente vai pegar todo esse conteúdo, jogar
// no Fábio, ele fazer todo o trabalho dele, colocar no lugar certo, dar
// presença, ou seja, fazer tudo como se ela tivesse feito pelo app."
//
// O motor do app é: áudio sobe pro bucket `fabio-audios` →
// `app_enfileirar_audio` insere em `fabio_fila_audios` → o trigger
// `trg_fabio_fila_novo` chama o Hermes → o agente transcreve, monta o registro
// das duas camadas e devolve em `fabio_registros_aula` pra confirmação.
//
// Os ÁUDIOS ORIGINAIS DELA ainda existem na UAZAPI. Então isto aqui não recria
// nem reinterpreta nada: baixa os mesmos bytes que ela gravou, sobe pro mesmo
// bucket, na mesma convenção de caminho (`{auth_uid}/{aula_id}/{ts}.mp3`), e
// enfileira. Daí pra frente é o motor de sempre. A voz dela é a fonte; eu não
// entro no meio.
//
// UMA DIFERENÇA, declarada: a inserção na fila é feita com service role em vez
// de `app_enfileirar_audio`, porque aquela RPC resolve o professor pelo JWT e
// eu não tenho (nem devo ter) a sessão dela. A LINHA gerada é idêntica à que a
// RPC geraria — mesmas colunas, mesmo `origem='app'`, mesmo `vinculo_id` nulo,
// que é o que o trigger olha pra rotear. As guardas que a RPC faria (aula é
// dela? cancelada? dentro da janela?) estão checadas aqui embaixo, uma a uma.
//
// Uso:
//   node scripts/recuperar-audios-daiana.mjs --dry     (só mostra o plano)
//   node scripts/recuperar-audios-daiana.mjs           (executa)

import { readFileSync, writeFileSync, mkdirSync } from 'node:fs'
import { execFileSync } from 'node:child_process'
import { tmpdir } from 'node:os'
import { join } from 'node:path'

const env = Object.fromEntries(
  readFileSync('.env', 'utf8')
    .split(/\r?\n/)
    .filter((l) => l.includes('=') && !l.trim().startsWith('#'))
    .map((l) => [l.slice(0, l.indexOf('=')).trim(), l.slice(l.indexOf('=') + 1).trim()]),
)
const URL = env.VITE_SUPABASE_URL
const KEY = env.SUPABASE_SERVICE_ROLE
if (!URL || !KEY) throw new Error('faltou VITE_SUPABASE_URL / SUPABASE_SERVICE_ROLE no .env')

const PROFESSOR_ID = 3
const AUTH_UID = '852c467d-8e42-4f7c-ab56-5980e0a098e9' // Daiana, usuarios.auth_user_id
const BUCKET = 'fabio-audios'
const DRY = process.argv.includes('--dry')

// Cada item é um áudio REAL dela, casado à aula-âncora (a de turma do horário —
// é ela que o app abre e que a chamada usa).
//
// A Beatriz (05/08 15h) entrou numa 2ª passada (10/08, tarde), depois de
// medir que o registro dela NÃO tinha passado pelo motor: em 08/08 o Fábio
// ainda tinha o MCP de banco e gravou o áudio dela via `registrar_aula_fabio`
// DIRETO — texto corrido ("AULA — 05/08 · Canto T..."), sem `fabio_registros_aula`,
// sem `campos` estruturados (molde C), sem devolutiva. As outras 4 aulas deste
// arquivo, sim, passaram pelo motor desde a 1ª passada. A aula-âncora dela é a
// de TURMA (202385, 1 aluno — regra v3 do agrupamento: turma de 1 some da tela
// e vira "individual", mas a CHAMADA e a fila continuam na âncora).
const AUDIOS = [
  {
    rotulo: 'Beatriz — quarta 05/08 15h (reprocesso: já tinha texto bruto, fora do motor)',
    aulaId: 202385,
    unidadeId: '368d47f5-2d88-4475-bc14-ba084a9a348e',
    url: 'https://lamusic.uazapi.com/files/9334058b2f9f8cc836dbbf7b251a4db83b89c23ab88947884631822ac8ef7551.mp3',
    modoConfirmacao: 'substituir', // ela já tem anotacoes_fabio (texto bruto) — 'novo' seria recusado
  },
  {
    rotulo: 'Pedro e Sofia — terça 04/08 18h',
    aulaId: 204670,
    unidadeId: '2ec861f6-023f-4d7b-9927-3960ad8c2a92',
    url: 'https://lamusic.uazapi.com/files/b050baa09d5a461f19ba700d2a589bf7b651986a74d59344826cbb1d1dd41d53.mp3',
  },
  {
    rotulo: 'Isabella (faltou) e Lara — quarta 05/08 18h',
    aulaId: 202411,
    unidadeId: '368d47f5-2d88-4475-bc14-ba084a9a348e',
    url: 'https://lamusic.uazapi.com/files/6bbf8eb8b300c2b96cdee66c8f7b8e44677dfebefcde3df1b6406a1772f97538.mp3',
  },
  {
    rotulo: 'Júlia e Clara — quarta 05/08 16h',
    aulaId: 202396,
    unidadeId: '368d47f5-2d88-4475-bc14-ba084a9a348e',
    url: 'https://lamusic.uazapi.com/files/abb64a140de81dbc2894f49d15f35c8b462e162d3cc5845c028270c75bdecd3a.mp3',
  },
  {
    rotulo: 'Eduardo — quinta 06/08 19h',
    aulaId: 204988,
    unidadeId: '2ec861f6-023f-4d7b-9927-3960ad8c2a92',
    url: 'https://lamusic.uazapi.com/files/50616cfb1bbdf5d6ff1667112eaf8c8a0ccce87b84c86484a5ffc01aa05f4a38.mp3',
  },
]

const h = { apikey: KEY, Authorization: `Bearer ${KEY}` }

async function rest(path, init = {}) {
  const r = await fetch(`${URL}${path}`, {
    ...init,
    headers: { ...h, 'Content-Type': 'application/json', ...(init.headers || {}) },
  })
  const txt = await r.text()
  if (!r.ok) throw new Error(`${path} -> ${r.status} ${txt.slice(0, 300)}`)
  return txt ? JSON.parse(txt) : null
}

const dir = join(tmpdir(), 'daiana-audios')
mkdirSync(dir, { recursive: true })

console.log(DRY ? '— MODO SECO: nada será escrito —\n' : '— EXECUTANDO —\n')

for (const a of AUDIOS) {
  // ── guardas que a app_enfileirar_audio faria ─────────────────────────────
  const [aula] = await rest(
    `/rest/v1/aulas_emusys?id=eq.${a.aulaId}&select=id,professor_id,cancelada,data_hora_fim,anotacoes_fabio,tipo`,
  )
  if (!aula) throw new Error(`${a.rotulo}: aula ${a.aulaId} não existe`)
  if (aula.professor_id !== PROFESSOR_ID) throw new Error(`${a.rotulo}: aula não é da professora`)
  if (aula.cancelada) throw new Error(`${a.rotulo}: aula cancelada`)
  const [{ dentro }] = await rest(`/rest/v1/rpc/fn_janela_registro_dias`, { method: 'POST', body: '{}' })
    .then((d) => [{ dentro: (Date.now() - Date.parse(aula.data_hora_fim)) / 86400000 <= d }])
  if (!dentro) throw new Error(`${a.rotulo}: fora da janela de registro`)

  // já enfileirado antes por este script? (idempotência — rodar 2x não duplica)
  const jaNaFila = await rest(
    `/rest/v1/fabio_fila_audios?aula_id=eq.${a.aulaId}&professor_id=eq.${PROFESSOR_ID}&select=id,status`,
  )
  if (jaNaFila.length) {
    console.log(`↷ ${a.rotulo}: já tem ${jaNaFila.length} áudio na fila (${jaNaFila.map((x) => x.status).join(',')}) — pulando`)
    continue
  }

  // ── baixa os bytes ORIGINAIS que ela gravou ──────────────────────────────
  const resp = await fetch(a.url)
  if (!resp.ok) throw new Error(`${a.rotulo}: download ${resp.status}`)
  const buf = Buffer.from(await resp.arrayBuffer())
  const arq = join(dir, `${a.aulaId}.mp3`)
  writeFileSync(arq, buf)
  const dur = Math.round(
    Number(
      execFileSync('ffprobe', [
        '-v', 'error', '-show_entries', 'format=duration',
        '-of', 'default=noprint_wrappers=1:nokey=1', arq,
      ]).toString().trim(),
    ),
  )

  const path = `${AUTH_UID}/${a.aulaId}/${Date.now()}.mp3`
  console.log(`• ${a.rotulo}\n    aula ${a.aulaId} · ${(buf.length / 1024).toFixed(0)} KB · ${dur}s\n    ${path}`)
  if (DRY) continue

  // ── sobe pro mesmo bucket, na mesma convenção do app ─────────────────────
  const up = await fetch(`${URL}/storage/v1/object/${BUCKET}/${path}`, {
    method: 'POST',
    headers: { ...h, 'Content-Type': 'audio/mpeg' },
    body: buf,
  })
  if (!up.ok) throw new Error(`upload: ${up.status} ${(await up.text()).slice(0, 200)}`)

  // ── enfileira: daqui em diante é o motor de sempre ───────────────────────
  const [row] = await rest('/rest/v1/fabio_fila_audios', {
    method: 'POST',
    headers: { Prefer: 'return=representation' },
    body: JSON.stringify({
      professor_id: PROFESSOR_ID,
      unidade_id: a.unidadeId,
      aula_id: a.aulaId,
      storage_path: path,
      duracao_segundos: dur,
      origem: 'app',
      status: 'pendente',
    }),
  })
  console.log(`    → fila ${row.id} (${row.status}); o trigger chamou o Hermes` +
    (a.modoConfirmacao ? ` · confirmar com p_modo='${a.modoConfirmacao}'` : '') + '\n')
}

console.log('pronto.')
