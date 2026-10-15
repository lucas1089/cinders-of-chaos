import React from 'react';
import {AbsoluteFill, Img, interpolate, staticFile, useCurrentFrame, Easing} from 'remotion';
import {colors, fonts} from '../theme';
import {useLayout} from '../layout';

const clamp = {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'} as const;

// Logo (client/overlay/data/images/chaos/logo.png) and the call to action. No date, no URL.
export const EndScene: React.FC<{cta: string}> = ({cta}) => {
  const frame = useCurrentFrame();
  const {vertical} = useLayout();
  const t = interpolate(frame, [0, 18], [0, 1], {...clamp, easing: Easing.out(Easing.cubic)});
  const c = interpolate(frame, [16, 28], [0, 1], {...clamp, easing: Easing.out(Easing.cubic)});
  const pulse = 0.75 + 0.25 * Math.sin(frame / 5);
  const logoW = vertical ? 960 : 1060;
  return (
    <AbsoluteFill
      style={{
        background: `radial-gradient(ellipse at 50% 42%, #3c160b 0%, #140705 50%, ${colors.bg} 85%)`,
        justifyContent: 'center',
        alignItems: 'center',
        flexDirection: 'column',
      }}
    >
      <Img
        src={staticFile('art/logo.png')}
        style={{width: logoW, height: Math.round((logoW * 740) / 1168), opacity: t, scale: `${0.9 + 0.1 * t}`}}
      />
      <div
        style={{
          marginTop: vertical ? 40 : 10,
          fontFamily: fonts.title,
          fontWeight: 800,
          fontSize: vertical ? 92 : 84,
          letterSpacing: 6,
          color: colors.text,
          opacity: c,
          translate: `0 ${Math.round((1 - c) * 24)}px`,
          textShadow: `0 5px 0 #000, 0 0 ${Math.round(30 * pulse)}px rgba(255,110,40,0.85)`,
          textTransform: 'uppercase',
        }}
      >
        {cta}
      </div>
    </AbsoluteFill>
  );
};
