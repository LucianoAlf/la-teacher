/**
 * Selo discreto de build: dá pra bater o olho e saber em que versão a pessoa
 * está antes de investigar um "sumiu" ou um "não atualiza".
 *
 * Nasceu inline na tela Meu perfil do professor e foi EXTRAÍDO quando o perfil
 * da coordenação precisou do mesmo selo. Recriar teria dado o de sempre: eu já
 * tinha escrito uma segunda versão que imprimia "versão de 08/08/2026 14:10" e
 * **omitia o número da versão** — dois selos dizendo coisas diferentes sobre o
 * mesmo build é pior do que não ter selo.
 */
export function SeloVersao({ className }: { className?: string }) {
  const data = (() => {
    try {
      return new Intl.DateTimeFormat('pt-BR', {
        day: '2-digit',
        month: '2-digit',
        year: 'numeric',
        hour: '2-digit',
        minute: '2-digit',
        timeZone: 'America/Sao_Paulo',
      }).format(new Date(__BUILD_TIME__))
    } catch {
      return null
    }
  })()

  return (
    <p className={`mt-6 text-center text-[11px] text-text-muted ${className ?? ''}`}>
      LA Teacher · v{__APP_VERSION__}
      {data ? ` · ${data}` : ''}
    </p>
  )
}
