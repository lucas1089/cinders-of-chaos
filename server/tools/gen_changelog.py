#!/usr/bin/env python3
"""Changelog of what reached players, from the git history of the deployed checkout (server/README.md "Changelog").

Run by the kit update (server/deploy/chaos_kit_update.sh) on CHAOS_REPO after the checkout moved, before the restart;
the server's patchnotes.lua serves the file to the client's Patch Notes window (tab Changelog). Stdlib only.

  python3 -I server/tools/gen_changelog.py --repo /opt/chaos/repo --out SERVER/data/changelog/changelog.json \
      [--ref HEAD] [--days 90] [--max 200] [--published-client N] [--releases FILE] [--now UNIX] [--print]

What it lists. The first-parent history of REF (main as deployed). A merge commit "Merge pull request #N ..." (or
"Merge PR N: ...") is one pull request: its own commits (those of the merged branch, no merges) are its entries, dated
by the merge (the day it reached main, which the kit update deploys). A commit pushed straight to main is an entry of
its own. Each commit is classified by the paths it touched:
  server    server/data (not patchnotes/), server/src-patches, server/sql, the install steps of server/tools
            (install_*, patch_*, add_*, adapt_*, apply_*, fix_*; not their tests)
  content   monster, spell, item, NPC and XML data of server/data, and the *_config.lua numbers of the Chaos scripts
  client    client/overlay, client/base-patches, client/MANIFEST.md when the subject names a sprite pair
  website   website/ but its tests, tools and README
A commit with none of these (docs, CI, tests, tools only) is left out. Only the subject line is shown (never the
body): a subject that reads as internal (CI, docs, tests, refactors, deploy tooling) is dropped, internal clauses
("...; docs") and patch numbers ("(base patch 0111)") are cut, and a subject that could carry something private (an
address, a path, an e-mail, a long hex or token, a password word) or a name check_names.py refuses is dropped whole.

Client versions. A client change reaches players with the first client update winpkg-N whose build commit contains
it. The releases are the tags winpkg-N of the checkout (the kit fetches them), the lines "N COMMIT" of --releases FILE
and those the previous output remembered (GitHub prunes old releases with their tags; a version once found is kept).
--published-client N (the live client update): a change in a newer release, or in none yet, is "pending" (the next
client update).

Limits: the last --days days and at most --max entries; each text at most 160 characters; the file at most 200 KB
(oldest entries dropped). Written atomically (a temporary file renamed), mode 0644, and only when its content changed:
running it twice is a no-op. Any failure exits 1 and leaves the old file as it was.
"""
import argparse
import importlib.util
import json
import os
import re
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
FORMAT = 1
MAX_TEXT = 160
MAX_BYTES = 200 * 1024
TAG_ORDER = ('server', 'client', 'content', 'website')

MERGE_PR = re.compile(r'^Merge (?:pull request #|PR )(\d{1,7})\b')
TAG_NAME = re.compile(r'^winpkg-(\d{1,6})$')
SHA = re.compile(r'^[0-9a-f]{7,64}$')

# ---------------------------------------------------------------- paths
SERVER_TOOL = re.compile(r'^server/tools/(install|patch|add|adapt|apply|fix)_[^/]*\.py$')
CONTENT = re.compile(r'^server/data/(monster|spells|items|npc|XML)/|^server/data/scripts/chaos/[^/]*_config\.lua$')
TEST = re.compile(r'(^|/)tests?/|_test\.[a-z]+$|(^|/)test_[^/]*$')
PAIR = re.compile(r'\bpairs? \d+', re.I)


def classify(paths, subject=''):
    """the set of tags of a commit that touched PATHS"""
    tags = set()
    for p in paths:
        if TEST.search(p) or p.endswith('README.md'):
            continue
        if p.startswith('server/data/'):
            if p.startswith('server/data/patchnotes/'):
                continue
            tags.add('content' if CONTENT.search(p) else 'server')
        elif p.startswith(('server/src-patches/', 'server/sql/')) or SERVER_TOOL.match(p):
            tags.add('server')
        elif p.startswith(('client/overlay/', 'client/base-patches/')):
            if not p.endswith('.md'):
                tags.add('client')
        elif p == 'client/MANIFEST.md':
            if PAIR.search(subject):
                tags.add('client')
        elif p.startswith('website/') and not p.startswith('website/tools/'):
            tags.add('website')
    return tags


