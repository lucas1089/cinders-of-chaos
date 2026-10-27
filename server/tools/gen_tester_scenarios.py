#!/usr/bin/env python3
"""The coverage table of the tester bots: server/tools/tester_scenarios.json (server/README.md "Tester bots", Coverage).

GENERATED from the sources, so CI can diff it (--check): every system with a *_core.lua in data/scripts/chaos, what a
player can do with it, and how the bots reach it.
  * opcode systems: the extended opcode (ChaosOpcodes name and number), the actions its engine files answer
    (`action == "x"`, `a == "x"`, ...), in the client's order where a client module sends them (first appearance in the
    module's Lua), the data keys the server reads (`data.x`, `d.x`), the client modules on that opcode number
  * talkactions: the words of TalkAction("...") in its engine files. Every one is a staff command (Chaos.staffCommand),
    so a system with nothing else is kind 'staff': never reached, testers are never staff
  * places: the systems the TEST ONLY helper can bring a tester to (`!tester enter ...`), with the argument
  * out of scope: what bots truly cannot do (staff only, real money, needs real players, a website flow), with the
    reason; the bots never send these
  * passive: everything else is reached by play (combat, loot, login, death): only server log errors name it
NPC dialogs: every NPC of data/npc with the {keywords} of its greeting.
keytest (O249, tester_keytree.py): per class key every keystone and mastery of the passive tree it may hold, the route to
it and how a bot can see that it works (statTotals for masteries, a combat log row for the keystones with extra hits).

usage: python3 -I server/tools/gen_tester_scenarios.py [--check]
Standard library only; deterministic (sorted, no timestamps).
"""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import tester_keytree as KT  # noqa: E402  (the keystone and mastery table, O249)
SERVER = os.path.dirname(HERE)
REPO = os.path.dirname(SERVER)
CHAOS = os.path.join(SERVER, 'data', 'scripts', 'chaos')
MODULES = os.path.join(REPO, 'client', 'overlay', 'modules')
NPCS = os.path.join(SERVER, 'data', 'npc')
OUT = os.path.join(HERE, 'tester_scenarios.json')

# what bots truly cannot do: never sent, listed in the report with the reason
OUT_OF_SCOPE = {
    'antibot': 'judges bots; testers are exempt by design',
    'botreview': 'staff review of suspected bots; testers are exempt',
    'clientguard': 'the login handshake itself; every bot login runs it',
    'remote_cmd': 'console commands of the owner (chaos-ctl.sh), not a player action',
    'spectate': "the owner's live view in the admin app (chaos-ctl.sh spectate), not a player action",
    'moderation_purge': 'staff moderation only',
    'shadow_mute': 'staff moderation only',
    'telemetry': 'client performance numbers; the bots send no client frames',
    'discord': 'server to Discord only; testers are filtered out of it',
    'reports': 'player reports reach the staff queue; bots must not spam it',
    'shop_payments': 'real money payments',
    'store_delivery': 'deliveries of real money purchases',
    'creator_codes': 'real money creator codes',
    'referral': 'links real accounts',
    'mentor': 'pairs a tester with real players',
    'guild': 'guilds of real players; testers stay apart',
    'guildwar': 'guild wars of real players',
    'guildboss': 'guild content of real players',
    'community': 'posts real players read',
    'market': 'testers are refused on the market by design (tests/testers_test.lua)',
    'market_orders': 'testers are refused on the market by design',
    'market_history': 'testers are refused on the market by design',
    'market_notify': 'testers are refused on the market by design',
    'bazaar': 'trades with real players',
    'orbexchange': 'an order book matched against real players\' orders',
    'party_finder': 'listings and applications real players see and answer',
    'arena': 'ranked PvP: a queue would match testers against real players',
    'legal_notice': 'a text the client shows; nothing to do',
    'patchnotes': 'a text the client shows; nothing to do',
    'beta': 'beta sign-up of real accounts',
    'pvpzone': 'player versus player; testers never fight players',
    'battleground': 'needs teams of real players',
    'conquest': 'needs guilds of real players',
    'siege': 'needs guilds of real players',
    'testers': 'the tester rules themselves (tests/testers_test.lua)',
    'i18n': 'translations; every bot text passes through it',
    'item_codec': 'the item encoding library; used by every item system',
    'areagen': 'a map building tool, not run in game',
}

