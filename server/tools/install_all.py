#!/usr/bin/env python3
"""Install everything of Cinders of Chaos into a stock base server folder, in the order of server/README.md "Install".

usage: python3 -I server/tools/install_all.py SERVER_DIR [--dry-run] [--no-sql] [--skip STEP,...] [--only STEP,...]
                                              [--db NAME] [--db-host HOST] [--db-port PORT] [--db-user USER]
                                              [--mysql PATH] [--quiet | --verbose]

SERVER_DIR is the base server folder: the one with config.lua and data/ (only the towns and worldtexts steps read and
change the map .otbm: the names of its towns, the texts of its signs and books).

Steps, in this order (each one is idempotent on its own; a second run of the whole script changes nothing):
  files        copy server/data from this repo into SERVER_DIR/data: scripts/chaos/**, lib/chaos_*.lua,
               monster/monsters/chaos/**/*.xml, monster/lua/chaos/**/*.lua, spells/chaos/** (the source folder
               register_spells.py reads) and patchnotes/*.md (+ index.txt). Only new or different files are written;
               files in SERVER_DIR/data/scripts/chaos that the repo no longer has are listed, never deleted.
  lib          data/lib/lib.lua loads chaos_unique_items.lua (data/items/README.md, "Install" 1)
  monsternames tools/patch_base_monster_names.py Chaos names of the base monsters (data/monster/base_monster_names.csv,
               keyed by the sha256 of the old name): registrations, monster files, spawns, raids, scripts, a few outfit and
               mount names (README "Base monster names"; before lategame and spawns, which name monsters by the new names)
  vocations    tools/add_vocations.py            the classes (README "Install" 5b, docs/CLASSES.md)
               tools/patch_base_classes.py       the base server's vocation checks (NPCs, quests, familiars, ...) know
                                                 the classes (README "Install" 5b, docs/CLASSES.md "Base scripts")
  events       tools/patch_base_events.py        experience / loot / siege / login hooks (README "Install" 4)
               tools/patch_season_events.py      season isolation hooks (when the tool exists)
               tools/patch_help_itemlinks.py     no item links in the Help channel (when the tool exists)
               tools/patch_report_chat.py        public channel lines for player reports (when the tool exists)
               tools/patch_market.py             the stock market item opens the Chaos market (when the tool exists)
               tools/patch_base_npcs.py          the base NPC library: replies as lists of lines, blessing cost tags
  basecrafting tools/patch_base_crafting.py       the base crafting script (opcode 91, tables 38820-38826): table check,
                                                 one pending craft per player, gold and materials taken before the item
                                                 is made, refund when it cannot be added (README "Base crafting script")
  basecraftingui tools/patch_base_crafting_ui.py  the base crafting script talks to the client's Crafting Table window:
                                                 messages instead of popups, material names, item tooltips (README
                                                 "Crafting Table window"; needs the basecrafting step first)
  basecraftingbonus tools/patch_base_crafting_bonus.py  crafted equipment rolls a Chaos rarity and item level, potions
                                                 and runes may give extra pieces, by the crafting skill (README
                                                 "Crafting bonus"; needs basecrafting and basecraftingui first)
  weapons      tools/two_handed.py               two-handed attack speed (README "Weapon styles")
  lategame     tools/late_game.py                experience stages in config.lua + late game spawns (README "Install" 5)
  crafting     tools/install_crafting.py         crafting orb items and the reroll guard (README "Crafting")
  orbs         tools/install_orbs.py             crafting orbs v2 items, orb renames in the base files (README "Crafting orbs v2")
  darktiles    tools/install_dark_tiles.py       the dark tile set in items.otb / items.xml (README "Dark tile set")
  outfits      tools/install_outfits.py          the Ninja / Samurai class outfits in outfits.xml (docs/CLASSES.md)
  auras        tools/install_auras.py            the Chaos auras in auras.xml (data/XML/chaos_auras.csv, written by
               client/tools/sprites/import_vfx.py; spells/README_FX.md "Animated pack effects")
  donoritems   tools/install_donor_items.py      the items imported from donor B art in items.otb / items.xml (server ids
               40000..; nothing to do while data/items/donor_items.csv is absent or empty)
  packitems    tools/install_pack_items.py       the pack items (new looks of the rune-stone orbs and ore pieces, creature
               products, food, corpses, trees, grounds, water, shores, lake objects) in items.otb / items.xml and the
               products in Grimgan's shop (README "Pack items and monsters")
  fistweapons  tools/install_fist_weapons.py     the Monk line's fist weapons in items.otb / items.xml, their Monk-only equip
               entries in movements.xml and the weapon dealers' / Grimgan's shops (README "Fist weapons")
  gems         tools/install_gems.py             the gems and the Orb of Sockets in items.otb / items.xml (README "Gems and sockets")
  salvage      tools/install_salvage.py          the salvage Rune Shard in items.otb / items.xml (README "Salvage")
  omens        tools/install_omens.py            the Omen Fragment and Omen Key in items.otb / items.xml (README "Rifts", Omens)
  ascended     tools/install_ascended.py         the Ascended Shards, Sigil and Relic in items.otb / items.xml (README "Ascended
               Omens and the Cinderheart")
  factions     tools/install_factions.py         the faction tokens in items.otb / items.xml and the four faction NPCs in data/npc
               (README "Factions")
  pouches      tools/install_pouches.py          the store pouches in items.otb / items.xml and their move hook in Player:onMoveItem
               (README "Store pouches")
  depot        tools/patch_base_depot.py         depot tabs: the depot boxes pickupable in items.otb and named "depot tab n" with
               100 slots in items.xml, the locker hook and the move hook in Player:onMoveItem (README "Depot tabs")
  charms       tools/install_charms.py           the charms and the charm shard in items.otb / items.xml (README "Charms")
  professions  tools/install_professions.py      the profession materials and gathering nodes in items.otb / items.xml, the
               Material Broker in data/npc and the hooks in the stock pick / sickle / skinning / fishing scripts
               (README "Professions")
  gamble       tools/install_gamble.py           the Gambler NPC in data/npc (README "The Gambler")
  supports     tools/install_supports.py         the spell support runes in items.otb / items.xml and the spell-library hook (scripts/chaos/SUPPORTS.md)
  monsters     tools/register_monsters.py        every folder under data/monster/monsters/chaos (world bosses, goblin, ...)
  spawns       tools/patch_base_spawns.py        spawn density and respawn of the loaded map's spawn file from
               tools/spawn_tuning.json: dead monster lines of monsters.xml, glitched spawntimes, the 300-600 band's
               respawn, entries on blocking tiles moved, spawns added in thin areas (README "Spawn density and
               respawn"; after monsters, which it reads)
  spells       tools/register_spells.py          the Chaos spells (README "Install" 3)
               CLASS HOOK: every tools/install_class_*.py (sorted), called as `install_class_X.py DATA_DIR [--dry-run]`;
               the class lines (Necromancer / Monk / Templar) put their own spell or data installers there
               tools/rename_spells.py --sql      Chaos names of the stock spells and runes (+ the player_spells UPDATEs)
  archery      tools/patch_base_archery.py       bows and crossbows fire without ammunition (attack, hit chance and missile of
               their band), quivers become off-hand equipment (items.xml, items.otb, movements.xml; engine src-patch
               0023), the base slot tables know the second ring slot, the might rings are marked (one at a time), the base
               rarity script keeps both rings of a ring slot swap and clears a hand the base two-handed swap emptied,
               the base two-handed swap keeps a quiver, arrows and bolts leave
               loot, shops and quest rewards, the conjure spells go (README "Infinite arrows and quivers"; after
               vocations, which still reads the launchers' ammo type, and after spells)
  itemnames    tools/patch_base_item_names.py    Chaos names of the base items with names of another world, by id
               (data/items/base_item_names.csv): items.xml, the monsters' loot by old name becomes loot by
               id, other mentions in the base data renamed (README "Base item names"; after archery)
  towns        tools/patch_base_towns.py         Chaos names of the map's towns by town id (tools/base_towns.csv), in the
               towns node of the .otbm; <map>.otbm.bak keeps the original (README "Town names")
  npcnames     tools/patch_base_npc_names.py     Chaos names of the base NPCs (data/npc/base_npc_names.csv, keyed by the
               sha256 of the old name): the NPC files and their shown names, the NPC spawn entries, Game.createNpc
               names (README "Base NPC names"; after towns, monsternames and itemnames)
  worldtexts   tools/patch_base_texts.py         the old world's names in NPC dialogue and keywords, travel, the quest log,
               raids, achievements, item descriptions, script messages and the map's signs and books
               (data/npc/base_world_names.csv + the NPC and monster lists; README "Base world texts"; after npcnames)
  servername   tools/patch_base_server_name.py   the base server's own name in whole strings of its data: the welcome text
               over the first temple, the web login service's console banner (tools/base_server_texts.csv, keyed by
               the sha256 of the old string; README "Server name"; after worldtexts)
  houses       tools/patch_base_houses.py        Chaos street names of the houses by house id (tools/base_house_names.csv)
               in the map's house file (README "Base houses")
  poi          tools/gen_poi.py                  the points of interest of the map markers (temples, depots, crafting tables,
               service NPCs, hunting areas, boss places) from the installed map, items, NPCs and spawn data into
               data/chaos_poi.lua (README "Map markers"; after towns, npcnames and worldtexts, which rename what it reads)
  autoloot     data/talkactions/talkactions.xml: the stock XML "!autoloot" line is commented out, so autoloot.lua's own
               talkaction runs and the window refreshes (README "Install" 7)
  commands     tools/install_commands.py         the players' spoken "!" commands of the base server commented out (every one is in the
               client's menu now; README "Player commands: the menu")
  autosave     tools/patch_base_save.py          the hourly autosave runs Game.saveIncremental (engine src-patch 0026: players
               in small batches over several ticks, only the changed houses) and keeps the game state (a closed server
               stays closed); the warnings stay; the logout writes the outfit columns and the skill history row only
               when they changed (README "Autosave in steps"; after commands, which also edits login.lua)
  stalls       tools/patch_base_stalls.py        the base expedition scripts announce a new NPC or boss to the players on its
               island from the list of players online instead of a scan of every tile of the island (627,000 tiles,
               0.6-0.9 s of frozen game loop at each spawn time; same players, sounds, marks and broadcasts); the base
               upgrade-slot check keeps the slots it parsed per item description and runs at login, at once on an
               equip move and once a second per player in 12 groups instead of every 100 ms, and adds and
               removes each slot bonus under one condition id, forgetting the bonus of an emptied slot (README
               "Game loop stalls"); the base extended opcode script reads and pushes the ancestral points at most
               once every 2 s per player instead of a database read for every request a client sends (README
               "Stress test")
  bossrooms    tools/patch_base_bossrooms.py     the base lever boss rooms and the step-in miniboss rooms (several in one file):
               the lever (or entry tile) is locked while a group is inside, a time limit (the room's own kick time, at
               most 30 minutes) with warnings and a countdown, everyone out to the room's exit and its monsters removed
               at the end, an empty room frees up after 2 minutes, a login inside a closed room goes to its exit (README
               "Instance limits")
  eventrooms   tools/patch_base_eventrooms.py    the base soul pit and tower defence as boss rooms: locked while a group's run is on
               (the tower defence's entrance tile sends a refused player back), a time limit of their own (soul pit 15,
               tower defence 20 minutes) with warnings, everyone out and the monsters removed at the end, the script's
               own state reset, its own end (completed, won, lost) closes the room (README "Instance limits")
  dungeonentry tools/patch_base_dungeon.py       the base dungeon entry tile (step-in, item 26702) opens the Chaos dungeon
               window instead of the base modal window, so every dungeon entry goes through the queue (one run per
               box, the time cap and warnings); the modal run with its box scan and fixed timer never starts (README
               "Instance limits")
  sql          server/sql/chaos.sql, then every other server/sql/*.sql (sorted), then the rename_spells UPDATEs, against
               the game database (CREATE TABLE IF NOT EXISTS / plain UPDATEs, safe to repeat)

--dry-run runs every step on a temporary copy of SERVER_DIR (config.lua and data/ without *.otbm, logs/, reports/) and
reports what would change; SERVER_DIR and the database are not touched (the SQL step only lists its files; the towns
and worldtexts steps read the real map and only report).
--quiet prints only the step lines and the changed files, --verbose every line of the tools' own output (else 15 per step).

Database: name, host, port and user default to config.lua's mysqlDatabase / mysqlHost / mysqlPort / mysqlUser. A value
written as os.getenv("NAME") or "default" (server/tools/prod_config.py writes them that way) is read from the environment.
The password comes from the environment variable CHAOS_DB_PASS, else MYSQL_PWD, else config.lua's mysqlPass. It is handed to
the mysql client through a temporary option file (mode 0600), never on the command line.

The report lists, per step, the files that changed (compared by content) and the tool's own output. Exit status 0 when
every step succeeded, 1 otherwise (the run stops at the first failed step: later steps build on earlier ones).
"""
import hashlib
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO_SERVER = os.path.dirname(HERE)
REPO_DATA = os.path.join(REPO_SERVER, 'data')
SQL_DIR = os.path.join(REPO_SERVER, 'sql')

