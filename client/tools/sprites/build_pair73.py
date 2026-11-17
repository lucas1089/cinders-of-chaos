#!/usr/bin/env python3
"""Pair 73 in one command (O612; client/MANIFEST.md "Pair 73 build (O612)").

usage: python3 -I client/tools/sprites/build_pair73.py P72_DIR OUT_DIR
           --creature-src DIR --spell-src DIR --status-src DIR --gap-src DIR --area-src DIR [--area-src DIR ...]
           [--wings-src DIR] [--work DIR] [--dry-run] [--any-base] [--order A,B,...]

P72_DIR holds Tibia.dat and Tibia.spr of pair 72 (read only, never changed). OUT_DIR must not exist: it gets the pair
and build/ (the log pair73_build.txt and the outfit centre table measured on pair 72). No source picture is copied and
the strips/ folder a step writes beside its pair is deleted.

Steps, in the order the tools' input rules allow (order_problems holds it; STEPS is the table):
  centre    O585          gen_outfit_centre.py apply     169 player looks move to the stock standing point (in place)
  wings     O583 / O594   gen_drawn_wings.py apply       the 121 wings looks drawn again (in place, sprites appended)
  classredraw O618        gen_class_redraw.py build      the class outfits drawn again (in place, sprites appended; sheets are committed, no source folder)
  creature  O608          gen_creature_outfits.py build  3 boss outfits after the 3,526 of pair 72
  spell     O596 / O600   gen_spell_vfx.py build         2 effects at 4743.., one projectile in the blank missile 46
  status    O597          gen_status_vfx.py build        blanks up to 5142, then 47 effects at 5143..5189 (status layer, kills)
  gap       O606          gen_gap_fx.py build            47 effects at 5190.. (it takes up to 5189 and pads nothing here)
  area      O607 / O609   gen_area_fx.py build           blanks up to 5299, 30 refills in place, 1 burst, 20 long beams
  lightning O614          gen_lightning_fx.py build      5 effects at 5321.. drawn by code (no source folder; it pads nothing here)

Why this order. The spell step takes a pair with exactly 4,742 effects, the status step 4,742 to 5,142 and it pads up to 5142
(the spell block 4743..5142 is the spell step's: after it the pair has 4,744 effects, so the status step pads 4745..5142),
the gap step 4,742 to 5,189, the area step 4,742 to 5,299 and it pads up to 5299, the lightning step 4,742 to 5,320 and it
pads up to 5320: so spell, status, gap, area, lightning, and nothing that adds an effect after lightning. The status step before the spell step is refused (the spell step wants exactly 4,742). The creature step
takes exactly 3,526 outfits and no other step adds one. The centring runs before the wings: its table lists the wings
looks with the displacement of pair 72, which the drawn wings drop, so its `check` is true only before them. After the
wings the 169 moved looks are held to their rows in this script (centre_rows_hold).

The centre table is of pair 71. Pair 72 has 16 more looks, so the script measures pair 72 first (about 2 minutes),
stops when a row of the committed table changed, and applies and checks with the measured table
(OUT_DIR/build/outfit_centre.csv: commit it over pair_fixes/outfit_centre.csv at the real build).

Every step: build into WORK/<step>, the step's own `live` / `check` on the output, the counts the plan says, then the
input copy is deleted (never P72_DIR). At most two pairs lie in WORK at once, about 2.4 GB. At the end every `live` runs
again on the final pair, with the two of pair 72 (gen_fun_costumes.py, gen_ki_auras.py) and check_pair.py against
pair 72: only the outfits, effects and the missile the tables name may differ from pair 72. Then the md5s.

--dry-run only checks the inputs: the pair 72 files, their counts and dat md5 (server/tools/client_pair.py), every
picture a table names by digest in its source folder, the wings sheets, the room on the disk, the step order.
--any-base takes a base pair with another dat md5 (a rebuilt pair 72). --wings-src DIR: the ten painted wings rows of
drawn_wings/pixellab_rows.csv come from DIR; without it all 121 are drawn by code (the owner's choice, open).
--work DIR: default OUT_DIR.work, on the disk of OUT_DIR (use a RAM disk: a pair is 1.2 GB).

The sources are purchased or private art: the script reads no picture itself (file digests only) and hands the folders
to the tools. Nothing of them is written to the repository.
"""
import argparse
import collections
import csv
import hashlib
import os
import shutil
import struct
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(HERE, '..', '..', '..'))
ART = os.path.join(HERE, 'art_import')
CENTRE_CSV = os.path.join(HERE, 'pair_fixes', 'outfit_centre.csv')
WINGS_CSV = os.path.join(HERE, 'drawn_wings', 'designs.csv')
WINGS_SHEETS_CSV = os.path.join(HERE, 'drawn_wings', 'pixellab_rows.csv')
SPELL_CSV = os.path.join(ART, 'spell_vfx.csv')
GAP_CSV = os.path.join(ART, 'gap_fx.csv')
STATUS_CSV = os.path.join(ART, 'status_vfx.csv')
AREA_CSV = os.path.join(ART, 'area_fx.csv')
LIGHTNING_CSV = os.path.join(ART, 'lightning_fx.csv')
CREATURE_CSV = os.path.join(ART, 'creature_outfits.csv')
CLASS_CSV = os.path.join(ART, 'class_redraw.csv')

