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
                    # is animated in place and needs no step. pair 74 is on windows-assets since 2026-11-18 (O647)

PAIR_MALGRATH = 74  # Malgrath, the Drowned Crown (O637): outfit 3530 and its eight attack effects 5326-5333 (gen_malgrath_boss.py; the lair and the
                    # boss only exist from this pair: install_monster_malgrath_look.py, step `monstermalgrathlook`, bosslair_config.lua,
                    # data/lib/chaos_malgrath_fx.lua). pair 74 is on windows-assets since 2026-11-18 (O647)
PAIR_PIXELLAB = 74  # the 24 PixelLab monsters 3531-3554 (O640, gen_pixellab_monsters.py; install_monster_pixellab_looks.py, step
                    # `monsterpixellablooks`: 24 hunt monsters wear them). pair 74 is on windows-assets since 2026-11-18 (O647)

PAIR_FOOTFX = 75    # the 20 footprint effects 5334-5353 (O649, gen_footprint_fx.py): the effect footprint cosmetics (cosmetics_config.lua `pair = 75`,
                    # data/lib/chaos_footprint_fx_ids.lua `on`) are offered only from this pair. pair 75 is on windows-assets since 2026-11-18 (O649)

PAIR_AWAKENFX = 76  # the awakened spell look kit (O711, gen_awakened_fx.py): 40 effects 5354-5393 and 8 projectiles (blank ids 43 47 52, donor ids
                    # 147-151 rebuilt); data/lib/chaos_awakened_fx.lua answers only from this pair, an awakened cast asks it through data/lib/chaos_awakened_look.lua (O711). On windows-assets

PAIR_AWAKENFX_HEADINGS = 77   # the awakened kit's line and wave heading north, south and west (O711 follow-up, gen_awakened_fx.py): 48 effects
                    # 5394-5441 appended after the kit; data/lib/chaos_awakened_fx.lua answers a heading only from this pair, below it a line or
                    # wave that does not face east keeps the single (awakened_look_config.lua eastOnly). On windows-assets since 2026-11-22 (PAIR_ASSETS 77);
                    # the client sees it once chaosClientPair is 77.

PAIR_DRAWN_WINGS = 78   # the six code-drawn wings of O581 phase 2 (gen_drawn_wings_new.py build-new): outfits 3555-3560 appended to pair 77, wings.xml ids
                    # 122-127. data/lib/chaos_drawn_wings.lua (the store offers) and install_outfits.py (the wings.xml lines) act only from this pair.
                    # On windows-assets (8433cf2, 2026-11-22, owner approved): PAIR_ASSETS 78

# the pair on windows-assets (things/things-1098.tar.xz.partNN) and the md5 of its Tibia.dat. The Windows package ships
# this pair in its own client, so its server records it (prepare_server.sh) and the guarded steps install; the package
# job stops when the archive's dat has another md5. Raise both with every windows-assets pair push (client/MANIFEST.md).
PAIR_WINGS_REDRAWN = 79   # pair 78 with the 117 code-drawn wings looks redrawn (O714 mirrored face-on pair, O714c side views in profile;
                    # gen_drawn_wings.py apply --new --keep-painted). No new ids: no server gate. On windows-assets (c01d1eb, 2026-11-23,
                    # owner approved): PAIR_ASSETS 79

PAIR_DRIVE_MONSTERS = 81   # pair 80 (O724 painted wings sides, O725b effect 3036 recentred; neither on windows-assets) plus ten hunt monster outfits
                    # 3561-3570 from 8-direction character packs (O726, gen_drive_monsters.py; install_monster_drive_looks.py, step
                    # `monsterdrivelooks`: ten hunt monsters wear them). Now 28 outfits 3561-3588 (O728, O729) on top of the 24 O640 looks
                    # redrawn at the game's angle (O728 relook). On windows-assets (2026-11-23, owner approved "pode mandar tudo"): PAIR_ASSETS 81

PAIR_WST_MORE = 82   # pair 81 (or the O734 fixes on it, same counts) plus the effects of the purchased 32 px effect sets not yet in a
                    # pair, appended at 5442.. (O735, gen_wst_more_fx.py; data/lib/chaos_wst_more_fx.lua sends nothing below 82).
                    # Pair 82 = pair 81 + the O734 fixes (fix_pack_fx.py) + this step. Built 2026-11-23, owner approved "pode publicar":
                    # PAIR_ASSETS 82

PAIR_MISSILE_U16 = 83   # the first pair that may carry missile ids above 255 (O737, owner 2026-11-23 "Pode fazer o patch do motor"): pair 81 uses
                    # all 253 one-byte missiles and pair 82 keeps 253. Engine src-patch 0094 and client base patch 0208 send a u16 id to a
                    # client that asked; data/lib/chaos_wide_missiles.lua hands a script an id above 255 only from this pair (C.PAIR), and the
                    # import tool that appends a missile must start at 256 (254 stays CONST_ANI_WEAPONTYPE). No such missile yet.

PAIR_CLIFF = 83     # the 42 cliff pieces of our own drawn by code (O746, gen_cliff_art.py build on pair 82): items 44564-44605, server ids
                    # 48564-48605 (install_cliff_art.py, step `cliffart`); the area planner draws plateaus with them only when the compile
                    # is told this pair (plan field plateaus.pair or compile_plan(client_pair=...)). Rides with PAIR_MISSILE_U16 in pair 83.
                    # Not built yet: waits for the pair 83 build and the owner's approval.

PAIR_WST_WEAR = 83  # the purchased wings, head pieces and capes (O747, client/tools/sprites/gen_wst_wear.py build on the cliff-built pair 82):
                    # 73 drawn wings looks get the pack art in place, Plasma Fly Wings is look 3589 (wings.xml id 128), the 66 head pieces
                    # and 78 capes are looks 3590-3733 (cosmetics of the kinds head / cape, data/lib/chaos_wst_wear.lua M.on); client base
                    # patches 0209 (levitation) and 0210 (the head and cape layer). Rides with PAIR_CLIFF in pair 83, on windows-assets 4be8c608.

PAIR_APEX_MONSTERS = 84   # the ten hunt monsters of levels 2100-2500 (O763, client/tools/sprites/gen_apex_monsters.py build on pair 83): outfits
                    # 3734-3743, our own PixelLab drawings; the monsters spawn in the six O759 hall hunts only through install_apex_hunts.py
                    # (step `apexhunts`, data/monster/apex_hunt_swaps.csv) from this pair. On windows-assets 7de16763 (2026-11-25, owner approved).

PAIR_ASSETS = 84
PAIR_ASSETS_DAT_MD5 = '65bfa6006c9e17c053229f5aaf236895'


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
