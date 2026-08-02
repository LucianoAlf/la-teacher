import React from 'react'
import { Composition } from 'remotion'
import { Piloto } from './Piloto'

export const Root: React.FC = () => (
  <>
    <Composition
      id="Piloto"
      component={Piloto}
      durationInFrames={540} // 18s a 30fps
      fps={30}
      width={1080}
      height={1350} // 4:5 — o formato que melhor mostra celular e ainda cabe no feed
    />
  </>
)
