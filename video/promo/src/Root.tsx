import React from 'react';
import {Composition} from 'remotion';
import {Promo} from './Promo';
import {ptBR} from './strings';

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
  </>
);
