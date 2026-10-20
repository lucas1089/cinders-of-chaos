#!/usr/bin/env python3
"""Shadow mute: the hook in the PUBLIC chat channel scripts (data/scripts/chaos/shadow_mute.lua).

usage: python3 -I patch_shadow_mute.py DATA_DIR [--dry-run]

Every channel of data/chatchannels/chatchannels.xml with public="1" and a script: the first lines of its onSpeak call
ChaosShadowMute.onChannelSpeak(player, <channel id>, type, message); when it returns true (the character is
shadow-muted, its line was shown to itself only) onSpeak returns false. Private messages, non-public channels and normal
speech are not touched. Idempotent: the change carries a marker and is not made twice. Run it again after replacing a
base channel script (install_all.py runs it after patch_report_chat.py).
"""
import os
import re
import sys
import xml.etree.ElementTree as ET

MARKER = '-- Chaos: shadow mute (patch_shadow_mute.py)'


def hook(channel_id):
    return ('\t' + MARKER + '\n'
            '\tif ChaosShadowMute and ChaosShadowMute.onChannelSpeak and ChaosShadowMute.onChannelSpeak(player, %d, type, message) then\n'
            '\t\treturn false\n'
            '\tend\n'
            '\n') % channel_id


def patch(text, channel_id):
    """returns (new text, status) with status 'patched', 'already' or an error message"""
    if MARKER in text:
        return text, 'already'
    m = re.search(r'function onSpeak\(player, type, message\)[ \t]*\r?\n', text)
    if not m:
        return text, 'no onSpeak(player, type, message), skipped'
    h = hook(channel_id)
    if '\r\n' in text:
        h = h.replace('\n', '\r\n')
    return text[:m.end()] + h + text[m.end():], 'patched'


def public_channels(data):
    xml = os.path.join(data, 'chatchannels', 'chatchannels.xml')
    root = ET.parse(xml).getroot()
    out = []
    for ch in root.iter('channel'):
        if ch.get('public') in ('1', 'true', 'yes') and ch.get('script') and (ch.get('id') or '').isdigit():
            out.append((ch.get('name') or '', ch.get('script'), int(ch.get('id'))))
    return out


def main(argv):
    args = [a for a in argv if not a.startswith('--')]
    dry = '--dry-run' in argv
    if len(args) != 1:
        print(__doc__.strip().splitlines()[2])
        return 2
    data = args[0]
    try:
        channels = public_channels(data)
    except (OSError, ET.ParseError) as e:
        print('chatchannels.xml: %s' % e)
        return 1
    for name, script, cid in channels:
        rel = os.path.join('chatchannels', 'scripts', script)
        path = os.path.join(data, rel)
        if not os.path.isfile(path):
            print('%s: not found, skipped' % rel)
            continue
        with open(path, encoding='utf-8', errors='surrogateescape', newline='') as f:
            text = f.read()
        new, st = patch(text, cid)
        if st == 'patched' and not dry:
            with open(path, 'w', encoding='utf-8', errors='surrogateescape', newline='') as f:
                f.write(new)
        print('%s (%s): %s%s' % (rel, name, st, ' (dry run, not written)' if dry and st == 'patched' else ''))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
