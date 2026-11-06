#!/usr/bin/env python3
"""Montages of recorded gameplay clips (O418): trailer 16:9 and 9:16, five short videos 9:16, each in pt-BR and en
(docs/PROMO.md "Recorded montages"). Reuses the captions, logo burn and end card of gen_promo_video.py and the game's own
region music. The clips are 1920x1080 30 fps recordings of the real client, listed in docs/PROMO.md; they are not in git.

    python3 -I website/tools/gen_promo_montage.py --clips CLIP_DIR --out OUT_DIR [--only NAME,...] [--check]

--check only checks the plans (every segment fits its clip when CLIP_DIR has the clips; captions exist in both languages).
Needs numpy, Pillow and ffmpeg.
"""
import argparse
import os
import subprocess
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)
import gen_promo_video as g  # noqa: E402

CLIPS = None  # set by main()
MUSIC = os.path.join(REPO, 'client', 'overlay', 'modules', 'game_chaosmusic', 'music')
FPS = 30
# game picture crops of the 1920x1080 recordings: the character stands near (940, 460)
CROP = {'wide': (300, 100, 1280, 720), 'tall': (680, 38, 522, 928)}
FULL = {'wide': (0, 0, 1920, 1080), 'tall': (656, 0, 608, 1080)}
SIZE = {'wide': (1920, 1080), 'tall': (1080, 1920)}
CLASS_NAMES = {'pt-BR': {'mystic': 'Místico', 'warrior': 'Guerreiro', 'thief': 'Ladino', 'ranger': 'Patrulheiro',
                         'monk': 'Monge', 'necro': 'Necromante', 'templar': 'Templário'},
               'en': {'mystic': 'Mystic', 'warrior': 'Warrior', 'thief': 'Thief', 'ranger': 'Ranger',
                      'monk': 'Monk', 'necro': 'Necromancer', 'templar': 'Templar'}}
EXTRA = {
    'pt-BR': {'rift_hook': 'Abra um Rift.', 'rift_2': 'Feche antes do tempo acabar.', 'tower_hook': 'Torre Infinita',
              'tower_2': 'Até onde você sobe?', 'arena_hook': 'Arena 1v1', 'arena_2': 'Sem perda na morte.',
              'boss_2': 'Chefes que enchem a tela.'},
    'en': {'rift_hook': 'Open a Rift.', 'rift_2': 'Seal it before time runs out.', 'tower_hook': 'Infinity Tower',
           'tower_2': 'How high can you climb?', 'arena_hook': 'Arena 1v1', 'arena_2': 'No death loss.',
           'boss_2': 'Bosses that fill the screen.'},
}


def text(lang, key):
    if key.startswith('class:'):
        return CLASS_NAMES[lang][key[6:]]
    return EXTRA[lang].get(key) or g.TEXT[lang][key]


# (kind, ...): ('clip', file, start, seconds, caption key or None) | ('intro', seconds) | ('end', seconds)
CLASSES = [('mystic_s', 4.0), ('warrior_s', 6.0), ('thief_s', 4.0), ('ranger_s', 3.0), ('monk', 6.0), ('necro', 6.0),
           ('templar', 6.0)]
CLASS_KEY = {'mystic_s': 'mystic', 'warrior_s': 'warrior', 'thief_s': 'thief', 'ranger_s': 'ranger', 'monk': 'monk',
             'necro': 'necro', 'templar': 'templar'}
PLANS = {
    'trailer': ('boss', [('intro', 4), ('clip', 'temple_s', 1.0, 6, 'world')]
                + [('clip', c, t, 1.6, 'classes') for c, t in CLASSES]
                + [('clip', '09_ui_tour', 6.7, 6, 'build', {'full': True, 'speed': 0.5}),
                   ('clip', 'tower_s', 43.0, 4, 'loot'),
                   ('clip', 'rift_s', 5.0, 4, 'rift'),
                   ('clip', 'rift_s', 22.0, 4, 'rift'),
                   ('clip', 'boss_s', 2.0, 8, 'raid'),
                   ('clip', 'arena_s', 21.0, 6, 'pvp'),
                   ('end', 6)]),
    'short-rift': ('dungeon', [
        ('clip', 'rift_s', 3.0, 7, 'rift_hook'),
        ('clip', 'rift_s', 20.0, 9, 'rift_2'),
        ('end', 4),
    ]),
    'short-tower': ('boss', [
        ('clip', 'tower_s', 2.0, 8, 'tower_hook'),
        ('clip', 'tower_s', 40.0, 10, 'tower_2'),
        ('end', 4),
    ]),
    'short-arena': ('arena', [
        ('clip', 'arena_s', 8.0, 5, 'arena_hook'),
        ('clip', 'arena_s', 20.0, 9, 'pvp'),
        ('end', 4),
    ]),
    'short-classes': ('hunt', [('clip', c, t, 3, 'class:' + CLASS_KEY[c]) for c, t in CLASSES] + [('end', 4)]),
    'short-boss': ('boss', [
        ('clip', 'boss_s', 1.0, 6, 'raid'),
        ('clip', 'boss_s', 26.0, 8, 'boss_2'),
        ('end', 4),
    ]),
}