STEPS = ['files', 'lib', 'monsternames', 'vocations', 'events', 'basecrafting', 'basecraftingui', 'basecraftingbonus', 'weapons', 'lategame', 'crafting', 'orbs', 'darktiles', 'gems', 'salvage', 'omens', 'ascended', 'factions', 'pouches', 'depot', 'charms', 'professions', 'gamble', 'supports', 'outfits', 'auras', 'donoritems', 'packitems', 'fistweapons', 'monsters', 'spawns', 'spells', 'archery', 'itemnames', 'towns', 'npcnames', 'worldtexts', 'houses', 'poi', 'autoloot', 'commands', 'autosave', 'stalls', 'sql']

# folders copied from the repo's server/data into SERVER_DIR/data: (repo sub-folder, file filter, recursive)
COPY = [
    ('scripts/chaos', None, True),
    ('lib', lambda name: name.startswith('chaos_') and name.endswith('.lua'), False),
    ('monster/monsters/chaos', lambda name: name.endswith('.xml'), True),
    ('monster/lua/chaos', lambda name: name.endswith('.lua'), True),
    ('spells/chaos', None, True),
    ('patchnotes', lambda name: name.endswith('.md') or name == 'index.txt', False),
]
# never copied, wherever they are (editor and Python leftovers)
IGNORE = re.compile(r'(^|/)(__pycache__|\.DS_Store)(/|$)|\.pyc$|~$|\.swp$|\.orig$|\.rej$')

