import {useVideoConfig} from 'remotion';

// 16:9 shows a 1920x1080 capture whole. 9:16 shows a 1080x1080 window of it at 1:1 (pixels stay crisp)
// and pans across; the caption sits under the window.
export const useLayout = () => {
  const {width, height} = useVideoConfig();
  const vertical = height > width;
  return {
    vertical,
    width,
    height,
    view: vertical ? {x: 0, y: 300, w: 1080, h: 1080} : {x: 0, y: 0, w: 1920, h: 1080},
  };
};
