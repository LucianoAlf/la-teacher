#!/usr/bin/env node
// Mutacao real da 095. Cada variante e gravada fora do repositorio e precisa
// reprovar o ensaio SQL. O runner atual aponta para o Supabase remoto; nesse
// caso este script termina como NAO VERIFICAVEL, sem executar SQL algum.

import { spawnSync } from 'node:child_process'
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { join, resolve } from 'node:path'
import { tmpdir } from 'node:os'

const MIGRATION = 'supabase/migrations/095-recibo-de-registro-no-whatsapp.sql'
const TEST = 'supabase/migrations/095-recibo-de-registro-no-whatsapp.test.sql'
const RUNNER = process.env.MUTANTE_095_SQL_RUNNER ?? 'scripts/rodar-teste-sql.mjs'
const PRE_REQUISITOS = [
  'supabase/migrations/093-presenca-padrao-e-fatias-canonicas.sql',
  'supabase/migrations/094-falhas-e-correcoes-auditadas.sql',
]

function executorEComprovadamenteLocal(fonte) {
  const apontaRemoto = /api\.supabase\.com|https?:\/\/[^\s`'"\\]+\.supabase\.co|projects\/[^/]+\/database\/query/i.test(fonte)
  const apontaLocal = /127\.0\.0\.1|localhost/i.test(fonte)
  return apontaLocal && !apontaRemoto
}

function falhar(mensagem) {
  console.error(mensagem)
  process.exitCode = 1
}

for (const arquivo of [MIGRATION, TEST, RUNNER, ...PRE_REQUISITOS]) {
  if (!existsSync(resolve(arquivo))) {
    falhar(`BLOQUEADO: arquivo ausente: ${arquivo}`)
  }
}
if (process.exitCode) process.exit()

const fonte = readFileSync(resolve(MIGRATION), 'utf8')
const fonteRunner = readFileSync(resolve(RUNNER), 'utf8')
const mutantes = [
  [
    'M0 chave do recibo',
    [
      'create unique index if not exists uq_fabio_notificacoes_registro_recibo_unico',
      '  on public.fabio_notificacoes(',
      '    professor_id, tipo, referencia_tipo, referencia_id, canal',
      '  )',
      "  where tipo = 'registro_recibo'",
      "    and referencia_tipo = 'registro_aula'",
      "    and canal = 'whatsapp';",
    ].join('\n'),
    '-- M0: chave idempotente removida',
  ],
  [
    'M1 guarda das devolutivas',
    "            and (d.id is null or d.status not in ('gerada', 'oferecida'))",
    '            and false -- M1: recibo sem guarda de devolutiva',
  ],
  [
    'M2 espelho no contexto',
    [
      '  insert into public.fabio_chat_mensagens(',
      '    identidade_tipo, role, kind, content, channel, professor_id, wa_message_id',
      '  ) values (',
      "    'professor', 'fabio', 'text', v_corpo, 'whatsapp',",
      '    v_notificacao.professor_id, v_envio_recibo',
      '  )',
      '  on conflict (wa_message_id) do update',
      '     set kind = excluded.kind,',
      '         content = excluded.content',
      '   where public.fabio_chat_mensagens.professor_id = excluded.professor_id',
      "     and public.fabio_chat_mensagens.role = 'fabio'",
      "     and public.fabio_chat_mensagens.channel = 'whatsapp'",
      '  returning id into v_chat_id;',
    ].join('\n'),
    '  v_chat_id := gen_random_uuid(); -- M2: espelho omitido',
  ],
  [
    'M3 projecao tem_rascunho',
    '          bool_or(rascunho.id is not null) as tem_rascunho,',
    '          false as tem_rascunho, -- M3: agenda esconde rascunho',
  ],
  [
    'M4 wrapper autenticado',
    '  v_auth_user_id uuid := auth.uid();',
    '  v_auth_user_id uuid := null; -- M4: identidade autenticada removida',
  ],
  [
    'M5 dedupe storage_path',
    '     and storage_path = v_storage_path',
    '     and false -- M5: ignora storage_path',
  ],
  [
    'M6 separacao da chave legada',
    "    and tipo <> 'registro_recibo';",
    '    and true; -- M6: legado volta a capturar recibo',
  ],
  [
    'M7 token do lease de conclusao',
    '     or v_notificacao.lease_token is distinct from p_lease_token',
    '     or false -- M7: token do lease ignorado',
  ],
  [
    'M8 expiracao do lease de falha',
    '     and n.lease_expira_em > now();',
    '     and true; -- M8: lease vencido aceito',
  ],
]

let pastaTemporaria
try {
  pastaTemporaria = mkdtempSync(join(tmpdir(), 'la-teacher-mutantes-095-'))
  const mutados = []
  for (const [nome, ancora, substituicao] of mutantes) {
    const ocorrencias = fonte.split(ancora).length - 1
    if (ocorrencias !== 1) {
      falhar(`FALHA: ancora de ${nome} apareceu ${ocorrencias} vez(es)`)
      continue
    }
    const arquivoMutado = join(pastaTemporaria, `${nome.replace(/[^a-z0-9]+/gi, '-').toLowerCase()}.sql`)
    writeFileSync(arquivoMutado, fonte.replace(ancora, substituicao), 'utf8')
    mutados.push({ nome, arquivoMutado })
  }

  if (process.exitCode) {
    // O finally abaixo ainda precisa remover as copias temporarias.
  } else if (!executorEComprovadamenteLocal(fonteRunner)) {
    console.error(`NAO VERIFICAVEL: ${RUNNER} aponta para um alvo remoto ou nao prova alvo local.`)
    console.error(`Nenhum SQL mutado foi executado; ${mutados.length} copia(s) temporaria(s) serao removidas.`)
    process.exitCode = 2
  } else {
    for (const { nome, arquivoMutado } of mutados) {
      const resultado = spawnSync(
        process.execPath,
        [resolve(RUNNER), ...PRE_REQUISITOS.map((arquivo) => resolve(arquivo)), arquivoMutado, resolve(TEST)],
        { cwd: process.cwd(), encoding: 'utf8' },
      )
      const saida = `${resultado.stdout ?? ''}\n${resultado.stderr ?? ''}`
      if (resultado.error) {
        falhar(`FALHA: ${nome} nao executou: ${resultado.error.message}`)
      } else if (resultado.status === 1 && /(?:passo\(s\) divergiram|execu.{0,12}falhou|rollback\s+n.{0,12}(?:restaurou|limpou))/iu.test(saida)) {
        console.log(`OK     morto por veredito real: ${nome}`)
      } else {
        falhar(`FALHA: ${nome} nao foi morto pelo veredito real do runner; status=${resultado.status}`)
        if (saida.trim()) console.error(saida.trim())
      }
    }
  }
} finally {
  if (pastaTemporaria) rmSync(pastaTemporaria, { recursive: true, force: true })
}
