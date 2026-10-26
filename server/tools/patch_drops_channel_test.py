#!/usr/bin/env python3
"""Test of patch_drops_channel.py on synthetic chatchannels.xml copies (no game data in the repo).

    python3 -I server/tools/patch_drops_channel_test.py

The channel is added once, a second run changes nothing, CRLF and the indent are kept, a taken id or name is refused and
left alone, a dry run writes nothing, the script is written and parses, and the id and name are the config's.
"""
import os
import re
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.dont_write_bytecode = True
import patch_drops_channel as P  # noqa: E402

fails = []


def check(cond, what):
    if not cond:
        fails.append(what)


STOCK = ('<?xml version="1.0" encoding="UTF-8"?>\n<channels>\n'
         '\t<channel id="1" name="Guild" public="0" />\n'
         '\t<channel id="4" name="Help" public="1" script="help.lua" />\n'
         '</channels>\n')

new, st = P.patch_xml(STOCK)
check(st == 'patched', 'patched (%s)' % st)
check(new.count('name="Drops"') == 1, 'one Drops channel')
check('\t<channel id="21" name="Drops" public="1" script="drops.lua" />\n</channels>' in new, 'indent and place')
again, st2 = P.patch_xml(new)
check(st2 == 'already' and again == new, 'second run changes nothing (%s)' % st2)

crlf, st = P.patch_xml(STOCK.replace('\n', '\r\n'))
check(st == 'patched' and '\r\n</channels>' in crlf and '\n' not in crlf.replace('\r\n', ''), 'CRLF kept')

taken = STOCK.replace('id="4"', 'id="21"')
same, st = P.patch_xml(taken)
check(st.startswith('id 21 is used') and same == taken, 'a taken id is refused (%s)' % st)
named = STOCK.replace('name="Help"', 'name="Drops"')
same, st = P.patch_xml(named)
check('another id' in st and same == named, 'a taken name is refused (%s)' % st)
same, st = P.patch_xml('<channels>\n')
check('not found' in st, 'no closing tag is refused')

# the whole tool on a folder
with tempfile.TemporaryDirectory() as d:
    os.makedirs(os.path.join(d, 'chatchannels', 'scripts'))
    xml = os.path.join(d, 'chatchannels', 'chatchannels.xml')
    with open(xml, 'w') as f:
        f.write(STOCK)
    check(P.main([d, '--dry-run']) == 0, 'dry run ok')
    with open(xml) as f:
        check(f.read() == STOCK, 'a dry run writes nothing')
    check(not os.path.exists(os.path.join(d, 'chatchannels', 'scripts', 'drops.lua')), 'a dry run writes no script')
    check(P.main([d]) == 0, 'run ok')
    check(P.main([d]) == 0, 'second run ok')
    with open(xml) as f:
        check(f.read().count('name="Drops"') == 1, 'one channel after two runs')
    with open(os.path.join(d, 'chatchannels', 'scripts', 'drops.lua')) as f:
        check(f.read() == P.SCRIPT_TEXT, 'the script is written')
    check(P.main([os.path.join(d, 'nothing')]) == 1, 'a missing folder fails')

for fn in ('canJoin', 'onJoin', 'onLeave', 'onSpeak'):
    check('function %s(' % fn in P.SCRIPT_TEXT, 'script has ' + fn)
check('return false' in P.SCRIPT_TEXT.split('function onSpeak')[1], 'nobody speaks')

# the config says the same id and name
cfg = os.path.join(HERE, '..', 'data', 'scripts', 'chaos', 'retention_loot_config.lua')
with open(cfg) as f:
    src = f.read()
m = re.search(r'channelId = (\d+)', src)
n = re.search(r'channelName = "([^"]+)"', src)
s = re.search(r'channelScript = "([^"]+)"', src)
check(m and int(m.group(1)) == P.CHANNEL_ID, 'channel id matches the config')
check(n and n.group(1) == P.CHANNEL_NAME, 'channel name matches the config')
check(s and s.group(1) == P.SCRIPT, 'channel script matches the config')

if fails:
    print('FAILED:')
    for x in fails:
        print('  ' + x)
    sys.exit(1)
print('patch_drops_channel_test: all checks passed')
