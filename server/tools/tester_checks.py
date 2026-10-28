#!/usr/bin/env python3
"""The system checks of the tester bots (O110; server/README.md "Tester bots", System checks).

testers.py run --checks: each bot, once per run, takes the checks that apply to its class and asserts something about a
system the coverage layer (tester_scenarios.py: requests and places) only touches: summons and pets, the Necromancer's
minions, the Beastmaster's wolf, party play, rifts, waystones, the cursed chest, reward chests, and the Auto setup spell
list of the class. A check that fails prints one line, "BUG <check>: <what> (<bot>, <class>)", in the report, in
run.json ("checks") and in the log. A check that cannot run (no spell yet, no partner, no pet, the system is not in the
server) is SKIP with the reason: nothing is faked.

O86 (the Beastmaster wolf and its owner took each other for enemies; the cause was never seen): the summon checks watch
the summons of a bot for 20 seconds and fail on a summon that targets its owner, a party member or their summons, on an
owner that holds a summon as target, and on allies left in the engine target list of a summon (the helper counts them,
`!tester summons`). The same rules run in the helper's loop for every tester with a summon, all the time
("[tester-anomaly] summon_targets_owner" ...).

No god command, no development key: the checks use the helper's `!tester` commands (a TEST ONLY script that acts only on
"Tester Xxx" characters with the tester storage), spell words, party packets and the requests a client window sends.

The pure flow lives here and talks to the game through an `io` object (testers.py CheckIO): async helper(command, kind,
wait) -> the helper's answer dict or None; async say(text); async sleep(seconds); alive(); async request(opname, action,
data, expect, timeout) -> the answer or None ("*" in expect: any action); async party(action, other) with action
"form" | "leave" (True when both packets could be sent); async partner() -> the name of another bot in game or None;
go(place) -> True ('town' / 'hunt' through the helper); autosetup() -> the rotation table (load_table) or None; spells() ->
{id: {level, vocations, name}} of the server. The tests (tester_checks_test.py) give it a
mocked server. Standard library only.
"""
import json

PASS, FAIL, SKIP = 'pass', 'fail', 'skip'
STATUSES = (FAIL, PASS, SKIP)

WATCH = 20.0        # seconds a summon is watched for a wrong target
LOOK = 2.0          # seconds between two looks
SETTLE = 3.0        # seconds after a cast, a teleport or a party change before the first look (the server's purge runs at 0.5 s)
ANSWER = 6.0

# class (vocation name of vocations.xml) -> the summon spell words (spells_chaos.xml) and the check that owns it
SUMMONERS = {
    'Beastmaster': ('vael ferh', 'beastmaster_wolf', 2),   # Wild Bond: a war wolf, 2 from level 400
    'Necromancer': ('vael oss', 'necro_minions', 5),       # Raise Dead
    'Lich': ('vael oss', 'necro_minions', 5),
    'Bone Lord': ('vael oss', 'necro_minions', 5),
}
SIDES_BAD = ('owner', 'ally', 'summon')   # what a summon must never have as its target


def class_key(name):
    return ''.join(ch for ch in str(name or '').lower() if ch.isalnum())


def snapshot_problems(snap):
    """[text] for one `!tester summons` answer: every wrong side in it"""
    out = []
    if not isinstance(snap, dict):
        return out
    for s in snap.get('summons') or []:
        if s.get('target') in SIDES_BAD:
            out.append('%s #%s targets %s' % (s.get('name', 'summon'), s.get('id', '?'),
                                              'its owner' if s['target'] == 'owner' else 'an ally (%s)' % s['target']))
        if int(s.get('listedAllies') or 0) > 0:
            out.append('%s #%s has %d allies in its engine target list' % (
                s.get('name', 'summon'), s.get('id', '?'), int(s['listedAllies'])))
    if snap.get('ownerTarget') == 'summon':
        out.append('the owner holds its own or a party member\'s summon as target')
    return out


class Result:
    def __init__(self, check, bot, cls, status, detail=''):
        self.check, self.bot, self.cls, self.status, self.detail = check, bot, cls, status, detail

    def bug_line(self):
        return 'BUG %s: %s (%s, %s)' % (self.check, self.detail, self.bot, self.cls) if self.status == FAIL else None

    def as_dict(self):
        return {'check': self.check, 'bot': self.bot, 'class': self.cls, 'status': self.status, 'detail': self.detail}


# ------------------------------------------------------------------------------------------------ the checks
async def watch_summons(io, seconds):
    """looks at the summons of the bot every LOOK seconds; (problems, last snapshot)"""
    problems, last = [], None
    waited = 0.0
    while waited <= seconds and io.alive():
        snap = await io.helper('summons', 'summons', ANSWER)
        if isinstance(snap, dict) and not snap.get('err'):
            last = snap
            for p in snapshot_problems(snap):
                if p not in problems:
                    problems.append(p)
        await io.sleep(LOOK)
        waited += LOOK
    return problems, last