PAIR = 73
BASE = {'outfits': 3526, 'effects': 4742, 'missiles': 253}       # pair 72

Step = collections.namedtuple('Step', 'key onum tool title needs after src table')
# needs: {count: (lowest, highest)} the tool takes in its input pair; after: steps that must have run before
STEPS = (
    Step('centre', 'O585', 'gen_outfit_centre.py', 'outfits centred on the tile', {}, (), None, CENTRE_CSV),
    Step('wings', 'O583 / O594', 'gen_drawn_wings.py', 'the 121 wings looks drawn again', {}, ('centre',), 'wings', WINGS_CSV),
    Step('classredraw', 'O618', 'gen_class_redraw.py', 'class outfits drawn again at the stock bar', {}, ('centre',), None,
         CLASS_CSV),
    Step('creature', 'O608', 'gen_creature_outfits.py', 'boss creature outfits', {'outfits': (3526, 3526)}, (), 'creature',
         CREATURE_CSV),
    Step('spell', 'O596 / O600', 'gen_spell_vfx.py', 'spell effects and a projectile', {'effects': (4742, 4742)}, (), 'spell',
         SPELL_CSV),
    Step('status', 'O597', 'gen_status_vfx.py', 'status layer and kill overlay effects', {'effects': (4742, 5142)}, (), 'status',
         STATUS_CSV),
    Step('gap', 'O606', 'gen_gap_fx.py', 'effects for roles that had none', {'effects': (4742, 5189)}, (), 'gap', GAP_CSV),
    Step('area', 'O607 / O609', 'gen_area_fx.py', 'area bursts, beams, markers, long beams', {'effects': (4742, 5299)}, (),
         'area', AREA_CSV),
    Step('lightning', 'O614', 'gen_lightning_fx.py', 'the bolt from the sky, drawn by code', {'effects': (4742, 5320)}, (), None,
         LIGHTNING_CSV),
)
BY_KEY = {s.key: s for s in STEPS}
ORDER = tuple(s.key for s in STEPS)


def rows_of(path):
    with open(path, newline='', encoding='utf-8') as f:
        return list(csv.DictReader(f))


def gives(tables=None):
    """{step: {count: value}}: what a step leaves in the pair, read from the committed tables"""
    t = tables or {}
    spell = t.get('spell') or rows_of(SPELL_CSV)
    status = t.get('status') or rows_of(STATUS_CSV)
    gap = t.get('gap') or rows_of(GAP_CSV)
    area = t.get('area') or rows_of(AREA_CSV)
    creature = t.get('creature') or rows_of(CREATURE_CSV)
    lightning = t.get('lightning') or rows_of(LIGHTNING_CSV)
    return {
        'creature': {'outfits': max(int(r['new']) for r in creature)},
        'spell': {'effects': max(int(r['id']) for r in spell if r['kind'] == 'effect')},
        'status': {'effects': max(int(r['id']) for r in status)},
        'gap': {'effects': max(int(r['id']) for r in gap if r['kind'] == 'effect')},
        'area': {'effects': max(int(r['id']) for r in area if r['kind'] in ('new', 'long'))},
        'lightning': {'effects': max(int(r['id']) for r in lightning if r['kind'] == 'effect')},
    }