LIB_LINE = "dofile('data/lib/chaos_unique_items.lua')"
LIB_MARK = '-- Chaos unique items (server/tools/install_all.py, data/items/README.md)'
AUTOLOOT_RE = re.compile(r'^([ \t]*)(<talkaction\s+words="!autoloot"[^>]*/>)[ \t]*$', re.M)
AUTOLOOT_MARK = 'Chaos: autoloot.lua registers !autoloot (server/tools/install_all.py)'

# hashed for the change report; the map itself is skipped (large and never changed by any step)
SKIP_HASH = re.compile(r'\.otbm(\.bak|\.tmp)?$|(^|/)(logs|reports)/')


# ------------------------------------------------------------------------------------------------ helpers
def say(text=''):
    print(text, flush=True)


def snapshot(server):
    """relative path -> sha1 of config.lua and every file under data/ (no maps, logs, reports)"""
    out = {}
    cfg = os.path.join(server, 'config.lua')
    if os.path.isfile(cfg):
        out['config.lua'] = digest(cfg)
    data = os.path.join(server, 'data')
    for root, dirs, files in os.walk(data):
        dirs.sort()
        for name in files:
            path = os.path.join(root, name)
            rel = os.path.relpath(path, server).replace(os.sep, '/')
            if SKIP_HASH.search(rel) or os.path.islink(path):
                continue
            out[rel] = digest(path)
    return out


