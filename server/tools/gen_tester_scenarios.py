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
  * closed: arena, battleground, the Marches, guild, guild war, market, bazaar, the raid (O588): only a --closed run reaches them (O582)
  * out of scope: what bots truly cannot do (staff only, real money, needs real players, a website flow), with the
    reason; the bots never send these
  * passive: everything else is reached by play (combat, loot, login, death): only server log errors name it
NPC dialogs: every NPC of data/npc with the {keywords} of its greeting.
keytest (O249, tester_keytree.py): per class key every keystone and mastery of the passive tree it may hold, the route to
it and how a bot can see that it works (statTotals for masteries, a combat log row for the keystones with extra hits).

usage: python3 -I server/tools/gen_tester_scenarios.py [--check | --skips]   (--skips lists every action the bots never send, with its reason)
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
    'guildboss': 'guild content of real players',
    'community': 'posts real players read',
    'orbexchange': 'an order book matched against real players\' orders',
    'party_finder': 'listings and applications real players see and answer',
    'legal_notice': 'a text the client shows; nothing to do',
    'beta': 'beta sign-up of real accounts',
    'siege': 'needs guilds of real players',
    'groupqueue': 'a queue that matches players: the server refuses testers (O582)',
    'party_finder': 'a list and a queue that match players: the server refuses testers (O582)',
    'testers': 'the tester rules themselves (tests/testers_test.lua)',
    'i18n': 'translations; every bot text passes through it',
    'item_codec': 'the item encoding library; used by every item system',
    'item_fusion': 'the rule of the base item fusion (opcode 67, not a Chaos opcode); no client window sends it (O544)',
    'areagen': 'a map building tool, not run in game',
}