# requests the server answers with nothing, by design: {opcode name: {action: why}}. The bots count them as sent and fine
# (the report's "no answer, no error" is for a request that should have been answered)
SILENT = {
    'castbar': {'cancel': 'ends the running cast of the player; there is nothing to say when none runs'},
}
# requests the server refuses when a bot sends them, by design: {opcode name: {action: why}}; the refusal is the right answer
EXPECT_REFUSAL = {
    'veiled': {'choose': 'answers a window the Orb of Unveiling opens (the signature of the item); the bots hold no veiled item'},
}
# data a bot cannot learn from an answer: {opcode name: {action: data}}. "$near" = the tiles around the bot (3 x 3)
HINTS = {
    'itemTooltip': {'get': {'items': [{'pos': {'x': 65535, 'y': slot, 'z': 0}} for slot in (6, 7, 4)]}},
    'groundLoot': {'look': {'t': '$near'}},
}
# the data keys of an on / off switch the server reads as `data.x == true` (a map overlay's watch): sent as true, since
# no answer ever carries them {opcode name: [keys]}. Hand-listed: other switches accept, allow or confirm something
FLAGS = {'mapMarkers': ['party', 'poi'], 'mapmarks': ['on']}

# systems the helper can bring a tester to: system -> the argument of "!tester enter"
PLACES = {
    'rift': 'rift', 'pocketboss': 'boss', 'bossspawns': 'boss', 'boss_mechanics': 'boss', 'bosspoints': 'boss',
    'arena': 'npc Arena Master', 'trials': 'npc Keeper of Trials', 'infinitytower': 'temple',
    'descent': 'temple', 'cityportals': 'travel', 'hunt_teleports': 'travel', 'townportal': 'temple',
    'idlehall': 'temple', 'hideout': 'temple', 'raid': 'hunt', 'invasion': 'hunt', 'ascension_quest': 'npc Ascendant Oracle',
    'blessings': 'bless', 'bank': 'bank', 'depot': 'depot', 'craft_bonus': 'craft', 'professions': 'craft',
    'service_npcs': 'shop', 'npc_booths': 'shop', 'npc_place': 'shop',
}

# `x == "a"` and the guard `x ~= "a"` (a handler of one action returns on any other)
ACTION_RE = re.compile(r'\b(?:action|act|a|kind|cmd|what|op)\s*[~=]=\s*"([A-Za-z_][\w]*)"')
DISPATCH_RE = re.compile(r'\b(\w+)\[\s*\w+\.action\s*\]')
DATA_RE = re.compile(r'\b(?:data|d|msg\.data|payload)\.([a-z][A-Za-z0-9_]*)\b')
LOCAL_OP_RE = re.compile(r'\blocal\s+(\w+)\s*=\s*\(?\s*(?:ChaosOpcodes\s+and\s+)?ChaosOpcodes\.(\w+)')
COMPARE_RE = re.compile(r'\b(?:op|opcode|code)\s*[~=]=\s*([\w.]+)')
TALK_RE = re.compile(r'TalkAction\(\s*"([^"]+)"')
# a sub-action in the data (the stash: {action = "Stash", data = {make = "Open"}}): its values, sent as that data key
SUB_RE = re.compile(r'\bdata\.(make)\s*==\s*"([A-Za-z_]\w*)"')
CLIENT_ACTION_RES = [re.compile(r'\baction\s*=\s*["\']([A-Za-z_]\w*)["\']'),
                     re.compile(r'\b(?:send|sendAction|request|sendMessage|sendRequest)\(\s*["\']([A-Za-z_]\w*)["\']'),
                     re.compile(r'\\?"action\\?"\s*:\s*\\?"([A-Za-z_]\w*)')]
