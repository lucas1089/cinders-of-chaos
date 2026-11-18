#!/usr/bin/env python3
"""The client pair guard (server/README.md "Client pair guard").

The install steps that write items.otb nodes pointing at client ids of a newer sprite pair (client/MANIFEST.md "Pair 55",
"Pair 56") must not run before the players' client has that pair: the items would show as unknown things. The server
records the pair the SHIPPED client is on, in config.lua:

    chaosClientPair = 54

The owner raises it when a pair ships (client update published). A step that needs pair N reads it with `allows()` and
skips its rows (printing why) while the record is lower than N or missing; it runs normally once the record is N or more.
Nothing is ever removed by a skip, and a second run changes nothing.

usage: python3 -I client_pair.py show SERVER_DIR                 prints `chaosClientPair=N` (N = `missing` without the key)
       python3 -I client_pair.py set SERVER_DIR N [--force] [--dry-run]
              writes the key into SERVER_DIR/config.lua (appended when missing, a trailing comment is kept); N is 1..999;
              lowering the record needs --force (a lower record only holds back steps, but the rule is: it follows the client)
SERVER_DIR is the folder with config.lua; the install tools take the data folder (SERVER_DIR/data) and use its parent.
       python3 -I client_pair.py assets
              prints PAIR_ASSETS, the pair on the private branch windows-assets (the Windows package's client ships it;
              tools/windows/prepare_server.sh records it in the package's own config.lua)
Also: chaos-ctl.sh client-pair [show | set N] on the VPS (README "Client pair guard").
"""
import os
import re
import sys

KEY = 'chaosClientPair'
LINE = re.compile(r'^(?P<lead>[ \t]*%s[ \t]*=[ \t]*)(?P<value>[^\r\n]*?)(?P<tail>[ \t]*--[^\r\n]*)?(?P<eol>\r?)$' % KEY, re.M)
COMMENT = ' -- Cinders of Chaos: the client sprite pair the shipped client is on (server/README.md "Client pair guard")'

# the client pair each guarded install step needs (client/MANIFEST.md); tools import these instead of repeating numbers
PAIR_PICKUPS = 55   # the Ember portal, health and mana globe looks (install_pickups.py)
PAIR_FIST = 56      # the fist weapon redraws and the three new fist weapons (install_fist_weapons.py)
PAIR_W800 = 56      # the 34 weapons above level 800 (install_weapons800.py)
PAIR_RELIC = 58     # the 65 pieces of the five relic sets (install_relic_sets.py)
PAIR_TEMPLE = 60    # the 39 pieces of the temple tileset (install_temple_art.py)
PAIR_ORBS = 63      # the ten orbs that get their own client item (install_orbs.py `look`; the other eight are redrawn in place)
PAIR_RECOLOUR = 69  # the 35 hue shifted monster outfits 3371-3405 (install_monster_recolour.py, step `monsterrecolour`)
PAIR_DONOR = 70     # the 28 polished creature outfits 3406-3433 of the donor client (install_monster_donor_looks.py, step `monsterdonorlooks`)
PAIR_PURCHASED = 71 # the 77 purchased creature outfits 3434-3510 (install_monster_wst_looks.py, step `monsterwstlooks`)
PAIR_FUN = 72       # the 12 fun costumes 3511-3522, the new Dusk Moth 3523 and the round Rune Seal 3524 (install_outfits.py, install_fun_looks.py,
                    # install_auras.py; data/lib/chaos_fun_costumes.lua reads the same record, O566)
PAIR_CREATURE = 73  # the 3 boss outfits 3527-3529 made from creature packs (O608, after O605; install_monster_creature_looks.py, step
                    # `monstercreaturelooks`)
PAIR_SWAP = 73      # the look swaps of O619: 24 monsters leave a look that fails the stock bar for a better one already in the pair (O610 audit;
                    # install_monster_swap_looks.py, step `monsterswaplooks`); no new outfit, so it rides with pair 73
PAIR_DECOR = 74     # the four animated decor flames 44560-44563 (O623, install_decor_flames.py, step `decorflames`); the torch 44544 of pair 60
                    # is animated in place and needs no step. Pair 74 is not built yet, PAIR_ASSETS stays 73 until it is

PAIR_MALGRATH = 74  # Malgrath, the Drowned Crown (O637): outfit 3530 and its eight attack effects 5326-5333 (gen_malgrath_boss.py; the lair and the
                    # boss only exist from this pair: install_monster_malgrath_look.py, step `monstermalgrathlook`, bosslair_config.lua,
                    # data/lib/chaos_malgrath_fx.lua). Pair 74 is not built for real yet, PAIR_ASSETS stays 73 until it is
