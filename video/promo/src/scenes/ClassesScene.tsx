import React from 'react';
import {AbsoluteFill, interpolate, useCurrentFrame, useVideoConfig, Easing} from 'remotion';
import {Shot} from '../components';
import {colors, fonts} from '../theme';
import {useLayout} from '../layout';

const clamp = {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'} as const;

// 7 base classes, each with two ascensions (docs/CLASSES.md).
export const ClassesScene: React.FC<{title: string; names: string[]}> = ({title, names}) => {
  const frame = useCurrentFrame();
  const {durationInFrames} = useVideoConfig();
  const {vertical} = useLayout();
  const tIn = interpolate(frame, [2, 14], [0, 1], {...clamp, easing: Easing.out(Easing.cubic)});
  const out = interpolate(frame, [durationInFrames - 6, durationInFrames], [1, 0], clamp);
  return (
    <AbsoluteFill style={{background: colors.bg}}>
      <Shot src="stills/arrival_camp.png" focusX={940} focusY={420} panFrom={1300} panTo={700} durationInFrames={durationInFrames} dim={0.62} />
      <AbsoluteFill
        style={{
          justifyContent: 'center',
          alignItems: 'center',
          flexDirection: 'column',
          gap: vertical ? 28 : 40,
          opacity: out,
          paddingTop: vertical ? 0 : 0,
        }}
      >
        <div
          style={{
            fontFamily: fonts.title,
            fontWeight: 800,
            fontSize: vertical ? 92 : 104,
            color: colors.text,
            opacity: tIn,
            translate: `0 ${Math.round((1 - tIn) * 30)}px`,
            textShadow: '0 5px 0 #000, 0 0 30px rgba(255,110,40,0.6)',
            textAlign: 'center',
          }}
        >
          {title}
        </div>
        <div
          style={{
            display: 'flex',
            flexDirection: vertical ? 'column' : 'row',
            flexWrap: 'wrap',
            justifyContent: 'center',
            alignItems: 'center',
            gap: vertical ? 14 : '18px 34px',
            maxWidth: vertical ? 1000 : 1840,
          }}
        >
          {names.map((n, i) => {
            const t = interpolate(frame, [16 + i * 5, 26 + i * 5], [0, 1], {...clamp, easing: Easing.out(Easing.cubic)});
            return (
              <div
                key={n}
                style={{
                  fontFamily: fonts.title,
                  fontWeight: 700,
                  fontSize: vertical ? 62 : 46,
                  color: colors.gold,
                  opacity: t,
                  translate: `0 ${Math.round((1 - t) * 24)}px`,
                  textShadow: '0 3px 0 #000, 0 0 16px rgba(255,120,40,0.45)',
                }}
              >
                {n}
              </div>
            );
          })}
        </div>
      </AbsoluteFill>
    </AbsoluteFill>
  );
};