CLIENT_OP_RE = re.compile(r'\b[\w.]*(?:OPCODE|Opcode|OpCode|opcode|CODE_\w+)\w*\s*=\s*(\d+)\b')
NPC_KEY_RE = re.compile(r'\{([a-z][a-z \-]{1,30})\}')
SKIP_DATA = {'action', 'data', 'type'}
# libraries many files load: never the owner of a file by that alone
LIBRARIES = {'i18n', 'item_codec'}
# actions the bots never send, whatever the system: money, staff queues, codes of real people
DENY_RE = re.compile(r'pay|checkout|donat|report|ticket|appeal|redeem|coupon|voucher|bug', re.I)
# staff and world actions: whole action names that would change the world for real players
# (start an invasion, reset a board) or hand out value (grant, give); gifts and transfers reach other players
ADMIN = {'start', 'stop', 'end', 'reset', 'rebuild', 'shift', 'schedule', 'wave', 'breach', 'event', 'grant',
         'give', 'xp', 'level', 'expire', 'winner', 'transfer', 'gift', 'gift_coins', 'giftPrice', 'claimreset',
         'rescan', 'testip', 'nopz', 'species', 'complete', 'memset', 'stat', 'pity', 'unlink'}


def read(path):
    with open(path, encoding='utf-8', errors='replace') as f:
        return f.read()


def strip_comments(text):
    text = re.sub(r'--\[(=*)\[.*?\]\1\]', '', text, flags=re.S)
    return re.sub(r'--[^\n]*', '', text)


def opcodes():
    """{name: number} of ChaosOpcodes (chaos_constants.lua)"""
    text = read(os.path.join(CHAOS, 'chaos_constants.lua'))
    m = re.search(r'^ChaosOpcodes = \{(.*?)^\}', text, re.S | re.M)
    out = {k: int(v) for k, v in re.findall(r'^\s*(\w+) = (\d+)', m.group(1) if m else '', re.M)}
    out.update({k: int(v) for k, v in re.findall(r'^ChaosOpcodes\.(\w+) = (\d+)', text, re.M)})
    return out


def lua_files():
    out = []
    for root, _, files in os.walk(CHAOS):
        for f in files:
            if f.endswith('.lua'):
                out.append(os.path.relpath(os.path.join(root, f), CHAOS).replace(os.sep, '/'))
    return sorted(out)


def handled_opcodes(text, ops):
    """the ChaosOpcodes names an engine file answers: what its onExtendedOpcode compares the opcode with"""
    if 'onExtendedOpcode' not in text:
        return []
    alias = dict(LOCAL_OP_RE.findall(text))
    out = []
    for ref in COMPARE_RE.findall(text):
        name = ref[len('ChaosOpcodes.'):] if ref.startswith('ChaosOpcodes.') else alias.get(ref)
        if name in ops and name not in out:
            out.append(name)
    return out


def dispatch_actions(text):
    """the actions of the dispatch tables of an engine file: `actions[msg.action]` / `ACTIONS[m.action]` names a table whose
    keys are the actions (`local actions = {\n\tname = fn,`, `actions.name = fn`, `function actions.name(`). The comparison
    regex above sees none of these (charms.lua, loadouts.lua and pact.lua answer open / place / buildSave ... and it listed
    other words of the file, so the bots sent requests no server answers: O262)"""
    out = []
    for var in sorted(set(DISPATCH_RE.findall(text))):
        keys = []
        for m in re.finditer(r'^([ \t]*)(?:local\s+)?%s\s*=\s*\{' % re.escape(var), text, re.M):
            rest = text[m.end():]
            depth, end = 1, 0
            for i, ch in enumerate(rest):
                depth += (ch == '{') - (ch == '}')
                if depth == 0:
                    end = i
                    break
            for k in re.findall(r'^%s\t(?:(\w+)|\["(\w+)"\])\s*=' % re.escape(m.group(1)), rest[:end], re.M):
                keys.append(k[0] or k[1])
        keys += re.findall(r'\b%s\.(\w+)\s*=[^=]' % re.escape(var), text)
        keys += re.findall(r'\bfunction\s+%s\.(\w+)\s*\(' % re.escape(var), text)
        keys += re.findall(r'\b%s\["(\w+)"\]\s*=[^=]' % re.escape(var), text)
        for k in keys:
            if k not in out:
                out.append(k)
    return out


def file_requests(text):
    """(actions, data keys) an engine file answers"""
    actions, keys = [], []
    for a in dispatch_actions(text) or ACTION_RE.findall(text):
        if a not in actions:
            actions.append(a)
    for k in DATA_RE.findall(text):
        if k not in keys and k not in SKIP_DATA:
            keys.append(k)
    return actions, keys


