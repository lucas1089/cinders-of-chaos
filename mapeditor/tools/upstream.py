#!/usr/bin/env python3
"""Where our map editor comes from: the upstream GitHub repository and the pinned commit.

    python3 -I mapeditor/tools/upstream.py [--repo OWNER/NAME] [--credits docs/CREDITS.md] [--pin mapeditor/UPSTREAM]

Prints repo=OWNER/NAME and sha=<40 hex> (the lines go to $GITHUB_OUTPUT as they are).

The repository is never written in this repo outside docs/CREDITS.md (project rule, tools/ci/check_names.py), so it
is taken from, in order: --repo (the workflow input), the environment variable MAPEDITOR_UPSTREAM_REPO (the
repository variable of the same name), else the credits: the entry whose licence names the AGPL and whose use names
the map, with a https://github.com/OWNER/NAME source. Exit 1 when none is found or the pin is not a full sha.
Test: mapeditor/tools/upstream_test.py."""
import os
import re
import sys

SLUG = re.compile(r'^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$')
SOURCE = re.compile(r'https://github\.com/([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+?)(?:\.git)?/?(?:[\s)#]|$)')


def from_credits(text):
    """OWNER/NAME of the AGPL map editor entry of the credits, or None"""
    found = []
    for block in re.split(r'\n(?=- \*\*)', text):
        if not block.startswith('- **'):
            continue
        licence = ' '.join(re.findall(r'^\s+- Licen[cs]e:(.*)$', block, re.M))
        used = ' '.join(re.findall(r'^\s+- Used for:(.*)$', block, re.M))
        source = ' '.join(re.findall(r'^\s+- Source:(.*)$', block, re.M))
        m = SOURCE.search(source + ' ')
        if m and 'AGPL' in licence.upper() and 'map' in used.lower():
            found.append(m.group(1))
    return found[0] if len(found) == 1 else None


def main(argv):
    root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    opts = {'--credits': os.path.join(root, 'docs', 'CREDITS.md'),
            '--pin': os.path.join(root, 'mapeditor', 'UPSTREAM'), '--repo': ''}
    for i in range(0, len(argv), 2):
        if argv[i] not in opts or i + 1 >= len(argv):
            print(__doc__, file=sys.stderr)
            return 2
        opts[argv[i]] = argv[i + 1]
    repo = opts['--repo'].strip() or os.environ.get('MAPEDITOR_UPSTREAM_REPO', '').strip()
    if not repo and os.path.exists(opts['--credits']):
        with open(opts['--credits'], encoding='utf-8') as f:
            repo = from_credits(f.read()) or ''
    if not SLUG.match(repo):
        print('no upstream repository: pass --repo, set the variable MAPEDITOR_UPSTREAM_REPO, or credit the map '
              'editor (AGPL licence, GitHub source) in docs/CREDITS.md', file=sys.stderr)
        return 1
    with open(opts['--pin'], encoding='utf-8') as f:
        words = f.read().split()
    sha = words[0] if words else ''
    if not re.fullmatch(r'[0-9a-f]{40}', sha):
        print('%s: not a full commit sha: %r' % (opts['--pin'], sha), file=sys.stderr)
        return 1
    print('repo=%s' % repo)
    print('sha=%s' % sha)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