def scrim(lay):
    """dark gradient under the caption"""
    W, H = SIZE[lay]
    h = 520 if lay == 'wide' else 760
    a = (np.linspace(0, 1, h) ** 1.6 * 225).astype(np.uint8)
    img = np.zeros((H, W, 4), np.uint8)
    img[H - h:, :, 3] = a[:, None]
    return img


def caption_png(lang, key, lay, path):
    W, H = SIZE[lay]
    c = g.caption_image(text(lang, key), 96 if lay == 'wide' else 84, W - 160)
    img = scrim(lay)
    cy = 930 if lay == 'wide' else 1640
    h, w = c.shape[:2]
    x, y = (W - w) // 2, cy - h // 2
    base = Image.fromarray(img)
    base.alpha_composite(Image.fromarray(c), (x, y))
    base.save(path)


def enc_args(out):
    return ['-an', '-c:v', 'libx264', '-preset', 'medium', '-crf', '19', '-pix_fmt', 'yuv420p', '-r', str(FPS), out]


def render_clip(seg, lang, lay, tmp, i, fade_in):
    _, name, start, secs, cap = seg[:5]
    opts = seg[5] if len(seg) > 5 else {}
    speed = opts.get('speed', 1.0)
    cx, cy, cw, ch = (FULL if opts.get('full') else CROP)[lay]
    W, H = SIZE[lay]
    out = os.path.join(tmp, '%02d.mp4' % i)
    flt = '[0:v]setpts=PTS/%g,crop=%d:%d:%d:%d,scale=%d:%d:flags=lanczos,setsar=1,fps=%d' % (speed, cw, ch, cx, cy, W, H, FPS)
    if fade_in:
        flt += ',fade=in:st=0:d=0.6'
    inputs = ['-ss', str(start), '-t', str(secs * speed), '-i', os.path.join(CLIPS, name + '.mp4')]
    if cap:
        png = os.path.join(tmp, 'cap%02d.png' % i)
        caption_png(lang, cap, lay, png)
        inputs += ['-loop', '1', '-t', str(secs), '-i', png]
        flt += '[v];[1:v]format=rgba[c];[v][c]overlay=0:0:shortest=1'
    subprocess.run(['ffmpeg', '-loglevel', 'error', '-y'] + inputs + ['-filter_complex', flt] + enc_args(out), check=True)
    return out


def pipe_frames(frames_fn, n, W, H, out):
    p = subprocess.Popen(['ffmpeg', '-loglevel', 'error', '-y', '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-s', '%dx%d' % (W, H),
                          '-r', str(FPS), '-i', '-'] + enc_args(out), stdin=subprocess.PIPE)
    for k in range(n):
        p.stdin.write(frames_fn(k).tobytes())
    p.stdin.close()
    p.wait()
    return out


