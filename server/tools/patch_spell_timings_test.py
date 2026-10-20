#!/usr/bin/env python3
"""Test of patch_spell_timings.py: every csv row lands on its base instant (the Chaos block untouched), the two base
scripts with their own cooldown condition follow the csv cooldown (Radiant Shard in seconds, Headsman's Hurl in ms; the
base had 26 s and (18000 * 1000) ms, five hours), a second run changes nothing, --dry-run writes nothing.
Run: python3 -I server/tools/patch_spell_timings_test.py"""
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.dont_write_bytecode = True
import patch_spell_timings as T  # noqa: E402

fails = []


def check(c, what):
    if not c:
        fails.append(what)
        print('FAIL ' + what)


rows = T.load()
cd = {r['script']: r['cooldown'] for r in rows}
xml = '<spells>\n'
for i, r in enumerate(rows):
    xml += '\t<instant group="attack" spellid="%d" name="%s" words="w%d" cooldown="1" groupcooldown="9000" script="%s">' \
           '\n\t</instant>\n' % (i + 1, r['name'], i, r['script'])
xml += '\t<!-- BEGIN chaos spells (x) -->\n\t<instant group="attack" spellid="250" name="C" words="c" cooldown="1" ' \
       'script="%s">\n\t</instant>\n\t<!-- END chaos spells -->\n</spells>\n' % rows[0]['script']
GRENADE = ('function onCastSpell(creature, var)\n    local cooldown = 26 -- Fixed cooldown\n'
           '        condition:setTicks((cooldown * 1000))\nend\n')
THROW = 'function onCastSpell(creature, variant)\n        condition:setTicks((18000 * 1000)/ 1)\nend\n'
with tempfile.TemporaryDirectory() as tmp:
    os.makedirs(os.path.join(tmp, 'spells', 'scripts', 'attack'))
    sp = os.path.join(tmp, 'spells', 'spells.xml')
    open(sp, 'w').write(xml)
    g = os.path.join(tmp, 'spells', 'scripts', 'attack', 'divine_grenade.lua')
    t = os.path.join(tmp, 'spells', 'scripts', 'attack', 'executioners_throw.lua')
    open(g, 'w').write(GRENADE)
    open(t, 'w').write(THROW)
    tool = os.path.join(HERE, 'patch_spell_timings.py')
    r = subprocess.run([sys.executable, '-I', tool, tmp, '--dry-run'], capture_output=True, text=True)
    check(r.returncode == 0 and open(sp).read() == xml and open(g).read() == GRENADE and open(t).read() == THROW,
          'dry run writes nothing: ' + r.stdout + r.stderr)
    r = subprocess.run([sys.executable, '-I', tool, tmp], capture_output=True, text=True)
    check(r.returncode == 0, 'run: ' + r.stdout + r.stderr)
    out = open(sp).read()
    for row in rows:
        if row['cooldown']:
            check('cooldown="%s" groupcooldown="%s"' % (row['cooldown'], row['groupcooldown'] or '9000') in out
                  or 'cooldown="%s"' % row['cooldown'] in out, row['name'] + ': cooldown')
    check('name="C" words="c" cooldown="1"' in out, 'the Chaos block is untouched')
    gtext, ttext = open(g).read(), open(t).read()
    check('local cooldown = %d -- Fixed cooldown' % (int(cd['attack/divine_grenade.lua']) // 1000) in gtext,
          'Radiant Shard script cooldown: ' + gtext)
    check('condition:setTicks(%s)' % cd['attack/executioners_throw.lua'] in ttext, "Headsman's Hurl script ticks: " + ttext)
    r = subprocess.run([sys.executable, '-I', tool, tmp], capture_output=True, text=True)
    check('0 change(s)' in r.stdout and open(g).read() == gtext and open(t).read() == ttext, 'second run: ' + r.stdout)
    os.remove(os.path.join(tmp, 'spells', 'spells.xml'))
    open(sp, 'w').write('<spells>\n</spells>\n')
    r = subprocess.run([sys.executable, '-I', tool, tmp], capture_output=True, text=True)
    check(r.returncode == 1, 'a csv script missing from spells.xml: refused')

if fails:
    print('%d failure(s)' % len(fails))
    sys.exit(1)
print('patch_spell_timings_test: OK (%d rows)' % len(rows))
