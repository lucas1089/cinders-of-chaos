#!/usr/bin/env python3
"""Guard for client base patch 0215: modal dialog choices keep 44 characters and the dialog grows to the widest one
(client/BASE.md "0215"; V35, seen in a client 2026-11-27: the Archivist's tale list cut "Cinderhold I: The Torn Ledger
(new)" to 28 characters, so the story quest's state never showed).

Checks on the patch text:
  * it is the only patch numbered 0215 and touches exactly modules/game_modaldialog/modaldialog.lua,
  * the 28 character cut is gone, the choices are cut at `choiceChars` (44) with the tooltip kept for longer ones,
  * the widest choice text is measured and the dialog width takes it (`listWidth`), still capped by maximumWidth,
  * each hunk has as many leading as trailing context lines, and the patch's own lines are consistent (the removed and
    context lines rebuild the old file part, the added and context lines the new one),
then runs the width rule cut from the added lines in LuaJIT (or Lua 5.3) on fake widgets: a long story chapter widens
the dialog, a long text is cut at 44 with its tooltip, the cap of 600 holds, a dialog without choices keeps the old width.
Run: python3 -I client/tools/modal_choices_patch_test.py (standard library; skips the Lua part when no Lua is found)."""
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
PATCHES = os.path.join(HERE, '..', 'base-patches')
NAME = '0215-modal-choices-wider.patch'
fails = 0


def check(cond, what):
    global fails
    if not cond:
        fails += 1
        print('FAIL ' + what)


files = sorted(f for f in os.listdir(PATCHES) if f.endswith('.patch'))
check([f for f in files if f.startswith('0215-')] == [NAME], 'one patch numbered 0215')
text = open(os.path.join(PATCHES, NAME), encoding='utf-8').read()
touched = re.findall(r'^\+\+\+ b/(\S+)', text, re.M)
check(touched == ['modules/game_modaldialog/modaldialog.lua'], 'files: %r' % touched)

removed = [l[1:] for l in text.splitlines() if l.startswith('-') and not l.startswith('---')]
added = [l[1:] for l in text.splitlines() if l.startswith('+') and not l.startswith('+++')]
check(any('short_text(choiceName, 28)' in l for l in removed), 'the 28 character cut is removed')
check(not any('28' in l and 'short_text' in l for l in added), 'no 28 character cut added back')
check(any(l.strip() == 'local choiceChars = 44' for l in added), 'choices keep 44 characters')
check(any('label:setText(short_text(choiceName, choiceChars))' in l for l in added), 'the cut uses choiceChars')
check(any('if #choiceName > choiceChars then' in l for l in added), 'the tooltip for a longer choice stays')
check(any('choicesWidth = math.max(choicesWidth, label:getTextSize().width)' in l for l in added), 'the widest text measured')
width = [l for l in added if 'modalDialog:setWidth(' in l]
check(len(width) == 1 and 'listWidth' in width[0] and 'modalDialog.maximumWidth' in width[0], 'the width takes the list: %r' % width)

hunks = re.split(r'^@@ .*@@.*$', text, flags=re.M)[1:]
check(len(hunks) == 2, 'two hunks')
for hunk in hunks:
    lines = [l for l in hunk.split('\n') if l[:1] in (' ', '+', '-') and not l.startswith('---') and not l.startswith('+++')]
    lead = 0
    while lead < len(lines) and lines[lead].startswith(' '):
        lead += 1
    trail = 0
    while trail < len(lines) and lines[-1 - trail].startswith(' '):
        trail += 1
    check(lead == trail == 3, 'symmetric hunk context (%d / %d)' % (lead, trail))
for head, hunk in zip(re.findall(r'^@@ -\d+,(\d+) \+\d+,(\d+) @@', text, re.M), hunks):
    lines = [l for l in hunk.split('\n') if l[:1] in (' ', '+', '-') and not l.startswith('---') and not l.startswith('+++')]
    old = sum(1 for l in lines if l[:1] in (' ', '-'))
    new = sum(1 for l in lines if l[:1] in (' ', '+'))
    check((old, new) == (int(head[0]), int(head[1])), 'hunk line counts %r against %r' % ((old, new), head))