async def check_summons(io, name, cls, level):
    """the class's own summon: cast it, watch it, then teleport (the leash and the portal paths) and watch again"""
    words, check, cap = SUMMONERS[cls]
    if not await io.go('hunt'):
        return Result(check, name, cls, SKIP, 'the helper did not bring the bot to its hunt spot')
    await io.say(words)
    await io.sleep(SETTLE)
    snap = await io.helper('summons', 'summons', ANSWER)
    if not isinstance(snap, dict) or snap.get('err'):
        return Result(check, name, cls, SKIP, 'no answer to !tester summons')
    count = int(snap.get('count') or 0)
    if count == 0:
        return Result(check, name, cls, SKIP, 'no summon after "%s" (level %s: not learned, no mana or on cooldown)' % (words, level))
    if count > cap + 1:
        return Result(check, name, cls, FAIL, '%d summons after one cast, the cap is %d' % (count, cap))
    problems, _ = await watch_summons(io, WATCH)
    if problems:
        return Result(check, name, cls, FAIL, '; '.join(problems[:3]))
    # teleport away and back (town portal, leash): the engine lists everybody in sight again
    if await io.go('town'):
        await io.sleep(SETTLE)
        await io.go('hunt')
        await io.sleep(SETTLE)
        problems, last = await watch_summons(io, 6.0)
        if problems:
            return Result(check, name, cls, FAIL, 'after a teleport: ' + '; '.join(problems[:3]))
    return Result(check, name, cls, PASS, '%d summon(s), no wrong target in %d s and after a teleport' % (count, int(WATCH)))


async def check_pets(io, name, cls, level):
    """call out a pet the character owns, it is a summon of the bot and never targets it; dismiss it"""
    state = await io.request('pets', 'get', {}, ['state'], ANSWER)
    if not state:
        return Result('pets', name, cls, SKIP, 'no answer from the pets window (below its level gate or not installed)')
    data = state.get('data') or {}
    owned = [p.get('species') or p.get('key') for p in data.get('pets') or [] if isinstance(p, dict)]
    owned = [o for o in owned if o]
    if not owned:
        return Result('pets', name, cls, SKIP, 'the bot owns no pet')
    if not await io.go('hunt'):
        return Result('pets', name, cls, SKIP, 'the helper did not bring the bot to its hunt spot')
    await io.request('pets', 'summon', {'species': owned[0]}, ['state'], ANSWER)
    await io.sleep(SETTLE)
    snap = await io.helper('summons', 'summons', ANSWER)
    if not snap or snap.get('err'):
        return Result('pets', name, cls, SKIP, 'no answer to !tester summons')
    if int(snap.get('count') or 0) < 1:
        return Result('pets', name, cls, SKIP, 'the pet did not come out (cooldown or a zone rule)')
    problems, _ = await watch_summons(io, 10.0)
    await io.request('pets', 'dismiss', {}, ['state'], ANSWER)
    await io.sleep(1.5)
    after = await io.helper('summons', 'summons', ANSWER)
    if problems:
        return Result('pets', name, cls, FAIL, '; '.join(problems[:3]))
    if after and int(after.get('count') or 0) > 0 and after.get('summons') and any(
            s.get('name', '').lower() == (snap['summons'][0].get('name') or '').lower() for s in after['summons']):
        return Result('pets', name, cls, FAIL, 'the pet is still out after dismiss')
    return Result('pets', name, cls, PASS, 'pet %s: out, no wrong target, gone after dismiss' % owned[0])


async def check_party(io, name, cls, level):
    """two bots form a party and leave it: the helper sees the size; a bot with a summon keeps its sides in the party"""
    other = await io.partner()
    if not other:
        return Result('party', name, cls, SKIP, 'no other bot in game')
    if not await io.party('form', other):
        return Result('party', name, cls, SKIP, 'the invite could not be sent')
    await io.sleep(SETTLE)
    p = await io.helper('party', 'party', ANSWER)
    if not p or p.get('err'):
        return Result('party', name, cls, SKIP, 'no answer to !tester party')
    if int(p.get('size') or 0) < 2:
        await io.party('leave', other)
        return Result('party', name, cls, FAIL, 'invited %s, joined, the party has %s member(s)' % (other, p.get('size')))
    detail = 'party of %s' % p.get('size')
    if cls in SUMMONERS:
        words = SUMMONERS[cls][0]
        await io.say(words)
        await io.sleep(SETTLE)
        problems, last = await watch_summons(io, 12.0)
        if problems:
            await io.party('leave', other)
            return Result('party', name, cls, FAIL, 'in a party: ' + '; '.join(problems[:3]))
        detail += ', summons keep their sides'
    await io.party('leave', other)
    await io.sleep(SETTLE)
    p = await io.helper('party', 'party', ANSWER)
    if p and not p.get('err') and int(p.get('size') or 0) >= 2:
        return Result('party', name, cls, FAIL, 'left the party, the helper still sees %s members' % p.get('size'))
    return Result('party', name, cls, PASS, detail + ', and gone after leaving')