def plan(order=ORDER, base=None, out=None):
    """[(step, counts after it)] and the problems of an order: a step the tools would refuse, a step twice or missing"""
    counts = dict(base or BASE)
    out = out if out is not None else gives()
    bad, done, steps = [], [], []
    for key in order:
        s = BY_KEY.get(key)
        if s is None:
            bad.append('%s: no such step' % key)
            continue
        if key in done:
            bad.append('%s: twice' % key)
            continue
        for a in s.after:
            if a not in done:
                bad.append('%s runs after %s' % (key, a))
        for what, (lo, hi) in sorted(s.needs.items()):
            if not lo <= counts[what] <= hi:
                want = '%d' % lo if lo == hi else '%d to %d' % (lo, hi)
                bad.append('%s takes a pair with %s %s, it would get %d' % (key, want, what, counts[what]))
        counts.update(out.get(key, {}))
        done.append(key)
        steps.append((key, dict(counts)))
    for key in ORDER:
        if key not in done:
            bad.append('%s: missing' % key)
    return steps, bad


def order_problems(order=ORDER, base=None, out=None):
    return plan(order, base, out)[1]


# ------------------------------------------------------------------------------------------------------- the inputs
def dat_counts(path):
    """{items, outfits, effects, missiles} of a dat header"""
    with open(path, 'rb') as f:
        head = f.read(12)
    if len(head) < 12:
        raise SystemExit('%s: not a dat' % path)
    _sig, ni, no, ne, nm = struct.unpack('<IHHHH', head)
    return {'items': ni, 'outfits': no, 'effects': ne, 'missiles': nm}


def md5(path):
    h = hashlib.md5()
    with open(path, 'rb') as f:
        for block in iter(lambda: f.read(1 << 22), b''):
            h.update(block)
    return h.hexdigest()


def digests(dirs):
    """{sha256 of every file under the folders}; the files are hashed, never decoded"""
    out = set()
    for d in dirs:
        for base, _dirs, files in os.walk(d):
            for name in files:
                h = hashlib.sha256()
                with open(os.path.join(base, name), 'rb') as f:
                    for block in iter(lambda: f.read(1 << 20), b''):
                        h.update(block)
                out.add(h.hexdigest())
    return out


def wanted(key, tables=None):
    """the 12 hex digests a step's table names"""
    rows = (tables or {}).get(key) or rows_of(BY_KEY[key].table)
    return sorted({r['src'] for r in rows if len(r.get('src') or '') == 12})


def base_md5():
    """the dat md5 of the live pair 72, or None when the live pair is another one"""
    sys.path.insert(0, os.path.join(REPO, 'server', 'tools'))
    try:
        import client_pair
    except ImportError:
        return None
    finally:
        sys.path.pop(0)
    return client_pair.PAIR_ASSETS_DAT_MD5 if client_pair.PAIR_ASSETS == PAIR - 1 else None


def source_dirs(a):
    return {'wings': [a.wings_src] if a.wings_src else [], 'creature': [a.creature_src], 'spell': [a.spell_src],
            'status': [a.status_src] if a.status_src else [], 'gap': [a.gap_src], 'area': list(a.area_src or [])}


