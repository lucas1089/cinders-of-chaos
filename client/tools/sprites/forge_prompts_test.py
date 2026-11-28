#!/usr/bin/env python3
"""Test of forge_prompts.py (O781): python3 -I client/tools/sprites/forge_prompts_test.py

Every recipe carries the view, the outline, hard edges and the transparent background, names the post steps that exist
in this folder, the theme words of style_palettes.json when a theme is named, the grid and the four wall pieces; no
recipe holds a name tools/ci/check_names.py refuses; the CLI prints the three lines. Text only, no service."""
import contextlib
import io
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import forge_prompts as F  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))


def recipes():
    yield F.item('an iron lantern')
    yield F.item('an iron lantern', 'rimewraith')
    yield F.pack('marsh herbs', 2)
    yield F.pack('marsh herbs', 3, 'blightfang')
    yield F.walls('basalt blocks', 'cinderwrought')
    for k in F.KINDS:
        yield F.walk('a grave keeper', k)


def test_rules_in_every_recipe():
    for r in recipes():
        for word in ('oblique', '1 px dark outline', 'hard edges', 'transparent background'):
            assert word in r['prompt'], (word, r['prompt'])
        for tool in re.findall(r'([a-z_]+\.py)', r['post']):
            assert os.path.exists(os.path.join(HERE, tool)), tool


def test_theme_grid_and_walls():
    import style_check
    words = style_check.load_palettes()['themes']['rimewraith']['words']
    assert words in F.item('x', 'rimewraith')['prompt']
    assert '3 x 3 sheet of 9' in F.pack('x', 3)['prompt']
    assert '2 x 2 sheet of 4' in F.pack('x', 2)['prompt']
    w = F.walls('basalt')['prompt']
    for k, _ in F.WALL_PIECES:
        assert k + ':' in w


def test_no_refused_names():
    sys.path.insert(0, os.path.join(ROOT, 'tools', 'ci'))
    import check_names
    text = '\n'.join(r['prompt'] + r['settings'] + r['post'] for r in recipes())
    assert not check_names.name_hit(text), check_names.name_hit(text)


def test_cli():
    with contextlib.redirect_stdout(io.StringIO()) as buf:
        assert F.main(['walls', 'cracked basalt', '--theme', 'cinderwrought']) == 0
        assert F.main(['walk', 'a moth', '--kind', 'thing']) == 0
    out = buf.getvalue()
    assert out.count('prompt:') == 2 and 'post:' in out
    with contextlib.redirect_stdout(io.StringIO()):
        try:
            F.main(['--help'])
        except SystemExit as e:
            assert e.code == 0


def main():
    tests = [v for k, v in sorted(globals().items()) if k.startswith('test_')]
    for t in tests:
        t()
    print('forge_prompts_test: %d tests OK' % len(tests))


if __name__ == '__main__':
    main()
