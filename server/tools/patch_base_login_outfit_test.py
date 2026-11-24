#!/usr/bin/env python3
"""Test of patch_base_login_outfit.py (O761) on the stock login.lua lines: the first-login outfit window and its line commented
out under the marker, the else branch untouched, idempotent, CRLF, a file without the call left alone, --dry-run, bad args;
and the install_all.py step is wired.
Run: python3 -I server/tools/patch_base_login_outfit_test.py"""
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(HERE, 'patch_base_login_outfit.py')
sys.path.insert(0, HERE)
import patch_base_login_outfit as P  # noqa: E402

STOCK = '''function onLogin(player)
	local serverName = configManager.getString(configKeys.SERVER_NAME)
	local loginStr = "Welcome to " .. serverName .. "!"
	if player:getLastLoginSaved() <= 0 then
		loginStr = loginStr .. " Please choose your outfit."
		player:sendOutfitWindow()
	else
		if loginStr ~= "" then
			player:sendTextMessage(MESSAGE_STATUS_DEFAULT, loginStr)
		end
		loginStr = string.format("Your last visit in %s: %s.", serverName, os.date("%d %b %Y %X", player:getLastLoginSaved()))
	end
	player:sendTextMessage(MESSAGE_STATUS_DEFAULT, loginStr)
	return true
end
'''

fails = 0


def check(cond, what):
    global fails
    if not cond:
        fails += 1
        print('FAIL', what)


def run(folder, *extra):
    p = subprocess.run([sys.executable, '-I', TOOL, folder] + list(extra), stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    return p.returncode, p.stdout.decode()


new, status = P.patch(STOCK)
check(status == 'patched', 'patched: ' + status)
check('\t\t-- player:sendOutfitWindow()\n' in new, 'the call commented out')
check('\t\t-- loginStr = loginStr .. " Please choose your outfit."\n' in new, 'the outfit line commented out')
check(new.count(P.MARKER) == 1 and ('\t\t' + P.MARKER + '\n') in new, 'one marker at the branch indent')
check(new.replace('\t\t' + P.MARKER + '\n', '').replace('-- player:sendOutfitWindow', 'player:sendOutfitWindow')
      .replace('-- loginStr = loginStr .. " Please', 'loginStr = loginStr .. " Please') == STOCK, 'nothing else changed')
check(P.patch(new) == (new, 'already'), 'idempotent')
check('Your last visit in' in new and 'else\n\t\tif loginStr' in new, 'the else branch kept')
crlf = STOCK.replace('\n', '\r\n')
out, st = P.patch(crlf)
check(st == 'patched' and out.count('\r\n') == crlf.count('\r\n') + 1 and '\n' not in out.replace('\r\n', ''), 'CRLF kept')
eq0 = STOCK.replace('<= 0 then', '== 0 then')
check(P.patch(eq0)[1] == 'patched', 'the == 0 form too')
none = STOCK.replace('\t\tplayer:sendOutfitWindow()\n', '').replace('\t\tloginStr = loginStr .. " Please choose your outfit."\n', '')
check(P.patch(none) == (none, 'nothing'), 'a file without the call is left alone')
elsewhere = 'function x(player)\n\tplayer:sendOutfitWindow()\nend\n'
check(P.patch(elsewhere) == (elsewhere, 'nothing'), 'a call outside the first-login branch is not touched')

with tempfile.TemporaryDirectory() as d:
    folder = os.path.join(d, 'creaturescripts', 'scripts')
    os.makedirs(folder)
    path = os.path.join(folder, 'login.lua')
    with open(path, 'w', encoding='utf-8', newline='') as f:
        f.write(STOCK)
    code, text = run(d, '--dry-run')
    check(code == 0 and 'dry run' in text, 'dry run reports: ' + text)
    check(open(path, encoding='utf-8').read() == STOCK, 'dry run writes nothing')
    code, text = run(d)
    check(code == 0 and 'removed' in text, 'first run patches: ' + text)
    after = open(path, encoding='utf-8').read()
    check(after == new, 'the file is the patched text')
    code, text = run(d)
    check(code == 0 and 'already' in text and open(path, encoding='utf-8').read() == after, 'second run changes nothing')
    check(run(os.path.join(d, 'nope'))[0] == 1, 'no login.lua')
    check(run(d, 'extra')[0] == 1, 'bad args')

with open(os.path.join(HERE, 'install_all.py'), encoding='utf-8') as f:
    inst = f.read()
check("def step_loginoutfit(" in inst and "patch_base_login_outfit.py" in inst, 'install_all.py has the step')
check("'loginoutfit'" in inst and "  loginoutfit " in inst, 'the step is in the docstring and the order')

print('patch_base_login_outfit_test:', 'OK' if not fails else '%d failure(s)' % fails)
sys.exit(1 if fails else 0)
