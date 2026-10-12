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
"""
import csv
import hashlib
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
LIST = os.path.join(HERE, 'base_server_texts.csv')
LITERAL = re.compile(r'''(['"])((?:\\.|(?!\1)[^\\\r\n])*)\1''')


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
        path = os.path.join(data, *rel.split('/'))
        if not os.path.isfile(path):
            print('data/%s: not there, skipped' % rel)
            continue
        with open(path, encoding='utf-8', errors='surrogateescape', newline='') as f:
            text = f.read()
        new, n, present = patch_text(text, rows[rel])
        missing = sorted(wanted[rel] - present)
        if n and not dry:
            with open(path, 'w', encoding='utf-8', errors='surrogateescape', newline='') as f:
                f.write(new)
        if n:
            print('data/%s: %d string%s replaced%s' % (rel, n, '' if n == 1 else 's', ' (dry run, not written)' if dry else ''))
        elif not missing:
            print('data/%s: already done' % rel)
        if missing:
            status = 1
            for m in missing:
                print('data/%s: neither the old string nor "%s" found (the base file differs; check by hand)' % (rel, m))
    return status


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