def input_problems(a, tables=None, want_md5=None, free=None):
    """what stops the build before it starts"""
    bad = []
    dat, spr = os.path.join(a.p72, 'Tibia.dat'), os.path.join(a.p72, 'Tibia.spr')
    if not (os.path.isfile(dat) and os.path.isfile(spr)):
        bad.append('%s: no Tibia.dat and Tibia.spr' % a.p72)
    else:
        c = dat_counts(dat)
        for what, n in sorted(BASE.items()):
            if c[what] != n:
                bad.append('%s: %d %s, pair 72 has %d' % (dat, c[what], what, n))
        if want_md5 and not a.any_base and md5(dat) != want_md5:
            bad.append('%s: not the dat of the live pair 72 (md5 %s); --any-base takes it all the same' % (dat, want_md5))
        need = 2 * os.path.getsize(spr) + (256 << 20)
        room = free if free is not None else free_bytes(a.work or a.out)
        if room < need:
            bad.append('%s: %d MB free, the build needs %d MB (two pairs)' % (a.work or a.out, room >> 20, need >> 20))
    if os.path.exists(a.out):
        bad.append('%s exists: remove it or name another folder' % a.out)
    srcs = source_dirs(a)
    for s in STEPS:
        if not s.src:
            continue
        dirs = srcs[s.src]
        if s.key == 'wings':
            if not dirs:
                continue
            for r in (tables or {}).get('sheets') or rows_of(WINGS_SHEETS_CSV):
                p = os.path.join(dirs[0], '%s.png' % r['wings'])
                if not os.path.isfile(p):
                    bad.append('--wings-src: no sheet %s' % p)
                elif hashlib.sha256(open(p, 'rb').read()).hexdigest() != r['sha256']:
                    bad.append('--wings-src: %s is not the sheet of drawn_wings/pixellab_rows.csv' % p)
            continue
        if not dirs:
            bad.append('--%s-src: no folder named' % s.src)
            continue
        missing = [d for d in dirs if not os.path.isdir(d)]
        if missing:
            bad.extend('--%s-src: %s is no folder' % (s.src, d) for d in missing)
            continue
        have = {h[:12] for h in digests(dirs)}
        lost = [w for w in wanted(s.key, tables) if w not in have]
        if lost:
            bad.append('--%s-src: %d of %d pictures of %s are not there (%s)'
                       % (s.src, len(lost), len(wanted(s.key, tables)), os.path.basename(s.table), ' '.join(lost[:6])))
    bad.extend('order: %s' % b for b in order_problems(a.order))
    return bad


def free_bytes(path):
    path = os.path.abspath(path)
    while not os.path.exists(path):
        path = os.path.dirname(path)
    fs = os.statvfs(path)
    return fs.f_bavail * fs.f_frsize


# ------------------------------------------------------------------------------------------------------- the steps
def tool(name):
    return [sys.executable, '-I', os.path.join(HERE, name)]


def build_cmd(key, a, dat, spr, out, centre_csv):
    s = BY_KEY[key]
    if key == 'centre':
        return tool(s.tool) + ['apply', dat, spr, out, '--csv', centre_csv]
    if key == 'wings':
        return tool(s.tool) + ['apply', dat, spr, out] + (['--src', a.wings_src] if a.wings_src else [])
    cmd = tool(s.tool) + ['build', dat, spr, out]
    for d in source_dirs(a).get(s.src, []):                  # a step drawn by code has no source folder
        cmd += ['--src', d]
    return cmd


def check_cmd(key, a, dat, spr, centre_csv):
    """the step's own check of a pair that holds it; None for the centring once the wings are in (centre_rows_hold)"""
    s = BY_KEY[key]
    if key == 'centre':
        return tool(s.tool) + ['check', dat, spr, '--csv', centre_csv]
    if key == 'wings':
        return tool(s.tool) + ['live', dat, spr] + (['--src', a.wings_src] if a.wings_src else [])
    return tool(s.tool) + ['live', dat, spr]


def measure_cmd(dat, spr, centre_csv):
    return tool('gen_outfit_centre.py') + ['measure', dat, spr, '--csv', centre_csv]


def table_grew(old_text, new_text):
    """the measured centre table is the committed one plus rows of new looks at its end: the number of new rows, or
    None when a committed row changed"""
    old, new = old_text.splitlines(), new_text.splitlines()
    if new[:len(old)] != old:
        return None
    return len(new) - len(old)


def class_looks(class_rows):
    """the looks the class step (O618) rewrites"""
    return {int(v) for r in class_rows for v in r['looks'].split('+')}


