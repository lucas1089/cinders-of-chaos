import React from 'react';
import {
  AbsoluteFill,
  Img,
  OffthreadVideo,
  interpolate,
  random,
  staticFile,
  useCurrentFrame,
  useVideoConfig,
  Easing,
} from 'remotion';
import {colors, fonts} from './theme';
import {useLayout} from './layout';

const clamp = {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'} as const;

type ShotProps = {
  // public path of a 1920x1080 capture
  src: string;
  video?: boolean;
  videoStart?: number;
  // integer zoom; 2 doubles game pixels with nearest-neighbour
  zoom?: number;
  // the source point that sits in the middle of the window (source pixels)
  focusX?: number;
  focusY?: number;
  // vertical cut: source x of the window centre at the start and end of the shot
  panFrom?: number;
  panTo?: number;
  durationInFrames: number;
  dim?: number;
  brightness?: number;
};

// A capture shown at an integer scale, positioned on whole pixels.
export const Shot: React.FC<ShotProps> = ({
  src,
  video,
  videoStart = 0,
  zoom = 1,
  focusX = 960,
  focusY = 540,
  panFrom,
  panTo,
  durationInFrames,
  dim = 0,
  brightness = 1,
}) => {
  const frame = useCurrentFrame();
  const {vertical, view} = useLayout();
  let cx = focusX;
  if (vertical && panFrom !== undefined && panTo !== undefined) {
    cx = interpolate(frame, [0, durationInFrames], [panFrom, panTo], {
      ...clamp,
      easing: Easing.inOut(Easing.quad),
    });
  }
  const w = 1920 * zoom;
  const h = 1080 * zoom;
  let left = Math.round(view.w / 2 - cx * zoom);
  let top = Math.round(view.h / 2 - focusY * zoom);
  left = Math.min(0, Math.max(view.w - w, left));
  top = Math.min(0, Math.max(view.h - h, top));
  const style: React.CSSProperties = {
    position: 'absolute',
    left,
    top,
    width: w,
    height: h,
    imageRendering: 'pixelated',
    filter: brightness !== 1 ? `brightness(${brightness})` : undefined,
  };
  return (
    <div
      style={{
        position: 'absolute',
        left: view.x,
        top: view.y,
        width: view.w,
        height: view.h,
        overflow: 'hidden',
      }}
    >
      {video ? (
        <OffthreadVideo src={staticFile(src)} trimBefore={videoStart} muted style={style} />
      ) : (
        <Img src={staticFile(src)} style={style} />
      )}
      {dim > 0 ? <AbsoluteFill style={{background: `rgba(6,3,2,${dim})`}} /> : null}
    </div>
  );
};

// Short shake after a hit, whole pixels only.
export const useShake = (at: number, strength = 14, length = 12) => {
  const frame = useCurrentFrame();
  const t = frame - at;
  if (t < 0 || t > length) {
    return {x: 0, y: 0};
  }
  const k = 1 - t / length;
  return {
    x: Math.round((random(`sx${at}-${t}`) * 2 - 1) * strength * k),
    y: Math.round((random(`sy${at}-${t}`) * 2 - 1) * strength * k),
  };
};

export const Flash: React.FC<{at: number; color?: string; length?: number}> = ({
  at,
  color = '#fff3dc',
  length = 9,
}) => {
  const frame = useCurrentFrame();
  const o = interpolate(frame, [at, at + length], [0.85, 0], clamp);
  if (frame < at) return null;
  return <AbsoluteFill style={{background: color, opacity: o, mixBlendMode: 'screen'}} />;
};

export const Vignette: React.FC = () => (
  <AbsoluteFill
    style={{
      background:
        'radial-gradient(ellipse at center, rgba(0,0,0,0) 55%, rgba(5,2,1,0.55) 85%, rgba(5,2,1,0.85) 100%)',
      pointerEvents: 'none',
    }}
  />
);

// Rising embers, drawn as small squares so they match the pixel art.
export const Embers: React.FC<{count?: number; seed?: string}> = ({count = 36, seed = 'e'}) => {
  const frame = useCurrentFrame();
  const {width, height} = useVideoConfig();
  return (
    <AbsoluteFill style={{pointerEvents: 'none'}}>
      {new Array(count).fill(0).map((_, i) => {
        const speed = 2 + random(`${seed}v${i}`) * 4;
        const size = 3 + Math.floor(random(`${seed}s${i}`) * 3) * 3;
        const x0 = random(`${seed}x${i}`) * width;
        const y = Math.round(height + 40 - ((random(`${seed}y${i}`) * height + frame * speed) % (height + 80)));
        const x = Math.round(x0 + Math.sin((frame + i * 17) / (14 + i % 7)) * 18);
        const life = (y / height);
        return (
          <div
            key={i}
            style={{
              position: 'absolute',
              left: x,
              top: y,
              width: size,
              height: size,
              background: i % 3 === 0 ? colors.gold : colors.ember,
              opacity: 0.25 + 0.6 * life,
              boxShadow: `0 0 ${size * 3}px ${colors.ember}`,
            }}
          />
        );
      })}
    </AbsoluteFill>
  );
};

// Caption plate: bottom left in 16:9, under the window in 9:16.
export const Caption: React.FC<{text: string; delay?: number; durationInFrames: number}> = ({
  text,
  delay = 4,
  durationInFrames,
}) => {
  const frame = useCurrentFrame();
  const {vertical} = useLayout();
  const inT = interpolate(frame, [delay, delay + 10], [0, 1], {...clamp, easing: Easing.out(Easing.cubic)});
  const outT = interpolate(frame, [durationInFrames - 6, durationInFrames], [1, 0], clamp);
  const bar = interpolate(frame, [delay + 4, delay + 18], [0, 1], {...clamp, easing: Easing.out(Easing.cubic)});
  const box: React.CSSProperties = vertical
    ? {position: 'absolute', left: 60, right: 60, top: 1440, textAlign: 'center'}
    : {position: 'absolute', left: 96, bottom: 110};
  return (
    <>
    <div
      style={{
        position: 'absolute',
        left: 0,
        right: 0,
        top: vertical ? 1380 : undefined,
        bottom: vertical ? undefined : 0,
        height: vertical ? 540 : 360,
        background: vertical ? 'transparent' : 'linear-gradient(0deg, rgba(8,4,3,0.85) 0%, rgba(8,4,3,0.55) 55%, rgba(8,4,3,0) 100%)',
        opacity: outT,
      }}
    />
    <div style={{...box, opacity: inT * outT, translate: vertical ? `0 ${Math.round((1 - inT) * 30)}px` : `${Math.round((1 - inT) * -60)}px 0`}}>
      <div
        style={{
          fontFamily: fonts.title,
          fontWeight: 800,
          fontSize: vertical ? 76 : 72,
          lineHeight: 1.1,
          color: colors.text,
          letterSpacing: 1,
          textShadow: '0 4px 0 #000, 0 0 28px rgba(255,110,40,0.55), 0 0 4px #000',
          display: 'inline-block',
          padding: vertical ? 0 : '6px 28px 10px 0',
        }}
      >
        {text}
      </div>
      <div
        style={{
          height: 6,
          marginTop: 10,
          width: vertical ? '60%' : '100%',
          marginLeft: vertical ? '20%' : 0,
          background: `linear-gradient(90deg, ${colors.ember}, ${colors.emberDeep} 70%, rgba(0,0,0,0))`,
          scale: `${bar} 1`,
          transformOrigin: vertical ? 'center' : 'left',
          boxShadow: `0 0 18px ${colors.ember}`,
        }}
      />
    </div>
    </>
  );
};

// Small logo above the window in the vertical cut.
export const TopLogo: React.FC = () => {
  const {vertical} = useLayout();
  if (!vertical) return null;
  return (
    <Img
      src={staticFile('art/logo.png')}
      style={{position: 'absolute', left: 540 - 220, top: 20, width: 440, height: 279}}
    />
  );
};
