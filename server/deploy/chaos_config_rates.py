#!/usr/bin/env python3
"""The experience rates of a server's config.lua: show them, set the XP multiplier, and keep them across an update.

usage: chaos_config_rates.py show CONFIG                 key=value lines: xp (x1, x10, custom), rateExp, rateSkill, ...
       chaos_config_rates.py set CONFIG FACTOR           experienceStages = the release's stages (late_game.py) x FACTOR
       chaos_config_rates.py reset CONFIG                the release's stages (FACTOR 1)
       chaos_config_rates.py save CONFIG FILE            the rates and the experienceStages table into FILE (JSON)
       chaos_config_rates.py restore CONFIG FILE         put them back after install_all.py (its lategame step writes
                                                         the release's stages and would drop a x10 set by hand)

FACTOR: a whole number 1..100. "set" keeps a backup next to the file (config.lua.before-xp-<time>) and marks the table
with "-- Chaos XP rate xN (chaos-ctl.sh xp-rate)", so "show" can tell the factor. The engine reads config.lua at its
start: a change applies at the next restart. chaos-ctl.sh xp-rate and chaos_kit_update.sh use this file
(docs/ADMIN_APP.md). Pure standard library; run with python3 -I.
"""
import json
import os
import re
import shutil
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS = os.path.join(os.path.dirname(HERE), 'tools')
RATE_KEYS = ('rateExp', 'rateSkill', 'rateLoot', 'rateMagic', 'rateSpawn')
XP_MARK = '-- Chaos XP rate x%d (chaos-ctl.sh xp-rate)'
XP_MARK_RE = re.compile(r'^-- Chaos XP rate x(\d+) \(chaos-ctl\.sh xp-rate\)\r?\n', re.M)
# the whole table with our mark and late_game.py's mark right above it (other comments stay where they are)
TABLE_RE = re.compile(r'(?:^-- Chaos XP rate x\d+ \(chaos-ctl\.sh xp-rate\)\r?\n)?'
                      r'(?:^-- Chaos late game stages \(server/tools/late_game\.py\)\r?\n)?'
                      r'^experienceStages\s*=\s*\{.*?\n\}', re.S | re.M)
ROW_RE = re.compile(r'minlevel\s*=\s*(\d+)\s*,\s*(?:maxlevel\s*=\s*(\d+)\s*,\s*)?multiplier\s*=\s*(\d+(?:\.\d+)?)')


def release_stages():
    sys.path.insert(0, TOOLS)
    import late_game  # noqa: E402  (server/tools/late_game.py of this checkout)
    return list(late_game.STAGES), late_game.STAGES_MARK, late_game.stages_lua


def read(path):
    with open(path, encoding='utf-8', errors='surrogateescape', newline='') as f:
        return f.read()


def write(path, text):
    tmp = path + '.tmp-rates'
    with open(tmp, 'w', encoding='utf-8', errors='surrogateescape', newline='') as f:
        f.write(text)
    shutil.copymode(path, tmp)
    try:
        st = os.stat(path)
        os.chown(tmp, st.st_uid, st.st_gid)
    except OSError:
        pass
    os.replace(tmp, path)


def table(text):
    return TABLE_RE.search(text)


def rows(block):
    return [(int(a), int(b) if b else None, float(c)) for a, b, c in ROW_RE.findall(block)]


def rates(text):
    out = {}
    for k in RATE_KEYS:
        m = re.search(r'^\s*%s\s*=\s*([^\n]*?)\s*$' % k, text, re.M)
        if m:
            out[k] = m.group(1)
    return out


def factor_of(block):
    """the XP factor of a table: from our mark, else by comparing with the release's stages; None = custom"""
    m = XP_MARK_RE.search(block)
    if m:
        return int(m.group(1))
    stages, _, _ = release_stages()
    got = rows(block)
    if len(got) != len(stages) or not got:
        return None
    k = got[0][2] / stages[0][2]
    for (lo, hi, mult), (glo, ghi, gm) in zip(stages, got):
        if lo != glo or hi != ghi or abs(gm - mult * k) > 1e-6:
            return None
    return int(k) if k == int(k) else None