def allow_changed(centre_rows, wings_rows, area_rows, spell_rows, class_rows=()):
    """the things of pair 72 that pair 73 changes in place, for check_pair.py --allow-changed"""
    outfits = sorted({int(r['look']) for r in centre_rows if r['action'] == 'move'} | {int(r['look']) for r in wings_rows}
                     | class_looks(class_rows))
    effects = sorted(int(r['id']) for r in area_rows if r['kind'] == 'refill')
    missiles = sorted(int(r['id']) for r in spell_rows if r['kind'] == 'missile')
    parts = [('outfit', outfits), ('effect', effects), ('missile', missiles)]
    return ';'.join('%s:%s' % (cat, ','.join(str(i) for i in ids)) for cat, ids in parts if ids)


def centre_rows_hold(dat, spr, centre_csv):
    """after the wings: every moved look still stands where its row says (the wings rows of the table are stale then; the class
    looks of O618 are drawn again and stand on the point by their own table)"""
    sys.path.insert(0, HERE)
    import gen_outfit_centre as C
    from datspr import Dat, Spr
    d, s = Dat(dat), Spr(spr)
    skip = class_looks(rows_of(CLASS_CSV))
    bad = [r['look'] for r in C.read_csv(centre_csv)
           if r['action'] == 'move' and int(r['look']) not in skip and C.row_state(r, d.outfits[int(r['look']) - 1], s) != 'after']
    return ['outfit %s is not where its row of the centre table puts it' % look for look in bad]


def say_now(text):
    print(text, flush=True)


def run(cmd, log):
    """a tool, its output kept short; stops the build when it fails"""
    t0 = time.time()
    p = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, errors='replace')
    lines = p.stdout.strip().splitlines()
    for line in lines[-3:] if p.returncode == 0 else lines[-25:]:
        log('    ' + line[:300])
    if p.returncode:
        raise SystemExit('FAILED (exit %d): %s' % (p.returncode, ' '.join(cmd[2:])))
    return time.time() - t0


