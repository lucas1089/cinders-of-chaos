import React from 'react';
import {Composition} from 'remotion';
import {Promo} from './Promo';
import {ptBR} from './strings';
import {Trailer} from './Trailer';
import {trailerPtBR} from './trailerStrings';
import {FPS, cutFrames} from './trailerTimeline';

export const RemotionRoot: React.FC = () => (
  <>
    <Composition
      id="Promo"
      component={Promo}
      durationInFrames={885}
      fps={30}
      width={1920}
      height={1080}
      defaultProps={{strings: ptBR}}
    />
    <Composition
      id="PromoVertical"
      component={Promo}
      durationInFrames={885}
      fps={30}
      width={1080}
      height={1920}
      defaultProps={{strings: ptBR}}
    />
    <Composition
      id="Trailer"
      component={Trailer}
      durationInFrames={cutFrames('trailer')}
      fps={FPS}
      width={1920}
      height={1080}
      defaultProps={{strings: trailerPtBR, lang: 'pt' as const, cut: 'trailer' as const}}
    />
    <Composition
      id="TrailerVertical"
      component={Trailer}
      durationInFrames={cutFrames('short')}
      fps={FPS}
      width={1080}
      height={1920}
      defaultProps={{strings: trailerPtBR, lang: 'pt' as const, cut: 'short' as const}}
    />
  </>
);
