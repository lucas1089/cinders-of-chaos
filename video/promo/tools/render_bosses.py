"""Render the deep dungeon boss sprites (owner art, client pair 26) to public/stills/.

Usage: python3 -I video/promo/tools/render_bosses.py PAIR_DIR
PAIR_DIR holds the merged Tibia.dat / Tibia.spr of pair 26 (not in git).
Look types come from the monster files in server/data/monster/monsters/chaos/.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..', '..', '..'))
sys.path.insert(0, os.path.join(REPO, 'client', 'tools', 'sprites'))
from datspr import Dat, Spr, render_thing  # noqa: E402

BOSSES = [(2213, 'vaelith'), (2215, 'kharzun'), (2214, 'ossivane')]


def main():
    pair = sys.argv[1]
    out = os.path.join(HERE, '..', 'public', 'stills')
    dat = Dat(os.path.join(pair, 'Tibia.dat'))
    spr = Spr(os.path.join(pair, 'Tibia.spr'))
    for look, name in BOSSES:
        img = render_thing(dat.outfit(look), spr, direction='south')
        img.save(os.path.join(out, 'boss_%s.png' % name))
        print('boss_%s.png' % name, img.size)


if __name__ == '__main__':
    main()
