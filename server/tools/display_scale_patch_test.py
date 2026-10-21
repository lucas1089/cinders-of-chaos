#!/usr/bin/env python3
"""Guard for engine src-patch 0037: the display scale (server/README.md "Display scale").

The engine shows each receiving player the damage / heal text messages, its own health and mana (stats packet) and its
energy shield x the factor of that player's level, from the table Lua hands it once (Game.setDisplayScale). This test
reads the patch chain in order and checks:
  * 0037 is in the chain, says it applies after 0001-0036, adds src/chaosdisplay.h, and every hunk of it is a clean
    unified diff (the line counts of each hunk match its header, so `patch` takes it);
  * the last patch that writes ProtocolGame::sendTextMessage scales both damage values, the heal value and the text,
    and only for the damage and heal types (experience stays);
  * 0037 scales health and max health in ProtocolGame::AddPlayerStats; the last patch that writes it is 0052, which
    sends mana and max mana as they are (fixed spell costs, owner 2026-10-21), and 0052 keeps a mana message (typeId
    CHAOS_IMPACT_MANA_DRAIN / _MANA_GAIN of patch 0051) at factor 1;
  * Player::sendEnergyShield scales "es:" and Lua gets Game.setDisplayScale and Player.getDisplayScale;
  * the Lua side calls Game.setDisplayScale with the core's table, and the client opcode (157) is the one of
    chaos_constants.lua, the config and the client module, and no other Chaos opcode uses it.
A fake patch without the scaling is caught (self-test).

Run: python3 -I server/tools/display_scale_patch_test.py (standard library only)."""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, '..', '..'))
PATCHES = os.path.join(HERE, '..', 'src-patches')
CHAOS = os.path.join(HERE, '..', 'data', 'scripts', 'chaos')
CLIENT = os.path.join(ROOT, 'client', 'overlay', 'modules', 'game_chaosscale')
NAME = '0037-display-scale.patch'
MANA = '0052-mana-outside-display-scale.patch'   # mana leaves the display scale (fixed spell costs)
IMPACT = '0051-typed-impact-numbers.patch'       # defines the impact types 0052 reads


def read(path):
    return open(path, encoding='utf-8', errors='replace').read()


def files_of(text):
    """{path: [new-side lines (context and added)]} of a patch"""
    out, cur = {}, None
    for line in text.splitlines():
        if line.startswith('+++ '):
            cur = line[4:].split()[0]
            cur = cur[2:] if cur.startswith('b/') else cur
            out.setdefault(cur, [])
            continue
        if cur and (line.startswith('+') or line.startswith(' ')) and not line.startswith('+++'):
            out[cur].append(line[1:])
    return out


def hunks_ok(text):
    """every @@ hunk has as many old / new lines as its header says"""
    bad = []
    lines = text.splitlines()
    i = 0
    while i < len(lines):
        m = re.match(r'^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@', lines[i])
        if not m:
            i += 1
            continue
        old_n = int(m.group(2) or 1)
        new_n = int(m.group(4) or 1)
        j, o, n = i + 1, 0, 0
        while j < len(lines) and (o < old_n or n < new_n):
            l = lines[j]
            if l.startswith('-'):
                o += 1
            elif l.startswith('+'):
                n += 1
            elif l.startswith(' ') or l == '':
                o += 1
                n += 1
            elif l.startswith('\\'):
                pass
            else:
                break
            j += 1
        if o != old_n or n != new_n:
            bad.append('%s: old %d/%d new %d/%d' % (lines[i], o, old_n, n, new_n))
        i = j
    return bad


def hunks_of(text):
    """[(path, header, [new-side lines])] of a patch: one entry per @@ hunk"""
    out, cur, hunk = [], None, None
    for line in text.splitlines():
        if line.startswith('+++ '):
            cur = line[4:].split()[0]
            cur = cur[2:] if cur.startswith('b/') else cur
            hunk = None
            continue
        if line.startswith('@@'):
            hunk = (cur, line, [])
            out.append(hunk)
            continue
        if hunk and (line.startswith('+') or line.startswith(' ')):
            hunk[2].append(line[1:])
    return out


def function_body(text, path, signature):
    """the new-side lines of the hunks of `path` that belong to a function: the hunk header names it (diff -p) or the
    hunk holds its signature line; '' when the patch does not touch it"""
    body = []
    for p, header, lines in hunks_of(text):
        if p != path:
            continue
        if signature in header or any(signature in l for l in lines):
            body.extend(lines)
    return '\n'.join(body)