def digest(path):
    h = hashlib.sha1()
    with open(path, 'rb') as f:
        for block in iter(lambda: f.read(1 << 20), b''):
            h.update(block)
    return h.hexdigest()


def diff(before, after):
    added = sorted(k for k in after if k not in before)
    removed = sorted(k for k in before if k not in after)
    changed = sorted(k for k in after if k in before and before[k] != after[k])
    return added, changed, removed


def run_tool(args, label):
    """runs a repo tool with this interpreter in isolated mode; returns (ok, output lines)"""
    cmd = [sys.executable, '-I'] + args
    proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, universal_newlines=True)
    lines = [line for line in proc.stdout.splitlines() if line.strip()]
    if proc.returncode != 0:
        lines.append('%s exited with status %d' % (label, proc.returncode))
    return proc.returncode == 0, lines


def read(path):
    with open(path, encoding='utf-8', errors='surrogateescape') as f:
        return f.read()


def write(path, text):
    with open(path, 'w', encoding='utf-8', errors='surrogateescape', newline='') as f:
        f.write(text)


# ------------------------------------------------------------------------------------------------ steps
def step_files(server, data, ctx):
    lines, warn = [], []
    copied = same = 0
    for sub, keep, recursive in COPY:
        src_root = os.path.join(REPO_DATA, *sub.split('/'))
        if not os.path.isdir(src_root):
            continue
        dst_root = os.path.join(data, *sub.split('/'))
        n_new = n_upd = 0
        for root, dirs, files in os.walk(src_root):
            dirs.sort()
            if not recursive:
                dirs[:] = []
            for name in sorted(files):
                src = os.path.join(root, name)
                rel = os.path.relpath(src, src_root).replace(os.sep, '/')
                if IGNORE.search(rel) or (keep and not keep(name)):
                    continue
                dst = os.path.join(dst_root, *rel.split('/'))
                if os.path.isfile(dst) and digest(dst) == digest(src):
                    same += 1
                    continue
                if os.path.isfile(dst):
                    n_upd += 1
                else:
                    n_new += 1
                os.makedirs(os.path.dirname(dst), exist_ok=True)
                shutil.copyfile(src, dst)
                copied += 1
        if n_new or n_upd:
            lines.append('data/%s: %d new, %d updated' % (sub, n_new, n_upd))
    # patchnotes: the server lists the folder with io.popen when it can, else it reads index.txt
    notes = os.path.join(data, 'patchnotes')
    if os.path.isdir(notes) and not os.path.isfile(os.path.join(REPO_DATA, 'patchnotes', 'index.txt')):
        index = ''.join(n + '\n' for n in sorted(os.listdir(notes)) if n.endswith('.md'))
        path = os.path.join(notes, 'index.txt')
        if not os.path.isfile(path) or read(path) != index:
            write(path, index)
            lines.append('data/patchnotes/index.txt written')
    # scripts the repo no longer has (renamed or removed modules) would still load: list them
    repo_scripts = os.path.join(REPO_DATA, 'scripts', 'chaos')
    dst_scripts = os.path.join(data, 'scripts', 'chaos')
    for root, dirs, files in os.walk(dst_scripts):
        for name in files:
            rel = os.path.relpath(os.path.join(root, name), dst_scripts)
            if name.endswith('.lua') and not os.path.isfile(os.path.join(repo_scripts, rel)):
                warn.append('data/scripts/chaos/%s is not in the repo (old module?): check it, delete it by hand' % rel)
    lines.append('%d file(s) written, %d already up to date' % (copied, same))
    return True, lines, warn


def step_lib(server, data, ctx):
    path = os.path.join(data, 'lib', 'lib.lua')
    if not os.path.isfile(path):
        return False, ['missing ' + path], []
    text = read(path)
    if LIB_LINE in text or LIB_LINE.replace("'", '"') in text:
        return True, ['lib.lua already loads chaos_unique_items.lua'], []
    sep = '' if text.endswith('\n') or text == '' else '\n'
    write(path, text + sep + LIB_MARK + '\n' + LIB_LINE + '\n')
    return True, ['lib.lua: added ' + LIB_LINE], []


def step_monsternames(server, data, ctx):
    return tool_result(run_tool([tool('patch_base_monster_names.py'), data], 'patch_base_monster_names.py'))


def step_vocations(server, data, ctx):
    ok, lines = run_tool([tool('add_vocations.py'), data], 'add_vocations.py')
    if ok and os.path.isfile(tool('patch_base_classes.py')):
        ok2, more = run_tool([tool('patch_base_classes.py'), data], 'patch_base_classes.py')
        ok, lines = ok2, lines + more
    return tool_result((ok, lines))


