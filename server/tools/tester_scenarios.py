#!/usr/bin/env python3
"""The coverage layer of the tester bots (server/README.md "Tester bots", Coverage). testers.py run --scenarios FILE.

FILE is the generated table server/tools/tester_scenarios.json (gen_tester_scenarios.py). A bot whose behaviour is
'opcodes' asks next_request(bot) for a scenario: a short list of steps it runs with a pause between them.
  * opcode: a client module's requests on its extended opcode, in the client's order ("open" first when the module has
    it), {"action": a, "data": {...}}. The data keys the server reads are filled from the answers this bot got on that
    opcode before (a value seen under the same key), never invented. A key that names a character (name, target, cid,
    ...) only ever gets a tester (this bot or another one), never a name or id from an answer.
  * place: the bot WALKS to the place (`!tester path <place>`: the engine's own pathfinding, the bot takes the steps; O589), the opcode
    of the system there, back to
    the hunt
  * npc: the bot walks to the NPC (`!tester path npc <name>`), hi, a keyword or two of its greeting, bye, back
    The helper's teleport (`!tester enter ...`) is only the fallback when there is no path or the walk did not arrive; the coverage counts
    it (HELP) and names the reason (`teleport: ...` in the system's actions), a walked arrival is counted as `walk` (O589).
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
NPC_CHANNEL = 12  # TALKTYPE_PRIVATE_PN: words to the NPC in focus
PAUSE = 1.5  # seconds between the steps of a scenario
WEIGHTS = {'opcode': 7, 'place': 2, 'npc': 2, 'rift': 1, 'effect': 3}
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


MISSING = object()
# check key (tester_checks.py) -> the system of the table it proves, or 'check:<key>' when no system carries its name
CHECK_SYSTEMS = {
    'beastmaster_wolf': 'summons', 'necro_minions': 'necro', 'pets': 'pets', 'party': 'party_xp', 'rift': 'rift',
    'rift_layout': 'rift_layout', 'waystone_run': 'waystone_tiers', 'content_rewards': 'content_rewards',
    'party_xp': 'party_xp', 'unique_passive': 'unique_passives', 'dual_fists': 'check:dual_fists',
    'dual_blades': 'check:dual_blades', 'waystone': 'waystone_atlas', 'reward_chest': 'check:reward_chest',
    'cursed_chest': 'cursedchest', 'auto_setup': 'check:auto_setup', 'spell_quest': 'spellquest',
    'craft_charms': 'charms', 'craft_cards': 'cards',
}
EFFECT_LIST_MAX = 200  # failed effects kept in the run's results


def path_get(msg, path):
    """the value at path (keys and list indexes) in an answer, MISSING when it is not there"""
    cur = msg
    for k in path:
        if isinstance(k, int):
            if not isinstance(cur, list) or not -len(cur) <= k < len(cur):
                return MISSING
        elif not isinstance(cur, dict) or k not in cur:
            return MISSING
        cur = cur[k]
    return cur


def numbers_under(v, out=None, depth=0):
    out = [] if out is None else out
    if isinstance(v, bool) or depth > 6:
        return out
    if isinstance(v, (int, float)):
        out.append(v)
    elif isinstance(v, dict):
        for x in v.values():
            numbers_under(x, out, depth + 1)
    elif isinstance(v, list):
        for x in v:
            numbers_under(x, out, depth + 1)
    return out


def cond_holds(cond, now, before=None):
    """one condition of an effect (gen_tester_scenarios.py EFFECTS) -> (True | False, why)"""
    kind, path = cond[0], cond[1]
    v = path_get(now, path)
    where = '.'.join(str(x) for x in path)
    if kind == 'has':
        return v is not MISSING and v not in (None, ''), '%s is missing' % where
    if v is MISSING:
        return False, '%s is missing in the answer' % where
    if kind == 'eq':
        return v == cond[2], '%s is %r, expected %r' % (where, v, cond[2])
    if kind == 'at_least':
        ok = isinstance(v, (int, float)) and not isinstance(v, bool) and v >= cond[2]
        return ok, '%s is %r, expected at least %r' % (where, v, cond[2])
    if kind == 'zero':
        nums = numbers_under(v)
        return all(n == 0 for n in nums), '%s is %r, expected 0' % (where, v)
    if kind == 'delta':
        b = path_get(before, path) if before is not None else MISSING
        if b is MISSING or not isinstance(v, (int, float)) or not isinstance(b, (int, float)):
            return False, '%s: no number to compare (%r before, %r now)' % (where, None if b is MISSING else b, v)
        return v - b == cond[2], '%s moved by %r (%r to %r), expected %r' % (where, v - b, b, v, cond[2])
    return False, 'unknown condition %r' % (kind,)


def resolve_data(data, last):
    """the data of an effect step: {"$answer": path, "plus": n, "table": [...]} taken from the last answers; (data, ok)"""
    if isinstance(data, dict) and '$answer' in data:
        v = MISSING
        for m in last.values():
            got = path_get(m, data['$answer'])
            if got is not MISSING:
                v = got
        if not isinstance(v, int) or isinstance(v, bool):
            return None, False
        i = v + int(data.get('plus', 0))
        table = data.get('table')
        if table:
            if not 1 <= i <= len(table):
                return None, False
            i = table[i - 1]
        return i, True
    if isinstance(data, dict):
        out = {}
        for k, v in data.items():
            r, ok = resolve_data(v, last)
            if not ok:
                return None, False
            out[k] = r
        return out, True
    if isinstance(data, list):
        out = []
        for v in data:
            r, ok = resolve_data(v, last)
            if not ok:
                return None, False
            out.append(r)
        return out, True
    return data, True


def bump(c, key, n=1):
    c[key] = c.get(key, 0) + n


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
            if s.get('place') and s.get('kind') not in ('out', 'staff', 'closed'):
                op = next((o for o in s.get('opcodes', []) if o in table.get('opcodes', {})
                           and not table['opcodes'][o].get('out')), None)
                self.places.append((name, s['place'], op))
        self.npcs = [n for n in table.get('npcs', []) if n.get('npc')]
        self.by_name = {name: num for num, (name, _) in self.opcodes.items()}
        # the effect scenarios (O584) whose opcode the bots may send
        self.effects = {}
        for e in table.get('effects', []):
            if e['opcode'] in self.by_name:
                self.effects[e['name']] = e
        self.fx = {}  # bot name -> the running effect: {effect, op, last, wait, dead}
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

    def near(self, bot):
        """the 3 x 3 tiles around the bot, [[x, y, z], ...]: its hunt spot (the scenarios end there) or its login spot"""
        for kind in ('hunt', 'info'):
            p = (getattr(bot, 'helper', {}).get(kind) or {}).get('pos')
            if isinstance(p, dict) and all(isinstance(p.get(k), int) for k in 'xyz'):
                return [[p['x'] + dx, p['y'] + dy, p['z']] for dx in (-1, 0, 1) for dy in (-1, 0, 1)]
        return None

    def pile(self, bot, num):
        """groundLoot tip / raise: an item of a pile the bot's own 'look' was answered with, as the client asks for it"""
        for msg in reversed(self.answers.get(bot.name, {}).get(num, [])):
            for tile in ((msg.get('data') or {}).get('t') or []) if msg.get('action') == 'tiles' else []:
                for row in (tile.get('i') or []):
                    if isinstance(tile.get('p'), dict) and isinstance(row.get('s'), int) and isinstance(row.get('id'), int):
                        data = {'p': tile['p'], 's': row['s'], 'id': row['id']}
                        for k in ('c', 'iid'):
                            if row.get(k) is not None:
                                data[k] = row[k]
                        return data
        return None

    def payload(self, bot, num, action, others):
        """the JSON of a request, or None when the bot cannot build one (nothing seen to ask about)"""
        name, e = self.opcodes[num]
        seen = self.answers.get(bot.name, {}).get(num, [])
        hint = (e.get('hints') or {}).get(action)
        if hint is not None:  # data no answer carries (gen_tester_scenarios.py HINTS)
            data = json.loads(json.dumps(hint))
            for k, v in list(data.items()):
                if v == '$near':
                    data[k] = self.near(bot)
                    if data[k] is None:
                        return None
            return json.dumps({'action': action, 'data': data}, separators=(',', ':'))
        if name == 'groundLoot' and action in ('tip', 'raise'):
            data = self.pile(bot, num)
            return json.dumps({'action': action, 'data': data}, separators=(',', ':')) if data else None
        data = {}
        for key in e.get('flags', []):  # an on / off switch (gen_tester_scenarios.py FLAGS)
            data[key] = True
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
        if 'start' in chosen and 'leave' in acts:
            # a run the bot began (Descent, raid: gen_tester_scenarios.py ADMIN_ALLOW) is left again at once; a player
            # who started alone does not stand in the lobby until the run times out (O584)
            chosen = [a for a in chosen if a != 'leave'] + ['leave']
        return [('op', num, a) for a in chosen]

    def build(self, bot):
        kinds = [k for k in WEIGHTS if (k != 'opcode' or self.opcodes) and (k != 'place' or self.places)
                 and (k != 'npc' or self.npcs) and (k != 'effect' or self.effects)]
        if not kinds:
            return []
        kind = self.rand.choices(kinds, [WEIGHTS[k] for k in kinds])[0]
        if kind == 'opcode':
            return self.opcode_steps(self.rand.choice(sorted(self.opcodes)))
        if kind == 'effect':
            e = self.effects[self.rand.choice(sorted(self.effects))]
            return [('fx', e['name'], i) for i in range(len(e['steps']))]
        if kind == 'place':
            system, place, op = self.rand.choice(self.places)
            # a rift key is no place to walk to: `enter rift` stays the helper's (step 5 of O589 walks the rift itself)
            steps = [('say', '!tester enter ' + place) if place.split(' ')[0] == 'rift' else ('walk', place), ('check', 'place:' + system)]
            if op and op in self.by_name:
                steps += self.opcode_steps(self.by_name[op])
            return steps + [('say', '!tester hunt')]
        if kind == 'npc':
            npc = self.rand.choice(self.npcs)
            words = list(npc.get('keywords') or [])
            say = self.rand.sample(words, min(2, len(words)))
            # after "hi" the NPC has the player in focus and hears keywords only in the NPC channel ('npc' steps)
            return ([('walk', 'npc ' + npc['npc']), ('check', 'npc:' + npc['npc']), ('say', 'hi')]
                    + [('npc', w) for w in say] + [('npc', 'bye'), ('say', '!tester hunt')])
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
            body = self.payload(bot, num, action, others)
            if body is None:
                return  # nothing to ask about yet (a pile in view): not a request, not counted
            c = self.cov(bot, key)
            c['tried'] += 1
            c['actions'][action] = c['actions'].get(action, 0) + 1
            if action in (self.opcodes[num][1].get('silent') or {}):
                c['ok'] += 1  # the server answers nothing by design (gen_tester_scenarios.py SILENT)
            else:
                self.pending[(bot.name, num)] = (key, action)
            send_ext(num, body)
        elif kind == 'fx':
            self.run_effect(bot, step, others, send_ext)
        elif kind == 'say':
            say(step[1])
        elif kind == 'walk':
            # a driver that cannot walk (a test, an old runner): the helper's teleport. TesterBot.do_opcodes walks the engine path
            # first and only falls back to this word (O589)
            say('!tester enter ' + step[1])
        elif kind == 'npc':
            say(step[1], NPC_CHANNEL)
        elif kind == 'check':
            # the helper's answer to the enter said a step ago
            c = self.cov(bot, step[1])
            c['tried'] += 1
            ans = bot.helper.get('enter') or {}
            if ans.get('err'):
                c['refused'] += 1
                c['actions'][str(ans['err'])[:40]] = c['actions'].get(str(ans['err'])[:40], 0) + 1
            elif ans and ans.get('walked'):
                c['ok'] += 1
                bump(c, 'walk')   # the bot walked the engine path there (O589): no helper shortcut
                c.setdefault('help', 0)
            elif ans:
                c['ok'] += 1
                bump(c, 'help')  # the helper's teleport brought the bot there: a shortcut, not a walk
                if ans.get('fallback'):
                    label = 'teleport: ' + str(ans['fallback'])[:50]   # a fallback is named and counted (O589)
                    c['actions'][label] = c['actions'].get(label, 0) + 1
            bot.helper['entered'] = bot.helper.pop('enter', None) or {}
        elif kind == 'usekey':
            cid = (bot.helper.get('entered') or {}).get('keyClientId')
            if cid:
                use_hotkey(int(cid))

    # ------------------------------------------------------------------ effects (O584 item 4)
    def run_effect(self, bot, step, others, send_ext):
        _, name, i = step
        e = self.effects.get(name)
        if e is None:
            return
        num = self.by_name[e['opcode']]
        c = self.cov(bot, e['system'])
        if i == 0:
            old = self.fx.get(bot.name)
            if old and old.get('wait'):
                bump(c, 'silent')  # the last chain never got its answer
            self.fx[bot.name] = {'effect': name, 'op': num, 'last': {}, 'wait': None, 'dead': False}
        fx = self.fx.get(bot.name)
        if not fx or fx['effect'] != name or fx['dead']:
            return
        if fx['wait'] is not None:  # the answer of the step before never came: the chain ends, nothing is judged
            fx['dead'] = True
            bump(c, 'silent')
            return
        st = e['steps'][i]
        data, ok = resolve_data(st.get('data'), fx['last'])
        if not ok:
            fx['dead'] = True
            bump(c, 'skipped')
            label = 'skip: no earlier answer to take the value from'
            c['actions'][label] = c['actions'].get(label, 0) + 1
            return
        body = {'action': st['action']}
        if data is not None:
            body['data'] = data
        c['tried'] += 1
        label = '%s:%s' % (name, st['action'])
        c['actions'][label] = c['actions'].get(label, 0) + 1
        fx['wait'] = {'reply': st['reply'], 'need': st.get('need') or [], 'expect': st.get('expect') or [],
                      'left': int(st.get('replies', 1)), 'key': e['system'], 'action': st['action'],
                      'before': fx['last'].get(st['reply'])}
        send_ext(num, json.dumps(body, separators=(',', ':')))

    def effect_answer(self, bot, op, msg):
        """True when the answer belongs to the running effect of the bot"""
        fx = self.fx.get(bot.name)
        if not fx or fx['dead'] or fx['op'] != op or not fx['wait']:
            return False
        w = fx['wait']
        c = self.cov(bot, w['key'])
        if is_refusal(msg):
            fx['wait'], fx['dead'] = None, True
            c['refused'] += 1
            return True
        if msg.get('action') != w['reply']:
            return False  # another answer of the window (a result, a push): not the one to judge
        fx['last'][w['reply']] = msg
        for cond in w['need']:
            good, why = cond_holds(cond, msg)
            if not good:
                fx['wait'], fx['dead'] = None, True
                bump(c, 'skipped')
                label = 'skip: ' + why[:60]
                c['actions'][label] = c['actions'].get(label, 0) + 1
                return True
        if not w['expect']:
            fx['wait'] = None
            c['ok'] += 1
            bump(c, 'ans')
            return True
        problems = []
        for cond in w['expect']:
            good, why = cond_holds(cond, msg, w['before'])
            if not good:
                problems.append(why)
        w['left'] -= 1
        if not problems:
            fx['wait'] = None
            c['ok'] += 1
            bump(c, 'real')
            return True
        if w['left'] > 0:
            return True  # the next answer of that kind may be the one that shows it
        fx['wait'], fx['dead'] = None, True
        bump(c, 'failed')
        bad = bot.results.d.setdefault('effects', [])
        if len(bad) < EFFECT_LIST_MAX:
            bad.append({'effect': fx['effect'], 'step': w['action'], 'bot': bot.name, 'why': '; '.join(problems)[:200]})
        log = getattr(bot.results, 'log', None)
        if log:
            log(bot, 'EFFECT', 'FAIL %s %s: %s' % (fx['effect'], w['action'], '; '.join(problems)[:200]))
        return True

    def on_answer(self, bot, op, msg):
        lst = self.answers.setdefault(bot.name, {}).setdefault(op, [])
        lst.append(msg)
        del lst[:-4]
        if self.effect_answer(bot, op, msg):
            return
        p = self.pending.pop((bot.name, op), None)
        if p:
            c = self.cov(bot, p[0])
            refuses = (self.opcodes.get(op, (None, {}))[1].get('refuses') or {})
            # a refusal the table lists is the right answer (a window the bots cannot have open)
            if is_refusal(msg) and p[1] not in refuses:
                c['refused'] += 1
            else:
                c['ok'] += 1
                bump(c, 'ans')  # an answer, no effect checked (an effect that is checked counts REAL or failed)


