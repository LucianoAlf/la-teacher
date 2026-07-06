# Seed do professor de teste (piloto)

Passo a passo para dar **login + vínculo** a um professor real do LA Report, de modo que ele entre no app e veja a própria agenda. É um passo **humano** (mexe em identidade/auth) — o app nunca cria vínculo sozinho.

> Contexto: a migração 001 criou `professores.usuario_id` e a função `fn_professor_do_usuario()` (resolve o professor a partir de `auth.uid()`). As RPCs `app_*` só respondem depois que os três elos abaixo existem.

## Os três elos

```
auth.users (Supabase Auth)  ──auth_user_id──▶  public.usuarios (perfil 'professor')  ──usuario_id──▶  public.professores
```

## 1 · Criar o usuário no Supabase Auth

No painel do projeto `ouqwbbermlzqqvtqwlul` → **Authentication → Users → Add user**:

- **Email**: o e-mail do professor (o mesmo que ele vai usar no login).
- **Password**: uma senha provisória (ele troca depois).
- Marque **Auto Confirm User** (senão o login trava em "e-mail não confirmado").

Anote o **User UID** gerado (um uuid) — é o `auth_user_id`.

## 2 · Criar a linha em `public.usuarios`

O app resolve o professor por `usuarios.auth_user_id` + `usuarios.perfil`. Crie (ou atualize) a linha:

```sql
insert into public.usuarios (auth_user_id, nome, email, perfil)
values ('<AUTH_USER_UID>', 'Nome do Professor', 'email@dominio', 'professor')
on conflict (auth_user_id) do update
  set perfil = 'professor'
returning id;   -- guarde este id (usuarios.id)
```

> Se o schema de `usuarios` exigir outras colunas obrigatórias na sua instância, preencha-as — o essencial é `auth_user_id` correto e `perfil = 'professor'`.

## 3 · Vincular ao professor escolhido

Descubra o `professores.id` do professor-piloto (ex.: pelo nome) e amarre o `usuario_id`:

```sql
-- achar o professor certo:
select id, nome from public.professores where nome ilike '%sobrenome%';

-- vincular (usuario_id = usuarios.id do passo 2):
update public.professores
   set usuario_id = <USUARIOS_ID>
 where id = <PROFESSORES_ID>;
```

O índice único `ux_professores_usuario` garante 1 usuário ↔ 1 professor.

## 4 · Conferir

```sql
-- deve devolver o professores.id (não null) quando executado como aquele usuário.
-- No app: login com o e-mail/senha do passo 1 → cai direto na Home (não no VínculoPendente).
select p.id, p.nome, u.email, u.perfil
from public.professores p
join public.usuarios u on u.id = p.usuario_id
where u.auth_user_id = '<AUTH_USER_UID>';
```

## Sem vínculo = comportamento esperado

Um usuário do Auth **sem** o passo 3 loga normalmente, mas `app_minha_agenda()` devolve
`{"erro":"sem_professor_vinculado"}` → o app mostra a tela **VínculoPendente** ("Falta ativar
seu acesso") com botão **Sair**. Isso é o correto, não um bug.

## Config do app

`.env` (a partir de `.env.example`):

```
VITE_SUPABASE_URL=https://ouqwbbermlzqqvtqwlul.supabase.co
VITE_SUPABASE_ANON_KEY=<anon/publishable key do projeto>
```

A anon key é pública por design (client-side); o que protege os dados é a RLS + as RPCs `app_*`.
