#!/usr/bin/env python3
"""Test of patch_wide_spell_ids.py (config.lua key chaosWideSpellIds) and guard for engine src-patch 0079 (wide spell ids,
server/README.md "Wide spell ids"): the key is added as false and never overwritten by a plain run, --on / --off set it,
a trailing comment and CRLF are kept, a second run changes nothing, --dry-run writes nothing; the patch widens the spell id
to 16 bits, gates the u16 0xA4 packet behind the client's capability bit 6 AND chaosWideSpellIds (default false), keeps the
u8 packet otherwise, and the install_all.py step is wired.
Run: python3 -I server/tools/patch_wide_spell_ids_test.py (standard library only)"""
import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, '..')
TOOL = os.path.join(HERE, 'patch_wide_spell_ids.py')
sys.path.insert(0, HERE)
sys.dont_write_bytecode = True
import patch_wide_spell_ids as P  # noqa: E402

fails = 0


def check(cond, what):
    global fails
    if not cond:
        fails += 1
        print('FAIL', what)


def run(folder, *extra):
    p = subprocess.run([sys.executable, '-I', TOOL, folder] + list(extra), stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    return p.returncode, p.stdout.decode()


STOCK = 'timeBetweenActions = 200\nmapName = "world"\n'
new, old = P.patch(STOCK)
check(old is None and P.parse(new) is False and new.startswith(STOCK + 'chaosWideSpellIds = false -- '), 'missing key added as false')
check(P.patch(new) == (new, 'false'), 'idempotent')
on = new.replace('chaosWideSpellIds = false', 'chaosWideSpellIds = true')
check(P.patch(on) == (on, 'true') and P.parse(on) is True, 'a plain run keeps the owner\'s true')
check(P.patch(on, False)[0] == new and P.patch(new, True)[0] == on, '--off and --on set it, the comment stays')
check(P.patch(STOCK, True)[0].startswith(STOCK + 'chaosWideSpellIds = true'), '--on on a missing key')
check(P.patch('chaosWideSpellIds=false')[0].count('chaosWideSpellIds') == 1, 'no spaces, no final newline: one key')
crlf = STOCK.replace('\n', '\r\n')
check(P.patch(crlf)[0].endswith('\r\n') and '\n' not in P.patch(crlf)[0].replace('\r\n', ''), 'CRLF kept')
check(P.patch('--chaosWideSpellIds = true\n')[0].count('chaosWideSpellIds') == 2, 'a commented-out key is not the key')
check(P.parse('chaosWideSpellIds = "yes"\n') is None, 'not a boolean: None')

with tempfile.TemporaryDirectory() as d:
    cfg = os.path.join(d, 'config.lua')
    with open(cfg, 'w', encoding='utf-8', newline='') as f:
        f.write(STOCK)
    code, text = run(d, '--dry-run')
    check(code == 0 and 'dry run' in text and open(cfg, encoding='utf-8').read() == STOCK, 'dry run writes nothing')
    code, text = run(d)
    check(code == 0 and 'missing -> False' in text, 'first run adds it: ' + text)
    after = open(cfg, encoding='utf-8').read()
    code, text = run(d)
    check(code == 0 and 'already' in text and open(cfg, encoding='utf-8').read() == after, 'second run changes nothing')
    code, text = run(d, '--on')
    check(code == 0 and P.parse(open(cfg, encoding='utf-8').read()) is True, '--on')
    check(run(d)[0] == 0 and P.parse(open(cfg, encoding='utf-8').read()) is True, 'a plain run after --on keeps true')
    check(run(d, '--on', '--off')[0] == 1, '--on with --off is refused')
    check(run(os.path.join(d, 'nope'))[0] == 1, 'no config.lua')

# install_all.py: the step exists, runs the tool and sits after baserain
inst = open(os.path.join(HERE, 'install_all.py'), encoding='utf-8').read()
check("def step_widespellids" in inst and "tool('patch_wide_spell_ids.py')" in inst, 'install_all step widespellids')
check("STEPS.insert(STEPS.index('baserain') + 1, 'widespellids')" in inst or "STEPS.index('shopprices')" in inst, 'step is in STEPS')

# the engine patch
pdir = os.path.join(ROOT, 'src-patches')
mine = sorted(n for n in os.listdir(pdir) if n.startswith('0079-'))
check(mine == ['0079-wide-spell-ids.patch'], 'one patch 0079: %s' % mine)
if mine:
    text = open(os.path.join(pdir, mine[0]), encoding='utf-8').read()
    files = sorted(l[6:].split()[0] for l in text.splitlines() if l.startswith('+++ b/'))
    check(files == ['src/configmanager.cpp', 'src/configmanager.h', 'src/const.h', 'src/luascript.cpp', 'src/player.h',
                    'src/protocolgame.cpp', 'src/protocolgame.h', 'src/spells.h'], 'files touched: %s' % files)
    add = '\n'.join(l[1:] for l in text.splitlines() if l.startswith('+') and not l.startswith('+++'))
    rem = '\n'.join(l[1:] for l in text.splitlines() if l.startswith('-') and not l.startswith('---'))
    check('getGlobalBoolean(L, "chaosWideSpellIds", false)' in add, 'the config key defaults to false')
    check('configKeys", ConfigManager::WIDE_SPELL_IDS' in add, 'configKeys.WIDE_SPELL_IDS registered')
    check('uint16_t spellId = 0;' in add and 'uint8_t spellId = 0;' in rem, 'Spell::spellId is 16 bits')
    check('uint16_t getId() const' in add and 'void setId(uint16_t id)' in add and 'getNumber<uint16_t>(L, 2)' in add,
          'Spell::getId / setId and spell:id() are 16 bits')
    check('GameChaosExtendedSpellIds = 152' in add, 'feature 152 declared')
    check('CHAOS_CAPABILITY_WIDE_SPELL_IDS = 1 << 6' in add, 'capability bit 6')
    check('chaosWideSpellIdsAsked = (capabilities & CHAOS_CAPABILITY_WIDE_SPELL_IDS) != 0' in add, 'the bit is read at login')
    check(re.search(r'if \(chaosWideSpellIdsAsked && g_config\.getBoolean\(ConfigManager::WIDE_SPELL_IDS\)\) \{\s*'
                    r'features\[GameChaosExtendedSpellIds\] = true;\s*chaosWideSpellIds = true;', add),
          'announced only when asked AND allowed')
    check('msg.add<uint16_t>(static_cast<uint16_t>(spellId));' in add and 'msg.addByte(static_cast<uint8_t>(spellId));' in add,
          'u16 with the feature, u8 without')
    check('spellId > (chaosWideSpellIds ? 0xFFFFu : 0xFFu)' in add, 'an id that does not fit sends nothing')
    check('sendSpellCooldown(uint32_t spellId, uint32_t time)' in add, 'the sender takes a u32 (no truncation on the way)')
    check('0xA5' not in add and 'sendSpellGroupCooldown' not in add, 'the group cooldown packet is not widened')
    check(text.count('\n--- a/src/') == len(files), 'every file has a header')

# the pool the quest spells use and the config note exist in the docs
readme = open(os.path.join(ROOT, 'README.md'), encoding='utf-8').read()
check('## Wide spell ids' in readme and 'chaosWideSpellIds' in readme, 'server/README.md section Wide spell ids')
base = open(os.path.join(ROOT, '..', 'client', 'BASE.md'), encoding='utf-8').read()
check('Wide spell ids' in base, 'client/BASE.md note Wide spell ids')

if fails:
    print('%d failure(s)' % fails)
    sys.exit(1)
print('patch_wide_spell_ids_test: ok')