def owners(f, names, text):
    """the systems an engine file belongs to: the longest system name it is named after (<name>.lua, <name>_x.lua),
    else every system whose core it loads"""
    base = f.rsplit('/', 1)[-1][:-len('.lua')]
    named = [n for n in names if base == n or base.startswith(n + '_')]
    if named:
        return [max(named, key=len)]
    return [n for n in names if n not in LIBRARIES and n + '_core.lua' in text]


def engine_files(system, files, texts, names):
    """the engine files of a system (owners)"""
    out = []
    for f in files:
        base = f.rsplit('/', 1)[-1]
        if base.endswith('_core.lua') or base.endswith('_config.lua') or base.endswith('_test.lua'):
            continue
        if system in owners(f, names, texts[f]):
            out.append(f)
    return out


def client_modules(ops_by_number):
    """{opcode number: [(module, [actions in order])]} of the client modules"""
    out = {}
    if not os.path.isdir(MODULES):
        return out
    for mod in sorted(os.listdir(MODULES)):
        folder = os.path.join(MODULES, mod)
        if not os.path.isdir(folder):
            continue
        numbers, actions = set(), []
        for f in sorted(os.listdir(folder)):
            if not f.endswith('.lua') or f.endswith('_test.lua'):
                continue
            text = strip_comments(read(os.path.join(folder, f)))
            numbers |= {int(n) for n in CLIENT_OP_RE.findall(text) if int(n) in ops_by_number}
            hits = []
            for rx in CLIENT_ACTION_RES:
                hits += [(m.start(), m.group(1)) for m in rx.finditer(text)]
            for _, act in sorted(hits):
                if act not in actions:
                    actions.append(act)
        for n in numbers:
            out.setdefault(n, []).append((mod, actions))
    return out


def npc_dialogs():
    out = []
    if not os.path.isdir(NPCS):
        return out
    for f in sorted(os.listdir(NPCS)):
        if not f.endswith('.xml'):
            continue
        text = read(os.path.join(NPCS, f))
        m = re.search(r'<npc\s+name="([^"]+)"', text)
        if not m:
            continue
        keys = []
        for k in NPC_KEY_RE.findall(text):
            if k not in keys:
                keys.append(k)
        out.append({'npc': m.group(1), 'keywords': keys})
    return out


