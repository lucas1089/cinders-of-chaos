#!/usr/bin/env python3
"""The coverage layer of the tester bots (server/README.md "Tester bots", Coverage). testers.py run --scenarios FILE.

FILE is the generated table server/tools/tester_scenarios.json (gen_tester_scenarios.py). A bot whose behaviour is
'opcodes' asks next_request(bot) for a scenario: a short list of steps it runs with a pause between them.
  * opcode: a client module's requests on its extended opcode, in the client's order ("open" first when the module has
    it), {"action": a, "data": {...}}. The data keys the server reads are filled from the answers this bot got on that
    opcode before (a value seen under the same key), never invented. A key that names a character (name, target, cid,
    ...) only ever gets a tester (this bot or another one), never a name or id from an answer.
  * place: `!tester enter <place>` (the TEST ONLY helper teleports this tester), the opcode of the system there, back to
    the hunt
  * npc: `!tester enter npc <name>`, hi, a keyword or two of its greeting, bye, back
  * rift: `!tester enter rift N` (a key of tier N into the backpack), then the key is used by hotkey
Never sent: out-of-scope and staff systems, opcodes only they answer, the skipped actions of the table.
Coverage per system goes to the run's results ('coverage': {key: {tried, ok, refused, actions}}); merge() adds what
the bots never reached (and why) and the server log errors that name a system's files, for the report.
Standard library only.
"""
import json
import random
import re

NAME_KEYS = {'name', 'player', 'target', 'receiver', 'to', 'member', 'cid', 'who', 'friend', 'invitee'}
# never sent at all, whatever an answer held: gifts, money of real payments, creator codes
# (a guid or owner from an answer is another character: a like or a visit would reach a real player)
NEVER_KEYS = {'gift', 'cents', 'method', 'creator', 'code', 'price', 'confirm', 'owner', 'guid', 'pid', 'player_id'}
PAUSE = 1.5  # seconds between the steps of a scenario
WEIGHTS = {'opcode': 7, 'place': 2, 'npc': 2, 'rift': 1}
FILE_RE = re.compile(r'data/scripts/chaos/([\w/]+\.lua)')


def load(path):
    with open(path, encoding='utf-8') as f:
        return json.load(f)


def values_of(obj, key, out=None, depth=0):
    """every scalar value under `key` anywhere in an answer (lists and dicts walked, 6 levels)"""
    out = [] if out is None else out
    if depth > 6:
        return out
    if isinstance(obj, dict):
        for k, v in obj.items():
            if k == key and isinstance(v, (str, int, float)):
                out.append(v)
            elif isinstance(v, (dict, list)):
                values_of(v, key, out, depth + 1)
    elif isinstance(obj, list):
        for v in obj[:200]:
            values_of(v, key, out, depth + 1)
    return out


def is_refusal(msg):
    """an answer that refuses the request (an error text, action "error", ok false)"""
    if not isinstance(msg, dict):
        return False
    data = msg.get('data') if isinstance(msg.get('data'), dict) else {}
    return bool(msg.get('error') or msg.get('err') or msg.get('action') == 'error' or msg.get('ok') is False
                or data.get('error') or data.get('err') or data.get('ok') is False)