def build(a, run=run, log=say_now, hold=centre_rows_hold):
    """the whole build; returns the lines of the build log"""
    work = a.work or a.out.rstrip('/') + '.work'
    if os.path.exists(work):
        raise SystemExit('%s exists: remove it (a build that stopped) or name another --work' % work)
    os.makedirs(work)
    notes = []

    def say(text):
        log(text)
        notes.append(text)

    base_dat, base_spr = os.path.join(a.p72, 'Tibia.dat'), os.path.join(a.p72, 'Tibia.spr')
    say('pair %d build, base %s: dat %s spr %s' % (PAIR, a.p72, md5(base_dat), md5(base_spr)))
    say('wings: %s' % ('the ten painted rows from %s, 111 by code' % a.wings_src if a.wings_src else 'all 121 by code'))
    centre_csv = os.path.join(work, 'outfit_centre.csv')
    log('measure: the centre table on the base pair')
    run(measure_cmd(base_dat, base_spr, centre_csv), log)
    grew = table_grew(open(CENTRE_CSV, encoding='utf-8').read(), open(centre_csv, encoding='utf-8').read())
    if grew is None:
        raise SystemExit('pair_fixes/outfit_centre.csv: a row is not what the base pair gives; measure it and look why')
    say('centre table: %d rows for looks pair 71 did not have%s' % (grew, '' if grew == 0 else ' (commit build/outfit_centre.csv)'))
    steps, bad = plan(a.order)
    if bad:
        raise SystemExit('order: ' + '; '.join(bad))
    cur, cur_dat, cur_spr = a.p72, base_dat, base_spr
    for i, (key, counts) in enumerate(steps, 1):
        s = BY_KEY[key]
        out = os.path.join(work, key)
        log('step %d %s (%s, %s)' % (i, key, s.onum, s.tool))
        secs = run(build_cmd(key, a, cur_dat, cur_spr, out, centre_csv), log)
        dat, spr = os.path.join(out, 'Tibia.dat'), os.path.join(out, 'Tibia.spr')
        if not os.path.exists(spr):                       # a step that changed the dat alone leaves the spr to us
            shutil.copyfile(cur_spr, spr)
        shutil.rmtree(os.path.join(out, 'strips'), ignore_errors=True)   # the cut art of a step: never kept beside the pair
        secs += run(check_cmd(key, a, dat, spr, centre_csv), log)
        got = dat_counts(dat)
        if any(got[k] != v for k, v in counts.items()):
            raise SystemExit('%s: the output has %s, the plan says %s' % (key, got, counts))
        say('step %d %-8s %-11s ok  %4d s  outfits %d effects %d missiles %d  dat %s spr %s'
            % (i, key, s.onum, secs, got['outfits'], got['effects'], got['missiles'], md5(dat), md5(spr)))
        if cur != a.p72:
            shutil.rmtree(cur)
        cur, cur_dat, cur_spr = out, dat, spr
    log('final checks on the built pair')
    done = [k for k, _c in steps]
    for key in done:
        if key == 'centre' and 'wings' in done:
            bad = hold(cur_dat, cur_spr, centre_csv)
            if bad:
                raise SystemExit('; '.join(bad[:10]))
            continue
        run(check_cmd(key, a, cur_dat, cur_spr, centre_csv), log)
    for name in ('gen_fun_costumes.py', 'gen_ki_auras.py'):
        run(tool(name) + ['live', cur_dat, cur_spr], log)
    allow = allow_changed(rows_of(centre_csv), rows_of(WINGS_CSV), rows_of(AREA_CSV), rows_of(SPELL_CSV), rows_of(CLASS_CSV))
    run(tool('check_pair.py') + [cur_dat, cur_spr, '--old', base_dat, base_spr, '--new-only', '--allow-changed', allow], log)
    say('final: every step holds on the built pair; against pair 72 only the listed things changed (%d outfits, %d effects, '
        '%d missiles in place)' % tuple(len(p.split(':')[1].split(',')) for p in allow.split(';')))
    extra = os.path.join(cur, 'build')
    os.makedirs(extra)
    shutil.move(centre_csv, os.path.join(extra, 'outfit_centre.csv'))
    got = dat_counts(cur_dat)
    say('pair %d: %d items, %d outfits, %d effects, %d missiles' % (PAIR, got['items'], got['outfits'], got['effects'],
                                                                 got['missiles']))
    say('Tibia.dat md5 %s  %d bytes' % (md5(cur_dat), os.path.getsize(cur_dat)))
    say('Tibia.spr md5 %s  %d bytes' % (md5(cur_spr), os.path.getsize(cur_spr)))
    with open(os.path.join(extra, 'pair73_build.txt'), 'w', encoding='utf-8') as f:
        f.write('\n'.join(notes) + '\n')
    shutil.move(cur, a.out)
    os.rmdir(work)
    log('wrote %s' % a.out)
    return notes


def parse(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('p72', metavar='P72_DIR')
    ap.add_argument('out', metavar='OUT_DIR')
    ap.add_argument('--creature-src')
    ap.add_argument('--spell-src')
    ap.add_argument('--status-src')
    ap.add_argument('--gap-src')
    ap.add_argument('--area-src', action='append')
    ap.add_argument('--wings-src')
    ap.add_argument('--work')
    ap.add_argument('--dry-run', action='store_true')
    ap.add_argument('--any-base', action='store_true')
    ap.add_argument('--order', default=','.join(ORDER), help='the step order (default %(default)s)')
    a = ap.parse_args(argv)
    a.order = tuple(k.strip() for k in a.order.split(',') if k.strip())
    return a


def main(argv=None):
    a = parse(argv)
    for i, (key, counts) in enumerate(plan(a.order)[0], 1):
        s = BY_KEY[key]
        print('plan %d %-8s %-11s %-24s -> outfits %d effects %d' % (i, key, s.onum, s.tool, counts['outfits'], counts['effects']))
    bad = input_problems(a, want_md5=base_md5())
    for b in bad:
        print('problem: ' + b)
    if a.dry_run:
        print('dry run: %s' % ('%d problems' % len(bad) if bad else 'the inputs are ready'))
        return 1 if bad else 0
    if bad:
        return 1
    build(a)
    return 0


if __name__ == '__main__':
    sys.exit(main())
