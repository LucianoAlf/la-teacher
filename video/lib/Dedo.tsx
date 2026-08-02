import React from 'react'
import { interpolate, staticFile, useCurrentFrame, Easing, Img } from 'remotion'
import { Sfx, SFX } from './sfx'

/**
 * A MÃOZINHA — duas mãos geradas no Higgsfield e recortadas, em
 * public/brand/mao-baixo.png e mao-cima.png. A mão TROCA DE POSIÇÃO conforme
 * o alvo (pedido do Alf): vem de cima apontando pra baixo nos alvos altos, e
 * de baixo apontando pra cima nos alvos rentes ao rodapé.
 *
 * Não é enfeite. Com uma mão só, apontando pra baixo, tocar a TabBar cobria a
 * tela inteira com o dorso e o braço — justamente o clique que o Alf pediu pra
 * aparecer ("o dedinho clicando ali nos ícones ali embaixo"). Vindo de baixo,
 * a mão fica FORA da tela e só a unha entra.
 *
 * Histórico das reprovações, pra não repetir: 1ª foi uma bolinha; 2ª um desenho
 * meu em SVG (parecia luva); 3ª uma mão 3D apontando pra cima em TODO alvo, ou
 * seja, encostando com as costas do dedo.
 *
 * • A PONTA DO DEDO é o ponto de toque — as coordenadas dos keyframes são
 *   sempre onde a mão encosta, não onde ela fica.
 * • Caminhando: inclina pro lado do movimento e balança de leve.
 * • No toque: avança no eixo do dedo, encolhe um tico e solta o anel teal.
 * Coordenadas no espaço do pai (position:relative).
 */

export type CursorKeyframe = { frame: number; x: number; y: number; click?: boolean }

/** Onde está a ponta do dedo dentro de cada PNG, em fração da imagem — MEDIDO
 *  pixel a pixel por scripts/medir-mao.mjs (que também apara a moldura vazia e
 *  cospe uma prova visual com a cruz na unha), nunca estimado no olho. */
const MAOS = {
  baixo: { arquivo: 'brand/mao-baixo.png', pontaX: 0.085, pontaY: 0.9985, razao: 1.13 },
  cima: { arquivo: 'brand/mao-cima.png', pontaX: 0.0861, pontaY: 0, razao: 0.9831 },
} as const

/** Altura (no conteúdo de 410×816) a partir da qual o alvo é "rodapé" e a mão
 *  vira. 700 pega TabBar, FABs e botões de rodapé; deixa o resto com a mão de
 *  cima pra baixo, que é a que o Alf aprovou como padrão. */
const Y_VIRA = 700

