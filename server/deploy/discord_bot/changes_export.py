#!/usr/bin/env python3
"""Cinders of Chaos Discord bot: the game's changes for /patch gerar and the automatic patch notes (O385).

Runs as root (chaos-discordbot-sync.timer every 5 minutes, chaos-ctl.sh discord-bot install / patchnotes), never as
the bot: the bot's sandbox cannot read the repository checkout. Two jobs, both idempotent:

  1. changes: DATA/changes.json from `git log --no-merges` of the checkout (REPO). Only commits that touched what
     players get (server/tools/gen_changelog.py classify: server data, engine patches, SQL, install steps, client
     overlay and patches, website) and whose subject is not internal (gen_changelog.clean_subject: CI, docs, tests,
     tooling, anything that could carry an address, a path, a key or a name check_names.py refuses) are kept. Each one:
     sha, ts, date, subject, the first paragraph of the body (ids like O123 cut, dropped when it looks private), tags.
     The last DAYS days (120), at most MAX commits (400), newest first, at most 300 KB. Written only when the
     checkout's HEAD moved (or --force); owner and group of the DATA folder (the bot user), mode 0640.
  2. notes: the patch note files the bot wrote (DATA/patchnotes) that the game does not have yet are copied into
     SERVER_DATA/patchnotes (never overwritten), owner of SERVER_DATA (bot_core.sync_new_notes). The game reads the
     folder at least every 60 seconds.

Exit 1 when the notes were not copied (sync) or the changes not written (changes); a sync whose changes failed
still exits 0 after its line on stderr (the notes matter right now, the changes wait for the next run).

usage: python3 -I changes_export.py sync --repo REPO --data DATA [--server-data DIR] [--force] [--days N] [--max N]
       python3 -I changes_export.py changes --repo REPO --data DATA [--force]
"""
import argparse
import importlib.util
import json
import os
import re
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
FORMAT = 1
MAX_BYTES = 300 * 1024
MAX_BODY = 500
TRAILER = re.compile(r'^(Co-Authored-By|Signed-off-by|Claude-Session|Reviewed-by|Change-Id):', re.I)
ROADMAP_ID = re.compile(r'\s*\(\s*O\d{1,4}(?:\s*[,/]\s*O?\d{1,4})*\s*\)|\bO\d{2,4}\b')
ROADMAP_LEAD = re.compile(r'^\s*O\d{1,4}(?:\s*[,/]\s*O?\d{1,4})*\s*:\s*')
# words for the team, not for players: a path (server/tools/x), a file name (x.lua), an identifier (client_chaos_x)
CODE_WORD = re.compile(r'[\w.-]*[A-Za-z_][\w.-]*/[\w./-]+|\b[\w-]+\.(?:sh|py|lua|md|json|ya?ml|otui|otmod|patch|csv|'
                       r'rs|java|php|sql|xml)\b|\b[a-z0-9]+_[\w]+\b')


def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def body_text(body, gc):
    """The first paragraph of a commit body as one line, roadmap ids cut; '' when it looks private or internal."""
    para = []
    for line in (body or '').split('\n'):
        line = line.strip()
        if not line:
            if para:
                break
            continue
        if TRAILER.match(line):
            break
        para.append(line)
    s = CODE_WORD.sub('', ROADMAP_ID.sub('', ' '.join(para)))
    s = re.sub(r'\(\s*[,;]?\s*\)', '', s)
    s = re.sub(r'\(\s*,\s*', '(', s)
    s = re.sub(r'\s+([,.;:)])', r'\1', re.sub(r'\s+', ' ', s)).strip().lstrip(':;,. ')
    if not s or gc.SENSITIVE.search(s) or gc.NAME_HIT is None or gc.NAME_HIT(s):
        return ''
    if len(s) > MAX_BODY:
        s = s[:MAX_BODY - 3].rstrip() + '...'
    return s


def collect(repo, gc, days=120, max_commits=400, now=None):
    """The player-facing commits of HEAD of `repo`, newest first."""
    now = int(time.time() if now is None else now)
    out = gc.git(repo, 'log', '--no-merges', '--no-renames', '--since=@%d' % (now - days * 86400),
                 '--format=%x1e%H%x1f%ct%x1f%s%x1f%b%x1d', '--name-only', 'HEAD', '--')
    res = []
    for block in out.split('\x1e')[1:]:
        head, _, paths = block.partition('\x1d')
        parts = head.split('\x1f')
        if len(parts) != 4:
            continue
        sha, ct, subject, body = parts
        paths = [p.strip() for p in paths.split('\n') if p.strip()]
        tags = gc.classify(paths, subject)
        if not tags:
            continue
        text = gc.clean_subject(ROADMAP_ID.sub('', ROADMAP_LEAD.sub('', subject)))
        if not text:
            continue
        ts = int(ct)
        res.append({'sha': sha, 'ts': ts, 'date': time.strftime('%Y-%m-%d', time.gmtime(ts)), 'subject': text,
                    'body': body_text(body, gc), 'tags': [t for t in gc.TAG_ORDER if t in tags]})
    res.sort(key=lambda c: -c['ts'])
    return res[:max_commits]


