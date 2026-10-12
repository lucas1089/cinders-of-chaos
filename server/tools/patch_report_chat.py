#!/usr/bin/env python3
"""Player reports: the last lines of a character in the PUBLIC chat channels (data/scripts/chaos/reports.lua).

usage: python3 -I patch_report_chat.py DATA_DIR [--dry-run]

Every channel of data/chatchannels/chatchannels.xml with public="1" and a script: its onSpeak calls
ChaosReports.onChannelSpeak(player, "<channel name>", type, message) right after the level check (else at the top).
reports.lua keeps the last few lines per character in memory and stores them with a report about that character.
Private messages and non-public channels are never touched. Idempotent: the change carries a marker and is not made
twice. Run it again after replacing a base channel script.
"""
import os
import re
import sys
import xml.etree.ElementTree as ET

MARKER = '-- Chaos: last public lines for player reports (patch_report_chat.py)'


def hook(name):
    return ('\t' + MARKER + '\n'
            '\tif ChaosReports and ChaosReports.onChannelSpeak then ChaosReports.onChannelSpeak(player, "%s", type, message) end\n'
            '\n') % name


def safe_name(name):
    return re.sub(r'[^A-Za-z0-9 \-]', '', name or '')[:24] or 'Channel'


def patch(text, name):
    """returns (new text, status) with status 'patched', 'already' or an error message"""
    if MARKER in text:
        return text, 'already'
    m = re.search(r'function onSpeak\(player, type, message\)[ \t]*\r?\n', text)
    if not m:
        return text, 'no onSpeak(player, type, message), skipped'
    level = re.search(r'if player:getLevel\(\) == 1.*?\r?\n\t\treturn false\r?\n\tend\r?\n\r?\n', text[m.end():], re.S)
    at = m.end() + level.end() if level else m.end()
    h = hook(safe_name(name))
    if '\r\n' in text:
        h = h.replace('\n', '\r\n')
    return text[:at] + h + text[at:], 'patched'


def public_channels(data):
    xml = os.path.join(data, 'chatchannels', 'chatchannels.xml')
    root = ET.parse(xml).getroot()
    out = []
    for ch in root.iter('channel'):
        if ch.get('public') in ('1', 'true', 'yes') and ch.get('script'):
            out.append((ch.get('name') or '', ch.get('script')))
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
    for name, script in channels:
        rel = os.path.join('chatchannels', 'scripts', script)
        path = os.path.join(data, rel)
        if not os.path.isfile(path):
            print('%s: not found, skipped' % rel)
            continue
        with open(path, encoding='utf-8', errors='surrogateescape', newline='') as f:
            text = f.read()
        new, st = patch(text, name)
        if st == 'patched' and not dry:
            with open(path, 'w', encoding='utf-8', errors='surrogateescape', newline='') as f:
                f.write(new)
        print('%s (%s): %s%s' % (rel, name, st, ' (dry run, not written)' if dry and st == 'patched' else ''))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
