import { describe, expect, it } from 'vitest'
import {
  CAMPOS_MANUAIS,
  aplicarCopia,
  contarDiferencasRascunho,
  detectarSobrescritas,
  mesclarCacheComRoster,
  seloAoEditar,
  seloAoGuardarLocal,
  type FatiaManual,
} from './modelo'

const fatias: FatiaManual[] = [
  {
    id: 'arthur',
    alunoId: 1,
    alunoNome: 'Arthur',
    versao: 1,
    campos: { repertorio: 'Astrobot', atividades: 'Até a metade', objetivo: 'Leitura' },
  },
  {
    id: 'nicolas',
    alunoId: 2,
    alunoNome: 'Nicolas',
    versao: 1,
    campos: { repertorio: 'Meu Lanchinho', objetivo: 'Coordenação' },
  },
]

describe('modelo da ficha manual', () => {
  it('mantém somente os seis campos pedagógicos aprovados', () => {
    expect(CAMPOS_MANUAIS).toEqual([
      'repertorio',
      'atividades',
      'objetivo',
      'observacao',
      'dever_casa',
      'progresso',
    ])
  })

  it('copia um campo somente para destinos pertencentes ao roster local', () => {
    const resultado = aplicarCopia(fatias, {
      origemId: 'arthur',
      destinos: ['nicolas', 'forjado'],
      campos: ['atividades'],
    })

    expect(resultado.find((f) => f.id === 'nicolas')?.campos.atividades).toBe('Até a metade')
    expect(resultado).toHaveLength(2)
  })

  it('duplicar ficha não leva presença nem metadados internos', () => {
    const comCampoForjado = [
      {
        ...fatias[0],
        campos: { ...fatias[0].campos, presenca: 'ausente', aula_id: 'forjada' } as never,
      },
      fatias[1],
    ]
    const resultado = aplicarCopia(comCampoForjado, {
      origemId: 'arthur',
      destinos: ['nicolas'],
      campos: [...CAMPOS_MANUAIS],
    })
    const destino = resultado.find((f) => f.id === 'nicolas')!

    expect(destino.campos).not.toHaveProperty('presenca')
    expect(destino.campos).not.toHaveProperty('aula_id')
    expect(destino.campos.repertorio).toBe('Astrobot')
  })

  it('avisa exatamente quais valores preenchidos serão sobrescritos', () => {
    expect(
      detectarSobrescritas(fatias, {
        origemId: 'arthur',
        destinos: ['nicolas'],
        campos: [...CAMPOS_MANUAIS],
      }),
    ).toEqual([{ destinoId: 'nicolas', destinoNome: 'Nicolas', campos: ['repertorio', 'objetivo'] }])
  })

  it('campo vazio da origem nunca apaga conteúdo já preenchido no destino', () => {
    const resultado = aplicarCopia(
      [
        { ...fatias[0], campos: { observacao: '' } },
        { ...fatias[1], campos: { observacao: 'Manter esta observação' } },
      ],
      { origemId: 'arthur', destinos: ['nicolas'], campos: ['observacao'] },
    )

    expect(resultado.find((f) => f.id === 'nicolas')?.campos.observacao).toBe('Manter esta observação')
  })
})

describe('conflito de rascunho manual', () => {
  it('conta divergencias entre o cache local e o servidor por campo e aluno', () => {
    const servidor = fatias.map((fatia) => ({ ...fatia, campos: { ...fatia.campos } }))
    const local = servidor.map((fatia) => fatia.id === 'arthur'
      ? { ...fatia, campos: { ...fatia.campos, objetivo: 'Nova leitura', progresso: 'Avancou' } }
      : fatia)

    expect(contarDiferencasRascunho(
      { objetivo: 'Objetivo comum' },
      { objetivo: 'Outro objetivo' },
      local,
      servidor,
    )).toBe(3)
  })

  it('preserva edicoes locais sem esconder aluno novo recebido do roster', () => {
    const servidor = [
      ...fatias,
      { id: 'caio', alunoId: 3, alunoNome: 'Caio', versao: 2, campos: {} },
    ]
    const local = fatias.map((fatia) => fatia.id === 'arthur'
      ? { ...fatia, campos: { ...fatia.campos, objetivo: 'Objetivo local' } }
      : fatia)

    const resultado = mesclarCacheComRoster(local, servidor)

    expect(resultado).toHaveLength(3)
    expect(resultado.find((fatia) => fatia.id === 'arthur')?.campos.objetivo).toBe('Objetivo local')
    expect(resultado.find((fatia) => fatia.id === 'caio')?.alunoNome).toBe('Caio')
  })
})

describe('selo de salvamento quando o professor digita', () => {
  // Medido no harness em 18/08/2026: 37 teclas produziam 76 trocas no cabeçalho —
  // "Não salvo" (71,7px) ⇄ "Só neste aparelho" (109px), duas por tecla. A tecla
  // não muda a notícia; só o PRIMEIRO caractere depois de um salvamento muda.
  it('não re-anuncia quando o texto já está guardado neste aparelho', () => {
    expect(seloAoEditar('local')).toBe('local')
  })

  it('avisa assim que o professor sai do estado salvo', () => {
    expect(seloAoEditar('salvo')).toBe('nao_salvo')
  })

  it('avisa também quando digita por cima de um salvamento em voo', () => {
    expect(seloAoEditar('salvando')).toBe('nao_salvo')
  })

  it('mantém o aviso de que a gravação local falhou', () => {
    expect(seloAoEditar('nao_salvo')).toBe('nao_salvo')
  })

  // O conflito é uma decisão que o professor ainda deve ("usar servidor" ou
  // "manter o que digitei"). Digitar não é decidir: apagar o aviso escondia os
  // dois botões, destravava o "Revisar e confirmar" e fazia a página pular.
  it('não apaga o conflito de versão — digitar não é decidir', () => {
    expect(seloAoEditar('conflito')).toBe('conflito')
  })
})

describe('selo quando o gravador local responde', () => {
  // O `.then` do gravador local é a SEGUNDA porta que publica estado por tecla.
  // Medido no harness: consertar só a porta síncrona não bastou — com o conflito
  // na tela, uma tecla ainda apagava o banner por este caminho.
  it('confirma que o texto ficou guardado neste aparelho', () => {
    expect(seloAoGuardarLocal('nao_salvo', true)).toBe('local')
  })

  it('acusa quando nem no aparelho deu para guardar', () => {
    expect(seloAoGuardarLocal('nao_salvo', false)).toBe('nao_salvo')
  })

  it('não apaga o conflito nem quando a gravação local dá certo', () => {
    expect(seloAoGuardarLocal('conflito', true)).toBe('conflito')
  })

  it('não apaga o conflito quando a gravação local falha', () => {
    expect(seloAoGuardarLocal('conflito', false)).toBe('conflito')
  })
})