export const Dedo: React.FC<{
  keyframes: CursorKeyframe[]
  /** largura da mão em px (no espaço do telefone) */
  tamanho?: number
  clickSound?: boolean
}> = ({ keyframes, tamanho = 150, clickSound = true }) => {
  const frame = useCurrentFrame()
  if (keyframes.length < 2) return null

  const ordenados = [...keyframes].sort((a, b) => a.frame - b.frame)

  // POUSAR E SEGURAR: depois de apertar, a mão fica no botão POUSADA_F frames
  // (~0,5s) e só então viaja, com VIAGEM_MIN de folga pra não "teleportar".
  // Sem isso ela toca e foge no mesmo instante — o toque não assenta e o olho
  // não acompanha o que foi apertado.
  //
  // Se a cena não deu espaço suficiente entre o clique e o destino seguinte,
  // a própria mão EMPURRA os keyframes seguintes pra frente. Os keyframes pós-
  // clique são só "sair da frente", não têm significado — adiá-los é seguro, e
  // evita ter que reequilibrar à mão as ~25 janelas curtas da coreografia.
  const POUSADA_F = 14
  const VIAGEM_MIN = 12

  // Só o keyframe de SAÍDA (o logo após um clique) é adiado — nunca um clique,
  // senão a mão descasa das mudanças de tela, que são presas a frames fixos.
  // O adiamento respeita o keyframe seguinte, então nada atropela nada.
  const espacados = ordenados.map((k, i) => {
    const anterior = ordenados[i - 1]
    if (!anterior?.click || k.click) return k
    const depois = ordenados[i + 1]
    const desejado = anterior.frame + POUSADA_F + VIAGEM_MIN
    const teto = depois ? depois.frame - 4 : desejado
    return { ...k, frame: Math.max(k.frame, Math.min(desejado, teto)) }
  })

  const comPousada: CursorKeyframe[] = []
  espacados.forEach((k, i) => {
    comPousada.push(k)
    const proximo = espacados[i + 1]
    if (!k.click || !proximo) return
    const janela = proximo.frame - k.frame
    if (janela < 8) return
    comPousada.push({ frame: k.frame + Math.min(POUSADA_F, janela - 6), x: k.x, y: k.y })
  })

  // interpolate exige inputRange crescente; keyframes repetidos (chega e clica
  // no mesmo frame) são deduplicados pro cálculo de posição.
  const pos = comPousada.filter((k, i) => i === 0 || k.frame > comPousada[i - 1].frame)
  const frames = pos.map((k) => k.frame)
  const opts = {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
    easing: Easing.inOut(Easing.cubic),
  } as const

  const em = (f: number) =>
    pos.length < 2
      ? { x: pos[0].x, y: pos[0].y }
      : {
          x: interpolate(f, frames, pos.map((k) => k.x), opts),
          y: interpolate(f, frames, pos.map((k) => k.y), opts),
        }

  const { x, y } = em(frame)
  const anterior = em(frame - 2)
  const vx = x - anterior.x
  const vy = y - anterior.y
  const velocidade = Math.hypot(vx, vy)

  const cliques = ordenados.filter((k) => k.click)
  const noClique = cliques.find((k) => frame >= k.frame && frame <= k.frame + 12)

  /**
   * A VIRADA. `mistura` vai de 0 (mão pra baixo) a 1 (mão pra cima) e troca NO
   * MEIO da viagem entre um toque e o seguinte, com cross-fade curto. Como as
   * duas pontas coincidem (x ≈ 0,085) e o pivô do transform é a unha, o giro
   * acontece em volta da própria ponta e lê como giro de pulso, não como corte.
   */
  const ehCima = (k: CursorKeyframe) => k.y >= Y_VIRA
  const rampa: { frame: number; v: number }[] = []
  if (cliques.length) {
    rampa.push({ frame: ordenados[0].frame - 1, v: ehCima(cliques[0]) ? 1 : 0 })
    for (let i = 0; i < cliques.length - 1; i++) {
      const a = ehCima(cliques[i])
      const b = ehCima(cliques[i + 1])
      if (a === b) continue
      const saida = cliques[i].frame + POUSADA_F
      const chegada = cliques[i + 1].frame
      const meio = (saida + chegada) / 2
      rampa.push({ frame: Math.max(saida, Math.min(meio - 4, chegada - 6)), v: a ? 1 : 0 })
      rampa.push({ frame: Math.min(meio + 4, chegada - 2), v: b ? 1 : 0 })
    }
    rampa.push({ frame: rampa[rampa.length - 1].frame + 1, v: rampa[rampa.length - 1].v })
  }
  // interpolate quebra com inputRange não-crescente; toques muito próximos
  // podem empurrar duas bordas pro mesmo frame. Força monotonia.
  let ultimo = -Infinity
  const rampaOk = rampa.map((p) => {
    const f = Math.max(p.frame, ultimo + 1)
    ultimo = f
    return { frame: f, v: p.v }
  })
  const mistura =
    rampaOk.length >= 2
      ? interpolate(frame, rampaOk.map((p) => p.frame), rampaOk.map((p) => p.v), opts)
      : 0

  // aperto: a mão avança um tico no eixo do dedo e encolhe
  const aperto = noClique
    ? interpolate(frame - noClique.frame, [0, 4, 12], [0, 1, 0], {
        extrapolateLeft: 'clamp',
        extrapolateRight: 'clamp',
      })
    : 0

  // caminhando: inclina pro lado pra onde vai + balanço leve (o "passo")
  const inclinacao = interpolate(vx, [-14, 0, 14], [-9, 0, 9], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  })
  const balanco = velocidade > 0.6 ? Math.sin(frame / 3.6) * 2 : 0
  const giroBase = inclinacao + balanco
  const escala = 1 - aperto * 0.05

  return (
    <>
      {clickSound &&
        cliques.map((k) => <Sfx key={`snd-${k.frame}`} file={SFX.tap} at={k.frame} volume={0.45} />)}

      {/* anel do toque, saindo da ponta do dedo */}
      {cliques.map((k) => {
        if (frame < k.frame || frame > k.frame + 16) return null
        const t = (frame - k.frame) / 16
        const d = 30 * (1 + t * 2.1)
        return (
          <div
            key={k.frame}
            style={{
              position: 'absolute',
              left: k.x,
              top: k.y,
              width: d,
              height: d,
              transform: 'translate(-50%, -50%)',
              borderRadius: '50%',
              border: '3px solid rgba(72,191,179,0.95)',
              opacity: 1 - t,
              zIndex: 49,
            }}
          />
        )
      })}

      {(['baixo', 'cima'] as const).map((qual) => {
        const m = MAOS[qual]
        const opacidade = qual === 'cima' ? mistura : 1 - mistura
        if (opacidade < 0.004) return null
        // o aperto avança no eixo do dedo: pra baixo numa, pra cima na outra
        const sentido = qual === 'cima' ? -1 : 1
        return (
          <Img
            key={qual}
            src={staticFile(m.arquivo)}
            style={{
              position: 'absolute',
              left: x - aperto * 3,
              top: y + aperto * 4 * sentido,
              width: tamanho,
              height: tamanho / m.razao,
              opacity: opacidade,
              transform: `translate(${-m.pontaX * 100}%, ${-m.pontaY * 100}%) rotate(${
                giroBase + aperto * 3 * sentido
              }deg) scale(${escala})`,
              transformOrigin: `${m.pontaX * 100}% ${m.pontaY * 100}%`,
              filter: 'drop-shadow(0 14px 22px rgba(0,0,0,.55))',
              zIndex: 50,
              pointerEvents: 'none',
            }}
          />
        )
      })}
    </>
  )
}
