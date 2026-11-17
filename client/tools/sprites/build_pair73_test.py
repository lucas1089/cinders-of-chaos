#!/usr/bin/env python3
"""Tests of build_pair73.py (O612): the step order against the tools' input rules, the flags, the dry run and the run of
the steps on fakes (no pair, no art, no tool is started): python3 -I client/tools/sprites/build_pair73_test.py"""
import hashlib
import os
import struct
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import build_pair73 as B  # noqa: E402

N = [0]


def ok(cond, msg):
    N[0] += 1
    if not cond:
        raise SystemExit('FAIL: ' + msg)


def fake_pair(folder, outfits=3526, effects=4742, missiles=253, body=b'spr'):
    os.makedirs(folder)
    with open(os.path.join(folder, 'Tibia.dat'), 'wb') as f:
        f.write(struct.pack('<IHHHH', 0x4A10, 44559, outfits, effects, missiles) + b'rest')
    with open(os.path.join(folder, 'Tibia.spr'), 'wb') as f:
        f.write(body)


def test_order():
    ok(B.order_problems() == [], 'the order of the script is one the tools take: %s' % B.order_problems())
    steps = B.plan()[0]
    ok([k for k, _c in steps] == ['centre', 'wings', 'creature', 'spell', 'status', 'gap', 'area', 'lightning'], 'eight steps in order')
    ok(steps[-1][1]['outfits'] == 3529 and steps[-1][1]['effects'] == 5335 and steps[-2][1]['effects'] == 5330,
       'pair 73 ends at 3,529 outfits and 5,335 effects, the area step at 5,330')
    ok(steps[3][1]['effects'] == 4744 and steps[4][1]['effects'] == 5189 and steps[5][1]['effects'] == 5237,
       'the spell step ends at 4744, the status step at 5189, the gap step at 5237')
    for bad, word in ((('centre', 'wings', 'creature', 'gap', 'spell', 'status', 'area'), 'spell takes'),
                      (('centre', 'wings', 'creature', 'spell', 'gap', 'area', 'status'), 'status takes'),
                      (('centre', 'wings', 'creature', 'spell', 'area', 'status', 'gap'), 'status takes'),
                      (('centre', 'wings', 'creature', 'status', 'spell', 'gap', 'area'), 'spell takes'),
                      (('centre', 'wings', 'creature', 'spell', 'status', 'area', 'gap'), 'gap takes'),
                      (('centre', 'wings', 'creature', 'area', 'spell', 'status', 'gap'), 'spell takes'),
                      (('wings', 'centre', 'creature', 'spell', 'status', 'gap', 'area'), 'wings runs after centre'),
                      (('centre', 'wings', 'spell', 'status', 'gap', 'area'), 'creature: missing'),
                      (('centre', 'wings', 'creature', 'spell', 'gap', 'area'), 'status: missing'),
                      (('centre', 'wings', 'creature', 'creature', 'spell', 'status', 'gap', 'area'), 'creature: twice'),
                      (('centre', 'wings', 'creature', 'status', 'status', 'spell', 'gap', 'area'), 'status: twice'),
                      (('centre', 'wings', 'creature', 'spell', 'status', 'gap', 'lightning', 'area'), 'area takes'),
                      (('centre', 'wings', 'creature', 'spell', 'status', 'lightning', 'gap', 'area'), 'gap takes'),
                      (('centre', 'wings', 'creature', 'spell', 'status', 'gap', 'area'), 'lightning: missing'),
                      (('centre', 'wings', 'creature', 'spell', 'status', 'gap', 'area', 'lightning', 'fx'), 'no such step')):
        ok(any(word in p for p in B.order_problems(bad)), 'refused: %s (%s)' % (','.join(bad), B.order_problems(bad)))
    for free in (('creature', 'centre', 'wings', 'spell', 'status', 'gap', 'area', 'lightning'),
                 ('centre', 'spell', 'status', 'gap', 'wings', 'area', 'lightning', 'creature'),
                 ('spell', 'status', 'gap', 'area', 'creature', 'centre', 'lightning', 'wings')):
        ok(B.order_problems(free) == [], 'also a good order: %s' % ','.join(free))
    ok(B.order_problems(base={'outfits': 3524, 'effects': 4742, 'missiles': 253}), 'a base without the Ki auras is refused')


