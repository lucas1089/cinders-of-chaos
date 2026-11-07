#!/usr/bin/env python3
"""Front-art live effects: the element of every effect and missile id the server sends (unity/Client/Assets/Chaos/Core/FrontFxIds.cs).

The server names its ids in server/data/lib/*.lua (ChaosFx, ChaosVfx, ChaosVfxMissile, ChaosPair51Missile, tables or one line each, with a
comment that says what the picture shows) and server/data/spells/effects_catalog.csv (the stock ids our art redraws, with a theme). The
stock ids that art does not redraw come from the table below (const.h of the base server). Each id gets one letter by the keywords of its
name and comment (the first rule that matches the name wins, then the comment):

  F fire  I ice  E energy (lightning)  A arcane  D death (necrotic, bones)  H holy  P physical (steel, impacts)  B blood
  S shadow  V poison  T earth (plants, stone)  W water  L heal  N neutral  X nothing to draw (loot rays, teleports, puffs, words)

The table is written as runs ("372-378F,379-383I"). Run: python3 -I unity/tools/gen_front_fx_ids.py [--check] [--root REPO]
--check exits 1 when the committed file is stale (CI). The C# side: Core/FrontFx.cs, test: Core.Tests/FrontFxTests.cs.
"""
import csv
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
OUT = os.path.join("unity", "Client", "Assets", "Chaos", "Core", "FrontFxIds.cs")

# rule order: the first element with a keyword in the text wins
RULES = [
    ("X", ["loot", "teleport", "poff", "word_", "mapmark", "tutorial", "mirror", "gift", "cake", "firework", "telegraph", "tp_", "portal_open"]),
    ("L", ["heal", "regen", "heart", "restor", "revive", "mend"]),
    ("B", ["sanguine", "scarlet", "vein", "guillotine", "blood", "bleed", "vampir", "crimson", "gore"]),
    ("V", ["caustic", "noxious", "bilious", "blight", "corrosive", "bog", "stinging", "pollen", "toxin", "sludge", "inkspout", "poison", "venom", "toxic", "acid", "plague", "spore", "miasma", "decay"]),
    ("D", ["ossuary", "dirge", "reaper", "tomb", "crypt", "grim", "banshee", "wail", "cemetery", "necro", "death", "bone", "skull", "soul", "grave", "lich", "spirit", "wraith", "mort", "undead", "ghost"]),
    ("H", ["hallowed", "halo", "hymn", "sanctum", "herald", "seraph", "aureole", "holy", "divine", "bless", "smite", "radiant", "ankh", "celestial", "angel", "dawn", "sacred", "luminous", "aegis", "sunburst", "sunbeam"]),
    ("I", ["rime", "hoar", "cryo", "winter", "glacial", "icicle", "sleet", "*frost", "ice", "frost", "frozen", "freez", "snow", "cold", "glacier", "blizzard", "shiver", "chill", "crystal"]),
    ("E", ["tempest", "ion", "static", "tesla", "railgun", "galvan", "chain_arc", "arc_reaper", "lightning", "thunder", "shock", "energy", "storm", "spark", "zap", "bolt_e", "electr", "volt"]),
    ("F", ["furnace", "slag", "flare", "plasma", "drake", "wyrm", "brimstone", "forge", "phoenix", "*fire", "*flame", "ash", "fire", "flame", "burn", "inferno", "ember", "cinder", "meteor", "hellfire", "magma", "lava", "blaze", "pyre", "explosion", "fireball", "ignite", "scorch", "sear"]),
    ("S", ["shade", "raven", "dusk", "nightmare", "ink", "shadow", "dark", "void", "umbra", "curse", "night", "abyss", "smoke", "gloom", "eclipse", "dread"]),
    ("A", ["chrono", "aether", "glyph", "sigil", "runic", "prism", "rift", "gravit", "dream", "echo", "starstep", "magnet", "hourglass", "hourhand", "rewind", "time", "arcane", "magic", "rune", "mana", "mystic", "sorcer", "violet", "astral", "cosmic", "psychic", "mind"]),
    ("W", ["riptide", "brine", "trident", "kelp", "seafoam", "torrent", "tidal", "coral", "foam", "flood", "water", "bubble", "drown", "tide", "wave_w", "splash", "ocean", "seawater"]),
    ("T", ["boulder", "briar", "bramble", "geode", "crag", "fault", "sand", "creeper", "seed", "obsidian", "tremor", "bellstone", "mud", "cactus", "earth", "plant", "thorn", "nature", "rock", "stone", "quake", "dirt", "leaf", "root", "vine", "petal", "sakura", "wood", "bark", "moss"]),
    ("P", ["crescent", "glaive", "fang", "rake", "rending", "ramming", "maul", "smash", "swipe", "scythe", "saw", "flail", "palm", "scimitar", "spike", "lance", "volley", "edge", "slash", "strike", "impact", "steel", "blade", "shockwave", "slam", "crush", "sword", "axe", "claw", "arrow", "spear", "dart", "knife", "club", "hammer", "punch", "kick", "whirl", "cleave", "iron", "stun", "dust"]),
]

