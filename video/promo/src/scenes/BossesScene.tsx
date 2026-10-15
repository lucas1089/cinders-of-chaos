import React from 'react';
import {AbsoluteFill, Img, interpolate, staticFile, useCurrentFrame, useVideoConfig, Easing} from 'remotion';
import {Caption, Flash, useShake} from '../components';
import {colors, fonts} from '../theme';
import {useLayout} from '../layout';

const clamp = {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'} as const;
const BOSSES = ['vaelith', 'kharzun', 'ossivane'];

// The deep dungeon bosses with the owner's art (client pair 26), 128x128 sprites at 4x (3x in 9:16).
export const BossesScene: React.FC<{caption: string; names: [string, string, string]}> = ({caption, names}) => {
  const frame = useCurrentFrame();
  const {durationInFrames} = useVideoConfig();
  const {vertical} = useLayout();
  const scale = vertical ? 3 : 4;
  const size = 128 * scale;
  const hits = [6, 22, 38];
  const shake = [useShake(hits[0], 12, 10), useShake(hits[1], 12, 10), useShake(hits[2], 12, 10)];
  const sx = shake.reduce((a, s) => a + s.x, 0);
  const sy = shake.reduce((a, s) => a + s.y, 0);
  return (
    <AbsoluteFill style={{background: `radial-gradient(ellipse at 50% 45%, #3a140a 0%, #160806 45%, ${colors.bg} 80%)`}}>
      <AbsoluteFill style={{translate: `${sx}px ${sy}px`}}>
        {BOSSES.map((b, i) => {
          const t = interpolate(frame, [hits[i] - 6, hits[i]], [0, 1], {...clamp, easing: Easing.in(Easing.quad)});
          const labelT = interpolate(frame, [hits[i] + 2, hits[i] + 12], [0, 1], clamp);
          const cx = vertical ? 540 : 480 + i * 480;
          const cy = vertical ? 300 + i * 400 : 440;
          const left = Math.round(cx - size / 2);
          const top = Math.round(cy - size / 2 - (1 - t) * 160);
          return (
            <React.Fragment key={b}>
              <div
                style={{
                  position: 'absolute',
                  left: cx - 260,
                  top: cy - 120,
                  width: 520,
                  height: 300,
                  background: 'radial-gradient(ellipse at center, rgba(255,90,30,0.35) 0%, rgba(0,0,0,0) 65%)',
                  opacity: t,
                }}
              />
              <Img
                src={staticFile(`stills/boss_${b}.png`)}
                style={{position: 'absolute', left, top, width: size, height: size, imageRendering: 'pixelated', opacity: t}}
              />
              <div
                style={{
                  position: 'absolute',
                  left: cx - 300,
                  width: 600,
                  top: cy + size / 2 + (vertical ? -6 : 6),
                  textAlign: 'center',
                  fontFamily: fonts.title,
                  fontWeight: 700,
                  fontSize: vertical ? 38 : 34,
                  color: colors.gold,
                  opacity: labelT,
                  textShadow: '0 3px 0 #000, 0 0 14px rgba(255,120,40,0.5)',
                }}
              >
                {names[i]}
              </div>
            </React.Fragment>
          );
        })}
      </AbsoluteFill>
      {hits.map((h) => (
        <Flash key={h} at={h} color="#ff8a40" length={6} />
      ))}
      <Caption text={caption} delay={44} durationInFrames={durationInFrames} />
    </AbsoluteFill>
  );
};