def step_events(server, data, ctx):
    # --enable-spell-events: the cooldown / mana-cost reductions run through the engine's spell events (engine patch
    # 0008); without that patch the engine only warns about the four unknown events and the Lua fallbacks apply
    ok, lines = run_tool([tool('patch_base_events.py'), data, '--enable-spell-events'], 'patch_base_events.py')
    if ok and os.path.isfile(tool('patch_season_events.py')):
        ok2, more = run_tool([tool('patch_season_events.py'), data], 'patch_season_events.py')
        ok, lines = ok2, lines + more
    if ok and os.path.isfile(tool('patch_market.py')):
        ok4, more = run_tool([tool('patch_market.py'), data], 'patch_market.py')
        ok, lines = ok4, lines + more
    if ok and os.path.isfile(tool('patch_help_itemlinks.py')):
        ok3, more = run_tool([tool('patch_help_itemlinks.py'), data], 'patch_help_itemlinks.py')
        ok, lines = ok3, lines + more
    if ok and os.path.isfile(tool('patch_report_chat.py')):
        ok6, more = run_tool([tool('patch_report_chat.py'), data], 'patch_report_chat.py')
        ok, lines = ok6, lines + more
    if ok:
        ok5, more = run_tool([tool('patch_base_npcs.py'), data], 'patch_base_npcs.py')
        ok, lines = ok5, lines + more
    return tool_result((ok, lines))


def step_basecrafting(server, data, ctx):
    return tool_result(run_tool([tool('patch_base_crafting.py'), data], 'patch_base_crafting.py'))


def step_basecraftingui(server, data, ctx):
    return tool_result(run_tool([tool('patch_base_crafting_ui.py'), data], 'patch_base_crafting_ui.py'))


def step_basecraftingbonus(server, data, ctx):
    return tool_result(run_tool([tool('patch_base_crafting_bonus.py'), data], 'patch_base_crafting_bonus.py'))


def step_weapons(server, data, ctx):
    return tool_result(run_tool([tool('two_handed.py'), data], 'two_handed.py'))


def step_lategame(server, data, ctx):
    return tool_result(run_tool([tool('late_game.py'), data, '--config', os.path.join(server, 'config.lua')],
                                'late_game.py'))


def step_crafting(server, data, ctx):
    return tool_result(run_tool([tool('install_crafting.py'), data], 'install_crafting.py'))


def step_orbs(server, data, ctx):
    return tool_result(run_tool([tool('install_orbs.py'), data], 'install_orbs.py'))


def step_darktiles(server, data, ctx):
    return tool_result(run_tool([tool('install_dark_tiles.py'), data], 'install_dark_tiles.py'))


def step_outfits(server, data, ctx):
    return tool_result(run_tool([tool('install_outfits.py'), data], 'install_outfits.py'))


def step_auras(server, data, ctx):
    return tool_result(run_tool([tool('install_auras.py'), data], 'install_auras.py'))


def step_donoritems(server, data, ctx):
    return tool_result(run_tool([tool('install_donor_items.py'), data], 'install_donor_items.py'))


def step_packitems(server, data, ctx):
    return tool_result(run_tool([tool('install_pack_items.py'), data], 'install_pack_items.py'))


def step_fistweapons(server, data, ctx):
    return tool_result(run_tool([tool('install_fist_weapons.py'), data], 'install_fist_weapons.py'))


def step_gems(server, data, ctx):
    return tool_result(run_tool([tool('install_gems.py'), data], 'install_gems.py'))


def step_salvage(server, data, ctx):
    return tool_result(run_tool([tool('install_salvage.py'), data], 'install_salvage.py'))


def step_omens(server, data, ctx):
    return tool_result(run_tool([tool('install_omens.py'), data], 'install_omens.py'))


def step_ascended(server, data, ctx):
    return tool_result(run_tool([tool('install_ascended.py'), data], 'install_ascended.py'))


def step_factions(server, data, ctx):
    return tool_result(run_tool([tool('install_factions.py'), data], 'install_factions.py'))


def step_pouches(server, data, ctx):
    return tool_result(run_tool([tool('install_pouches.py'), data], 'install_pouches.py'))


def step_depot(server, data, ctx):
    return tool_result(run_tool([tool('patch_base_depot.py'), data], 'patch_base_depot.py'))


def step_charms(server, data, ctx):
    return tool_result(run_tool([tool('install_charms.py'), data], 'install_charms.py'))


def step_professions(server, data, ctx):
    return tool_result(run_tool([tool('install_professions.py'), data], 'install_professions.py'))


def step_gamble(server, data, ctx):
    return tool_result(run_tool([tool('install_gamble.py'), data], 'install_gamble.py'))


def step_supports(server, data, ctx):
    return tool_result(run_tool([tool('install_supports.py'), data], 'install_supports.py'))


def step_monsters(server, data, ctx):
    xml = os.path.join(data, 'monster', 'monsters.xml')
    root = os.path.join(data, 'monster', 'monsters', 'chaos')
    if not os.path.isfile(xml):
        return False, ['missing ' + xml], []
    lines = []
    for folder, dirs, files in os.walk(root):
        dirs.sort()
        if not any(f.endswith('.xml') for f in files):
            continue
        ok, out = run_tool([tool('register_monsters.py'), xml, folder], 'register_monsters.py')
        rel = os.path.relpath(folder, data).replace(os.sep, '/')
        lines += ['%s: %s' % (rel, line) for line in out]
        if not ok:
            return False, lines, []
    return True, lines, []