def test_tool_rules():
    """the needs of STEPS are the numbers the tools refuse by (the tools need numpy only to cut art)"""
    import gen_area_fx as A
    import gen_creature_outfits as K
    import gen_gap_fx as G
    import gen_lightning_fx as L
    import gen_spell_vfx as V
    import gen_status_vfx as T
    need = {s.key: s.needs for s in B.STEPS}
    ok(need['spell'] == {'effects': (V.NEED_EFFECTS, V.NEED_EFFECTS)}, 'spell: exactly %d effects' % V.NEED_EFFECTS)
    ok(need['status'] == {'effects': (T.BASE_EFFECTS, T.RESERVED_LAST)}, 'status: %d to %d effects' % (T.BASE_EFFECTS, T.RESERVED_LAST))
    ok(need['gap'] == {'effects': (G.MIN_EFFECTS, G.FIRST - 1)}, 'gap: %d to %d effects' % (G.MIN_EFFECTS, G.FIRST - 1))
    ok(need['area'] == {'effects': (A.MIN_EFFECTS, A.FIRST - 1)}, 'area: %d to %d effects' % (A.MIN_EFFECTS, A.FIRST - 1))
    ok(need['lightning'] == {'effects': (L.MIN_EFFECTS, L.FIRST - 1)}, 'lightning: %d to %d effects' % (L.MIN_EFFECTS, L.FIRST - 1))
    ok(B.gives()['area']['effects'] == L.FIRST - 1 and L.NEED_MISSILES == 253, 'the lightning block starts right after the area block')
    ok(need['creature'] == {'outfits': (K.OUTFITS_72, K.OUTFITS_72)}, 'creature: exactly %d outfits' % K.OUTFITS_72)
    ok(B.BASE == {'outfits': K.OUTFITS_72, 'effects': V.NEED_EFFECTS, 'missiles': V.NEED_MISSILES}, 'the base is pair 72')
    ok(V.NEED_MISSILES == G.NEED_MISSILES == A.NEED_MISSILES == 253, 'no step takes another missile count')
    out = B.gives()
    ok(out['gap']['effects'] < A.FIRST and out['spell']['effects'] <= T.RESERVED_LAST, 'no block runs into the next')
    ok(out['status']['effects'] < G.FIRST and out['status']['effects'] >= T.FIRST, 'the status block ends before the gap block')
    ok(V.PAIR == G.PAIR == A.PAIR == K.PAIR == T.PAIR == B.PAIR, 'every step is of pair %d' % B.PAIR)
    for s in B.STEPS:
        ok(os.path.isfile(os.path.join(HERE, s.tool)) and os.path.isfile(s.table), '%s: its tool and table are there' % s.key)


def args(tmp, *more):
    return B.parse([os.path.join(tmp, 'p72'), os.path.join(tmp, 'out'), '--creature-src', os.path.join(tmp, 'c'),
                    '--spell-src', os.path.join(tmp, 's'), '--status-src', os.path.join(tmp, 'st'), '--gap-src', os.path.join(tmp, 'g'),
                    '--area-src', os.path.join(tmp, 'a1'), '--area-src', os.path.join(tmp, 'a2')] + list(more))


def put(folder, name, data):
    os.makedirs(folder, exist_ok=True)
    with open(os.path.join(folder, name), 'wb') as f:
        f.write(data)
    return hashlib.sha256(data).hexdigest()


