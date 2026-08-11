# Contrato vivo do registro de aula via WhatsApp

**Projeto:** `ouqwbbermlzqqvtqwlul`
**Data da captura:** 10/08/2026 23:57:39 -03:00
**Escopo:** leitura somente pelo Management API; nenhuma linha produtiva foi inserida, alterada ou removida.

## Como a captura foi feita

Foram executadas consultas `SELECT` contra `pg_proc`, `information_schema`,
`pg_class`, `pg_indexes`, `pg_constraint`, `information_schema.role_table_grants`
e `storage.buckets`. O token foi lido apenas em memória a partir do `.env` do
clone principal e não aparece neste arquivo, no terminal ou nos resultados.

As definições completas foram medidas com `md5(pg_get_functiondef(oid))`; o hash
é o carimbo de drift para a extração dos núcleos. Antes de aplicar qualquer
migration, o G2 deve repetir `pg_get_functiondef` e comparar estes hashes.

## Funções públicas vivas

| assinatura | md5 da definição | security definer | ACL observada |
|---|---|---:|---|
| `app_atualizar_fatia(uuid,text,jsonb)` | `332f709f421925cb89b25705154f72a4` | sim | postgres, authenticated, service_role |
| `app_confirmar_registro(uuid,text)` | `207b514a00d4826ef9f028aedb94ea63` | sim | postgres, authenticated, service_role |
| `app_enfileirar_audio(integer,text,integer,uuid)` | `4b42641f39a7a7e21360ee864ba0c703` | sim | postgres, authenticated, service_role |
| `app_registrar_presencas_aula(integer,integer[])` | `6ed387ed516f18ae4a9eee1a382d77e3` | sim | postgres, authenticated, service_role |
| `app_registro_completo(uuid)` | `a7582d89c48a3f7e724ab1b971f9854e` | sim | postgres, authenticated, service_role |
| `app_responder_presenca(uuid,text)` | `b696a10e89ddd6d6e60c416ccc1e321b` | sim | postgres, authenticated, service_role |
| `app_status_audio_fila(uuid)` | `4e9b60d32158be9c0c6b77470d9d0de4` | sim | postgres, authenticated, service_role |
| `fabio_emitir_presenca_por_registro_e_devolutiva(uuid)` | `b9301ac70742160b07c3169a671a92bf` | sim | postgres, service_role, fabio_agent |
| `fabio_identidade_whatsapp(text)` | `02423999f21091a714e703a618907e4b` | sim | postgres, service_role, fabio_agent |
| `fn_compor_texto_prontuario(jsonb,jsonb)` | `24a24c13d333fc9a9281cd9db16d1398` | não | postgres, authenticated, service_role |
| `fn_janela_registro_dias()` | `0e1589b67d9ad43468171fdea575346b` | não | PUBLIC, postgres, anon, authenticated, service_role |
| `fn_pendencia_presenca(uuid,text,integer)` | `ac3179b16c5961259bd9f21fd3370264` | não | postgres, authenticated, service_role, fabio_agent |
| `fn_presenca_declarada(jsonb)` | `faf78303e4d6e43d3621a457e4df2a9d` | não | postgres, authenticated, service_role, fabio_agent |
| `fn_presenca_e_forte(text)` | `159f9270cc92ea14bce68bf33e37003c` | não | PUBLIC, postgres, anon, authenticated, service_role |
| `fn_registrar_presencas_core(integer,integer,integer[],text,boolean)` | `97038f481cee4279f241be8d9065ce4d` | sim | postgres, service_role |
| `fn_sincronizar_gemeos_presenca(integer)` | `6534df1a8c539b3988d394981453ef39` | sim | PUBLIC, postgres, anon, authenticated, service_role |
| `registrar_aula_fabio(integer,text,text,integer,text)` | `58f301e085e9fcb447dccc7a9bda84df` | sim | postgres, authenticated, service_role, fabio_agent |

Observações que bloqueiam uma cópia cega das migrations antigas:

- `app_atualizar_fatia` e `app_registro_completo` têm contrato vivo mais rico que
  as primeiras migrations locais; a extração deve começar destas definições.
- `app_status_audio_fila` e `fabio_identidade_whatsapp` estão vivos, mas não têm
  uma fonte local completa equivalente no conjunto 084–089.
- `fn_presenca_e_forte` e `fn_janela_registro_dias` ainda têm `EXECUTE` público;
  isso é estado preexistente. A migration nova não deve ampliar essa superfície.
- `fn_registrar_presencas_core` é security definer e o sincronizador de gêmeos é
  parte do efeito canônico da presença.

## Tabelas e objetos existentes

Todas as seis tabelas abaixo estão com RLS habilitado. Os números são contagens
de colunas capturadas pelo `information_schema`; nenhum valor de linha foi lido.

| tabela | colunas | índices relevantes | constraints relevantes |
|---|---:|---|---|
| `fabio_fila_audios` | 14 | PK; professor; status; experimental | origem/status checks; FKs para aula/professor/unidade/vínculo |
| `fabio_registros_aula` | 17 | PK; aguardando; aluno; aula; parent; professor/status | tronco/fatia; molde/origem/status checks; FKs para aula/aluno/audio/confirmador/parent/professor/unidade |
| `fabio_chat_mensagens` | 17 | PK; professor/criação; unseen; `fcm_wa_msg_uq`; históricos | actor/channel/identidade/kind/role checks; FKs para professor/usuário |
| `aulas_emusys` | 30 | PK; emusys/unidade; data; curso; turma; professor; reagendada | PK/unique emusys+unidade; FKs para professor/unidade |
| `aluno_presenca` | 19 | PK; aluno; professor; status; unique aluno+aula | checks de status/respondido; FKs para aluno/aula/professor/unidade |
| `fabio_devolutivas` | 30 | PK; fila; unique por registro | destinatário/override/status checks; FKs para fatia/skill |

`public.aulas` e `public.aula` não existem no alvo; a entidade de sessão é
`public.aulas_emusys`. O plano deve usar esta fonte real e verificar as views/RPCs
que projetam `aula_id` antes de escrever o pool de candidatas.

Os grants de tabelas existentes são amplos em alguns objetos, mas a leitura
atual continua protegida pelas policies/RLS vigentes. As tabelas novas de ações
devem nascer com RLS, sem grants de tabela a `anon`/`authenticated`, e com acesso
somente pelas RPCs guardadas. Não usar estes grants legados como modelo.

## Storage

`storage.buckets` contém o bucket `fabio-audios` com:

```text
public = false
file_size_limit = null
```

A coluna `mime_types` não existe nesta versão do schema de Storage; a validação
de MIME e tamanho fica no bridge antes do upload, conforme a SPEC. O path novo
continua sendo `whatsapp/{professor_id}/{wa_message_id}.{ext}` e a chave de
service role nunca sai do processo servidor.

## Deltas locais e decisão para G1

- Migration 084 é a referência local da janela de sete dias e do enfileiramento,
  mas a função viva precisa ser preservada na extração.
- Migration 086 é a referência local da sincronização de gêmeos e da presença
  forte; o teste vivo confirmou que ela continua sem divergência após rollback.
- Migrations 005/009/019/020b são fontes históricas dos corpos app, não cópias
  suficientes do contrato atual.
- `fabio_acoes_pendentes` e `fabio_acao_eventos` não aparecem nesta captura e
  seguem inexistentes até G1/G2.
- Não foram criadas filas, ações, blobs, registros, presenças ou devolutivas.

**Conclusão:** snapshot pronto para revisão. A implementação deve repetir os
hashes imediatamente antes do G2 e parar se qualquer definição mudar.
