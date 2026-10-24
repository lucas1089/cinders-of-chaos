#!/usr/bin/env python3
"""Faster skill and magic level training from level 101 (idempotent). install_all.py step `skillstages`.

usage: python3 -I patch_skill_stages.py DATA_DIR [--dry-run]       (python3 -I patch_skill_stages.py --show prints the config)

Owner decision (2026-10-24, "pode acelerar 5x o treino de skill", ROADMAP O154): a character that hunts to level 1000 trains
its main skill to about 105 (docs/PRICES.md "Skill training (O150)"), so every stage multiplier of the base server's
DATA_DIR/scripts/customs/skills/skills_stages.lua from skill (and magic) level `fromLevel` (101) up is multiplied by
`factor` (5). Stages up to 100 stay. The two numbers are in data/scripts/chaos/skill_stages_config.lua (the model,
tools/skill_model.lua, reads the same file). Hunting, exercise weapons and offline training all pass this script
(onGainSkillTries), so all three speed up alike and the value of a dummy hour in hunting hours does not change.

The stock rows look like `[{ 101, 110}] = {multiplier = 9},` and `[{150}] = {multiplier = 4}` (no end: open). A row that
spans `fromLevel - 1` and `fromLevel` is split in two. Every changed row ends with `-- Chaos: was 9`: the original value, so a
changed factor or a second run derives from the original and never compounds. A header line (MARK) on top says which
factor the file has. CRLF line ends are kept. A file whose shape is not the one above (no `local skillStages = {` table or
`onGainSkillTries`, a line in the table that is not a skill header, a stage row or a close, overlapping rows, a marked
file with a row from `fromLevel` up that has no `was` value) is refused with the reason and left alone (exit 1).
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
CONFIG = os.path.join(HERE, '..', 'data', 'scripts', 'chaos', 'skill_stages_config.lua')
TARGET = os.path.join('scripts', 'customs', 'skills', 'skills_stages.lua')
MARK = '-- Chaos: skill stages (patch_skill_stages.py)'

HEADER = re.compile(r'^\s*local\s+skillStages\s*=\s*\{\s*$')
SKILL = re.compile(r'^\s*\[\s*[A-Z_]+\s*\]\s*=\s*\{\s*$')
CLOSE = re.compile(r'^\s*\}\s*,?\s*$')
ROW = re.compile(r'^(?P<ind>\s*)\[\{\s*(?P<a>\d+)\s*(?:,\s*(?P<b>\d+)\s*)?\}\](?P<eq>\s*=\s*\{\s*multiplier\s*=\s*)'
                 r'(?P<m>\d+(?:\.\d+)?)(?P<end>\s*\})(?P<comma>,?)(?P<tail>[ \t]*(?:--.*)?)$')
WAS = re.compile(r'--\s*Chaos:\s*was\s+(\d+(?:\.\d+)?)')


class Refused(Exception):
    pass


def read_config(path=CONFIG):
    """(fromLevel, factor) of skill_stages_config.lua"""
    with open(path, encoding='utf-8') as f:
        text = f.read()
    got = []
    for key in ('fromLevel', 'factor'):
        m = re.search(r'\b%s\s*=\s*(\d+(?:\.\d+)?)' % key, text)
        if not m:
            raise Refused('%s: no "%s = number"' % (os.path.basename(path), key))
        got.append(float(m.group(1)) if '.' in m.group(1) else int(m.group(1)))
    if got[0] < 2 or got[1] <= 0 or got[0] != int(got[0]):
        raise Refused('%s: fromLevel must be a whole number from 2 and factor above 0' % os.path.basename(path))
    return int(got[0]), got[1]


def num(x):
    x = round(x, 6)
    return str(int(x)) if x == int(x) else repr(x)


def row(m, a, b, mult, was):
    """one stage row in the shape of the original (indent, spacing, comma); `was` is the original value of a changed row"""
    rng = '%d' % a if b is None else '%d, %d' % (a, b)
    s = '%s[{%s}]%s%s%s%s' % (m.group('ind'), rng, m.group('eq'), num(mult), m.group('end'), m.group('comma'))
    tail = WAS.sub('', m.group('tail')).strip()
    if was is not None:
        tail = (tail + ' ' if tail else '') + '-- Chaos: was %s' % num(was)
    return s + (' ' + tail if tail else '')


def patch_text(text, from_level, factor):
    """(new text, 'patched' | 'already'). Raises Refused. The stock text and the output of an earlier run (any factor) give
    the same result for the same numbers."""
    crlf = '\r\n' in text
    marked = MARK in text
    lines = [ln for ln in text.replace('\r\n', '\n').split('\n') if not ln.startswith(MARK)]
    start = next((i for i, ln in enumerate(lines) if HEADER.match(ln)), None)
    if start is None:
        raise Refused('no "local skillStages = {" table (is this the stock skills_stages.lua?)')
    if not any('onGainSkillTries' in ln for ln in lines):
        raise Refused('no onGainSkillTries callback: the stages are not used the way this tool expects')
    out = lines[:start + 1]
    inside, prev, rows, closed = False, None, 0, False
    for n in range(start + 1, len(lines)):
        ln = lines[n]
        if closed:
            out.append(ln)
        elif not inside:
            if SKILL.match(ln):
                inside, prev = True, None
            elif CLOSE.match(ln):
                closed = True
            elif ln.strip():
                raise Refused('line %d: not a skill header "[SKILL_X] = {": %r' % (n + 1, ln.strip()))
            out.append(ln)
        else:
            m = ROW.match(ln)
            if not m:
                if CLOSE.match(ln):
                    inside = False
                    out.append(ln)
                    continue
                raise Refused('line %d: not a stage row [{ a, b}] = {multiplier = n}: %r' % (n + 1, ln.strip()))
            a = int(m.group('a'))
            b = int(m.group('b')) if m.group('b') is not None else None
            if b is not None and b < a:
                raise Refused('line %d: stage %d-%d runs backwards' % (n + 1, a, b))
            if prev is not None and a <= prev:
                raise Refused('line %d: stage %d overlaps the one before it' % (n + 1, a))
            prev = float('inf') if b is None else b
            rows += 1
            was = WAS.search(m.group('tail'))
            orig = float(was.group(1)) if was else float(m.group('m'))
            hi = float('inf') if b is None else b
            if hi < from_level:
                if was:
                    raise Refused('line %d: a row below level %d carries a "was" value' % (n + 1, from_level))
                out.append(ln)
            elif a >= from_level:
                if marked and not was:
                    raise Refused('line %d: the file is marked as patched but this row from level %d up has no '
                                  '"-- Chaos: was N" value (edited by hand?)' % (n + 1, from_level))
                out.append(row(m, a, b, orig * factor, orig))
            else:  # spans from_level - 1 and from_level: split
                if was:
                    raise Refused('line %d: a row that starts below level %d carries a "was" value' % (n + 1, from_level))
                out.append(row(m, a, from_level - 1, orig, None))
                out.append(row(m, from_level, b, orig * factor, orig))
    if not closed:
        raise Refused('the skillStages table is never closed')
    if rows == 0:
        raise Refused('no stage rows in skillStages')
    out.insert(0, '%s: stage multipliers x%s from level %d up (data/scripts/chaos/skill_stages_config.lua)' % (
        MARK, num(factor), from_level))
    new = '\n'.join(out)
    if crlf:
        new = new.replace('\n', '\r\n')
    return new, ('already' if new == text else 'patched')


def main(argv):
    if argv == ['--show']:
        print('fromLevel %d, factor %s' % (read_config()[0], num(read_config()[1])))
        return 0
    args = [a for a in argv if a != '--dry-run']
    dry = '--dry-run' in argv
    if len(args) != 1 or args[0].startswith('-'):
        print(__doc__)
        return 1
    name = TARGET.replace(os.sep, '/')
    path = os.path.join(args[0], TARGET)
    if not os.path.isfile(path):
        print('%s: not found (skipped)' % name)
        return 0
    try:
        from_level, factor = read_config()
        with open(path, encoding='utf-8', errors='surrogateescape', newline='') as f:
            text = f.read()
        new, status = patch_text(text, from_level, factor)
    except Refused as e:
        print('%s: REFUSED, left alone: %s' % (name, e))
        return 1
    if status == 'already':
        print('skill stages: already x%s from level %d' % (num(factor), from_level))
        return 0
    if not dry:
        with open(path, 'w', encoding='utf-8', errors='surrogateescape', newline='') as f:
            f.write(new)
    print('skill stages: %s x%s from level %d (%s)' % ('would multiply' if dry else 'multiplied', num(factor), from_level, name))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