def test_flags_and_dry_run():
    with tempfile.TemporaryDirectory() as tmp:
        a = args(tmp, '--dry-run', '--work', os.path.join(tmp, 'w'), '--order', 'centre, wings,creature,spell,status,gap,area,lightning')
        ok(a.dry_run and a.area_src == [os.path.join(tmp, 'a1'), os.path.join(tmp, 'a2')] and a.wings_src is None, 'flags')
        ok(a.order == B.ORDER and a.work.endswith('w') and not a.any_base, 'the order flag is read, spaces dropped')
        ok(B.source_dirs(a)['wings'] == [] and len(B.source_dirs(a)['area']) == 2, 'source folders by step')
        ok(any('no Tibia.dat' in p for p in B.input_problems(a, free=1 << 40)), 'a missing pair is said')
        fake_pair(os.path.join(tmp, 'p72'))
        tables = {'spell': [{'src': hashlib.sha256(b'sv').hexdigest()[:12]}],
                  'status': [{'src': hashlib.sha256(b'stx').hexdigest()[:12]}, {'src': ''}],
                  'gap': [{'src': hashlib.sha256(b'gx1').hexdigest()[:12]}, {'src': hashlib.sha256(b'gx2').hexdigest()[:12]}],
                  'area': [{'src': hashlib.sha256(b'ar1').hexdigest()[:12]}, {'src': hashlib.sha256(b'ar2').hexdigest()[:12]},
                           {'src': ''}],
                  'creature': [{'src': hashlib.sha256(b'cr').hexdigest()[:12]}], 'sheets': []}
        bad = B.input_problems(a, tables, free=1 << 40)
        ok(len(bad) == 6 and all('is no folder' in p for p in bad), 'six source folders missing: %s' % bad)
        a.status_src = None
        ok(any('--status-src: no folder named' in p for p in B.input_problems(a, tables, free=1 << 40)), 'no --status-src is said')
        a.status_src = os.path.join(tmp, 'st')
        put(os.path.join(tmp, 's'), 'x.png', b'sv')
        ok(len(B.input_problems(a, tables, free=1 << 40)) == 5, 'the status pictures are counted on their own')
        put(os.path.join(tmp, 'st', 'a', 'b'), 'sheet.png', b'stx')
        put(os.path.join(tmp, 'g', 'deep', 'er'), 'one.png', b'gx1')
        put(os.path.join(tmp, 'a1'), 'p.png', b'ar1')
        put(os.path.join(tmp, 'a2'), 'q.png', b'ar2')
        put(os.path.join(tmp, 'c'), 'idle.png', b'cr')
        bad = B.input_problems(a, tables, free=1 << 40)
        ok(len(bad) == 1 and '--gap-src: 1 of 2 pictures' in bad[0], 'a picture that is not there is counted: %s' % bad)
        put(os.path.join(tmp, 'g'), 'two.png', b'gx2')
        ok(B.input_problems(a, tables, free=1 << 40) == [], 'ready: every picture found by digest, in any sub folder')
        ok(any('MB free' in p for p in B.input_problems(a, tables, free=5)), 'no room on the disk is said')
        ok(any('not the dat of the live pair 72' in p for p in B.input_problems(a, tables, want_md5='0' * 32, free=1 << 40)),
           'another base dat is refused')
        a.any_base = True
        ok(B.input_problems(a, tables, want_md5='0' * 32, free=1 << 40) == [], '--any-base takes it')
        a.order = ('centre', 'wings', 'creature', 'gap', 'spell', 'area')
        ok(any(p.startswith('order: spell') for p in B.input_problems(a, tables, free=1 << 40)), 'a bad order is an input problem')
        a.order = B.ORDER
        fake_pair(os.path.join(tmp, 'p72b'), outfits=3524)
        a.p72 = os.path.join(tmp, 'p72b')
        ok(any('3524 outfits' in p for p in B.input_problems(a, tables, free=1 << 40)), 'a pair that is not pair 72 is said')
        a.p72 = os.path.join(tmp, 'p72')
        sha = put(os.path.join(tmp, 'wsrc'), '58.png', b'wing')
        a.wings_src = os.path.join(tmp, 'wsrc')
        tables['sheets'] = [{'wings': '58', 'sha256': sha}, {'wings': '93', 'sha256': 'f' * 64}]
        bad = B.input_problems(a, tables, free=1 << 40)
        ok(len(bad) == 1 and 'no sheet' in bad[0] and '93.png' in bad[0], 'a missing wings sheet is said: %s' % bad)
        tables['sheets'][1] = {'wings': '58', 'sha256': 'e' * 64}
        ok(any('not the sheet' in p for p in B.input_problems(a, tables, free=1 << 40)), 'a wrong wings sheet is said')
        os.makedirs(os.path.join(tmp, 'out'))
        ok(any('exists' in p for p in B.input_problems(a, {**tables, 'sheets': []}, free=1 << 40)), 'OUT_DIR must not exist')