def step_spawns(server, data, ctx):
    return tool_result(run_tool([tool('patch_base_spawns.py'), data, '--config', os.path.join(server, 'config.lua')],
                                'patch_base_spawns.py'))


def step_spells(server, data, ctx):
    ok, lines = run_tool([tool('register_spells.py'), data], 'register_spells.py')
    if not ok:
        return False, lines, []
    # CLASS HOOK (see the docstring): installers of the class lines, run after the Chaos spell block exists
    for hook in class_hooks():
        ok, more = run_tool([hook, data], os.path.basename(hook))
        lines += ['[%s] %s' % (os.path.basename(hook), line) for line in more]
        if not ok:
            return False, lines, []
    sql_out = os.path.join(ctx['tmp'], 'rename_spells.sql')
    ok, more = run_tool([tool('rename_spells.py'), data, '--sql', sql_out], 'rename_spells.py')
    lines += more
    if ok and os.path.isfile(sql_out):
        ctx['rename_sql'] = sql_out
    warn = unregistered_spell_fragments(data)
    return ok, lines, warn


def step_archery(server, data, ctx):
    return tool_result(run_tool([tool('patch_base_archery.py'), data], 'patch_base_archery.py'))


def step_itemnames(server, data, ctx):
    return tool_result(run_tool([tool('patch_base_item_names.py'), data], 'patch_base_item_names.py'))


def step_towns(server, data, ctx):
    if ctx['dry']:
        # the dry copy has no map: read the real one, write nothing
        real = os.path.join(ctx['server'], 'data')
        return tool_result(run_tool([tool('patch_base_towns.py'), real, '--dry-run'], 'patch_base_towns.py'))
    return tool_result(run_tool([tool('patch_base_towns.py'), data], 'patch_base_towns.py'))


def step_npcnames(server, data, ctx):
    return tool_result(run_tool([tool('patch_base_npc_names.py'), data], 'patch_base_npc_names.py'))


def step_worldtexts(server, data, ctx):
    if ctx['dry']:
        # the dry copy has no map: the data files on the copy, the map texts read from the real map, nothing written
        ok, lines = run_tool([tool('patch_base_texts.py'), data, '--no-map'], 'patch_base_texts.py')
        if ok:
            real = os.path.join(ctx['server'], 'data')
            ok, more = run_tool([tool('patch_base_texts.py'), real, '--map-only', '--dry-run'], 'patch_base_texts.py')
            lines += more
        return tool_result((ok, lines))
    return tool_result(run_tool([tool('patch_base_texts.py'), data], 'patch_base_texts.py'))


def step_servername(server, data, ctx):
    return tool_result(run_tool([tool('patch_base_server_name.py'), data], 'patch_base_server_name.py'))


STEPS.insert(STEPS.index('worldtexts') + 1, 'servername')  # after worldtexts, which may rename part of a phrase first


def step_houses(server, data, ctx):
    return tool_result(run_tool([tool('patch_base_houses.py'), data], 'patch_base_houses.py'))


def step_poi(server, data, ctx):
    if ctx['dry']:
        # the dry copy has no map: read the real one, write into the copy
        real = os.path.join(ctx['server'], 'data')
        mp = tool_map_path(real)
        if not mp:
            return tool_result((False, ['no map in %s/world' % real]))
        return tool_result(run_tool([tool('gen_poi.py'), server, '--map', mp], 'gen_poi.py'))
    return tool_result(run_tool([tool('gen_poi.py'), server], 'gen_poi.py'))


def tool_map_path(data_dir):
    sys.path.insert(0, HERE)
    import patch_base_towns
    return patch_base_towns.map_path(data_dir)


def step_commands(server, data, ctx):
    return tool_result(run_tool([tool('install_commands.py'), data], 'install_commands.py'))


def step_autosave(server, data, ctx):
    return tool_result(run_tool([tool('patch_base_save.py'), data], 'patch_base_save.py'))


def step_stalls(server, data, ctx):
    return tool_result(run_tool([tool('patch_base_stalls.py'), data], 'patch_base_stalls.py'))


def step_bossrooms(server, data, ctx):
    return tool_result(run_tool([tool('patch_base_bossrooms.py'), data], 'patch_base_bossrooms.py'))


STEPS.insert(STEPS.index('stalls') + 1, 'bossrooms')  # after stalls, before sql


def step_dungeonentry(server, data, ctx):
    return tool_result(run_tool([tool('patch_base_dungeon.py'), data], 'patch_base_dungeon.py'))


STEPS.insert(STEPS.index('bossrooms') + 1, 'dungeonentry')  # after bossrooms, before sql


def step_eventrooms(server, data, ctx):
    return tool_result(run_tool([tool('patch_base_eventrooms.py'), data], 'patch_base_eventrooms.py'))


STEPS.insert(STEPS.index('bossrooms') + 1, 'eventrooms')  # after bossrooms, before dungeonentry and sql


def step_autoloot(server, data, ctx):
    path = os.path.join(data, 'talkactions', 'talkactions.xml')
    if not os.path.isfile(path):
        return True, ['no talkactions.xml, nothing to do'], []
    text = read(path)
    new, n = AUTOLOOT_RE.subn(lambda m: '%s<!-- %s: %s -->' % (m.group(1), AUTOLOOT_MARK, m.group(2)), text)
    if not n:
        return True, ['the XML !autoloot talkaction is already off (or not there)'], []
    write(path, new)
    return True, ['talkactions.xml: XML !autoloot commented out'], []


