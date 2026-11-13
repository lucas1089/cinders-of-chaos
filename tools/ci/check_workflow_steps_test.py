#!/usr/bin/env python3
"""check_workflow_steps.py: the rule on made-up run blocks, what bash -e really does, and the real workflows (clean).
python3 -I tools/ci/check_workflow_steps_test.py"""
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import check_workflow_steps as C  # noqa: E402

failures = []


def check(name, cond):
    if not cond:
        failures.append(name)
        print("FAIL: " + name)


def bad(block):
    return [line for _, line in C.swallowed(block.strip("\n").split("\n"))]


# 1. the hole itself: a list in the middle of a block
check("check && check in the middle", bad("""
a --check && b --check
echo done
""") == ["a --check && b --check"])
check("three commands", bad("""
a && b && c
echo done
""") == ["a && b && c"])
check("guard and action in the middle", bad("""
[ -f x ] && cp x y
echo done
""") == ['[ -f x ] && cp x y'])
check("list over a backslash", bad("""
a --check \\
  && b --check
echo done
""") == ["a --check \\"])
check("list over a trailing &&", bad("""
a --check &&
  b --check
echo done
""") == ["a --check &&"])
check("list inside a loop", bad("""
for t in 1 2; do
  luajit "$t" && lua5.3 "$t"
done
""") == ['luajit "$t" && lua5.3 "$t"'])
check("group left open over lines", bad("""
(
  cd x && a --check
  echo more
)
""") == ["cd x && a --check"])

# 2. what the rule leaves alone
check("last line of the block", bad("""
echo start
a --check && b --check
""") == [])
check("last line, comment after it", bad("""
a --check && b --check
# a comment
""") == [])
check("one command per line", bad("""
a --check
b --check
echo done
""") == [])
check("group on one line", bad("""
(cd assets && sha256sum -c SUMS)
echo done
""") == [])
check("if condition", bad("""
if [ -n "$A" ] && [ -n "$B" ]; then
  echo both
fi
""") == [])
check("if condition over two lines", bad("""
if gh release list > r.json &&
   [ -s r.json ]; then
  echo both
fi
""") == [])
check("while and until", bad("""
while a && b; do c; done
until a && b; do c; done
echo done
""") == [])
check("own failure branch", bad("""
test -f a && test -f b || { echo missing; exit 1; }
echo done
""") == [])
check("own failure branch over a backslash", bad("""
{ a && b; } > log 2>&1 \\
  && rm -f log || echo t >> FAILED
echo done
""") == [])
check("command substitution", bad("""
tool $([ "$X" = true ] && echo --flag) file
echo done
""") == [])
check("single quotes over lines", bad("""
xargs sh -c '
  a "$1" && b "$1"
' _ x
echo done
""") == [])
check("awk program", bad("""
awk '/x/{p=1; next} p&&/^(diff |--- )/{p=0} p' in > out
echo done
""") == [])
check("double quotes", bad("""
echo "run a && b"
echo done
""") == [])
check("expression", bad("""
echo ${{ a && b }}
echo done
""") == [])
check("comment", bad("""
echo x  # a && b
# a && b
echo done
""") == [])
check("here-document", bad("""
cat > f <<'EOF'
a && b
it's text
EOF
echo done
""") == [])
check("apostrophe in a comment does not open a quote", bad("""
# don't
a --check && b --check
echo done
""") == ["a --check && b --check"])
check("$# is not a comment", bad("""
echo $# && b
echo done
""") == ["echo $# && b"])

# 3. the blocks of a workflow file, with their line numbers
WORKFLOW = """name: x
jobs:
  a:
    steps:
      - name: one line
        run: a --check && b --check
      - name: block
        run: |
          a --check && b --check

          echo done
      - run: |
          echo only
          c && d
"""
blocks = C.run_blocks(WORKFLOW)
check("two blocks", [first for first, _ in blocks] == [9, 13])
check("block body", [line.strip() for line in blocks[0][1]] == ["a --check && b --check", "", "echo done"])
check("trailing empty lines dropped", [line.strip() for line in blocks[1][1]] == ["echo only", "c && d"])

# 4. bash -e as the runner starts a block: the reason for the rule
def bash_e(script):
    return subprocess.run(["bash", "-e", "-c", script]).returncode


check("bash -e goes on after a failure left of &&", bash_e("false && true\ntrue\n") == 0)
check("bash -e stops when the commands are on their own lines", bash_e("false\ntrue\ntrue\n") != 0)
check("bash -e fails on the last line", bash_e("true\nfalse && true\n") != 0)
check("bash -e fails on a group", bash_e("(false && true)\ntrue\n") != 0)
check("bash -e keeps a guard as if", bash_e("if false; then true; fi\ntrue\n") == 0)

# 5. the real workflows are clean
real = []
for name in sorted(os.listdir(os.path.join(C.ROOT, ".github", "workflows"))):
    if name.endswith(".yml"):
        real += C.check_file(os.path.join(C.ROOT, ".github", "workflows", name))
check("real workflows: no swallowed && line (%r)" % real[:3], real == [])

if failures:
    print("%d failure(s)" % len(failures))
    sys.exit(1)
print("check_workflow_steps_test: ok")