def check_text_message(body):
    """problems of a ProtocolGame::sendTextMessage body"""
    probs = []
    if 'ChaosDisplay::factorOf(player->getLevel())' not in body:
        probs.append('sendTextMessage does not take the receiver\'s factor')
    if body.count('ChaosDisplay::scaleU32(message.primary.value') < 2:
        probs.append('sendTextMessage does not scale the damage and the heal value')
    if 'ChaosDisplay::scaleU32(message.secondary.value' not in body:
        probs.append('sendTextMessage does not scale the secondary damage value')
    if 'ChaosDisplay::scaleText(message.text' not in body:
        probs.append('sendTextMessage does not scale the text')
    head = body.split('NetworkMessage msg;')[0]
    if 'MESSAGE_EXPERIENCE' in head:
        probs.append('sendTextMessage scales experience messages')
    for t in ('MESSAGE_DAMAGE_DEALT', 'MESSAGE_DAMAGE_RECEIVED', 'MESSAGE_DAMAGE_OTHERS', 'MESSAGE_HEALED',
              'MESSAGE_HEALED_OTHERS'):
        if t not in head:
            probs.append('sendTextMessage leaves %s unscaled' % t)
    return probs


def check_mana_patch(names, text=None):
    """problems of 0052: mana and max mana unscaled in the stats packet, a mana message at factor 1"""
    if text is None:
        if MANA not in names:
            return ['missing']
        text = read(os.path.join(PATCHES, MANA))
    probs = ['hunk line counts do not match: %s' % b for b in hunks_ok(text)]
    if 'Applies after 0001-0051.' not in text:
        probs.append('does not say it applies after 0001-0051')
    stats = function_body(text, 'src/protocolgame.cpp', 'void ProtocolGame::AddPlayerStats(')
    added = [l[1:] for l in text.splitlines() if l.startswith('+') and not l.startswith('+++')]
    removed = '\n'.join(l[1:] for l in text.splitlines() if l.startswith('-') and not l.startswith('---'))
    for what in ('getMana()', 'getMaxMana()'):
        if 'ChaosDisplay::scaleU32(player->%s, displayFactor)' % what not in removed:
            probs.append('AddPlayerStats: the scaled %s of 0037 is not replaced' % what)
        if 'ChaosDisplay::scaleU32(player->%s, 1)' % what not in stats:
            probs.append('AddPlayerStats does not send %s as it is' % what)
    if any('getHealth()' in l or 'getMaxHealth()' in l for l in added) or 'getHealth()' in removed:
        probs.append('touches the health of the stats packet (it stays scaled)')
    send = function_body(text, 'src/protocolgame.cpp', 'void ProtocolGame::sendTextMessage(')
    if not re.search(r'message\.typeId == CHAOS_IMPACT_MANA_DRAIN \|\| message\.typeId == CHAOS_IMPACT_MANA_GAIN\)'
                     r'\s*\{\s*displayFactor = 1;', send):
        probs.append('sendTextMessage does not keep a mana message at factor 1')
    impact = read(os.path.join(PATCHES, IMPACT)) if IMPACT in names else ''
    for t in ('CHAOS_IMPACT_MANA_DRAIN = 3', 'CHAOS_IMPACT_MANA_GAIN = 4'):
        if t not in impact:
            probs.append('%s does not define %s' % (IMPACT, t))
    return probs


