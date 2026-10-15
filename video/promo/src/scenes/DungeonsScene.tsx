import React from 'react';
import {AbsoluteFill, Img, staticFile, useCurrentFrame, useVideoConfig} from 'remotion';
import {Caption} from '../components';
import {colors} from '../theme';
import {useLayout} from '../layout';

// The 9 dungeon banners of the client (client/overlay/data/images/dungeons), 1:1, scrolling up.
const BANNERS = [
  'Bones', 'MasterElement', 'Forbidden', 'Rootkraken', 'HollowVault',
  'MarrowCrypts', 'IronCrucible', 'FallenSanctum', 'PyreThrone',
];

export const DungeonsScene: React.FC<{caption: string}> = ({caption}) => {
  const frame = useCurrentFrame();
  const {durationInFrames} = useVideoConfig();
  const {vertical, width, height} = useLayout();
  const gap = 18;
  const step = 100 + gap;
  const startY = vertical ? 260 : 120;
  const speed = vertical ? 5 : 4;
  const y0 = startY - frame * speed;
  const left = Math.round((width - 966) / 2);
  const fadeTo = vertical ? 1400 : height;
  return (
    <AbsoluteFill style={{background: `radial-gradient(ellipse at 50% 40%, #2a120b 0%, ${colors.bg} 70%)`}}>
      <AbsoluteFill
        style={{
          WebkitMaskImage: `linear-gradient(180deg, transparent 0px, #000 140px, #000 ${fadeTo - 260}px, transparent ${fadeTo - 60}px)`,
        }}
      >
        {[...BANNERS, ...BANNERS].map((b, i) => (
          <div
            key={`${b}${i}`}
            style={{
              position: 'absolute',
              left,
              top: Math.round(y0 + i * step),
              width: 966,
              height: 100,
              outline: `3px solid #5a2a14`,
              boxShadow: '0 0 0 6px #120806, 0 10px 30px rgba(0,0,0,0.8)',
            }}
          >
            <Img src={staticFile(`art/dungeons/${b}.png`)} style={{width: 966, height: 100, imageRendering: 'pixelated'}} />
          </div>
        ))}
      </AbsoluteFill>
      <Caption text={caption} durationInFrames={durationInFrames} />
    </AbsoluteFill>
  );
};
