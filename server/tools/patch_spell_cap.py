#!/usr/bin/env python3
"""The spell cap: every class keeps at most MAX_SPELLS (24) spells of its own (idempotent). install_all.py step `spells`, second
(after retire_cure_spells.py, before register_spells.py).

usage: python3 -I patch_spell_cap.py DATA_DIR [--dry-run]       (python3 -I patch_spell_cap.py --list prints the table)

Owner decision (2026-10-20, "mysthic tem magias demais. abaixe pra 15. faça isso pra todas as classes"): every class
and ascension (docs/CLASSES.md vocation ids) can learn and cast at most 15 spells (raised to 20 on 2026-10-23: the owner
asked for the same number of attack spells in every class, "devem ter a mesma quantidade", so every class has 10 and the
Bone Lord, the class with most other spells, reaches 20; docs/CLASSES.md "Attack spell parity"): attack, healing and support, the
stock spells it kept and the Chaos spells. Not counted (UNIVERSAL below): the 12 spells every character shares (Bloodtrail,
Ghost Rope, Wraith Step, Fleetfoot, Town Portal, Flickerdash, Hunter's Instinct, the four vigils, Banner Call), nor the two mana
shields (OUTSIDE_CAP: Ward of the Mind, the classic mana shield of the Mystic, Necromancer and Ranger lines, owner 2026-10-21, and
Soulward, its 15 s cousin of the same lines and the Templar line, owner 2026-10-28: "Deixe o mana shield somente pra classes de magia e
híbridas"). The three light spells (Lantern, Greater Lantern, Radiant Lantern) are retired for every class (retire_cure_spells.py,
owner 2026-10-28). An ascension's 15 include the base spells it keeps. The kits per class are in
docs/CLASSES.md "Spell cap"; tests/spell_cap_test.lua counts them from the repo data.

CAP names each stock instant of DATA_DIR/spells/spells.xml the cap changes, by script (rename_spells.py never changes a
script), with the classes that keep it. Every other class's <vocation> line goes from that instant; an instant left
with no class is commented out (marker "Chaos: spell cap", the original tag kept in the comment), like
retire_cure_spells.py does, and its id is free. An instant that a monster names (monster_spells.py: base and
Chaos monsters attack with player spells by name, e.g. "arc bolt", "dread") is kept in the monster-only form instead
(words "###chaos ...", needlearn="1", no vocation, no spellid; owner report 2026-10-21 "Unknown spell name: arc bolt"),
and one that an earlier run commented out comes back in that form. The Chaos block is never touched: its vocation lists are in
data/spells/chaos/spells_chaos.xml. Characters who learned a dropped spell keep the row in player_spells; the engine
refuses the cast ("You have the wrong vocation to cast this spell.") and the spellbook no longer lists it.
Needs to run after add_vocations.py (the class lists) and before register_spells.py, patch_spell_ids.py,
rename_spells.py, patch_spell_timings.py and patch_aoe_damage.py, which leave the retired spells alone.
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import monster_spells as MS  # noqa: E402

MARK = 'Chaos: spell cap (patch_spell_cap.py): '
UNIVERSAL = ("Town Portal", "Bloodtrail", "Ghost Rope", "Wraith Step", "Fleetfoot",
             "Hunter's Instinct", "Flickerdash", "Vigil of Clarity", "Vigil of Haste", "Vigil of Iron", "Vigil of Wrath",
             "Banner Call")
MAX_SPELLS = 24  # was 20 (2026-10-23): the biggest kit, Bone Lord, has 21 now (22 with its level 800 buff)
# kept by some classes but not counted in their 15 (owner 2026-10-21: the classic Magic Shield back "somente pra mages e
# rangers", the Necromancer counted as a mage; add_vocations.py LINE_STOCK_SPELLS gives it to the Mystic, Necromancer
# and Ranger lines, CAP keeps exactly those nine; Soulward, a Chaos spell, lists the same nine and the Templar line in
# spells_chaos.xml, owner 2026-10-28)
OUTSIDE_CAP = ("Ward of the Mind", "Soulward")
# script (relative to data/spells/scripts) -> (spell id, Chaos name, the classes that keep it; () = retired)
CAP = {
    'healing/light_healing.lua': (1, 'Minor Mending', ('Ranger', 'Deadeye', 'Beastmaster', 'Mystic', 'Elementalist', 'Illusionist', 'Necromancer', 'Lich', 'Bone Lord')),
    'healing/intense_healing.lua': (2, 'Deep Mending', ()),
    'healing/ultimate_healing.lua': (3, 'Grand Mending', ('Mystic', 'Elementalist', 'Necromancer', 'Lich', 'Bone Lord')),
    'support/summon_creature.lua': (9, 'Call Thrall', ()),
    'attack/energy_wave.lua': (13, 'Tempest Fan', ('Elementalist',)),
    'attack/fire_wave.lua': (19, 'Cinder Fan', ()),
    'attack/energy_beam.lua': (22, 'Stormlance', ()),
    'attack/great_energy_beam.lua': (23, 'Thunder Lance', ()),
    "attack/hell's_core.lua": (24, 'Infernal Heart', ()),
    'attack/divine_grenade.lua': (34, 'Radiant Shard', ('Ranger',)),
    'attack/grand_death_beam.lua': (35, 'Lance of the Grave', ()),
    'support/creature_illusion.lua': (38, "Skinchanger's Guise", ()),
    'support/strong_haste.lua': (39, 'Galeborne Stride', ()),  # retired 2026-10-23 (O136): the universal Vigil of Haste and Fleetfoot do the same
    'attack/ice_burst.lua': (40, 'Shatterfrost', ()),
    'attack/terra_burst.lua': (41, 'Quakeburst', ()),
    'attack/strong_ice_wave.lua': (43, 'Greater Glacier Fan', ()),
    'support/magic_shield.lua': (44, 'Ward of the Mind', ('Mystic', 'Elementalist', 'Illusionist', 'Necromancer', 'Lich', 'Bone Lord', 'Ranger', 'Deadeye', 'Beastmaster')),
    'support/invisible.lua': (45, 'Shroud of Shadows', ()),
    'support/divine_empowerment.lua': (46, 'Hallowed Ground', ('Ranger',)),
    'custom/illusionist_class/evasion.lua': (47, 'Fading Step', ()),
    'custom/illusionist_class/cruz.lua': (52, 'Crossfire Hex', ()),
    'attack/wrath_of_nature.lua': (56, 'Wildwood Ruin', ()),
    'attack/strong_ethereal_spear.lua': (57, 'Greater Phantom Javelin', ()),
    'custom/illusionist_class/fear.lua': (60, 'Dread', ()),
    'attack/annihilation.lua': (62, 'Ruinous Cleave', ()),
    'attack/berserk.lua': (80, "Reaver's Spin", ()),
    'healing/mass_healing.lua': (82, 'Circle of Mending', ()),
    'healing/heal_friend.lua': (84, 'Kindred Mend', ()),
    'attack/death_strike.lua': (87, 'Gravetouch', ()),
    'attack/energy_strike.lua': (88, 'Arc Bolt', ()),
    'attack/flame_strike.lua': (89, 'Ember Lash', ()),
    'support/cancel_invisibility.lua': (90, 'Unveil', ()),
    'support/challenge.lua': (93, 'Taunt of Iron', ('Juggernaut',)),
    'healing/natures_embrace.lua': (101, 'Heartwood Embrace', ()),
    'healing/restoration.lua': (103, 'Rebirth of Flesh', ('Necromancer', 'Lich', 'Bone Lord')),
    'attack/groundshaker.lua': (106, 'Earthrend', ()),
    'attack/whirlwind_throw.lua': (107, 'Cyclone Hurl', ()),
    'attack/ice_strike.lua': (112, 'Frostbite', ()),
    'attack/terra_strike.lua': (113, 'Thornlash', ()),
    'attack/eternal_winter.lua': (118, 'Endless Rime', ()),
    'attack/rage_of_the_skies.lua': (119, "Storm Crown's Wrath", ()),
    'attack/terra_wave.lua': (120, 'Bramble Fan', ()),
    'attack/ice_wave.lua': (121, 'Glacier Fan', ()),
    'attack/divine_missile.lua': (122, 'Dawnbolt', ()),
    'party/train_party.lua': (126, 'Martial Communion', ()),
    'party/protect_party.lua': (127, 'Shielding Communion', ()),
    'party/heal_party.lua': (128, 'Mending Communion', ()),
    'party/enchant_party.lua': (129, 'Arcane Communion', ()),
    'support/charge.lua': (131, 'Warhorse Rush', ()),
    'support/blood_rage.lua': (133, 'Bloodlust', ('Warrior', 'Berserker')),
    'attack/ignite.lua': (138, 'Smoulder Brand', ()),
    'attack/curse.lua': (139, 'Hex of Withering', ()),
    'attack/electrify.lua': (140, 'Galvanic Mark', ()),
    'attack/inflict_wound.lua': (141, 'Rending Mark', ()),
    'attack/envenom.lua': (142, 'Blackroot Venom', ()),
    'attack/holy_flash.lua': (143, 'Glare of Dawn', ()),
    'attack/physical_strike.lua': (148, 'Hammerfall Palm', ()),
    'attack/lightning.lua': (149, 'Skyfang', ()),
    'attack/strong_flame_strike.lua': (150, 'Greater Ember Lash', ()),
    'attack/strong_energy_strike.lua': (151, 'Greater Arc Bolt', ()),
    'attack/strong_ice_strike.lua': (152, 'Greater Frostbite', ()),
    'attack/strong_terra_strike.lua': (153, 'Greater Thornlash', ()),
    'attack/ultimate_flame_strike.lua': (154, 'Supreme Ember Lash', ()),
    'attack/ultimate_energy_strike.lua': (155, 'Supreme Arc Bolt', ()),
    'attack/ultimate_ice_strike.lua': (156, 'Supreme Frostbite', ()),
    'attack/ultimate_terra_strike.lua': (157, 'Supreme Thornlash', ()),
    'healing/intense_wound_cleansing.lua': (158, "Warlord's Resolve", ()),
    'healing/recovery.lua': (159, 'Second Wind', ()),
    'healing/intense_recovery.lua': (160, 'Greater Second Wind', ()),
    'attack/great_fire_wave.lua': (163, 'Pyre Torrent', ('Elementalist',)),
    'custom/illusionist_class/adento_grav.lua': (165, 'Gravity Snare', ()),
    'custom/illusionist_class/arcane_strike.lua': (168, 'Riftbolt', ()),
    'attack/expose_weakness.lua': (171, 'Sunder Guard', ()),
    'attack/mud_attack.lua': (172, 'Bog Splatter', ()),
    'attack/chill_out.lua': (173, 'Rime Breath', ()),
    'healing/magic_patch.lua': (174, 'Arcane Stitch', ()),
    'attack/buzz.lua': (177, 'Static Sting', ()),
    'attack/scorch.lua': (178, 'Searing Gust', ()),
    'support/chivalrous_challenge.lua': (237, "Duelist's Oath", ()),
}
RETIRED_IDS = sorted(sid for sid, _, keep in CAP.values() if not keep)
TAG = re.compile(r'<instant\b[^>]*?(?:/>|>.*?</instant>)', re.S)
VOC = re.compile(r'[ \t]*<vocation\s+name="([^"]+)"[^>]*/>[ \t]*(?:\r?\n)?')


def patch(text, needed=frozenset()):
    """(new text, classes taken off, spells retired, spells kept for monsters); comments (earlier retirements) and
    the Chaos block stay. needed: lowercased instant names a monster uses (monster_spells.needed_names): such a spell
    is not commented out but gets the monster-only form, and an earlier retirement comment of one comes back in it."""
    text, kept = MS.restore(text, needed)
    chaos_a = text.find('<!-- BEGIN chaos spells')
    chaos_b = text.find('<!-- END chaos spells -->')
    removed = retired = 0
    out, pos = [], 0
    for m in re.finditer(r'<!--.*?-->|' + TAG.pattern, text, re.S):
        tag = m.group(0)
        if tag.startswith('<!--') or (chaos_a != -1 and chaos_a <= m.start() < chaos_b):
            continue
        script = re.search(r'\bscript="([^"]*)"', tag)
        if not script or script.group(1) not in CAP:
            continue
        keep = CAP[script.group(1)][2]
        if not keep and MS.is_monster_only(tag) and MS.needs(tag, needed):
            continue
        out.append(text[pos:m.start()])
        if not keep:
            out.append(MS.retire(text, m, MARK, needed))
            if MS.needs(tag, needed):
                kept += 1
            else:
                retired += 1
        else:
            def drop(v):
                return '' if v.group(1) not in keep else v.group(0)
            new = VOC.sub(drop, tag)
            removed += len(VOC.findall(tag)) - len(VOC.findall(new))
            out.append(new)
        pos = m.end()
    out.append(text[pos:])
    return MS.tidy(''.join(out)), removed, retired, kept


def main(argv):
    if '--list' in argv:
        for script, (sid, name, keep) in sorted(CAP.items(), key=lambda kv: kv[1][0]):
            print('%3d  %-24s %-44s %s' % (sid, name, script, ', '.join(keep) or 'retired'))
        return 0
    args = [a for a in argv if not a.startswith('--')]
    if len(args) != 1:
        print(__doc__)
        return 1
    path = os.path.join(args[0], 'spells', 'spells.xml')
    if not os.path.isfile(path):
        print('missing file: ' + path)
        return 1
    text = open(path, encoding='utf-8', errors='surrogateescape', newline='').read()
    new, removed, retired, kept = patch(text, MS.needed_names(args[0]))
    dry = '--dry-run' in argv
    if new != text and not dry:
        open(path, 'w', encoding='utf-8', errors='surrogateescape', newline='').write(new)
    if new == text:
        print('spell cap: nothing to change')
    else:
        print('spell cap: %d class entries removed, %d spells retired, %d kept or brought back for monsters only%s'
              % (removed, retired, kept, ' (dry run)' if dry else ''))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