def main():
    bad = 0

    def fail(msg):
        nonlocal bad
        print(msg)
        bad += 1

    names = sorted(n for n in os.listdir(PATCHES) if n.endswith('.patch'))
    if NAME not in names:
        fail('%s is missing' % NAME)
        return 1
    numbers = [int(n[:4]) for n in names]
    if numbers != list(range(1, len(numbers) + 1)):
        fail('the chain is not numbered 0001.. without gaps: %s' % numbers)
    text = read(os.path.join(PATCHES, NAME))
    if 'Applies after 0001-0036.' not in text:
        fail('%s does not say it applies after 0001-0036' % NAME)
    for b in hunks_ok(text):
        fail('%s: hunk line counts do not match: %s' % (NAME, b))
    files = files_of(text)
    for f in ('src/chaosdisplay.h', 'src/protocolgame.cpp', 'src/player.cpp', 'src/luascript.cpp', 'src/luascript.h'):
        if f not in files:
            fail('%s does not change %s' % (NAME, f))
    if '--- /dev/null\n+++ b/src/chaosdisplay.h' not in text:
        fail('%s does not add src/chaosdisplay.h as a new file' % NAME)

    # the last patch of the chain that writes each function wins
    last = {}
    for n in names:
        ptext = read(os.path.join(PATCHES, n))
        for sig in ('void ProtocolGame::sendTextMessage(', 'void ProtocolGame::AddPlayerStats('):
            body = function_body(ptext, 'src/protocolgame.cpp', sig)
            if body:
                last[sig] = (n, body)
        es = function_body(ptext, 'src/player.cpp', 'void Player::sendEnergyShield(')
        if es:
            last['es'] = (n, es)
    # 0037 scales; 0052 (the last writer of both) takes mana out again
    for sig in ('void ProtocolGame::sendTextMessage(', 'void ProtocolGame::AddPlayerStats('):
        n, _ = last.get(sig, (None, ''))
        if n != MANA:
            fail('the last patch writing %s is %s, not %s' % (sig, n, MANA))
    for p in check_text_message(function_body(text, 'src/protocolgame.cpp', 'void ProtocolGame::sendTextMessage(')):
        fail('%s: %s' % (NAME, p))
    body = function_body(text, 'src/protocolgame.cpp', 'void ProtocolGame::AddPlayerStats(')
    for what in ('getHealth()', 'getMaxHealth()'):
        if 'ChaosDisplay::scaleU32(player->%s, displayFactor)' % what not in body:
            fail('%s: AddPlayerStats does not scale %s' % (NAME, what))
    for p in check_mana_patch(names):
        fail('%s: %s' % (MANA, p))
    n, body = last.get('es', (None, ''))
    if n != NAME:
        fail('the last patch writing Player::sendEnergyShield is %s, not %s' % (n, NAME))
    if 'ChaosDisplay::factorOf(getLevel())' not in body or body.count('ChaosDisplay::scale(') < 2:
        fail('%s: Player::sendEnergyShield does not scale "es:"' % n)
    lua = '\n'.join(files.get('src/luascript.cpp', []))
    for reg in ('registerMethod("Game", "setDisplayScale"', 'registerMethod("Player", "getDisplayScale"'):
        if reg not in lua:
            fail('%s: %s is not registered' % (NAME, reg))

    # self-test: a sendTextMessage that does not scale is caught
    if not check_text_message('void ProtocolGame::sendTextMessage(const TextMessage& message)\n{\n'
                              '\tNetworkMessage msg;\n\tmsg.add<uint32_t>(message.primary.value);\n}'):
        fail('self-test: an unscaled sendTextMessage passed')
    if not hunks_ok('@@ -1,2 +1,2 @@\n context\n-old\n'):
        fail('self-test: a short hunk passed')
    fake = ('Applies after 0001-0051.\n--- a/src/protocolgame.cpp\n+++ b/src/protocolgame.cpp\n'
            '@@ -1,2 +1,2 @@ void ProtocolGame::AddPlayerStats(Networ\n'
            '-\tmsg.add<uint32_t>(ChaosDisplay::scaleU32(player->getMana(), displayFactor));\n'
            '+\tmsg.add<uint32_t>(ChaosDisplay::scaleU32(player->getMana(), displayFactor * 2));\n x\n')
    if not check_mana_patch(names, fake):
        fail('self-test: a 0052 that still scales mana passed')

    # the Lua side
    glue = read(os.path.join(CHAOS, 'display_scale.lua'))
    if 'Game.setDisplayScale, DS.table()' not in glue:
        fail('display_scale.lua does not hand the engine the core\'s table')
    const = read(os.path.join(CHAOS, 'chaos_constants.lua'))
    m = re.search(r'ChaosOpcodes\.displayScale = (\d+)', const)
    cfg = re.search(r'opcode = (\d+)', read(os.path.join(CHAOS, 'display_scale_config.lua')))
    if not m or not cfg or m.group(1) != cfg.group(1):
        fail('ChaosOpcodes.displayScale and display_scale_config.lua opcode differ')
    else:
        op = m.group(1)
        users = []
        for f in os.listdir(CHAOS):
            if not f.endswith('.lua') or f.startswith('display_scale'):
                continue
            s = read(os.path.join(CHAOS, f))
            if re.search(r'(?:opcode|OPCODE)\w*\s*=\s*%s\b' % op, s) or re.search(r'=\s*%s,\s*--.*opcode' % op, s, re.I):
                users.append(f)
            if f == 'chaos_constants.lua':
                others = [k for k, v in re.findall(r'(\w+)\s*=\s*(\d+)', s.split('Chaos.itemAttr')[0])
                          if v == op and k != 'displayScale']
                users += ['chaos_constants.lua:%s' % k for k in others]
        if users:
            fail('opcode %s is used elsewhere too: %s' % (op, users))
        client = read(os.path.join(CLIENT, 'chaosscale.lua')) if os.path.isdir(CLIENT) else ''
        if not re.search(r'OPCODE\s*=\s*%s\b' % op, client):
            fail('client game_chaosscale does not listen on opcode %s' % op)

    if bad:
        print('display_scale_patch_test: %d problem(s)' % bad)
        return 1
    print('display_scale_patch_test: ok (%s)' % NAME)
    return 0


if __name__ == '__main__':
    sys.exit(main())