STOCK_EFFECTS = {
    1: "drawblood", 2: "water loseenergy", 3: "poff", 4: "blockhit steel", 5: "explosion fire", 6: "explosion fire", 7: "fire", 8: "yellow rings holy",
    9: "green rings earth", 10: "hitarea steel", 11: "teleport", 12: "energy", 13: "magic blue arcane", 14: "magic red arcane", 15: "magic green earth",
    16: "hitbyfire fire", 17: "poison", 18: "mortarea death", 19: "sound green earth", 20: "sound red blood", 21: "poison", 22: "sound yellow holy",
    23: "sound purple arcane", 24: "sound blue arcane", 25: "sound white holy", 26: "bubbles water", 27: "craps", 28: "gift", 29: "firework", 30: "firework",
    31: "firework", 32: "stun", 33: "sleep arcane", 34: "watercreature water", 35: "groundshaker earth", 36: "hearts heal", 37: "fireattack fire",
    38: "energy", 39: "smallclouds death", 40: "holydamage holy", 41: "bigclouds death", 42: "ice", 43: "ice tornado", 44: "ice", 45: "stones earth",
    46: "smallplants earth", 47: "carniphila earth", 48: "purple energy", 49: "yellow energy", 50: "holy", 51: "bigplants earth", 52: "cake",
    53: "giant ice", 54: "water splash", 55: "plant earth", 56: "tutorial", 57: "tutorial", 58: "mirror", 59: "mirror", 60: "skull death", 61: "skull death",
    62: "assassin shadow", 63: "steps", 64: "bloody steps blood", 65: "steps", 66: "yalahari ghost shadow", 67: "bats shadow", 68: "smoke shadow",
    69: "insects poison", 70: "dragon head fire",
}
STOCK_MISSILES = {
    1: "spear", 2: "bolt arrow", 3: "arrow", 4: "fire", 5: "energy", 6: "poison arrow", 7: "burst fire arrow", 8: "throwing star", 9: "throwing knife",
    10: "small stone rock", 11: "death", 12: "large rock stone", 13: "snowball ice", 14: "power bolt energy", 15: "poison", 16: "infernal bolt fire",
    17: "hunting spear", 18: "enchanted spear arcane", 19: "red star", 20: "green star", 21: "royal spear", 22: "sniper arrow", 23: "onyx arrow shadow",
    24: "piercing bolt", 25: "whirlwind sword", 26: "whirlwind axe", 27: "whirlwind club", 28: "ethereal spear arcane", 29: "ice", 30: "earth",
    31: "holy", 32: "sudden death", 33: "flash arrow energy", 34: "flaming arrow fire", 35: "shiver arrow ice", 36: "energy ball", 37: "small ice",
    38: "small holy", 39: "small earth", 40: "earth arrow", 41: "explosion fire", 42: "cake",
}


def classify(name, comment=""):
    """The element letter: keywords match at the start of a word (so "light" does not match inside "lightning" first: E is checked
    before H, and H has no "light"); the name is read before the comment."""
    for text in (name.lower(), comment.lower()):
        for letter, words in RULES:
            for w in words:
                pat = re.escape(w[1:]) if w.startswith("*") else r"(?<![a-z])" + re.escape(w)
                if re.search(pat, text):
                    return letter
    return "N"


def lua_files(root):
    d = os.path.join(root, "server", "data", "lib")
    return sorted(os.path.join(d, f) for f in os.listdir(d) if f.endswith(".lua"))


RE_LINE_TABLE = re.compile(r"^\s*(\w+)\s*=\s*(?:\{\s*id\s*=\s*)?(\d+)\b[^-]*?(?:--\s*(.*))?$")
RE_DOT = re.compile(r"^(ChaosVfxMissile|ChaosVfx|ChaosPair51Missile)\.(\w+)\s*=\s*(?:\{\s*id\s*=\s*)?(\d+)\b[^-]*?(?:--\s*(.*))?$")
RE_TABLE_OPEN = re.compile(r"^(ChaosFx|ChaosFxMissile|ChaosVfx|ChaosVfxMissile|ChaosVfxAura)\s*=\s*\{")


