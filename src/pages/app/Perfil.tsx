import { useEffect, useState, type FormEvent } from 'react'
import { useNavigate } from 'react-router-dom'
import { Button, EmptyState, ScreenHeader, Skeleton, Toast, useToast } from '../../components/ui'
import { atualizarPerfil, meuPerfil, type MeuPerfil } from '../../lib/api'
import { AppFrame } from './AppFrame'

type Estado =
  | { fase: 'carregando' }
  | { fase: 'erro' }
  | { fase: 'sem_vinculo' }
  | { fase: 'ok'; perfil: MeuPerfil }

const MAX_NOME = 60
const MAX_BIO = 400

/**
 * /app/perfil — "Meu perfil" (espelha o LA Organizer).
 *
 * Nome/e-mail/telefone/foto/unidades vêm do banco via `app_meu_perfil` (só
 * leitura). `nome_preferido`/`bio` são editáveis e gravados por
 * `app_atualizar_perfil` — é o que o Fábio usa pra personalizar as mensagens.
 * Upload de foto ainda não tem porta no banco (reportado, fica pra depois).
 */
export default function PerfilPage() {
  const navigate = useNavigate()
  const { message, visible, show } = useToast()

  const [estado, setEstado] = useState<Estado>({ fase: 'carregando' })
  const [nomePreferido, setNomePreferido] = useState('')
  const [bio, setBio] = useState('')
  const [salvando, setSalvando] = useState(false)

  async function carregar() {
    setEstado({ fase: 'carregando' })
    try {
      const res = await meuPerfil()
      if (!res) {
        setEstado({ fase: 'sem_vinculo' })
        return
      }
      setEstado({ fase: 'ok', perfil: res })
      setNomePreferido(res.nome_preferido ?? '')
      setBio(res.bio ?? '')
    } catch {
      setEstado({ fase: 'erro' })
    }
  }

  useEffect(() => {
    void carregar()
  }, [])

  async function salvar(e: FormEvent) {
    e.preventDefault()
    if (estado.fase !== 'ok') return
    setSalvando(true)
    try {
      const nomeFinal = nomePreferido.trim()
      const bioFinal = bio.trim()
      await atualizarPerfil(nomeFinal, bioFinal)
      setEstado({
        fase: 'ok',
        perfil: { ...estado.perfil, nome_preferido: nomeFinal || null, bio: bioFinal || null },
      })
      show('Perfil atualizado ✓')
    } catch {
      show('Não consegui salvar. Tenta de novo.')
    } finally {
      setSalvando(false)
    }
  }

  return (
    <AppFrame>
      <ScreenHeader
        title="Meu perfil"
        subtitle="O que o Fábio usa pra te conhecer melhor"
        onBack={() => navigate(-1)}
      />

      <div className="flex-1 overflow-y-auto px-4 pb-10 pt-1">
        {estado.fase === 'carregando' && <PerfilSkeleton />}

        {estado.fase === 'erro' && (
          <EmptyState
            icon="fa-solid fa-triangle-exclamation"
            title="Não consegui carregar"
            description="Deu um problema ao buscar seu perfil. Verifica a conexão e tenta de novo."
            action={
              <Button size="sm" onClick={() => void carregar()}>
                <i className="fa-solid fa-rotate-right" aria-hidden="true" /> Tentar de novo
              </Button>
            }
          />
        )}

        {estado.fase === 'sem_vinculo' && (
          <EmptyState
            icon="fa-solid fa-id-badge"
            title="Acesso não ativado"
            description="Fala com a coordenação pra vincular seu login a um professor."
          />
        )}

        {estado.fase === 'ok' && (
          <>
            {/* Foto */}
            <div className="mb-3 flex flex-col items-center gap-3 rounded-lg border border-border-subtle bg-bg-surface px-4 py-6">
              <Avatar perfil={estado.perfil} />
              <span className="text-[12.5px] text-text-secondary">Trocar foto chega em breve 📸</span>
            </div>

            {/* Informações da conta — só leitura */}
            <div className="overflow-hidden rounded-lg border border-border-subtle bg-bg-surface">
              <div className="border-b border-border-subtle px-[14px] py-3">
                <span className="text-[11px] font-bold uppercase tracking-[.5px] text-text-secondary">
                  Informações da conta
                </span>
              </div>
              <LinhaInfo rotulo="Nome" valor={estado.perfil.nome} />
              <LinhaInfo rotulo="E-mail" valor={estado.perfil.email} />
              <LinhaInfo rotulo="WhatsApp" valor={estado.perfil.telefone_whatsapp} />
              <LinhaInfo rotulo="Unidade" valor={estado.perfil.unidades} />
            </div>

            {/* Editável — o que o Fábio usa pra te conhecer */}
            <form
              onSubmit={(e) => void salvar(e)}
              className="mt-3 overflow-hidden rounded-lg border border-border-subtle bg-bg-surface"
            >
              <div className="border-b border-border-subtle px-[14px] py-3">
                <span className="text-[11px] font-bold uppercase tracking-[.5px] text-text-secondary">
                  Como o Fábio te conhece
                </span>
              </div>

              <div className="flex flex-col gap-4 px-[14px] py-4">
                <label className="flex flex-col gap-[6px]">
                  <span className="text-[12.5px] font-bold text-text-secondary">Como quer ser chamado</span>
                  <input
                    type="text"
                    value={nomePreferido}
                    onChange={(e) => setNomePreferido(e.target.value)}
                    maxLength={MAX_NOME}
                    placeholder={estado.perfil.nome}
                    className="w-full rounded-md border border-border-strong bg-bg-inset px-[14px] py-[11px] text-sm text-text-primary placeholder:text-text-muted focus-visible:border-brand"
                  />
                </label>

                <label className="flex flex-col gap-[6px]">
                  <span className="text-[12.5px] font-bold text-text-secondary">Bio</span>
                  <textarea
                    value={bio}
                    onChange={(e) => setBio(e.target.value)}
                    maxLength={MAX_BIO}
                    rows={4}
                    placeholder="Instrumento, estilo de aula, preferências… o que o Fábio deve saber sobre você."
                    className="w-full resize-none rounded-md border border-border-strong bg-bg-inset px-[14px] py-[11px] text-sm text-text-primary placeholder:text-text-muted focus-visible:border-brand"
                  />
                  <span className="self-end text-[11px] text-text-muted">
                    {bio.length}/{MAX_BIO}
                  </span>
                </label>

                <button
                  type="submit"
                  disabled={salvando}
                  className="rounded-md bg-brand py-[11px] text-sm font-bold text-on-brand disabled:opacity-60"
                >
                  {salvando ? 'Salvando…' : 'Salvar perfil'}
                </button>
              </div>
            </form>
          </>
        )}
      </div>

      <Toast message={message} visible={visible} />
    </AppFrame>
  )
}

