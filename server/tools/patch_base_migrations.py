#!/usr/bin/env python3
"""The engine's database migrations add a column only when it is missing (idempotent). install_all.py step `migrations`.

usage: python3 -I patch_base_migrations.py DATA_DIR [--dry-run]

At its start the engine runs data/migrations/<db_version>.lua, <db_version + 1>.lua, ... until one returns false, and
stores the new db_version. The base schema.sql already creates the columns its own migrations 33-40 add, but sets
db_version to 33: on a fresh database every one of them failed with "Duplicate column name" (start log 2026-10-16),
and 41 failed with "Table ... doesn't exist" while the website's znote_shop_orders was missing.

This rewrites each line of DATA_DIR/migrations/*.lua of the form
    db.query("ALTER TABLE `t` ADD [COLUMN] `c1` ..., ADD [COLUMN] `c2` ...")
(only ADD of named columns, nothing else in the statement) into
    if db.tableExists("t") then db.query("ALTER TABLE `t` ADD COLUMN IF NOT EXISTS `c1` ..., ...") end
so a column that is there and a table that is not are both skipped without a console error. ADD COLUMN IF NOT EXISTS
is MariaDB syntax (the game database is MariaDB: docs/LAUNCH.md; server/sql uses it too). Every other line stays as it
is. A second run changes nothing. Prints one line per changed file.
"""
import os
import re
import sys

LINE_RE = re.compile(r'^(?P<lead>[ \t]*)db\.query\((?P<q>["\'])(?P<sql>ALTER\s+TABLE\s+`(?P<table>[A-Za-z0-9_]+)`\s+'
                     r'(?P<rest>.*?))(?P=q)\)(?P<tail>[ \t;]*)(?P<eol>\r?)$', re.M | re.I)
ADD_RE = re.compile(r'^ADD\s+(?:COLUMN\s+)?(?!IF\b)`(?P<col>[A-Za-z0-9_]+)`(?P<def>.*)$', re.S | re.I)
MARK = '-- Cinders of Chaos: patch_base_migrations.py'


def split_top(text):
    """the comma separated clauses of an ALTER TABLE, commas inside () and quotes kept"""
    out, depth, quote, cur = [], 0, None, ''
    for ch in text:
        if quote:
            cur += ch
            if ch == quote:
                quote = None
            continue
        if ch in '\'"`':
            quote = ch
        elif ch == '(':
            depth += 1
        elif ch == ')':
            depth -= 1
        elif ch == ',' and depth == 0:
            out.append(cur.strip())
            cur = ''
            continue
        cur += ch
    out.append(cur.strip())
    return out


def rewrite_sql(rest):
    """the clauses with ADD COLUMN IF NOT EXISTS, or None when the statement is not only ADD of named columns"""
    body = rest.strip()
    end = ''
    if body.endswith(';'):
        body, end = body[:-1].rstrip(), ';'
    clauses = split_top(body)
    new = []
    for c in clauses:
        m = ADD_RE.match(c)
        if not m:
            return None
        new.append('ADD COLUMN IF NOT EXISTS `%s`%s' % (m.group('col'), m.group('def')))
    return ', '.join(new) + end


def patch(text):
    """(new text, [table.column, ...])"""
    done = []

    def line(m):
        new_rest = rewrite_sql(m.group('rest'))
        if new_rest is None:
            return m.group(0)
        head = m.group('sql')[:len(m.group('sql')) - len(m.group('rest'))]
        q = m.group('q')
        table = m.group('table')
        for c in split_top(new_rest.rstrip(';')):
            done.append('%s.%s' % (table, re.search(r'`([^`]+)`', c).group(1)))
        return '%sif db.tableExists("%s") then db.query(%s%s%s%s) end %s%s' % (
            m.group('lead'), table, q, head, new_rest, q, MARK, m.group('eol'))
    return LINE_RE.sub(line, text), done


def main(argv):
    args = [a for a in argv if a != '--dry-run']
    dry = '--dry-run' in argv
    if len(args) != 1 or args[0].startswith('-'):
        print(__doc__)
        return 1
    folder = os.path.join(args[0], 'migrations')
    if not os.path.isdir(folder):
        print('%s: no migrations folder' % args[0])
        return 1
    names = [f for f in os.listdir(folder) if re.match(r'^\d+\.lua$', f)]
    changed = 0
    for name in sorted(names, key=lambda f: int(f[:-4])):
        path = os.path.join(folder, name)
        with open(path, encoding='utf-8', errors='surrogateescape', newline='') as f:
            text = f.read()
        new, done = patch(text)
        if new == text:
            continue
        changed += 1
        if not dry:
            with open(path, 'w', encoding='utf-8', errors='surrogateescape', newline='') as f:
                f.write(new)
        print('migrations/%s: %s only when missing' % (name, ', '.join(done)))
    if changed:
        print('migrations: %d file(s) %s' % (changed, 'would change' if dry else 'changed'))
    else:
        print('migrations: %d file(s), nothing to change' % len(names))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
