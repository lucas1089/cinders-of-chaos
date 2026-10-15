// Every on-screen text of the trailer. English: --props=./props/trailer_en.json. Captions stay at six words or fewer.
// Each number is in docs/CONTENT_LIST.md (README "Trailer", Claims).
export type TrailerStrings = {
  hook1: string;
  hook2: string;
  title: string;
  teleports: string;
  packs: string;
  loot: string;
  classes: string;
  classPlay: string;
  classBerserker: string;
  classBoneLord: string;
  classInquisitor: string;
  tree: string;
  supports: string;
  codex: string;
  dungeons: string;
  gate: string;
  bosses: string;
  bossVaelith: string;
  bossKharzun: string;
  bossAzhkarrath: string;
  rifts: string;
  atlas: string;
  worldBoss: string;
  cta: string;
};

export const trailerPtBR: TrailerStrings = {
  hook1: 'Uma horda.',
  hook2: 'Um feitiço.',
  title: 'Fantasia sombria em pixel art',
  teleports: 'Um teleporte para cada caçada',
  packs: 'Monstros em bandos',
  loot: '15 raridades de itens',
  classes: '7 classes, 14 ascensões',
  classPlay: 'Cada classe joga diferente',
  classBerserker: 'Berserker',
  classBoneLord: 'Bone Lord',
  classInquisitor: 'Inquisitor',
  tree: 'Árvore passiva de 663 nós',
  supports: '20 suportes de feitiço',
  codex: '106 únicos, 77 modificadores',
  dungeons: '9 dungeons, 6 dificuldades',
  gate: 'Chefe liberado aos 85%',
  bosses: 'Chefes com mecânicas próprias',
  bossVaelith: 'Vaelith the Fallen Seraph',
  bossKharzun: 'Forgewarden Kharzun',
  bossAzhkarrath: 'Azhkarrath the Chained Wyrm',
  rifts: 'Rifts com 36 modificadores',
  atlas: 'Atlas de 81 nós',
  worldBoss: '5 chefes mundiais',
  cta: 'Beta em breve',
};

export type TrailerProps = {
  strings: TrailerStrings;
  // client language of the UI captures (public/footage/trailer/<id>_<lang>.mp4)
  lang: 'pt' | 'en';
  // which list of src/trailer_timing.json "cuts" to play; the score is public/audio/<cut>_score.wav
  cut: 'trailer' | 'short';
};
