import timing from './trailer_timing.json';
import {TrailerStrings} from './trailerStrings';

type Src = {clip: string; in: number; dir?: string};
type SceneRow = {
  id: string;
  section: string;
  kind?: string;
  dur: number;
  src?: Src | {pt: Src; en: Src};
  caption?: string;
  tag?: string;
  mark?: string;
  focusX?: number;
};

export type TimedScene = SceneRow & {from: number; frames: number; footage?: string};

export const FPS: number = timing.fps;

// The scenes of one cut with their first frame and length; durations snap to whole frames.
export const timeline = (cut: 'trailer' | 'short', lang: 'pt' | 'en'): TimedScene[] => {
  const rows = timing.scenes as SceneRow[];
  const byId = new Map(rows.map((s) => [s.id, s]));
  const list = (timing.cuts as Record<string, (string | [string, number])[]>)[cut];
  let from = 0;
  return list.map((entry) => {
    const [id, dur] = Array.isArray(entry) ? entry : [entry, byId.get(entry)!.dur];
    const row = byId.get(id)!;
    const frames = Math.round(dur * FPS);
    const perLang = row.src !== undefined && 'pt' in row.src;
    const footage = row.src ? `footage/trailer/${id}${perLang ? `_${lang}` : ''}.mp4` : undefined;
    const scene = {...row, dur, from, frames, footage};
    from += frames;
    return scene;
  });
};

export const cutFrames = (cut: 'trailer' | 'short'): number =>
  timeline(cut, 'pt').reduce((n, s) => n + s.frames, 0);

export const text = (s: TrailerStrings, key?: string): string | undefined =>
  key ? (s as Record<string, string>)[key] : undefined;