# systems only the closed test mode reaches (O582, tester_closed.py, testers.py run --closed, chaos-ctl.sh testers closed on): the
# bots play them among themselves, the server refuses every pairing with a player; tried only in a --closed run
CLOSED_MODE = {
    'arena': 'ranked PvP, testers only matched with testers (closed test mode)',
    'battleground': 'queue of the testers\' own realm (closed test mode)',
    'pvpzone': 'the Marches, the testers\' own instance (closed test mode)',
    'guild': 'a tester guild made by the run (closed test mode)',
    'guildwar': 'a war between the two tester guilds (closed test mode)',
    'market': 'the testers\' own book, gold only (closed test mode)',
    'market_orders': 'the testers\' own book, gold only (closed test mode)',
    'market_history': 'the testers\' own book, gold only (closed test mode)',
    'market_notify': 'the testers\' own book, gold only (closed test mode)',
    'bazaar': 'the character lock of a listing of a tester; the site never shows or sells it (closed test mode)',
    'raid': 'the Ashen Sepulchre among testers only, in the slot of their own (closed test mode, O588)',
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

# expected effects of a request (O584 item 4): what an answer must show before it counts as REAL proof, not just ANS. Each
# effect is a short scenario on one opcode: {name, system, opcode, about, steps}. A step sends {action, data}, waits for the
# answer whose action is `reply` and checks it. `data` may hold {"$answer": path, "plus": n, "table": [...]}: a value taken from
# the last answer the bot got (table is 1-based, as in Lua). Conditions are lists on a path into the answer (the message
# {"action", "data"}; a Lua array is a JSON list, so its first element has index 0):
#   need    [cond ...]  checked on the step's own answer; false: the effect is skipped (nothing to show), not failed
#   expect  [cond ...]  checked on the step's answer against the last answer of the same kind; false: a FAIL, never ok
#   ["delta", path, n]   now - before == n          ["eq", path, v]   now == v          ["at_least", path, n]  now >= n
#   ["zero", path]       every number under path is 0 (a number, or a table of numbers)    ["has", path]  a value is there
# `replies` (default 1): how many answers of that kind may come before one has to show the effect (a watcher's own state push
# can come between the request and its answer). The generator fails when an opcode, an action or an answer name is not in the
# server files, so a renamed answer is a failed build of the table, not a silent ANS.
EFFECTS = [
    {'name': 'bank_gold_moves', 'system': 'bank', 'opcode': 'bank',
     'about': 'withdrawing gold takes it from the bank balance into the backpack, depositing moves it back',
     'steps': [
         {'action': 'openBank', 'reply': 'open', 'need': [['at_least', ['data', 1], 500]]},
         {'action': 'withdraw', 'data': ['gold', 500], 'reply': 'open',
          'expect': [['delta', ['data', 1], -500], ['delta', ['data', 0], 500]]},
         {'action': 'deposit', 'data': ['gold', 500], 'reply': 'open',
          'expect': [['delta', ['data', 1], 500], ['delta', ['data', 0], -500]]},
     ]},
    {'name': 'daily_claim_sets_day', 'system': 'daily', 'opcode': 'daily',
     'about': 'the claim of a day not yet taken marks the day as taken',
     'steps': [
         {'action': 'open', 'reply': 'OpenDailyWindow', 'need': [['eq', ['data', 'TakenReward'], 0]]},
         {'action': 'calim', 'reply': 'OpenDailyWindow',
          'data': {'$answer': ['data', 'Day'], 'plus': 2, 'table': [6, 7, 1, 2, 3, 4, 5]},
          'expect': [['eq', ['data', 'TakenReward'], 1]]},
     ]},
    {'name': 'hunt_session_reset', 'system': 'hunt', 'opcode': 'hunt',
     'about': 'the reset of the hunt meter zeroes experience, kills, damage, healing, loot and supplies',
     'steps': [
         {'action': 'open', 'reply': 'state', 'need': [['at_least', ['data', 'dmg'], 1]]},
         {'action': 'reset', 'reply': 'state', 'replies': 2,
          'expect': [['zero', ['data', key]] for key in ('xp', 'kc', 'dmg', 'heal', 'lv', 'sv')]},
     ]},
    {'name': 'lootfilter_counts_reset', 'system': 'lootfilter', 'opcode': 'lootfilter',
     'about': 'the reset of the filter counters (all) answers with every counter at 0',
     'steps': [
         {'action': 'reset', 'data': {'scope': 'all'}, 'reply': 'counts',
          'expect': [['zero', ['data', 'session']], ['zero', ['data', 'total']]]},
     ]},
    {'name': 'loadout_save_delete', 'system': 'loadouts', 'opcode': 'loadouts',
     'about': 'saving the live build fills slot 1, deleting it empties the slot again',
     'steps': [
         {'action': 'open', 'reply': 'state',
          'need': [['eq', ['data', 'slots', 0, 'empty'], True], ['eq', ['data', 'slots', 0, 'locked'], False]]},
         {'action': 'save', 'data': {'slot': 1, 'name': 'Bot build'}, 'reply': 'state',
          'expect': [['eq', ['data', 'slots', 0, 'name'], 'Bot build']]},
         {'action': 'delete', 'data': {'slot': 1}, 'reply': 'state',
          'expect': [['eq', ['data', 'slots', 0, 'empty'], True]]},
     ]},
    {'name': 'tooltip_of_backpack', 'system': 'item_tooltip', 'opcode': 'itemTooltip',
     'about': 'the tooltip of the item in the backpack slot names the item',
     'steps': [
         {'action': 'get', 'data': {'items': [{'pos': {'x': 65535, 'y': 3, 'z': 0}}]}, 'reply': 'tips',
          'expect': [['has', ['data', 'items', 0, 'tip', 'name']]]},
     ]},
]

# systems the helper can bring a tester to: system -> the argument of "!tester enter"
PLACES = {
    'rift': 'rift', 'pocketboss': 'boss', 'bossspawns': 'boss', 'boss_mechanics': 'boss', 'bosspoints': 'boss',
    'arena': 'npc Arena Master', 'trials': 'npc Keeper of Trials', 'infinitytower': 'temple',
    'descent': 'temple', 'cityportals': 'travel', 'hunt_teleports': 'travel', 'townportal': 'temple',
    'idlehall': 'temple', 'hideout': 'temple', 'raid': 'hunt', 'invasion': 'hunt', 'ascension_quest': 'npc Ascendant Oracle',
    'spellquest': 'npc Archivist Odrenna',
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
# ADMIN words that are a player's own action on one opcode (O584): {opcode name: {action: why}}. A word in ADMIN is skipped
# on every opcode but these; the generator fails when an entry names an action no server file answers on that opcode
ADMIN_ALLOW = {
    'descent': {'start': "the player's own run of the Ember Descent (X.start of the player, a rate limit of 2 s)"},
    'raid': {'start': "the player's own raid of the Ashen Sepulchre (X.open of the player); sent only by the closed check closed_raid (O588), which walks, fights and leaves"},
    'combatLog': {'reset': "the player's own DPS meter counters"},
    'hunt': {'reset': "the player's own hunt session meter"},
    'lootfilter': {'reset': "the player's own filter counters (scope session, total or all)"},
    'trainerMeter': {'reset': "the player's own dummy meter"},
}
# actions a bot sends only from a closed check that walks, fights and leaves (O589), never from the random request behaviour: {opcode
# name: {action: why}}. They stay actions of the opcode (the closed check sends them), skipped here with the reason
CLOSED_ONLY = {
    'dungeons': {'queue': 'only the closed check closed_dungeon queues (it walks to the entrance, plays the run and leaves; a random queue '
                          'would teleport a bot into a run it does not play)'},
}


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
        elif name in CLOSED_MODE:
            entry['kind'], entry['why'] = 'closed', CLOSED_MODE[name]
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
    unused = sorted((set(OUT_OF_SCOPE) | set(CLOSED_MODE)) - set(systems))
    if unused:
        raise SystemExit('OUT_OF_SCOPE or CLOSED_MODE names no system: %s' % ', '.join(unused))
    for o, acts in ADMIN_ALLOW.items():
        missing = sorted(a for a in acts if a not in table.get(o, {}).get('actions', []))
        if o not in table or missing:
            raise SystemExit('ADMIN_ALLOW names an opcode or action no server file answers: %s %s' % (o, missing))
        bad = sorted(a for a in acts if a not in ADMIN)
        if bad:
            raise SystemExit('ADMIN_ALLOW names an action that is not in ADMIN: %s %s' % (o, bad))
    for o, acts in CLOSED_ONLY.items():
        missing = sorted(a for a in acts if a not in table.get(o, {}).get('actions', []))
        if o not in table or missing:
            raise SystemExit('CLOSED_ONLY names an opcode or action no server file answers: %s %s' % (o, missing))
    for e in EFFECTS:
        o = e['opcode']
        t = table.get(o)
        if not t or e['system'] not in systems:
            raise SystemExit('EFFECTS names an opcode or system the server does not have: %s' % e['name'])
        text = '\n'.join(clean[f] for f in t['files'])
        for st in e['steps']:
            if st['action'] not in t['actions']:
                raise SystemExit('EFFECTS %s: the action %s is not one the bots may send on %s' % (e['name'], st['action'], o))
            if '"%s"' % st['reply'] not in text:
                raise SystemExit('EFFECTS %s: no server file of %s names the answer "%s"' % (e['name'], o, st['reply']))
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
        t['out'] = bool(op_systems) and all(systems[n]['kind'] in ('out', 'closed') for n in op_systems)
        # actions only an out-of-scope system's files answer, and money / staff actions: never sent, each with its reason
        allowed, out_why = set(), {}
        for f in t['files']:
            own = owners(f, names, texts[f])
            if not own or any(systems.get(n, {}).get('kind') not in ('out', 'closed') for n in own):
                allowed |= set(per_file[(o, f)])
            else:
                for a in per_file[(o, f)]:
                    out_why.setdefault(a, 'out of scope (%s): %s' % (own[0], systems[own[0]]['why']))
        keep = ADMIN_ALLOW.get(o, {})
        t['skip'], t['skipWhy'] = [], {}
        for a in t['actions']:
            if a not in allowed:
                why = out_why.get(a, 'only an out-of-scope system answers it')
            elif a in ADMIN and a not in keep:
                why = 'staff or world action (ADMIN): it would change the world for real players or hand out value'
            elif DENY_RE.search(a):
                why = 'money, report, ticket or code action (DENY_RE)'
            elif a in CLOSED_ONLY.get(o, {}):
                why = CLOSED_ONLY[o][a]
            else:
                continue
            t['skip'].append(a)
            t['skipWhy'][a] = why
        t['actions'] = [a for a in t['actions'] if a not in t['skip']]
        if keep:
            t['adminAllowed'] = sorted(keep)
    for e in EFFECTS:
        for st in e['steps']:
            if st['action'] in table[e['opcode']]['skip']:
                raise SystemExit('EFFECTS %s: the action %s is skipped on %s' % (e['name'], st['action'], e['opcode']))
    used = {t['opcode'] for t in table.values()}
    client_only = sorted({m for n, mods in clients.items() if n not in used for m, _ in mods})
    return {'generated_by': 'server/tools/gen_tester_scenarios.py', 'counts': dict(sorted(counts.items())),
            'systems': dict(sorted(systems.items())), 'opcodes': dict(sorted(table.items())),
            'clientOnly': client_only, 'npcs': npc_dialogs(), 'keytest': KT.build(CHAOS),
            'effects': sorted(EFFECTS, key=lambda e: e['name'])}


def render(table):
    return json.dumps(table, indent=1, sort_keys=True, ensure_ascii=False) + '\n'


def skipped(table):
    """[(opcode name, action, reason)] of every action the bots never send, sorted"""
    return sorted((o, a, t.get('skipWhy', {}).get(a, '')) for o, t in table['opcodes'].items() for a in t['skip'])


def main(argv):
    if '--skips' in argv:
        for o, a, why in skipped(build()):
            print('%-16s %-14s %s' % (o, a, why))
        return 0
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