def build():
    ops = opcodes()
    by_number = {}
    for k, v in sorted(ops.items()):
        by_number.setdefault(v, k)
    files = lua_files()
    texts = {f: read(os.path.join(CHAOS, f)) for f in files}
    clean = {f: strip_comments(t) for f, t in texts.items()}
    clients = client_modules(by_number)
    # every opcode a server file answers: its files, actions in the client's order, data keys, client modules
    names = sorted(f.rsplit('/', 1)[-1][:-len('_core.lua')] for f in files if f.endswith('_core.lua'))
    table, per_file = {}, {}
    for f in files:
        for o in handled_opcodes(clean[f], ops):
            acts, keys = file_requests(clean[f])
            t = table.setdefault(o, {'opcode': ops[o], 'files': [], 'actions': [], 'dataKeys': []})
            t['files'].append(f)
            t['actions'] += [a for a in acts if a not in t['actions']]
            t['dataKeys'] = sorted(set(t['dataKeys']) | set(keys))
            per_file[(o, f)] = acts
    for o, t in table.items():
        mods = clients.get(t['opcode'], [])
        ordered = []
        for _, acts in mods:
            ordered += [a for a in acts if a in t['actions'] and a not in ordered]
        # what the client really sends: a server comparison the client never sends is no request (the item tooltip's
        # `kind == "slot"` is a position kind, not an action); no client actions found: every server one
        t['actions'] = ordered if ordered else t['actions']
        t['client'] = [m for m, _ in mods]
        if o in FLAGS:
            t['flags'] = FLAGS[o]
        for key, table_ in (('silent', SILENT), ('refuses', EXPECT_REFUSAL), ('hints', HINTS)):
            if o in table_:
                t[key] = table_[o]
        sub = {}
        for f in t['files']:
            for k, v in SUB_RE.findall(clean[f]):
                if v not in sub.setdefault(k, []) and v not in ADMIN and not DENY_RE.search(v):
                    sub[k].append(v)
        if sub:
            t['sub'] = sub
    systems = {}
    for f in files:
        base = f.rsplit('/', 1)[-1]
        if not base.endswith('_core.lua'):
            continue
        name = base[:-len('_core.lua')]
        eng = engine_files(name, files, texts, names)
        op_names, talks = [], []
        for e in eng:
            for o in handled_opcodes(clean[e], ops):
                if o not in op_names:
                    op_names.append(o)
            for w in TALK_RE.findall(clean[e]):
                if w not in talks:
                    talks.append(w)
        entry = {'files': eng, 'opcodes': op_names, 'talkactions': sorted(talks)}
        if name in OUT_OF_SCOPE:
            entry['kind'], entry['why'] = 'out', OUT_OF_SCOPE[name]
        elif any(table[o]['actions'] for o in op_names):
            entry['kind'] = 'opcode'
        elif name in PLACES:
            entry['kind'] = 'place'
        elif talks and all(w.startswith('/') for w in talks):
            # every talkaction here is a staff command (Chaos.staffCommand); a player's words are only chat
            entry['kind'], entry['why'] = 'staff', 'staff command only (%s); testers are never staff' % ', '.join(talks)
        else:
            entry['kind'] = 'passive'
            entry['why'] = ('no request of its own: reached by play (combat, loot, login, death); '
                            'only server log errors name it')
        if name in PLACES:
            entry['place'] = PLACES[name]
        systems[name] = entry
    unused = sorted(set(OUT_OF_SCOPE) - set(systems))
    if unused:
        raise SystemExit('OUT_OF_SCOPE names no system: %s' % ', '.join(unused))
    for o, keys in FLAGS.items():
        if o not in table or sorted(set(keys) - set(table[o]['dataKeys'])):
            raise SystemExit('FLAGS names an opcode or data key no server file reads: %s' % o)
    for name, table_ in (('SILENT', SILENT), ('EXPECT_REFUSAL', EXPECT_REFUSAL), ('HINTS', HINTS)):
        for o, acts in table_.items():
            missing = sorted(a for a in acts if a not in table.get(o, {}).get('actions', []))
            if o not in table or missing:
                raise SystemExit('%s names an opcode or action no server file answers: %s %s' % (name, o, missing))
    counts = {}
    for s in systems.values():
        counts[s['kind']] = counts.get(s['kind'], 0) + 1
    # the systems of an opcode; an opcode only out-of-scope systems answer is never sent
    for o, t in table.items():
        op_systems = sorted(n for n, x in systems.items() if o in x['opcodes'])
        t['systems'] = op_systems
        t['out'] = bool(op_systems) and all(systems[n]['kind'] == 'out' for n in op_systems)
        # actions only an out-of-scope system's files answer, and money / staff actions: never sent
        allowed = set()
        for f in t['files']:
            own = owners(f, names, texts[f])
            if not own or any(systems.get(n, {}).get('kind') != 'out' for n in own):
                allowed |= set(per_file[(o, f)])
        t['skip'] = [a for a in t['actions'] if a not in allowed or a in ADMIN or DENY_RE.search(a)]
        t['actions'] = [a for a in t['actions'] if a not in t['skip']]
    used = {t['opcode'] for t in table.values()}
    client_only = sorted({m for n, mods in clients.items() if n not in used for m, _ in mods})
    return {'generated_by': 'server/tools/gen_tester_scenarios.py', 'counts': dict(sorted(counts.items())),
            'systems': dict(sorted(systems.items())), 'opcodes': dict(sorted(table.items())),
            'clientOnly': client_only, 'npcs': npc_dialogs(), 'keytest': KT.build(CHAOS)}


def render(table):
    return json.dumps(table, indent=1, sort_keys=True, ensure_ascii=False) + '\n'


def main(argv):
    text = render(build())
    if '--check' in argv:
        old = read(OUT) if os.path.exists(OUT) else ''
        if old != text:
            print('%s is not up to date: run python3 -I server/tools/gen_tester_scenarios.py' % OUT)
            return 1
        print('tester scenarios: up to date')
        return 0
    with open(OUT, 'w', encoding='utf-8') as f:
        f.write(text)
    t = json.loads(text)
    print('tester scenarios: %d systems %s, %d opcodes, %d NPCs, %d keystone and mastery nodes -> %s' % (
        len(t['systems']), t['counts'], len(t['opcodes']), len(t['npcs']),
        sum(len(v) for v in t['keytest']['classes'].values()), OUT))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
