#!/usr/bin/env python3
"""The Drops channel of the server drop feed (O260; data/scripts/chaos/retention_loot.lua).

usage: python3 -I patch_drops_channel.py DATA_DIR [--dry-run]

Adds  <channel id="21" name="Drops" public="1" script="drops.lua" />  to data/chatchannels/chatchannels.xml and writes
data/chatchannels/scripts/drops.lua: a read-only channel; joining and leaving tell ChaosRetentionLoot, which posts each
legendary / divine / unique drop line into it (and into the Default tab of everyone online). Nobody can speak in it.
Idempotent: a channel that is there is left alone (a different channel on the same id is an error), the script is
written only when it is not there (a script with the marker is ours and stays). The id and name are the ones of retention_loot_config.lua (feed.channelId, channelName).
"""
import os
import re
import sys

CHANNEL_ID = 21
CHANNEL_NAME = 'Drops'
SCRIPT = 'drops.lua'
MARKER = '-- Chaos: the Drops channel (patch_drops_channel.py)'

SCRIPT_TEXT = MARKER + '''
-- Read-only: the lines are posted by data/scripts/chaos/retention_loot.lua. Joining registers the player for them.
function canJoin(player)
	return true
end

function onJoin(player)
	if ChaosRetentionLoot and ChaosRetentionLoot.channelJoin then
		ChaosRetentionLoot.channelJoin(player)
	end
	return true
end

function onLeave(player)
	if ChaosRetentionLoot and ChaosRetentionLoot.channelLeave then
		ChaosRetentionLoot.channelLeave(player)
	end
	return true
end

function onSpeak(player, type, message)
	local text = "Nobody can speak in the Drops channel."
	if Chaos and Chaos.t then
		text = Chaos.t(player, text)
	end
	player:sendCancelMessage(text)
	return false
end
'''


def line_for(indent):
    return '%s<channel id="%d" name="%s" public="1" script="%s" />' % (indent, CHANNEL_ID, CHANNEL_NAME, SCRIPT)


def patch_xml(text):
    """returns (new text, status): 'patched', 'already' or an error message"""
    ids = {}
    for m in re.finditer(r'<channel\b[^>]*>', text):
        tag = m.group(0)
        i = re.search(r'\bid="(\d+)"', tag)
        n = re.search(r'\bname="([^"]*)"', tag)
        if i:
            ids[int(i.group(1))] = n.group(1) if n else ''
    if ids.get(CHANNEL_ID) == CHANNEL_NAME:
        return text, 'already'
    if CHANNEL_ID in ids:
        return text, 'id %d is used by the channel "%s"' % (CHANNEL_ID, ids[CHANNEL_ID])
    if CHANNEL_NAME in ids.values():
        return text, 'a channel named "%s" is there under another id' % CHANNEL_NAME
    end = re.search(r'^([ \t]*)</channels>', text, re.M)
    if not end:
        return text, '</channels> not found'
    nl = '\r\n' if '\r\n' in text else '\n'
    child = re.search(r'^([ \t]+)<channel\b', text, re.M)
    indent = child.group(1) if child else '\t'
    at = end.start()
    return text[:at] + line_for(indent) + nl + text[at:], 'patched'


def main(argv):
    args = [a for a in argv if not a.startswith('--')]
    dry = '--dry-run' in argv
    if len(args) != 1:
        print(__doc__.strip().splitlines()[2])
        return 2
    data = args[0]
    xml = os.path.join(data, 'chatchannels', 'chatchannels.xml')
    try:
        with open(xml, encoding='utf-8', errors='surrogateescape', newline='') as f:
            text = f.read()
    except OSError as e:
        print('chatchannels.xml: %s' % e)
        return 1
    new, st = patch_xml(text)
    if st not in ('patched', 'already'):
        print('chatchannels.xml: %s' % st)
        return 1
    if st == 'patched' and not dry:
        with open(xml, 'w', encoding='utf-8', errors='surrogateescape', newline='') as f:
            f.write(new)
    print('chatchannels.xml (%s): %s%s' % (CHANNEL_NAME, st, ' (dry run, not written)' if dry and st == 'patched' else ''))
    path = os.path.join(data, 'chatchannels', 'scripts', SCRIPT)
    old = None
    if os.path.isfile(path):
        with open(path, encoding='utf-8', errors='surrogateescape', newline='') as f:
            old = f.read()
    if old is not None and MARKER in old:  # ours (other patches may have added a hook to it): left alone
        print('chatchannels/scripts/%s: already' % SCRIPT)
    else:
        if not dry:
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, 'w', encoding='utf-8', errors='surrogateescape', newline='') as f:
                f.write(SCRIPT_TEXT)
        print('chatchannels/scripts/%s: %s%s' % (SCRIPT, 'written' if old is None else 'updated',
                                                 ' (dry run, not written)' if dry else ''))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