def test_commands():
    with tempfile.TemporaryDirectory() as tmp:
        a = args(tmp, '--wings-src', '/w')
        c = B.build_cmd('centre', a, 'D', 'S', 'O', 'T.csv')
        ok(c[1] == '-I' and c[2].endswith('gen_outfit_centre.py') and c[3:] == ['apply', 'D', 'S', 'O', '--csv', 'T.csv'], 'centre')
        ok(B.build_cmd('wings', a, 'D', 'S', 'O', 'T')[3:] == ['apply', 'D', 'S', 'O', '--src', '/w'], 'wings with sheets')
        ok(B.check_cmd('wings', a, 'D', 'S', 'T')[3:] == ['live', 'D', 'S', '--src', '/w'], 'wings live with the same sheets')
        a.wings_src = None
        ok(B.build_cmd('wings', a, 'D', 'S', 'O', 'T')[3:] == ['apply', 'D', 'S', 'O'], 'wings by code')
        c = B.build_cmd('status', a, 'D', 'S', 'O', 'T')
        ok(c[2].endswith('gen_status_vfx.py') and c[3:] == ['build', 'D', 'S', 'O', '--src', os.path.join(tmp, 'st')], 'status')
        ok(B.check_cmd('status', a, 'D', 'S', 'T')[2:] == B.tool('gen_status_vfx.py')[2:] + ['live', 'D', 'S'], 'status live: all 47 rows')
        c = B.build_cmd('area', a, 'D', 'S', 'O', 'T')
        ok(c[3:] == ['build', 'D', 'S', 'O', '--src', os.path.join(tmp, 'a1'), '--src', os.path.join(tmp, 'a2')], 'area, two folders')
        ok(B.check_cmd('area', a, 'D', 'S', 'T')[2].endswith('gen_area_fx.py') and B.check_cmd('area', a, 'D', 'S', 'T')[3:] ==
           ['live', 'D', 'S'], 'area live: all 70 rows')
        c = B.build_cmd('lightning', a, 'D', 'S', 'O', 'T')
        ok(c[2].endswith('gen_lightning_fx.py') and c[3:] == ['build', 'D', 'S', 'O'], 'lightning: drawn by code, no source folder')
        ok(B.check_cmd('lightning', a, 'D', 'S', 'T')[3:] == ['live', 'D', 'S'], 'lightning live')
        ok(B.check_cmd('centre', a, 'D', 'S', 'T')[3:] == ['check', 'D', 'S', '--csv', 'T'], 'centre check with the measured table')
    ok(B.table_grew('h\na\nb\n', 'h\na\nb\nc\nd\n') == 2 and B.table_grew('h\na\n', 'h\na\n') == 0, 'new looks at the end')
    ok(B.table_grew('h\na\nb\n', 'h\na\nB\nc\n') is None and B.table_grew('h\na\nb\n', 'h\na\n') is None, 'a changed row is found')
    allow = B.allow_changed([{'look': '9', 'action': 'move'}, {'look': '5', 'action': 'keep'}], [{'look': '7'}],
                            [{'id': '1612', 'kind': 'refill'}, {'id': '5300', 'kind': 'new'}],
                            [{'id': '46', 'kind': 'missile'}, {'id': '4743', 'kind': 'effect'}])
    ok(allow == 'outfit:7,9;effect:1612;missile:46', 'only the things changed in place may differ from pair 72: %s' % allow)


