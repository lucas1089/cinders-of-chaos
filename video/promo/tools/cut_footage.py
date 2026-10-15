"""Cut the trailer's shots out of the raw rig recordings.

Usage: python3 -I video/promo/tools/cut_footage.py RAW_DIR [--force]

RAW_DIR holds the raw 1920x1080 30 fps recordings of the live rig (README "Live rig"), named as the `clip` fields of
src/trailer_timing.json (c1_take4.mp4, ui_tree_pt.mp4, ...). A src with "dir": "footage" is read from public/footage/
instead (the login scenes of tools/capture_login.sh). Every scene of the table becomes public/footage/trailer/<id>.mp4,
or <id>_<lang>.mp4 for a capture made in each client language, cut from `in` for the scene's longest duration in any
cut (plus 0.2 s of slack). Existing files are kept unless --force. Needs ffmpeg.
"""
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..'))
TIMING = os.path.join(ROOT, 'src', 'trailer_timing.json')
OUT = os.path.join(ROOT, 'public', 'footage', 'trailer')


def longest(table):
    """Longest duration of each scene id over every cut (a cut entry may override the duration: [id, dur])."""
    dur = {s['id']: s['dur'] for s in table['scenes']}
    best = dict(dur)
    for entries in table['cuts'].values():
        for e in entries:
            if isinstance(e, list):
                best[e[0]] = max(best[e[0]], e[1])
    return best


def jobs(table, raw_dir):
    best = longest(table)
    for s in table['scenes']:
        src = s.get('src')
        if not src:
            continue
        variants = [(lang, src[lang]) for lang in ('pt', 'en')] if 'pt' in src else [(None, src)]
        for lang, v in variants:
            base = os.path.join(ROOT, 'public', 'footage') if v.get('dir') == 'footage' else raw_dir
            name = '%s_%s.mp4' % (s['id'], lang) if lang else '%s.mp4' % s['id']
            yield os.path.join(base, v['clip'] + '.mp4'), v['in'], best[s['id']] + 0.2, os.path.join(OUT, name)


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    raw_dir = sys.argv[1]
    force = '--force' in sys.argv
    with open(TIMING, encoding='utf-8') as f:
        table = json.load(f)
    os.makedirs(OUT, exist_ok=True)
    missing = 0
    for src, start, length, out in jobs(table, raw_dir):
        if not os.path.isfile(src):
            print('missing', src)
            missing += 1
            continue
        if os.path.isfile(out) and not force:
            continue
        # every frame a keyframe would be large; a short GOP keeps seeking cheap for the renderer
        subprocess.run(['ffmpeg', '-v', 'error', '-y', '-ss', '%.3f' % start, '-i', src, '-t', '%.3f' % length,
                        '-an', '-c:v', 'libx264', '-preset', 'medium', '-crf', '17', '-g', '15',
                        '-pix_fmt', 'yuv420p', out], check=True)
        print(os.path.relpath(out, ROOT))
    return 1 if missing else 0


if __name__ == '__main__':
    sys.exit(main())