PAIR_PIXELLAB = 74  # the 24 PixelLab monsters 3531-3554 (O640, gen_pixellab_monsters.py; install_monster_pixellab_looks.py, step
                    # `monsterpixellablooks`: 24 hunt monsters wear them). Pair 74 is not built for real yet, PAIR_ASSETS stays 73 until it is

# the pair on windows-assets (things/things-1098.tar.xz.partNN) and the md5 of its Tibia.dat. The Windows package ships
# this pair in its own client, so its server records it (prepare_server.sh) and the guarded steps install; the package
# job stops when the archive's dat has another md5. Raise both with every windows-assets pair push (client/MANIFEST.md).
PAIR_ASSETS = 73
PAIR_ASSETS_DAT_MD5 = 'd4bc7cef1fa224926c04b07ad35fd6ed'


def parse(text):
    """the recorded pair of a config.lua text, or None when the key is missing or not a whole number"""
    m = LINE.search(text)
    if not m:
        return None
    v = m.group('value').strip()
    return int(v) if re.fullmatch(r'\d{1,4}', v) else None


def server_dir_of(data_dir):
    """SERVER_DIR of a data folder (the folder holding config.lua)"""
    return os.path.dirname(os.path.abspath(data_dir))


def recorded(data_dir):
    """the pair recorded in the config.lua next to the data folder; None when there is no config.lua or no key"""
    path = os.path.join(server_dir_of(data_dir), 'config.lua')
    if not os.path.isfile(path):
        return None
    with open(path, encoding='utf-8', errors='surrogateescape') as f:
        return parse(f.read())


def allows(data_dir, need, what):
    """(ok, message): ok when the recorded pair is `need` or more. The message says what a skip does and how to lift it."""
    have = recorded(data_dir)
    if have is not None and have >= need:
        return True, '%s: client pair %d recorded (needs %d or newer): installing' % (what, have, need)
    return False, 'WARNING: %s skipped, it needs client pair %d or newer and the recorded pair is %s. %s' % (
        what, need, 'missing' if have is None else str(have), lift_hint(need))


def lift_hint(need):
    """how the owner lifts a skip once the client with pair `need` is published"""
    return ('Once the client update with pair %d is published: admin app, or chaos-ctl.sh client-pair set %d, or '
            'python3 -I server/tools/client_pair.py set SERVER_DIR %d (config.lua %s; README "Client pair guard").'
            % (need, need, need, KEY))


def patch(text, n):
    """(new text, old value text or None when the key was missing)"""
    m = LINE.search(text)
    if not m:
        sep = '' if text.endswith('\n') or text == '' else '\n'
        return text + sep + '%s = %d%s\n' % (KEY, n, COMMENT), None
    new = m.group('lead') + str(n) + (m.group('tail') or '') + m.group('eol')
    return text[:m.start()] + new + text[m.end():], m.group('value').strip()


def main(argv):
    args = list(argv)
    dry = '--dry-run' in args
    force = '--force' in args
    args = [a for a in args if a not in ('--dry-run', '--force')]
    if args == ['assets']:
        print(PAIR_ASSETS)
        return 0
    if args == ['assets-md5']:
        print(PAIR_ASSETS_DAT_MD5)
        return 0
    if len(args) < 2 or args[0] not in ('show', 'set') or (args[0] == 'show') != (len(args) == 2):
        print(__doc__)
        return 1
    path = os.path.join(args[1], 'config.lua')
    if not os.path.isfile(path):
        print('%s: no config.lua' % args[1])
        return 1
    with open(path, encoding='utf-8', errors='surrogateescape', newline='') as f:
        text = f.read()
    have = parse(text)
    if args[0] == 'show':
        print('%s=%s' % (KEY, 'missing' if have is None else have))
        return 0
    if len(args) != 3 or not re.fullmatch(r'\d{1,3}', args[2]) or not 1 <= int(args[2]) <= 999:
        print('client pair: a whole number from 1 to 999')
        return 1
    n = int(args[2])
    if have is not None and n < have and not force:
        print('config.lua: %s is %d, %d is lower: refused (--force to lower it)' % (KEY, have, n))
        return 1
    new, old = patch(text, n)
    if new == text:
        print('config.lua: %s = %d already' % (KEY, n))
        return 0
    if not dry:
        with open(path, 'w', encoding='utf-8', errors='surrogateescape', newline='') as f:
            f.write(new)
    print('config.lua: %s %s -> %d%s' % (KEY, old if old is not None else '(missing)', n, ' (dry run)' if dry else ''))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
