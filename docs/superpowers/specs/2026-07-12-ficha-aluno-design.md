# Ficha do aluno enriquecida (v1) — LA Teacher

**Data:** 2026-07-12
**Tela:** `/app/aluno/:alunoId` (`src/pages/app/AlunoDetalhe.tsx`)
**RPC:** `app_aluno_ficha(p_aluno_id)` — criada, corrigida e testada pelo Claude Web.

## 1. Objetivo

Transformar a tela do aluno (hoje mostra só carteira + "gravar aula de hoje") numa
**ficha completa**: o professor abre um aluno e enxerga quem é, onde está na jornada,
presença, responsável e histórico pedagógico. Meta: chegar preparado pra aula e dar o
"uau" na estreia com o Matheus (segunda, 13/07).

## 2. Fora de escopo (decisões do Alf, travadas)

- **Zero financeiro** — não vem no payload, não aparece.
- **Sem anamnese** — sensível + só 18 registros no banco todo (quase ninguém tem).
- **Sem health score** — o score atual inclui fator financeiro ("não é exclusivamente
  pedagógico"); vazaria sinal financeiro indireto. Fica pro modelo v2 pedagógico, futuro.
- **`outros_cursos` = apontamento apenas** — "Também faz X com Y", sem nenhum conteúdo
  pedagógico do curso do outro professor.

## 3. Fonte de dados: `app_aluno_ficha(p_aluno_id integer) → jsonb`

- `security definer`, guardada por `fn_professor_do_usuario`; grant só `authenticated`.
- **Guards (exceções):**
  - sem professor vinculado → `sem_professor_vinculado`
  - aluno fora da carteira do professor → `aluno_fora_da_sua_carteira` (o professor não
    consegue puxar aluno de outro).
- **Contrato (blocos):**

```
perfil: { aluno_id, nome, foto_url, idade, data_nascimento,
          classificacao (LAMK=Kids / EMLA=School), modalidade, unidade,
          data_matricula, meses_de_casa, status, is_retorno, is_segundo_curso }
minha_jornada: [{ curso, aula_atual, aulas_contratadas, aulas_realizadas,
                  jornada_label, dia_aula, horario, status_matricula, percentual }]
                — SÓ o(s) curso(s) do professor logado.
outros_cursos: [{ curso, professor }]  — apontamento, sem conteúdo.
responsaveis:  [{ nome, parentesco, principal }]  — SEM telefone.
presenca_recente: [{ data, status, curso }]  — últimas 10 aulas com esse professor.
historico_pedagogico: [{ data, curso, texto, origem ("fabio"|"emusys"), foi_voce }]
                — últimos 10 registros do(s) curso(s) do professor; escopado pra NÃO
                  vazar outros cursos; inclui professor ANTERIOR do mesmo curso
                  (foi_voce=false = continuidade pedagógica).
```

**Nota de fonte (resolvido pelo Web):** o histórico lê `coalesce(anotacoes_fabio,
anotacoes)` — prefere o Fábio (futuro), cai no Emusys legado (presente). O
`fabio_registros_aula` (pipeline novo) ainda está zerando; o histórico real está em
`aulas_emusys.anotacoes`. O `origem` diz de onde veio. Escopado por curso do professor
(um bug de vazamento — trazer Power Kids/Teclado de outros professores — foi pego no
teste e corrigido).

## 4. Camada de dados (frontend)

- `src/lib/api.ts`: tipo `AlunoFicha` (com os 6 blocos) + wrapper
  `alunoFicha(alunoId): Promise<AlunoFicha | 'fora_da_carteira'>` chamando
  `supabase.rpc('app_aluno_ficha', { p_aluno_id })`. Detecta `aluno_fora_da_sua_carteira`
  no `error.message` (padrão dos outros erros guardados) e devolve um sinal tratável.
- `src/types/db.ts` regenerado via MCP se o `tsc` reclamar da assinatura nova.

## 5. Tela (`AlunoDetalhe` reescrita)

Estados de topo: `carregando` (skeleton), `erro` (retry), `fora_da_carteira`
(empty state), `ok`.

Blocos (ordem), **cada um com empty state honesto**:

1. **Identidade** — foto real (`foto_url`; fallback inicial), nome, chips: `idade` +
   Kids/School, unidade, meses de casa ("2 anos e 2 meses"), aniversário
   (`data_nascimento` → "faz N em X dias" quando perto), chip **"retornou"** se
   `is_retorno`. `status` só aparece se ≠ `ativo`.
2. **Gravar aula de hoje** — bloco existente (window-aware via `podeGravar`), mantido.
3. **Responsável** — `responsaveis[]` (nome + parentesco; `principal` primeiro). Vazio →
   oculta o bloco.
4. **Jornada** — `minha_jornada[]` (curso, dia/horário, "Aula X/40", barra, percentual,
   marco quando perto da renovação) + `outros_cursos` ("Também faz X · Prof").
5. **Presença** — derivada de `presenca_recente[]`: tirinha das últimas 10
   (presente/falta), % recente, "última aula há X dias". Vazio → "sem presença ainda".
6. **Histórico pedagógico** — `historico_pedagogico[]`: lista (data, curso, texto com
   `objetivo:`/`conteudo:` preservados, tag **"você"** vs **"prof. anterior"** por
   `foi_voce`). Vazio → "sem registros ainda".

## 6. Regras de exibição

- Empty states honestos — **nunca inventar dado**.
- Datas relativas ("hoje", "ontem", "há N dias").
- `classificacao`: `LAMK`→"Kids", `EMLA`→"School".
- `presenca_recente[].status`: mapear os valores do banco (presente/falta/ausente/…) pra
  presente/falta na tirinha; desconhecido → neutro.
- Histórico: mostrar o texto com quebras; sem accordion no v1 (se ficar longo demais na
  prática, limitar linhas numa fase seguinte).

## 7. Identidade (nuance registrada)

`aluno_id` é uma **linha de matrícula/disciplina**, não a pessoa. A tela abre por
`aluno_id` = o curso do professor com aquele aluno. `outros_cursos` e o escopo do
histórico são resolvidos **no banco** (Web) — o front não tenta reconciliar pessoa.

## 8. Verificação

- `npm run build` limpo (tsc+vite) + anti-hex.
- Ao vivo com **Valentina (697)**: histórico cheio (13 Canto, um de professor anterior),
  presença rica (59 presenças), responsável (Giulliany), outros cursos (Power Kids/
  Teclado como apontamento). A sessão de teste do Matheus expira — plano: rota `/dev`
  temporária apontando pra ficha OU logar no preview.
- Conferir que **nenhum campo financeiro** aparece.

## 9. Pendências externas

- Web já corrigiu a fonte do histórico + o vazamento de outros cursos. ✓
- Futuro (fases seguintes): health score pedagógico (v2), anamnese (quando houver
  cobertura + tela autorizada), histórico de aulas detalhado, "praticou em casa".
