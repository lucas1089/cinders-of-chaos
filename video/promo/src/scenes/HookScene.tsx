import React from 'react';
import {AbsoluteFill, Sequence, interpolate, useCurrentFrame, useVideoConfig, Easing} from 'remotion';
import {Flash, Shot, useShake} from '../components';
import {colors, fonts} from '../theme';
import {useLayout} from '../layout';

const clamp = {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'} as const;

const BigWord: React.FC<{text: string; at: number}> = ({text, at}) => {
  const frame = useCurrentFrame();
  const {vertical} = useLayout();
  const t = interpolate(frame, [at, at + 7], [0, 1], {...clamp, easing: Easing.out(Easing.back(2))});
  return (
    <div
      style={{
        fontFamily: '"ChaosCinzel", serif',
        fontWeight: 900,
        fontSize: vertical ? 120 : 150,
        color: colors.text,
        opacity: t,
        scale: `${0.7 + 0.3 * t}`,
        textShadow: '0 6px 0 #000, 0 0 40px rgba(255,100,30,0.8), 0 0 6px #000',
        textAlign: 'center',
        lineHeight: 1.05,
      }}
    >
      {text}
    </div>
  );
};

// 0-3 s: one area spell over a whole pack, then a 2x punch-in on the damage numbers.
export const HookScene: React.FC<{hook1: string; hook2: string}> = ({hook1, hook2}) => {
  const {fps, durationInFrames} = useVideoConfig();
  const {vertical} = useLayout();
  const cut = Math.round(1.5 * fps);
  const s1 = useShake(0);
  const s2 = useShake(cut, 18);
  const s = {x: s1.x + s2.x, y: s1.y + s2.y};
  return (
    <AbsoluteFill style={{background: colors.bg}}>
      <AbsoluteFill style={{translate: `${s.x}px ${s.y}px`}}>
        <Sequence durationInFrames={cut} premountFor={fps}>
          <Shot src="stills/fight_fire_pack.png" focusX={940} focusY={500} panFrom={760} panTo={980} durationInFrames={cut} />
        </Sequence>
        <Sequence from={cut} premountFor={fps}>
          <Shot src="stills/fight_fire_pack.png" zoom={2} focusX={1120} focusY={470} panFrom={1060} panTo={1180} durationInFrames={durationInFrames - cut} />
        </Sequence>
      </AbsoluteFill>
      <AbsoluteFill
        style={{
          background: vertical
            ? 'linear-gradient(180deg, rgba(0,0,0,0) 1300px, rgba(8,4,3,0.9) 1400px)'
            : 'radial-gradient(ellipse 900px 380px at 50% 50%, rgba(8,4,3,0.72) 0%, rgba(8,4,3,0.45) 55%, rgba(8,4,3,0) 100%)',
        }}
      />
      <Flash at={0} />
      <Flash at={cut} color="#ffb070" />
      <AbsoluteFill
        style={{
          justifyContent: vertical ? 'flex-start' : 'center',
          alignItems: 'center',
          paddingTop: vertical ? 1420 : 0,
          gap: 8,
          fontFamily: fonts.title,
        }}
      >
        <BigWord text={hook1} at={4} />
        <BigWord text={hook2} at={cut + 4} />
      </AbsoluteFill>
    </AbsoluteFill>
  );
};