def cmd_show(cfg):
    text = read(cfg)
    m = table(text)
    if not m:
        print('xp=none')
    else:
        f = factor_of(m.group(0))
        print('xp=%s' % ('custom' if f is None else 'x%d' % f))
        r = rows(m.group(0))
        if r:
            print('stage_first=%g' % r[0][2])
            print('stage_last=%g' % r[-1][2])
    for k, v in rates(text).items():
        print('%s=%s' % (k, v))
    return 0


def cmd_set(cfg, factor):
    if not re.fullmatch(r'[0-9]{1,3}', factor) or not 1 <= int(factor) <= 100:
        print('chaos_config_rates: FACTOR must be a whole number 1..100', file=sys.stderr)
        return 2
    k = int(factor)
    text = read(cfg)
    m = table(text)
    if not m:
        print('chaos_config_rates: no experienceStages table in %s' % cfg, file=sys.stderr)
        return 1
    stages, mark, stages_lua = release_stages()
    eol = '\r\n' if '\r\n' in m.group(0) else '\n'
    scaled = [(lo, hi, mult * k) for lo, hi, mult in stages]
    marker = mark if k == 1 else (XP_MARK % k) + eol + mark
    new = stages_lua(scaled, marker, eol)
    if m.group(0) == new:
        print('xp=x%d unchanged' % k)
        return 0
    backup = '%s.before-xp-%s' % (cfg, time.strftime('%Y%m%d-%H%M%S'))
    shutil.copy2(cfg, backup)
    write(cfg, text[:m.start()] + new + text[m.end():])
    print('xp=x%d set (stages %g..%g); backup %s; applies at the next restart' % (k, scaled[0][2], scaled[-1][2], backup))
    return 0


def cmd_save(cfg, out):
    text = read(cfg)
    m = table(text)
    data = {'rates': rates(text), 'stages': m.group(0) if m else None}
    with open(out, 'w', encoding='utf-8') as f:
        json.dump(data, f)
    f_ = factor_of(m.group(0)) if m else None
    print('saved: xp %s, %s' % ('custom' if f_ is None else 'x%d' % f_,
                                ', '.join('%s=%s' % kv for kv in data['rates'].items()) or 'no rate lines'))
    return 0


def cmd_restore(cfg, src):
    with open(src, encoding='utf-8') as f:
        data = json.load(f)
    text = read(cfg)
    changed = []
    for k, v in (data.get('rates') or {}).items():
        if k not in RATE_KEYS:
            continue
        m = re.search(r'^(\s*%s\s*=\s*)([^\n]*?)(\s*)$' % k, text, re.M)
        if m and m.group(2) != v:
            text = text[:m.start(2)] + v + text[m.end(2):]
            changed.append('%s=%s' % (k, v))
    old = data.get('stages')
    m = table(text)
    if old and m and m.group(0) != old:
        text = text[:m.start()] + old + text[m.end():]
        f_ = factor_of(old)
        changed.append('experienceStages (%s)' % ('custom' if f_ is None else 'x%d' % f_))
    if changed:
        write(cfg, text)
        print('restored: ' + ', '.join(changed))
    else:
        print('restored: nothing to do (the rates were not changed by the install)')
    return 0


def main(argv):
    if len(argv) >= 2 and argv[0] == 'show' and len(argv) == 2:
        return cmd_show(argv[1])
    if len(argv) == 3 and argv[0] == 'set':
        return cmd_set(argv[1], argv[2])
    if len(argv) == 2 and argv[0] == 'reset':
        return cmd_set(argv[1], '1')
    if len(argv) == 3 and argv[0] == 'save':
        return cmd_save(argv[1], argv[2])
    if len(argv) == 3 and argv[0] == 'restore':
        return cmd_restore(argv[1], argv[2])
    print(__doc__.strip(), file=sys.stderr)
    return 2


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
