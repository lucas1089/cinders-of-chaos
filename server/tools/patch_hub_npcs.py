#!/usr/bin/env python3
"""Clear the hub's NPC stalls of the base server's NPCs (server/README.md "Hub NPC booths"), idempotent.

usage: python3 -I server/tools/patch_hub_npcs.py DATA_DIR [--spawn FILE] [--config FILE] [--dry-run]

Owner 2026-10-22: the Chaos NPCs of the main city stand in the stalls of the hub (the market of Cinderhold's teleport
room), "take the current ones out and put ours there". data/scripts/chaos/npc_booths_config.lua lists the stalls: the
tile each NPC stands on. Every <npc> entry of the map's spawn file (DATA_DIR/world/<mapName>-spawn.xml, mapName read
from DATA_DIR/../config.lua, or --spawn) that stands on one of those tiles (center + offset; its own z) is removed, by
position, so the base NPCs' names never appear here; a <spawn> block left with no creature goes too. Nothing else of
the file changes (bytes, line endings). The NPCs keep their files and their other spawns elsewhere in the world. The
Chaos NPCs are put in the stalls at startup (npc_booths.lua, npc_place.lua), not through the spawn file.
A second run changes nothing. --dry-run lists what would go and writes nothing. Exit 0, or 1 when the spawn file or
the config cannot be read. Install step `hubnpcs` (after npcnames, before poi). Test: tools/patch_hub_npcs_test.py.
"""
import os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
SERVER = os.path.dirname(HERE)
sys.path.insert(0, HERE)
CONFIG = os.path.join(SERVER, 'data', 'scripts', 'chaos', 'npc_booths_config.lua')

SPAWN_RE = re.compile(r'([ \t]*)<spawn\b([^>]*)>(.*?)</spawn>[ \t]*(\r?\n)?', re.S)
NPC_RE = re.compile(r'([ \t]*)<npc\b([^>]*?)/>[ \t]*(\r?\n)?')
CREATURE_RE = re.compile(r'<(npc|monster)\b')
ATTR_RE = re.compile(r'(\w+)\s*=\s*"([^"]*)"')


class HubError(Exception):
    pass


def booth_tiles(cfg):
    """{(x, y, z)} of the stalls (every one, with or without a Chaos NPC: each is cleared)"""
    if not cfg.get('enabled'):
        return set()
    return {(int(b['x']), int(b['y']), int(b['z'])) for b in cfg.get('booths') or ()}


def _int(attrs, key, default=None):
    try:
        return int(attrs[key])
    except (KeyError, ValueError):
        return default


def patch(text, tiles):
    """(new text, [(name, x, y, z)] removed)"""
    removed = []

    def one_spawn(m):
        attrs = dict(ATTR_RE.findall(m.group(2)))
        cx, cy, cz = _int(attrs, 'centerx'), _int(attrs, 'centery'), _int(attrs, 'centerz')
        if cx is None or cy is None or cz is None:
            return m.group(0)
        hit = []

        def one_npc(n):
            a = dict(ATTR_RE.findall(n.group(2)))
            dx, dy = _int(a, 'x'), _int(a, 'y')
            if dx is None or dy is None:
                return n.group(0)
            p = (cx + dx, cy + dy, _int(a, 'z', cz))
            if p not in tiles:
                return n.group(0)
            hit.append((a.get('name', '?'),) + p)
            return ''

        body = NPC_RE.sub(one_npc, m.group(3))
        if not hit:
            return m.group(0)
        removed.extend(hit)
        if not CREATURE_RE.search(body):
            return ''
        s0, whole = m.start(0), m.group(0)
        return whole[:m.start(3) - s0] + body + whole[m.end(3) - s0:]

    return SPAWN_RE.sub(one_spawn, text), removed


def spawn_path(data_dir):
    import late_game
    cfg = os.path.join(data_dir, '..', 'config.lua')
    if not os.path.isfile(cfg):
        raise HubError('%s: no config.lua, pass --spawn' % os.path.normpath(cfg))
    name = late_game.map_name(open(cfg, encoding='utf-8', errors='surrogateescape').read())
    if not name:
        raise HubError('%s: mapName not found, pass --spawn' % os.path.normpath(cfg))
    return os.path.join(data_dir, 'world', name + '-spawn.xml')


def run(data_dir, spawn=None, config=CONFIG, dry=False, log=print):
    import install_content_areas as IC
    tiles = booth_tiles(IC.load_config(config))
    path = spawn or spawn_path(data_dir)
    if not os.path.isfile(path):
        raise HubError('no spawn file %s' % path)
    with open(path, encoding='utf-8', errors='surrogateescape', newline='') as f:
        text = f.read()
    new, removed = patch(text, tiles)
    for name, x, y, z in removed:
        # the base names are not printed (they may be old-world names before the npcnames step)
        log('hub stall %d,%d,%d: a base NPC entry removed' % (x, y, z))
    if new != text and not dry:
        tmp = path + '.tmp'
        with open(tmp, 'w', encoding='utf-8', errors='surrogateescape', newline='') as f:
            f.write(new)
        os.replace(tmp, path)
    log('%s: %d stall(s), %d base NPC entr%s removed%s' % (path, len(tiles), len(removed),
                                                            'y' if len(removed) == 1 else 'ies',
                                                            ' (dry run)' if dry and removed else ''))
    return removed


def main(argv):
    args, opts, dry = [], {}, False
    it = iter(argv)
    for a in it:
        if a == '--dry-run':
            dry = True
        elif a in ('--spawn', '--config'):
            opts[a] = next(it, None)
        elif a.startswith('-'):
            print(__doc__)
            return 1
        else:
            args.append(a)
    if len(args) != 1 or None in opts.values():
        print(__doc__)
        return 1
    try:
        run(args[0], spawn=opts.get('--spawn'), config=opts.get('--config', CONFIG), dry=dry)
    except (HubError, OSError) as e:
        print('patch_hub_npcs: %s' % e)
        return 1
    except Exception as e:  # the config's Lua dump (install_content_areas.InstallError)
        print('patch_hub_npcs: %s' % e)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