LUA = r'''
function short_text(text, chars_limit)
  text = tostring(text or '')
  if #text > chars_limit then return text:sub(1, chars_limit) .. '...' end
  return text
end
local CHAR_W = 7 -- a fake font: 7 px a character
local function label(list)
  local l = { text = '', tip = nil }
  function l:setText(t) self.text = t end
  function l:setTooltip(t) self.tip = t end
  function l:getTextSize() return { width = #self.text * CHAR_W } end
  list[#list + 1] = l
  return l
end
local fails = 0
local function eq(a, b, what) if a ~= b then fails = fails + 1; print('FAIL ' .. what .. ': ' .. tostring(a)) end end
-- the patched lines between "local choiceChars" and the loop's end, and the width rule, on fake widgets
local function dialog(choices, buttonsWidth, message)
  local list = {}
  local horizontalPadding = 16
  local modalDialog = { maximumWidth = 600, minimumWidth = 245 }
  local width
  function modalDialog:setWidth(w) width = w end
%s
  for i = 1, #choices do
    local choiceName = choices[i][2]
    local label = label(list)
%s
  end
  local labelWidth = math.min(600, math.floor(message:len() * 1.5))
%s
  return width, list
end
local w, list = dialog({ { 1, 'Teeth in the Cellars (new)' }, { 2, 'Cinderhold I: The Torn Ledger (new)' } }, 120, 'Pick one.')
eq(list[2].text, 'Cinderhold I: The Torn Ledger (new)', 'the story chapter is shown whole')
eq(list[2].tip, nil, 'no tooltip needed')
eq(w, #'Cinderhold I: The Torn Ledger (new)' * CHAR_W + 16 + 24, 'the dialog fits the widest choice')
local long = string.rep('x', 60)
w, list = dialog({ { 1, long } }, 120, 'Pick one.')
eq(#list[1].text, 44 + 3, 'a longer choice is cut at 44')
eq(list[1].tip, long, 'and keeps its tooltip')
w = dialog({ { 1, string.rep('y', 44) } }, 120, string.rep('m', 10))
eq(w <= 600, true, 'never wider than maximumWidth')
w = dialog({}, 120, 'Hello there')
eq(w, 245, 'no choices: the old width rule')
os.exit(fails == 0 and 0 or 1)
'''

head = '\n'.join(l for l in added if 'local choiceChars = 44' in l or 'local choicesWidth = 0' in l)
rule = '\n'.join(l for l in added if 'local listWidth' in l or 'modalDialog:setWidth(' in l)

lua = shutil.which('luajit') or shutil.which('lua5.3')
if lua:
    # the loop body: setText, the tooltip if, the measure; the "end" of the if is context in the patch
    lines = [l for l in added if 'label:setText(short_text(choiceName, choiceChars))' in l]
    lines += [l for l in added if 'if #choiceName > choiceChars then' in l]
    lines += ['      label:setTooltip(choiceName)', '    end']
    lines += [l for l in added if 'choicesWidth = math.max' in l]
    with tempfile.TemporaryDirectory() as d:
        path = os.path.join(d, 'm.lua')
        with open(path, 'w') as fh:
            fh.write(LUA % (head, '\n'.join(lines), rule))
        r = subprocess.run([lua, path], capture_output=True, text=True)
        if r.returncode != 0:
            print(r.stdout + r.stderr)
        check(r.returncode == 0, 'the width rule in ' + os.path.basename(lua))
else:
    print('modal_choices_patch_test: no luajit or lua5.3, the Lua part skipped')

if fails:
    print('modal_choices_patch_test: %d failed' % fails)
    sys.exit(1)
print('modal_choices_patch_test: OK')
