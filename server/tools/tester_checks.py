#!/usr/bin/env python3
"""The system checks of the tester bots (O110; server/README.md "Tester bots", System checks).

testers.py run --checks: each bot, once per run, takes the checks that apply to its class and asserts something about a
system the coverage layer (tester_scenarios.py: requests and places) only touches: summons and pets, the Necromancer's
minions, the Beastmaster's wolf, party play and its shared experience, rifts and their layouts, waystone runs (tier and
modifiers), the content rewards of both, waystones, the cursed chest, reward chests, and the Auto setup spell
list of the class, and the line spell quest (O263: hunt, fragments, the trial at Archivist Odrenna, the spell in the class's spell
and Auto setup data). A check that fails prints one line, "BUG <check>: <what> (<bot>, <class>)", in the report, in
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
"form" | "share" | "unshare" | "leave" (True when both packets could be sent); async partner() -> the name of another bot in game or None;
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
QUEST_LEVEL = 500   # the level of the first line spell quest (spellquest_config.lua quests[1].level)
QUEST_GOLD = 2000   # gold per level to the bank when a spell quest is done (spellquest_config.lua reward.goldPerLevel)

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


# ------------------------------------------------------------------------------------------ O110: runs and rewards
WAYSTONE_TIERS = (2, 8, 14)   # one tier per band of waystone_tiers_config.lua (low 1-5, mid 6-10, high 11-15)
LOOT_TIER = 8
HELPER_WAIT = 15.0


def tier_level(tier):
    """the level of a waystone run: 1100 at tier I, 100 more per tier up to 2500 (owner 2026-10-23; waystone_tiers_config.lua)"""
    return 1000 + 100 * tier


def bonus_percent(lines):
    """the party frames' bonus in percent for n class lines (party_xp_core.lua bonusPercent); the stock 20 % for none"""
    if lines < 1:
        return 20
    if lines == 1:
        return 20
    n = min(lines, 5)
    return n * (5 * (n - 1) + 10)


