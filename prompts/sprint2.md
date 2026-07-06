# LA Teacher · Sprint 2 — Pacote de Execução para o Claude Code
### App base: fundação SQL, tokens globais, auth do professor, Home e Agenda · 04/07/2026

## Mini-PRD do Sprint

**Objetivo:** ao fim do S2, um professor de teste loga no PWA e vê a Home com a agenda real do dia (dados vivos do LA Report), no Fábio DS, nos dois temas.

**Entra:** scaffold + tokens globais + componentes base · migração 001 no LA Report · auth + vínculo professor · Home (briefing estático por ora + aulas do dia + pendências) · tela Agenda (dia/semana) · lista de Alunos (carteira).
**Não entra (S3/S4):** gravação de áudio, confirmação, chat, push, Painel da Coordenação.

**Materiais que acompanham este pacote:** `la-teacher-sql-001-fundacao.sql` · `frontend-tokens.md` · `repo-estrutura.md` · `design-system-fabio-v1.html` · `la-teacher-prototipo-golden-path.html` (spec visual) · `la-teacher-mapa-produto-v1-1.html`.

**Regra transversal (vale em TODOS os prompts):** tokens semânticos globais — nenhuma cor/sombra/raio/fonte fora de `src/styles/tokens.css`. O checklist anti-hex do `frontend-tokens.md` é critério de aceite de cada prompt, não só do último.

---

## P0 · Scaffold + tokens globais + componentes base

```
Crie o projeto la-teacher conforme docs/repo-estrutura.md:
Vite + React + TypeScript + Tailwind + react-router + @supabase/supabase-js.

1. Crie src/styles/tokens.css copiando EXATAMENTE os blocos :root,
   [data-theme="dark"] e [data-theme="light"] de docs/design-system-fabio-v1.html.
   Importe UMA vez em src/main.tsx. data-theme="dark" como padrão no <html>.
2. Configure tailwind.config.ts mapeando cores/raios/sombras/fontes para
   var(--token) conforme docs/frontend-tokens.md. Não use paleta default.
3. Crie src/lib/theme.ts (useTheme: lê/salva em localStorage, aplica no html).
4. Crie os componentes base em src/components/ui/ (lista e papéis no
   frontend-tokens.md), reproduzindo o visual do protótipo
   docs/la-teacher-prototipo-golden-path.html: Button, Card, Badge, AulaRow,
   FabioCard, FieldCard, Fatia, Fab, TabBar, Toast, ScreenHeader, EmptyState.
5. Crie a rota /dev/ds: página demo renderizando todos os componentes,
   com botão de alternar tema.

Aceite:
- npm run dev sobe sem erro; /dev/ds mostra todos os componentes nos 2 temas.
- grep -rnE '#[0-9a-fA-F]{3,8}' src/ --include='*.tsx' --include='*.ts' \
    --include='*.css' | grep -v tokens.css  → saída vazia.
- Nenhuma classe de cor default/arbitrária do Tailwind no código.
```

## P1 · Migração 001 no LA Report + types

```
Aplique supabase/migrations/001-fundacao-fabio.sql no projeto Supabase
ouqwbbermlzqqvtqwlul (LA Report) via MCP/psql. O script é idempotente.

Depois:
1. Sanidade: select count(*) from fabio_registros_aula; (0)
   select * from vw_risco_atual limit 1; (vazio, sem erro)
   select proname from pg_proc where proname like 'app_%'; (4 funções)
   select id from storage.buckets where id='fabio-audios'; (1 linha)
2. Gere os types: supabase gen types typescript --project-id ouqwbbermlzqqvtqwlul
   > src/types/db.ts
3. Commit da migração espelhada no repo.

Aceite: as 4 checagens acima passam; db.ts contém fabio_registros_aula,
fabio_fila_audios e risco_evasao.
Atenção: NÃO alterar objetos existentes do LA Report (só os criados aqui).
```

## P2 · Auth + vínculo do professor