def attach(a, path):
    """testers.py run --scenarios: a.next_request / a.on_answer / a.scenarios_runner"""
    s = Scenarios(load(path), getattr(a, 'ops', None))
    a.scenarios_runner = s
    a.next_request = s.next_request
    a.on_answer = s.on_answer
    return s


def merge(table, run_cov, log, checks=None):
    """the per-system coverage of the report: every system of the table -> {tried, ok, refused, errors, why, real, ans,
    help, failed}. REAL: an effect the bot saw (an effect scenario that held, a system check that passed); ANS: an answer
    with no effect checked; HELP: the helper's shortcut took the bot there (teleport, item). failed: an answer without its
    effect, or a system check that failed.
    run_cov: the bots' coverage (results 'coverage'); log: tester_core.parse_log of the run's server log;
    checks: the run's system check results (tester_checks Result.as_dict)."""
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
    by_check = {}
    for r in checks or []:
        key = CHECK_SYSTEMS.get(r.get('check'), 'check:' + str(r.get('check')))
        row = by_check.setdefault(key, {'tried': 0, 'ok': 0, 'real': 0, 'help': 0, 'failed': 0})
        if r.get('status') == 'pass':
            row['tried'] += 1
            row['ok'] += 1
            row['real'] += 1   # the check asserts an effect it saw
            row['help'] += 1   # and the helper set it up
        elif r.get('status') == 'fail':
            row['tried'] += 1
            row['failed'] += 1
            row['help'] += 1
    out = {}
    for name, s in sorted(table.get('systems', {}).items()):
        c = dict(run_cov.get(name) or {})
        place = run_cov.get('place:' + name) or {}
        ch = by_check.pop(name, {})
        row = {'tried': c.get('tried', 0) + place.get('tried', 0) + ch.get('tried', 0),
               'ok': c.get('ok', 0) + place.get('ok', 0) + ch.get('ok', 0),
               'refused': c.get('refused', 0) + place.get('refused', 0), 'errors': errors.get(name, 0),
               'kind': s.get('kind'), 'real': c.get('real', 0) + ch.get('real', 0),
               'failed': c.get('failed', 0) + ch.get('failed', 0),
               'ans': c.get('ans', max(0, c.get('ok', 0) - c.get('real', 0))) + place.get('walk', 0),
               'help': c.get('help', 0) + place.get('help', place.get('ok', 0)) + ch.get('help', 0)}
        kind = s.get('kind')
        if kind in ('out', 'staff'):
            row['why'] = 'out of scope: ' + s.get('why', '')
        elif kind == 'closed':
            row['why'] = 'closed test mode: ' + s.get('why', '') + ' (testers.py run --closed)'
        elif kind == 'passive':
            row['why'] = 'passive (reached by play; only log errors name it)'
        elif not row['tried']:
            row['why'] = 'not picked in this run (more bots or minutes)'
        out[name] = row
    for key, c in run_cov.items():
        # NPC dialogs, the rift key, opcodes no system owns
        if key not in out and not (key.startswith('place:') and key[6:] in out):
            out[key] = dict(c, errors=0)
            helped = key.startswith(('npc:', 'place:'))
            out[key]['help'] = c.get('help', c.get('ok', 0) if helped else 0)
            out[key].setdefault('real', 0)
            out[key].setdefault('ans', c.get('walk', 0) if helped else c.get('ok', 0))
    for key, ch in by_check.items():
        out[key] = dict(ch, refused=0, errors=0, ans=0)
    return out
