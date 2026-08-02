// Carrega as MESMAS fontes do app (index.html): Inter 400–800 + Prompt 900.
// Sem isso o render headless cai em fonte genérica e a marca perde a cara.
// Importar uma vez no Root — o loadFont segura o render até a fonte chegar.
import { loadFont as loadInter } from '@remotion/google-fonts/Inter'
import { loadFont as loadPrompt } from '@remotion/google-fonts/Prompt'

loadInter('normal', { weights: ['400', '500', '600', '700', '800'], subsets: ['latin'] })
loadPrompt('normal', { weights: ['900'], subsets: ['latin'] })
