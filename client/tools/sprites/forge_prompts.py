#!/usr/bin/env python3
"""Prompt recipes for AI drops of items, packs, wall sets and walks, in our words (O781; docs/SPRITE_FORGE.md).

Text only: this tool calls no service and spends no credit. It prints the description to paste into the AI pixel art
service we use (PixelLab) or a local model, plus the settings and the post steps that follow, so every drop of one kind
is asked the same way and lands in the shape our tools expect:

    item    one item filling a 32 px cell                 -> pixel_grid.py clean, item_post.py, style_check.py
    pack    K x K related items, transparent gutters       -> pixel_grid.py clean, sheet_cut.py pack, item_post.py
    walls   a 2 x 2 wall set: post, north, east, corner    -> pixel_grid.py clean, sheet_cut.py walls / room
    walk    one creature, 4 directions, standing and walk  -> gen_pixellab_monsters.py / walk_sheet.py, oblique_lean.py

    python3 -I forge_prompts.py item "a soot-black iron lantern with a cold blue flame" [--theme rimewraith]
    python3 -I forge_prompts.py pack "healing herbs of the ash marsh" --grid 3 [--theme ...]
    python3 -I forge_prompts.py walls "cracked basalt blocks with ember seams" [--theme cinderwrought]
    python3 -I forge_prompts.py walk "a hunched grave keeper with a lantern on a pole" [--kind man|beast|thing]

Rules the recipes carry (docs/SPRITE_STYLE.md): our view (top-down oblique, height drawn up and to the left, lit from the
top left), a 1 px dark outline, hard edges with no soft alpha, a transparent background, flat shading in few colours,
no text, no frame, and the theme words of style_palettes.json when a theme is named. Our own words only: never the name of
another game, server or client, never a picture of anyone else as a source (docs/AI_TOOLS.md).
"""
import argparse
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

VIEW = 'top-down oblique view, height drawn up and to the left, lit from the top left, shade on the bottom right'
STYLE = ('pixel art, 1 px dark outline, hard edges, no anti-aliasing against the background, flat shading in few '
         'colours, transparent background, no text, no frame, no shadow on the ground')
KINDS = {
    'man': 'standing at the angle of the view, feet right of the head, adult proportions',
    'beast': 'on all fours, body along the view, head to the front',
    'thing': 'a floating or rolling thing, its base at the bottom of the frame',
}
WALL_PIECES = (('post', 'a short square post, one tile'),
               ('north', 'a straight run along the north edge of a tile'),
               ('east', 'a straight run along the east edge of a tile'),
               ('corner', 'an L-shaped join of the north and east runs'))


def theme_words(theme):
    if not theme:
        return ''
    import style_check
    t = style_check.load_palettes()['themes'][theme]
    return ', colours of %s' % t['words']


def item(desc, theme=None):
    return {'prompt': '%s, one inventory item filling the frame, %s, %s%s' % (desc, VIEW, STYLE, theme_words(theme)),
            'settings': 'size 32 x 32 (or 64 x 64 for a painted render, cleaned to 32), transparent background',
            'post': 'pixel_grid.py clean -> item_post.py -> style_check.py check -> sprite_quality.py check --kind item'}


def pack(desc, grid=3, theme=None):
    n = grid * grid
    return {'prompt': '%s: a %d x %d sheet of %d different related items, one item centred in each cell, empty '
                      'transparent gaps between cells, %s, %s%s' % (desc, grid, grid, n, VIEW, STYLE, theme_words(theme)),
            'settings': 'size %d x %d (cells of 32) or a painted render of whole cells' % (32 * grid, 32 * grid),
            'post': 'pixel_grid.py clean -> sheet_cut.py pack --anchor item -> item_post.py -> style_check.py check'}


def walls(desc, theme=None):
    pieces = '; '.join('%s: %s %s' % (k, desc, w) for k, w in WALL_PIECES)
    return {'prompt': 'a matching wall set of %s in a 2 x 2 sheet, top row post and north run, bottom row east run and '
                      'corner; %s; every piece stands on the bottom-right tile of its cell; %s, %s%s' % (
                          desc, pieces, VIEW, STYLE, theme_words(theme)),
            'settings': 'size 128 x 128 (cells of 64: one tile and the height above it)',
            'post': 'pixel_grid.py clean -> sheet_cut.py walls -> sheet_cut.py room (preview) -> style_check.py check'}


def walk(desc, kind='man', theme=None):
    return {'prompt': '%s, %s, %s, %s%s' % (desc, KINDS[kind], VIEW, STYLE, theme_words(theme)),
            'settings': 'character, 4 directions, view oblique, a standing picture and a walk of 8 frames per '
                        'direction, size 52 for a 2 x 2 look (the O618 recipe)',
            'post': 'gen_pixellab_monsters.py drop-import (PixelLab folders) or walk_sheet.py engine -> walk_sheet.py '
                    'fit -> oblique_lean.py lean -> sprite_quality.py check --kind creature'}


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__.split('\n')[0],
                                formatter_class=argparse.RawDescriptionHelpFormatter, epilog=__doc__)
    sub = p.add_subparsers(dest='cmd', required=True)
    for name in ('item', 'pack', 'walls', 'walk'):
        s = sub.add_parser(name)
        s.add_argument('desc')
        s.add_argument('--theme')
        if name == 'pack':
            s.add_argument('--grid', type=int, default=3, choices=(2, 3))
        if name == 'walk':
            s.add_argument('--kind', default='man', choices=sorted(KINDS))
    args = p.parse_args(argv)
    if args.cmd == 'pack':
        r = pack(args.desc, args.grid, args.theme)
    elif args.cmd == 'walk':
        r = walk(args.desc, args.kind, args.theme)
    else:
        r = {'item': item, 'walls': walls}[args.cmd](args.desc, args.theme)
    for k in ('prompt', 'settings', 'post'):
        print('%-8s %s' % (k + ':', r[k]))
    return 0


if __name__ == '__main__':
    sys.exit(main())
