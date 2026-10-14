#!/usr/bin/env python3
"""Guard for engine src-patch 0032: the NetworkMessage buffer is not value-initialised again by a later patch.

0007 made it `uint8_t buffer[NETWORKMESSAGE_MAXSIZE] = {};`. With this engine's NETWORKMESSAGE_MAXSIZE (90459) every
NetworkMessage on the stack then copied 90 KB of zeros (one per packet piece the game sends) and every new OutputMessage
was cleared, 90 KB, by the value-initialisation of allocate_shared (OutputMessage() = default): about a quarter of the
game loop at 300 online in the full-map load test (server/README.md "Load test on the full map"). 0032 takes the
initialiser out and gives OutputMessage a user-provided constructor. This test reads the patch chain in order and checks
that the last patch that writes the buffer line writes it without an initialiser, and that the last one that writes the
OutputMessage default constructor makes it user-provided.

Run: python3 -I server/tools/netmsg_buffer_patch_test.py (standard library only)."""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PATCHES = os.path.join(HERE, '..', 'src-patches')
LINE = re.compile(r'^([+-])\s*uint8_t buffer\[NETWORKMESSAGE_MAXSIZE\](.*?);\s*$')
CTOR = re.compile(r'^\+\s*OutputMessage\(\)\s*(.*?)\s*$')


def buffer_lines(text):
    """[(sign, initialiser)] of the buffer declaration lines a patch removes (-) or adds (+) in src/networkmessage.h"""
    out, inside = [], False
    for line in text.splitlines():
        if line.startswith('+++ ') or line.startswith('--- '):
            inside = line[4:].split()[0].endswith('src/networkmessage.h') if line.startswith('+++ ') else inside
            continue
        if inside:
            m = LINE.match(line)
            if m:
                out.append((m.group(1), m.group(2).strip()))
    return out


def ctor_lines(text):
    """the OutputMessage default constructor lines a patch adds in src/outputmessage.h ("= default;", "{}")"""
    out, inside = [], False
    for line in text.splitlines():
        if line.startswith('+++ '):
            inside = line[4:].split()[0].endswith('src/outputmessage.h')
        elif inside and CTOR.match(line):
            out.append(CTOR.match(line).group(1))
    return out


def main():
    fails = []
    last = None
    ctor = None
    for name in sorted(os.listdir(PATCHES)):
        if not re.match(r'^\d{4}-.*\.patch$', name):
            continue
        with open(os.path.join(PATCHES, name), errors='replace') as f:
            text = f.read()
        lines = buffer_lines(text)
        for c in ctor_lines(text):
            ctor = (name, c)
        for sign, init in lines:
            if sign == '+':
                last = (name, init)
        if name.startswith('0007-') and ('+', '= {}') not in lines:
            fails.append('0007 no longer adds the zeroed buffer (update this test with the chain)')
        if name.startswith('0032-') and lines != [('-', '= {}'), ('+', '')]:
            fails.append('0032 must replace the zeroed buffer line by a plain one, has %r' % lines)
    if last is None:
        fails.append('no patch declares the NetworkMessage buffer')
    elif last[1]:
        fails.append('%s declares the buffer with the initialiser %r (90 KB copied per message sent)' % last)
    if ctor is None or ctor[1] != '{}':
        fails.append('OutputMessage needs a user-provided default constructor (allocate_shared clears 90 KB), last: %r'
                     % (ctor,))
    for f in fails:
        print('FAIL ' + f)
    print('netmsg_buffer_patch_test: last buffer line from %s, %d failure(s)' % (last[0] if last else '-', len(fails)))
    return 1 if fails else 0


if __name__ == '__main__':
    sys.exit(main())