async def check_rift(io, name, cls, level):
    """the helper gives a rift key and enters; the answer must say so, then back to the hunt"""
    r = await io.helper('enter rift 1', 'enter', 8.0)
    await io.go('hunt')
    if not r:
        return Result('rift', name, cls, SKIP, 'no answer to !tester enter rift')
    if r.get('err'):
        return Result('rift', name, cls, FAIL, 'enter rift: %s' % str(r['err'])[:80])
    q = await io.request('rift', 'query', {}, ['*'], ANSWER)
    if q is None:
        return Result('rift', name, cls, SKIP, 'key given; the rift window did not answer')
    return Result('rift', name, cls, PASS, 'key given, the rift window answered')


async def check_opcode(io, name, cls, level, check, opname, action, data=None):
    q = await io.request(opname, action, data or {}, ['*'], ANSWER)
    if q is None:
        return Result(check, name, cls, SKIP, '%s %s: no answer (level gate, or not installed)' % (opname, action))
    if (q.get('data') or {}).get('err'):
        return Result(check, name, cls, FAIL, '%s %s answered an error: %s' % (opname, action, str(q['data']['err'])[:80]))
    return Result(check, name, cls, PASS, '%s %s answered' % (opname, action))


async def check_waystone(io, name, cls, level):
    return await check_opcode(io, name, cls, level, 'waystone', 'waystoneAtlas', 'open')


async def check_reward_chest(io, name, cls, level):
    r = await check_opcode(io, name, cls, level, 'reward_chest', 'weeklyChest', 'open')
    await io.request('weeklyChest', 'close', {}, [], ANSWER)
    return r


async def check_cursed_chest(io, name, cls, level):
    """a chest next to the bot: spawn, use (the horde starts), abort; nothing may be left"""
    a = await io.helper('chest spawn', 'chest', ANSWER)
    if not a:
        return Result('cursed_chest', name, cls, SKIP, 'no answer to !tester chest')
    if a.get('err'):
        return Result('cursed_chest', name, cls, SKIP, str(a['err'])[:80])
    if a.get('state') != 'idle':
        await io.helper('chest abort', 'chest', ANSWER)
        return Result('cursed_chest', name, cls, FAIL, 'spawned chest is %r, expected idle' % a.get('state'))
    u = await io.helper('chest use', 'chest', ANSWER)
    await io.sleep(SETTLE)
    s = await io.helper('chest state', 'chest', ANSWER)
    bad = []
    if not u or u.get('state') not in ('running', 'idle'):
        bad.append('after use the chest is %r' % (u or {}).get('state'))
    if s and s.get('state') == 'running' and int(s.get('monsters') or 0) < 1:
        bad.append('the event runs with no monster')
    z = await io.helper('chest abort', 'chest', ANSWER)
    await io.sleep(1.0)
    z = await io.helper('chest state', 'chest', ANSWER) or z
    if z and (z.get('state') not in ('none', 'gone') or int(z.get('left') or 0) > 0):
        bad.append('after abort the chest is still %r (left %s)' % (z.get('state'), z.get('left')))
    if bad:
        return Result('cursed_chest', name, cls, FAIL, '; '.join(bad))
    return Result('cursed_chest', name, cls, PASS, 'spawn, use, abort: the chest and its monsters are gone')


async def check_auto_setup(io, name, cls, level):
    """Auto setup lists (O186): the spells the client's preset holds for this class and level are all castable. Done
    offline against the data (auto_setup_problems); here the bot's own list is looked up in the table given to the run."""
    table = io.autosetup()
    if not table:
        return Result('auto_setup', name, cls, SKIP, 'no rotation table (autorotation_data.lua) was given')
    bad = auto_setup_problems(table, cls, level, io.spells())
    if bad is None:
        return Result('auto_setup', name, cls, SKIP, 'the class is not in the rotation table')
    if bad:
        return Result('auto_setup', name, cls, FAIL, '; '.join(bad[:3]))
    return Result('auto_setup', name, cls, PASS, 'the preset of level %s is castable' % level)


def preset_for(presets, level):
    """the last preset whose level the character has reached (the client takes the best rotation from its level on)"""
    best = None
    for p in presets:
        if p['level'] <= level:
            best = p
    return best


