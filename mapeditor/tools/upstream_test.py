#!/usr/bin/env python3
"""Tests of upstream.py: the repository from the input, the variable or the credits; the pin check.

    python3 -I mapeditor/tools/upstream_test.py"""
import contextlib
import io
import os
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import upstream  # noqa: E402

CREDITS = """## Tools

- **Some sprite tool**
  - Licence: paid subscription
  - Source: https://github.com/someone/sprites
  - Used for: painting items
- **A map editor**
  - Author: someone
  - Licence: AGPL-3.0; our build ships its patched source
  - Source: https://github.com/example/editor-repo
  - Used for: editing the game map
- **An old map tool**
  - Licence: freeware
  - Source: https://github.com/other/maptool
  - Used for: editing the game map
"""
failures = 0


def check(cond, what):
    global failures
    if not cond:
        failures += 1
        print('FAIL', what)


def run(argv, env=None):
    old = os.environ.pop('MAPEDITOR_UPSTREAM_REPO', None)
    if env:
        os.environ['MAPEDITOR_UPSTREAM_REPO'] = env
    out, err = io.StringIO(), io.StringIO()
    try:
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = upstream.main(argv)
    finally:
        os.environ.pop('MAPEDITOR_UPSTREAM_REPO', None)
        if old is not None:
            os.environ['MAPEDITOR_UPSTREAM_REPO'] = old
    return code, out.getvalue()


check(upstream.from_credits(CREDITS) == 'example/editor-repo', 'the AGPL map entry of the credits')
check(upstream.from_credits(CREDITS.replace('AGPL-3.0', 'MIT')) is None, 'no AGPL map entry')
check(upstream.from_credits(CREDITS + CREDITS) is None, 'two candidates are ambiguous')

with tempfile.TemporaryDirectory() as tmp:
    credits, pin = os.path.join(tmp, 'CREDITS.md'), os.path.join(tmp, 'UPSTREAM')
    with open(credits, 'w') as f:
        f.write(CREDITS)
    sha = 'ab' * 20
    with open(pin, 'w') as f:
        f.write(sha + '\n')
    base = ['--credits', credits, '--pin', pin]
    check(run(base) == (0, 'repo=example/editor-repo\nsha=%s\n' % sha), 'from the credits')
    check(run(base, env='var/repo')[1].startswith('repo=var/repo\n'), 'the variable wins over the credits')
    check(run(base + ['--repo', 'in/put'], env='var/repo')[1].startswith('repo=in/put\n'), 'the input wins')
    check(run(base + ['--repo', 'not a repo'])[0] == 1, 'a bad repository is refused')
    with open(pin, 'w') as f:
        f.write('abc\n')
    check(run(base)[0] == 1, 'a short pin is refused')
    with open(pin, 'w') as f:
        f.write('')
    check(run(base)[0] == 1, 'an empty pin is refused')

root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
with open(os.path.join(root, 'mapeditor', 'UPSTREAM')) as f:
    words = f.read().split()
check(len(words) == 1 and len(words[0]) == 40, 'mapeditor/UPSTREAM holds one full sha')

if failures:
    sys.exit('%d failure(s)' % failures)
print('upstream tests passed')