class Scenarios:
    def __init__(self, table, ops=None, rand=None):
        self.t = table
        self.pause = PAUSE
        self.rand = rand or random.Random()
        ops = ops or {}
        self.opcodes = {}  # number -> (name, entry) of what the bots may send
        for name, e in sorted(table.get('opcodes', {}).items()):
            if e.get('out') or not e.get('actions'):
                continue
            num = ops.get(name, e['opcode'])  # the installed constants win over the table's
            self.opcodes[num] = (name, e)
        self.places = []  # (system, place argument, opcode name or None)
        for name, s in sorted(table.get('systems', {}).items()):
            if s.get('place') and s.get('kind') not in ('out', 'staff'):
                op = next((o for o in s.get('opcodes', []) if o in table.get('opcodes', {})
                           and not table['opcodes'][o].get('out')), None)
                self.places.append((name, s['place'], op))
        self.npcs = [n for n in table.get('npcs', []) if n.get('npc')]
        self.by_name = {name: num for num, (name, _) in self.opcodes.items()}
        self.answers = {}  # bot name -> {opcode number: [recent answers]}
        self.pending = {}  # (bot name, opcode number) -> (coverage key, action)

    # ------------------------------------------------------------------ coverage
    @staticmethod
    def cov(bot, key):
        c = bot.results.d.setdefault('coverage', {})
        return c.setdefault(key, {'tried': 0, 'ok': 0, 'refused': 0, 'actions': {}})

    def system_of(self, opname):
        e = self.t.get('opcodes', {}).get(opname, {})
        return (e.get('systems') or [opname])[0]

    # ------------------------------------------------------------------ payloads
    def tester_value(self, bot, key, others):
        if key == 'cid':
            ids = [cid for cid, b in others.items() if b is not bot] or [getattr(bot, 'cid', 0)]
            return self.rand.choice(ids) if ids else None
        names = [b.name for b in others.values() if b is not bot] or [bot.name]
        return self.rand.choice(names)

    def payload(self, bot, num, action, others):
        name, e = self.opcodes[num]
        seen = self.answers.get(bot.name, {}).get(num, [])
        data = {}
        for key, values in sorted((e.get('sub') or {}).items()):  # a sub-action (the stash's make): one of them
            if values:
                data[key] = self.rand.choice(values)
        for key in e.get('dataKeys', []):
            if key in data:
                continue
            if key in NEVER_KEYS:
                continue
            if key in NAME_KEYS:
                v = self.tester_value(bot, key, others)
                if v is not None:
                    data[key] = v
                continue
            found = []
            for msg in seen:
                values_of(msg, key, found)
            if found:
                data[key] = self.rand.choice(found)
        return json.dumps({'action': action, 'data': data}, separators=(',', ':'))

    # ------------------------------------------------------------------ scenarios
    def opcode_steps(self, num):
        name, e = self.opcodes[num]
        acts = e['actions']
        rest = [a for a in acts if a != 'open']
        pick = sorted(self.rand.sample(range(len(rest)), min(len(rest), self.rand.randint(1, 3)))) if rest else []
        chosen = (['open'] if 'open' in acts else []) + [rest[i] for i in pick]
        return [('op', num, a) for a in chosen]

    def build(self, bot):
        kinds = [k for k in WEIGHTS if (k != 'opcode' or self.opcodes) and (k != 'place' or self.places)
                 and (k != 'npc' or self.npcs)]
        if not kinds:
            return []
        kind = self.rand.choices(kinds, [WEIGHTS[k] for k in kinds])[0]
        if kind == 'opcode':
            return self.opcode_steps(self.rand.choice(sorted(self.opcodes)))
        if kind == 'place':
            system, place, op = self.rand.choice(self.places)
            steps = [('say', '!tester enter ' + place), ('check', 'place:' + system)]
            if op and op in self.by_name:
                steps += self.opcode_steps(self.by_name[op])
            return steps + [('say', '!tester hunt')]
        if kind == 'npc':
            npc = self.rand.choice(self.npcs)
            words = list(npc.get('keywords') or [])
            say = self.rand.sample(words, min(2, len(words)))
            return ([('say', '!tester enter npc ' + npc['npc']), ('check', 'npc:' + npc['npc']), ('say', 'hi')]
                    + [('say', w) for w in say] + [('say', 'bye'), ('say', '!tester hunt')])
        tier = self.rand.randint(1, 5)
        return [('say', '!tester enter rift %d' % tier), ('check', 'place:rift'), ('usekey',)]

    def next_request(self, bot):
        """a scenario for the bot: [step]; testers.py TesterBot.do_opcodes runs it with run_step()"""
        return self.build(bot)

    # ------------------------------------------------------------------ running a step (TesterBot.do_opcodes)
    def run_step(self, bot, step, others, send_ext, say, use_hotkey):
        kind = step[0]
        if kind == 'op':
            _, num, action = step
            name = self.opcodes[num][0]
            key = self.system_of(name)
            c = self.cov(bot, key)
            c['tried'] += 1
            c['actions'][action] = c['actions'].get(action, 0) + 1
            self.pending[(bot.name, num)] = (key, action)
            send_ext(num, self.payload(bot, num, action, others))
        elif kind == 'say':
            say(step[1])
        elif kind == 'check':
            # the helper's answer to the enter said a step ago
            c = self.cov(bot, step[1])
            c['tried'] += 1
            ans = bot.helper.get('enter') or {}
            if ans.get('err'):
                c['refused'] += 1
                c['actions'][str(ans['err'])[:40]] = c['actions'].get(str(ans['err'])[:40], 0) + 1
            elif ans:
                c['ok'] += 1
            bot.helper['entered'] = bot.helper.pop('enter', None) or {}
        elif kind == 'usekey':
            cid = (bot.helper.get('entered') or {}).get('keyClientId')
            if cid:
                use_hotkey(int(cid))

    def on_answer(self, bot, op, msg):
        lst = self.answers.setdefault(bot.name, {}).setdefault(op, [])
        lst.append(msg)
        del lst[:-4]
        p = self.pending.pop((bot.name, op), None)
        if p:
            c = self.cov(bot, p[0])
            c['refused' if is_refusal(msg) else 'ok'] += 1


def attach(a, path):
    """testers.py run --scenarios: a.next_request / a.on_answer / a.scenarios_runner"""
    s = Scenarios(load(path), getattr(a, 'ops', None))
    a.scenarios_runner = s
    a.next_request = s.next_request
    a.on_answer = s.on_answer
    return s


def merge(table, run_cov, log):
    """the per-system coverage of the report: every system of the table -> {tried, ok, refused, errors, why}.
    run_cov: the bots' coverage (results 'coverage'); log: tester_core.parse_log of the run's server log."""
    owner = {}
    for name, s in table.get('systems', {}).items():
        for f in s.get('files', []):
            owner.setdefault(f, name)
        owner.setdefault(name + '_core.lua', name)
    errors = {}
    for text, n in (log.get('errors') or {}).items():
        for f in FILE_RE.findall(text):
            sysname = owner.get(f) or owner.get(f.rsplit('/', 1)[-1])
            if sysname:
                errors[sysname] = errors.get(sysname, 0) + n
                break
    out = {}
    for name, s in sorted(table.get('systems', {}).items()):
        c = dict(run_cov.get(name) or {})
        place = run_cov.get('place:' + name) or {}
        row = {'tried': c.get('tried', 0) + place.get('tried', 0), 'ok': c.get('ok', 0) + place.get('ok', 0),
               'refused': c.get('refused', 0) + place.get('refused', 0), 'errors': errors.get(name, 0),
               'kind': s.get('kind')}
        kind = s.get('kind')
        if kind in ('out', 'staff'):
            row['why'] = 'out of scope: ' + s.get('why', '')
        elif kind == 'passive':
            row['why'] = 'passive (reached by play; only log errors name it)'
        elif not row['tried']:
            row['why'] = 'not picked in this run (more bots or minutes)'
        out[name] = row
    for key, c in run_cov.items():
        # NPC dialogs, the rift key, opcodes no system owns
        if key not in out and not (key.startswith('place:') and key[6:] in out):
            out[key] = dict(c, errors=0)
    return out