def render_intro(secs, lay, tmp, i):
    W, H = SIZE[lay]
    L = dict(g.layouts()['wide' if lay == 'wide' else 'tall'])
    logo, noise = g.logo_burn(L)
    n = int(secs * FPS)

    def frame(k):
        f = np.zeros((H, W, 3), np.uint8)
        g.draw_logo_burn(f, logo, noise, min(1.2, 1.3 * k / n), W // 2, H // 2)
        return f
    return pipe_frames(frame, n, W, H, os.path.join(tmp, '%02d.mp4' % i))


def render_end(secs, lang, lay, tmp, i):
    W, H = SIZE[lay]
    card = g.end_card(lang, g.layouts()['wide' if lay == 'wide' else 'tall']).astype(np.float32)
    n = int(secs * FPS)

    def frame(k):
        return (card * min(1.0, k / 15)).astype(np.uint8)
    return pipe_frames(frame, n, W, H, os.path.join(tmp, '%02d.mp4' % i))


def render(name, lang, lay, out_dir):
    track, plan = PLANS[name]
    tmp = os.path.join(out_dir, '_tmp', '%s-%s-%s' % (name, lay, lang))
    os.makedirs(tmp, exist_ok=True)
    parts, total, prev = [], 0.0, None
    for i, seg in enumerate(plan):
        if seg[0] == 'intro':
            parts.append(render_intro(seg[1], lay, tmp, i))
        elif seg[0] == 'end':
            parts.append(render_end(seg[1], lang, lay, tmp, i))
        else:
            parts.append(render_clip(seg, lang, lay, tmp, i, fade_in=prev in (None, 'intro')))
        total += seg[3] if seg[0] == 'clip' else seg[1]
        prev = seg[0]
    lst = os.path.join(tmp, 'list.txt')
    with open(lst, 'w') as f:
        f.writelines("file '%s'\n" % p for p in parts)
    W, H = SIZE[lay]
    out = os.path.join(out_dir, '%s-%dx%d.%s.mp4' % (name, W, H, lang))
    music = os.path.join(MUSIC, 'music_%s.ogg' % track)
    subprocess.run(['ffmpeg', '-loglevel', 'error', '-y', '-f', 'concat', '-safe', '0', '-i', lst, '-i', music,
                    '-filter_complex', '[1:a]atrim=0:%.2f,afade=in:st=0:d=1,afade=out:st=%.2f:d=2.5[a]' % (total, total - 2.5),
                    '-map', '0:v', '-map', '[a]', '-c:v', 'copy', '-c:a', 'aac', '-b:a', '160k', '-movflags', '+faststart',
                    '-shortest', out], check=True)
    print(out, '%.1f s' % total)


SHORTS = ['short-rift', 'short-tower', 'short-arena', 'short-classes', 'short-boss']
JOBS = ([('trailer', lang, lay) for lay in ('wide', 'tall') for lang in ('pt-BR', 'en')]
        + [(n, lang, 'tall') for n in SHORTS for lang in ('pt-BR', 'en')])


def clip_names():
    return sorted({seg[1] for _, plan in PLANS.values() for seg in plan if seg[0] == 'clip'})


def clip_seconds(name):
    out = subprocess.run(['ffprobe', '-v', 'error', '-show_entries', 'format=duration', '-of', 'csv=p=0',
                          os.path.join(CLIPS, name + '.mp4')], capture_output=True, text=True, check=True).stdout
    return float(out.strip())


def check(have_clips):
    """problems of the plans: unknown caption keys, segments past the end of their clip"""
    bad = []
    for name, (track, plan) in PLANS.items():
        if not os.path.isfile(os.path.join(MUSIC, 'music_%s.ogg' % track)):
            bad.append('%s: no music_%s.ogg' % (name, track))
        for seg in plan:
            if seg[0] != 'clip':
                continue
            for lang in ('pt-BR', 'en'):
                try:
                    text(lang, seg[4])
                except KeyError:
                    bad.append('%s: caption %s missing in %s' % (name, seg[4], lang))
            if have_clips:
                speed = (seg[5] if len(seg) > 5 else {}).get('speed', 1.0)
                if seg[2] + seg[3] * speed > clip_seconds(seg[1]) + 0.01:
                    bad.append('%s: %s %.1f+%.1f s past the clip end' % (name, seg[1], seg[2], seg[3] * speed))
    return bad


def main():
    global CLIPS
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[1])
    ap.add_argument('--clips', required=True)
    ap.add_argument('--out')
    ap.add_argument('--only', default='')
    ap.add_argument('--check', action='store_true')
    a = ap.parse_args()
    CLIPS = a.clips
    missing = [n for n in clip_names() if not os.path.isfile(os.path.join(CLIPS, n + '.mp4'))]
    if missing and not a.check:
        sys.exit('missing clips in %s: %s' % (CLIPS, ', '.join(missing)))
    bad = check(not missing)
    for b in bad:
        print('FAIL', b)
    if a.check or bad:
        sys.exit(1 if bad else 0)
    only = [x for x in a.only.split(',') if x]
    for name, lang, lay in JOBS:
        if not only or name in only:
            render(name, lang, lay, a.out)


if __name__ == '__main__':
    main()
