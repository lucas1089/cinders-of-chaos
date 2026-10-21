#!/usr/bin/env python3
"""Tests for the slim client tool (client/tools/slim_client.py): the prune rules on a synthetic tree, the reference
check (a pruned or missing file fails it, a known-missing line does not), and the repo's own slim_prune.txt (it parses,
and its `-` rules match no overlay file but unit tests and notes). Run with python3 -I; CI (.github/workflows/ci.yml)."""
import contextlib
import io
import os
import shutil
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import slim_client as S  # noqa: E402

FAIL = 0


def check(cond, msg):
    global FAIL
    if not cond:
        print('FAIL:', msg)
        FAIL += 1


def write(root, rel, text=''):
    path = os.path.join(root, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w', encoding='utf-8') as fh:
        fh.write(text)


def make_tree(root):
    write(root, 'init.lua', "dofile('/modules/corelib/x.lua')\n")
    write(root, 'modules/corelib/x.lua', 'return 1\n')
    write(root, 'modules/game_a/game_a.otmod', 'Module\n  name: game_a\n  scripts: [ a ]\n')
    write(root, 'modules/game_a/a.lua',
          "local w = g_ui.displayUI('a')\n"
          "w:setImageSource('/images/game/used')\n"
          "local dyn = '/images/game/dyn/' .. name\n")
    write(root, 'modules/game_a/a.otui', 'Panel\n  image-source: /images/game/rel\n  icon: images/local\n')
    write(root, 'modules/game_a/images/local.png', 'png')
    write(root, 'modules/game_a/a_test.lua', "dofile('/images/never')\n")
    write(root, 'data/images/game/used.png', 'png')
    write(root, 'data/images/game/rel.png', 'png')
    write(root, 'data/images/game/dyn/x.png', 'png')
    write(root, 'data/images/big/bg1.png', 'x' * 1000)
    write(root, 'data/images/big/bg2.png', 'x' * 1000)
    write(root, 'data/images/big/keep.png', 'k')
    write(root, 'modules/old_mod/old.otmod', 'Module\n  name: old_mod\n  scripts: [ gone ]\n')


def run(fn, *args):
    out = io.StringIO()
    with contextlib.redirect_stdout(out):
        res = fn(*args)
    return res, out.getvalue()


def main():
    tmp = tempfile.mkdtemp(prefix='slimtest')
    try:
        game = os.path.join(tmp, 'game')
        make_tree(game)
        rules_path = os.path.join(tmp, 'rules.txt')
        write(tmp, 'rules.txt', '# big pictures\n- data/images/big/*\n+ data/images/big/keep.png\n'
                                '# tests\n- modules/*_test.lua\n# dead module\n- modules/old_mod/*\n')
        rules = S.load_rules(rules_path)
        check(S.pruned('data/images/big/bg1.png', rules) == 'big pictures', 'a - rule removes')
        check(S.pruned('data/images/big/keep.png', rules) is None, 'a + rule keeps')
        check(S.pruned('data/images/game/used.png', rules) is None, 'no rule: kept')

        # before the prune: everything resolves; the dead module's own broken script does not count
        errors, unresolved = S.check(game, rules, set())
        check(errors == [], f'clean tree: no errors, got {errors}')
        check(unresolved == 0, f'clean tree: nothing unresolved, got {unresolved}')

        groups, out = run(S.prune, game, rules, False)
        check(not os.path.exists(os.path.join(game, 'data/images/big/bg1.png')), 'pruned file removed')
        check(os.path.exists(os.path.join(game, 'data/images/big/keep.png')), 'kept file stays')
        check(not os.path.exists(os.path.join(game, 'modules/old_mod')), 'emptied folder removed')
        check(not os.path.exists(os.path.join(game, 'modules/game_a/a_test.lua')), 'test removed')
        check(groups['big pictures'] == [2, 2000], f'group sizes: {groups}')
        check('removed 4 files' in out, out)
        errors, _ = S.check(game, rules, set())
        check(errors == [], f'after the prune: no errors, got {errors}')

        # a new reference to a pruned file, before and after the prune
        write(game, 'modules/game_a/b.otui', 'Panel\n  image-source: /images/big/bg1\n')
        errors, _ = S.check(game, rules, set())
        check(len(errors) == 1 and 'resolves to no file' in errors[0], f'missing after prune: {errors}')
        write(game, 'data/images/big/bg1.png', 'x')
        errors, _ = S.check(game, rules, set())
        check(len(errors) == 1 and 'removed by slim_prune.txt' in errors[0], f'pruned before prune: {errors}')
        os.remove(os.path.join(game, 'data/images/big/bg1.png'))
        errors, _ = S.check(game, rules, {'modules/game_a/b.otui /images/big/bg1'})
        check(errors == [], f'a known-missing line is tolerated: {errors}')

        # computed paths are not checked; a missing lua script is
        write(game, 'modules/game_a/game_a.otmod', 'Module\n  name: game_a\n  scripts: [ a, nope ]\n')
        errors, _ = S.check(game, rules, {'modules/game_a/b.otui /images/big/bg1'})
        check(len(errors) == 1 and "'nope'" in errors[0], f'missing otmod script: {errors}')

        # bad rules
        write(tmp, 'bad.txt', '- /abs/path\n')
        try:
            S.load_rules(os.path.join(tmp, 'bad.txt'))
            check(False, 'absolute rule refused')
        except SystemExit:
            pass

        # the repo's rules: they parse, and no overlay file is pruned but unit tests and notes
        rules = S.load_rules()
        check(len(rules) > 10, 'repo rules load')
        overlay = os.path.join(os.path.dirname(S.HERE), 'overlay')
        for dp, dn, fn in os.walk(overlay):
            for name in fn:
                rel = os.path.relpath(os.path.join(dp, name), overlay).replace(os.sep, '/')
                reason = S.pruned(rel, rules)
                if reason and not (name.endswith('_test.lua') or name.endswith('.md')):
                    check(False, f'slim_prune.txt removes the overlay file {rel} ({reason})')
        known = S.load_known_missing()
        check(all(' ' in k for k in known), 'known-missing lines are "<file> <reference>"')
    finally:
        shutil.rmtree(tmp)
    print('slim_client_test:', 'FAIL' if FAIL else 'ok')
    return 1 if FAIL else 0


if __name__ == '__main__':
    sys.exit(main())