def owner_of(path):
    st = os.stat(path)
    return st.st_uid, st.st_gid


def write_file(path, blob, uid=None, gid=None, mode=0o640):
    d = os.path.dirname(os.path.abspath(path))
    fd, tmp = tempfile.mkstemp(prefix='.changes.', dir=d)
    try:
        with os.fdopen(fd, 'wb') as f:
            f.write(blob)
        os.chmod(tmp, mode)
        if uid is not None and os.geteuid() == 0:
            os.chown(tmp, uid, gid)
        os.replace(tmp, path)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def export_changes(repo, data, force=False, days=120, max_commits=400, now=None):
    """Write DATA/changes.json. Returns (written, count)."""
    gc = load_module('chaos_gen_changelog', os.path.join(repo, 'server', 'tools', 'gen_changelog.py'))
    if gc.NAME_HIT is None:
        raise RuntimeError('the names check (tools/ci/check_names.py) did not load')
    repo = os.path.abspath(repo)
    head = gc.git(repo, 'rev-parse', 'HEAD').strip()
    path = os.path.join(data, 'changes.json')
    if not force:
        try:
            with open(path, encoding='utf-8') as f:
                old = json.load(f)
            if old.get('head') == head and old.get('format') == FORMAT:
                return False, len(old.get('commits') or [])
        except (OSError, ValueError, AttributeError):
            pass
    commits = collect(repo, gc, days, max_commits, now)
    doc = {'format': FORMAT, 'head': head, 'generated_at': int(time.time() if now is None else now), 'days': days,
           'commits': commits}
    blob = json.dumps(doc, ensure_ascii=False, sort_keys=True).encode('utf-8')
    while commits and len(blob) > MAX_BYTES:
        commits.pop()
        blob = json.dumps(doc, ensure_ascii=False, sort_keys=True).encode('utf-8')
    uid, gid = owner_of(data)
    write_file(path, blob + b'\n', uid, gid)
    return True, len(commits)


def sync_notes(data, server_data):
    sys.path.insert(0, HERE)
    import bot_core
    uid, gid = owner_of(server_data)
    return bot_core.sync_new_notes(os.path.join(data, 'patchnotes'), os.path.join(server_data, 'patchnotes'),
                                   uid if os.geteuid() == 0 else None, gid if os.geteuid() == 0 else None)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('job', choices=('sync', 'changes'))
    ap.add_argument('--repo', required=True)
    ap.add_argument('--data', required=True)
    ap.add_argument('--server-data')
    ap.add_argument('--force', action='store_true')
    ap.add_argument('--days', type=int, default=120)
    ap.add_argument('--max', type=int, default=400)
    ap.add_argument('--now', type=int)
    a = ap.parse_args(argv)
    if not (1 <= a.days <= 3650 and 1 <= a.max <= 2000):
        ap.error('--days 1..3650, --max 1..2000')
    if not os.path.isdir(a.data):
        print('changes: no folder %s (discord-bot install first)' % a.data, file=sys.stderr)
        return 1
    rc = 0
    try:
        wrote, n = export_changes(a.repo, a.data, a.force, a.days, a.max, a.now)
        print('changes: %d game change%s%s' % (n, '' if n == 1 else 's', '' if wrote else ' (unchanged)'))
    except Exception as e:  # noqa: BLE001 - one line, the notes copy still runs
        print('changes: not written: %s' % str(e)[:200], file=sys.stderr)
        rc = 1 if a.job == 'changes' else 0  # sync: the notes copy decides; the log keeps this line
    if a.job == 'sync' and a.server_data:
        if not os.path.isdir(a.server_data):
            print('notes: no folder %s' % a.server_data, file=sys.stderr)
            return 1
        try:
            names = sync_notes(a.data, a.server_data)
            for n in names:
                print('copied ' + n)
            print('%d file%s copied' % (len(names), '' if len(names) == 1 else 's'))
        except OSError as e:
            print('notes: not copied: %s' % e, file=sys.stderr)
            rc = 1
    return rc


if __name__ == '__main__':
    sys.exit(main())