```
Implemente a autenticação usando o Supabase Auth já existente no LA Report
(tabela public.usuarios tem auth_user_id; professores.usuario_id criado na 001):

1. src/lib/supabase.ts com env VITE_SUPABASE_URL/ANON_KEY (.env.example).
2. Página /app/login (e-mail + senha) no Fábio DS.
3. Guard em routes.tsx: sem sessão → login; com sessão, chamar
   app_minha_agenda() — se retornar {erro:'sem_professor_vinculado'},
   renderizar página VinculoPendente ("Fala com a coordenação pra ativar
   seu acesso") com botão sair. Nunca tela branca.
4. src/lib/api.ts: wrappers tipados APENAS das RPCs app_* (minhaAgenda,
   minhaCarteira, meusRegistros, confirmarRegistro). Proibido select
   direto em tabela no cliente.
5. Documente em docs/seed-professor-teste.md o passo a passo do seed:
   criar usuário no Auth → linha em public.usuarios (auth_user_id, perfil
   'professor') → update professores set usuario_id = <id> no professor
   escolhido pro piloto.

Aceite: login com o professor de teste entra; usuário sem vínculo cai na
VinculoPendente; logout funciona; zero hex fora de tokens.css.
```

## P3 · Home (a tela do protótipo, com dados vivos)

```
Implemente /app (Home) seguindo a tela 1 do protótipo
docs/la-teacher-prototipo-golden-path.html:

1. Header: saudação com nome do professor (da carteira/sessão) + data
   por extenso pt-BR + botão de tema.
2. FabioCard "Briefing do Fábio": nesta fase, conteúdo estático
   placeholder ("Seu copiloto chega no próximo sprint 🎙️") — o motor de
   briefing é do agente, não do app.
3. Card "Hoje": app_minha_agenda(hoje) → AulaRow por aula com hora (BRT),
   nome (turma_nome ou aluno_nome), tipo, e status derivado:
   anotacoes_fabio/anotacoes preenchida → badge Registrada (dot ok);
   aula em andamento agora → dot now; futura → dot next.
   Contador "X de Y registradas" no título.
4. Card "Pendências": app_minha_agenda(ontem) filtrando aulas sem
   anotação → linhas com badge warn. Sem pendência → EmptyState positivo.
5. FAB central de microfone presente porém levando a um Toast
   "Registro por voz chega no Sprint 3 🎙️" (o fluxo é do S3).
6. Estados: skeleton no carregamento; erro com retry; dia sem aulas →
   EmptyState com direção.

Aceite: com o professor de teste, a Home lista as aulas reais de hoje do
LA Report com horários corretos em BRT; alternar tema não quebra nada;
checklist anti-hex passa.
```

## P4 · Agenda + Alunos (leitura)

```
1. /app/agenda: seletor de dia (hoje ± navegação) + visão da semana
   compacta; reusa app_minha_agenda(data) e AulaRow.
2. /app/alunos: app_minha_carteira() → lista com busca por nome,
   agrupada por curso; célula com nome, curso, dia/horário e badge de
   qualidade quando qualidade_contexto != 'ok' (texto amigável, e.g.
   "cadastro incompleto").
   NÃO exibir nada financeiro (a RPC já não retorna — manter assim).
3. TabBar ativa: Início / Alunos / [mic] / Agenda / Fábio — "Fábio"
   abre Toast "Chat com o Fábio chega no Sprint 4".
4. README.md do repo: setup, envs, seed do professor de teste, scripts.

Aceite: navegação completa pelas 3 telas com dados vivos; busca de
alunos funciona; README permite subir o projeto do zero; anti-hex passa.
```

---

## Definition of Done · Sprint 2
1. Professor de teste loga e usa Home/Agenda/Alunos com dados reais do LA Report.
2. Migração 001 aplicada e espelhada no repo; RPCs `app_*` como única via de dados.
3. `/dev/ds` demonstra o DS vivo nos dois temas; checklist anti-hex verde no repo inteiro.
4. Nenhum dado financeiro ou de risco cru acessível no bundle do professor.
5. Pronto para o S3 (motor de registro): fila de áudios e registros já existem no banco esperando o fluxo.
