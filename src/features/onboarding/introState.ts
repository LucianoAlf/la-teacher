// "Quem já viu, pula." O intro pré-login é marketing/demonstração — mostra uma
// vez por dispositivo. Sem login ainda, então o flag mora no localStorage.
const KEY = 'la_intro_visto'

export function introVisto(): boolean {
  try {
    return localStorage.getItem(KEY) === '1'
  } catch {
    return false // modo privado / storage bloqueado: mostra o intro, sem quebrar
  }
}

export function marcarIntroVisto(): void {
  try {
    localStorage.setItem(KEY, '1')
  } catch {
    /* storage indisponível — tudo bem, só mostra o intro de novo depois */
  }
}
