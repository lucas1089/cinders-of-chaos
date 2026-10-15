import React from 'react';
import {AbsoluteFill, useVideoConfig} from 'remotion';
import {Caption, Shot} from '../components';
import {colors} from '../theme';

type Props = {
  src: string;
  caption: string;
  video?: boolean;
  videoStart?: number;
  focusX?: number;
  focusY?: number;
  panFrom?: number;
  panTo?: number;
  brightness?: number;
};

// One capture with a caption.
export const ShotScene: React.FC<Props> = ({caption, ...shot}) => {
  const {durationInFrames} = useVideoConfig();
  return (
    <AbsoluteFill style={{background: colors.bg}}>
      <Shot {...shot} durationInFrames={durationInFrames} />
      <Caption text={caption} durationInFrames={durationInFrames} />
    </AbsoluteFill>
  );
};
