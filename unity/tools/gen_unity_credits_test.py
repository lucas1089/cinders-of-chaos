#!/usr/bin/env python3
"""gen_unity_credits.py: the output of a small credits text, escapes, the committed file is current. python3 -I unity/tools/gen_unity_credits_test.py"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gen_unity_credits as G  # noqa: E402

SAMPLE = '''# Credits
<!-- credits:begin -->
## Team {pt-BR: Equipe}
A note with "quotes" and a backslash \\ here.
- **Pack One**
  - Author: Somebody
  - Credit: Art by Somebody
  - Used for: the "login" screen
## Fonts {pt-BR: Fontes}
- **Font Two**
  - Licence: OFL
<!-- credits:end -->
'''


def main():
    out = G.output(SAMPLE)
    assert 'new CreditSection' in out and 'Title = "Team", Pt = "Equipe"' in out, out
    assert 'a backslash \\\\ here' in out and '\\"quotes\\"' in out, out
    assert 'new CreditEntry { Name = "Pack One", Author = "Somebody", Credit = "Art by Somebody", Use = "the \\"login\\" screen" }' in out, out
    assert 'new CreditEntry { Name = "Font Two", Licence = "OFL" }' in out, out
    assert out.count('new CreditSection') == 2
    # null for a missing field: nothing written for it
    assert 'Author = null' not in out
    # the committed file matches docs/CREDITS.md
    assert G.main(['--check']) == 0
    print('gen_unity_credits_test: ok')


if __name__ == '__main__':
    main()
