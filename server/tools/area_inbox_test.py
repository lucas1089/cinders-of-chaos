#!/usr/bin/env python3
"""python3 -I server/tools/area_inbox_test.py : area_inbox.py (docs/MAP_GUIDE.md "Map inbox") on a throwaway inbox.

Covers: new from a plan file (only plan.json and meta.json land in the folder), the refusals (an invalid plan writes
nothing, a taken id, a bad id, no endpoint for --from-prompt exits 2 with the set-up text), list, check, approve (only a
pending entry), build (the editor files, files.txt hashes, no chest script, the same bytes on a second build: the compile is
deterministic), publish (list.txt lines, index.json, the status filter), promote (approved only, an origin is needed, a
clash with another plan is refused unless forced, the plan moves, nothing stays in the inbox), remove, find_assets. The
entries of the real inbox must pass `check`. Needs LuaJIT, as area_planner.py does."""
import argparse, hashlib, io, json, os, shutil, sys, tempfile
from contextlib import redirect_stdout

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import area_inbox as T  # noqa: E402

failed = 0


def check(ok, what):
    global failed
    if not ok:
        failed += 1
        print('FAIL:', what)


def run(argv, inbox, **kw):
    """(exit code, output) of main(argv)"""
    buf = io.StringIO()
    with redirect_stdout(buf):
        rc = T.main(argv, inbox=inbox)
    return rc, buf.getvalue()


def call(fn, argv, **kw):
    a = T.parser().parse_args(argv)
    buf = io.StringIO()
    with redirect_stdout(buf):
        try:
            rc = fn(a, **kw)
        except T.InboxError as e:
            rc = 'error: %s' % e
    return rc, buf.getvalue()


def digest(d):
    out = {}
    for root, _, files in os.walk(d):
        for n in files:
            p = os.path.join(root, n)
            out[os.path.relpath(p, d)] = hashlib.sha256(open(p, 'rb').read()).hexdigest()
    return out


