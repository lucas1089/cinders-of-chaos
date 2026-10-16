#!/usr/bin/env python3
"""Test of install_commands.py on a small copy of the base server's command files: the "!" lines of talkactions.xml
commented out, "/" lines kept, a revscript's "!" words out (mixed ones keep the staff word), the stock /pos made staff
only, the login hint commented out, idempotent, --dry-run writes nothing.
Run: python3 -I server/tools/install_commands_test.py"""
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(HERE, 'install_commands.py')

XML = '''<?xml version="1.0" encoding="UTF-8"?>
<talkactions>
	<talkaction words="/ban" separator=" " script="ban.lua" />
	<talkaction words="!online" script="online.lua" />
	<talkaction words="!buyhouse" script="buyhouse.lua" />
</talkactions>
'''
POS = '''local talk = TalkAction("/pos")

function talk.onSay(player, words, param)
	if player:getGroup():getAccess() and param ~= "" then
		local split = param:split(",")
		player:teleportTo(Position(split[1], split[2], split[3]))
	else
		local position = player:getPosition()
		player:sendTextMessage(MESSAGE_STATUS_CONSOLE_BLUE, "Your current position is: " .. position.x .. ".")
	end
	return false
end

talk:separator(" ")
talk:register()
'''
EXP = '''local expCheck = TalkAction("!exp")
function expCheck.onSay(player, words, param)
	return false
end
expCheck:register()
local mixed = TalkAction("/where", "!where")
mixed:register()
'''
LOGIN = '''function onLogin(player)
	player:sendTextMessage(MESSAGE_STATUS_DEFAULT, "To see the commands use: !commands")
	return true
end
'''
CHAOS = 'local t = TalkAction("!bless")\nt:register()\n'

checks = 0


def eq(a, b, msg):
    global checks
    checks += 1
    if a != b:
        raise AssertionError('%s: %r != %r' % (msg, a, b))


def put(root, rel, text):
    path = os.path.join(root, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w', encoding='utf-8', newline='') as f:
        f.write(text)


def get(root, rel):
    with open(os.path.join(root, rel), encoding='utf-8', newline='') as f:
        return f.read()


def run(data, *extra):
    p = subprocess.run([sys.executable, '-I', TOOL, data] + list(extra), capture_output=True, text=True)
    eq(p.returncode, 0, 'exit code ' + p.stderr)
    return p.stdout


with tempfile.TemporaryDirectory() as tmp:
    data = os.path.join(tmp, 'data')
    files = {'talkactions/talkactions.xml': XML, 'scripts/talkactions/position.lua': POS,
             'scripts/customs/exp.lua': EXP, 'creaturescripts/scripts/login.lua': LOGIN,
             'scripts/chaos/gentledeath.lua': CHAOS}
    for rel, text in files.items():
        put(data, rel, text)

    out = run(data, '--dry-run')
    eq('would change' in out, True, 'dry run lists the changes')
    for rel, text in files.items():
        eq(get(data, rel), text, 'dry run writes nothing: ' + rel)

    run(data)
    xml = get(data, 'talkactions/talkactions.xml')
    eq('<talkaction words="/ban" separator=" " script="ban.lua" />' in xml, True, '/ban stays')
    eq('<!-- chaos-menu (Info & Services window): <talkaction words="!online" script="online.lua" /> -->' in xml, True,
       '!online commented out')
    eq(xml.count('<!-- chaos-menu'), 2, 'both "!" lines commented out')

    pos = get(data, 'scripts/talkactions/position.lua')
    lines = pos.split('\n')
    eq(lines[2], 'function talk.onSay(player, words, param)', 'onSay line kept')
    eq(lines[3].strip().startswith('if not player:getGroup():getAccess() then return true end -- chaos-menu'), True,
       '/pos guard is the first line of onSay')
    eq(pos.replace(lines[3] + '\n', ''), POS, 'the rest of /pos unchanged')
    eq('talk:register()' in pos and '-- talk:register()' not in pos, True, '/pos stays registered for staff')

    exp = get(data, 'scripts/customs/exp.lua')
    eq('-- expCheck:register() -- chaos-menu' in exp, True, '!exp registration commented out')
    eq('TalkAction("/where")' in exp, True, 'mixed talkaction keeps its staff word')

    eq('-- player:sendTextMessage' in get(data, 'creaturescripts/scripts/login.lua'), True, 'login hint commented out')
    eq(get(data, 'scripts/chaos/gentledeath.lua'), CHAOS, 'scripts/chaos untouched (!bless stays)')

    before = {rel: get(data, rel) for rel in files}
    out = run(data)
    eq('nothing to do' in out, True, 'second run: nothing to do')
    for rel in files:
        eq(get(data, rel), before[rel], 'idempotent: ' + rel)

print('install_commands_test: OK (%d checks)' % checks)
