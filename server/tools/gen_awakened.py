#!/usr/bin/env python3
"""server/data/spells/awakened.csv: the awakened name and the signature effect of every attack and heal spell (O686 phase 7).

docs/SPELL_UPGRADES.md section 3: an awakened spell has a new name and a signature effect worth about +5% of the spell (+3% of a class's
damage with the +10%). One row for each spell of server/data/spells/forms.csv (every attack and healing spell a class has, once). Columns:
id, spell, role (damage | heal), element (the spell's own, empty when it has none), shape (the client spell list's areaShape: single, self,
line, wave, circle, around), cooldown (seconds), kind (the signature parts joined by +, see spell_awakening_core.lua), over (the numbers
`PART.key=number;...`, every key written), name_en, name_pt. The names are in server/tools/awakened_names.csv.

The kinds follow the shape of the spell (a ring that pulses for an area spell, a line for a wave or a line, a mark or an echo for a single
target, a reflect for a heal) and rotate inside a shape so the spells of a class do not all do the same. The four examples of the design
(3.3) are written verbatim. The numbers are solved so that the value of a row, spell_awakening_core.lua A.value, is about the config's
`signature.target`: the free number of the output part (the pct of the ring, the line, the echo) is the one the tool solves.

    python3 -I server/tools/gen_awakened.py            # write server/data/spells/awakened.csv
    python3 -I server/tools/gen_awakened.py --check    # CI: the file is what the tool writes, every row inside the band (the Lua value), names unique

Needs luajit (or lua5.3) for the numbers of the config and the value of each row. Deterministic.
"""
import csv
import io
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SERVER = os.path.normpath(os.path.join(HERE, '..'))
REPO = os.path.normpath(os.path.join(SERVER, '..'))
FORMS = os.path.join(SERVER, 'data', 'spells', 'forms.csv')
NAMES = os.path.join(HERE, 'awakened_names.csv')
OUT = os.path.join(SERVER, 'data', 'spells', 'awakened.csv')
SPELLDATA = os.path.join(REPO, 'client', 'overlay', 'modules', 'game_chaosspells', 'spelldata.lua')
COLUMNS = ['id', 'spell', 'role', 'element', 'shape', 'cooldown', 'kind', 'over', 'name_en', 'name_pt']

# spells the client list does not carry: their shape, by what the spell does
SHAPE_FALLBACK = {
    1: 'single', 3: 'single', 13: 'wave', 36: 'single', 37: 'single', 53: 'single', 59: 'wave', 61: 'single', 85: 'wave', 102: 'single',
    103: 'single', 105: 'around', 111: 'line', 123: 'single', 124: 'circle', 125: 'single', 163: 'wave', 169: 'single', 175: 'single',
}

# the keys of each part in the order they are written
KEYS = {
    'PULSE': ['pulses', 'pct', 'secs', 'minHit', 'mana', 'radius'],
    'LINE': ['len', 'pct'],
    'MARK': ['secs', 'pct'],
    'RINGS': ['rings', 'pct'],
    'ECHO': ['pct', 'delay'],
    'SHIELD': ['pct', 'secs', 'minHit'],
    'CDCUT': ['cut', 'window', 'cap'],
    'LEECH': ['pct'],
    'REFLECT': ['pct', 'radius'],
}

# the kinds a spell of each shape rotates through; CDCUT only for a spell with a long enough cooldown, else it becomes a SHIELD
ROTATION = {
    'around': ['PULSE', 'RINGS+CDCUT', 'ECHO+SHIELD', 'PULSE+LEECH'],
    'circle': ['PULSE', 'ECHO+MARK', 'RINGS', 'PULSE+SHIELD'],
    'wave': ['LINE+MARK', 'ECHO', 'PULSE+CDCUT', 'LINE+SHIELD'],
    'line': ['LINE+MARK', 'LINE', 'ECHO+LEECH', 'LINE+CDCUT'],
    'single': ['ECHO+MARK', 'LINE+MARK', 'ECHO+SHIELD', 'PULSE', 'ECHO+LEECH', 'LINE', 'ECHO+CDCUT'],
    'self': ['ECHO+MARK', 'PULSE', 'ECHO+SHIELD', 'RINGS', 'ECHO+LEECH'],
    'heal': ['REFLECT+SHIELD', 'PULSE', 'ECHO+SHIELD', 'REFLECT', 'PULSE+CDCUT', 'REFLECT+CDCUT'],
}
MIN_CDCUT_SECONDS = 20

