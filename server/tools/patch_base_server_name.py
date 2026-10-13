#!/usr/bin/env python3
"""The base server's own name in its data (server/README.md "Server name").

usage: python3 -I patch_base_server_name.py DATA_DIR [--dry-run] [--list CSV]

The base data names the server it came from in a few whole strings: the floating welcome text over the first temple
(players see it) and the console banner of the web login service. The world renames (patch_base_texts.py) know single
names, not these phrases, and a new row there would double our name where the world step already changed part of a
phrase. This step replaces exact whole strings instead.

The list (default tools/base_server_texts.csv, columns sha256,file,new,note) holds no old text: each row is the
SHA-256 (hex) of one old Lua string literal's content exactly as written in the file (between its quotes, case and
escapes as they are), the file relative to DATA_DIR, and the new content. A phrase that another step may already have
changed in part has one row per form, with the same new text.

In each listed file every quoted Lua string ('...' or "...") whose content hashes to a row of that file becomes the
row's new text; nothing else changes (no partial matches, identifiers and other strings stay). A second run changes
nothing: the old strings are gone and the new text is found. A missing file is skipped; a file that has neither an old
string nor the new text of a row is reported and the exit status is 1.

A row whose file is config.lua means the server's config.lua next to DATA_DIR (DATA_DIR/../config.lua). There only the
value of the `serverName = "..."` line is checked: it becomes the new text when it hashes to a row (the base server's
own name, which the login server sends as the world name). Any other value (an owner's own name, the one
tools/prod_config.py wrote) stays and is no error; a config.lua without a serverName line is reported (exit 1).
"""
import csv
import hashlib
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
LIST = os.path.join(HERE, 'base_server_texts.csv')
LITERAL = re.compile(r'''(['"])((?:\\.|(?!\1)[^\\\r\n])*)\1''')
SERVER_NAME = re.compile(r'''^([ \t]*serverName[ \t]*=[ \t]*)(['"])((?:\\.|(?!\2)[^\\\r\n])*)\2''', re.M)
CONFIG = 'config.lua'


def digest(text):
    return hashlib.sha256(text.encode('utf-8', 'surrogateescape')).hexdigest()


def read_list(path):
    """{file: {sha256: new}} and {file: set(new)}; refuses a row the tool cannot write safely"""
    rows, wanted = {}, {}
    with open(path, encoding='utf-8', newline='') as f:
        for n, row in enumerate(csv.DictReader(f), 2):
            key = (row.get('sha256') or '').strip().lower()
            if not key or key.startswith('#'):
                continue
            rel = (row.get('file') or '').strip().replace('\\', '/')
            new = row.get('new') or ''
            if not re.match(r'^[0-9a-f]{64}$', key) or not rel or rel.startswith('/') or '..' in rel.split('/'):
                raise ValueError('%s:%d: bad sha256 or file' % (path, n))
            if not new or re.search(r'[\'"\\\r\n]', new):
                raise ValueError('%s:%d: the new text is empty or has a quote, a backslash or a line break' % (path, n))
            rows.setdefault(rel, {})[key] = new
            wanted.setdefault(rel, set()).add(new)
    return rows, wanted


def patch_text(text, table):
    """(new text, number of strings replaced, set of new texts present afterwards)"""
    count = [0]
    present = set()

    def repl(m):
        new = table.get(digest(m.group(2)))
        if new is None:
            return m.group(0)
        count[0] += 1
        return m.group(1) + new + m.group(1)

    out = LITERAL.sub(repl, text)
    for m in LITERAL.finditer(out):
        present.add(m.group(2))
    return out, count[0], present


def patch_config(text, table):
    """config.lua, the serverName line only: (new text, number replaced, the serverName values afterwards)"""
    count = [0]

    def repl(m):
        new = table.get(digest(m.group(3)))
        if new is None:
            return m.group(0)
        count[0] += 1
        return m.group(1) + m.group(2) + new + m.group(2)

    out = SERVER_NAME.sub(repl, text)
    return out, count[0], set(m.group(3) for m in SERVER_NAME.finditer(out))


def main(argv):
    args, dry, path_list = [], False, LIST
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == '--dry-run':
            dry = True
        elif a == '--list' and i + 1 < len(argv):
            path_list = argv[i + 1]
            i += 1
        elif a.startswith('--'):
            print('unknown option %s' % a)
            return 2
        else:
            args.append(a)
        i += 1
    if len(args) != 1 or not os.path.isdir(args[0]):
        print(__doc__.strip().splitlines()[2])
        return 2
    data = args[0]
    try:
        rows, wanted = read_list(path_list)
    except (OSError, ValueError) as e:
        print('list: %s' % e)
        return 1
    status = 0
    for rel in sorted(rows):
        config = rel == CONFIG
        path = os.path.join(data, os.pardir, CONFIG) if config else os.path.join(data, *rel.split('/'))
        label = rel if config else 'data/' + rel
        if not os.path.isfile(path):
            print('%s: not there, skipped' % label)
            continue
        with open(path, encoding='utf-8', errors='surrogateescape', newline='') as f:
            text = f.read()
        if config:
            new, n, present = patch_config(text, rows[rel])
            if not present:
                status = 1
                print('%s: no serverName line (the base file differs; check by hand)' % label)
                continue
            if not n and not present & wanted[rel]:
                print('%s: serverName is not the base value, left as it is' % label)
                continue
            missing = []
        else:
            new, n, present = patch_text(text, rows[rel])
            missing = sorted(wanted[rel] - present)
        if n and not dry:
            with open(path, 'w', encoding='utf-8', errors='surrogateescape', newline='') as f:
                f.write(new)
        if n:
            print('%s: %d string%s replaced%s' % (label, n, '' if n == 1 else 's', ' (dry run, not written)' if dry else ''))
        elif not missing:
            print('%s: already done' % label)
        if missing:
            status = 1
            for m in missing:
                print('%s: neither the old string nor "%s" found (the base file differs; check by hand)' % (label, m))
    return status


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