def main():
    ex = os.path.join(HERE, 'areaplan', 'examples', 'swamp_hunt.json')
    with tempfile.TemporaryDirectory() as tmp:
        inbox = os.path.join(tmp, 'inbox')
        plans = os.path.join(tmp, 'plans')
        os.makedirs(plans)
        empty = []  # no other plan folders

        rc, out = run(['list'], inbox)
        check(rc == 0 and 'empty' in out, 'list of a missing inbox: ' + out)

        # new
        rc, out = call(T.cmd_new, ['new', '--plan', ex, '--prompt', 'a swamp', '--note', 'n', '--id', 'mire_test'],
                       inbox=inbox, plans_dirs=[plans])
        check(rc == 0 and 'mire_test: pending' in out, 'new from a plan file: %r %s' % (rc, out))
        d = os.path.join(inbox, 'mire_test')
        check(sorted(os.listdir(d)) == ['meta.json', 'plan.json'], 'only plan.json and meta.json in git: %s' % os.listdir(d))
        meta = json.load(open(os.path.join(d, 'meta.json')))
        plan = json.load(open(os.path.join(d, 'plan.json')))
        check(plan['id'] == 'mire_test' and meta['id'] == 'mire_test' and meta['status'] == 'pending', 'id renamed, pending')
        check(meta['prompt'] == 'a swamp' and meta['note'] == 'n' and meta['schema'] == T.SCHEMA, 'prompt and note kept')
        check(set(meta['compiled_sha256']) == {'mire_test.otbm', 'mire_test-frame.otbm', 'mire_test-spawn.xml', 'mire_test.json'},
              'hashes of the four compiled files: %s' % sorted(meta['compiled_sha256']))
        check(meta['stats']['walkable'] > 100 and meta['stats']['monsters'] > 0, 'stats kept')

        rc, out = call(T.cmd_new, ['new', '--plan', ex, '--id', 'mire_test'], inbox=inbox, plans_dirs=[plans])
        check(isinstance(rc, str) and 'taken' in rc, 'a taken id is refused: %r' % (rc,))
        open(os.path.join(plans, 'old_one.json'), 'w').write('{}')
        rc, out = call(T.cmd_new, ['new', '--plan', ex, '--id', 'old_one'], inbox=inbox, plans_dirs=[plans])
        check(isinstance(rc, str) and 'taken' in rc, 'an id of plans/ is refused')
        rc, out = call(T.cmd_new, ['new', '--plan', ex, '--id', 'Bad Id'], inbox=inbox, plans_dirs=[plans])
        check(isinstance(rc, str) and 'bad id' in rc, 'a bad id is refused')
        bad = json.load(open(ex))
        bad['id'] = 'bad_monster'
        bad['spawns'][0]['monster'] = 'No Such Monster'
        badp = os.path.join(tmp, 'bad.json')
        json.dump(bad, open(badp, 'w'))
        rc, out = call(T.cmd_new, ['new', '--plan', badp], inbox=inbox, plans_dirs=[plans])
        check(isinstance(rc, str) and 'not valid' in rc and not os.path.exists(os.path.join(inbox, 'bad_monster')),
              'an invalid plan writes nothing: %r' % (rc,))
        rc, out = call(T.cmd_new, ['new'], inbox=inbox, plans_dirs=[plans])
        check(isinstance(rc, str) and 'exactly one' in rc, 'new needs a source')
        # --level overrides the band of a plan file
        rc, out = call(T.cmd_new, ['new', '--plan', ex, '--id', 'mire_two', '--level', '60', '120'], inbox=inbox,
                       plans_dirs=[plans])
        check(rc == 0 and json.load(open(os.path.join(inbox, 'mire_two', 'plan.json')))['level'] == [60, 120], '--level with --plan')

        # --from-prompt without an endpoint: the set-up text and exit 2
        saved = dict(os.environ)
        for k in list(os.environ):
            if k.startswith('AREAPLAN_') or k in ('ANTHROPIC_API_KEY',):
                del os.environ[k]
        try:
            rc, out = run(['new', '--from-prompt', 'a swamp'], inbox)
        finally:
            os.environ.clear()
            os.environ.update(saved)
        check(rc == 2 and 'No AI endpoint' in out and 'new --plan' in out, 'no endpoint: exit 2 with the set-up text: %r' % rc)

        # list, check
        rc, out = run(['list'], inbox)
        check(rc == 0 and 'mire_test' in out and 'pending' in out and 'mire_two' in out, 'list: ' + out)
        rc, out = run(['list', '--json'], inbox)
        check(rc == 0 and [r['id'] for r in json.loads(out)] == ['mire_test', 'mire_two'], 'list --json')
        rc, out = run(['check'], inbox)
        check(rc == 0 and 'mire_test: ok' in out, 'check: ' + out)
        rc, out = run(['check', 'nope'], inbox)
        check(rc == 1 and 'no inbox entry' in out, 'check of an unknown id')
        open(os.path.join(inbox, 'mire_two', 'meta.json'), 'a').close()
        shutil.rmtree(os.path.join(inbox, 'mire_two'))

        # build: deterministic
        o1, o2 = os.path.join(tmp, 'o1'), os.path.join(tmp, 'o2')
        rc, out = run(['build', 'mire_test', o1], inbox)
        check(rc == 0 and 'pictures skipped' in out, 'build without render inputs says so: ' + out)
        run(['build', 'mire_test', o2], inbox)
        check(digest(o1) == digest(o2), 'two builds give the same bytes')
        names = sorted(os.listdir(os.path.join(o1, 'mire_test')))
        check(names == ['NOTE.txt', 'files.txt', 'mire_test-frame.otbm', 'mire_test-spawn.xml', 'mire_test.json',
                        'mire_test.otbm', 'plan.json'], 'build files: %s' % names)
        sums = {}
        for line in open(os.path.join(o1, 'mire_test', 'files.txt')):
            h, n = line.rstrip('\n').split('  ', 1)
            sums[n] = h
        check(set(sums) == set(names) - {'files.txt'}, 'files.txt lists every file but itself')
        check(all(hashlib.sha256(open(os.path.join(o1, 'mire_test', n), 'rb').read()).hexdigest() == h for n, h in sums.items()),
              'files.txt hashes match')
        check(sums['mire_test.otbm'] == meta['compiled_sha256']['mire_test.otbm'], 'the build equals the bytes hashed at new')
        check('differ' not in out, 'no generator-changed note on a fresh entry')
        # the note appears when the hashes differ
        m2 = json.load(open(os.path.join(d, 'meta.json')))
        m2['compiled_sha256']['mire_test.otbm'] = '0' * 64
        json.dump(m2, open(os.path.join(d, 'meta.json'), 'w'))
        rc, out = run(['build', 'mire_test', o2], inbox)
        check('differ' in out, 'a changed generator is noted')
        json.dump(meta, open(os.path.join(d, 'meta.json'), 'w'))

        # render inputs
        check(T.find_assets(None, {}) is None, 'no assets without a folder')
        ad = os.path.join(tmp, 'assets')
        os.makedirs(ad)
        check(T.find_assets(ad, {}) is None, 'an empty assets folder is none')
        for n in T.ASSET_FILES:
            open(os.path.join(ad, n), 'w').close()
        check(T.find_assets(None, {'AREAINBOX_ASSETS': ad}) == [os.path.join(ad, n) for n in T.ASSET_FILES], 'assets from the env')

        # publish
        rc, out = call(T.cmd_publish, ['publish', os.path.join(tmp, 'pub')], inbox=inbox)
        check(rc == 0, 'publish: %r %s' % (rc, out))
        lt = open(os.path.join(tmp, 'pub', 'list.txt')).read().splitlines()
        check(lt == ['mire_test|pending|50-140|Mirewater Fen'], 'list.txt: %s' % lt)
        idx = json.load(open(os.path.join(tmp, 'pub', 'index.json')))
        check(idx[0]['id'] == 'mire_test' and 'mire_test.otbm' in idx[0]['files'], 'index.json')
        rc, out = call(T.cmd_publish, ['publish', os.path.join(tmp, 'pub2'), '--status', 'approved'], inbox=inbox)
        check(open(os.path.join(tmp, 'pub2', 'list.txt')).read() == '', 'the status filter leaves a pending entry out')
        rc, out = call(T.cmd_publish, ['publish', os.path.join(tmp, 'pub2'), '--status', 'weird'], inbox=inbox)
        check(isinstance(rc, str) and 'unknown status' in rc, 'a bad status is refused')

        # approve, promote
        rc, out = call(T.cmd_promote, ['promote', 'mire_test'], inbox=inbox, plans=plans, plans_dirs=[plans])
        check(isinstance(rc, str) and 'only an approved' in rc, 'promote of a pending entry is refused')
        rc, out = run(['approve', 'mire_test', '--note', 'looks good'], inbox)
        check(rc == 0 and json.load(open(os.path.join(d, 'meta.json')))['status'] == 'approved', 'approve: ' + out)
        rc, out = run(['approve', 'mire_test'], inbox)
        check(rc == 1 and 'not pending' in out, 'approve twice is refused')
        rc, out = call(T.cmd_promote, ['promote', 'mire_test'], inbox=inbox, plans=plans, plans_dirs=[plans])
        check(isinstance(rc, str) and 'no origin' in rc, 'promote needs an origin: %r' % (rc,))
        other = dict(id='other', size=[100, 100], origin=dict(x=15000, y=14500, z=8))
        json.dump(other, open(os.path.join(plans, 'other.json'), 'w'))
        rc, out = call(T.cmd_promote, ['promote', 'mire_test', '--origin', '15050', '14550', '8'], inbox=inbox, plans=plans,
                       plans_dirs=[plans])
        check(isinstance(rc, str) and 'lands on other' in rc, 'a clash is refused: %r' % (rc,))
        rc, out = call(T.cmd_promote, ['promote', 'mire_test', '--origin', '15050', '14550', '9'], inbox=inbox, plans=plans,
                       plans_dirs=[plans])
        check(rc == 0, 'another z is free: %r %s' % (rc, out))
        check(os.path.isfile(os.path.join(plans, 'mire_test.json')), 'the plan is in plans/')
        pl = json.load(open(os.path.join(plans, 'mire_test.json')))
        check(pl['origin'] == dict(x=15050, y=14550, z=9) and pl['id'] == 'mire_test', 'the origin is written')
        check(os.listdir(d) == ['meta.json'], 'only meta.json stays in the inbox')
        mm = json.load(open(os.path.join(d, 'meta.json')))
        check(mm['status'] == 'installed' and mm['promoted_to'].endswith('plans/mire_test.json'), 'status installed')
        check('Remaining' in out and 'install_content_areas.py' in out, 'the remaining steps are printed')
        rc, out = run(['check'], inbox)
        check(rc == 0, 'check passes with an installed entry')
        rc, out = run(['build', 'mire_test', os.path.join(tmp, 'o3')], inbox)
        check(rc == 1 and 'installed' in out, 'an installed entry has no plan to build')
        rc, out = run(['remove', 'mire_test'], inbox)
        check(rc == 1 and 'installed' in out, 'an installed entry is not removed')

        # remove
        rc, out = call(T.cmd_new, ['new', '--plan', ex, '--id', 'gone_soon'], inbox=inbox, plans_dirs=[plans])
        rc, out = run(['remove', 'gone_soon'], inbox)
        check(rc == 0 and not os.path.exists(os.path.join(inbox, 'gone_soon')), 'remove')

    # the real inbox
    rc, out = run(['check'], T.INBOX)
    check(rc == 0, 'the entries of the real inbox pass check: ' + out)

    print('area_inbox_test: %s' % ('FAILED %d' % failed if failed else 'ok'))
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())