# the four examples of the design (3.3), verbatim; the numbers the design does not give are ours
VERBATIM = {
    206: ('PULSE', 'PULSE.pulses=3;PULSE.pct=0.4;PULSE.secs=6;PULSE.minHit=3;PULSE.mana=0.03;PULSE.radius=3'),
    218: ('LINE+MARK', 'LINE.len=6;LINE.pct=1;MARK.secs=6;MARK.pct=0.5'),
    148: ('RINGS+CDCUT', 'RINGS.rings=3;RINGS.pct=0.05;CDCUT.cut=1;CDCUT.window=8;CDCUT.cap=5'),
    96: ('REFLECT+SHIELD', 'REFLECT.pct=0.5;REFLECT.radius=4;SHIELD.pct=0.03;SHIELD.secs=4;SHIELD.minHit=1'),
}


def lua_bin():
    for name in (os.environ.get('LUAJIT', ''), 'luajit', 'lua5.3'):
        if name and subprocess.run(['which', name], capture_output=True).returncode == 0:
            return name
    raise SystemExit('gen_awakened: luajit or lua5.3 not found')


def lua_numbers():
    """({config name: value}, {spell id: (value, output, utility, kind)}) from tools/awakening_numbers.lua"""
    p = subprocess.run([lua_bin(), os.path.join('tools', 'awakening_numbers.lua')], cwd=SERVER, capture_output=True, text=True)
    if p.returncode != 0:
        raise SystemExit('gen_awakened: awakening_numbers.lua failed: ' + p.stderr.strip())
    cfg, rows = {}, {}
    for line in p.stdout.splitlines():
        f = line.split('\t')
        if f[0] == 'cfg':
            cfg[f[1]] = f[2]
        elif f[0] == 'row':
            rows[int(f[1])] = (float(f[2]), float(f[3]), float(f[4]), f[5])
    return cfg, rows


def read_forms():
    """{id: (spell, role, element)} of forms.csv, once for a spell"""
    out = {}
    with open(FORMS, newline='', encoding='utf-8') as f:
        for r in csv.DictReader(f):
            out.setdefault(int(r['id']), (r['spell'], r['role'], r['element']))
    return out


def read_names():
    with open(NAMES, newline='', encoding='utf-8') as f:
        return {int(r['id']): r for r in csv.DictReader(f)}


def spell_shapes():
    text = open(SPELLDATA, encoding='utf-8').read()
    out = {}
    for m in re.finditer(r'\{ id = (\d+), name = "([^"]+)"[^\n]*', text):
        s = re.search(r'areaShape = "(\w+)"', m.group(0))
        if s:
            out[int(m.group(1))] = s.group(1)
    return out


def cooldowns():
    sys.path.insert(0, HERE)
    import rotation_sim as R
    out = {}
    for s in R.load_chaos() + R.load_stock():
        if s['group'] in ('attack', 'healing') and s['vocations'] and s['id'] not in out:
            out[s['id']] = s['cooldown'] / 1000.0
    return out


def fmt(v):
    s = '%g' % v
    return s


class Solver:
    def __init__(self, cfg):
        self.c = {k: float(v) for k, v in cfg.items() if re.match(r'^[-0-9.e]+$', v)}

    def targets(self, shape, heal):
        return 1.0 if heal else self.c['targets.' + shape]

    def utility(self, part, cd):
        w = lambda k: self.c['worth.' + k]
        if part['kind'] == 'MARK':
            return part['pct'] * w('markShare') * w('mark')
        if part['kind'] == 'SHIELD':
            return part['pct'] * w('shield')
        if part['kind'] == 'LEECH':
            return part['pct'] * w('leech')
        if part['kind'] == 'CDCUT':
            return min(part['cap'], part['cut'] * self.c['kills']) / max(1.0, cd) * w('cooldown')
        return 0.0

    def per_pct(self, part, shape, heal):
        """output raw per unit of pct"""
        c, T = self.c, self.targets(shape, heal)
        k = part['kind']
        if k == 'PULSE':
            return part['pulses'] * c['allies'] if heal else part['pulses'] * max(T, c['ringReach']) / T
        if k == 'LINE':
            return min(c['lineReach'], part['len'] * c['lineDensity']) / T
        if k == 'RINGS':
            return part['rings']
        if k == 'ECHO':
            return 1.0
        if k == 'REFLECT':
            return c['allies']
        raise KeyError(k)


