# Presença canônica — contrato para agentes

> **Todo mundo bebe desta fonte.** Se você está construindo qualquer coisa que
> precise saber se o aluno veio, é aqui. Não reimplemente a regra.
>
> Banco: projeto Supabase `ouqwbbermlzqqvtqwlul` (compartilhado por LA Teacher,
> Fábio, Sol e LA Report). Vigente desde 13/08/2026.

---

## 1. De onde LER presença

```sql
public.vw_aluno_presenca_semantica_v1
```

Uma linha por aluno × aula, com as três fontes **já resolvidas**. É ela que o
Fábio, o briefing matinal, a ficha do aluno, o radar, a conciliação da
coordenação, o health score do professor e a frequência canônica já leem —
14 consumidores hoje.

**Colunas que respondem "o aluno veio?"**

| coluna | conteúdo |
|---|---|
| `resultado_pedagogico` | `presente` · `falta_confirmada` · `aula_justificada` · `aula_cancelada` |
| `considera_presenca` / `considera_falta` | booleanos prontos — some sem `case when` |
| `considera_frequencia_denominador` | se a aula entra na conta (o denominador honesto) |

**Colunas de proveniência** — para auditar, não para decidir:
`respondido_por` (a fonte que ganhou) · `proveniencia` · `confianca` ·
`possui_conflito` · `estado_emusys_bruto` (o que o Emusys disse, guardado cru) ·
`regra_versao`.

---

## 2. A regra (decisão do Alf, 13/08/2026)

| fonte | vale? |
|---|---|
| Equipe / secretaria (`agenda_secretaria`) | **sim**, presença E falta |
| Professor no app (`professor_la_teacher`) | **sim**, presença E falta |
| Professor por WhatsApp (`professor_whatsapp`) | **sim** |
| Áudio do Fábio (`fabio_audio`) | **sim** |
| Manual (`manual`) | **sim** |
| **Emusys — `presente`** | **sim** |
| **Emusys — `ausente`** | **NÃO** — não vira falta, vira **pendência** |

> O `ausente` do Emusys é ambíguo: pode ser falta de verdade ou ninguém ter
> lançado. Ele não acusa aluno — ele cobra a equipe. Cai como pendência e vai
> pro grupo no dia seguinte.

Estados finais possíveis: **presença · falta · falta justificada · cancelamento**.

---

## 3. As duas funções — e por que são duas

```sql
public.fn_presenca_e_resposta(respondido_por, status_presenca, status) → boolean
```
**"O aluno tem veredito?"** É a régua da tabela acima. Use para contar,
cobrar e acender selo.

```sql
public.fn_presenca_e_forte(respondido_por) → boolean
```
**"Isto pode ser sobrescrito?"** Protege decisão humana de ser pisada pela
sincronização. **Emusys NÃO é forte** — de propósito, para a equipe poder
corrigir o que veio errado do Emusys.

⚠️ **Não funda as duas.** Se o Emusys virar "forte", a equipe perde o direito
de corrigir a sincronização — o oposto do que a regra pede.

Auxiliar:
```sql
public.fn_presenca_status_efetivo(status_presenca, status) → text
```
Faz o `coalesce` com a coluna antiga `status`. A sincronização do Emusys ainda
escreve só nela; sem isso, linhas reais somem da conta.

**Custo: zero.** As três são `sql` puro, `IMMUTABLE`, sem acesso a tabela — o
planejador **inlina**. Verificado no plano de produção: o nome da função não
aparece, vira o predicado literal. Há passo de teste que reprova se isso mudar.

---

## 4. A pegadinha que erra o número

`aula_emusys_id` é id de **EVENTO**, não de aula. **O mesmo horário existe em
mais de uma linha.** Contar linha crua **dobra**.

✅ Agrupe por `(aluno_id, professor_id, data_hora_inicio)`
❌ Não conte `count(*)` direto na view

Existe `fn_aula_operacional_id(aula_id)` para escolher a linha canônica do
horário — mas atenção: **51% das marcas fortes de agosto foram gravadas na
gêmea**, não na operacional. Ancorar só na operacional subconta. Agrupar pelo
horário é o caminho seguro.

---

## 5. Números de referência — agosto/2026 até 13/08

Use para conferir se a sua consulta está certa. Se der muito diferente disso,
provavelmente é a pegadinha do item 4.

| unidade | aulas-aluno | cobertura | presença | falta |
|---|---|---|---|---|
| Campo Grande | 852 | 97,3% | 77,6% | 22,4% |
| Barra | 352 | 96,6% | 78,2% | 21,8% |
| Recreio | 607 | 92,1% | 81,0% | 19,0% |
| **TOTAL** | **1.811** | **95,4%** | **78,8%** | **21,2%** |

1.362 presenças · 312 faltas · 54 justificadas · 83 ainda sem resposta.

---

## 6. O que NÃO fazer

1. **Não reimplemente a regra inline.** Foi isso que criou duas réguas
   discordando em 925 pares só em agosto — uma dizia 44,4% de cobertura, a
   outra 95,4%. Pergunte à função.
2. **Não trate ausência de registro como falta.** Sem resposta ≠ faltou.
3. **Não conte linha crua** da view (item 4).
4. **Não use `fn_presenca_e_forte` para contar.** Ela responde outra pergunta e
   vai te dar 44,4%.

---

## 7. Exemplo pronto

```sql
-- Presença × falta por unidade num período, com a régua canônica
with pares as (
  select distinct ae.unidade_id, ae.professor_id, ae.data_hora_inicio, r.aluno_id
    from public.aulas_emusys ae
    join public.aula_alunos_emusys r on r.aula_emusys_id = ae.id
   where ae.data_aula >= :de and ae.data_hora_fim < now()
     and not coalesce(ae.cancelada, false)
     and ae.professor_id is not null
     and r.aluno_id is not null
     and ae.id = public.fn_aula_operacional_id(ae.id)
), veredito as (
  select p.unidade_id,
         (select ap.status_presenca
            from public.aluno_presenca ap
            join public.aulas_emusys g on g.id = ap.aula_emusys_id
           where ap.aluno_id = p.aluno_id
             and g.professor_id = p.professor_id
             and g.data_hora_inicio = p.data_hora_inicio
             and public.fn_presenca_e_resposta(ap.respondido_por, ap.status_presenca, ap.status)
           order by case when public.fn_presenca_e_forte(ap.respondido_por) then 0 else 1 end,
                    ap.respondido_em desc nulls last
           limit 1) as resultado
    from pares p
)
select u.nome,
       count(*) as aulas_aluno,
       count(*) filter (where resultado is not null) as com_resposta,
       count(*) filter (where resultado = 'presente') as presencas,
       count(*) filter (where resultado in ('falta','falta_justificada')) as faltas
  from veredito v join public.unidades u on u.id = v.unidade_id
 group by 1;
```

O `order by` importa: **fonte humana ganha do Emusys** no desempate.
