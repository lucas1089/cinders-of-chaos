#!/usr/bin/env python3
"""Credits check (docs/CREDITS.md, the single list of third-party sources). Fails when
  - a pack of an art tracing file (any `*sources.csv`, e.g. client/tools/sprites/art_import/pack27_sources.csv,
    client/tools/outfit_art/class_looks_sources.csv, client/tools/sprites/monster_looks/sources.csv) is not named in
    docs/CREDITS.md: the file's `pack` column, else its `source` column, must contain the name of an entry
    (`- **Name**` anywhere in CREDITS.md, case-insensitive),
  - a shown section heading has no matching pt-BR entry in client_chaos_locale/pt_br.lua (the client shows it with tr()),
  - the generated credits data is not up to date (client/tools/gen_credits.py --check).

  python3 -I tools/ci/check_credits.py
"""
import csv
import io
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CREDITS = os.path.join(ROOT, 'docs', 'CREDITS.md')
PT_BR = os.path.join(ROOT, 'client', 'overlay', 'modules', 'client_chaos_locale', 'pt_br.lua')
sys.path.insert(0, os.path.join(ROOT, 'client', 'tools'))
import gen_credits  # noqa: E402

NAME = re.compile(r'\*\*(.+?)\*\*')
PT_ENTRY = re.compile(r'^\s*\["((?:[^"\\]|\\.)*)"\]\s*=\s*"((?:[^"\\]|\\.)*)"', re.M)


def credited_names(credits_text):
    """Every bold name in the list items of CREDITS.md (shown and internal parts), lower case."""
    names = set()
    for line in credits_text.split('\n'):
        if line.lstrip().startswith('- ') or (line.startswith('  ') and '**' in line):
            for m in NAME.finditer(line):
                names.add(m.group(1).strip().lower())
    return names


def csv_packs(csv_text):
    """The distinct non-empty values of the `pack` column, else of the `source` column; [] without either."""
    reader = csv.DictReader(io.StringIO(csv_text))
    fields = [f.strip().lower() for f in (reader.fieldnames or [])]
    column = 'pack' if 'pack' in fields else 'source' if 'source' in fields else None
    if column is None:
        return []
    real = (reader.fieldnames or [])[fields.index(column)]
    seen = []
    for row in reader:
        value = (row.get(real) or '').strip()
        if value and value not in seen:
            seen.append(value)
    return seen


def pt_br_table(lua_text):
    return {m.group(1): m.group(2) for m in PT_ENTRY.finditer(lua_text)}


def problems(credits_text, csv_files, pt_br_text):
    """csv_files: {path: text}. Returns a list of messages (empty when all is well)."""
    out = []
    names = credited_names(credits_text)
    if not names:
        out.append('docs/CREDITS.md names no entry')
    for path in sorted(csv_files):
        for value in csv_packs(csv_files[path]):
            low = value.lower()
            if not any(n in low for n in names):
                out.append(f'{path}: pack {value!r} is not named in docs/CREDITS.md (add an entry "- **<pack>**")')
    try:
        sections = gen_credits.parse(credits_text)
    except gen_credits.CreditsError as e:
        return out + [f'docs/CREDITS.md: {e}']
    table = pt_br_table(pt_br_text)
    for s in sections:
        if s['title'] == s['pt'] and s['title'] not in table:
            continue
        if table.get(s['title']) != s['pt']:
            out.append(f'pt_br.lua: heading ["{s["title"]}"] = "{s["pt"]}" missing or different (docs/CREDITS.md)')
    return out


def source_csvs():
    listed = subprocess.check_output(['git', 'ls-files', '-co', '--exclude-standard'], cwd=ROOT, text=True).split('\n')
    files = {}
    for rel in listed:
        if rel.endswith('sources.csv') and os.path.isfile(os.path.join(ROOT, rel)):
            with open(os.path.join(ROOT, rel), encoding='utf-8') as f:
                files[rel] = f.read()
    return files


def main():
    with open(CREDITS, encoding='utf-8') as f:
        credits_text = f.read()
    with open(PT_BR, encoding='utf-8') as f:
        pt_br_text = f.read()
    csvs = source_csvs()
    bad = problems(credits_text, csvs, pt_br_text)
    for p in bad:
        print(p)
    stale = gen_credits.main(['--check'])
    print(f'credits check: {len(csvs)} sources file(s);', 'OK' if not bad and not stale else f'{len(bad)} problem(s)')
    return 1 if bad or stale else 0


if __name__ == '__main__':
    sys.exit(main())