def step_sql(server, data, ctx):
    files = sql_files(ctx)
    if ctx['dry'] or ctx['no_sql']:
        why = 'dry run' if ctx['dry'] else '--no-sql'
        return True, ['(%s) would run against `%s`: %s' % (why, ctx['db'].get('database', '?'),
                                                         ', '.join(os.path.basename(f) for f in files))], []
    db = ctx['db']
    if not db.get('database'):
        return False, ['no database name (config.lua mysqlDatabase or --db)'], []
    mysql = ctx['mysql']
    if not shutil.which(mysql):
        return False, ['mysql client not found (%s); install it or pass --mysql PATH' % mysql], []
    fd, opt = tempfile.mkstemp(prefix='chaos_my_', suffix='.cnf')
    try:
        os.chmod(opt, 0o600)
        with os.fdopen(fd, 'w') as f:
            f.write('[client]\n')
            for key in ('host', 'port', 'user', 'password'):
                if db.get(key) not in (None, ''):
                    f.write('%s="%s"\n' % (key, str(db[key]).replace('\\', '\\\\').replace('"', '\\"')))
        base = [mysql, '--defaults-extra-file=' + opt, '--batch', '--skip-column-names', db['database']]
        before = tables(base)
        if before is None:
            return False, ['cannot connect to the database `%s` (check host, user, CHAOS_DB_PASS)' % db['database']], []
        lines = []
        for path in files:
            with open(path, 'rb') as f:
                proc = subprocess.run(base, stdin=f, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
            out = proc.stdout.decode('utf-8', 'replace').strip()
            if proc.returncode != 0:
                return False, lines + ['%s failed: %s' % (os.path.basename(path), out)], []
            lines.append('%s: ok' % os.path.basename(path))
        after = tables(base) or set()
        new = sorted(after - before)
        lines.append('%d new table(s)%s' % (len(new), (': ' + ', '.join(new)) if new else ''))
        ctx['new_tables'] = new
        return True, lines, []
    finally:
        os.unlink(opt)


# ------------------------------------------------------------------------------------------------ step helpers
def tool(name):
    return os.path.join(HERE, name)


def tool_result(res):
    ok, lines = res
    return ok, lines, []


def class_hooks():
    return sorted(os.path.join(HERE, n) for n in os.listdir(HERE) if re.match(r'install_class_\w+\.py$', n))


def unregistered_spell_fragments(data):
    """spells_*.xml fragments of the class lines whose spells are not in spells.xml yet (no installer ran for them)"""
    src = os.path.join(REPO_DATA, 'spells', 'chaos')
    spells = os.path.join(data, 'spells', 'spells.xml')
    if not os.path.isfile(spells):
        return []
    have = set(re.findall(r'\bwords="([^"]+)"', read(spells)))
    warn = []
    for name in sorted(os.listdir(src)):
        if not re.match(r'spells_\w+\.xml$', name) or name == 'spells_chaos.xml':
            continue
        words = re.findall(r'\bwords="([^"]+)"', read(os.path.join(src, name)))
        missing = [w for w in words if w not in have]
        if missing:
            warn.append('%s: %d of %d spells are not in spells.xml (no installer for this class yet: add '
                        'server/tools/install_class_<name>.py, the class hook of the spells step)'
                        % (name, len(missing), len(words)))
    return warn


def sql_files(ctx):
    names = sorted(n for n in os.listdir(SQL_DIR) if n.endswith('.sql'))
    files = [os.path.join(SQL_DIR, 'chaos.sql')] if 'chaos.sql' in names else []
    files += [os.path.join(SQL_DIR, n) for n in names if n != 'chaos.sql']
    if ctx.get('rename_sql'):
        files.append(ctx['rename_sql'])
    return files


def tables(base):
    proc = subprocess.run(base + ['-e', 'SHOW TABLES'], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if proc.returncode != 0:
        return None
    return set(proc.stdout.decode('utf-8', 'replace').split())


def config_value(text, key):
    """a config.lua string/number setting; os.getenv("X") or "default" reads the environment"""
    m = re.search(r'^\s*%s\s*=\s*(.+?)\s*(?:--.*)?$' % re.escape(key), text, re.M)
    if not m:
        return None
    expr = m.group(1)
    env = re.match(r'(?:tonumber\(\s*)?os\.getenv\(\s*["\']([^"\']+)["\']\s*\)\s*\)?\s*(?:or\s*(.+))?$', expr)
    if env:
        if os.environ.get(env.group(1)):
            return os.environ[env.group(1)]
        expr = env.group(2) or '""'
    lit = re.match(r'^"([^"]*)"$|^\'([^\']*)\'$|^(\d+)$', expr.strip())
    if not lit:
        return None
    return next(g for g in lit.groups() if g is not None)


def db_settings(server, args):
    cfg = os.path.join(server, 'config.lua')
    text = read(cfg) if os.path.isfile(cfg) else ''
    db = {'host': config_value(text, 'mysqlHost'), 'port': config_value(text, 'mysqlPort'),
          'user': config_value(text, 'mysqlUser'), 'database': config_value(text, 'mysqlDatabase'),
          'password': os.environ.get('CHAOS_DB_PASS') or os.environ.get('MYSQL_PWD') or config_value(text, 'mysqlPass')}
    for key, opt in (('database', '--db'), ('host', '--db-host'), ('port', '--db-port'), ('user', '--db-user')):
        if args.get(opt):
            db[key] = args[opt]
    return db


def make_dry_copy(server, tmp):
    """config.lua + data/ without maps, logs and reports"""
    copy = os.path.join(tmp, 'server')
    os.makedirs(copy)
    shutil.copy2(os.path.join(server, 'config.lua'), os.path.join(copy, 'config.lua'))
    src = os.path.join(server, 'data')

    def ignore(folder, names):
        rel = os.path.relpath(folder, src).replace(os.sep, '/')
        skip = [n for n in names if n.endswith(('.otbm', '.otbm.bak', '.otbm.tmp'))]
        if rel == '.':
            skip += [n for n in names if n in ('logs', 'reports')]
        return skip
    shutil.copytree(src, os.path.join(copy, 'data'), ignore=ignore, symlinks=True)
    return copy


# ------------------------------------------------------------------------------------------------ main
def parse_args(argv):
    args, pos = {}, []
    i = 0
    while i < len(argv):
        a = argv[i]
        if a in ('--dry-run', '--no-sql', '--quiet', '--verbose'):
            args[a] = True
        elif a in ('--skip', '--only', '--db', '--db-host', '--db-port', '--db-user', '--mysql'):
            if i + 1 >= len(argv):
                sys.exit('%s needs a value' % a)
            args[a] = argv[i + 1]
            i += 1
        elif a in ('-h', '--help'):
            print(__doc__)
            sys.exit(0)
        elif a.startswith('-'):
            sys.exit('unknown option %s (see --help)' % a)
        else:
            pos.append(a)
        i += 1
    if len(pos) != 1:
        print(__doc__)
        sys.exit(2)
    return pos[0], args


def main(argv):
    server, args = parse_args(argv)
    server = os.path.abspath(server)
    dry = bool(args.get('--dry-run'))
    for need in ('config.lua', 'data'):
        if not os.path.exists(os.path.join(server, need)):
            sys.exit('%s has no %s: pass the base server folder (the one with config.lua and data/)' % (server, need))
    steps = list(STEPS)
    for opt in ('--skip', '--only'):
        if args.get(opt):
            names = [s.strip() for s in args[opt].split(',') if s.strip()]
            bad = [s for s in names if s not in STEPS]
            if bad:
                sys.exit('unknown step(s) %s; steps: %s' % (', '.join(bad), ', '.join(STEPS)))
            steps = [s for s in steps if (s not in names) == (opt == '--skip')]

    tmp = tempfile.mkdtemp(prefix='chaos_install_')
    try:
        target = make_dry_copy(server, tmp) if dry else server
        data = os.path.join(target, 'data')
        ctx = {'dry': dry, 'server': server, 'no_sql': bool(args.get('--no-sql')), 'tmp': tmp, 'mysql': args.get('--mysql', 'mysql'),
               'db': db_settings(server, args)}
        say('Cinders of Chaos install%s' % (' (DRY RUN on a temporary copy; nothing is changed)' if dry else ''))
        say('  server:   %s' % server)
        say('  repo:     %s' % REPO_SERVER)
        say('  steps:    %s' % ', '.join(steps))
        hooks = class_hooks()
        say('  class hook installers: %s' % (', '.join(os.path.basename(h) for h in hooks) or 'none yet'))
        say()
        total_changed, warnings, failed = 0, [], None
        snap = snapshot(target)
        for name in steps:
            fn = globals()['step_' + name]
            ok, lines, warn = fn(target, data, ctx)
            after = snapshot(target)
            added, changed, removed = diff(snap, after)
            snap = after
            n = len(added) + len(changed) + len(removed)
            total_changed += n
            say('[%s] %s%s' % ('ok' if ok else 'FAILED', name,
                               '' if name == 'sql' else ' - %d file(s) %s' % (n, 'would change' if dry else 'changed')))
            if not args.get('--quiet') or not ok:
                limit = len(lines) if args.get('--verbose') or not ok else 15
                for line in lines[:limit]:
                    say('    ' + line)
                if len(lines) > limit:
                    say('    ... %d more line(s) of tool output (--verbose shows them)' % (len(lines) - limit))
            shown = [('+', p) for p in added] + [('~', p) for p in changed] + [('-', p) for p in removed]
            for sign, p in shown[:25]:
                say('    %s %s' % (sign, p))
            if len(shown) > 25:
                say('    ... and %d more' % (len(shown) - 25))
            for w in warn:
                say('    WARNING: ' + w)
            warnings += warn
            if not ok:
                failed = name
                break
        say()
        say('Summary: %d file(s) %s%s; %s.' % (total_changed, 'would change' if dry else 'changed',
                                               ', %d new table(s)' % len(ctx.get('new_tables', [])) if 'sql' in steps
                                               and not dry and not ctx['no_sql'] else '',
                                               'FAILED at step "%s"' % failed if failed else 'every step succeeded'))
        if warnings:
            say('%d warning(s), see above.' % len(warnings))
        if not failed and not dry:
            say('Next: restart the server (or /reload scripts) and read the console for Lua errors. See docs/LAUNCH.md.')
        return 1 if failed else 0
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