function Avatar({ perfil }: { perfil: MeuPerfil }) {
  if (perfil.foto_url) {
    return (
      <img
        src={perfil.foto_url}
        alt={perfil.nome}
        className="h-[92px] w-[92px] flex-none rounded-full object-cover"
      />
    )
  }
  const inicial = perfil.nome.charAt(0).toUpperCase()
  return (
    <div className="flex h-[92px] w-[92px] items-center justify-center rounded-full bg-[var(--avatar-grad)] text-3xl font-extrabold text-[color:var(--avatar-fg)]">
      {inicial}
    </div>
  )
}

function LinhaInfo({ rotulo, valor }: { rotulo: string; valor: string | null }) {
  return (
    <div className="flex items-center gap-3 border-b border-border-subtle px-[14px] py-3 last:border-b-0">
      <span className="w-[76px] flex-none text-[12.5px] font-bold text-text-secondary">{rotulo}</span>
      <span className="min-w-0 flex-1 truncate text-sm text-text-primary">{valor || '—'}</span>
    </div>
  )
}

function PerfilSkeleton() {
  return (
    <div className="flex flex-col gap-3">
      <div className="flex flex-col items-center gap-3 rounded-lg border border-border-subtle bg-bg-surface px-4 py-6">
        <Skeleton className="h-[92px] w-[92px] rounded-full" />
        <Skeleton className="h-3 w-40" />
      </div>
      <div className="space-y-3 rounded-lg border border-border-subtle bg-bg-surface px-[14px] py-4">
        {[0, 1, 2, 3].map((i) => (
          <Skeleton key={i} className="h-4 w-2/3" />
        ))}
      </div>
    </div>
  )
}