# ---------------------------------------------------------------- subjects
INTERNAL_START = re.compile(
    r'^(ci|docs?|roadmap|claude\.md|readme|handoff|tests?|refactor(ing)?|lint|typo|wip|merge|revert|fixup!|squash!|'
    r'patch notes|kit update|admin app|map master|deploy|tooling|chore|base\.md|manifest|owner_todo|'
    r'client base\.md|server readme|gm panel|remote admin|cinders admin|windows package|linux package|install|'
    r'website smoke)\b'
    r'|^[\w.-]*[_.][\w.-]*:', re.I)  # "install_orbs: ...": a file or identifier first
# a subject about the project's own tooling or uploads, not the game
INTERNAL_ANY = re.compile(r'windows-assets|owner_todo|\bmanifest\b|\bplugin\b|\bmcp\b|\bclaude\b|\bagents?\b|'
                          r'\b[\w-]+\.(?:sh|py|lua|md|json|ya?ml|otui|otmod|patch|csv)\b', re.I)
INTERNAL_CLAUSE = re.compile(r'^(ci|ci check.*|docs?|tests?|readme|manifest|base\.md|roadmap|owner_todo|refactor.*|'
                             r'(an? |the )?ci check.*)$', re.I)
SHORT_TEST = re.compile(r'\btests?\b', re.I)  # a short clause about tests ("test fixes for the new orbs")
PATCH_NOTE = re.compile(r'\s*\((?:client |server )?(?:base patch|src-patch|patch|install step)[^()]*\)', re.I)
PATCH_LEAD = re.compile(r'^(client |server )?(base patch|src-patch|engine patch) \d+:\s*', re.I)
# a parenthesis for the team: an upload, an approval, a commit, a check
PAREN_INTERNAL = re.compile(r'\s*\((?:[^()]*\b(?:windows-assets|push(?:ed)?|approved|owner|md5|ci|tests?|checks?|land '
                            r'with)\b[^()]*|[0-9a-f]{7,12})\)', re.I)
SENSITIVE = re.compile(
    r'\b\d{1,3}(?:\.\d{1,3}){3}\b'                    # an IPv4 address
    r'|[\w.+-]+@[\w-]+\.[\w.]+'                       # an e-mail address
    r'|https?://|\bwww\.'                             # a link
    r'|(?<![\w.])(?:/(?:opt|etc|var|root|home|srv|usr|tmp|mnt)\b|~/|[A-Za-z]:\\)'  # a path of a machine
    r'|\b[0-9a-f]{16,}\b'                             # a long hex string (a key, a hash)
    r'|[A-Za-z0-9+/_=-]{32,}'                         # a token-looking run
    r'|\b(?:passw(?:or)?d|secret|token|api ?key|private key|ssh|credential|vps|ip address|e-?mail)s?\b',
    re.I)