def parse_over(text):
    """'LINE.len=6;MARK.pct=0.5' -> {'LINE': {'len': 6.0}, 'MARK': {'pct': 0.5}}"""
    out = {}
    for item in filter(None, text.split(';')):
        key, val = item.split('=')
        part, name = key.split('.')
        out.setdefault(part, {})[name] = float(val)
    return out


def py_value(row, S):
    """the value of a written row as the tool counts it (the mirror of spell_awakening_core.lua A.value; --check holds the two equal)"""
    heal = row['role'] == 'heal'
    over = parse_over(row['over'])
    parts = [dict(over[k], kind=k) for k in row['kind'].split('+')]
    cd = float(row['cooldown'])
    out, util = 0.0, 0.0
    T = 1.0 if heal else S.c['targets.' + row['shape']]
    c = S.c
    for p in parts:
        if p['kind'] in ('PULSE', 'LINE', 'RINGS', 'ECHO', 'REFLECT'):
            out += p['pct'] * S.per_pct(p, row['shape'], heal)
        else:
            util += S.utility(p, cd)
    return min(out, c['capShare']) * c['use'] + util


def base_part(kind, shape, heal, cd, i):
    """a part with its numbers before the output pct is solved"""
    area = shape in ('around', 'circle', 'wave')
    if kind == 'PULSE':
        return {'kind': kind, 'pulses': 3, 'pct': 0.3, 'secs': 6, 'minHit': 3 if area else 2, 'mana': 0 if heal else 0.03, 'radius': 3}
    if kind == 'LINE':
        return {'kind': kind, 'len': {'line': 7, 'wave': 5}.get(shape, 6), 'pct': 0.5}
    if kind == 'MARK':
        return {'kind': kind, 'secs': 6 + 2 * (i % 2), 'pct': 0.5}
    if kind == 'RINGS':
        return {'kind': kind, 'rings': 2 if cd < 30 else 3, 'pct': 0.1}
    if kind == 'ECHO':
        return {'kind': kind, 'pct': 0.5, 'delay': 2000 if heal else 1500}
    if kind == 'SHIELD':
        return {'kind': kind, 'pct': (0.03, 0.04)[i % 2], 'secs': 4 + (i % 2), 'minHit': 3 if area else 1}
    if kind == 'CDCUT':
        return {'kind': kind, 'cut': 1, 'window': 8, 'cap': 5 if cd >= 40 else 4}
    if kind == 'LEECH':
        return {'kind': kind, 'pct': 0.04}
    if kind == 'REFLECT':
        return {'kind': kind, 'pct': 0.5, 'radius': 4}
    raise KeyError(kind)


def over_text(parts):
    return ';'.join('%s.%s=%s' % (p['kind'], k, fmt(p[k])) for p in parts for k in KEYS[p['kind']])


def pick_kind(shape, heal, cd, counter):
    key = 'heal' if heal else shape
    rot = ROTATION[key]
    kind = rot[counter[key] % len(rot)]
    counter[key] += 1
    if 'CDCUT' in kind and cd < MIN_CDCUT_SECONDS:
        kind = kind.replace('CDCUT', 'SHIELD')
        if kind.count('SHIELD') > 1:
            kind = kind.split('+')[0]
    return kind


def build_row(sid, spell, role, element, shape, cd, kind, S, i, names):
    heal = role == 'heal'
    kinds = kind.split('+')
    parts = [base_part(k, shape, heal, cd, i) for k in kinds]
    util = sum(S.utility(p, cd) for p in parts)
    outs = [p for p in parts if p['kind'] in ('PULSE', 'LINE', 'RINGS', 'ECHO', 'REFLECT')]
    target, use, cap = S.c['target'], S.c['use'], S.c['capShare']
    if len(outs) != 1:
        raise SystemExit('gen_awakened: %s has %d output parts' % (kind, len(outs)))
    out = outs[0]
    if len(parts) == 1:
        # alone: generous numbers that the cap holds to the target (the examples of the design are of this kind)
        raw = 2 * cap
    else:
        raw = max(0.0, (target - util)) / use
    pct = raw / S.per_pct(out, shape, heal)
    out['pct'] = min(1.0, max(0.02, round(pct * 100) / 100.0))
    return {'id': sid, 'spell': spell, 'role': role, 'element': element, 'shape': shape, 'cooldown': fmt(cd), 'kind': kind,
            'over': over_text(parts), 'name_en': names[sid]['name_en'], 'name_pt': names[sid]['name_pt']}


