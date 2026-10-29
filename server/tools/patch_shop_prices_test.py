#!/usr/bin/env python3
"""Test of patch_shop_prices.py on the stock requestTrade lines: patched once, idempotent, CRLF, a changed base refused,
--dry-run, bad args, and the patched Lua (run under luajit / lua5.3 when present) sends 0 for -1 and leaves the shop list
alone; the install_all.py step is wired.
Run: python3 -I server/tools/patch_shop_prices_test.py"""
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(HERE, 'patch_shop_prices.py')
sys.path.insert(0, HERE)
import patch_shop_prices as P  # noqa: E402

STOCK = '''	function ShopModule.requestTrade(cid, message, keywords, parameters, node)
		local module = parameters.module
		local itemWindow = {}
		for i = 1, #module.npcHandler.shopItems do
			itemWindow[#itemWindow + 1] = module.npcHandler.shopItems[i]
		end

		if itemWindow[1] == nil then
			return true
		end
		return itemWindow
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


def setup(text):
    d = tempfile.mkdtemp()
    path = os.path.join(d, P.REL)
    os.makedirs(os.path.dirname(path))
    with open(path, 'w', newline='') as f:
        f.write(text)
    return d, path


def read(path):
    with open(path, newline='') as f:
        return f.read()


d, path = setup(STOCK)
code, out = run(d, '--dry-run')
check(code == 0 and read(path) == STOCK, 'dry run changes nothing')
code, out = run(d)
new = read(path)
check(code == 0 and P.MARK in new and 'patched' in out, 'patched: ' + out)
check('itemWindow[#itemWindow + 1] = entry' in new and 'itemWindow[#itemWindow + 1] = module' not in new, 'window gets the entry')
code, out = run(d)
check(code == 0 and read(path) == new and 'already' in out, 'second run changes nothing')

# the patched function, run: -1 goes out as 0, the shop list keeps -1
for lua in ('luajit', 'lua5.3'):
    if shutil.which(lua):
        script = 'local ShopModule = {}\n' + new + '''
local list = {{id = 1, buy = 10, sell = -1, name = "a"}, {id = 2, buy = -1, sell = 5, name = "b"}, {id = 3, buy = 7, sell = 3, name = "c"}}
local w = ShopModule.requestTrade(1, "", {}, {module = {npcHandler = {shopItems = list}}})
assert(w[1].buy == 10 and w[1].sell == 0 and w[1].name == "a", "a")
assert(w[2].buy == 0 and w[2].sell == 5 and w[2].id == 2, "b")
assert(w[3] == list[3], "c is the very entry")
assert(list[1].sell == -1 and list[2].buy == -1, "the shop list keeps -1")
'''
        p = subprocess.run([lua, '-e', script], stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        check(p.returncode == 0, '%s runs the patched function: %s' % (lua, p.stdout.decode()))
shutil.rmtree(d)

d, path = setup(STOCK.replace('\n', '\r\n'))
code, out = run(d)
new = read(path)
check(code == 0 and '\r\n' in new and '\n' not in new.replace('\r\n', ''), 'CRLF kept')
shutil.rmtree(d)

d, path = setup('-- some other modules.lua\n')
code, out = run(d)
check(code == 1 and read(path) == '-- some other modules.lua\n', 'a changed base is refused, untouched')
shutil.rmtree(d)

check(run(tempfile.gettempdir() + '/no-such-folder')[0] == 1, 'missing file')
check(subprocess.run([sys.executable, '-I', TOOL], stdout=subprocess.PIPE).returncode == 1, 'no args')

with open(os.path.join(HERE, 'install_all.py'), encoding='utf-8') as f:
    ia = f.read()
check("'shopprices'" in ia and 'patch_shop_prices.py' in ia and 'def step_shopprices' in ia, 'install_all.py step wired')

print('FAILED %d' % fails if fails else 'patch_shop_prices tests ok')
sys.exit(1 if fails else 0)
