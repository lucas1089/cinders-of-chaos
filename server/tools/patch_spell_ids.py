#!/usr/bin/env python3
"""Give the base spells whose spellid does not fit in a byte (or is used twice) their own id below 256 (idempotent).

usage: python3 -I patch_spell_ids.py DATA_DIR [--dry-run]

The engine keeps a spell's id in one byte (Spell::spellId is uint8_t; spells.xml spellid is read as a number and cut
to 8 bits) and the 10.98 cooldown packet sends it as one byte too. A base spell with spellid 258 is spell 2 for the
engine: casting Radiant Shard put Deep Mending (2) on its 26 s cooldown, Arcane Ripple (394) locked Smoulder Brand
(138), and the client (helper, action bar) showed the cooldown on the wrong spell. Two base spells also share id 106.
Each spell below is found by its script (the names are changed by rename_spells.py, the scripts are not) and gets a fixed
id that no other spell of the base server, the Chaos block or the client's spell table uses (client
overlay game_chaosspells/spellfix.lua uses the same ids). Three base scripts also start their own cooldown condition
with the old id as sub id; that number is changed with it.
Refuses (exit 1) when a new id is already taken by another spell or a script is missing from spells.xml. A spell the
15-spell cap retired (patch_spell_cap.py, a comment by then) is not missing: it keeps no id.
"""
import os, re, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from patch_spell_cap import CAP  # noqa: E402
CAP_RETIRED = {script for script, (_, _, keep) in CAP.items() if not keep}

# script (relative to data/spells/scripts) -> new spellid; old id in the comment
NEW_IDS = {
    'attack/divine_grenade.lua': 34,                    # 258 Radiant Shard
    'attack/grand_death_beam.lua': 35,                  # 260 Lance of the Grave
    'attack/executioners_throw.lua': 37,                # 261 Headsman's Hurl
    'attack/ice_burst.lua': 40,                         # 262 Shatterfrost
    'attack/terra_burst.lua': 41,                       # 263 Quakeburst
    'support/divine_empowerment.lua': 46,               # 268 Hallowed Ground
    'custom/illusionist_class/evasion.lua': 47,         # 389 Fading Step
    'custom/illusionist_class/cruz.lua': 52,            # 390 Crossfire Hex
    'custom/illusionist_class/bewitched_curse.lua': 53, # 391 Bewitching Hex
    'custom/illusionist_class/fear.lua': 60,            # 393 Dread
    'custom/illusionist_class/arcane_wave.lua': 85,     # 394 Arcane Ripple
    'custom/illusionist_class/adento_grav.lua': 165,    # 396 Gravity Snare
    'custom/illusionist_class/arcane_strike.lua': 168,  # 397 Riftbolt
    'attack/expose_weakness.lua': 171,                  # 106 Sunder Guard (Earthrend keeps 106)
}
# scripts that add their own cooldown condition: Condition(CONDITION_SPELLCOOLDOWN, CONDITIONID_DEFAULT, <old id>)
SUB_IDS = {
    'attack/divine_grenade.lua': (258, 34),
    'attack/executioners_throw.lua': (261, 37),
    'support/divine_empowerment.lua': (268, 46),
}
SPELL = re.compile(r'<(instant|rune|conjure)\b[^>]*>')


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    dry = '--dry-run' in sys.argv
    if not args:
        sys.exit(__doc__)
    data = os.path.abspath(args[0])
    xml_path = os.path.join(data, 'spells', 'spells.xml')
    if not os.path.isfile(xml_path):
        sys.exit(f'missing file: {xml_path}')
    raw = open(xml_path, 'rb').read()
    text = raw.decode('latin-1')  # byte for byte: the file mixes encodings

    found, changed, errors = {}, 0, []
    taken = {}
    for m in SPELL.finditer(re.sub(r'<!--.*?-->', lambda c: ' ' * len(c.group(0)), text, flags=re.S)):
        tag = m.group(0)
        sid = re.search(r'\bspellid="(\d+)"', tag)
        script = re.search(r'\bscript="([^"]*)"', tag)
        if not sid:
            continue
        if script and script.group(1) in NEW_IDS:
            found[script.group(1)] = (m.start(), m.end())
        else:
            taken.setdefault(int(sid.group(1)), []).append(script.group(1) if script else '?')
    for script, new in NEW_IDS.items():
        if script not in found and script not in CAP_RETIRED:
            errors.append(f'{script}: no spell with this script in spells.xml')
        if new in taken:
            errors.append(f'{script}: spellid {new} is already used by {", ".join(taken[new])}')
    if errors:
        sys.exit('refusing to renumber spells:\n  ' + '\n  '.join(errors))

    out, last = [], 0
    for script, (a, b) in sorted(found.items(), key=lambda kv: kv[1][0]):
        tag = text[a:b]
        new_tag = re.sub(r'\bspellid="\d+"', f'spellid="{NEW_IDS[script]}"', tag, count=1)
        if new_tag != tag:
            changed += 1
        out.append(text[last:a])
        out.append(new_tag)
        last = b
    out.append(text[last:])
    new_text = ''.join(out)

    scripts_changed = 0
    for script, (old, new) in SUB_IDS.items():
        path = os.path.join(data, 'spells', 'scripts', script)
        if not os.path.isfile(path):
            continue
        s = open(path, 'rb').read().decode('latin-1')
        t = re.sub(r'(CONDITION_SPELLCOOLDOWN,\s*CONDITIONID_DEFAULT,\s*)%d\)' % old, r'\g<1>%d)' % new, s)
        if t != s:
            scripts_changed += 1
            if not dry:
                open(path, 'wb').write(t.encode('latin-1'))
    if new_text != text and not dry:
        open(xml_path, 'wb').write(new_text.encode('latin-1'))
    print(f'{"[dry-run] " if dry else ""}{changed} spell id(s) changed in {xml_path}; '
          f'{scripts_changed} script cooldown sub id(s) changed')


if __name__ == '__main__':
    main()