def auto_setup_problems(table, cls, level, spells):
    """table: {class name: {'presets': [{'level', 'spells': [id]}]}}; spells: {id: {'level', 'vocations': [ids], 'name'}} of
    the server. [] when every spell of the class's preset at `level` exists, is open to the class and is not gated higher;
    None when the class has no row"""
    row = table.get(cls)
    if not row:
        return None
    voc = row.get('voc')
    p = preset_for(row['presets'], level)
    if not p:
        return []
    out = []
    for sid in p['spells']:
        s = spells.get(sid)
        if not s:
            out.append('spell %d is not on the server' % sid)
            continue
        if s.get('vocations') and voc not in s['vocations']:
            out.append('%s (%d) is not open to %s' % (s.get('name', sid), sid, cls))
        if s.get('level', 0) > level:
            out.append('%s (%d) needs level %s' % (s.get('name', sid), sid, s['level']))
    return out


# the checks in the order they run; (key, function, applies(cls) -> bool)
def _summoner(cls):
    return cls in SUMMONERS


CHECKS = [
    ('beastmaster_wolf', check_summons, lambda c: c == 'Beastmaster'),
    ('necro_minions', check_summons, lambda c: c in ('Necromancer', 'Lich', 'Bone Lord')),
    ('pets', check_pets, lambda c: True),
    ('party', check_party, lambda c: True),
    ('rift', check_rift, lambda c: True),
    ('waystone', check_waystone, lambda c: True),
    ('reward_chest', check_reward_chest, lambda c: True),
    ('cursed_chest', check_cursed_chest, lambda c: True),
    ('auto_setup', check_auto_setup, lambda c: True),
]
KEYS = tuple(k for k, _, _ in CHECKS)


class CheckRun:
    """the checks of one bot; results go on after a death (a check cut off by it is done again) like the keystone scenario"""

    def __init__(self, name, cls, level, only=None):
        self.name, self.cls, self.level = name, cls, level
        self.only = set(only) if only else None
        self.done = set()
        self.results = []
        self.resets = []

    def todo(self):
        return [k for k, _, ok in CHECKS if ok(self.cls) and k not in self.done and (not self.only or k in self.only)]

    async def run(self, io):
        """True when no check failed; stops early when the bot is gone"""
        for key, fn, ok in CHECKS:
            if key in self.done or not ok(self.cls) or (self.only and key not in self.only):
                continue
            if not io.alive():
                return False
            try:
                r = await fn(io, self.name, self.cls, self.level)
            except Exception as e:  # noqa: BLE001 - a check that breaks is a result, not a crash of the run
                r = Result(key, self.name, self.cls, SKIP, 'the check broke: %s' % e)
            if not io.alive() and r.status != PASS:
                return False   # cut off by the bot's own death: not a result, done again after the next login
            self.results.append(r)
            self.done.add(key)
        return not any(r.status == FAIL for r in self.results)

    @property
    def finished(self):
        return not self.todo()


def report_lines(results):
    """results: list of Result.as_dict(); the report section"""
    if not results:
        return []
    by = {}
    for r in results:
        by.setdefault(r['check'], {PASS: 0, FAIL: 0, SKIP: 0})[r['status']] += 1
    L = ['== System checks (%d results; pass / fail / skip per check)' % len(results)]
    for key in sorted(by):
        c = by[key]
        L.append('  %-18s %4d %4d %4d' % (key, c[PASS], c[FAIL], c[SKIP]))
    bugs = [r for r in results if r['status'] == FAIL]
    for r in bugs:
        L.append('  BUG %s: %s (%s, %s)' % (r['check'], r['detail'], r['bot'], r['class']))
    skips = {}
    for r in results:
        if r['status'] == SKIP:
            skips.setdefault((r['check'], r['detail']), 0)
            skips[(r['check'], r['detail'])] += 1
    for (key, why), n in sorted(skips.items()):
        L.append('  skip %-14s %3dx %s' % (key, n, why[:100]))
    return L


def load_table(path):
    """the rotation table for check_auto_setup from autorotation_data.lua: {class name: {'voc', 'presets'}}"""
    import re
    with open(path, encoding='utf-8') as f:
        text = f.read()
    head, _, _ = text.partition('  spells = {')
    out = {}
    for m in re.finditer(r'\[(\d+)\] = \{ name = "([^"]+)", presets = \{(.*?)\}, (?:extras = \{ ([\d, ]*) \}, )?(?:ultimate = \d+, )?heals', head, re.S):
        presets = []
        for p in re.finditer(r'\{ level = (\d+), gap = [\d.]+, spells = \{ ([\d, ]+) \}', m.group(3)):
            presets.append({'level': int(p.group(1)), 'spells': [int(x) for x in p.group(2).split(',')]})
        out[m.group(2)] = {'voc': int(m.group(1)), 'presets': presets}
    return out


if __name__ == '__main__':
    print(json.dumps({'checks': list(KEYS)}))
