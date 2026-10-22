#!/usr/bin/env python3
"""Tests for server/tools/gen_changelog.py (server/README.md "Changelog").

The subject rules and the path classes alone; then a throwaway git repository: a pull request branch whose package
release winpkg-5 is tagged on the branch before the merge, a "Merge pull request #7" merge, a commit straight to main, a
second pull request no release contains yet. Checks: the entries and their tags, the dates of the merge, the internal and
private subjects left out, the client versions and "pending" against the published client update, the window (days and
count), the atomic write that is a no-op the second time, a failure that keeps the old file, a version kept after its
tag is gone (the previous output), a --releases mapping, and a shallow clone (no crash, nothing past its edge).

usage: python3 -I server/tools/gen_changelog_test.py
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gen_changelog as G  # noqa: E402

GEN = os.path.join(HERE, 'gen_changelog.py')
fails = 0


def check(cond, what, extra=''):
    global fails
    if not cond:
        fails += 1
        print('FAIL %s %s' % (what, str(extra)[:600]))


# ---------------------------------------------------------------- subjects
C = G.clean_subject
check(C('Bank: deposits work') == 'Bank: deposits work', 'plain subject kept')
check(C('  Bank:   deposits  work (#12)') == 'Bank: deposits work', 'spaces squeezed, PR suffix cut')
check(C('CI: quote a step name') is None, 'CI dropped')
check(C('Docs: BASE.md entry 68') is None, 'docs dropped')
check(C('ROADMAP: engine hardening') is None, 'roadmap dropped')
check(C('Refactor the loot code') is None, 'refactor dropped')
check(C('Patch notes 2026-10-21: monsters') is None, 'patch notes commits dropped')
check(C('Kit update: fetch the branch') is None, 'deploy tooling dropped')
check(C('install_orbs: keep base names') is None, 'a file name first: dropped')
check(C('Cinders Admin: app and chaos-ctl.sh') is None, 'a script name: dropped')
check(C('Pair 32 on windows-assets: anchors') is None, 'asset uploads dropped')
check(C('Level-scaled monsters: cut five spells; CI check for them') == 'Level-scaled monsters: cut five spells',
      'internal clause cut')
check(C('Pair 35 published: anchors; docs') == 'Pair 35 published: anchors', 'docs clause cut')
check(C('Temple cleanse; test fixes for the new orbs') == 'Temple cleanse', 'short test clause cut')
check(C('Lift names over tall looks (base patch 0111)') == 'Lift names over tall looks', 'patch number cut')
check(C('Client base patch 0116: a busy tile draws effects') == 'Client: a busy tile draws effects', 'patch lead')
check(C('Wings re-centred (pair 32, not pushed)') == 'Wings re-centred', 'upload parenthesis cut')
check(C('Characters nudged left (owner)') == 'Characters nudged left', 'owner parenthesis cut')
check(C('Feet table (407ad9b6) from the pair') == 'Feet table from the pair', 'commit hash cut')
check(C('Void Orb (1,000, like Ember)') == 'Void Orb (1,000, like Ember)', 'a plain parenthesis stays')
for bad in ('Connect to 10.20.30.40 at last', 'Mail admin@example.org about it', 'See https://example.org/x',
            'Logs in /var/log/chaos now', 'Backup from /opt/chaos/repo', 'Key 0123456789abcdef0123 rotated',
            'New password for the panel', 'Token rotation done', 'VPS moved', 'SSH keys for staff',
            'Use QUJDREVGR0hJSktMTU5PUFFSU1RVVldYWVo0123 now', 'Copy C:\\Users\\x\\file'):
    check(C(bad) is None, 'private subject dropped: ' + bad)
check(C('Rings like ' + 'med' + 'ivia') is None, 'a name check_names refuses is dropped')
check(C('word ' * 80).endswith('...') and len(C('word ' * 80)) <= G.MAX_TEXT, 'long subject cut')
check(C('') is None and C('ok') is None, 'empty and too short')

# ---------------------------------------------------------------- paths
K = G.classify
check(K(['server/data/scripts/chaos/bank.lua']) == {'server'}, 'server script')
check(K(['server/data/scripts/chaos/bank_config.lua']) == {'content'}, 'config numbers: content')
check(K(['server/data/monster/rat.xml', 'server/data/spells/x.lua']) == {'content'}, 'monster and spells')
check(K(['server/data/patchnotes/2026-10-22.md']) == set(), 'patch notes files are not a change')
check(K(['server/src-patches/0001-x.patch']) == {'server'}, 'engine patch')
check(K(['server/tools/install_gems.py']) == {'server'}, 'install step')
check(K(['server/tools/install_gems_test.py', 'server/tools/gen_poi.py']) == set(), 'its test and a tool: nothing')
check(K(['server/tests/bank_test.lua', 'docs/X.md', '.github/workflows/ci.yml', 'tools/ci/check.py']) == set(),
      'tests, docs, CI: nothing')
check(K(['client/overlay/modules/game_bank/bank.lua']) == {'client'}, 'client module')
check(K(['client/overlay/modules/game_bank/bank_test.lua']) == set(), 'client test')
check(K(['client/base-patches/0100-x.patch']) == {'client'}, 'client base patch')
check(K(['client/MANIFEST.md'], 'Pair 35 published') == {'client'}, 'MANIFEST with a pair')
check(K(['client/MANIFEST.md'], 'Modules table tidy') == set(), 'MANIFEST alone')
check(K(['client/tools/gen_orb_art.py', 'client/BASE.md']) == set(), 'client tools and docs')
check(K(['website/overlay/plugins/chaos/x.php']) == {'website'}, 'website')
check(K(['website/tests/x_test.php', 'website/tools/gen.py', 'website/README.md']) == set(), 'website tests, tools')

# ---------------------------------------------------------------- a repository
DAY = 86400
T0 = 1790000000  # the first commit (14:13 UTC)
MERGE7 = T0 + 12 * DAY + 10 * 3600  # 00:13 UTC of the next day, still 21:13 of the day before at -0300


def local_day(ts):
    return time.strftime('%Y-%m-%d', time.gmtime(ts - 3 * 3600))


root = tempfile.mkdtemp(prefix='gen_changelog_test_')
repo = os.path.join(root, 'repo')
env = dict(os.environ, GIT_AUTHOR_NAME='t', GIT_AUTHOR_EMAIL='t@example.org', GIT_COMMITTER_NAME='t',
           GIT_COMMITTER_EMAIL='t@example.org', GIT_CONFIG_NOSYSTEM='1', HOME=root, TZ='UTC')
for k in list(env):
    if k.startswith('GIT_DIR') or k == 'GIT_WORK_TREE':
        del env[k]


def run(*args, cwd=None, when=None, ok=True):
    e = dict(env)
    if when is not None:
        e['GIT_AUTHOR_DATE'] = e['GIT_COMMITTER_DATE'] = '@%d -0300' % when
    r = subprocess.run(list(args), cwd=cwd or repo, env=e, capture_output=True, text=True)
    if ok and r.returncode != 0:
        raise AssertionError('%s: %s' % (args, r.stderr))
    return r


def commit(subject, files, when):
    for path, text in files.items():
        p = os.path.join(repo, path)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, 'w') as f:
            f.write(text)
    run('git', 'add', '-A')
    run('git', 'commit', '-q', '-m', subject + '\n\nThe body is never shown: secret 10.0.0.1', when=when)
    return run('git', 'rev-parse', 'HEAD').stdout.strip()


def gen(*args, out=None):
    cmd = [sys.executable, '-I', GEN, '--repo', repo] + (['--out', out] if out else []) + list(args)
    return subprocess.run(cmd, env=env, capture_output=True, text=True)


try:
    os.makedirs(repo)
    run('git', 'init', '-q', '-b', 'main', repo, cwd=root)
    commit('First commit', {'README.md': 'x\n', 'server/data/scripts/chaos/a.lua': '-- a\n'}, T0)
    commit('Old change', {'server/data/scripts/chaos/a.lua': '-- a2\n'}, T0 + 1 * DAY)
    # pull request 7: a branch, its package tagged on the branch before the merge
    run('git', 'checkout', '-q', '-b', 'feat')
    commit('Bank: deposits work', {'server/data/scripts/chaos/bank.lua': '-- bank\n'}, T0 + 10 * DAY)
    b_sha = commit('Client: a new bank window', {'client/overlay/modules/game_bank/bank.lua': '-- w\n'}, T0 + 11 * DAY)
    run('git', 'tag', 'winpkg-5')
    commit('Docs: the bank', {'docs/BANK.md': 'x\n'}, T0 + 11 * DAY + 60)
    commit('Bank tests', {'server/tests/bank_test.lua': '-- t\n'}, T0 + 11 * DAY + 120)
    commit('CI: run the bank test', {'server/data/scripts/chaos/bank.lua': '-- bank2\n'}, T0 + 11 * DAY + 180)
    commit('Bank: reach 10.1.2.3 for payments', {'server/data/scripts/chaos/bank.lua': '-- bank3\n'}, T0 + 11 * DAY + 240)
    commit('Bank numbers; docs', {'server/data/scripts/chaos/bank_config.lua': 'x = 1\n', 'docs/BANK.md': 'y\n'},
           T0 + 11 * DAY + 300)
    run('git', 'checkout', '-q', 'main')
    run('git', 'merge', '-q', '--no-ff', 'feat', '-m', 'Merge pull request #7 from someone/feat', when=MERGE7)
    commit('Monsters: tougher rats', {'server/data/monster/rat.xml': '<monster/>\n'}, T0 + 13 * DAY)
    # pull request 8: a client change no release has yet
    run('git', 'checkout', '-q', '-b', 'feat2')
    c_sha = commit('Client: the bank window remembers its size', {'client/overlay/modules/game_bank/bank.lua': '-- w2\n'},
                   T0 + 14 * DAY)
    commit('Site: bank page', {'website/overlay/bank.php': '<?php\n'}, T0 + 14 * DAY + 60)
    run('git', 'checkout', '-q', 'main')
    run('git', 'merge', '-q', '--no-ff', 'feat2', '-m', 'Merge pull request #8 from someone/feat2', when=T0 + 15 * DAY)
    NOW = T0 + 16 * DAY

    out = os.path.join(root, 'server', 'data', 'changelog', 'changelog.json')
    r = gen('--now', str(NOW), '--published-client', '5', out=out)
    check(r.returncode == 0 and 'changelog: 7 entries' in r.stdout, 'written', r.stdout + r.stderr)
    data = json.load(open(out))
    E = data['entries']
    texts = [e['text'] for e in E]
    check(texts == ['Site: bank page', 'Client: the bank window remembers its size', 'Monsters: tougher rats',
                    'Bank numbers', 'Client: a new bank window', 'Bank: deposits work', 'Old change'],
          'entries newest first', texts)
    by = {e['text']: e for e in E}
    check('Docs: the bank' not in by and 'Bank tests' not in by and 'CI: run the bank test' not in by,
          'docs, tests and CI left out', sorted(by))
    check(not any('10.1.2.3' in t for t in by), 'an address left out', sorted(by))
    check('10.0.0.1' not in json.dumps(data) and 'secret' not in json.dumps(data), 'commit bodies never shown')
    check('First commit' not in by, 'the root commit (no diff) left out')
    pr7 = by.get('Bank: deposits work', {})
    check(pr7.get('pr') == 7 and pr7.get('tags') == ['server'] and pr7.get('date') == local_day(MERGE7) != time.strftime('%Y-%m-%d', time.gmtime(MERGE7)),
          'PR 7 entry dated by its merge (commit time zone)', pr7)
    check(pr7.get('ts') == MERGE7, 'ts is the merge time', pr7)
    check(by.get('Bank numbers', {}).get('tags') == ['content'], 'config numbers are content; docs clause cut')
    win = by.get('Client: a new bank window', {})
    check(win.get('tags') == ['client'] and win.get('client') == 5 and win.get('pending') is False,
          'client change in winpkg-5 (tagged on the branch), published', win)
    rats = by.get('Monsters: tougher rats', {})
    check(rats.get('pr') is None and rats.get('tags') == ['content'] and 'client' not in rats, 'a direct commit', rats)
    new = by.get('Client: the bank window remembers its size', {})
    check(new.get('pr') == 8 and new.get('client') is None and new.get('pending') is True, 'no release yet: pending', new)
    check(by.get('Site: bank page', {}).get('tags') == ['website'], 'website')
    check(data['server']['date'] == local_day(T0 + 15 * DAY) and data['server']['ts'] == T0 + 15 * DAY, 'server date: HEAD',
          data['server'])
    check(data['published'] == 5 and data['releases'] == {'5': b_sha}, 'published and releases', data)
    check(oct(os.stat(out).st_mode & 0o777) == '0o644', 'mode 0644')
    check(not [f for f in os.listdir(os.path.dirname(out)) if f != 'changelog.json'], 'no temporary file left')

    # idempotent
    before = open(out, 'rb').read()
    mtime = os.stat(out).st_mtime_ns
    r = gen('--now', str(NOW), '--published-client', '5', out=out)
    check(r.returncode == 0 and '(unchanged)' in r.stdout and os.stat(out).st_mtime_ns == mtime, 'second run: no-op',
          r.stdout)

    # a failure keeps the old file
    r = gen('--now', str(NOW), '--ref', 'nosuchbranch', out=out)
    check(r.returncode == 1 and 'not written' in r.stderr and open(out, 'rb').read() == before, 'failure: old file kept',
          r.stdout + r.stderr)
    r = gen('--ref', 'HEAD..main', out=out)
    check(r.returncode != 0 and open(out, 'rb').read() == before, 'a range is no --ref')

    # the published update is older than the release: pending
    r = gen('--now', str(NOW), '--published-client', '4', '--print', out=out)
    d4 = json.load(open(out))
    w4 = [e for e in d4['entries'] if e['text'] == 'Client: a new bank window'][0]
    check(w4['client'] == 5 and w4['pending'] is True, 'release 5 not published yet: pending', w4)
    check('[winpkg-5, pending]' in r.stdout and '[next client update]' in r.stdout, '--print lines', r.stdout)

    # the tag is gone (GitHub pruned the release): the previous output keeps the version
    run('git', 'tag', '-d', 'winpkg-5')
    r = gen('--now', str(NOW), '--published-client', '5', out=out)
    d5 = json.load(open(out))
    w5 = [e for e in d5['entries'] if e['text'] == 'Client: a new bank window'][0]
    check(w5['client'] == 5 and d5['releases'] == {'5': b_sha}, 'version kept without the tag', d5)
    # without the previous output, the releases file gives it; a later release then names the newer change
    rel = os.path.join(root, 'releases.txt')
    with open(rel, 'w') as f:
        f.write('# release commit\nwinpkg-5 %s\n6 %s\nbad line\n7 nothex\n' % (b_sha, c_sha))
    out2 = os.path.join(root, 'other.json')
    r = gen('--now', str(NOW), '--published-client', '6', '--releases', rel, out=out2)
    d6 = json.load(open(out2))
    by6 = {e['text']: e for e in d6['entries']}
    check(by6['Client: a new bank window']['client'] == 5 and by6['Client: the bank window remembers its size']['client']
          == 6 and not by6['Client: the bank window remembers its size']['pending'], '--releases mapping', d6['entries'])
    # a broken previous file is ignored, not trusted
    with open(out2, 'w') as f:
        f.write('{"entries": [{"id": 5, "client": "x"}], "releases": {"9": "../../etc"}}')
    r = gen('--now', str(NOW), out=out2)
    check(r.returncode == 0 and '../' not in open(out2).read(), 'a bad previous file is not trusted', r.stderr)

    # the window: days and count
    r = gen('--now', str(NOW), '--days', '3', '--print')
    check(r.returncode == 0 and 'Monsters: tougher rats' in r.stdout and 'Bank: deposits work' not in r.stdout,
          '--days', r.stdout)
    r = gen('--now', str(NOW), '--max', '2', '--print')
    check(len(r.stdout.strip().split('\n')) == 2, '--max', r.stdout)
    r = gen('--now', str(NOW + 400 * DAY), '--print')
    check(r.returncode == 0 and r.stdout.strip() == '', 'everything older than the window', r.stdout)

    # a shallow clone (git clone --depth 1): no crash, nothing past its edge
    shallow = os.path.join(root, 'shallow')
    run('git', 'clone', '-q', '--depth', '1', 'file://' + repo, shallow, cwd=root)
    r = subprocess.run([sys.executable, '-I', GEN, '--repo', shallow, '--now', str(NOW), '--print'], env=env,
                       capture_output=True, text=True)
    check(r.returncode == 0, 'shallow clone: runs', r.stderr)
    run('git', 'fetch', '-q', '--shallow-since=@%d' % (T0 + 9 * DAY), 'origin', cwd=shallow)
    r = subprocess.run([sys.executable, '-I', GEN, '--repo', shallow, '--now', str(NOW), '--print'], env=env,
                       capture_output=True, text=True)
    check(r.returncode == 0 and 'Monsters: tougher rats' in r.stdout and 'Client: the bank window' in r.stdout,
          'deepened shallow clone: the recent entries', r.stdout + r.stderr)


    # the size cap: the oldest entries go
    saved, G.MAX_BYTES = G.MAX_BYTES, 700
    try:
        d = G.build(repo, now=NOW)
        check(len(G.encode(d)) <= 700 and 0 < len(d['entries']) < 7 and d['entries'][0]['text'] == 'Site: bank page',
              'size cap drops the oldest', len(d['entries']))
    finally:
        G.MAX_BYTES = saved
finally:
    shutil.rmtree(root, ignore_errors=True)

if fails:
    print('%d failure(s)' % fails)
    sys.exit(1)
print('gen_changelog_test: OK')
