/**
 * Modo somente-leitura (ambiente de demonstração / navegação em produção).
 * Liga com VITE_SOMENTE_LEITURA=true no build. Quando ligado, as portas de
 * ESCRITA do app não gravam — a chamada não envia, protegendo a produção
 * durante um passeio de leitura. Telas de leitura (Carteira, Agenda, Ponto,
 * Disponibilidade) seguem normais.
 */
export const SOMENTE_LEITURA = import.meta.env.VITE_SOMENTE_LEITURA === 'true'
