import React from 'react';
import {
  AbsoluteFill,
  Audio,
  Img,
  Sequence,
  interpolate,
  staticFile,
  useCurrentFrame,
  useVideoConfig,
  Easing,
} from 'remotion';
import {Caption, Embers, Flash, Shot, TopLogo, Vignette, useShake} from './components';
import {colors, fonts, loadFonts} from './theme';
import {useLayout} from './layout';
import {BigWord} from './scenes/HookScene';
import {EndScene} from './scenes/EndScene';
import {TrailerProps, TrailerStrings} from './trailerStrings';
import {TimedScene, text, timeline} from './trailerTimeline';

loadFonts();

const clamp = {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'} as const;

// Class or boss name, bottom right in 16:9 (above the caption in 9:16).
const Tag: React.FC<{label: string; durationInFrames: number}> = ({label, durationInFrames}) => {
  const frame = useCurrentFrame();
  const {vertical} = useLayout();
  const t = interpolate(frame, [3, 12], [0, 1], {...clamp, easing: Easing.out(Easing.cubic)});
  const out = interpolate(frame, [durationInFrames - 5, durationInFrames], [1, 0], clamp);
  const box: React.CSSProperties = vertical
    ? {left: 0, right: 0, top: 1395, textAlign: 'center'}
    : {right: 120, bottom: 300, textAlign: 'right'};
  return (
    <div
      style={{
        position: 'absolute',
        ...box,
        fontFamily: fonts.title,
        fontWeight: 700,
        fontSize: vertical ? 44 : 46,
        letterSpacing: 2,
        color: colors.gold,
        opacity: t * out,
        translate: `0 ${Math.round((1 - t) * 16)}px`,
        textShadow: '0 3px 0 #000, 0 0 18px rgba(255,120,40,0.6), 0 0 4px #000',
      }}
    >
      {label}
    </div>
  );
};

// One live capture: integer scale, a flash on the cut, the caption and the name tag.
const ClipScene: React.FC<{scene: TimedScene; s: TrailerStrings; punch?: boolean; flash?: boolean}> = ({
  scene,
  s,
  punch,
  flash = true,
}) => {
  const {durationInFrames} = useVideoConfig();
  const shake = useShake(0, scene.mark === 'big' || scene.section === 'finale' ? 14 : 8, 10);
  const caption = text(s, scene.caption);
  const tag = text(s, scene.tag);
  return (
    <AbsoluteFill style={{background: colors.bg}}>
      <AbsoluteFill style={{translate: `${shake.x}px ${shake.y}px`}}>
        <Shot
          src={scene.footage!}
          video
          zoom={punch ? 2 : 1}
          focusX={scene.focusX ?? 960}
          focusY={punch ? 430 : 540}
          durationInFrames={durationInFrames}
        />
      </AbsoluteFill>
      {scene.mark && flash ? (
        <Flash
          at={0}
          length={scene.section === 'finale' ? 4 : 8}
          color={scene.mark === 'big' || scene.section === 'finale' ? '#ffb070' : '#fff3dc'}
        />
      ) : null}
      {caption ? <Caption text={caption} durationInFrames={durationInFrames} /> : null}
      {tag ? <Tag label={tag} durationInFrames={durationInFrames} /> : null}
    </AbsoluteFill>
  );
};

// The login scene dimmed under the logo, then the line under it.
const TitleScene: React.FC<{scene: TimedScene; s: TrailerStrings}> = ({scene, s}) => {
  const frame = useCurrentFrame();
  const {durationInFrames} = useVideoConfig();
  const {vertical} = useLayout();
  const t = interpolate(frame, [0, 14], [0, 1], {...clamp, easing: Easing.out(Easing.cubic)});
  const c = interpolate(frame, [18, 30], [0, 1], {...clamp, easing: Easing.out(Easing.cubic)});
  const out = interpolate(frame, [durationInFrames - 6, durationInFrames], [1, 0], clamp);
  const logoW = vertical ? 900 : 980;
  return (
    <AbsoluteFill style={{background: colors.bg}}>
      <Shot src={scene.footage!} video durationInFrames={durationInFrames} dim={0.55} focusX={scene.focusX ?? 960} />
      <Flash at={0} color="#ffb070" length={12} />
      <AbsoluteFill style={{justifyContent: 'center', alignItems: 'center', flexDirection: 'column', opacity: out}}>
        <Img
          src={staticFile('art/logo.png')}
          style={{width: logoW, height: Math.round((logoW * 740) / 1168), opacity: t, scale: `${1.08 - 0.08 * t}`}}
        />
        <div
          style={{
            marginTop: vertical ? 30 : 0,
            fontFamily: fonts.title,
            fontWeight: 700,
            fontSize: vertical ? 54 : 56,
            letterSpacing: 3,
            color: colors.text,
            opacity: c,
            translate: `0 ${Math.round((1 - c) * 20)}px`,
            textShadow: '0 4px 0 #000, 0 0 24px rgba(255,110,40,0.7)',
            textAlign: 'center',
          }}
        >
          {text(s, scene.caption)}
        </div>
      </AbsoluteFill>
    </AbsoluteFill>
  );
};

// The two hook words over the cold open, on its second and third cut.
const HookWords: React.FC<{s: TrailerStrings; at1: number; at2: number}> = ({s, at1, at2}) => {
  const {vertical} = useLayout();
  return (
    <AbsoluteFill
      style={{
        justifyContent: vertical ? 'flex-start' : 'center',
        alignItems: 'center',
        paddingTop: vertical ? 1420 : 0,
        gap: 8,
        background: vertical
          ? 'transparent'
          : 'radial-gradient(ellipse 900px 340px at 50% 50%, rgba(8,4,3,0.55) 0%, rgba(8,4,3,0.25) 60%, rgba(8,4,3,0) 100%)',
      }}
    >
      <BigWord text={s.hook1} at={at1} />
      <BigWord text={s.hook2} at={at2} />
    </AbsoluteFill>
  );
};

// Trailer (about 86 s) and its 60 s vertical cut: one shot list, src/trailer_timing.json. README "Trailer".
export const Trailer: React.FC<TrailerProps> = ({strings: s, lang, cut}) => {
  const {fps, durationInFrames} = useVideoConfig();
  const scenes = timeline(cut, lang);
  const opens = scenes.filter((x) => x.section === 'coldopen');
  const openEnd = opens.length ? opens[opens.length - 1].from + opens[opens.length - 1].frames : 0;
  const title = scenes.find((x) => x.kind === 'title');
  const logoFrom = title ? title.from + title.frames : openEnd;
  const fadeOut = Math.round(1.5 * fps);
  return (
    <AbsoluteFill style={{background: colors.bg}}>
      {scenes.map((scene, i) => (
        <Sequence key={scene.id} name={scene.id} from={scene.from} durationInFrames={scene.frames} premountFor={fps}>
          {scene.kind === 'title' ? (
            <TitleScene scene={scene} s={s} />
          ) : scene.kind === 'end' ? (
            <EndScene cta={s.cta} />
          ) : (
            // the finale cuts every half second: a flash on every other cut only, no strobe
            <ClipScene
              scene={scene}
              s={s}
              punch={scene.section === 'finale' && i % 3 === 1}
              flash={scene.section !== 'finale' || i % 2 === 0}
            />
          )}
        </Sequence>
      ))}
      {opens.length >= 3 ? (
        <Sequence name="Hook words" from={0} durationInFrames={openEnd}>
          <HookWords s={s} at1={opens[1].from + 4} at2={opens[2].from + 4} />
        </Sequence>
      ) : null}
      <Sequence name="Top logo (9:16)" from={logoFrom} durationInFrames={durationInFrames - logoFrom - scenes[scenes.length - 1].frames}>
        <TopLogo />
      </Sequence>
      <Embers count={28} />
      <Vignette />
      <Audio
        src={staticFile(`audio/${cut}_score.wav`)}
        volume={(f) =>
          interpolate(f, [0, 8, durationInFrames - fadeOut, durationInFrames - 1], [0, 1, 1, 0], clamp)
        }
      />
    </AbsoluteFill>
  );
};