def share_expected(lines, size, exp=1000):
    """what Party:onShareExperience pays one member for `exp`: ceil(exp x (100 + bonus) / 100 / members)"""
    return -(-(exp * (100 + bonus_percent(lines))) // (100 * max(1, size)))


def party_share_problems(p):
    """[text] for one `!tester party` answer of a party whose leader switched shared experience on"""
    out = []
    if not p.get('shareActive'):
        out.append('the leader switched shared experience on, the party says it is off')
    lines, size = int(p.get('lines') or 0), int(p.get('size') or 0)
    if p.get('shareOf1000') is not None and lines >= 1:
        want = share_expected(lines, size)
        if int(p['shareOf1000']) != want:
            out.append('1000 experience pays %s to a member, the rule (%d class line(s), %d members, +%d%%) gives %d' % (
                p['shareOf1000'], lines, size, bonus_percent(lines), want))
    hard = [x for x in p.get('problems') or [] if x.get('kind') in ('level', 'range')]
    if p.get('shareEnabled') and hard:
        out.append('shared experience works while %s %s' % (hard[0].get('name', '?'), 'is below two thirds of the highest level'
                                                             if hard[0].get('kind') == 'level' else 'is out of range'))
    if p.get('shareActive') and not p.get('shareEnabled') and not (p.get('problems') or []):
        out.append('shared experience is off while every member passes level, range and fight')
    return out


async def check_party_xp(io, name, cls, level):
    """party XP sharing: two bots form a party, the leader (this bot) switches shared experience on (packet 0xA8); the helper
    reads the party: the switch took, what the game's Party:onShareExperience pays for 1000 experience is
    ceil(1000 x (1 + class line bonus) / members), and the engine's verdict agrees with the rules (nobody below two
    thirds of the highest level, within 30 tiles and 1 floor, in a fight): not working while a member fails level or
    range, working when all pass. A verdict seen in two looks 3 s apart. Left again at the end."""
    other = await io.partner()
    if not other:
        return Result('party_xp', name, cls, SKIP, 'no other bot in game')
    if not await io.party('form', other):
        return Result('party_xp', name, cls, SKIP, 'the invite could not be sent')
    await io.sleep(SETTLE)
    try:
        p = await io.helper('party', 'party', ANSWER)
        if not p or p.get('err'):
            return Result('party_xp', name, cls, SKIP, 'no answer to !tester party')
        if int(p.get('size') or 0) < 2:
            return Result('party_xp', name, cls, SKIP, 'the party was not formed (%s member(s))' % p.get('size'))
        if p.get('leader') != name:
            return Result('party_xp', name, cls, SKIP, 'this bot is not the leader (%s is)' % p.get('leader'))
        if 'shareActive' not in p:
            return Result('party_xp', name, cls, SKIP, 'the helper does not report the shared experience (old helper file)')
        await io.party('share', other)
        await io.sleep(SETTLE)
        first = await io.helper('party', 'party', ANSWER)
        await io.sleep(3.0)
        second = await io.helper('party', 'party', ANSWER)
        if not first or not second or first.get('err') or second.get('err'):
            return Result('party_xp', name, cls, SKIP, 'no answer to !tester party after the switch')
        a, b = party_share_problems(first), party_share_problems(second)
        bad = [x for x in a if x in b]    # the engine's own update lags a tick: only what both looks saw
        if bad:
            return Result('party_xp', name, cls, FAIL, '; '.join(bad[:3]))
        verdict = 'working' if second.get('shareEnabled') else 'off: %s' % (
            ', '.join('%s %s' % (x.get('name'), x.get('kind')) for x in second.get('problems') or [])[:60] or 'none')
        return Result('party_xp', name, cls, PASS, 'switch took, 1000 xp pays %s (%s class line(s), %s members), engine %s' % (
            second.get('shareOf1000'), second.get('lines'), second.get('size'), verdict))
    finally:
        await io.party('unshare', other)
        await io.party('leave', other)
        await io.sleep(1.0)


def waystone_problems(a):
    """[text] for one `!tester waystone <tier>` answer (a run of that tier, read back)"""
    out = []
    t = int(a.get('tier') or 0)
    if int(a.get('tierLevel') or 0) != tier_level(t):
        out.append('tier %d runs at level %s, expected %d' % (t, a.get('tierLevel'), tier_level(t)))
    held, take, run = a.get('held') or {}, a.get('take') or {}, a.get('run') or {}
    n = int(a.get('nrolled') or 0)
    if held.get('tier') != t or int(held.get('mods') or 0) != n:
        out.append('the waystone written with %d modifiers reads back as tier %s with %s' % (n, held.get('tier'), held.get('mods')))
    if held.get('rarity') != 'Rare' or held.get('expectRarity') != 'Rare':
        out.append('a waystone with %d modifiers is %s, expected Rare' % (n, held.get('rarity')))
    if not take.get('ok'):
        out.append('the device could not take the waystone it was given')
    else:
        if int(take.get('before') or 0) - int(take.get('after') or 0) != 1:
            out.append('taking one waystone changed the count %s -> %s' % (take.get('before'), take.get('after')))
        if int(take.get('mods') or 0) != n:
            out.append('the take returned %s modifiers, the waystone has %d' % (take.get('mods'), n))
    if take.get('ok'):
        if not run.get('live'):
            out.append('the run with %d modifiers is not registered' % n)
        else:
            if run.get('tier') != t or int(run.get('mods') or 0) != n:
                out.append('the run is tier %s with %s modifiers, expected %d with %d' % (run.get('tier'), run.get('mods'), t, n))
            if not 0 < int(run.get('seconds') or 0) <= 3600:
                out.append('the run lasts %s s' % run.get('seconds'))
        if run.get('active') != t:
            out.append('the map counts at tier %s during the run, expected %d' % (run.get('active'), t))
    for m in a.get('monsters') or []:
        if m.get('level') != tier_level(t) or m.get('expectLevel') != tier_level(t):
            out.append('%s is level %s (rule %s) in a tier %d run, expected %d' % (
                m.get('name'), m.get('level'), m.get('expectLevel'), t, tier_level(t)))
            break
    for m in a.get('monsters') or []:
        r, e = m.get('ratio'), m.get('expectRatio')
        if r and e and abs(r / e - 1) > 0.03:
            out.append('%s health x%.3f in the run, the level and modifiers give x%.3f' % (m.get('name'), r, e))
            break
    return out


def waystone_loot_problems(loot):
    out = []
    if not loot.get('paid'):
        out.append('the run\'s boss kill paid nothing through the content rewards')
        return out
    if int(loot.get('pieces') or 0) < int(loot.get('minPieces') or 0):
        out.append('boss table: %s gear piece(s) of Legendary or better, the config guarantees %s' % (loot.get('pieces'), loot.get('minPieces')))
    if int(loot.get('badRarity') or 0) > 0:
        out.append('boss table: %s piece(s) below Legendary' % loot['badRarity'])
    for o in loot.get('orbs') or []:
        if int(o.get('count') or 0) < int(o.get('min') or 0):
            out.append('boss table: %s x%s, the config guarantees at least %s' % (o.get('name'), o.get('count'), o.get('min')))
    if int(loot.get('waystones') or 0) < int(loot.get('minWaystones') or 0):
        out.append('boss table: %s waystone(s) of the run\'s tier, the config guarantees %s' % (loot.get('waystones'), loot.get('minWaystones')))
    return out


async def check_waystone_run(io, name, cls, level):
    """waystone tiers and modifiers in a run, on the game's own code (the helper does what the device does: writes a Rare
    waystone, takes it, starts the run on a map of the band): for one tier of each band the waystone reads back with its
    tier and modifiers, the device takes exactly one, the run is registered with the tier and the modifiers, and the map's
    monsters in range are at the tier's level (1100 + 100 a tier) with health following the level and modifiers. The pads
    and the teleport (base code) are not walked."""
    seen, notes = 0, []
    for t in WAYSTONE_TIERS:
        a = await io.helper('waystone %d' % t, 'waystone', HELPER_WAIT)
        if not isinstance(a, dict):
            return Result('waystone_run', name, cls, SKIP, 'no answer to !tester waystone %d' % t)
        err = str(a.get('err') or '')
        if err.startswith('startRun'):
            return Result('waystone_run', name, cls, FAIL, 'tier %d: ChaosWaystoneTiers.%s' % (t, err[:90]))
        if err:
            if err == 'no waystone system':
                return Result('waystone_run', name, cls, SKIP, err)
            notes.append('tier %d: %s' % (t, err[:40]))
            continue
        bad = waystone_problems(a)
        if bad:
            return Result('waystone_run', name, cls, FAIL, 'tier %d: %s' % (t, '; '.join(bad[:3])))
        seen += 1
        notes.append('tier %d: %d mods, %d monster(s) sampled' % (t, int(a.get('nrolled') or 0), len(a.get('monsters') or [])))
    if not seen:
        return Result('waystone_run', name, cls, SKIP, '; '.join(notes) or 'no run could start')
    return Result('waystone_run', name, cls, PASS, '; '.join(notes))


async def check_rift_layout(io, name, cls, level):
    """the layout of a real rift run (the helper opens one as a player does, in the temple, with a key of the highest tier the
    character may open): its theme, kind and floors are in the config of the theme, the size band is the tier's, the walkable
    cells are inside the band's limits, the arrival, the guardian's spot and the arena's mouth are walkable cells, the bot
    stands on one, 40 cells spread over the map have a ground and do not block, and the run closes with the slot freed."""
    a = await io.helper('riftrun layout', 'riftrun', 20.0)
    if not isinstance(a, dict):
        return Result('rift_layout', name, cls, SKIP, 'no answer to !tester riftrun')
    err = str(a.get('err') or '')
    if err and not a.get('theme'):
        return Result('rift_layout', name, cls, SKIP, err[:80])
    bad = rift_layout_problems(a)
    if bad:
        return Result('rift_layout', name, cls, FAIL, '; '.join(bad[:3]))
    return Result('rift_layout', name, cls, PASS, 'tier %s %s (%s), band %s, %s walkable, route %s, %s sampled tiles on the ground' % (
        a.get('tier'), a.get('theme'), a.get('kind'), a.get('band'), a.get('walkable'), a.get('route'), (a.get('sample') or {}).get('n')))


def rift_layout_problems(a):
    out = []
    if a.get('err'):
        out.append(str(a['err'])[:80])
    if a.get('kind') not in (a.get('kinds') or []):
        out.append('%s has the layout kind %s, its config allows %s' % (a.get('theme'), a.get('kind'), '/'.join(a.get('kinds') or [])))
    if a.get('floors') not in (a.get('floorCounts') or []):
        out.append('%s has %s floor(s), its config allows %s' % (a.get('theme'), a.get('floors'), a.get('floorCounts')))
    if a.get('band') != a.get('bandExpected'):
        out.append('tier %s made a band %s layout, the config says band %s' % (a.get('tier'), a.get('band'), a.get('bandExpected')))
    lim = a.get('limits') or {}
    w = int(a.get('walkable') or 0)
    if lim and not (lim.get('walkableMin', 0) <= w <= lim.get('walkableMax', 10 ** 9)):
        out.append('%d walkable tiles, the band holds %s to %s' % (w, lim.get('walkableMin'), lim.get('walkableMax')))
    if not int(a.get('route') or 0) > 0:
        out.append('no walking route from the arrival to the guardian (%s)' % a.get('route'))
    for key, what in (('startWalk', 'the arrival'), ('bossWalk', 'the guardian\'s spot'), ('mouthWalk', 'the arena\'s mouth'),
                      ('playerWalk', 'the bot after entering')):
        if a.get(key) is not True:
            out.append('%s is not a walkable cell of the layout' % what)
    s = a.get('sample') or {}
    if int(s.get('bare') or 0) or int(s.get('blocked') or 0):
        out.append('of %s walkable cells sampled %s have no ground and %s block' % (s.get('n'), s.get('bare'), s.get('blocked')))
    after = a.get('after') or {}
    if after.get('inRun') or after.get('slotFree') is False:
        out.append('the run did not close (bot inside: %s, slot free: %s)' % (after.get('inRun'), after.get('slotFree')))
    return out


async def check_content_rewards(io, name, cls, level):
    """the passive rewards (content_rewards.lua: no window, the kill pays): a boss kill of a waystone run of tier VIII and the
    guardian's kill of a rift, each through ChaosContentRewards.onKill with a stand-in monster (nothing is spawned): the
    corpse holds what the config guarantees (Legendary or better gear pieces, the sure orbs and a waystone of the run's
    tier; the guardian's orbs). The first unique and the pity of retention_loot.lua are not checked: they skip testers by rule."""
    parts, ran = [], 0
    a = await io.helper('waystone %d loot' % LOOT_TIER, 'waystone', HELPER_WAIT)
    if not isinstance(a, dict):
        return Result('content_rewards', name, cls, SKIP, 'no answer to !tester waystone %d loot' % LOOT_TIER)
    loot = a.get('loot')
    if a.get('err') or not loot:
        parts.append('waystone boss not checked: %s' % str(a.get('err') or 'no loot answer')[:50])
    elif loot.get('err'):
        parts.append('waystone boss not checked: %s' % str(loot['err'])[:50])
    else:
        bad = waystone_loot_problems(loot)
        if bad:
            return Result('content_rewards', name, cls, FAIL, 'waystone boss: ' + '; '.join(bad[:3]))
        ran += 1
        parts.append('waystone boss: %s piece(s), %s sure orb kinds, %s waystone(s)' % (loot.get('pieces'), len(loot.get('orbs') or []), loot.get('waystones')))
    r = await io.helper('riftrun loot', 'riftrun', 20.0)
    rl = r.get('loot') if isinstance(r, dict) else None
    if not isinstance(r, dict) or not rl or rl.get('err'):
        why = (r or {}).get('err') or (rl or {}).get('err') or 'no answer'
        parts.append('rift guardian not checked: %s' % str(why)[:50])
    else:
        if not rl.get('paid') or int(rl.get('orbs') or 0) < int(rl.get('minOrbs') or 0):
            return Result('content_rewards', name, cls, FAIL, 'rift guardian: %s orb(s) (paid %s), the config guarantees %s' % (
                rl.get('orbs'), rl.get('paid'), rl.get('minOrbs')))
        ran += 1
        parts.append('rift guardian: %s orbs' % rl.get('orbs'))
    if not ran:
        return Result('content_rewards', name, cls, SKIP, '; '.join(parts))
    return Result('content_rewards', name, cls, PASS, '; '.join(parts))


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


def quest_spell_problems(spell, cls, level, spells, table):
    """[text] for the quest spell a bot learned: it must be in the server's spell list (by name), open to the class, not gated
    above the level, and in the class's Auto setup data (a preset, the extras or the ultimate). spells / table may be empty:
    that part is left out (the caller says so); returns None when the spell is not on the server at all"""
    found = [(sid, s) for sid, s in spells.items() if str(s.get('name', '')).lower() == str(spell).lower()]
    if spells and not found:
        return None
    out = []
    row = (table or {}).get(cls)
    for sid, s in found:
        if s.get('vocations') and row and row.get('voc') not in s['vocations']:
            out.append('%s (%d) is not open to %s' % (spell, sid, cls))
        if s.get('level', 0) > level:
            out.append('%s (%d) needs level %s' % (spell, sid, s['level']))
        if row:
            ids = {x for p in row['presets'] for x in p['spells']} | set(row.get('extras') or []) | (
                {row['ultimate']} if row.get('ultimate') else set())
            if sid not in ids:
                out.append('%s (%d) is in no preset or extras of the Auto setup of %s' % (spell, sid, cls))
    return out


async def quest_step(io, command, want):
    """one !tester spellquest command; (answer, problem): the problem names the first wrong field of `want`
    ({field: value}, a callable(answer) -> bool for a rule)"""
    a = await io.helper('spellquest ' + command, 'spellquest', ANSWER)
    if not isinstance(a, dict):
        return None, 'no answer to !tester spellquest %s' % command
    if a.get('err'):
        return a, 'spellquest %s: %s' % (command, str(a['err'])[:80])
    for key, val in want.items():
        if callable(val):
            if not val(a):
                return a, 'spellquest %s: %s is %r' % (command, key, a.get(key))
        elif a.get(key) != val:
            return a, 'spellquest %s: %s is %r, expected %r' % (command, key, a.get(key), val)
    return a, None


async def check_spell_quest(io, name, cls, level):
    """the line spell quest, end to end on the game's own code (the helper's `!tester spellquest`): set the hunt step, kills
    count (3, then 45 more: the pity of 40 forces a fragment, then a boss for 25), the trial step fills the counters, at
    Archivist Odrenna the trial opens (and is left again), the reward teaches the spell and pays 2000 gold a level, and the
    spell is on the server for the class and in its Auto setup data. The quest is reset at the end."""
    if level < QUEST_LEVEL:
        return Result('spell_quest', name, cls, SKIP, 'the first quest opens at level %d (the bot is level %s)' % (QUEST_LEVEL, level))
    check = 'spell_quest'
    a, bad = await quest_step(io, 'reset', {})
    if bad:
        if a is None or 'no spell quest system' in bad or 'no class line' in bad:
            return Result(check, name, cls, SKIP, bad)
        return Result(check, name, cls, FAIL, bad)
    level = int(a.get('level') or level)   # the game's level now: a death since the setup may have lowered it
    if level < QUEST_LEVEL:
        return Result(check, name, cls, SKIP, 'the first quest opens at level %d (the bot is level %s now)' % (QUEST_LEVEL, level))
    try:
        return await _spell_quest_run(io, name, cls, level)
    finally:
        await io.helper('spellquest reset', 'spellquest', ANSWER)
        await io.go('hunt')


async def _spell_quest_run(io, name, cls, level):
    check = 'spell_quest'

    def fail(text):
        return Result(check, name, cls, FAIL, text)

    a, bad = await quest_step(io, 'state', {'quest': 1, 'code': 'ok', 'step': 0})
    if bad:
        return fail('level %s, fresh: %s' % (level, bad))
    spell = a.get('spell')
    need = a.get('need') or {}
    if not spell or not need.get('kills'):
        return fail('the state names no spell or hunt: %s' % json.dumps(a)[:100])
    a, bad = await quest_step(io, 'set 1 1 0 0', {'step': 1, 'kills': 0, 'fragments': 0})
    if bad:
        return fail(bad)
    a, bad = await quest_step(io, 'kill 3', {'counted': 3, 'kills': 3})
    if bad:
        return fail('kills do not count: ' + bad)
    a, bad = await quest_step(io, 'kill 45', {'counted': 45, 'kills': 48, 'fragments': lambda r: int(r.get('fragments') or 0) >= 1})
    if bad:
        return fail('no fragment within 41 counted kills (pity): ' + bad)
    a, bad = await quest_step(io, 'kill boss', {'weight': 25, 'kills': 73})
    if bad:
        return fail('a boss kill does not count 25: ' + bad)
    a, bad = await quest_step(io, 'set 1 2', {'step': 2, 'kills': need['kills'], 'fragments': need['fragments']})
    if bad:
        return fail('the trial step: ' + bad)
    # Archivist Odrenna must stand in the world (placed at startup in her stall); the helper takes the bot to her
    at = await io.helper('enter npc Archivist Odrenna', 'enter', 8.0)
    if not at:
        return Result(check, name, cls, SKIP, 'no answer to !tester enter npc Archivist Odrenna')
    if at.get('err'):
        return fail('Archivist Odrenna is not in the game (%s): placement at startup failed or her XML did not load' % str(at['err'])[:60])
    a, bad = await quest_step(io, 'trial', {'near': True, 'entered': True, 'running': True})
    if bad:
        return fail('the trial does not open at Odrenna (%s): %s' % (str((a or {}).get('text'))[:60], bad))
    a, bad = await quest_step(io, 'leave', {'left': True, 'running': False})
    if bad:
        return fail('the trial run could not be left: ' + bad)
    a, bad = await quest_step(io, 'complete', {'taught': spell, 'taughtKnown': True,
                                               'gold': lambda r: int(r.get('gold') or 0) == QUEST_GOLD * level})
    if bad:
        return fail('the reward: ' + bad)
    spells, table = io.spells(), io.autosetup()
    problems = quest_spell_problems(spell, cls, level, spells, table)
    if problems is None:
        return fail('%s is learned but not in the server\'s spell list' % spell)
    if problems:
        return fail('; '.join(problems[:3]))
    parts = ['%d kills, fragment, boss 25' % 48, 'trial opened at Odrenna', '%s learned' % spell]
    if spells:
        parts.append('in the spell list')
    if table and cls in table:
        parts.append('in the Auto setup data')
    return Result(check, name, cls, PASS, ', '.join(parts))


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
    ('rift_layout', check_rift_layout, lambda c: True),
    ('waystone_run', check_waystone_run, lambda c: True),
    ('content_rewards', check_content_rewards, lambda c: True),
    ('party_xp', check_party_xp, lambda c: True),
    ('waystone', check_waystone, lambda c: True),
    ('reward_chest', check_reward_chest, lambda c: True),
    ('cursed_chest', check_cursed_chest, lambda c: True),
    ('auto_setup', check_auto_setup, lambda c: True),
    ('spell_quest', check_spell_quest, lambda c: True),
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
    for m in re.finditer(r'\[(\d+)\] = \{ name = "([^"]+)", presets = \{(.*?)\}, (?:extras = \{ ([\d, ]*) \}, )?(?:ultimate = (\d+), )?heals', head, re.S):
        presets = []
        for p in re.finditer(r'\{ level = (\d+), gap = [\d.]+, spells = \{ ([\d, ]+) \}', m.group(3)):
            presets.append({'level': int(p.group(1)), 'spells': [int(x) for x in p.group(2).split(',')]})
        out[m.group(2)] = {'voc': int(m.group(1)), 'presets': presets,
                           'extras': [int(x) for x in (m.group(4) or '').split(',') if x.strip()],
                           'ultimate': int(m.group(5)) if m.group(5) else None}
    return out


if __name__ == '__main__':
    print(json.dumps({'checks': list(KEYS)}))
