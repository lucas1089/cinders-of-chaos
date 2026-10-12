#!/usr/bin/env python3
"""Speech-bubble tails of game_npctalk (the NPC dialogue window drawn over the map).
  tail_down.png  22x12: points down at the NPC from under the bubble; its top 3 rows are the bubble's fill, so it covers
                 the gold rim of /images/chaos/panel_highlight where it joins (the window is a ChaosPanelHighlight).
  tail_up.png    the same, flipped: the bubble sits under the NPC when there is no room above it.
python3 -I client/tools/gen_npctalk_art.py   (writes into client/overlay/modules/game_npctalk/images/)"""
import os
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, '..', 'overlay', 'modules', 'game_npctalk', 'images')
W, H, JOIN = 22, 12, 3

# the colours of panel_highlight.png: outer black line, gold rim, bronze inner line, dark fill
BLACK = (3, 2, 2, 255)
GOLD = (214, 169, 69, 255)
BRONZE = (113, 81, 37, 255)
FILL = (30, 21, 23, 255)


def tail_down():
    im = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    px = im.load()
    half = W / 2.0
    for y in range(H):
        if y < JOIN:
            # the joint: the bubble's fill over its bottom rim, edged like the rim's sides
            for x in range(1, W - 1):
                px[x, y] = FILL
            px[0, y], px[W - 1, y] = BLACK, BLACK
            px[1, y], px[W - 2, y] = GOLD, GOLD
            continue
        # a triangle narrowing from the full width to a 2 px point at the bottom
        t = (y - JOIN) / float(H - JOIN - 1)
        w = max(1.0, half * (1.0 - t))
        left, right = int(round(half - w)), int(round(half + w)) - 1
        for x in range(left, right + 1):
            px[x, y] = FILL
        for x in (left, right):
            px[x, y] = BLACK
        if right - left >= 3:
            px[left + 1, y], px[right - 1, y] = GOLD, GOLD
        if right - left >= 5:
            px[left + 2, y], px[right - 2, y] = BRONZE, BRONZE
        if y == H - 1:
            for x in range(left, right + 1):
                px[x, y] = GOLD if left < x < right else BLACK
    return im


def main():
    os.makedirs(OUT, exist_ok=True)
    down = tail_down()
    down.save(os.path.join(OUT, 'tail_down.png'))
    down.transpose(Image.FLIP_TOP_BOTTOM).save(os.path.join(OUT, 'tail_up.png'))
    print('wrote', os.path.normpath(OUT))


if __name__ == '__main__':
    main()