def collect(root):
    effects, missiles = {}, {}
    for i, text in STOCK_EFFECTS.items():
        effects[i] = classify(text)
    for i, text in STOCK_MISSILES.items():
        missiles[i] = classify(text)
    cat = os.path.join(root, "server", "data", "spells", "effects_catalog.csv")
    if os.path.isfile(cat):
        with open(cat, newline="", encoding="utf-8") as f:
            for row in csv.DictReader(f):
                target = missiles if row["category"] == "missile" else effects
                target[int(row["id"])] = classify(row["name"].replace("CONST_ME_", "").replace("CONST_ANI_", ""), row["theme"] + " " + row["note"])
    for path in lua_files(root):
        table = None
        with open(path, encoding="utf-8") as f:
            for line in f:
                line = line.rstrip("\n")
                m = RE_TABLE_OPEN.match(line)
                if m:
                    table = m.group(1)
                    continue
                if table and line.startswith("}"):
                    table = None
                    continue
                m = RE_DOT.match(line)
                if m:
                    kind, name, num, comment = m.group(1), m.group(2), int(m.group(3)), m.group(4) or ""
                    (missiles if kind.endswith("Missile") or kind == "ChaosPair51Missile" else effects)[num] = classify(name, comment)
                    continue
                if table:
                    m = RE_LINE_TABLE.match(line)
                    if m and not line.strip().startswith("--"):
                        name, num, comment = m.group(1), int(m.group(2)), m.group(3) or ""
                        (missiles if table.endswith("Missile") else effects)[num] = classify(name, comment)
    return effects, missiles


def runs(table):
    out = []
    ids = sorted(table)
    i = 0
    while i < len(ids):
        j = i
        while j + 1 < len(ids) and ids[j + 1] == ids[j] + 1 and table[ids[j + 1]] == table[ids[i]]:
            j += 1
        out.append(("%d-%d%s" % (ids[i], ids[j], table[ids[i]])) if j > i else ("%d%s" % (ids[i], table[ids[i]])))
        i = j + 1
    return out


def render(effects, missiles):
    def chunk(items):
        lines, cur = [], ""
        for it in items:
            if len(cur) + len(it) > 110:
                lines.append(cur)
                cur = ""
            cur += it + ","
        if cur:
            lines.append(cur)
        return lines

    def block(name, table):
        lines = chunk(runs(table))
        body = "\n".join('            "%s" +' % l for l in lines[:-1] + [lines[-1]])
        body = body[:-2] + ";"
        return "        public const string %s =\n%s\n" % (name, body)

    return (
        "// GENERATED by unity/tools/gen_front_fx_ids.py from server/data/lib/*.lua and server/data/spells/effects_catalog.csv. Do not edit by hand.\n"
        "// The element letter of every effect id and missile id the server sends (F fire, I ice, E energy, A arcane, D death, H holy, P physical,\n"
        "// B blood, S shadow, V poison, T earth, W water, L heal, N neutral, X nothing to draw), as runs \"first-lastLetter\" or \"idLetter\".\n"
        "// %d effect ids, %d missile ids. Read by Core/FrontFx.cs (FrontFx.ElementOfEffect / ElementOfMissile).\n"
        "namespace Chaos.Core\n{\n    public static class FrontFxIds\n    {\n%s\n%s    }\n}\n"
        % (len(effects), len(missiles), block("Effects", effects), block("Missiles", missiles))
    )


def main(argv):
    root = REPO
    if "--root" in argv:
        root = argv[argv.index("--root") + 1]
    effects, missiles = collect(root)
    text = render(effects, missiles)
    path = os.path.join(root, OUT)
    if "--check" in argv:
        cur = open(path, encoding="utf-8").read() if os.path.isfile(path) else ""
        if cur != text:
            print("FrontFxIds.cs is stale: run python3 -I unity/tools/gen_front_fx_ids.py")
            return 1
        print("front fx ids: up to date (%d effects, %d missiles)" % (len(effects), len(missiles)))
        return 0
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)
    print("wrote %s: %d effects, %d missiles" % (OUT, len(effects), len(missiles)))
    from collections import Counter
    print("effects", dict(Counter(effects.values())))
    print("missiles", dict(Counter(missiles.values())))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
