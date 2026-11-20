#!/usr/bin/env python3
"""Every place that sets a monster's health reads the spell ranks' health factor H (O686 phase 3).

docs/SPELL_UPGRADES.md 5.3 and 5.4: the compensation for the spell ranks is monster health by level, one curve
(spell_ranks_config.lua `health`), one door (Chaos.healthFactor / Chaos.scaleHealth in chaos_constants.lua). A system that
sets a monster's maximum health and forgets the door would leave its monsters at today's health while the players' spells
grow: a content that is too easy, found only after the switch. This check is the grep that finds it first.

Every server Lua file under server/data with a `setMaxHealth(` call is in one of two tables:
  PATHS    the file takes H: it must call Chaos.scaleHealth( or Chaos.healthFactor( at least `count` times (non comment code)
  ALLOWED  the file does not, with the reason (a player, a minion of a player, a value relative to a monster that already
           has H, a tester bot's copy)
A file with a setMaxHealth call that is in neither table fails (a new health-setting path must choose), and so does a file
listed that has no such call any more (a stale row).

python3 -I tools/ci/check_health_paths.py   (exit 1 and the lines when one breaks the rule)
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SCRIPTS = os.path.join("server", "data", "scripts", "chaos")
CALL_RE = re.compile(r"setMaxHealth\s*\(")
DOOR_RE = re.compile(r"Chaos\.(?:scaleHealth|healthFactor)\s*\(")

# file (under server/data/scripts/chaos): (minimum calls of the door, where H is read)
PATHS = {
    "pace.lua": (1, "hunts: every natural spawn and generated-area point, at its hunting level (a boss or a summon is skipped there)"),
    "areagen.lua": (1, "a generated area's boss point (the pace layer skips bosses), at the point's level"),
    "cursedchest.lua": (1, "the chest's husk: the pace call took H at its own level, the husk is a hunt monster of the target level"),
    "dungeons.lua": (1, "a base dungeon's monsters at the dungeon level + 25 (a generated dungeon has H from pace.lua and areagen.lua)"),
    "boss_mechanics.lua": (1, "adds and totems of a mechanic, at the level the host plans the boss for (opts.level)"),
    "rift.lua": (1, "rift packs and guardians at the tier's level, an Omen guardian at omen.refLevel, the Greater Rift at greater.healthLevel"),
    "infinitytower_run.lua": (1, "a tower floor's monster at the floor's monster level"),
    "descent.lua": (1, "Ember Descent rooms and boss at the party's level"),
    "waystone_tiers.lua": (1, "a waystone map's monster at the map's level (a paced map spawn moves from its own level)"),
    "pinnacle.lua": (1, "the Ascended bosses at the planned level 1900 / 2100 / 2300 / 2500"),
    "uber.lua": (2, "Omen Ascended bosses and the Cinderheart (and their adds) at model.refLevel"),
    "guildboss.lua": (2, "the guild boss and its adds at model.refLevel"),
    "raid.lua": (1, "every monster of a raid at model.refLevel"),
    "worldboss.lua": (2, "the world boss and its phase adds at the entry level"),
    "pocketboss.lua": (1, "a pocket boss at the level the pocket is tuned for"),
    "invasion.lua": (2, "invaders and the warlords at the area level"),
    "trials.lua": (2, "Trial wardens and thralls at the level the trial is scaled to"),
    "ascension_quest.lua": (2, "the Oracle's Trial guardian and adds at the level the trial is scaled to"),
    "bosslair.lua": (1, "a lair boss (Talath, Malgrath) at the level its lair is planned for (healthLevel), at its first think"),
    "treasure_goblin.lua": (1, "the goblin's real health when it comes from its level (from a replaced monster it already carries H)"),
}

ALLOWED = {
    "monster_tiers.lua": "magic / rare / legendary tier: a share of the monster's current maximum, which carries H of its host",
    "nemesis.lua": "relative to the monster pace.apply scaled right before it (pace.lua took H at the hunting level)",
    "waystone_mods.lua": "a run modifier's multiplier on the maximum the tier layer already set, relative only",
    "pvpzone.lua": "the zone's PvP objective monsters, a multiplier of the monster's own maximum; no kill-time target of the ranks",
    "necro_lib.lua": "a player's minion: its health follows its owner's stats, not a monster health curve",
    "classes.lua": "a player's companion (the Beastmaster's wolves): health follows its owner",
    "testers_boss.lua": "a tester bot's own copy of a boss: a share of the copy's health the host system already set",
    "shop_services.lua": "Player:setMaxHealth (a character's stats)",
    "newplayer.lua": "Player:setMaxHealth (the tutorial's stats)",
    "newplayer_core.lua": "Player:setMaxHealth (the tutorial's stats)",
    "class_migration.lua": "Player:setMaxHealth (a class change)",
    "ascension.lua": "Player:setMaxHealth (an ascension)",
    "admin/testkit.lua": "Player:setMaxHealth (the staff test kit)",
}


def strip_comments(text):
    """The text with Lua comments blanked and string contents masked (same length, same line breaks)."""
    out = []
    i, n = 0, len(text)
    while i < n:
        c = text[i]
        if c in "\"'":
            j = i + 1
            while j < n and text[j] != c and text[j] != "\n":
                j += 2 if text[j] == "\\" else 1
            out.append(c + "_" * (j - i - 1) + text[j:j + 1])
            i = j + 1
        elif text.startswith("--", i):
            m = re.match(r"--\[(=*)\[", text[i:])
            if m:
                end = text.find("]" + m.group(1) + "]", i)
                end = n if end < 0 else end + len(m.group(1)) + 2
            else:
                end = text.find("\n", i)
                end = n if end < 0 else end
            out.append(re.sub(r"[^\n]", " ", text[i:end]))
            i = end
        else:
            out.append(c)
            i += 1
    return "".join(out)


def counts(text):
    """(setMaxHealth calls, door calls) of the code of a Lua text"""
    code = strip_comments(text)
    return len(CALL_RE.findall(code)), len(DOOR_RE.findall(code))


def check_files(files, paths=PATHS, allowed=ALLOWED):
    """files: {relative name: text}. The list of problems."""
    bad = []
    for name, text in sorted(files.items()):
        calls, door = counts(text)
        if name in paths:
            need = paths[name][0]
            if calls == 0:
                bad.append("%s: listed in PATHS but has no setMaxHealth call any more" % name)
            elif door < need:
                bad.append("%s: %d setMaxHealth call(s) and %d read(s) of Chaos.scaleHealth / Chaos.healthFactor, needs %d (%s)" % (
                    name, calls, door, need, paths[name][1]))
        elif name in allowed:
            if calls == 0:
                bad.append("%s: listed in ALLOWED but has no setMaxHealth call any more" % name)
        elif calls:
            bad.append("%s: %d setMaxHealth call(s), neither read H (Chaos.scaleHealth) nor named in ALLOWED with a reason" % (name, calls))
    for name in sorted(set(paths) | set(allowed)):
        if name not in files:
            bad.append("%s: listed but the file is gone" % name)
    return bad


def load(root=ROOT):
    base = os.path.join(root, SCRIPTS)
    files = {}
    for d, _, names in os.walk(base):
        for n in names:
            if n.endswith(".lua"):
                p = os.path.join(d, n)
                with open(p, encoding="utf-8") as f:
                    files[os.path.relpath(p, base).replace(os.sep, "/")] = f.read()
    return files


def main():
    bad = check_files(load())
    for b in bad:
        print("FAIL " + b)
    if not bad:
        print("health paths: ok (%d files read H, %d named with a reason)" % (len(PATHS), len(ALLOWED)))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
