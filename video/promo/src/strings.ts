// Every on-screen text of the promo. An English cut is one prop change: --props=./props/en.json
export type PromoStrings = {
  hook1: string;
  hook2: string;
  login: string;
  spells: string;
  packs: string;
  teleports: string;
  classes: string;
  classNames: string[];
  dungeons: string;
  bosses: string;
  bossNames: [string, string, string];
  cta: string;
  // file under public/footage/ with the live login scene in this language
  loginClip: string;
};

export const ptBR: PromoStrings = {
  hook1: 'Uma horda.',
  hook2: 'Um feitiço.',
  login: 'Fantasia sombria em pixel art',
  spells: '88 feitiços próprios',
  packs: 'Monstros em bandos',
  teleports: 'Um teleporte para cada caçada',
  classes: '7 classes, 14 ascensões',
  classNames: ['Warrior', 'Ranger', 'Mystic', 'Thief', 'Necromancer', 'Monk', 'Templar'],
  dungeons: '9 dungeons, 6 dificuldades',
  bosses: 'Chefes com mecânicas próprias',
  bossNames: ['Vaelith the Fallen Seraph', 'Forgewarden Kharzun', 'Ossivane the Gravecage'],
  cta: 'Beta em breve',
  loginClip: 'login_ptbr.mp4',
};

export type PromoProps = {
  strings: PromoStrings;
};