def test_build_on_fakes():
    """the run of the steps with a runner that writes fake pairs: order, checks, counts, clean-up, log"""
    with tempfile.TemporaryDirectory() as tmp:
        fake_pair(os.path.join(tmp, 'p72'), body=b'base spr')
        a = args(tmp, '--wings-src', '/w')
        after = dict(B.plan()[0])
        calls, alive = [], []

        def runner(cmd, log):
            name, verb = os.path.basename(cmd[2]), cmd[3]
            calls.append((name, verb))
            if name == 'gen_outfit_centre.py' and verb == 'measure':
                with open(cmd[cmd.index('--csv') + 1], 'w', encoding='utf-8') as f:
                    f.write(open(B.CENTRE_CSV, encoding='utf-8').read() + '9999,other,2x2,report,0,0,0,0,0,0,1,1,1,1,0,0,x\n')
            elif verb in ('apply', 'build'):
                key = os.path.basename(cmd[6])
                ok(os.path.isfile(cmd[4]) and os.path.isfile(cmd[5]), '%s: its input pair is there' % key)
                c = after[key]
                fake_pair(cmd[6], c['outfits'], c['effects'], c['missiles'], body=key.encode())
                if key == 'centre':
                    os.remove(os.path.join(cmd[6], 'Tibia.spr'))          # the dat alone changed
                else:
                    os.makedirs(os.path.join(cmd[6], 'strips'))
                work = os.path.dirname(cmd[6])
                alive.append(sorted(d for d in os.listdir(work) if os.path.isdir(os.path.join(work, d))))
            return 1.0

        held = []
        notes = B.build(a, run=runner, log=lambda t: None, hold=lambda d, s, c: held.append(d) or [])
        builds = [n for n, v in calls if v in ('apply', 'build')]
        ok(builds == [B.BY_KEY[k].tool for k in B.ORDER], 'the eight tools in order: %s' % builds)
        ok(calls[0] == ('gen_outfit_centre.py', 'measure'), 'the centre table is measured first')
        ok(calls[1:3] == [('gen_outfit_centre.py', 'apply'), ('gen_outfit_centre.py', 'check')], 'a check right after each build')
        ok(all(len(d) <= 2 for d in alive) and alive[-1] == ['area', 'lightning'], 'at most two pairs in the work folder: %s' % alive)
        tail = [c for c in calls[17:]]
        ok(tail == [('gen_drawn_wings.py', 'live'), ('gen_creature_outfits.py', 'live'), ('gen_spell_vfx.py', 'live'),
                    ('gen_status_vfx.py', 'live'), ('gen_gap_fx.py', 'live'), ('gen_area_fx.py', 'live'), ('gen_lightning_fx.py', 'live'),
                    ('gen_fun_costumes.py', 'live'), ('gen_ki_auras.py', 'live'),
                    ('check_pair.py', os.path.join(tmp, 'out.work', 'lightning', 'Tibia.dat'))],
           'the final pass: every live again, pair 72, check_pair: %s' % tail)
        ok(len(held) == 1, 'the moved looks are held once after the wings')
        out = os.path.join(tmp, 'out')
        ok(sorted(os.listdir(out)) == ['Tibia.dat', 'Tibia.spr', 'build'] and not os.path.exists(out + '.work'),
           'OUT_DIR holds the pair and build/, no strips, the work folder is gone')
        ok(open(os.path.join(out, 'Tibia.spr'), 'rb').read() == b'lightning', 'the last step is the pair')
        ok(open(os.path.join(tmp, 'p72', 'Tibia.spr'), 'rb').read() == b'base spr' and
           sorted(os.listdir(os.path.join(tmp, 'p72'))) == ['Tibia.dat', 'Tibia.spr'], 'pair 72 is untouched')
        ok(B.dat_counts(os.path.join(out, 'Tibia.dat')) == {'items': 44559, 'outfits': 3529, 'effects': 5335, 'missiles': 253},
           'the counts of pair 73')
        log = open(os.path.join(out, 'build', 'pair73_build.txt'), encoding='utf-8').read()
        ok(log.count('\nstep ') == 8 and 'Tibia.dat md5 ' + B.md5(os.path.join(out, 'Tibia.dat')) in log and
           'centre table: 1 rows' in log and notes[-1].startswith('Tibia.spr md5'), 'the log names every step and the md5s')
        ok(open(os.path.join(out, 'build', 'outfit_centre.csv'), encoding='utf-8').read().endswith(',x\n'), 'the measured table')

        # a step whose output is not what the plan says stops the build; so does a stale work folder
        a2 = args(tmp)
        a2.out = os.path.join(tmp, 'out2')

        def wrong(cmd, log):
            if cmd[3] == 'measure':
                open(cmd[cmd.index('--csv') + 1], 'w', encoding='utf-8').write(open(B.CENTRE_CSV, encoding='utf-8').read())
            elif cmd[3] in ('apply', 'build'):
                fake_pair(cmd[6], outfits=3526, effects=4743)
            return 0.0

        try:
            B.build(a2, run=wrong, log=lambda t: None)
            ok(False, 'a wrong count stops the build')
        except SystemExit as e:
            ok('the plan says' in str(e), 'a wrong count stops the build: %s' % e)
        try:
            B.build(a2, run=wrong, log=lambda t: None)
            ok(False, 'a stale work folder stops the build')
        except SystemExit as e:
            ok('exists' in str(e), 'a stale work folder stops the build')

        def changed(cmd, log):
            if cmd[3] == 'measure':
                text = open(B.CENTRE_CSV, encoding='utf-8').read().splitlines()
                text[5] = text[5] + 'x'
                open(cmd[cmd.index('--csv') + 1], 'w', encoding='utf-8').write('\n'.join(text) + '\n')
            return 0.0

        a3 = args(tmp)
        a3.out = os.path.join(tmp, 'out3')
        try:
            B.build(a3, run=changed, log=lambda t: None)
            ok(False, 'a changed row of the centre table stops the build')
        except SystemExit as e:
            ok('outfit_centre.csv' in str(e), 'a changed row of the centre table stops the build')


def main():
    test_order()
    test_tool_rules()
    test_flags_and_dry_run()
    test_commands()
    test_build_on_fakes()
    print('build_pair73_test: %d checks OK' % N[0])


if __name__ == '__main__':
    main()
