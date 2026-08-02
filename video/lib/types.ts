// Tipos compartilhados entre roteiros, narração e composições.
export type Cena = {
  id: string;
  narracao: string;     // texto falado (ElevenLabs)
  caption: string;      // legenda 1 linha (WhatsApp sem som)
  duracaoMinS: number;  // duração mínima; áudio pode esticar
};
