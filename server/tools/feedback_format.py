#!/usr/bin/env python3
"""Bug reports and suggestions as plain text (chaos-ctl.sh feedback; docs/ADMIN_APP.md "Bugs e sugestoes").

Reads the tab separated rows of the fixed query of chaos-ctl.sh on stdin (mysql -N -B):
  id, created_at, note, pos_x, pos_y, pos_z, chat, status, staff_note, reporter_name
and prints one block per report, newest first as given:

  #12 | 2026-10-27 14:03 UTC | map | open | pos 1010,990,7 | lvl 120 Mystic
    the text
    from: NAME            (only with --names; the query leaves the name empty otherwise)
    closed: staff note    (closed reports)

No account id, IP or e-mail is ever read from the database or printed. Every text is stripped of control and format
characters (also the bidi controls) and capped. The same format is parsed by the admin app (FeedbackInfo.java).
usage: feedback_format.py [--names]    (python3 -I)
"""
import re
import sys
import unicodedata
from datetime import datetime, timezone

CATEGORIES = ('map', 'typo', 'technical', 'other', 'suggestion')
TEXT_MAX = 400
NOTE_MAX = 200


def unescape(s):
    """mysql -B escapes \\ as \\\\, newline as \\n, tab as \\t, NUL as \\0"""
    def one(m):
        c = m.group(1)
        return {'n': '\n', 't': ' ', '0': '', 'r': ' '}.get(c, c)
    return re.sub(r'\\(.)', one, s, flags=re.S)


def clean(s, cap):
    s = ''.join(' ' if c in '\n\r\t' else c for c in s)
    s = ''.join(c for c in s if unicodedata.category(c) not in ('Cc', 'Cf', 'Cs', 'Co', 'Cn') or c == ' ')
    s = re.sub(r' +', ' ', s).strip()
    return s[:cap].rstrip()


def level_voc(chat):
    for line in chat.split('\n'):
        m = re.match(r'Level (\d{1,5}), (.{1,32})$', line.strip())
        if m:
            return int(m.group(1)), clean(m.group(2), 32)
    return None, ''


def num(s):
    return int(s) if re.fullmatch(r'\d{1,10}', s or '') else 0


def block(f, names):
    f = (f + [''] * 10)[:10]
    rid, at, note, px, py, pz, chat, status, staff, who = f
    note = clean(unescape(note), TEXT_MAX + 20)
    m = re.match(r'\[([a-z]{3,12})\] ?(.*)$', note)
    cat, text = (m.group(1), m.group(2)) if m else ('other', note)
    if cat not in CATEGORIES:
        cat, text = 'other', note
    text = text[:TEXT_MAX].rstrip()
    when = datetime.fromtimestamp(num(at), timezone.utc).strftime('%Y-%m-%d %H:%M UTC')
    lvl, voc = level_voc(unescape(chat))
    head = ['#%d' % num(rid), when, cat, 'closed' if status == 'closed' else 'open',
            'pos %d,%d,%d' % (num(px), num(py), num(pz))]
    if lvl is not None:
        head.append(('lvl %d %s' % (lvl, voc)).strip())
    out = [' | '.join(head), '  ' + (text or '-')]
    if names and who:
        out.append('  from: ' + clean(unescape(who), 29))
    if status == 'closed':
        out.append('  closed: ' + (clean(unescape(staff), NOTE_MAX) or '-'))
    return out


def main(argv):
    names = '--names' in argv
    data = sys.stdin.buffer.read().decode('utf-8', 'replace')
    blocks = []
    for line in data.split('\n'):
        if not line.strip():
            continue
        blocks.append(block(line.split('\t'), names))
    if not blocks:
        print('No bug reports or suggestions.')
        return 0
    for b in blocks:
        print('\n'.join(b))
    print('-- %d report%s' % (len(blocks), '' if len(blocks) == 1 else 's'))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