def _load_names():
    path = os.path.join(os.path.dirname(os.path.dirname(HERE)), 'tools', 'ci', 'check_names.py')
    spec = importlib.util.spec_from_file_location('chaos_check_names', path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod.name_hit


try:
    NAME_HIT = _load_names()
except Exception as e:  # noqa: BLE001 - without the names check nothing may be shown
    NAME_HIT = None
    NAME_ERROR = str(e)


def clean_subject(subject):
    """the subject as players read it, or None when it is internal or could carry something private"""
    s = re.sub(r'\s+', ' ', subject or '').strip()
    s = re.sub(r'\s*\(#\d+\)$', '', s)
    if not s or INTERNAL_START.match(s) or INTERNAL_ANY.search(s):
        return None
    if SENSITIVE.search(s):
        return None
    if NAME_HIT is None or NAME_HIT(s):
        return None
    lead = PATCH_LEAD.match(s)
    if lead:
        s = ('Client: ' if 'client' in (lead.group(1) or '').lower() else '') + s[lead.end():]
    s = PAREN_INTERNAL.sub('', PATCH_NOTE.sub('', s))
    clauses = [c.strip() for c in s.split(';')]
    kept = [c for c in clauses if c and not INTERNAL_CLAUSE.match(c)
            and not (SHORT_TEST.search(c) and len(c.split()) <= 7)]
    if not kept:
        return None
    s = '; '.join(kept).strip(' ;,')
    if len(s) < 4:
        return None
    if len(s) > MAX_TEXT:
        s = s[:MAX_TEXT - 3].rstrip() + '...'
    return s


# ---------------------------------------------------------------- git
class GitError(Exception):
    pass


def git(repo, *args):
    r = subprocess.run(['git', '-C', repo, '-c', 'safe.directory=' + repo, '-c', 'core.quotepath=off'] + list(args),
                       capture_output=True, text=True, encoding='utf-8', errors='replace')
    if r.returncode != 0:
        raise GitError('git %s: %s' % (' '.join(args[:2]), r.stderr.strip()[:200]))
    return r.stdout


def commits_with_paths(repo, revs):
    """[(sha, parents, ct, subject, [paths])] of `git log --no-merges REVS`, newest first"""
    out = git(repo, 'log', '--no-merges', '--no-renames', '--format=%x1e%H%x1f%P%x1f%ct%x1f%s', '--name-only', *revs, '--')
    res = []
    for block in out.split('\x1e')[1:]:
        head, _, rest = block.partition('\n')
        parts = head.split('\x1f')
        if len(parts) != 4:
            continue
        sha, parents, ct, subject = parts
        paths = [p.strip() for p in rest.split('\n') if p.strip()]
        res.append((sha, parents.split(), int(ct), subject, paths))
    return res


def first_parent(repo, ref, since):
    out = git(repo, 'log', '--first-parent', '--format=%H%x1f%P%x1f%ct%x1f%cd%x1f%s', '--date=short',
              '--since=@%d' % since, ref, '--')
    res = []
    for line in out.split('\n'):
        parts = line.split('\x1f')
        if len(parts) == 5:
            res.append((parts[0], parts[1].split(), int(parts[2]), parts[3], parts[4]))
    return res


def tag_releases(repo):
    out = git(repo, 'for-each-ref', '--format=%(refname:strip=2) %(objectname) %(*objectname)', 'refs/tags/winpkg-*')
    rel = {}
    for line in out.split('\n'):
        f = line.split()
        if len(f) >= 2:
            m = TAG_NAME.match(f[0])
            sha = f[2] if len(f) > 2 else f[1]
            if m and SHA.match(sha):
                rel[int(m.group(1))] = sha
    return rel


def read_releases_file(path):
    rel = {}
    with open(path, encoding='utf-8') as f:
        for line in f:
            p = line.split()
            if len(p) >= 2 and not line.startswith('#'):
                n = p[0][7:] if p[0].startswith('winpkg-') else p[0]
                if n.isdigit() and SHA.match(p[1].lower()):
                    rel[int(n)] = p[1].lower()
    return rel


def release_sets(repo, releases, since):
    """{N: set of commit shas the release N contains (back to about the window)}; releases git does not have skipped"""
    sets = {}
    for n in sorted(releases):
        try:
            out = git(repo, 'rev-list', '--since=@%d' % (since - 30 * 86400), releases[n], '--')
        except GitError:
            continue
        sets[n] = set(out.split())
    return sets


# ---------------------------------------------------------------- build
def load_previous(path):
    """(entries by id, releases) of the previous output; nothing when it is missing or unreadable"""
    try:
        if os.path.getsize(path) > 4 * MAX_BYTES:
            return {}, {}
        with open(path, encoding='utf-8') as f:
            data = json.load(f)
    except (OSError, ValueError):
        return {}, {}
    if not isinstance(data, dict):
        return {}, {}
    entries = {}
    for e in data.get('entries') or []:
        if isinstance(e, dict) and isinstance(e.get('id'), str) and isinstance(e.get('client'), int):
            entries[e['id']] = e['client']
    rel = {}
    r = data.get('releases')
    if isinstance(r, dict):
        for k, v in r.items():
            if str(k).isdigit() and isinstance(v, str) and SHA.match(v):
                rel[int(k)] = v
    return entries, rel


def build(repo, ref='HEAD', days=90, max_entries=200, now=None, published=None, extra_releases=None, previous=None):
    now = int(now if now is not None else time.time())
    since = now - days * 86400
    prev_entries, prev_rel = previous or ({}, {})
    head = git(repo, 'log', '-1', '--format=%H%x1f%ct%x1f%cd', '--date=short', ref, '--').strip().split('\x1f')
    if len(head) != 3:
        raise GitError('no commit at ' + ref)

    entries, seen = [], set()
    for sha, parents, ct, day, subject in first_parent(repo, ref, since):
        m = MERGE_PR.match(subject)
        if len(parents) >= 2:
            revs = ['^' + parents[0]] + parents[1:]
            pr = int(m.group(1)) if m else None
        elif len(parents) == 1:
            revs = ['^' + parents[0], sha]
            pr = None
        else:
            continue  # the root, or the edge of a shallow history: no diff to classify
        try:
            commits = commits_with_paths(repo, revs)
        except GitError:
            continue  # a parent outside a shallow history
        for csha, cparents, _cct, csubject, paths in commits:  # dated by the merge: the day it reached main
            if not cparents:
                continue
            tags = classify(paths, csubject)
            if not tags:
                continue
            text = clean_subject(csubject)
            if not text:
                continue
            key = (pr, text.lower()) if pr else (csha,)
            if key in seen:
                continue
            seen.add(key)
            entries.append({'id': csha[:12], 'sha': csha, 'date': day, 'ts': ct, 'pr': pr, 'text': text,
                            'tags': [t for t in TAG_ORDER if t in tags]})
            if len(entries) >= max_entries:
                break
        if len(entries) >= max_entries:
            break

    releases = dict(prev_rel)
    releases.update(extra_releases or {})
    releases.update(tag_releases(repo))
    sets = release_sets(repo, releases, since)
    for e in entries:
        sha = e.pop('sha')
        if 'client' not in e['tags']:
            continue
        n = next((k for k in sorted(sets) if sha in sets[k]), None)
        old = prev_entries.get(e['id'])
        if old is not None and (n is None or old < n):
            n = old
        e['client'] = n
        e['pending'] = n is None or (published is not None and n > published)

    used = {e['client'] for e in entries if e.get('client')}
    keep = sorted(releases)[-20:]
    out = {
        'format': FORMAT,
        'server': {'date': head[2], 'ts': int(head[1])},
        'published': published,
        'releases': {str(k): releases[k] for k in sorted(releases) if k in used or k in keep},
        'entries': entries,
    }
    while entries and len(encode(out)) > MAX_BYTES:
        entries.pop()
    return out


def encode(data):
    return (json.dumps(data, ensure_ascii=False, sort_keys=True, separators=(',', ':')) + '\n').encode('utf-8')


def write_atomic(path, blob):
    """True when the file was written, False when it already had this content"""
    try:
        with open(path, 'rb') as f:
            if f.read(len(blob) + 1) == blob:
                return False
    except OSError:
        pass
    d = os.path.dirname(os.path.abspath(path))
    os.makedirs(d, exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix='.changelog.', dir=d)
    try:
        with os.fdopen(fd, 'wb') as f:
            f.write(blob)
            f.flush()
            os.fsync(f.fileno())
        os.chmod(tmp, 0o644)
        os.replace(tmp, path)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise
    return True


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--repo', required=True)
    ap.add_argument('--out')
    ap.add_argument('--ref', default='HEAD')
    ap.add_argument('--days', type=int, default=90)
    ap.add_argument('--max', type=int, default=200)
    ap.add_argument('--published-client', type=int)
    ap.add_argument('--releases')
    ap.add_argument('--now', type=int)
    ap.add_argument('--print', action='store_true', help='print the entries (and write nothing without --out)')
    a = ap.parse_args(argv)
    if not a.out and not a.print:
        ap.error('--out or --print')
    if NAME_HIT is None:
        print('changelog: the names check (tools/ci/check_names.py) did not load: %s' % NAME_ERROR, file=sys.stderr)
        return 1
    if not (1 <= a.days <= 3650 and 1 <= a.max <= 1000):
        ap.error('--days 1..3650, --max 1..1000')
    if not re.match(r'^[A-Za-z0-9][A-Za-z0-9._/~^-]{0,99}$', a.ref) or '..' in a.ref:
        ap.error('bad --ref')
    published = a.published_client if a.published_client and a.published_client > 0 else None
    try:
        extra = read_releases_file(a.releases) if a.releases else {}
        previous = load_previous(a.out) if a.out else ({}, {})
        data = build(os.path.abspath(a.repo), a.ref, a.days, a.max, a.now, published, extra, previous)
        blob = encode(data)
        if a.print:
            for e in data['entries']:
                v = ''
                if 'client' in e['tags']:
                    v = ' [next client update]' if e['pending'] and e.get('client') is None else \
                        ' [winpkg-%s%s]' % (e['client'], ', pending' if e['pending'] else '')
                print('%s #%s %s: %s%s' % (e['date'], e['pr'] or '-', '/'.join(e['tags']), e['text'], v))
        if a.out:
            wrote = write_atomic(a.out, blob)
            print('changelog: %d entries, server %s, %d bytes%s' % (len(data['entries']), data['server']['date'],
                                                                     len(blob), '' if wrote else ' (unchanged)'))
    except (GitError, OSError, ValueError) as e:
        print('changelog: not written: %s' % e, file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