def generate():
    cfg, _ = lua_numbers()
    S = Solver(cfg)
    forms, names = read_forms(), read_names()
    shapes, cds = spell_shapes(), cooldowns()
    counter = {k: 0 for k in ROTATION}
    rows = []
    for sid in sorted(forms):
        spell, role, element = forms[sid]
        if sid not in names:
            raise SystemExit('gen_awakened: no awakened name for %d %s (server/tools/awakened_names.csv)' % (sid, spell))
        if names[sid]['spell'] != spell:
            raise SystemExit('gen_awakened: the name row of %d is for %s, the spell is %s' % (sid, names[sid]['spell'], spell))
        shape = shapes.get(sid) or SHAPE_FALLBACK.get(sid)
        if shape is None:
            raise SystemExit('gen_awakened: no shape for %d %s' % (sid, spell))
        cd = cds.get(sid)
        if cd is None:
            raise SystemExit('gen_awakened: no cooldown for %d %s' % (sid, spell))
        heal = role == 'heal'
        kind = pick_kind(shape, heal, cd, counter)
        if sid in VERBATIM:
            kind, over = VERBATIM[sid]
            row = {'id': sid, 'spell': spell, 'role': role, 'element': element, 'shape': shape, 'cooldown': fmt(cd), 'kind': kind,
                   'over': over, 'name_en': names[sid]['name_en'], 'name_pt': names[sid]['name_pt']}
        else:
            row = build_row(sid, spell, role, element, shape, cd, kind, S, len(rows), names)
        rows.append(row)
    extra = sorted(set(names) - set(forms))
    if extra:
        raise SystemExit('gen_awakened: names for spells that have no Forms: %s' % extra)
    return rows


def render(rows):
    buf = io.StringIO()
    w = csv.DictWriter(buf, fieldnames=COLUMNS, lineterminator='\n')
    w.writeheader()
    for r in rows:
        w.writerow(r)
    return buf.getvalue()


def main(argv):
    rows = generate()
    text = render(rows)
    if '--check' in argv:
        problems = []
        have = open(OUT, encoding='utf-8', newline='').read() if os.path.exists(OUT) else ''
        if have != text:
            problems.append('server/data/spells/awakened.csv is not what tools/gen_awakened.py writes: run it')
        cfg, values = lua_numbers()
        lo, hi = float(cfg['bandMin']), float(cfg['bandMax'])
        for sid, (v, out, util, kind) in sorted(values.items()):
            if not lo - 1e-9 <= v <= hi + 1e-9:
                problems.append('%d: the signature is worth %.1f%%, the band is %.0f%% to %.0f%%' % (sid, v * 100, lo * 100, hi * 100))
        if len(values) != len(rows):
            problems.append('the Lua table has %d rows, the tool writes %d' % (len(values), len(rows)))
        S = Solver(cfg)
        for r in rows:
            mine, theirs = py_value(r, S), values.get(r['id'], (None,))[0]
            if theirs is None or abs(mine - theirs) > 1e-6:
                problems.append('%d: the tool counts a value of %s, spell_awakening_core.lua %s' % (r['id'], mine, theirs))
        for p in problems:
            print('FAIL ' + p)
        if not problems:
            vs = [v[0] for v in values.values()]
            print('gen_awakened: ok (%d rows, value %.1f%% to %.1f%%, mean %.2f%%)' % (len(rows), min(vs) * 100, max(vs) * 100,
                                                                                      sum(vs) / len(vs) * 100))
        return 1 if problems else 0
    with open(OUT, 'w', encoding='utf-8', newline='') as f:
        f.write(text)
    print('wrote %s (%d rows)' % (os.path.relpath(OUT, REPO), len(rows)))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
