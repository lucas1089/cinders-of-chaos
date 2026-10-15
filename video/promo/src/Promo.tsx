import React from 'react';
import {AbsoluteFill, Sequence, useVideoConfig} from 'remotion';
import {Embers, TopLogo, Vignette} from './components';
import {colors, loadFonts} from './theme';
import {PromoProps} from './strings';
import {HookScene} from './scenes/HookScene';
import {ShotScene} from './scenes/ShotScene';
import {ClassesScene} from './scenes/ClassesScene';
import {DungeonsScene} from './scenes/DungeonsScene';
import {BossesScene} from './scenes/BossesScene';
import {EndScene} from './scenes/EndScene';

loadFonts();

// Storyboard (30 fps): see README.md. Total 885 frames = 29.5 s.
export const Promo: React.FC<PromoProps> = ({strings: s}) => {
  const {fps} = useVideoConfig();
  return (
    <AbsoluteFill style={{background: colors.bg}}>
      <Sequence name="Hook" from={0} durationInFrames={90} premountFor={fps}>
        <HookScene hook1={s.hook1} hook2={s.hook2} />
      </Sequence>
      <Sequence name="Login (live footage)" from={90} durationInFrames={120} premountFor={fps}>
        <ShotScene src={`footage/${s.loginClip}`} video videoStart={2 * fps} caption={s.login} focusX={960} focusY={540} panFrom={700} panTo={1220} />
      </Sequence>
      <Sequence name="Spells" from={210} durationInFrames={90} premountFor={fps}>
        <ShotScene src="stills/fight_ice_liches.png" caption={s.spells} panFrom={820} panTo={1100} />
      </Sequence>
      <Sequence name="Packs" from={300} durationInFrames={90} premountFor={fps}>
        <ShotScene src="stills/fight_swamp_pack.png" caption={s.packs} panFrom={1100} panTo={800} brightness={1.45} />
      </Sequence>
      <Sequence name="Teleports" from={390} durationInFrames={90} premountFor={fps}>
        <ShotScene src="stills/teleport_room.png" caption={s.teleports} panFrom={540} panTo={1380} />
      </Sequence>
      <Sequence name="Classes" from={480} durationInFrames={120} premountFor={fps}>
        <ClassesScene title={s.classes} names={s.classNames} />
      </Sequence>
      <Sequence name="Dungeons" from={600} durationInFrames={105} premountFor={fps}>
        <DungeonsScene caption={s.dungeons} />
      </Sequence>
      <Sequence name="Bosses" from={705} durationInFrames={105} premountFor={fps}>
        <BossesScene caption={s.bosses} names={s.bossNames} />
      </Sequence>
      <Sequence name="End" from={810} durationInFrames={75} premountFor={fps}>
        <EndScene cta={s.cta} />
      </Sequence>
      <Sequence name="Top logo (9:16), hook" from={0} durationInFrames={90}>
        <TopLogo />
      </Sequence>
      <Sequence name="Top logo (9:16), features" from={210} durationInFrames={270}>
        <TopLogo />
      </Sequence>
      <Embers />
      <Vignette />
    </AbsoluteFill>
  );
};
