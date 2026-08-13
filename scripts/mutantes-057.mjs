// Mutantes da 057 — liberar o acesso de um professor.
//
// W2 é o pior de todos e o mais provável de acontecer de verdade: o admin
// clica "liberar" duas vezes porque não lembra se já mandou. Se a segunda
// chamada reescrever o vínculo, o professor que estava logado perde a sessão e
// o vínculo aponta pra um usuário órfão — numa segunda-feira, sem ninguém ligar
// uma coisa à outra.
//
// W5 é o silencioso: liberar quem não tem WhatsApp cria um acesso que ninguém
// consegue usar (nem convite nem código chegam) e que aparece no painel como
// "liberado".

import { execFileSync } from 'node:child_process'
import { readFileSync, writeFileSync, unlinkSync } from 'node:fs'
import { exigirBaselineVerde } from './lib-baseline.mjs'

const ORIGINAL = 'supabase/migrations/057-liberar-acesso-do-professor.sql'
const TESTE = 'supabase/migrations/057-liberar-acesso-do-professor.test.sql'

// Sem baseline verde, todo mutante 'morre' por erro e o placar mente.
// Ver scripts/lib-baseline.mjs: isso ja aconteceu duas vezes em 13/08/2026.
exigirBaselineVerde(ORIGINAL, TESTE)
const TEMP = 'supabase/migrations/_mutante-057.sql'
const fonte = readFileSync(ORIGINAL, 'utf8')

const MUTANTES = [
  {
    nome: 'W1 — a liberação não amarra o professor ao usuário',
    pega: 'passo "o professor passa a ter usuario"',
    de: '  update public.professores set usuario_id = v_usuario where id = p_professor_id;',
    para: '',
  },
  {
    nome: 'W2 — liberar de novo reescreve o vínculo de quem já entrava',
    pega: 'passos "liberar de novo NAO reescreve o vinculo" e "nao troca o auth_user_id"',
    de: `  if v_prof.usuario_id is not null then
    return jsonb_build_object(
      'ok', true, 'ja_liberado', true,
      'professor_id', p_professor_id, 'usuario_id', v_prof.usuario_id);
  end if;`,
    para: '',
  },
  {
    nome: 'W3 — o usuário nasce sem perfil de professor',
    pega: 'passo "o usuario nasce com perfil de professor"',
    de: "          'professor', 'Professor', true, p_auth_user_id)",
    para: "          'unidade', 'Professor', true, p_auth_user_id)",
  },
  {
    // E-mail com maiúscula não casa com o que o Supabase Auth guarda, e o
    // verifyOtp falha sem dizer por quê.
    nome: 'W4 — o e-mail é guardado como veio digitado',
    pega: 'passo "o e-mail e guardado em minusculas"',
    de: '  values (v_prof.nome, lower(btrim(p_email)), v_prof.telefone_whatsapp,',
    para: '  values (v_prof.nome, btrim(p_email), v_prof.telefone_whatsapp,',
  },
  {
    nome: 'W5 — libera professor sem WhatsApp (acesso que ninguém usa)',
    pega: 'passo "professor sem whatsapp nao e liberado"',
    de: `  if nullif(btrim(coalesce(v_prof.telefone_whatsapp, '')), '') is null then`,
    para: '  if false then',
  },
  {
    nome: 'W6 — libera professor inativo',
    pega: 'passo "professor inativo nao e liberado"',
    de: `  if not v_prof.ativo then
    raise exception 'professor_inativo';
  end if;`,
    para: '',
  },
  {
    // O whatsapp não indo pro usuário: o resto do sistema que procura contato
    // por `usuarios.telefone` fica sem número.
    nome: 'W7 — o WhatsApp não acompanha o usuário criado',
    pega: 'passo "e o whatsapp do cadastro vai junto"',
    de: '  values (v_prof.nome, lower(btrim(p_email)), v_prof.telefone_whatsapp,',
    para: '  values (v_prof.nome, lower(btrim(p_email)), null,',
  },
  {
    // Sobrescrever e-mail de verdade por um @la.internal tira da pessoa o
    // caminho de recuperação que ela tinha.
    nome: 'W8 — o e-mail interno sobrescreve o e-mail de verdade',
    pega: 'passo "e NAO sobrescreve e-mail de verdade"',
    de: `     and nullif(btrim(coalesce(email, '')), '') is null;`,
    para: ';',
  },
  {
    nome: 'W9 — o painel da equipe abre pra qualquer professor',
    pega: 'passo "professor comum nao ve o painel"',
    de: `  if v_perfil is distinct from 'admin' then
    raise exception 'apenas_admin' using errcode = '42501';
  end if;`,
    para: '',
  },
  {
    nome: 'W10 — o painel lista professor inativo',
    pega: 'passo "e nao lista professor inativo"',
    de: '     where p.ativo);',
    para: '     where true);',
  },
  {
    // GRANT ativo: `create or replace function` preserva privilégio.
    nome: 'W11 — a liberação fica chamável pelo app',
    pega: 'passo "nem o admin libera direto pelo banco"',
    de: 'revoke all on function public.fn_liberar_acesso_professor(integer, uuid, text) from public, anon, authenticated;',
    para: 'grant execute on function public.fn_liberar_acesso_professor(integer, uuid, text) to authenticated;',
  },
]

let previstos = 0
let stale = 0

for (const m of MUTANTES) {
  if (!fonte.includes(m.de)) {
    console.log(`STALE  ${m.nome} — ancora nao existe mais na migration`)
    console.log(`       procurava: ${JSON.stringify(m.de.slice(0, 90))}`)
    stale++
    continue
  }
  writeFileSync(TEMP, fonte.replace(m.de, m.para))
  let passou = true
  try {
    execFileSync('node', ['scripts/rodar-teste-sql.mjs', TEMP, TESTE], { stdio: 'pipe' })
  } catch {
    passou = false
  }
  if (!passou) {
    previstos++
    console.log(`OK     morto: ${m.nome}  (${m.pega})`)
  } else {
    console.log(`FALHA  SOBREVIVEU: ${m.nome}  (${m.pega})`)
  }
}

try { unlinkSync(TEMP) } catch {}
console.log(`\n${previstos}/${MUTANTES.length} mutantes mortos` + (stale ? `  —  ${stale} ANCORA(S) PODRE(S)` : ''))
process.exitCode = previstos === MUTANTES.length ? 0 : 1
