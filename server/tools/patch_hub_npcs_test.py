#!/usr/bin/env python3
"""python3 -I server/tools/patch_hub_npcs_test.py : patch_hub_npcs.py on a synthetic spawn file.

An NPC on a stall tile goes (by center + offset and its own z), its emptied <spawn> block goes too; a block that keeps a
creature stays with only that line removed; NPCs next to a stall, on another floor or of a stall-less block stay; CRLF
line endings and every other byte are kept; a dry run writes nothing; a second run changes nothing. The real config:
16 stalls on two rows, no tile twice, every Chaos NPC named once. No base server needed (luajit or lua5.3)."""
import os, shutil, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import patch_hub_npcs as T  # noqa: E402
import install_content_areas as IC  # noqa: E402

failed = 0


def check(ok, what):
    global failed
    if not ok:
        failed += 1
        print('FAIL: %s' % what)


CONFIG = """return {enabled = true, town = 2, temple = {x = 1, y = 1, z = 7},
	booths = {{x = 100, y = 50, z = 7, npc = "A"}, {x = 106, y = 50, z = 7, npc = false}, {x = 100, y = 56, z = 7, npc = "B"}}}
"""

SPAWN = ('<?xml version="1.0"?>\r\n<spawns>\r\n'
         '\t<spawn centerx="100" centery="50" centerz="7" radius="1">\r\n'
         '\t\t<npc name="Old One" x="0" y="0" z="7" spawntime="120" />\r\n'
         '\t</spawn>\r\n'
         '\t<spawn centerx="107" centery="50" centerz="7" radius="1">\r\n'
         '\t\t<npc name="Old Two" x="-1" y="0" z="7" spawntime="120" />\r\n'
         '\t</spawn>\r\n'
         '\t<spawn centerx="100" centery="55" centerz="7" radius="3">\r\n'
         '\t\t<monster name="Rat" x="2" y="0" z="7" spawntime="60" />\r\n'
         '\t\t<npc name="Old Three" x="0" y="1" z="7" spawntime="120" />\r\n'
         '\t</spawn>\r\n'
         '\t<spawn centerx="101" centery="50" centerz="7" radius="1">\r\n'
         '\t\t<npc name="Neighbour" x="0" y="0" z="7" spawntime="120" />\r\n'
         '\t</spawn>\r\n'
         '\t<spawn centerx="100" centery="50" centerz="6" radius="1">\r\n'
         '\t\t<npc name="Upstairs" x="0" y="0" z="6" spawntime="120" />\r\n'
         '\t</spawn>\r\n'
         '</spawns>\r\n')

WANT = ('<?xml version="1.0"?>\r\n<spawns>\r\n'
        '\t<spawn centerx="100" centery="55" centerz="7" radius="3">\r\n'
        '\t\t<monster name="Rat" x="2" y="0" z="7" spawntime="60" />\r\n'
        '\t</spawn>\r\n'
        '\t<spawn centerx="101" centery="50" centerz="7" radius="1">\r\n'
        '\t\t<npc name="Neighbour" x="0" y="0" z="7" spawntime="120" />\r\n'
        '\t</spawn>\r\n'
        '\t<spawn centerx="100" centery="50" centerz="6" radius="1">\r\n'
        '\t\t<npc name="Upstairs" x="0" y="0" z="6" spawntime="120" />\r\n'
        '\t</spawn>\r\n'
        '</spawns>\r\n')


def main():
    root = tempfile.mkdtemp(prefix='hubnpcs_')
    try:
        data = os.path.join(root, 'data')
        os.makedirs(os.path.join(data, 'world'))
        open(os.path.join(root, 'config.lua'), 'w').write('mapName = "town"\n')
        cfg = os.path.join(root, 'booths.lua')
        open(cfg, 'w').write(CONFIG)
        sp = os.path.join(data, 'world', 'town-spawn.xml')
        open(sp, 'wb').write(SPAWN.encode())
        quiet = lambda *a: None
        removed = T.run(data, config=cfg, dry=True, log=quiet)
        check(len(removed) == 3 and open(sp, 'rb').read() == SPAWN.encode(), 'a dry run writes nothing: %s' % removed)
        removed = T.run(data, config=cfg, log=quiet)
        check(sorted(r[1:] for r in removed) == [(100, 50, 7), (100, 56, 7), (106, 50, 7)],
              'the three stall NPCs go: %s' % removed)
        got = open(sp, 'rb').read().decode()
        check(got == WANT, 'the file as wanted:\n%r' % got)
        check(T.run(data, config=cfg, log=quiet) == [] and open(sp, 'rb').read().decode() == WANT,
              'a second run changes nothing')
        check(T.main([data, '--config', cfg]) == 0, 'the command line runs')
        check(T.main([os.path.join(root, 'none', 'data'), '--config', cfg]) == 1, 'no config.lua: exit 1')

        real = IC.load_config(T.CONFIG)
        tiles = T.booth_tiles(real)
        check(len(tiles) == len(real['booths']) == 16, 'the real config: 16 stalls, no tile twice')
        check({t[1] for t in tiles} == {32230, 32236} and {t[2] for t in tiles} == {7}, 'two rows on floor 7')
        names = [b['npc'] for b in real['booths'] if b['npc']]
        check(len(names) == len(set(names)), 'every Chaos NPC in one stall: %s' % names)
        for need in ('Ascendant Oracle', 'Keeper of Trials', 'Archivist Maelis', 'Archivist Odrenna', 'Warden Ysolde', 'Loot Buyer'):
            check(need in names, '%s has a stall' % need)
    finally:
        shutil.rmtree(root, ignore_errors=True)
    print('patch_hub_npcs_test: %s' % ('ok' if not failed else '%d failed' % failed))
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())
