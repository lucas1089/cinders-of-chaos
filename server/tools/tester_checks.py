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
import asyncio
import json
import time

PASS, FAIL, SKIP = 'pass', 'fail', 'skip'
STATUSES = (FAIL, PASS, SKIP)

WATCH = 20.0        # seconds a summon is watched for a wrong target
LOOK = 2.0          # seconds between two looks
SETTLE = 3.0        # seconds after a cast, a teleport or a party change before the first look (the server's purge runs at 0.5 s)
ANSWER = 6.0
QUEST_WAIT = 12.0   # one answer of `!tester spellquest`: the quest check sends 25 commands, the first live run of 100 bots lost 4 % of
                    # all helper commands to a busy server (O579), and a quest is no fault of the game for a late answer
CROWD_TRIES = 3     # `enter npc` finds no free tile round the NPC (the other testers crowd her stall): asked again this often
CROWD_WAIT = 4.0    # seconds between the asks
QUEST_LEVEL = 500   # the level of the first line spell quest (spellquest_config.lua quests[1].level)
QUEST_LEVELS = (500, 800, 1200)  # spellquest_config.lua quests[n].level, in order
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
    def __init__(self, check, bot, cls, status, detail='', fallbacks=None):
        self.check, self.bot, self.cls, self.status, self.detail = check, bot, cls, status, detail
        self.fallbacks = list(fallbacks or [])   # helper teleports used in place of walking (O589), counted by the report

    def bug_line(self):
        return 'BUG %s: %s (%s, %s)' % (self.check, self.detail, self.bot, self.cls) if self.status == FAIL else None

    def as_dict(self):
        d = {'check': self.check, 'bot': self.bot, 'class': self.cls, 'status': self.status, 'detail': self.detail}
        if self.fallbacks:
            d['fallbacks'] = list(self.fallbacks)
        return d


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


def not_at_hunt(io):
    """the skip text when io.go('hunt') failed, with the helper's own reason (a spot too high, no answer)"""
    why = getattr(io, 'go_err', None)
    return 'the helper did not bring the bot to its hunt spot' + (' (%s)' % str(why)[:80] if why else '')


async def check_summons(io, name, cls, level):
    """the class's own summon: cast it, watch it, then teleport (the leash and the portal paths) and watch again"""
    words, check, cap = SUMMONERS[cls]
    if not await io.go('hunt'):
        return Result(check, name, cls, SKIP, not_at_hunt(io))
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


PET_REST = {'pz': 'a protection zone', 'zone': 'a zone without pets', 'summons': 'the bot has other summons'}


def pet_rest_text(live):
    """why the helper's !tester pet answer shows no live pet: a rest rule, a cooldown, or none known"""
    if live.get('rest'):
        return 'rests: ' + PET_REST.get(live['rest'], str(live['rest']))
    if int(live.get('deathLeft') or 0) > 0:
        return 'death cooldown %s s' % live['deathLeft']
    if int(live.get('summonLeft') or 0) > 0 and not live.get('live'):
        return 'call cooldown %s s' % live['summonLeft']
    if not live:
        return 'no answer to !tester pet'
    return 'no rule of the game says why'


async def check_pets(io, name, cls, level):
    """call out a pet the character owns, it is a summon of the bot and never targets it; dismiss it"""
    state = await io.request('pets', 'get', {}, ['state'], ANSWER)
    if not state:
        return Result('pets', name, cls, SKIP, 'no answer from the pets window (below its level gate or not installed)')
    data = state.get('data') or {}
    owned = [p.get('species') or p.get('key') for p in data.get('pets') or [] if isinstance(p, dict)]
    owned = [o for o in owned if o]
    if not owned:
        # a pet of the helper (ChaosPets.grant): before, every bot read "owns no pet" and the check never ran
        g = await io.helper('pet', 'pet', ANSWER)
        if g and g.get('owns'):
            state = await io.request('pets', 'get', {}, ['state'], ANSWER) or {}
            owned = [p.get('species') or p.get('key') for p in (state.get('data') or {}).get('pets') or [] if isinstance(p, dict)]
            owned = [o for o in owned if o] or [g.get('key')]
    if not owned:
        return Result('pets', name, cls, SKIP, 'the bot owns no pet')
    if not await io.go('hunt'):
        return Result('pets', name, cls, SKIP, not_at_hunt(io))
    await io.request('pets', 'summon', {'species': owned[0]}, ['state'], ANSWER)
    await io.sleep(SETTLE)
    live = await io.helper('pet', 'pet', ANSWER) or {}
    cid = live.get('cid')
    if not cid:
        why = pet_rest_text(live)
        return Result('pets', name, cls, SKIP, 'the pet did not come out (%s)' % why)
    snap = await io.helper('summons', 'summons', ANSWER)
    if not snap or snap.get('err'):
        return Result('pets', name, cls, SKIP, 'no answer to !tester summons')
    if not any(s.get('id') == cid for s in snap.get('summons') or []):
        await io.request('pets', 'dismiss', {}, ['state'], ANSWER)
        return Result('pets', name, cls, FAIL, 'the pet (creature %s) is out but not a summon of the bot' % cid)
    problems, _ = await watch_summons(io, 10.0)
    await io.request('pets', 'dismiss', {}, ['state'], ANSWER)
    await io.sleep(1.5)
    after = await io.helper('summons', 'summons', ANSWER)
    if problems:
        return Result('pets', name, cls, FAIL, '; '.join(problems[:3]))
    # the pet by its creature id: a Necromancer's minions stay out after the pet's dismiss (before: the first summon by name)
    if after and any(s.get('id') == cid for s in after.get('summons') or []):
        return Result('pets', name, cls, FAIL, 'the pet is still out after dismiss')
    return Result('pets', name, cls, PASS, 'pet %s: out, no wrong target, gone after dismiss' % owned[0])


PARTNER_GONE = 'this bot or its partner died or logged in again during the check (no party to read)'


def partner_kept(io, other):
    """io.partner_kept(other): both bots still in game with the creature ids of the form (True for an io without it)"""
    f = getattr(io, 'partner_kept', None)
    return True if f is None else bool(f(other))


async def check_party(io, name, cls, level):
    """two bots form a party and leave it: the helper sees the size; a bot with a summon keeps its sides in the party"""
    other = await io.partner()
    if not other:
        return Result('party', name, cls, SKIP, 'no free bot in game (none online, or all in another party check)')
    if not await io.party('form', other):
        return Result('party', name, cls, SKIP, 'the invite could not be sent')
    await io.sleep(SETTLE)
    p = await io.helper('party', 'party', ANSWER)
    if not p or p.get('err'):
        await io.party('leave', other)
        return Result('party', name, cls, SKIP, 'no answer to !tester party')
    if int(p.get('size') or 0) < 2:
        await io.party('leave', other)
        if not partner_kept(io, other):
            return Result('party', name, cls, SKIP, PARTNER_GONE)
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
        if not partner_kept(io, other):
            return Result('party', name, cls, SKIP, PARTNER_GONE)
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
    # the rift window answers a query only inside a run (rift.lua ChaosRiftExtended); the run itself is check rift_layout
    if r.get('held') is False and r.get('bagFull'):
        return Result('rift', name, cls, SKIP, 'the bag is full: the tier %s key went to the inbox or the ground (by design)' % r.get('tier'))
    if r.get('held') is False:
        return Result('rift', name, cls, FAIL, 'a rift key of tier %s was given, the backpack holds none' % r.get('tier'))
    if r.get('held') is None:
        return Result('rift', name, cls, SKIP, 'key given; the helper does not read it back (old helper file)')
    return Result('rift', name, cls, PASS, 'a tier %s key reached the backpack' % r.get('tier'))


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
    # off with no problem the helper sees is no failure: the engine also needs an attack or a heal of each member since
    # it joined (Party ticksMap); the helper only sees the fight condition (live run 2026-10-31)
    return out


def party_gone(p, name):
    """True when a `!tester party` answer shows no party of two or more with this bot as the leader"""
    return int(p.get('size') or 0) < 2 or p.get('leader') != name


def party_state(p):
    """the facts behind a party_xp verdict, for the failure text: size, leader, where the leader stood"""
    return 'party of %s, leader %s, leader in a fight outside a protection zone: %s, in a protection zone: %s' % (
        p.get('size', 0), p.get('leader'), bool(p.get('leaderBlocked')), bool(p.get('leaderPz')))


KILL_TOLERANCE = 0.05


def shared_kill_problems(kill, share_of_1000):
    """(skip text or None, [problems]) for the "kill" part of `!tester party kill`: a real kill with the share as the
    leader set it, then a solo kill. Working share: both gain, the leader's gain against the solo kill is what
    Party:onShareExperience pays (share_of_1000 / 1000, within KILL_TOLERANCE). Share off: the partner gains nothing.
    A solo kill never pays the partner."""
    if not kill:
        return 'no answer to !tester party kill (an old helper file, or the bot died)', []
    if kill.get('err'):
        return 'no shared kill: %s' % kill['err'], []
    sh, so = kill.get('shared') or {}, kill.get('solo') or {}
    for k in (sh, so):
        if k.get('err'):
            return 'no shared kill: %s' % k['err'], []
        if not k.get('dead'):
            return 'the %s did not die in the kill (health %s -> %s%s%s)' % (
                kill.get('monster', 'monster'), k.get('hp'), k.get('hpLeft'), ', leader in a protection zone' if k.get('pz')
                else '', ', ' + k['hitErr'] if k.get('hitErr') else ''), []
    if int(so.get('leader') or 0) <= 0:
        return 'the solo kill paid the leader nothing (no experience from this monster here)', []
    out = []
    if int(so.get('partner') or 0) != 0 and not so.get('partnerHit'):
        out.append('a solo kill of the leader paid the partner %s experience' % so['partner'])
    if sh.get('enabled'):
        if int(sh.get('partner') or 0) <= 0:
            out.append('a kill with the share working paid the partner nothing')
        if share_of_1000:
            got = int(sh.get('leader') or 0) / float(so['leader'])
            want = int(share_of_1000) / 1000.0
            if abs(got / want - 1) > KILL_TOLERANCE:
                out.append('the leader got %.0f%% of a solo kill with the share working, Party:onShareExperience pays %.0f%%' % (
                    got * 100, want * 100))
    elif int(sh.get('partner') or 0) > 0 and not sh.get('partnerHit'):
        # a partner that hit the monster earns its damage share without the share (engine rule, no failure)
        out.append('the partner got %s experience from a kill with the share not working' % sh['partner'])
    return None, out


async def check_party_xp(io, name, cls, level):
    """party XP sharing: two bots form a party, the leader (this bot) switches shared experience on (packet 0xA8); the helper
    reads the party: the switch took, what the game's Party:onShareExperience pays for 1000 experience is
    ceil(1000 x (1 + class line bonus) / members), and the engine's verdict agrees with the rules (nobody below two
    thirds of the highest level, within 30 tiles and 1 floor, in a fight): not working while a member fails level or
    range (off with no problem seen is no failure: the engine also needs each member's attack or heal since the join). A
    verdict seen in two looks 3 s apart. Left again at the end."""
    other = await io.partner()
    if not other:
        return Result('party_xp', name, cls, SKIP, 'no free bot in game (none online, or all in another party check)')
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
        # the engine takes the switch in a fight only in a protection zone (Game::playerEnableSharedPartyExperience),
        # and a hunting bot is in one: the leader switches in the temple (live run 2026-11-01: 2 "says it is off")
        await io.go('town')
        await io.party('share', other)
        await io.sleep(SETTLE)
        first = await io.helper('party', 'party', ANSWER)
        if first and not first.get('err') and not first.get('shareActive') and not first.get('leaderBlocked'):
            # one more switch: 1 of 14 leaders read off once with no rule against it (live run 2026-11-01); an engine
            # that never takes it still fails below
            await io.party('share', other)
            await io.sleep(SETTLE)
            first = await io.helper('party', 'party', ANSWER)
        await io.sleep(3.0)
        second = await io.helper('party', 'party', ANSWER)
        if not first or not second or first.get('err') or second.get('err'):
            return Result('party_xp', name, cls, SKIP, 'no answer to !tester party after the switch')
        if not first.get('shareActive') and not second.get('shareActive') and first.get('leaderBlocked'):
            return Result('party_xp', name, cls, SKIP, 'the engine refused the switch: the leader is in a fight outside a '
                                                       'protection zone (the temple teleport did not take)')
        a, b = party_share_problems(first), party_share_problems(second)
        bad = [x for x in a if x in b]    # the engine's own update lags a tick: only what both looks saw
        if bad and not partner_kept(io, other):
            return Result('party_xp', name, cls, SKIP, PARTNER_GONE)
        # O580 (live run 2026-11-15: 1 "the party says it is off" in 68): the engine drops the switch of a leader with no
        # party (Game::playerEnableSharedPartyExperience) and a party that broke up and formed again starts with the
        # switch off. Nobody died or logged in (partner_kept), but a random invite, a join or a leave of either bot, or the
        # hold of PARTY_BUSY running out, can still end the party between the first look and the switch: no party of two
        # with this bot as the leader in a look is no verdict on the shared experience
        if bad and (party_gone(first, name) or party_gone(second, name)):
            return Result('party_xp', name, cls, SKIP, 'the party broke up before the switch could be read (%s)' % party_state(
                second if party_gone(second, name) else first))
        if bad:
            return Result('party_xp', name, cls, FAIL, '; '.join(bad[:3]) + ' (%s)' % party_state(second))
        verdict = 'working' if second.get('shareEnabled') else 'off: %s' % (
            ', '.join('%s %s' % (x.get('name'), x.get('kind')) for x in second.get('problems') or [])[:60] or 'none')
        pays = second.get('shareOf1000')
        # a real kill: the leader back at its hunt (no kill in a protection zone), one kill shared, one solo
        await io.go('hunt')
        k = await io.helper('party kill', 'partykill', ANSWER + 6.0)   # two kills, each read 1.5 s later
        skip, kbad = shared_kill_problems(k, pays)
        if kbad and not partner_kept(io, other):
            return Result('party_xp', name, cls, SKIP, PARTNER_GONE)
        if kbad:
            sh, so = (k or {}).get('shared') or {}, (k or {}).get('solo') or {}
            nums = 'leader/partner xp: shared %s/%s, solo %s/%s%s' % (
                sh.get('leader'), sh.get('partner'), so.get('leader'), so.get('partner'),
                '' if so.get('fromMonster') else ', whole change (old helper file)')
            return Result('party_xp', name, cls, FAIL, '; '.join(kbad[:3]) + ' (' + nums + ')')
        sh, so = (k or {}).get('shared') or {}, (k or {}).get('solo') or {}
        kill = skip or 'kill %s: leader %s / partner %s xp (share %s), solo %s' % (
            'shared' if sh.get('enabled') else 'not shared', sh.get('leader'), sh.get('partner'),
            'working' if sh.get('enabled') else 'off', so.get('leader'))
        return Result('party_xp', name, cls, PASS, 'switch took, 1000 xp pays %s (%s class line(s), %s members), engine %s; %s' % (
            'not read (old helper file)' if pays is None else pays, second.get('lines'), second.get('size'), verdict, kill))
    finally:
        await io.party('unshare', other)
        await io.party('leave', other)
        await io.sleep(1.0)
        await io.go('hunt')


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
    if a.get('band') != a.get('bandExpected') and a.get('readyOfBand') != 0:
        # no ready slot of the band: the pool hands out another band by design (rift.lua RF.findReady)
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
            return Result('content_rewards', name, cls, FAIL, 'rift guardian: %s orb(s) (paid %s), the config guarantees %s (run tier %s, quantity %s)' % (
                rl.get('orbs'), rl.get('paid'), rl.get('minOrbs'), rl.get('runTier'), rl.get('quantity')))
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
    await io.go('hunt')   # the rift and spell quest checks leave the bot in the temple: no chest in a protection zone
    a = await io.helper('chest spawn', 'chest', ANSWER)
    if not a:
        return Result('cursed_chest', name, cls, SKIP, 'no answer to !tester chest')
    if a.get('err'):
        return Result('cursed_chest', name, cls, SKIP, str(a['err'])[:80])
    if a.get('state') != 'idle':
        await io.helper('chest abort', 'chest', ANSWER)
        return Result('cursed_chest', name, cls, FAIL, 'spawned chest is %r, expected idle' % a.get('state'))
    u = await io.helper('chest use', 'chest', ANSWER)
    if u is None:
        # no answer (a busy server, a bot cut off): the chest is taken away again; the system was not looked at
        await io.helper('chest abort', 'chest', ANSWER)
        return Result('cursed_chest', name, cls, SKIP, 'no answer to !tester chest use (the server did not answer in time)')
    await io.sleep(SETTLE)
    s = await io.helper('chest state', 'chest', ANSWER)
    bad = []
    if not u or u.get('state') not in ('running', 'idle'):
        bad.append('after use the chest is %r' % (u or {}).get('state'))
    if s and s.get('state') == 'running' and int(s.get('monsters') or 0) < 1 and int(s.get('horde') or 0) > 0 \
            and int(s.get('made') if s.get('made') is not None else 0) < 1:
        # a horde the bots killed at once is fine: only a horde that made no monster is a failure
        bad.append('horde %s came with no monster' % s.get('horde'))
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


def load_timer_ids(path):
    """the spell ids Auto setup keeps up as buffs (game_helpersupport/supportspells.lua: `[id] = { auto = 'timer'` or, since
    O366, a fight buff of the Support list `[id] = { auto = 'support', fight = true`)"""
    import re
    with open(path, encoding='utf-8') as f:
        return {int(m.group(1)) for m in re.finditer(
            r"\[(\d+)\]\s*=\s*\{\s*auto\s*=\s*(?:'timer'|'support',\s*fight\s*=\s*true)", f.read())}


def quest_spell_problems(spell, cls, level, spells, table, timers=None):
    """[text] for the quest spell a bot learned: it must be in the server's spell list (by name), open to the class, not gated
    above the level, and in the class's Auto setup data (a preset, the extras or the ultimate; a level 800 quest buff: the
    timer buffs of `timers`, load_timer_ids, as Auto setup keeps a buff up and never casts it in a rotation). spells / table may be empty:
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
            if timers is not None and sid in timers:
                continue
            if sid not in ids:
                out.append('%s (%d) is in no preset or extras of the Auto setup of %s%s' % (
                    spell, sid, cls, '' if timers is None else ' and no timer buff of it'))
    return out


class NoAnswer(Exception):
    """the helper did not answer a command in time: the server was busy or the bot was cut off, no fault of the system the
    check looks at (the live run of 2026-11-15 failed 33 of 60 spell quest checks for it)"""


async def quest_answer(io, command, want):
    """quest_step, but a missing answer raises NoAnswer (the check is then a skip, not a bug)"""
    a, bad = await quest_step(io, command, want)
    if a is None:
        raise NoAnswer(bad)
    return a, bad


async def quest_step(io, command, want):
    """one !tester spellquest command; (answer, problem): the problem names the first wrong field of `want`
    ({field: value}, a callable(answer) -> bool for a rule); (None, 'no answer ...') when nothing came in QUEST_WAIT seconds"""
    a = await io.helper('spellquest ' + command, 'spellquest', QUEST_WAIT)
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
        await io.helper('spellquest reset', 'spellquest', QUEST_WAIT)
        await io.go('hunt')


async def _spell_quest_run(io, name, cls, level):
    """every quest the level opens, in order (500, 800, 1200): before, only the first one ran live (O302)"""
    check = 'spell_quest'
    done, fallbacks = [], []
    for n, qlevel in enumerate(QUEST_LEVELS, 1):
        if level < qlevel:
            break
        r = await _one_spell_quest(io, name, cls, level, n)
        if r.status != PASS:
            if done and r.status == SKIP:
                break
            r.fallbacks = fallbacks + r.fallbacks
            return r
        done.append(r.detail)
        fallbacks += r.fallbacks
    later = [lv for lv in QUEST_LEVELS[len(done):]]
    tail = '; quests at level %s not reached (level %s)' % (', '.join(map(str, later)), level) if later else ''
    return Result(check, name, cls, PASS, ' | '.join(done) + tail, fallbacks)


async def _one_spell_quest(io, name, cls, level, n):
    try:
        return await _one_spell_quest_run(io, name, cls, level, n)
    except NoAnswer as e:
        return Result('spell_quest', name, cls, SKIP, 'quest %d: %s (the server did not answer in time: no fault of the quest)' % (n, e))


async def _one_spell_quest_run(io, name, cls, level, n):
    check = 'spell_quest'
    fallbacks = []   # helper teleports used in place of walking (O589)

    def fail(text):
        return Result(check, name, cls, FAIL, 'quest %d: %s' % (n, text), fallbacks)

    a, bad = await quest_answer(io, 'state', {'quest': n, 'code': 'ok', 'step': 0})
    if bad:
        return fail('level %s, %s: %s' % (level, 'fresh' if n == 1 else 'after quest %d' % (n - 1), bad))
    spell = a.get('spell')
    need = a.get('need') or {}
    if not spell or not need.get('kills'):
        return fail('the state names no spell or hunt: %s' % json.dumps(a)[:100])
    a, bad = await quest_answer(io, 'set %d 1 0 0' % n, {'step': 1, 'kills': 0, 'fragments': 0})
    if bad:
        return fail(bad)
    a, bad = await quest_answer(io, 'kill 3', {'counted': 3, 'kills': 3})
    if bad:
        return fail('kills do not count: ' + bad)
    a, bad = await quest_answer(io, 'kill 45', {'counted': 45, 'kills': 48, 'fragments': lambda r: int(r.get('fragments') or 0) >= 1})
    if bad:
        return fail('no fragment within 41 counted kills (pity): ' + bad)
    a, bad = await quest_answer(io, 'kill boss', {'weight': 25, 'kills': 73})
    if bad:
        return fail('a boss kill does not count 25: ' + bad)
    a, bad = await quest_answer(io, 'set %d 2' % n, {'step': 2, 'kills': need['kills'], 'fragments': need['fragments']})
    if bad:
        return fail('the trial step: ' + bad)
    # Archivist Odrenna must stand in the world (placed at startup in her stall); the helper takes the bot to her
    # a person walks to her by the engine path (O589); the helper's teleport only when there is no path, and the result names it
    at = None
    how, got = await walk_by_path(io, {'name': name, 'lead': True}, 'path npc Archivist Odrenna', 'path', 1)
    if how == 'foot':
        at = {'npc': 'Archivist Odrenna', 'walked': True}
    else:
        fallbacks.append(fallback_note('enter npc Archivist Odrenna', (got or {}).get('err') or 'the walk did not arrive'))
        for attempt in range(CROWD_TRIES):
            at = await io.helper('enter npc Archivist Odrenna', 'enter', 8.0)
            if not at or not (at.get('err') and at.get('crowd')):
                break
            await io.sleep(CROWD_WAIT)   # the other testers stand round her stall: they move on
    if not at:
        return Result(check, name, cls, SKIP, 'quest %d: no answer to !tester enter npc Archivist Odrenna' % n, fallbacks)
    if at.get('err') and at.get('crowd'):
        return Result(check, name, cls, SKIP, 'quest %d: no free tile within 4 of Archivist Odrenna after %d tries (the testers crowd '
                      'her stall: no fault of the quest)' % (n, CROWD_TRIES), fallbacks)
    if at.get('err'):
        return fail('Archivist Odrenna is not in the game (%s): placement at startup failed or her XML did not load' % str(at['err'])[:60])
    a, bad = await quest_answer(io, 'trial', {'near': True, 'entered': True, 'running': True})
    if bad:
        return fail('the trial does not open at Odrenna (%s): %s' % (str((a or {}).get('text'))[:60], bad))
    a, bad = await quest_answer(io, 'leave', {'left': True, 'running': False})
    if bad:
        return fail('the trial run could not be left: ' + bad)
    a, bad = await quest_answer(io, 'complete', {'completed': n, 'taught': spell, 'taughtKnown': True,
                                               'gold': lambda r: int(r.get('gold') or 0) == QUEST_GOLD * level})
    if bad:
        return fail('the reward: ' + bad)
    spells, table = io.spells(), io.autosetup()
    timers = io.timers() if hasattr(io, 'timers') else None
    problems = quest_spell_problems(spell, cls, level, spells, table, timers)
    if problems is None:
        return fail('%s is learned but not in the server\'s spell list' % spell)
    if problems:
        return fail('; '.join(problems[:3]))
    parts = ['%d kills, fragment, boss 25' % 48, 'trial opened at Odrenna', '%s learned' % spell]
    if n > 1:
        parts = ['quest %d (level %d): %s learned' % (n, QUEST_LEVELS[n - 1], spell)]
    if spells:
        parts.append('in the spell list')
    if table and cls in table:
        parts.append('in the Auto setup data')
    return Result(check, name, cls, PASS, ', '.join(parts), fallbacks)


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


UNIQUE_TOLERANCE = 0.03


def unique_problems(u):
    """[text] for one `!tester unique` answer: the worn unique's passive is active and the hit after it is worn lost
    the monster `m` times the health of the hit before (within UNIQUE_TOLERANCE)"""
    out = []
    fam = u.get('family')
    if fam not in (u.get('active') or []):
        out.append('a worn %s unique (item %s) leaves its passive asleep (active: %s)' % (
            fam, u.get('id'), ', '.join(u.get('active') or []) or 'none'))
        return out
    m = u.get('m')
    if m is None:
        out.append('a hit with the %s unique worn never reached the passive\'s damage rule' % fam)
        return out
    before, after = int(u.get('lostBefore') or 0), int(u.get('lostAfter') or 0)
    if before > 0:
        got = after / float(before)
        if abs(got / float(m) - 1) > UNIQUE_TOLERANCE:
            out.append('with the %s unique worn a hit took x%.3f of the health, its rule says x%.3f' % (fam, got, m))
    return out


async def check_unique_passive(io, name, cls, level):
    """unique passives (O278): the helper wears a real unique copy of an item whose passive is a plain damage
    multiplier (critrule, opener, lowlife, overflow) for this bot's class line, hits a fresh monster before and after,
    and catches the multiplier the game's own rule returned. The passive must be active and the second hit must take
    that multiple of the first."""
    u = await io.helper('unique', 'unique', ANSWER)
    if not u:
        return Result('unique_passive', name, cls, SKIP, 'no answer to !tester unique (an old helper file, or the bot died)')
    if u.get('err'):
        return Result('unique_passive', name, cls, SKIP, u['err'])
    if not u.get('lostBefore'):
        return Result('unique_passive', name, cls, SKIP, 'the hit before the unique was worn took no health')
    bad = unique_problems(u)
    if bad:
        return Result('unique_passive', name, cls, FAIL, '; '.join(bad))
    return Result('unique_passive', name, cls, PASS, '%s (item %s, %s line): hit %s -> %s, rule x%.3f%s' % (
        u.get('family'), u.get('id'), u.get('line'), u.get('lostBefore'), u.get('lostAfter'), float(u.get('m')),
        ' (critical)' if u.get('crit') else ''))


MONK_LINE = ('Monk', 'Shadowfist', 'Iron Sage')
# the helper watches the fight for 10 s (tester_helper.lua FIST_WATCH_MS) before it answers
FIST_ANSWER = 16.0


def dual_problems(f, kind):
    """[text] for one `!tester fists` / `!tester blades` answer. able (the class may hold both: the Monk line for fist
    weapons, Thief and Ninja for daggers): both are worn (codes 0) and every melee hit of the main hand is followed by
    an off-hand strike. Not able: fists, the fist weapon is refused; blades, the dagger is refused in the shield hand."""
    out = []
    what = 'fist weapon' if kind == 'fists' else 'dagger'
    if not f.get('able'):
        if kind == 'fists' and f.get('left') == 0:
            out.append('a class outside the Monk line could wear a fist weapon')
        if kind == 'blades' and f.get('right') == 0:
            out.append('a class that does not dual wield could hold a dagger in the shield hand')
        return out
    if f.get('left') != 0 or f.get('right') != 0:
        out.append('could not wear a %s in each hand (weapon hand code %s, shield hand code %s)' % (
            what, f.get('left'), f.get('right')))
        return out
    melee, off = int(f.get('melee') or 0), int(f.get('off') or 0)
    if melee == 0:
        return out
    if off == 0:
        out.append('%d melee hits with a %s in each hand and no off-hand strike' % (melee, what))
        return out
    # a hit may bring no strike by rule (O580, live run 2026-11-15: "14 melee hits but 11 off-hand strikes"): the one that
    # landed in the last 150 ms of the watch (the strike follows after delayMs), the strikes the attack rate gate refused
    # (ChaosAttackRate limits offhand / fistOffhand, 1.5 a second a player: the helper counts them) and the hits too small
    # for a strike of at least 1 (the helper counts those too). Anything beyond that is a hit without its strike.
    gated, small = int(f.get('gated') or 0), int(f.get('small') or 0)
    if off < melee - 1 - gated - small or off > melee:
        out.append('%d melee hits but %d off-hand strikes (one each%s)' % (
            melee, off, '; %d refused by the attack rate gate, %d hits too small' % (gated, small) if gated or small
            else ''))
    return out


async def check_dual(io, name, cls, level, kind):
    check = 'dual_fists' if kind == 'fists' else 'dual_blades'
    f = await io.helper(kind, kind, FIST_ANSWER)
    if not f:
        return Result(check, name, cls, SKIP, 'no answer to !tester %s (an old helper file, or the bot died)' % kind)
    if f.get('err'):
        return Result(check, name, cls, SKIP, f['err'])
    bad = dual_problems(f, kind)
    if bad:
        return Result(check, name, cls, FAIL, '; '.join(bad))
    if not f.get('able'):
        if kind == 'fists':
            return Result(check, name, cls, PASS, 'a fist weapon is refused outside the Monk line (code %s)' % f.get('left'))
        return Result(check, name, cls, PASS, 'a dagger is refused in the shield hand (code %s)' % f.get('right'))
    if not int(f.get('melee') or 0):
        return Result(check, name, cls, SKIP, 'both worn, but no melee hit landed in the watch')
    # offSum: the strikes as the script deals them (before armour); the share itself is covered by the unit tests
    return Result(check, name, cls, PASS, 'both worn; %s melee hits, %s off-hand strikes (%s damage)' % (
        f.get('melee'), f.get('off'), f.get('offSum')))


async def check_dual_fists(io, name, cls, level):
    """fist weapons in either hand (engine patch 0087, O360): a Monk-line bot puts a fist weapon in each hand through the
    engine's slot rule and hits a Demon; every fist hit must bring an off-hand strike. Another class must be refused."""
    return await check_dual(io, name, cls, level, 'fists')


async def check_dual_blades(io, name, cls, level):
    """the Thief and Ninja dual wield (src-patch 0002, thief_combat.lua; owner 2026-11-01 "faça os mesmos testes com o
    thief"): a dagger in each hand, every melee hit of the main hand brings an off-hand strike. Every other class, the
    Samurai too, must be refused the dagger in the shield hand."""
    return await check_dual(io, name, cls, level, 'blades')


# ------------------------------------------------------------------------------------------------ crafting and upgrades (O584 item 3)
# The bots held no orb, gem, rune, charm or card, so the crafting window got ANS at best and no modifier change was ever seen.
# The helper's `!tester give` puts one of each into the backpack (a plain kit weapon with no rarity for the orbs); the checks use
# them the way a player does (the crafting window's requests, the use-with packet) and read the item's modifiers from its TOOLTIP
# before and after, next to the bench's own view of the item: the two must agree, and the change must be the one the orb promises.
RARITY_RANK = {0: 0, 1: 1, 2: 2, 3: 3, 4: 4, 5: 5, 10: 6}
BACKPACK_POS = 0x40  # the y of a position inside container 0 (the backpack the check opened)


class Held:
    """where the things the helper gave sit in the backpack: a new stack goes in front and moves the others one slot back
    (Container:addItem). The answer of a give names the slot at that moment; the index here follows the later ones"""

    def __init__(self):
        self.items = {}   # name -> {'index', 'id', 'clientId', 'path', 'bagClientId', ...}

    def add(self, name, ans):
        merged = any(i['id'] == ans.get('id') and i['index'] == 0 for i in self.items.values())  # into a stack that was in front
        if int(ans.get('index', 0)) == 0 and not merged:
            for it in self.items.values():
                it['index'] += 1
        item = dict(ans)
        self.items[name] = item
        return item

    def __getitem__(self, name):
        return self.items[name]


def rarity_rank(r):
    return RARITY_RANK.get(int(r or 0), int(r or 0))


def item_view(tip, state_item):
    """what a check compares: the rarity and modifier keys of the tooltip (tip.rarity, tip.mods[].k), the bench's own view of
    the same item (state item: mods[].key, quality, sockets.count and list)"""
    tip = tip if isinstance(tip, dict) else {}
    st = state_item if isinstance(state_item, dict) else {}
    socks = st.get('sockets') if isinstance(st.get('sockets'), dict) else {}
    return {
        'rarity': int(tip.get('rarity') if tip.get('rarity') is not None else st.get('rarity') or 0),
        'mods': [str(m.get('k')) for m in (tip.get('mods') or []) if isinstance(m, dict)],
        'bench_mods': [str(m.get('key') or m.get('group')) for m in (st.get('mods') or []) if isinstance(m, dict)],
        'quality': int(st.get('quality') or 0),
        'sockets': int(socks.get('count') or 0),
        'sockets_max': int(socks.get('max') or 0),
        'socketed': sum(1 for g in (socks.get('list') or []) if not isinstance(g, dict) or g.get('id')),   # O660: the list names every socket: an empty one has no gem id
        'tip': json.dumps(tip, sort_keys=True),
    }


def orb_problems(orb, b, a):
    """[text] for one orb applied to an item: the effect the orb's text promises, read from the views before and after, and
    the agreement of the tooltip with the bench"""
    out = []
    nb, na = len(b['mods']), len(a['mods'])
    if orb == 'transmutation':
        if a['rarity'] not in (1, 2) or na < 1:
            out.append('a normal item became rarity %s with %d modifiers, expected Common or Uncommon with at least 1' % (a['rarity'], na))
    elif orb == 'alchemy':
        if a['rarity'] not in (3, 4, 5) or na < 1:
            out.append('a normal item became rarity %s with %d modifiers, expected Magic, Rare or Legendary with modifiers' % (a['rarity'], na))
    elif orb == 'exalted':
        if na != nb + 1 or a['rarity'] != b['rarity']:
            out.append('modifiers %d -> %d, rarity %s -> %s: expected one more and the same rarity' % (nb, na, b['rarity'], a['rarity']))
    elif orb == 'annulment':
        if na != nb - 1:
            out.append('modifiers %d -> %d: expected one less' % (nb, na))
    elif orb == 'scouring':
        if a['rarity'] != 0 or na != 0:
            out.append('rarity %s with %d modifiers after the Orb of Erasure: expected a normal item' % (a['rarity'], na))
    elif orb == 'chaos':
        if a['rarity'] != b['rarity'] or na != nb:
            out.append('rarity %s -> %s, modifiers %d -> %d: a reroll keeps both' % (b['rarity'], a['rarity'], nb, na))
    elif orb == 'divine':
        if rarity_rank(a['rarity']) <= rarity_rank(b['rarity']) or na < 1:
            out.append('rarity %s -> %s with %d modifiers: expected one step up' % (b['rarity'], a['rarity'], na))
    elif orb == 'whetstone':
        if a['quality'] != b['quality'] + 1:
            out.append('quality %d -> %d: expected +1' % (b['quality'], a['quality']))
    elif orb == 'sockets':
        if a['sockets'] > a['sockets_max'] or a['sockets'] < 0:
            out.append('%d sockets of a maximum of %d' % (a['sockets'], a['sockets_max']))
    if a['mods'] and a['bench_mods'] and len(a['mods']) != len(a['bench_mods']):
        out.append('the tooltip lists %d modifiers, the bench %d' % (len(a['mods']), len(a['bench_mods'])))
    return out


class Bench:
    """the crafting window and the tooltip, as a check uses them"""

    def __init__(self, io, name, cls, check):
        self.io, self.name, self.cls, self.check = io, name, cls, check
        self.held = Held()
        self.counts = {}

    def skip(self, why):
        return Result(self.check, self.name, self.cls, SKIP, why)

    def fail(self, why):
        return Result(self.check, self.name, self.cls, FAIL, why)

    async def give(self, name, what):
        """`!tester give <what>`; the helper's answer, or None with self.err set"""
        ans = await self.io.helper('give ' + what, 'give', ANSWER)
        self.err = None
        if not isinstance(ans, dict) or ans.get('err'):
            self.err = (ans or {}).get('err') if isinstance(ans, dict) else 'no answer to !tester give'
            return None
        return self.held.add(name, ans)

    async def tooltip(self, item):
        ans = await self.io.request('itemTooltip', 'get', {'items': [{'pos': {'x': 0xFFFF, 'y': BACKPACK_POS, 'z': item['index']},
                                                                      'cid': item['clientId']}]}, ('tips',), ANSWER)
        rows = ((ans or {}).get('data') or {}).get('items') or []
        return rows[0].get('tip') if rows and isinstance(rows[0], dict) else None

    async def select(self, item):
        ans = await self.io.request('crafting', 'select', {'path': str(item['index']), 'id': item['id']}, ('state',), ANSWER)
        data = (ans or {}).get('data') or {}
        if isinstance(data.get('counts'), dict):
            self.counts = data['counts']
        return data.get('item') if isinstance(data.get('item'), dict) else None

    async def view(self, item):
        """(view, the bench's item) or (None, None) when the tooltip or the bench did not answer"""
        st = await self.select(item)
        tip = await self.tooltip(item)
        if st is None or tip is None:
            return None, st
        return item_view(tip, st), st

    async def apply(self, orb, item, st):
        """the orb on the item; the result message or None"""
        ans = await self.io.request('crafting', 'apply', {'orb': orb, 'path': str(item['index']), 'id': item['id'],
                                                         'sig': (st or {}).get('sig')}, ('result',), ANSWER)
        await self.io.sleep(0.5)
        return (ans or {}).get('data') if isinstance(ans, dict) else None


async def bench_with_item(io, name, cls, check, orbs):
    """a Bench with the orbs given first and a plain item last (so it sits in slot 0), the backpack open as container 0;
    (bench, item) or (None, a SKIP Result)"""
    bench = Bench(io, name, cls, check)
    if not await io.go('town'):   # O660: the bench is a window: no need to stand in a hunt of a bot with no gear
        return None, bench.skip(not_at_hunt(io))
    for orb, n in orbs:
        if not await bench.give('orb:' + orb, 'orb %s %d' % (orb, n)):
            return None, bench.skip('no %s orb from the helper (%s)' % (orb, bench.err))
    item = await bench.give('item', 'item')
    if not item:
        return None, bench.skip('no plain item from the helper (%s)' % bench.err)
    await io.open_bag(item.get('bagClientId'))
    await io.sleep(1.0)
    return bench, item


async def orb_chain(io, name, cls, check, steps, start_rarity_zero=True):
    """apply each orb of steps in order on one plain item and check what it did; steps = [(orb key, label)]"""
    bench, item = await bench_with_item(io, name, cls, check, [(o, 1) for o, _ in steps])
    if bench is None:
        return item
    before, st = await bench.view(item)
    if before is None:
        return bench.skip('no tooltip or bench answer for the given item')
    if start_rarity_zero and (before['rarity'] != 0 or before['mods']):
        return bench.skip('the given item is not a normal one (rarity %s, %d modifiers)' % (before['rarity'], len(before['mods'])))
    done, notes = [], []
    for orb, label in steps:
        res = await bench.apply(orb, item, st)
        if res is None:
            return bench.skip('no answer to the %s' % label)
        if not res.get('ok'):
            notes.append('%s refused: %s' % (label, str(res.get('text'))[:50]))
            continue
        after, st2 = await bench.view(item)
        if after is None:
            return bench.skip('no tooltip or bench answer after the %s' % label)
        problems = orb_problems(orb, before, after)
        if orb != 'sockets' and after['tip'] == before['tip']:
            problems.append('the tooltip did not change')
        if upheaval_count_only(orb, before, after, problems):   # O660: a rule the owner decides, said in the text; the chain goes on
            notes.append(upheaval_note(before, after))
            problems = [p for p in problems if 'a reroll keeps both' not in p]
        if problems:
            return bench.fail('%s: %s' % (label, '; '.join(problems[:3])))
        done.append(label)
        before, st = after, st2
    if not done:
        return bench.skip('every orb was refused (%s)' % '; '.join(notes[:2]))
    return Result(check, name, cls, PASS, '%s changed the item as promised, tooltip and bench agree%s' % (
        ', '.join(done), ' (%s)' % '; '.join(notes[:2]) if notes else ''))


async def check_craft_orbs(io, name, cls, level):
    """Awakening, Grafting, Upheaval, Unmaking, Fate, Erasure, Gilding on one plain item"""
    steps = [('transmutation', 'Orb of Awakening'), ('exalted', 'Orb of Grafting'), ('chaos', 'Orb of Upheaval'),
             ('annulment', 'Orb of Unmaking'), ('divine', 'Orb of Fate'), ('scouring', 'Orb of Erasure'),
             ('alchemy', 'Orb of Gilding')]
    return await orb_chain(io, name, cls, 'craft_orbs', steps)


async def check_craft_whetstone(io, name, cls, level):
    """a rarity from Gilding, then the Whetstone: +1 quality, and the tooltip shows it"""
    return await orb_chain(io, name, cls, 'craft_whetstone', [('alchemy', 'Orb of Gilding'), ('whetstone', 'Whetstone')])


async def check_craft_sockets(io, name, cls, level):
    """the Orb of Sockets rolls sockets for a plain piece (never more than its maximum); up to five tries"""
    bench, item = await bench_with_item(io, name, cls, 'craft_sockets', [('sockets', 5)])
    if bench is None:
        return item
    before, st = await bench.view(item)
    if before is None:
        return bench.skip('no tooltip or bench answer for the given item')
    if before['sockets_max'] < 1:
        return bench.skip('this item cannot have sockets (maximum %d)' % before['sockets_max'])
    for n in range(1, 6):
        res = await bench.apply('sockets', item, st)
        if res is None:
            return bench.skip('no answer to the Orb of Sockets')
        if not res.get('ok'):
            return bench.skip('the Orb of Sockets was refused: %s' % str(res.get('text'))[:60])
        after, st = await bench.view(item)
        if after is None:
            return bench.skip('no tooltip or bench answer after the Orb of Sockets')
        problems = orb_problems('sockets', before, after)
        if problems:
            return bench.fail('; '.join(problems))
        if after['sockets'] >= 1:
            return Result('craft_sockets', name, cls, PASS, '%d socket(s) of %d after %d orb(s)' % (
                after['sockets'], after['sockets_max'], n))
        before = after
    return bench.fail('five Orbs of Sockets and no socket on an item that may have %d' % before['sockets_max'])


async def check_craft_gems(io, name, cls, level):
    """sockets, a gem, the use-with packet: the gem sits in the socket (the bench's list), the tooltip changed"""
    bench, item = await bench_with_item(io, name, cls, 'craft_gems', [('sockets', 5)])
    if bench is None:
        return item
    # the gem goes in after the sockets orbs and the item: it sits in front, the item one slot back
    gem = await bench.give('gem', 'gem')
    if not gem:
        return bench.skip('no gem from the helper (%s)' % bench.err)
    item = bench.held['item']
    await io.open_bag(item.get('bagClientId'))
    before, st = await bench.view(item)
    if before is None:
        return bench.skip('no tooltip or bench answer for the given item')
    for _ in range(5):
        if before['sockets'] >= 1:
            break
        res = await bench.apply('sockets', item, st)
        if not res or not res.get('ok'):
            return bench.skip('no socket: %s' % (str((res or {}).get('text'))[:60] if res else 'no answer to the Orb of Sockets'))
        before, st = await bench.view(item)
        if before is None:
            return bench.skip('no tooltip or bench answer after the Orb of Sockets')
    if before['sockets'] < 1:
        return bench.fail('five Orbs of Sockets and no socket')
    await io.use_with(gem['index'], gem['clientId'], item['index'], item['clientId'])
    await io.sleep(1.5)
    item = slot_after_use(gem, item, gem.get('count'))   # O660: a gem used up leaves its slot: the item behind it moves one slot forward
    after, st2 = await bench.view(item)
    if after is None:
        return bench.skip('no tooltip or bench answer after the gem')
    if after['socketed'] != before['socketed'] + 1:
        return bench.fail('gems in the sockets %d -> %d after the use-with: expected one more (item slot %s, gem slot %s; before %s, after %s)' % (
            before['socketed'], after['socketed'], item.get('index'), gem.get('index'), sock_names(st), sock_names(st2)))   # O660: what the bench listed
    if after['tip'] == before['tip']:
        return bench.fail('the gem sits in the socket but the tooltip did not change')
    return Result('craft_gems', name, cls, PASS, 'a gem socketed by use-with (%d of %d sockets), the tooltip shows it' % (
        after['socketed'], after['sockets']))


async def check_craft_supports(io, name, cls, level):
    """a support rune into a spell of the class through the support window: the spell lists it afterwards"""
    bench = Bench(io, name, cls, 'craft_supports')
    if not await io.go('town'):   # O660: a window: no hunt for a bot with no gear
        return bench.skip(not_at_hunt(io))
    ans = await io.request('supports', 'open', {}, ('state',), ANSWER)
    spells = [s for s in (((ans or {}).get('data') or {}).get('spells') or []) if isinstance(s, dict)]
    if not spells:
        return bench.skip('no state or no spell in the support window')
    free = [s for s in spells if spell_has_room(s)]
    if not free:
        return bench.skip('every spell has its sockets full')
    rune = await bench.give('rune', 'rune')
    if not rune:
        return bench.skip('no rune from the helper (%s)' % bench.err)
    spell, res, data, tried = None, None, {}, 0
    for cand in free[:SUPPORT_TRIES]:   # O660: a rune fits some spells only (single target, area ...): the bot tries the next spell, as a person does
        tried += 1
        res = await io.request('supports', 'socket', {'spell': cand['id'], 'rune': rune['id']}, ('result',), ANSWER)
        data = (res or {}).get('data') or {}
        if res is None or data.get('ok') or 'does not fit' not in str(data.get('text')):
            spell = cand
            break
        await io.sleep(SUPPORT_GAP)
    else:
        return bench.skip('the rune fits none of the %d spell(s) tried: %s' % (tried, str(data.get('text'))[:60]))
    if res is None:
        return bench.skip('no answer to the rune')
    if not data.get('ok'):
        return bench.skip('the rune was refused: %s' % str(data.get('text'))[:60])
    ans = await io.request('supports', 'open', {}, ('state',), ANSWER)
    now = next((s for s in (((ans or {}).get('data') or {}).get('spells') or []) if isinstance(s, dict) and s.get('id') == spell['id']), None)
    if now is None:
        return bench.skip('no state after the rune')
    if spell_runes(now) != spell_runes(spell) + 1:   # O660: `count` is the sockets the spell has open, `runes` the runes inside
        return bench.fail('spell %s holds %s runes after the socket, expected %d' % (
            spell.get('name') or spell['id'], spell_runes(now), spell_runes(spell) + 1))
    return Result('craft_supports', name, cls, PASS, 'a rune socketed into %s: %s runes now' % (spell.get('name') or spell['id'], spell_runes(now)))


async def check_craft_charms(io, name, cls, level):
    """a charm into the grid and out again: the bag, the grid and the totals move one by one"""
    bench = Bench(io, name, cls, 'craft_charms')
    if not await io.go('town'):   # O660: a window: no hunt for a bot with no gear
        return bench.skip(not_at_hunt(io))
    charm = await bench.give('charm', 'charm')
    if not charm:
        return bench.skip('no charm from the helper (%s)' % bench.err)
    ans = await io.request('charms', 'open', {}, ('state',), ANSWER)
    st = (ans or {}).get('data') or {}
    if not st:
        return bench.skip('no state in the charm window')
    bag, cells = st.get('bag') or [], [c for c in (st.get('cells') or []) if c.get('open')]
    if not bag:
        return bench.skip('the given charm is not in the charm bag list')
    if not cells:
        return bench.skip('no open cell in the grid')
    b0 = bag[0]
    placed_before = len(st.get('placed') or [])
    for cell in cells:
        res = await io.request('charms', 'place', {'ref': b0.get('ref'), 'sid': b0.get('sid'), 'iid': b0.get('iid'),
                                                   'x': cell['x'], 'y': cell['y']}, ('result',), ANSWER)
        data = (res or {}).get('data') or {}
        if res is None:
            return bench.skip('no answer to the charm')
        if data.get('ok'):
            break
    else:
        return bench.skip('no cell took the charm: %s' % str(data.get('text'))[:60])
    ans = await io.request('charms', 'open', {}, ('state',), ANSWER)
    st2 = (ans or {}).get('data') or {}
    if len(st2.get('placed') or []) != placed_before + 1 or len(st2.get('bag') or []) != len(bag) - 1:
        return bench.fail('placed %d -> %d, bag %d -> %d after the charm was placed: expected one more and one less' % (
            placed_before, len(st2.get('placed') or []), len(bag), len(st2.get('bag') or [])))
    mine = (st2.get('placed') or [])[-1]
    res = await io.request('charms', 'take', {'id': mine.get('id')}, ('result',), ANSWER)
    if res is None or not ((res.get('data') or {}).get('ok')):
        return bench.fail('the charm could not be taken out again: %s' % str(((res or {}).get('data') or {}).get('text'))[:60])
    ans = await io.request('charms', 'open', {}, ('state',), ANSWER)
    st3 = (ans or {}).get('data') or {}
    if len(st3.get('placed') or []) != placed_before or len(st3.get('bag') or []) != len(bag):
        return bench.fail('after taking it out the grid holds %d and the bag %d, expected %d and %d' % (
            len(st3.get('placed') or []), len(st3.get('bag') or []), placed_before, len(bag)))
    return Result('craft_charms', name, cls, PASS, 'a charm placed (grid %d -> %d, bag %d -> %d) and taken out again' % (
        placed_before, placed_before + 1, len(bag), len(bag) - 1))


async def check_craft_cards(io, name, cls, level):
    """a card in the backpack: its tooltip names it and carries its description (what it gives, the set, how to use it)"""
    bench = Bench(io, name, cls, 'craft_cards')
    if not await io.go('hunt'):
        return bench.skip(not_at_hunt(io))
    card = await bench.give('card', 'card')
    if not card:
        return bench.skip('no card from the helper (%s)' % bench.err)
    await io.open_bag(card.get('bagClientId'))
    await io.sleep(1.0)
    tip = await bench.tooltip(card)
    if tip is None:
        return bench.skip('no tooltip answer for the card')
    if not tip.get('name'):
        return bench.fail('the card tooltip has no name')
    if not str(tip.get('desc') or '').strip():
        return bench.fail('the tooltip of the card %s has no description' % tip.get('name'))
    return Result('craft_cards', name, cls, PASS, 'the tooltip of %s carries its description' % tip.get('name'))

# ------------------------------------------------------------------------------------------------ closed test mode (O582)
# testers.py run --closed (switch: chaos-ctl.sh testers closed on): arena, battleground, the Marches, guild and guild war, market,
# the bazaar lock and the raid (O588, below) among the bots only. Extra io (testers.py CheckIO): io.closed_plan() -> {'guild', 'leader', 'rival',
# 'rival_leader'} of this bot or None; async io.helper_of / request_of / go_of(other, ...) the same as io.helper / request / go for
# another bot; io.online(name) -> the name when that bot is in game; io.sql(statements) the closed-mode rows of the bazaar check.
CLOSED_SYSTEMS = ('arena', 'battleground', 'bazaar', 'dungeon', 'groupqueue', 'guild', 'guildboss', 'guildwar', 'market', 'partyfinder', 'pvp', 'raid',
                  'siege')  # testers_core.lua K.CLOSED_SYSTEMS
ARENA_WAIT = 40.0   # seconds two queued testers wait for their match
FEE_GOLD = 100      # the gold price of the market check's offer


def closed_problems(c):
    """[text] for one `!tester closed` answer: whatever says a tester could meet a player, or the mode is not what the run needs"""
    if not isinstance(c, dict):
        return ['no answer']
    out = []
    if not c.get('loaded'):
        return ['the server has no testers_core.lua rules']
    if not c.get('on'):
        out.append('the switch reads off while the bots run in closed mode (data/chaos_testers_closed)')
    guards = c.get('guards') or {}
    for system in CLOSED_SYSTEMS:
        g = guards.get(system)
        if not isinstance(g, dict):
            out.append('%s: no guard reported (an old rules file)' % system)
            continue
        if not g.get('mixed'):
            out.append('%s: the rules let a tester meet a player' % system)
        if not g.get('off'):
            out.append('%s: testers are matched with the mode off' % system)
        if not g.get('together'):
            out.append('%s: testers are refused with the mode on' % system)
    guild = c.get('guild')
    if isinstance(guild, dict) and guild.get('side') != 'tester':
        out.append('guild %s is not a tester guild (side %s)' % (guild.get('name'), guild.get('side')))
    return out


async def check_closed_guards(io, name, cls, level):
    """the rules the server runs: a tester against a player is refused in every closed system, the mode off refuses testers"""
    c = await io.helper('closed', 'closed', ANSWER)
    if not c or c.get('err'):
        return Result('closed_guards', name, cls, SKIP, 'no answer to !tester closed (old helper file)')
    problems = closed_problems(c)
    if problems:
        return Result('closed_guards', name, cls, FAIL, '; '.join(problems[:4]))
    return Result('closed_guards', name, cls, PASS, 'every closed system refuses a tester against a player; guild %s' % (
        (c.get('guild') or {}).get('name') or 'none'))


async def check_closed_arena(io, name, cls, level):
    """two testers queue for a 1v1 in the arena and are matched with each other"""
    other = await io.partner()
    if not other:
        return Result('closed_arena', name, cls, SKIP, 'no free bot in game')
    if not await io.go('town') or not await io.go_of(other, 'town'):
        return Result('closed_arena', name, cls, SKIP, 'the helper did not bring both bots to the temple')
    await io.sleep(SETTLE)
    a = await io.request('arena', 'queue', {'mode': '1v1'}, ['state'], ANSWER)
    b = await io.request_of(other, 'arena', 'queue', {'mode': '1v1'}, ['state'], ANSWER)
    if a is None or b is None:
        return Result('closed_arena', name, cls, SKIP, 'no answer from the arena window (not installed)')
    waited = 0.0
    while waited <= ARENA_WAIT and io.alive():
        ca = await io.helper('closed', 'closed', ANSWER)
        cb = await io.helper_of(other, 'closed', 'closed', ANSWER)
        sa, sb = (ca or {}).get('arena') or {}, (cb or {}).get('arena') or {}
        if sa.get('inMatch') and sb.get('inMatch'):
            return Result('closed_arena', name, cls, PASS, 'matched with %s, both inside' % other)
        if waited >= 6 and not (sa.get('queued') or sa.get('inMatch')) and not (sb.get('queued') or sb.get('inMatch')):
            return Result('closed_arena', name, cls, SKIP, 'neither bot is in the queue after the request (level, zone or cooldown)')
        await io.sleep(LOOK * 2)
        waited += LOOK * 2
    await io.request('arena', 'leave', {}, ['state'], ANSWER)
    await io.request_of(other, 'arena', 'leave', {}, ['state'], ANSWER)
    return Result('closed_arena', name, cls, FAIL, 'two queued testers were not matched in %d seconds' % int(ARENA_WAIT))


async def check_closed_battleground(io, name, cls, level):
    """a tester queues for the battleground (its own realm) and leaves the queue; the match needs the whole roster"""
    await io.go('town')
    await io.sleep(SETTLE)
    q = await io.request('battleground', 'queue', {}, ['state'], ANSWER)
    if q is None:
        return Result('closed_battleground', name, cls, SKIP, 'no answer from the battleground window (not installed)')
    await io.sleep(SETTLE)
    c = await io.helper('closed', 'closed', ANSWER)
    queued = bool(((c or {}).get('battleground') or {}).get('queued'))
    inside = bool(((c or {}).get('battleground') or {}).get('inMatch'))
    await io.request('battleground', 'leave', {}, ['state'], ANSWER)
    if not queued and not inside:
        return Result('closed_battleground', name, cls, SKIP, 'the queue refused the bot (level, zone, deserter)')
    return Result('closed_battleground', name, cls, PASS, 'queued among testers, then left (a match needs a full roster)')


async def check_closed_pvp(io, name, cls, level):
    """a tester enters the Marches: its own instance, never a player's"""
    await io.go('town')
    await io.sleep(SETTLE)
    r = await io.request('pvpZone', 'enter', {'accept': True}, ['*'], ANSWER)
    if r is None:
        return Result('closed_pvp', name, cls, SKIP, 'no answer from the Marches window (not installed)')
    await io.sleep(SETTLE)
    c = await io.helper('closed', 'closed', ANSWER)
    inside = bool(((c or {}).get('pvp') or {}).get('inside'))
    if not inside:
        return Result('closed_pvp', name, cls, SKIP, 'the Marches refused the bot: %s' % str(((r or {}).get('data') or {}).get('text', ''))[:80])
    return Result('closed_pvp', name, cls, PASS, 'inside the testers\' own Marches instance')


async def check_closed_guild(io, name, cls, level):
    """the leader of a tester guild declares a war on the other tester guild, its leader accepts, the war is active, the
    declarer surrenders"""
    plan = io.closed_plan()
    if not plan:
        return Result('closed_guild_war', name, cls, SKIP, 'this bot has no tester guild (too few bots for two guilds)')
    if not plan.get('leader'):
        return Result('closed_guild_war', name, cls, SKIP, 'not the leader of its guild')
    rival = io.online(plan.get('rival_leader'))
    if not rival:
        return Result('closed_guild_war', name, cls, SKIP, 'the leader of %s is not in game' % plan.get('rival'))
    c = await io.helper('closed', 'closed', ANSWER)
    g = (c or {}).get('guild') or {}
    if g.get('name') != plan.get('guild') or g.get('side') != 'tester':
        return Result('closed_guild_war', name, cls, FAIL, 'the bot has guild %s (side %s), expected %s as a tester guild' % (
            g.get('name'), g.get('side'), plan.get('guild')))
    d = await io.request('guildWar', 'declare', {'target': plan['rival'], 'fragLimit': 10, 'hours': 6, 'stake': 0}, ['message'], ANSWER)
    if d is None:
        return Result('closed_guild_war', name, cls, SKIP, 'no answer from the guild war window (not installed)')
    data = d.get('data') or {}
    if not data.get('ok'):
        return Result('closed_guild_war', name, cls, SKIP, 'declare refused: %s' % str(data.get('text', ''))[:90])
    await io.sleep(SETTLE)
    state = await io.request_of(rival, 'guildWar', 'refresh', {'tab': 'wars'}, ['state'], ANSWER)
    pending = (((state or {}).get('data') or {}).get('wars') or {}).get('pending') or []
    offer = next((w for w in pending if w.get('id')), None)
    if not offer:
        return Result('closed_guild_war', name, cls, FAIL, 'the other tester guild sees no war offer')
    acc = await io.request_of(rival, 'guildWar', 'accept', {'id': offer['id']}, ['message'], ANSWER)
    if acc is None or not (acc.get('data') or {}).get('ok'):
        return Result('closed_guild_war', name, cls, FAIL, 'accept refused: %s' % str(((acc or {}).get('data') or {}).get('text', ''))[:90])
    await io.sleep(SETTLE)
    mine = await io.request('guildWar', 'refresh', {'tab': 'wars'}, ['state'], ANSWER)
    active = (((mine or {}).get('data') or {}).get('wars') or {}).get('active') or []
    await io.request('guildWar', 'surrender', {'id': offer['id']}, ['message'], ANSWER)
    if not any(w.get('id') == offer['id'] for w in active):
        return Result('closed_guild_war', name, cls, FAIL, 'the accepted war %s is not active' % offer['id'])
    return Result('closed_guild_war', name, cls, PASS, 'war %s between %s and %s: declared, accepted, active, surrendered' % (
        offer['id'], plan.get('guild'), plan.get('rival')))


async def check_closed_market(io, name, cls, level):
    """a tester lists an item for gold, another tester sees it in the tester book and buys it"""
    other = await io.partner()
    if not other:
        return Result('closed_market', name, cls, SKIP, 'no free bot in game')
    s = await io.request('market', 'sellable', {}, ['sellable'], ANSWER)
    if s is None:
        return Result('closed_market', name, cls, SKIP, 'no answer from the market (not installed)')
    items = [i for i in ((s.get('data') or {}).get('items') or []) if i.get('ref') and not i.get('why')]
    if not items:
        return Result('closed_market', name, cls, SKIP, 'nothing sellable in the backpack')
    item = items[0]
    r = await io.request('market', 'list', {'ref': item['ref'], 'count': 1, 'gold': FEE_GOLD, 'coins': 0, 'days': 1}, ['done', 'error'], ANSWER)
    if r is None or r.get('action') == 'error' or (r.get('data') or {}).get('what') != 'list':
        return Result('closed_market', name, cls, SKIP, 'the offer was not listed: %s' % str(((r or {}).get('data') or {}).get('text', ''))[:90])
    offer_id = (r.get('data') or {}).get('id')
    page = await io.request_of(other, 'market', 'browse', {}, ['page'], ANSWER)
    rows = ((page or {}).get('data') or {}).get('rows') or []
    seen = any(row.get('id') == offer_id for row in rows)
    b = await io.request_of(other, 'market', 'buy', {'id': offer_id, 'cur': 'gold'}, ['done', 'error'], ANSWER)
    bought = b is not None and b.get('action') != 'error' and (b.get('data') or {}).get('what') == 'buy'
    if not bought:
        await io.request('market', 'cancel', {'id': offer_id}, ['done', 'error'], ANSWER)
        return Result('closed_market', name, cls, FAIL, 'offer %s: %s could not buy it (%s); seen in browse: %s' % (
            offer_id, other, str(((b or {}).get('data') or {}).get('text', ''))[:70], seen))
    return Result('closed_market', name, cls, PASS, 'offer %s listed for %d gold, bought by %s%s' % (
        offer_id, FEE_GOLD, other, '' if seen else ' (not in its first browse page)'))


def bazaar_problem(before, during, after):
    """the three `!tester closed` bazaar facts (locked before listing, while listed, after release) -> text or None"""
    if before:
        return 'locked before it was listed'
    if not during:
        return 'a listed tester is not locked: it could log in during its own sale'
    if after:
        return 'still locked after the listing was cancelled'
    return None


async def check_closed_bazaar(io, name, cls, level):
    """a listing of a tester locks the character like any listing (login refused); the website never shows or sells it"""
    import tester_closed as TCL
    c0 = await io.helper('closed', 'closed', ANSWER)
    if not c0 or c0.get('err') or 'bazaar' not in c0:
        return Result('closed_bazaar', name, cls, SKIP, 'the helper does not report the bazaar lock (old helper file)')
    if not io.sql(TCL.bazaar_statements(name)):
        return Result('closed_bazaar', name, cls, SKIP, 'the listing could not be written (no database access)')
    try:
        await io.sleep(1.0)
        c1 = await io.helper('closed', 'closed', ANSWER)
    finally:
        io.sql(TCL.bazaar_release_statements(name))
    await io.sleep(1.0)
    c2 = await io.helper('closed', 'closed', ANSWER)
    problem = bazaar_problem(bool((c0.get('bazaar') or {}).get('locked')), bool(((c1 or {}).get('bazaar') or {}).get('locked')),
                             bool(((c2 or {}).get('bazaar') or {}).get('locked')))
    if problem:
        return Result('closed_bazaar', name, cls, FAIL, problem)
    return Result('closed_bazaar', name, cls, PASS, 'listed: locked; cancelled: free (no Chaos Coins, no bid, not on the site)')


# ------------------------------------------------------------------------------------------------ the raid, played (O588)
# The Ashen Sepulchre in closed test mode: a party of testers forms, waits for its members at the entrance, steps into the portal,
# starts the raid from its window, walks hall, corridors and boss rooms a step at a time, fights each pack and each boss (the bot
# casts its rotation and drinks by itself; the helper targets what is within 5 tiles), takes the loot, and leaves by the exit
# portal or the Leave button. The helper only reads (`!tester raid`: what a person sees on the screen, and the step next to the
# entrance, like `enter` for an NPC) and closes the empty run so the next one finds the slot free. No teleport inside the raid.
# Extra io for this check: io.partner(min_level=N), async io.step(dx, dy) / io.step_of(name, dx, dy) (one walk step: north (0, -1),
# east (1, 0), south (0, 1), west (-1, 0)), async io.loot(), io.raid_mode(names, on) (no flight to the temple while inside).
RAID_BUDGET = 1200.0    # seconds a party plays at most (the whole raid takes an hour; the check judges what it reached)
RAID_LOOK = 1.0         # seconds between two looks at the screen
RAID_STEP = 0.3         # seconds between two steps of a walk
RAID_STEPS = 3          # steps between two looks
RAID_PARTY = 2          # a party of this many bots at most (the leader and one member)
RAID_PARTY_WAIT = 20.0  # seconds the leader waits for its member at the entrance
RAID_ENTER_WAIT = 12.0  # seconds from `start` to standing inside
RAID_FIGHT_MIN = 180.0  # seconds at a pack or a boss without a kill that make a failure (damage, targets or the monsters)
RAID_LEAVE_WAIT = 150.0  # seconds after the budget for a fight to end before the run is closed by the helper
RAID_STUCK = 30.0       # seconds on one tile with a goal elsewhere: the walk is blocked there
RAID_MISSES = 6         # looks without an answer in a row
RAID_TURN = {'by': None, 'done': None}   # the testers have ONE raid slot: one party at a time, once in a run
RAID_MEMBERS = {}       # member name -> leader name, while a party plays (a member's own check starts no second raid)


def reset_raid_turn():
    RAID_TURN.update(by=None, done=None)
    RAID_MEMBERS.clear()


def raid_refusal(a, level=0):
    """(status, text) when this bot must not start the raid check, else None: from its `!tester raid` answer"""
    if not isinstance(a, dict):
        return SKIP, 'no answer to !tester raid (old helper file)'
    if a.get('err'):
        return SKIP, str(a['err'])[:80]
    if not a.get('on'):
        return SKIP, 'the closed mode switch reads off'
    if a.get('enabled') is False:
        return SKIP, 'the raid is sealed (raid_config.lua enabled)'
    have, need = int(a.get('level') or level or 0), int(a.get('minLevel') or 0)
    if have < need:
        return SKIP, 'level %d: the raid needs level %d' % (have, need)
    if a.get('inside'):
        return SKIP, 'the bot is inside a raid already'
    if not isinstance(a.get('portal'), dict):
        return SKIP, 'no entrance portal known'
    return None


def raid_plan(pos, goal, n):
    """up to n steps [(dx, dy)] from pos to goal, the longer axis first, walked in the head (so a look every few steps is
    enough); [] on another floor or when there"""
    if not isinstance(pos, dict) or not isinstance(goal, dict) or pos.get('z') != goal.get('z'):
        return []
    x, y = pos['x'], pos['y']
    out = []
    while len(out) < n and (x, y) != (goal['x'], goal['y']):
        dx, dy = goal['x'] - x, goal['y'] - y
        step = ((1 if dx > 0 else -1), 0) if abs(dx) >= abs(dy) else (0, (1 if dy > 0 else -1))
        out.append(step)
        x, y = x + step[0], y + step[1]
    return out


# the directions of the engine (north 0, east 1, south 2, west 3, southwest 4, southeast 5, northwest 6, northeast 7) as walk steps; a
# diagonal is two steps (the longer part of it first is not needed: x then y)
RAID_DIRS = {0: [(0, -1)], 1: [(1, 0)], 2: [(0, 1)], 3: [(-1, 0)], 4: [(-1, 0), (0, 1)], 5: [(1, 0), (0, 1)], 6: [(-1, 0), (0, -1)],
             7: [(1, 0), (0, -1)]}


def raid_path_steps(path):
    """the walk steps of a path of engine directions (`!tester raid path`); [] for anything that is not a list of directions"""
    out = []
    if not isinstance(path, list):
        return out
    for d in path[:120]:
        out.extend(RAID_DIRS.get(d, []) if isinstance(d, int) and not isinstance(d, bool) else [])
    return out


def raid_near(pos, goal, d):
    return isinstance(pos, dict) and isinstance(goal, dict) and pos.get('z') == goal.get('z') \
        and abs(pos['x'] - goal['x']) <= d and abs(pos['y'] - goal['y']) <= d


class RaidWalker:
    """what a person does when the way is blocked (a creature, a pillar, a door that is not open yet): the steps did not move the
    bot, so it goes round, one tile to the side, alternating the side, then on. `stuck(now)`: seconds without moving"""

    def __init__(self):
        self.pos = None
        self.sent = 0
        self.blocked = 0
        self.since = None

    def steps(self, pos, goal, n, now):
        p = (pos['x'], pos['y'], pos['z'])
        if p == self.pos and self.sent:
            self.blocked += 1
        else:
            self.blocked = 0
            self.since = now
        if self.since is None:
            self.since = now
        self.pos = p
        plan = raid_plan(pos, goal, n)
        if self.blocked and plan:
            dx, dy = plan[0]
            sign = 1 if self.blocked % 2 else -1   # the other side every time the way is blocked again
            side = (0, sign) if dx else (sign, 0)  # across the blocked direction; the next look walks on from the new tile
            plan = [side] * (1 + self.blocked // 2)
        self.sent = len(plan)
        return plan

    def stuck(self, now):
        return 0.0 if self.since is None else now - self.since


def raid_problems(a, slot=None):
    """[text] for one inside-the-raid answer: whatever says the run is not the testers' own"""
    out = []
    r = a.get('run') if isinstance(a, dict) else None
    if not isinstance(r, dict):
        return out
    if r.get('side') != 'tester':
        out.append('a tester is in a %s raid (it must be the testers\' own)' % r.get('side'))
    if slot is not None and r.get('slot') != slot:
        out.append('the testers\' raid runs in slot %s, not the testers\' slot %s' % (r.get('slot'), slot))
    if int(r.get('players') or 0) > RAID_PARTY:
        out.append('%s players in the testers\' raid, the party is %d bots at most (a player may be in it)' % (r.get('players'), RAID_PARTY))
    return out


def raid_verdict(t):
    """(status, text) from the trace of a played raid: entered, faults, killed (bosses), trash (corridors cleared), reached (set of
    places), fought (seconds at a pack or a boss), stuck (position or None), steps, secs, left, members"""
    if t.get('faults'):
        return FAIL, '; '.join(t['faults'][:3])
    done = 'came %s, entered by the portal with %d bot(s), %d step(s), corridors cleared %d, bosses slain %d of %d in %d s, left by %s' % (
        'on foot from the temple' if t.get('came') == 'foot' else 'next to the portal by the helper', t.get('members', 1), t.get('steps', 0),
        t.get('trash', 0), t.get('killed', 0), t.get('bosses', 0), t.get('secs', 0), t.get('left', '?'))
    if t.get('killed') or t.get('trash') or t.get('kills'):
        return PASS, done
    reached = sorted(t.get('reached') or [])
    if t.get('fought', 0) >= RAID_FIGHT_MIN:
        return FAIL, 'fought %d s at the first pack and killed nothing (damage, targets or the pack); reached %s' % (t['fought'], ', '.join(reached))
    if t.get('stuck'):
        return SKIP, 'the walk was blocked at (%d, %d) for %d s; reached %s' % (t['stuck'][0], t['stuck'][1], RAID_STUCK, ', '.join(reached) or 'the hall')
    return SKIP, 'no pack was killed in %d s (reached %s)' % (t.get('secs', 0), ', '.join(reached) or 'the hall')


def raid_start_refusal(text):
    """(status, text) of a start the raid window refused: the mode on and a closed-mode text is a bug, the rest is the state of the world"""
    text = str(text or '')[:90]
    if 'Closed test mode is off' in text or 'never mixed' in text:
        return FAIL, 'the raid refused a tester with the mode on: %s' % text
    return SKIP, 'the raid did not open: %s' % text


async def raid_look(io, r):
    if r['lead']:
        return await io.helper('raid state', 'raid', ANSWER)
    return await io.helper_of(r['name'], 'raid state', 'raid', ANSWER)


async def raid_walk(io, r, step):
    if r['lead']:
        await io.step(step[0], step[1])
    else:
        await io.step_of(r['name'], step[0], step[1])


async def raid_to_portal(io, r, portal):
    """'foot' when the bot walked from the temple to the entrance by its path, 'helper' when the helper had to put it next to the
    portal, else the reason it could not be there"""
    ask = (lambda c: io.helper(c, 'raid', HELPER_WAIT)) if r['lead'] else (lambda c: io.helper_of(r['name'], c, 'raid', HELPER_WAIT))
    if not (await io.go('town') if r['lead'] else await io.go_of(r['name'], 'town')):
        return 'the helper did not bring the bot to the temple'
    await io.sleep(SETTLE)
    got = await ask('raid path')
    steps = raid_path_steps((got or {}).get('path') if isinstance(got, dict) else None)
    for step in steps:
        await raid_walk(io, r, step)
        await io.sleep(RAID_STEP)
    if steps:
        await io.sleep(RAID_STEP)
        here = await raid_look(io, r)
        if isinstance(here, dict) and raid_near(here.get('pos'), portal, 1):
            return 'foot'
    got = await ask('raid portal')
    if not isinstance(got, dict) or got.get('err'):
        return str((got or {}).get('err') if isinstance(got, dict) else 'no answer')[:80] or 'no answer'
    return 'helper'


async def raid_release(io, partners):
    for p in list(partners):
        RAID_MEMBERS.pop(p, None)
        await io.party('leave', p)


async def check_closed_raid(io, name, cls, level):
    """a party of testers plays the raid like people: forms, waits for its members, enters by the portal, walks, fights, loots, leaves"""
    key = 'closed_raid'
    if name in RAID_MEMBERS:
        return Result(key, name, cls, SKIP, 'played as the member of the party of %s (its result is the party\'s)' % RAID_MEMBERS[name])
    a = await io.helper('raid state', 'raid', ANSWER)
    no = raid_refusal(a, level)
    if no:
        return Result(key, name, cls, no[0], no[1])
    if RAID_TURN['done']:
        return Result(key, name, cls, SKIP, 'the testers have one raid slot and %s played it in this run' % RAID_TURN['done'])
    if RAID_TURN['by'] not in (None, name):
        return Result(key, name, cls, SKIP, 'the testers have one raid slot: %s is in it' % RAID_TURN['by'])
    RAID_TURN['by'] = name
    partners = []
    try:
        r = await raid_play(io, name, cls, a, partners)
    finally:
        RAID_TURN['by'] = None
        await raid_release(io, partners)
        io.raid_mode([name] + partners, False)
    return r


async def raid_play(io, name, cls, a, partners):
    key = 'closed_raid'
    need = int(a.get('minPlayers') or 1)
    if need > RAID_PARTY:
        return Result(key, name, cls, SKIP, 'the raid needs %d players: a run of the bots forms %d at most' % (need, RAID_PARTY))
    # the party: one member when a free bot of the raid's level is in game (the raid opens for one alone, minPlayers 1)
    want = max(need, RAID_PARTY)
    min_level = int(a.get('minLevel') or 0)
    while len(partners) + 1 < want:
        other = await io.partner(min_level=min_level)
        if not other:
            break
        RAID_MEMBERS[other] = name
        partners.append(other)
    if len(partners) + 1 < need:
        return Result(key, name, cls, SKIP, 'the raid needs %d players and %d bot(s) of level %d are free' % (need, len(partners) + 1, min_level))
    squad = [{'name': name, 'lead': True, 'walker': RaidWalker(), 'inside': False}]
    for p in list(partners):
        m = await io.helper_of(p, 'raid state', 'raid', ANSWER)
        if raid_refusal(m, 0) is not None:
            await raid_release(io, [p])
            partners.remove(p)
            continue
        squad.append({'name': p, 'lead': False, 'walker': RaidWalker(), 'inside': False})
    if len(squad) < need:
        return Result(key, name, cls, SKIP, 'the raid needs %d players and %d bot(s) can play it' % (need, len(squad)))
    # to the shop first, like a person: the potions topped up
    for r in squad:
        if r['lead']:
            await io.helper('bag', 'bag', HELPER_WAIT)
        else:
            await io.helper_of(r['name'], 'bag', 'bag', HELPER_WAIT)
    # to the entrance: from the temple on foot, by the path the server's own pathfinding gives (a player's auto walk); the helper
    # puts the bot next to the portal only when that path fails (the way `enter` takes a bot to an NPC). The leader then invites,
    # the member joins
    portal = a['portal']
    came = {}
    for r in squad:
        how = await raid_to_portal(io, r, portal)
        if how not in ('foot', 'helper'):
            return Result(key, name, cls, SKIP, 'to the raid portal: %s' % how)
        came[r['name']] = how
    if len(squad) > 1:
        await io.party('form', squad[1]['name'])
        waited = 0.0
        while waited < RAID_PARTY_WAIT and io.alive():
            there = []
            for r in squad:
                there.append(raid_near(((await raid_look(io, r)) or {}).get('pos'), portal, 3))
            if all(there):
                break
            await io.sleep(LOOK)
            waited += LOOK
        else:
            if io.alive():
                return Result(key, name, cls, SKIP, 'the member of the party did not come to the entrance in %d s' % int(RAID_PARTY_WAIT))
    await io.sleep(SETTLE)
    io.raid_mode([r['name'] for r in squad], True)
    # the first step into the portal opens the raid window; the start request is the window's button
    me = await raid_look(io, squad[0])
    for step in raid_plan((me or {}).get('pos'), portal, 1):
        await io.step(step[0], step[1])
    await io.sleep(1.0)
    window = await io.request('raid', 'open', {}, ['info'], ANSWER)
    if window is None:
        return Result(key, name, cls, SKIP, 'no answer from the raid window (not installed)')
    start = await io.request('raid', 'start', {}, ['closeInfo', 'msg', 'hud'], ANSWER)
    if start is not None and start.get('action') == 'msg':
        no = raid_start_refusal((start.get('data') or {}).get('text'))
        return Result(key, name, cls, no[0], no[1])
    trace = {'faults': [], 'reached': set(), 'steps': 0, 'killed': 0, 'trash': 0, 'kills': 0, 'fought': 0.0, 'stuck': None,
             'secs': 0, 'left': '?', 'members': 0, 'bosses': int(a.get('bosses') or 0),
             'came': 'foot' if all(h == 'foot' for h in came.values()) else 'helper',
             'fallbacks': [fallback_note('raid portal', 'no path, or the walk did not arrive') for h in came.values() if h != 'foot']}
    waited, state = 0.0, None
    while waited <= RAID_ENTER_WAIT and io.alive():
        state = await raid_look(io, squad[0])
        if isinstance(state, dict) and state.get('inside'):
            break
        await io.sleep(1.0)
        waited += 1.0
    if not (isinstance(state, dict) and state.get('inside')):
        return Result(key, name, cls, SKIP, 'the start did not bring the bot into the raid (%s)' % str(((start or {}).get('data') or {}).get('text') or 'no answer')[:70])
    RAID_TURN['done'] = name   # a raid is played in this run: the other bots do not start a second one (one slot)
    for r in squad:
        s = state if r['lead'] else await raid_look(io, r)
        r['inside'] = bool(isinstance(s, dict) and s.get('inside'))
    trace['members'] = sum(1 for r in squad if r['inside'])
    return await raid_walk_all(io, name, cls, a, squad, trace)


async def raid_walk_all(io, name, cls, a, squad, trace):
    """the play loop: look, then each bot walks, waits or fights by what the screen says, until the raid is over or the time is"""
    key = 'closed_raid'
    slot = a.get('slot')
    elapsed, misses = 0.0, 0
    leaving, leave_at = False, None
    fight_since, progress = None, None
    home = home_rule(key, name, cls, (a or {}).get('level'))   # O659: the way home of a second retreat
    while io.alive():
        looks = {}
        for r in squad:
            looks[r['name']] = await raid_look(io, r) if r['inside'] else None
        lead = looks.get(squad[0]['name'])
        if not isinstance(lead, dict):
            misses += 1
            if misses >= RAID_MISSES:
                trace['left'] = 'no answer from the helper'
                break
            await io.sleep(RAID_LOOK)
            elapsed += RAID_LOOK
            continue
        misses = 0
        if not lead.get('inside'):
            trace['left'] = 'the exit' if trace['killed'] >= trace['bosses'] and trace['bosses'] else 'the run ended (time or an exit)'
            break
        trace['faults'] += [p for p in raid_problems(lead, slot) if p not in trace['faults']]
        if trace['faults']:
            break
        run = lead.get('run') or {}
        guide = lead.get('guide') or {}
        spent = await retreat_or_home(io, squad[0], lead, trace, guide, home) if not leaving else 0.0   # O659: the retreat of the raid loop
        if trace.get('gone'):
            trace['left'] = 'retreated home'
            break
        if spent:
            elapsed += spent
            continue
        trace['reached'].add(str(guide.get('where') or 'hall'))
        if run.get('killed', 0) > trace['killed']:
            trace['killed'] = int(run['killed'])
            await io.loot()
        trace['trash'] = max(trace['trash'], int(run.get('trash') or 0))
        trace['kills'] = max(trace['kills'], int(run.get('kills') or 0))
        # progress: a pack or a boss losing health, or a corridor cleared, resets the clock of a fight with nothing to show
        mark = (run.get('killed'), run.get('trash'), run.get('trashLeft'), run.get('bossHp'), run.get('monsters'))
        if mark != progress:
            progress, fight_since = mark, None
        mode = guide.get('mode')
        if mode == 'fight':
            fight_since = elapsed if fight_since is None else fight_since
            trace['fought'] = max(trace['fought'], elapsed - fight_since)
        else:
            fight_since = None if mode != 'wait' else fight_since
        if elapsed >= RAID_BUDGET and not leaving:
            leaving, leave_at = True, elapsed
        if leaving:
            for r in squad:
                if not r['inside'] or not (looks.get(r['name']) or {}).get('inside'):
                    continue
                reply = await (io.request('raid', 'leave', {}, ['end', 'msg'], ANSWER) if r['lead']
                               else io.request_of(r['name'], 'raid', 'leave', {}, ['end', 'msg'], ANSWER))
                if reply is not None and reply.get('action') == 'end':
                    r['inside'] = False
            if not any(r['inside'] for r in squad):
                trace['left'] = 'the Leave button'
                break
            if elapsed - leave_at >= RAID_LEAVE_WAIT:
                trace['left'] = 'a close by the helper (a fight did not end in %d s)' % int(RAID_LEAVE_WAIT)
                break
        else:
            sent = {}
            for r in squad:
                s = looks.get(r['name'])
                g = (s or {}).get('guide') or {}
                if not r['inside'] or not isinstance(s, dict) or not s.get('inside'):
                    r['inside'] = False
                    continue
                if g.get('mode') in ('walk', 'exit') and isinstance(g.get('goal'), dict) and not (
                        g.get('mode') == 'walk' and raid_near(s.get('pos'), g['goal'], 1)):
                    sent[r['name']] = r['walker'].steps(s['pos'], g['goal'], RAID_STEPS, elapsed)
                    if r['lead'] and r['walker'].stuck(elapsed) >= RAID_STUCK:
                        trace['stuck'] = (s['pos']['x'], s['pos']['y'])
            for i in range(RAID_STEPS):
                moved = False
                for r in squad:
                    plan = sent.get(r['name']) or []
                    if i < len(plan):
                        await raid_walk(io, r, plan[i])
                        trace['steps'] += 1
                        moved = True
                if not moved:
                    break
                await io.sleep(RAID_STEP)
                elapsed += RAID_STEP
        await io.sleep(RAID_LOOK)
        elapsed += RAID_LOOK
        trace['secs'] = int(elapsed)
    trace['secs'] = int(elapsed)
    # out: the empty run is closed so the slot is free for the next one (the idle close would do it after minutes)
    closed = await io.helper('raid close', 'raid', ANSWER)
    after = await io.helper('raid state', 'raid', ANSWER)
    if isinstance(after, dict) and after.get('inside'):
        trace['faults'].append('the bot is still inside the raid after the close')
    if trace['left'] == '?' and isinstance(closed, dict) and closed.get('closed'):
        trace['left'] = 'a close by the helper'
    status, text = raid_verdict(trace)
    status, text = home_verdict(trace, status, text)   # O659
    return Result(key, name, cls, status, text, trace.get('fallbacks'))


# ------------------------------------------------------------------------------------------------ walking like a person (O589)
# The helper's `enter` puts a bot at a place by a teleport; a person walks. `walk_by_path` walks the engine's own path of a helper
# command (`path <kind>`, `dungeon path`): the answer carries the directions, the bot takes them step by step and asks again until it
# is there. A teleport stays only as the fallback when there is no path (a wall, another floor, the engine's search limit); the check
# names it in its result and the report counts it (Result.fallbacks, "Helper teleports in place of walking").
PATH_ROUNDS = 8         # asks for a path at most this many times for one walk (each answer holds up to 80 steps)
PATH_STALL = 2          # rounds in a row that left the bot no nearer: the walk is blocked


def fallback_note(what, why):
    """the line a result carries for a teleport it used because the walk was not possible: `what` is the helper command"""
    return '%s (%s)' % (what, str(why or 'no reason')[:60])


async def hcmd(io, r, command, kind, wait=None):
    """a helper command of the leader (r['lead']) or of the squad member r['name']"""
    wait = ANSWER if wait is None else wait
    if r['lead']:
        return await io.helper(command, kind, wait)
    return await io.helper_of(r['name'], command, kind, wait)


async def walk_by_path(io, r, command, kind, near=1, rounds=PATH_ROUNDS):
    """walks the engine path of a helper command until the answer says the bot is there (`here`, or `dist` at most `near`).
    -> (how, got): how is 'foot' (arrived: got is the last answer, with pos and dest), 'err' (got['err'] says why: no path, another
    floor, no answer) or 'far' (still on the way after `rounds` asks, or blocked)"""
    last, stalled = None, 0
    for _ in range(rounds):
        if not io.alive():
            return 'err', {'err': 'the bot is gone'}
        got = await hcmd(io, r, command, kind)
        if not isinstance(got, dict):
            return 'err', {'err': 'no answer to !tester %s' % command}
        if got.get('err'):
            return 'err', got
        dist = got.get('dist')
        if got.get('here') or (dist is not None and dist <= near):
            return 'foot', got
        steps = raid_path_steps(got.get('path'))
        if not steps:
            return 'err', dict(got, err='an empty path')
        if last is not None and dist is not None and dist >= last:
            stalled += 1
            if stalled >= PATH_STALL:
                return 'far', got
        else:
            stalled = 0
        last = dist
        for step in steps:
            await raid_walk(io, r, step)
            await io.sleep(RAID_STEP)
        await io.sleep(RAID_STEP)
    return 'far', got


async def walk_to_place(io, r, kind, n=None, near=1):
    """a person's way to a map place: on foot by `!tester path <kind>`; when that fails the helper's `enter` puts the bot next to it.
    -> (how, got, fallback): 'foot' / 'helper' (or the failure text), the last path answer, the note of the teleport or None"""
    place = kind if n is None else '%s %d' % (kind, n)
    how, got = await walk_by_path(io, r, 'path ' + place, 'path', near)
    if how == 'foot':
        return 'foot', got, None
    why = (got or {}).get('err') or 'the walk did not arrive'
    moved = await hcmd(io, r, 'enter ' + place, 'enter', HELPER_WAIT)
    if not isinstance(moved, dict) or moved.get('err'):
        return 'no way to %s: %s; the teleport: %s' % (place, why, str((moved or {}).get('err') or 'no answer')[:50]), got, None
    again = await hcmd(io, r, 'path ' + place, 'path')
    return 'helper', again if isinstance(again, dict) else got, fallback_note('enter ' + place, why)


# ------------------------------------------------------------------------------------------------ the dungeons, played (O589)
# A dungeon in closed test mode: the bots go to a dungeon entrance on foot, step on it (the window), queue, and play the run like a
# person: the monsters nearest first until the boss is unlocked, then the boss, loot, and out by the exit teleport the server gives
# after a clear. The helper only reads (`!tester dungeon`: what a person sees on the screen) and gives the engine path to the next
# goal; the walk, the fights (the class's own rotation and potions) and the loot are the bot's own. No teleport inside the run.
DUNGEON_BUDGET = 1000.0   # seconds a run is played at most (the server's own limit is 15 minutes)
DUNGEON_STEPS = 6         # steps between two looks
DUNGEON_QUEUE_WAIT = 90.0 # seconds a queued bot waits for its run (a player's run may be ahead of it)
DUNGEON_START_WAIT = 20.0 # seconds from the start of the run to the first look inside
DUNGEON_FIGHT_MIN = 180.0 # seconds at a monster or the boss without any progress that make a failure (damage, targets, the monsters)
DUNGEON_STUCK = 30.0      # seconds on one tile with a goal elsewhere: the walk is blocked there
DUNGEON_MISSES = 6        # looks without an answer in a row
DUNGEON_BUSY = {}         # dungeon id -> bot name, while a bot plays it
DUNGEON_DONE = {}         # dungeon id -> bot name, once a bot played it in this run (one play of each dungeon is the coverage)
DUNGEON_MEMBERS = {}      # member name -> leader name, while a party plays


def reset_dungeon_turn():
    DUNGEON_DIFF_DONE.clear()
    DUNGEON_BUSY.clear()
    DUNGEON_DONE.clear()
    DUNGEON_MEMBERS.clear()


def dungeon_refusal(a, level=0):
    """(status, text) when this bot must not start the dungeon check, else None: from its `!tester dungeon` answer"""
    if not isinstance(a, dict):
        return SKIP, 'no answer to !tester dungeon (old helper file)'
    if a.get('err'):
        return SKIP, str(a['err'])[:80]
    if not a.get('on'):
        return SKIP, 'the closed mode switch reads off'
    if a.get('inside'):
        return SKIP, 'the bot is inside a dungeon already'
    if a.get('queued'):
        return SKIP, 'the bot is queued for a dungeon already'
    if not a.get('list'):
        return SKIP, 'no dungeon list'
    return None


def dungeon_pick(a, level=0):
    """the dungeon this bot plays: the highest of its level not played or being played by another bot in this run.
    -> (dungeon dict, None) or (None, the skip text)"""
    have = int(a.get('level') or level or 0)
    ok = [d for d in a.get('list') or [] if isinstance(d, dict) and isinstance(d.get('id'), int) and not d.get('weekly')]   # the Weekly Challenge: its own check (O651)
    fit = [d for d in ok if int(d.get('level') or 0) <= have]
    if not fit:
        low = min([int(d.get('level') or 0) for d in ok] or [0])
        return None, 'level %d: the lowest dungeon needs level %d' % (have, low)
    free = [d for d in fit if d['id'] not in DUNGEON_BUSY and d['id'] not in DUNGEON_DONE]
    if not free:
        names = sorted(set(list(DUNGEON_DONE.values()) + list(DUNGEON_BUSY.values())))
        return None, 'every dungeon of level %d was played in this run (by %s)' % (have, ', '.join(names) or 'another bot')
    return max(free, key=lambda d: (int(d.get('level') or 0), -d['id'])), None


def dungeon_problems(a, size=None):
    """[text] for one inside-a-run answer: whatever says the run is not the testers' own"""
    out = []
    r = a.get('run') if isinstance(a, dict) else None
    if not isinstance(r, dict):
        return out
    if r.get('side') != 'tester':
        out.append('a tester is in a %s dungeon run (it must be the testers\' own)' % r.get('side'))
    if size is not None and int(r.get('members') or 0) > size:
        out.append('%s players in the testers\' dungeon run, the party is %d bots at most (a player may be in it)' % (r.get('members'), size))
    return out


def difficulty_problems(a, trace):
    """[text] for one inside-a-run answer (O651): the run's difficulty is the one the check expects (the queue's request, or the fixed one of the
    Weekly Challenge), and the difficulty is on the monsters (`scaled`: monsters of the run that carry it). Keeps the most scaled in the trace"""
    out = []
    r = a.get('run') if isinstance(a, dict) else None
    if not isinstance(r, dict):
        return out
    want = trace.get('difficulty')
    if want is not None and r.get('difficulty') is not None and int(r['difficulty']) != int(want):
        out.append('the run is at difficulty %s, the check expects %s (queued for %s)' % (r['difficulty'], want, trace.get('asked')))
    if isinstance(r.get('scaled'), int):
        trace['scaled'] = max(trace.get('scaled', 0), r['scaled'])
        trace['monsters'] = max(trace.get('monsters', 0), int(r.get('left') or 0))
    return out


def dungeon_verdict(t):
    """(status, text) from the trace of a played run: faults, kills (percent reached), won (boss down after the unlock), unlocked,
    fought (seconds at a monster or the boss without progress), stuck, steps, secs, left, members, title"""
    if t.get('faults'):
        return FAIL, '; '.join(t['faults'][:3])
    how = 'came %s, %d bot(s), %d step(s), %d%% of the monsters dead%s%s in %d s, left by %s' % (
        'on foot from the temple' if t.get('came') == 'foot' else 'by a helper teleport next to the entrance', t.get('members', 1),
        t.get('steps', 0), t.get('percent', 0), ', boss unlocked' if t.get('unlocked') else '', ', boss slain' if t.get('won') else '',
        t.get('secs', 0), t.get('left', '?'))
    if t.get('fallbacks'):
        how += '; teleport in place of walking: ' + ', '.join(t['fallbacks'])
    if t.get('asked', 1) > 1 or t.get('difficulty', 1) > 1:
        how += '; difficulty %s%s, %d of %d monster(s) scaled' % (t.get('difficulty'), ' (asked for %s)' % t['asked'] if t.get('asked') != t.get('difficulty') else '',
                                                                t.get('scaled', 0), t.get('monsters', 0))
    if t.get('won') or t.get('percent', 0) > 0:
        return PASS, '%s: %s' % (t.get('title') or 'dungeon', how)
    if t.get('fought', 0) >= DUNGEON_FIGHT_MIN:
        return FAIL, 'fought %d s at the first monsters and killed none (damage, targets or the monsters)' % t['fought']
    if t.get('stuck'):
        return SKIP, 'the walk was blocked at (%d, %d) for %d s' % (t['stuck'][0], t['stuck'][1], DUNGEON_STUCK)
    if t.get('died'):
        return SKIP, 'the bot died before it killed a monster (level %s against the dungeon)' % t.get('level', '?')
    return SKIP, 'no monster was killed in %d s' % t.get('secs', 0)


async def dungeon_look(io, r):
    return await hcmd(io, r, 'dungeon state', 'dungeon')


async def check_closed_dungeon(io, name, cls, level):
    """a bot (and a partner when the dungeon takes two) walks to a dungeon entrance, queues and plays the run: monsters, boss, loot, out"""
    key = 'closed_dungeon'
    if name in DUNGEON_MEMBERS:
        return Result(key, name, cls, SKIP, 'played as the member of the party of %s (its result is the party\'s)' % DUNGEON_MEMBERS[name])
    a = await io.helper('dungeon state', 'dungeon', ANSWER)
    no = dungeon_refusal(a, level)
    if no:
        return Result(key, name, cls, no[0], no[1])
    dg, why = dungeon_pick(a, level)
    if dg is None:
        return Result(key, name, cls, SKIP, why)
    DUNGEON_BUSY[dg['id']] = name
    partners = []
    result = None
    try:
        result = await dungeon_play(io, name, cls, a, dg, partners)
    finally:
        DUNGEON_BUSY.pop(dg['id'], None)
        if result is not None and result.status == PASS:
            DUNGEON_DONE[dg['id']] = name
        for p in list(partners):
            DUNGEON_MEMBERS.pop(p, None)
            await io.party('leave', p)
        io.raid_mode([name] + partners, False)
    return result


async def dungeon_play(io, name, cls, a, dg, partners, key='closed_dungeon', difficulty=1, title=None):
    """one run of dungeon dg at `difficulty` (O651: 2 to 6 and the Weekly Challenge, whose fixed difficulty wins over the request). A difficulty
    above the one unlocked is unlocked on the bot's own progress first (the helper's TEST ONLY `dungeon unlock`: a person earns it with one clear
    of each difficulty before)"""
    size = max(1, int(dg.get('size') or 1))
    expect = int(dg.get('fixed') or difficulty)
    while len(partners) + 1 < size:
        other = await io.partner(min_level=int(dg.get('level') or 0))
        if not other:
            break
        DUNGEON_MEMBERS[other] = name
        partners.append(other)
    squad = [{'name': name, 'lead': True, 'walker': RaidWalker(), 'inside': False}]
    for p in list(partners):
        m = await io.helper_of(p, 'dungeon state', 'dungeon', ANSWER)
        if dungeon_refusal(m, 0) is not None:
            DUNGEON_MEMBERS.pop(p, None)
            partners.remove(p)
            continue
        squad.append({'name': p, 'lead': False, 'walker': RaidWalker(), 'inside': False})
    # the potions topped up, then the temple and the way to an entrance on foot (the helper only when there is no path)
    for r in squad:
        await hcmd(io, r, 'bag', 'bag', HELPER_WAIT)
    fallbacks, came = [], {}
    for r in squad:
        if not (await io.go('town') if r['lead'] else await io.go_of(r['name'], 'town')):
            return Result(key, name, cls, SKIP, 'the helper did not bring the bot to the temple')
        await io.sleep(SETTLE)
        how, got, note = await walk_to_place(io, r, 'dungeon')
        if how not in ('foot', 'helper'):
            return Result(key, name, cls, SKIP, how[:110])
        came[r['name']] = how
        if note:
            fallbacks.append(note)
        # the last step is onto the entrance tile: that opens the window, as for a player
        here, dest = (got or {}).get('pos'), (got or {}).get('dest')
        for step in raid_plan(here, dest, 1):
            await raid_walk(io, r, step)
        await io.sleep(1.0)
    if len(squad) > 1:
        await io.party('form', squad[1]['name'])
    io.raid_mode([r['name'] for r in squad], True, keep_flee=True)
    window = await io.request('dungeons', 'fetch', {}, ['list', 'dungeon'], ANSWER)
    if window is None:
        return Result(key, name, cls, SKIP, 'no answer from the dungeons window (not installed)', fallbacks)
    if difficulty > int(dg.get('max') or 1) and not dg.get('fixed'):
        for r in squad:
            got = await hcmd(io, r, 'dungeon unlock %d %d' % (dg['id'], difficulty), 'dungeon', HELPER_WAIT)
            if not isinstance(got, dict) or got.get('err') or int(got.get('unlocked') or 0) < difficulty:
                return Result(key, name, cls, SKIP, 'difficulty %d could not be unlocked: %s' % (
                    difficulty, str((got or {}).get('err') or 'no answer')[:60]), fallbacks)
    # queue, each bot from its own window; the run starts when the group is full or the solo wait is over
    for r in squad:
        data = {'id': dg['id'], 'difficulty': difficulty}
        reply, _calm = await queue_dungeon_calm(io, r, data)   # O661: a bot in a fight waits at the door and asks again
        if reply is not None and (reply.get('data') or {}).get('joined') is False and r['lead']:
            said = str((reply.get('data') or {}).get('text') or (reply.get('data') or {}).get('why') or '') or recent_text(io, 2)   # O660: the server's own words
            return Result(key, name, cls, SKIP, 'the queue refused the bot (level, a cooldown, a fight or the dungeon\'s own rule)%s' % (
                ': ' + said[:90] if said else ''), fallbacks)
    waited, state = 0.0, None
    while waited <= DUNGEON_QUEUE_WAIT and io.alive():
        state = await dungeon_look(io, squad[0])
        if isinstance(state, dict) and state.get('inside'):
            break
        if isinstance(state, dict) and not state.get('queued') and waited >= 4.0:
            return Result(key, name, cls, SKIP, 'the bot is not in the queue after the request (level, a cooldown or a fight)', fallbacks)
        await io.sleep(2.0)
        waited += 2.0
    if not (isinstance(state, dict) and state.get('inside')):
        for r in squad:   # a queue entry is left by sending the request again (the window's one button)
            await (io.request('dungeons', 'queue', {'id': dg['id'], 'difficulty': difficulty}, ['queue'], ANSWER) if r['lead']
                   else io.request_of(r['name'], 'dungeons', 'queue', {'id': dg['id'], 'difficulty': difficulty}, ['queue'], ANSWER))
        return Result(key, name, cls, SKIP, 'the dungeon did not start in %d s (a run of players is ahead of the testers)' % int(DUNGEON_QUEUE_WAIT), fallbacks)
    for r in squad:
        s = state if r['lead'] else await dungeon_look(io, r)
        r['inside'] = bool(isinstance(s, dict) and s.get('inside'))
    trace = {'faults': [], 'steps': 0, 'percent': 0, 'unlocked': False, 'won': False, 'fought': 0.0, 'stuck': None, 'secs': 0,
             'left': '?', 'members': sum(1 for r in squad if r['inside']), 'title': dg.get('title'), 'died': False,
             'level': a.get('level'), 'came': 'foot' if all(h == 'foot' for h in came.values()) else 'helper',
             'size': size, 'fallbacks': fallbacks, 'key': key, 'difficulty': expect, 'asked': difficulty, 'scaled': 0, 'monsters': 0}
    if title:
        trace['title'] = title
    res = await dungeon_walk_all(io, name, cls, squad, trace)
    return res


async def dungeon_walk_all(io, name, cls, squad, trace):
    """the play loop: look, then each bot walks, waits or fights by what the screen says, until the run is over or the time is"""
    key = trace.get('key', 'closed_dungeon')
    elapsed, misses = 0.0, 0
    fight_since, progress, boss_seen, looted = None, None, False, 0.0
    home = home_rule(key, name, cls, trace.get('level'))   # O659: the way home of a second retreat
    while io.alive():
        looks = {}
        for r in squad:
            looks[r['name']] = await dungeon_look(io, r) if r['inside'] else None
        lead = looks.get(squad[0]['name'])
        if not isinstance(lead, dict):
            misses += 1
            if misses >= DUNGEON_MISSES:
                trace['left'] = 'no answer from the helper'
                break
            await io.sleep(RAID_LOOK)
            elapsed += RAID_LOOK
            continue
        misses = 0
        if not lead.get('inside'):
            trace['left'] = 'the exit teleport' if trace['won'] else 'the run ended (time, death or the exit)'
            trace['died'] = not trace['won'] and elapsed < DUNGEON_BUDGET and not trace['unlocked']
            break
        trace['faults'] += [p for p in dungeon_problems(lead, trace['size']) + difficulty_problems(lead, trace) if p not in trace['faults']]
        if trace['faults']:
            break
        run = lead.get('run') or {}
        guide = lead.get('guide') or {}
        spent = await retreat_or_home(io, squad[0], lead, trace, guide, home)   # O659: the retreat of the dungeon loop; a second one goes home
        if trace.get('gone'):
            trace['left'] = 'retreated home'
            break
        if spent:
            elapsed += spent
            continue
        pct = int(run.get('percent') or 0)
        if pct > trace['percent']:
            trace['percent'] = pct
            if elapsed - looted >= 3.0:   # the corpses of the pack: the bot takes the loot as it does anywhere
                await io.loot()
                looted = elapsed
        trace['unlocked'] = trace['unlocked'] or bool(run.get('unlocked'))
        if run.get('bossHp') is not None:
            boss_seen = True
        if run.get('unlocked') and boss_seen and run.get('bossHp') is None:
            trace['won'] = True
            await io.loot()
        mark = (run.get('percent'), run.get('left'), run.get('bossHp'), run.get('unlocked'))
        if mark != progress:
            progress, fight_since = mark, None
        mode = guide.get('mode')
        if mode == 'fight':
            fight_since = elapsed if fight_since is None else fight_since
            trace['fought'] = max(trace['fought'], elapsed - fight_since)
        elif mode != 'wait':
            fight_since = None
        if elapsed >= DUNGEON_BUDGET:
            trace['left'] = 'a close by the helper (the time of the check)'
            break
        sent = {}
        for r in squad:
            s = looks.get(r['name'])
            g = (s or {}).get('guide') or {}
            if not r['inside'] or not isinstance(s, dict) or not s.get('inside'):
                r['inside'] = False
                continue
            if g.get('mode') == 'walk' and isinstance(g.get('goal'), dict):
                plan = r['walker'].steps(s['pos'], g['goal'], DUNGEON_STEPS, elapsed)
                if not r['walker'].blocked:   # the engine's path first (walls, doors); the side step only when the way is blocked
                    got = await hcmd(io, r, 'dungeon path', 'dungeon')
                    steps = raid_path_steps((got or {}).get('path')) if isinstance(got, dict) and not got.get('err') else []
                    plan = steps[:DUNGEON_STEPS] or plan
                sent[r['name']] = plan
                if r['lead'] and r['walker'].stuck(elapsed) >= DUNGEON_STUCK:
                    trace['stuck'] = (s['pos']['x'], s['pos']['y'])
        for i in range(DUNGEON_STEPS):
            moved = False
            for r in squad:
                plan = sent.get(r['name']) or []
                if i < len(plan):
                    await raid_walk(io, r, plan[i])
                    trace['steps'] += 1
                    moved = True
            if not moved:
                break
            await io.sleep(RAID_STEP)
            elapsed += RAID_STEP
        await io.sleep(RAID_LOOK)
        elapsed += RAID_LOOK
        trace['secs'] = int(elapsed)
    trace['secs'] = int(elapsed)
    # out: the run of the testers is closed so the dungeon is free for the next one
    closed = await io.helper('dungeon close', 'dungeon', ANSWER)
    after = await io.helper('dungeon state', 'dungeon', ANSWER)
    if isinstance(after, dict) and after.get('inside'):
        trace['faults'].append('the bot is still inside the dungeon after the close')
    if trace['left'] == '?' and isinstance(closed, dict) and closed.get('closed'):
        trace['left'] = 'a close by the helper'
    status, text = dungeon_verdict(trace)
    status, text = home_verdict(trace, status, text)   # O659
    return Result(key, name, cls, status, text, trace.get('fallbacks'))


# ------------------------------------------------------------------------------------------------ dungeon difficulties 2 to 6 and the Weekly Challenge (O651)
# The same walk and fights as closed_dungeon (a closed check: the run is the testers' own, never ranked or recorded) at a higher difficulty or in the
# Weekly Challenge's dungeon. The difficulty a person unlocks by clearing the one before is written to the bot's own progress by the helper (TEST ONLY
# `dungeon unlock`), the queue asks for it like the window's button, and the run must carry it: `run.difficulty` and the monsters scaled (health and
# damage x the table of dungeons_difficulty.lua). The Weekly Challenge has one difficulty for every run: the bot asks for another and the run must
# be at the fixed one; its board (challenge_solo, challenge_party) must list no tester before and after.
DUNGEON_DIFFS = (2, 3, 4, 5, 6)
DUNGEON_DIFF_DONE = {}   # difficulty -> bot name, once a bot played it in this run
DUNGEON_DIFF_MARGIN = {2: 1.0, 3: 1.3, 4: 1.7, 5: 2.2, 6: 3.0}   # the level over the dungeon's own a bot needs for the difficulty (health x2 to x13, damage x1.3 to x6)
WEEKLY_ASK = 3           # the difficulty the bot asks the Weekly Challenge for (its own rule ignores it)


def reset_difficulty_turn():
    DUNGEON_DIFF_DONE.clear()


def dungeon_difficulty_pick(a, level=0):
    """(dungeon, difficulty, None) this bot plays: the highest difficulty not played yet in this run that the bot's level carries on a dungeon no bot is
    in (solo dungeons first, then the lowest level), else (None, None, the skip text)"""
    have = int(a.get('level') or level or 0)
    top = int(a.get('maxDifficulty') or 6)
    plain = [d for d in a.get('list') or [] if isinstance(d, dict) and isinstance(d.get('id'), int) and not d.get('fixed') and not d.get('weekly')]
    free = [d for d in plain if d['id'] not in DUNGEON_BUSY]
    todo = [d for d in DUNGEON_DIFFS if d <= top and d not in DUNGEON_DIFF_DONE]
    if not todo:
        return None, None, 'every difficulty of 2 to %d was played in this run (by %s)' % (top, ', '.join(sorted(set(DUNGEON_DIFF_DONE.values()))) or 'other bots')
    for d in sorted(todo, reverse=True):
        fit = [g for g in free if have >= int(int(g.get('level') or 0) * DUNGEON_DIFF_MARGIN[d])]
        if fit:
            return min(fit, key=lambda g: (int(g.get('size') or 1), int(g.get('level') or 0), g['id'])), d, None
    low = min([int(g.get('level') or 0) for g in plain] or [0])
    return None, None, 'level %d: no free dungeon carries difficulty %d (the lowest dungeon needs level %d, x%.1f)' % (have, min(todo), low, DUNGEON_DIFF_MARGIN[min(todo)])


async def check_dungeon_difficulty(io, name, cls, level):
    """a dungeon at difficulty 2 to 6: unlock it on the bot's progress, queue for it, play the run, the run must carry it"""
    key = 'dungeon_difficulty'
    if name in DUNGEON_MEMBERS:
        return Result(key, name, cls, SKIP, 'played as the member of the party of %s (its result is the party\'s)' % DUNGEON_MEMBERS[name])
    a = await io.helper('dungeon state', 'dungeon', ANSWER)
    no = dungeon_refusal(a, level)
    if no:
        return Result(key, name, cls, no[0], no[1])
    dg, diff, why = dungeon_difficulty_pick(a, level)
    if dg is None:
        return Result(key, name, cls, SKIP, why)
    DUNGEON_BUSY[dg['id']] = name
    partners = []
    result = None
    try:
        result = await dungeon_play(io, name, cls, a, dg, partners, key=key, difficulty=diff, title='%s at difficulty %d' % (dg.get('title') or 'dungeon', diff))
    finally:
        DUNGEON_BUSY.pop(dg['id'], None)
        if result is not None and result.status == PASS:
            DUNGEON_DIFF_DONE[diff] = name
        for p in list(partners):
            DUNGEON_MEMBERS.pop(p, None)
            await io.party('leave', p)
        io.raid_mode([name] + partners, False)
    return result


def weekly_board_problem(w, when):
    """the text of a Weekly Challenge board that lists a tester, else None: w is the `weekly` part of `!tester dungeon weekly`"""
    if isinstance(w, dict) and int(w.get('testersListed') or 0) > 0:
        return 'the Weekly Challenge boards list %s tester(s) %s (a tester run is never ranked)' % (w['testersListed'], when)
    return None


async def check_weekly_challenge(io, name, cls, level):
    """the Weekly Challenge dungeon: asks for another difficulty, the run is at the fixed one, a tester is on neither board before or after"""
    key = 'weekly_challenge'
    if name in DUNGEON_MEMBERS:
        return Result(key, name, cls, SKIP, 'played as the member of the party of %s (its result is the party\'s)' % DUNGEON_MEMBERS[name])
    a = await io.helper('dungeon state', 'dungeon', ANSWER)
    no = dungeon_refusal(a, level)
    if no:
        return Result(key, name, cls, no[0], no[1])
    dg = next((d for d in a.get('list') or [] if isinstance(d, dict) and d.get('weekly') and isinstance(d.get('id'), int)), None)
    if dg is None:
        return Result(key, name, cls, SKIP, 'no Weekly Challenge in the dungeon list (not built this week)')
    have = int(a.get('level') or level or 0)
    if have < int(dg.get('level') or 0):
        return Result(key, name, cls, SKIP, 'level %d: the Weekly Challenge needs level %s' % (have, dg.get('level')))
    if dg['id'] in DUNGEON_BUSY:
        return Result(key, name, cls, SKIP, 'another bot plays the Weekly Challenge now (%s)' % DUNGEON_BUSY[dg['id']])
    w0 = await io.helper('dungeon weekly', 'dungeon', ANSWER)
    w = (w0 or {}).get('weekly') if isinstance(w0, dict) else None
    if not isinstance(w, dict):
        return Result(key, name, cls, SKIP, 'no answer to !tester dungeon weekly (old helper file)')
    if not w.get('current'):
        return Result(key, name, cls, SKIP, 'the Weekly Challenge layout is not this week\'s (built %s)' % w.get('built'))
    bad = weekly_board_problem(w, 'before the run')
    if bad:
        return Result(key, name, cls, FAIL, bad)
    DUNGEON_BUSY[dg['id']] = name
    partners = []
    result = None
    try:
        result = await dungeon_play(io, name, cls, a, dg, partners, key=key, difficulty=WEEKLY_ASK, title='Weekly Challenge %s (%s)' % (w.get('built'), w.get('theme')))
    finally:
        DUNGEON_BUSY.pop(dg['id'], None)
        for p in list(partners):
            DUNGEON_MEMBERS.pop(p, None)
            await io.party('leave', p)
        io.raid_mode([name] + partners, False)
    if result is not None and result.status != SKIP:
        w1 = await io.helper('dungeon weekly', 'dungeon', ANSWER)
        bad = weekly_board_problem((w1 or {}).get('weekly') if isinstance(w1, dict) else None, 'after the run')
        if bad:
            return Result(key, name, cls, FAIL, bad, result.fallbacks)
    return result


# ------------------------------------------------------------------------------------------------ the group queue and the party finder (O589)
# Two checks of closed mode, both with two bots that form a group the way people do: through the windows. The server keeps them apart
# from the players (a group or a listing has a side, the modes pair by side); the live rules are asked by closed_guards.
GQ_WAIT = 45.0     # seconds from the join to a run of the group (a ready check and the dungeon's next tick)
GQ_LOOK = 1.0      # seconds between two looks
PF_ROLES = ('tank', 'healer', 'dps', 'support')


def groupqueue_pick(listing, have, taken):
    """the dungeon of a group of two: the highest one both bots may enter that no bot plays now. -> dict or None"""
    sized = [d for d in listing or [] if isinstance(d, dict) and isinstance(d.get('id'), int) and int(d.get('size') or 1) >= 2
             and int(d.get('level') or 0) <= have and d['id'] not in taken]
    return max(sized, key=lambda d: (int(d.get('level') or 0), -d['id'])) if sized else None


def groupqueue_text(reply):
    return str(((reply or {}).get('data') or {}).get('text') or '')[:90]


def groupqueue_refusal(text):
    """(status, text) of a join the Group Queue refused: a closed-mode text with the mode on is a bug, the rest is the state of the world"""
    if 'Closed test mode is off' in text or 'never mixed' in text:
        return FAIL, 'the Group Queue refused a party of testers with the mode on: %s' % text
    return SKIP, 'the Group Queue did not take the party: %s' % (text or 'no reason')


async def check_closed_groupqueue(io, name, cls, level):
    """two testers form a party, join a dungeon through the Group Queue, both accept the ready check, and the run of the testers starts"""
    key = 'closed_groupqueue'
    a = await io.helper('dungeon state', 'dungeon', ANSWER)
    no = dungeon_refusal(a, level)
    if no:
        return Result(key, name, cls, no[0], no[1])
    two = [int(d.get('level') or 0) for d in a['list'] if isinstance(d, dict) and int(d.get('size') or 1) >= 2]
    if not two:
        return Result(key, name, cls, SKIP, 'no dungeon takes a group of two')
    if int(a.get('level') or level or 0) < min(two):
        return Result(key, name, cls, SKIP, 'level %d: the lowest dungeon for two needs level %d' % (int(a.get('level') or level or 0), min(two)))
    other = await io.partner(min_level=min(two))
    if not other:
        return Result(key, name, cls, SKIP, 'no free bot of level %d in game' % min(two))
    try:
        return await groupqueue_play(io, name, cls, a, other)
    finally:
        await io.party('leave', other)


async def groupqueue_play(io, name, cls, a, other):
    key = 'closed_groupqueue'
    b = await io.helper_of(other, 'dungeon state', 'dungeon', ANSWER)
    no = dungeon_refusal(b, 0)
    if no:
        return Result(key, name, cls, SKIP, 'the partner %s: %s' % (other, no[1]))
    have = min(int(a.get('level') or 0), int(b.get('level') or 0))
    dg = groupqueue_pick(a['list'], have, set(DUNGEON_BUSY))
    if dg is None:
        return Result(key, name, cls, SKIP, 'no dungeon for two at level %d that no bot plays now' % have)
    DUNGEON_BUSY[dg['id']] = name
    try:
        if not await io.go('town') or not await io.go_of(other, 'town'):
            return Result(key, name, cls, SKIP, 'the helper did not bring both bots to the temple')
        await io.sleep(SETTLE)
        if not await io.party('form', other):
            return Result(key, name, cls, SKIP, 'the invite could not be sent')
        await io.sleep(SETTLE)
        window = await io.request('groupQueue', 'open', {}, ['state'], ANSWER)
        if window is None:
            return Result(key, name, cls, SKIP, 'no answer from the Group Queue window (not installed)')
        join = await io.request('groupQueue', 'join', {'dungeon': {'id': dg['id'], 'difficulty': 1}}, ['state', 'msg'], ANSWER)
        if join is not None and join.get('action') == 'msg':
            no = groupqueue_refusal(groupqueue_text(join))
            return Result(key, name, cls, no[0], no[1])
        saw_check, answered, run, waited = False, set(), None, 0.0
        while waited <= GQ_WAIT and io.alive():
            st = await io.request('groupQueue', 'query', {}, ['state'], ANSWER)
            group = ((st or {}).get('data') or {}).get('group') or {}
            check = group.get('check')
            if isinstance(check, dict):
                saw_check = True
                for who in (name, other):
                    if who in answered:
                        continue
                    answered.add(who)
                    await (io.request('groupQueue', 'accept', {}, ['state', 'checkEnd'], ANSWER) if who == name
                           else io.request_of(other, 'groupQueue', 'accept', {}, ['state', 'checkEnd'], ANSWER))
            la = await io.helper('dungeon state', 'dungeon', ANSWER)
            if isinstance(la, dict) and la.get('inside'):
                run = la
                break
            await io.sleep(GQ_LOOK)
            waited += GQ_LOOK
        if run is None:
            await io.request('groupQueue', 'leave', {}, ['state', 'msg'], ANSWER)
            why = 'the ready check was accepted by both' if len(answered) == 2 else 'no ready check came'
            return Result(key, name, cls, SKIP, 'no run in %d s (%s; a run of players ahead of the testers?)' % (int(GQ_WAIT), why))
        lb = await io.helper_of(other, 'dungeon state', 'dungeon', ANSWER)
        r = (run.get('run') or {})
        problems = dungeon_problems(run, 2)
        if int(r.get('members') or 0) < 2 or not (isinstance(lb, dict) and lb.get('inside')):
            problems.append('the party of two started with %s member(s) inside' % r.get('members'))
        if not saw_check:
            problems.append('the party was started without a ready check')
        await io.helper('dungeon close', 'dungeon', ANSWER)
        after = await io.helper('dungeon state', 'dungeon', ANSWER)
        if isinstance(after, dict) and after.get('inside'):
            problems.append('the bot is still inside the dungeon after the close')
        if problems:
            return Result(key, name, cls, FAIL, '; '.join(problems[:3]))
        return Result(key, name, cls, PASS, 'party of 2 in the Group Queue for %s: ready check accepted by both, a run of the testers started (%d s)'
                      % (dg.get('title') or dg['id'], int(waited)))
    finally:
        DUNGEON_BUSY.pop(dg['id'], None)


def pf_pick_activity(init):
    """(activity dict, None) the listing is made for: the first activity that needs no title; else the first. (None, text) when none"""
    acts = [x for x in ((init or {}).get('acts') or []) if isinstance(x, dict) and x.get('k')]
    if not acts:
        return None, 'the window lists no activity'
    plain = [x for x in acts if not x.get('title')]
    return (plain or acts)[0], None


def pf_listing(act, role, want, init):
    """the data of a `post` request for one wanted slot of `want`"""
    d = {'a': act['k'], 'want': {want: 1}, 'minLevel': 1, 'role': role, 'exp': int((init or {}).get('defExp') or 30), 'nk': 0}
    if isinstance(act.get('range'), dict):
        d['lo'] = d['hi'] = int(act['range'].get('min') or 1)
    if act.get('targets'):
        d['t'] = 1
    if act.get('title'):
        d['title'] = 'Tester group'
    return d


def pf_roles(init):
    return [r for r in ((init or {}).get('my') or []) if r in PF_ROLES]


async def check_closed_party_finder(io, name, cls, level):
    """a tester lists a group in the Party Finder, another tester finds it, applies, is accepted by the leader and joins the party"""
    key = 'closed_party_finder'
    other = await io.partner()
    if not other:
        return Result(key, name, cls, SKIP, 'no free bot in game')
    listed = None
    try:
        init = await io.request('partyFinder', 'open', {}, ['init'], ANSWER)
        init_b = await io.request_of(other, 'partyFinder', 'open', {}, ['init'], ANSWER)
        if init is None or init_b is None:
            return Result(key, name, cls, SKIP, 'no answer from the Party Finder window (not installed)')
        a_init, b_init = init.get('data') or {}, init_b.get('data') or {}
        mine, theirs = pf_roles(a_init), pf_roles(b_init)
        if not mine or not theirs:
            return Result(key, name, cls, SKIP, 'no role either bot can fill')
        act, why = pf_pick_activity(a_init)
        if act is None:
            return Result(key, name, cls, SKIP, why)
        post = await io.request('partyFinder', 'post', pf_listing(act, mine[0], theirs[0], a_init), ['list', 'notice'], ANSWER)
        text = str(((post or {}).get('data') or {}).get('text') or '')
        if post is None:
            return Result(key, name, cls, SKIP, 'no answer to the listing')
        if post.get('action') == 'notice':
            if 'Closed test mode is off' in text or 'never mixed' in text:
                return Result(key, name, cls, FAIL, 'the Party Finder refused a tester with the mode on: %s' % text[:80])
            return Result(key, name, cls, SKIP, 'the listing was refused: %s' % text[:80])
        mine_row = (post.get('data') or {}).get('mine') or {}
        listed = mine_row.get('id')
        if listed is None:
            return Result(key, name, cls, SKIP, 'the answer to the listing holds no listing of the bot')
        seen = await io.request_of(other, 'partyFinder', 'refresh', {}, ['list'], ANSWER)
        rows = ((seen or {}).get('data') or {}).get('rows') or []
        row = next((r for r in rows if isinstance(r, dict) and r.get('id') == listed), None)
        if row is None:
            return Result(key, name, cls, FAIL, 'a tester\'s listing is not in another tester\'s Party Finder (%d rows)' % len(rows))
        await io.request_of(other, 'partyFinder', 'apply', {'id': listed, 'role': theirs[0]}, ['notice', 'list'], ANSWER)
        look = await io.request('partyFinder', 'refresh', {}, ['list'], ANSWER)
        apps = (((look or {}).get('data') or {}).get('mine') or {}).get('apps') or []
        app = next((x for x in apps if isinstance(x, dict) and x.get('n') == other), None)
        if app is None:
            return Result(key, name, cls, FAIL, '%s applied to the listing, the leader sees %d application(s) and not it' % (other, len(apps)))
        await io.request('partyFinder', 'accept', {'id': listed, 'g': app.get('g')}, ['list', 'notice'], ANSWER)
        await io.sleep(SETTLE)
        if not await io.party('join', other):
            return Result(key, name, cls, SKIP, 'the bots could not join the party of the invite')
        await io.sleep(SETTLE)
        p = await io.helper('party', 'party', ANSWER)
        if not p or p.get('err'):
            return Result(key, name, cls, SKIP, 'no answer to !tester party')
        if int(p.get('size') or 0) < 2:
            if not partner_kept(io, other):
                return Result(key, name, cls, SKIP, PARTNER_GONE)
            return Result(key, name, cls, FAIL, 'the leader accepted %s through the finder, the party has %s member(s)' % (other, p.get('size')))
        return Result(key, name, cls, PASS, 'listed (%s), found by %s, applied, accepted, joined: party of %s among testers' % (
            act.get('n') or act['k'], other, p.get('size')))
    finally:
        if listed is not None:
            await io.request('partyFinder', 'unlist', {'id': listed}, ['list', 'notice'], ANSWER)
        await io.party('leave', other)


# ------------------------------------------------------------------------------------------------ the siege and the guild boss, played (O592)
# Two checks of closed mode that play content the way a person does. The server keeps the testers' own side apart from the players (the
# siege has a side of its own, the guild boss a tester guild with a free hall and a small stone, the boards hide tester guilds); the helper
# only reads (`!tester siege`, `!tester guildboss`: what a person sees on the screen) and gives the engine path to the next goal, the
# walk, the donation, the summon and the fights are the bot's own.
SIEGE_BUDGET = 220.0      # seconds a siege is played at most (the testers' siege lasts a gather and a match: siege_config.lua `tester`)
SIEGE_STEPS = 6           # steps between two looks
SIEGE_HOLD_FIRST = 3      # points the first guild holds the obelisk alone before the rival walks to it: then the point must be contested
SIEGE_CONTEST_LOOKS = 4   # looks with both guilds on the point in which the server must call it contested
SIEGE_STUCK = 30.0        # seconds on one tile with a goal elsewhere: the walk is blocked there
SIEGE_MISSES = 6          # looks without an answer in a row
SIEGE_IN_WAIT = 4.0       # seconds from the step onto the portal to the look inside
SIEGE_TURN = {'by': None, 'members': {}}   # one siege check at a time: the leader that runs it and the rival leader it plays with


def reset_siege_turn():
    SIEGE_TURN['by'] = None
    SIEGE_TURN['members'].clear()


def siege_refusal(a, who='the bot'):
    """(status, text) when this bot must not play the siege, else None: from its `!tester siege` answer"""
    if not isinstance(a, dict):
        return SKIP, 'no answer to !tester siege (old helper file)'
    if a.get('err'):
        return SKIP, str(a['err'])[:80]
    if not a.get('on'):
        return SKIP, 'the closed mode switch reads off'
    if a.get('running'):
        return SKIP, 'a siege is running already'
    if a.get('inside'):
        return SKIP, '%s is inside a siege already' % who
    if not a.get('guild'):
        return SKIP, '%s is in no tester guild' % who
    if int(a.get('level') or 0) < int(a.get('minLevel') or 0):
        return SKIP, '%s is level %s, the siege needs %s' % (who, a.get('level'), a.get('minLevel'))
    return None


def siege_problems(a):
    """[text] for one inside-the-siege answer: whatever says it is not the testers' own"""
    if not isinstance(a, dict) or not a.get('inside'):
        return []
    if a.get('side') != 'tester':
        return ['a tester is inside a %s siege (it must be the testers\' own)' % a.get('side')]
    return []


def siege_verdict(t):
    """(status, text) from the trace of a played siege: faults, both (both bots inside at once), score (the runner guild's best), held
    (looks the runner held the point alone), contested (the server called a tie contested), contest_looks, came, secs, fallbacks, stuck,
    left, guild, rival"""
    if t.get('faults'):
        return FAIL, '; '.join(t['faults'][:3])
    if not t.get('both'):
        return SKIP, 'the two bots were never inside the siege together'
    if t.get('stuck'):
        return SKIP, 'the walk was blocked at (%d, %d) for %d s' % (t['stuck'][0], t['stuck'][1], SIEGE_STUCK)
    how = '%s on foot, %d step(s) in %d s' % ('came' if t.get('came') == 'foot' else 'came by a helper teleport next to the portal, then',
                                             t.get('steps', 0), t.get('secs', 0))
    if t.get('fallbacks'):
        how += '; teleport in place of walking: ' + ', '.join(t['fallbacks'])
    if t.get('score', 0) > 0 and t.get('contested'):
        return PASS, '%s held the Chaos Obelisk for %d point(s); with %s on it too the server called it contested; closed (%s)' % (
            t.get('guild'), t['score'], t.get('rival'), how)
    if t.get('held', 0) >= 8 and t.get('score', 0) <= 0:
        return FAIL, 'held the obelisk alone for %d looks and the guild scored 0' % t['held']
    if t.get('score', 0) > 0:
        return SKIP, 'the guild scored %d but the rival never stood on the obelisk with it (%s)' % (t['score'], how)
    return SKIP, 'the bots never reached the obelisk in %d s (%s)' % (t.get('secs', 0), how)


async def check_closed_siege(io, name, cls, level):
    """the leader of one tester guild and the leader of the other: the helper starts the testers' own siege, both walk to the portal,
    through the base's gate to the obelisk; the first holds it alone (it scores), the second comes and the point is contested"""
    key = 'closed_siege'
    if name in SIEGE_TURN['members']:
        return Result(key, name, cls, SKIP, 'played as the rival leader of %s (its result is the siege\'s)' % SIEGE_TURN['members'][name])
    plan = io.closed_plan()
    if not plan:
        return Result(key, name, cls, SKIP, 'this bot has no tester guild (too few bots for two guilds)')
    if not plan.get('leader'):
        return Result(key, name, cls, SKIP, 'not the leader of its guild')
    rival = io.online(plan.get('rival_leader'))
    if not rival:
        return Result(key, name, cls, SKIP, 'the leader of %s is not in game' % plan.get('rival'))
    if SIEGE_TURN['by'] not in (None, name):
        return Result(key, name, cls, SKIP, 'the siege is played by %s' % SIEGE_TURN['by'])
    SIEGE_TURN['by'] = name
    SIEGE_TURN['members'][rival] = name
    try:
        return await siege_play(io, name, cls, rival, plan)
    finally:
        io.raid_mode([name, rival], False)


async def siege_play(io, name, cls, rival, plan):
    key = 'closed_siege'
    squad = [{'name': name, 'lead': True, 'walker': RaidWalker(), 'inside': False},
             {'name': rival, 'lead': False, 'walker': RaidWalker(), 'inside': False}]
    a = await io.helper('siege state', 'siege', ANSWER)
    no = siege_refusal(a)
    if no:
        return Result(key, name, cls, no[0], no[1])
    b = await io.helper_of(rival, 'siege state', 'siege', ANSWER)
    no = siege_refusal(b, 'the rival leader')
    if no:
        return Result(key, name, cls, no[0], no[1])
    io.raid_mode([name, rival], True)
    for r in squad:
        if not (await io.go('town') if r['lead'] else await io.go_of(r['name'], 'town')):
            return Result(key, name, cls, SKIP, 'the helper did not bring the bot to the temple')
    await io.sleep(SETTLE)
    started = await io.helper('siege start', 'siege', HELPER_WAIT)
    if not isinstance(started, dict):
        return Result(key, name, cls, SKIP, 'no answer to !tester siege start')
    if started.get('err') or not started.get('started'):
        return Result(key, name, cls, SKIP, 'the testers\' siege did not start: %s' % str(started.get('why') or started.get('err'))[:90])
    fallbacks, came = [], {}
    trace = {'faults': [], 'steps': 0, 'both': False, 'inside': 0, 'score': 0, 'held': 0, 'contested': False, 'contest_looks': 0,
             'stuck': None, 'secs': 0, 'left': '?', 'guild': plan.get('guild'), 'rival': plan.get('rival'), 'fallbacks': fallbacks,
             'came': 'foot'}
    try:
        for r in squad:
            how, got = await walk_by_path(io, r, 'siege path', 'siege', near=1)
            came[r['name']] = how
            if how != 'foot':
                why = (got or {}).get('err') or 'the walk did not arrive'
                moved = await hcmd(io, r, 'siege portal', 'siege', HELPER_WAIT)
                if not isinstance(moved, dict) or moved.get('err'):
                    return Result(key, name, cls, SKIP, 'no way to the siege portal: %s; the teleport: %s' % (
                        str(why)[:50], str((moved or {}).get('err') or 'no answer')[:40]), fallbacks)
                fallbacks.append(fallback_note('siege portal', why))
                trace['came'] = 'helper'
                got = await hcmd(io, r, 'siege path', 'siege')
            for attempt in range(2):   # the last step is onto the portal tile, as a person's
                here, dest = (got or {}).get('pos'), (got or {}).get('dest')
                for step in raid_plan(here, dest, 1):
                    await raid_walk(io, r, step)
                await io.sleep(SIEGE_IN_WAIT)
                look = await hcmd(io, r, 'siege state', 'siege')
                r['inside'] = bool(isinstance(look, dict) and look.get('inside'))
                if r['inside']:
                    break
                got = await hcmd(io, r, 'siege path', 'siege')
            if not r['inside']:
                trace['faults'].append('the siege portal did not take %s, a member of the tester guild it was started for' % r['name'])
                return Result(key, name, cls, FAIL, trace['faults'][0], fallbacks)
        trace['inside'] = 2
        return await siege_walk_all(io, name, cls, squad, trace)
    finally:
        closed = await io.helper('siege close', 'siege', ANSWER)   # standings and rewards of the testers, nothing stored
        trace['closed'] = bool(isinstance(closed, dict) and closed.get('closed'))


async def siege_walk_all(io, name, cls, squad, trace):
    key = 'closed_siege'
    rival = squad[1]['name']
    elapsed, misses = 0.0, 0
    while io.alive() and elapsed < SIEGE_BUDGET:
        looks = {}
        for r in squad:
            looks[r['name']] = await hcmd(io, r, 'siege state', 'siege')
        lead, riv = looks.get(name), looks.get(rival)
        if not isinstance(lead, dict):
            misses += 1
            if misses >= SIEGE_MISSES:
                trace['left'] = 'no answer from the helper'
                break
            await io.sleep(RAID_LOOK)
            elapsed += RAID_LOOK
            continue
        misses = 0
        for s in (lead, riv):
            for p in siege_problems(s):
                if p not in trace['faults']:
                    trace['faults'].append(p)
        if trace['faults']:
            break
        if not lead.get('running') or not lead.get('inside'):
            trace['left'] = 'the siege ended by itself'
            break
        trace['both'] = trace['both'] or bool(isinstance(riv, dict) and riv.get('inside'))
        team = lead.get('team') or {}
        trace['score'] = max(trace['score'], int(team.get('score') or 0))
        riv_on = bool(isinstance(riv, dict) and riv.get('onPoint'))
        if lead.get('onPoint') and not riv_on:
            trace['held'] += 1
        if lead.get('onPoint') and riv_on:
            trace['contest_looks'] += 1
            if lead.get('contested'):
                trace['contested'] = True
            if trace['contest_looks'] >= SIEGE_CONTEST_LOOKS and not trace['contested']:
                trace['faults'].append('both guilds stood on the obelisk for %d looks and the server never called it contested' %
                                       trace['contest_looks'])
                break
        if trace['contested'] and trace['score'] > 0 and trace['contest_looks'] >= SIEGE_CONTEST_LOOKS:
            trace['left'] = 'closed by the check (the point was contested)'
            break
        sent = {}
        for r in squad:
            s = looks.get(r['name'])
            if not isinstance(s, dict) or not s.get('inside'):
                continue
            g = s.get('guide') or {}
            # the second guild waits in its base until the first one scored: then it comes and the point must be contested
            waits = (not r['lead']) and not (trace['score'] >= SIEGE_HOLD_FIRST or elapsed > SIEGE_BUDGET * 0.55)
            if g.get('mode') == 'walk' and isinstance(g.get('goal'), dict) and not (waits and g.get('area') == 'obelisk'):
                plan = r['walker'].steps(s['pos'], g['goal'], SIEGE_STEPS, elapsed)
                if not r['walker'].blocked:   # the engine's path first (walls, the gate); the side step only when the way is blocked
                    got = await hcmd(io, r, 'siege path', 'siege')
                    steps = raid_path_steps((got or {}).get('path')) if isinstance(got, dict) and not got.get('err') else []
                    plan = steps[:SIEGE_STEPS] or plan
                sent[r['name']] = plan
                if r['lead'] and r['walker'].stuck(elapsed) >= SIEGE_STUCK:
                    trace['stuck'] = (s['pos']['x'], s['pos']['y'])
        if trace['stuck']:
            break
        for i in range(SIEGE_STEPS):
            moved = False
            for r in squad:
                plan = sent.get(r['name']) or []
                if i < len(plan):
                    await raid_walk(io, r, plan[i])
                    trace['steps'] += 1
                    moved = True
            if not moved:
                break
            await io.sleep(RAID_STEP)
            elapsed += RAID_STEP
        await io.sleep(RAID_LOOK)
        elapsed += RAID_LOOK
        trace['secs'] = int(elapsed)
    trace['secs'] = int(elapsed)
    status, text = siege_verdict(trace)
    return Result(key, name, cls, status, text, trace.get('fallbacks'))


GB_BUDGET = 480.0       # seconds a guild boss run is played at most (the boss's own limit is 13 minutes)
GB_BOSS_WAIT = 45.0     # seconds from the summon to the boss
GB_ENTER_WAIT = 30.0    # seconds from the summon to standing in the arena
GB_FIGHT_MIN = 150.0    # seconds at the boss without taking any of its health: damage, targets or the boss
GB_STUCK = 30.0
GB_STEPS = 6
GB_MISSES = 6
GB_ACT_GAP = 1.3        # seconds between two requests of the stone (guildboss.lua rate limit: one a second)

def guildboss_refusal(a):
    """(status, text) when this bot must not play the guild boss, else None: from its `!tester guildboss` answer"""
    if not isinstance(a, dict):
        return SKIP, 'no answer to !tester guildboss (old helper file)'
    if a.get('err'):
        return SKIP, str(a['err'])[:80]
    if not a.get('on'):
        return SKIP, 'the closed mode switch reads off'
    if a.get('inside'):
        return SKIP, 'the bot is inside a guild boss arena already'
    if not a.get('guild'):
        return SKIP, 'the bot is in no tester guild'
    if int(a.get('rank') or 0) < 2:
        return SKIP, 'not a leader or vice-leader of its guild'
    if int(a.get('level') or 0) < int(a.get('minLevel') or 0):
        return SKIP, 'level %s, the guild boss needs %s' % (a.get('level'), a.get('minLevel'))
    if a.get('killed'):
        return SKIP, 'the guild slew the guild boss this week already'
    if a.get('running'):
        return SKIP, 'the guild is fighting the guild boss already'
    return None


def guildboss_problems(a):
    """[text] for one `!tester guildboss` answer: whatever says a tester meets players' content"""
    out = []
    if not isinstance(a, dict):
        return out
    if a.get('guild') and a.get('side') not in (None, 'tester'):
        out.append('the tester\'s guild %s has side %s' % (a.get('guild'), a.get('side')))
    for g in a.get('board') or []:
        if not str(g).startswith('Tester '):
            out.append('the board a tester sees lists the guild %s (a guild of players)' % str(g)[:40])
    r = a.get('run')
    if isinstance(r, dict) and r.get('tester') is False:
        out.append('a tester is in a guild boss run of players')
    return out


def guildboss_verdict(t):
    """(status, text) from the trace of a played run: faults, boss_seen, hp (lowest health percent of the boss seen), won, stuck, died,
    fought (seconds at the boss without damage), secs, fuel, need, came, fallbacks, left"""
    if t.get('faults'):
        return FAIL, '; '.join(t['faults'][:3])
    how = 'free hall, %s of %s embers from an Orb of Upheaval, summoned' % (t.get('fuel'), t.get('need'))
    if t.get('came') != 'foot':
        how += ' (the hall by the portal\'s own entry)'
    if t.get('fallbacks'):
        how += '; teleport in place of walking: ' + ', '.join(t['fallbacks'])
    if not t.get('boss_seen'):
        if t.get('died') or t.get('left') in ('the run ended', 'the arena closed'):
            return SKIP, 'the run ended before the boss came (%s)' % how
        return FAIL, 'the guild boss did not appear in %d s after the summon (%s)' % (int(GB_BOSS_WAIT), how)
    if t.get('won') or (t.get('hp') is not None and t['hp'] < 100):
        return PASS, 'Gorvath at %s%% health after %d s, %d step(s), left by %s (%s)' % (
            'down: 0' if t.get('won') else t.get('hp'), t.get('secs', 0), t.get('steps', 0), t.get('left', '?'), how)
    if t.get('fought', 0) >= GB_FIGHT_MIN:
        return FAIL, 'fought %d s at the guild boss and took none of its health (damage, targets or the boss)' % t['fought']
    if t.get('stuck'):
        return SKIP, 'the walk was blocked at (%d, %d) for %d s' % (t['stuck'][0], t['stuck'][1], GB_STUCK)
    if t.get('died'):
        return SKIP, 'the bot died before it hurt the boss (level %s against Gorvath)' % t.get('level', '?')
    return SKIP, 'the boss was not hurt in %d s' % t.get('secs', 0)


async def check_closed_guildboss(io, name, cls, level):
    """the leader of a tester guild buys its free hall (the guild window), walks into it by the portal, feeds the Summoning Stone one Orb of
    Upheaval, summons Gorvath and walks into the arena and fights him; the board it reads shows tester guilds only; the run is closed"""
    key = 'closed_guildboss'
    a = await io.helper('guildboss state', 'guildboss', ANSWER)
    no = guildboss_refusal(a)
    if no:
        return Result(key, name, cls, no[0], no[1])
    bad = guildboss_problems(a)
    if bad:
        return Result(key, name, cls, FAIL, '; '.join(bad[:3]))
    io.raid_mode([name], True)
    try:
        return await guildboss_play(io, name, cls, a)
    finally:
        await io.helper('guildboss close', 'guildboss', ANSWER)
        io.raid_mode([name], False)


def window_text(reply):
    d = (reply or {}).get('data') if isinstance(reply, dict) else None
    return str((d or {}).get('text') or '')[:90]


async def guildboss_play(io, name, cls, a):
    key = 'closed_guildboss'
    r = {'name': name, 'lead': True, 'walker': RaidWalker(), 'inside': False}
    fallbacks = []
    trace = {'faults': [], 'steps': 0, 'boss_seen': False, 'hp': None, 'won': False, 'stuck': None, 'died': False, 'fought': 0.0, 'secs': 0,
             'left': '?', 'fuel': a.get('fuel'), 'need': a.get('need'), 'came': 'foot', 'fallbacks': fallbacks, 'level': a.get('level')}
    # 1. the hall: free for a tester guild, bought from the guild window like a player's
    if not a.get('hasHall'):
        reply = await io.request('guild', 'buyHall', {'from': 'bank'}, ['message'], ANSWER)
        if reply is None:
            return Result(key, name, cls, SKIP, 'no answer from the guild window (not installed)')
        await io.sleep(SETTLE)
        a = await io.helper('guildboss state', 'guildboss', ANSWER)
        if not (isinstance(a, dict) and a.get('hasHall')):
            return Result(key, name, cls, FAIL, 'the leader of a tester guild could not buy its free hall: %s' % (window_text(reply) or 'no text'))
    # 2. on foot from the temple to the Guild Hall Portal, and in (the portal's own entry is the counted fallback)
    if not a.get('inHall'):
        if not await io.go('town'):
            return Result(key, name, cls, SKIP, 'the helper did not bring the bot to the temple')
        await io.sleep(SETTLE)
        how, got = await walk_by_path(io, r, 'guildboss path', 'guildboss', near=1)
        if how == 'foot':
            here, dest = (got or {}).get('pos'), (got or {}).get('dest')
            for step in raid_plan(here, dest, 1):
                await raid_walk(io, r, step)
            await io.sleep(SIEGE_IN_WAIT)
        look = await io.helper('guildboss state', 'guildboss', ANSWER)
        if not (isinstance(look, dict) and look.get('inHall')):
            why = (got or {}).get('err') or 'the walk did not arrive'
            moved = await io.helper('guildboss hall', 'guildboss', HELPER_WAIT)
            if not isinstance(moved, dict) or moved.get('err') or not moved.get('inHall'):
                return Result(key, name, cls, SKIP, 'no way into the guild hall: %s; the portal\'s entry: %s' % (
                    str(why)[:50], str((moved or {}).get('err') or 'not in the hall')[:40]), fallbacks)
            fallbacks.append(fallback_note('guildboss hall', why))
            trace['came'] = 'helper'
    # 3. to the stone, the window, the stone's fuel
    how, _ = await walk_by_path(io, r, 'guildboss path', 'guildboss', near=1)
    await io.request('guildWar', 'open', {'tab': 'boss'}, ['state'], ANSWER)
    a = await io.helper('guildboss state', 'guildboss', ANSWER)
    if not isinstance(a, dict) or a.get('err'):
        return Result(key, name, cls, SKIP, 'no state in the hall: %s' % str((a or {}).get('err') or 'no answer')[:60], fallbacks)
    need = int(a.get('need') or 0)
    if int(a.get('fuel') or 0) < need:
        g = await io.helper('give orb chaos 1', 'give', HELPER_WAIT)
        if not isinstance(g, dict) or g.get('err'):
            return Result(key, name, cls, SKIP, 'the helper could not give an Orb of Upheaval: %s' % str((g or {}).get('err') or 'no answer')[:60], fallbacks)
        await io.sleep(GB_ACT_GAP)
        reply = await io.request('guildWar', 'bossItem', {'key': 'upheaval'}, ['message'], ANSWER)
        await io.sleep(GB_ACT_GAP)
        a = await io.helper('guildboss state', 'guildboss', ANSWER)
        if not isinstance(a, dict) or int(a.get('fuel') or 0) < need:
            return Result(key, name, cls, FAIL, 'fed the stone an Orb of Upheaval (5 embers) and it holds %s of %s: %s' % (
                (a or {}).get('fuel'), need, window_text(reply) or 'no text'), fallbacks)
    trace['fuel'], trace['need'] = a.get('fuel'), a.get('need')
    bad = guildboss_problems(a)
    if bad:
        return Result(key, name, cls, FAIL, '; '.join(bad[:3]), fallbacks)
    if not a.get('canSummon'):
        why = str(a.get('reason') or 'no reason')[:80]
        return Result(key, name, cls, FAIL if 'embers' in why else SKIP, 'the stone is full and the summon is not open: %s' % why, fallbacks)
    # 4. the summon and into the arena
    await io.sleep(GB_ACT_GAP)
    reply = await io.request('guildWar', 'bossSummon', {}, ['message'], ANSWER)
    waited, state = 0.0, None
    while waited <= GB_ENTER_WAIT and io.alive():
        state = await io.helper('guildboss state', 'guildboss', ANSWER)
        if isinstance(state, dict) and state.get('inside'):
            break
        await io.sleep(1.0)
        waited += 1.0
    if not (isinstance(state, dict) and state.get('inside')):
        text = window_text(reply)
        if 'kept for the players' in text or 'Closed test mode' in text:
            return Result(key, name, cls, SKIP, 'the summon was refused: %s' % text, fallbacks)
        return Result(key, name, cls, FAIL, 'the summon with a full stone put nobody in the arena in %d s: %s' % (int(GB_ENTER_WAIT), text or 'no text'),
                      fallbacks)
    r['inside'] = True
    return await guildboss_walk(io, name, cls, r, trace)


async def guildboss_walk(io, name, cls, r, trace):
    key = 'closed_guildboss'
    elapsed, misses, since_summon, fight_since, last_hp = 0.0, 0, 0.0, None, None
    while io.alive():
        s = await io.helper('guildboss state', 'guildboss', ANSWER)
        if not isinstance(s, dict):
            misses += 1
            if misses >= GB_MISSES:
                trace['left'] = 'no answer from the helper'
                break
            await io.sleep(RAID_LOOK)
            elapsed += RAID_LOOK
            continue
        misses = 0
        for p in guildboss_problems(s):
            if p not in trace['faults']:
                trace['faults'].append(p)
        if trace['faults']:
            break
        run = s.get('run') or {}
        if not s.get('inside') or run.get('state') not in (None, 'running'):
            trace['left'] = 'the run ended' if not run.get('state') or run.get('state') == 'failed' else 'the kill'
            trace['died'] = not trace['won'] and run.get('state') == 'failed' and not trace['boss_seen']
            break
        if run.get('boss') == 'alive':
            trace['boss_seen'] = True
            hp = run.get('bossHp')
            if hp is not None:
                trace['hp'] = hp if trace['hp'] is None else min(trace['hp'], hp)
        elif run.get('boss') == 'dead':
            trace['won'] = True
            trace['left'] = 'the kill'
            await io.loot()
            break
        if not trace['boss_seen'] and since_summon >= GB_BOSS_WAIT:
            break
        g = s.get('guide') or {}
        hp_now = run.get('bossHp')
        if hp_now != last_hp:
            last_hp, fight_since = hp_now, None
        if g.get('mode') == 'fight':
            fight_since = elapsed if fight_since is None else fight_since
            trace['fought'] = max(trace['fought'], elapsed - fight_since)
        elif g.get('mode') != 'wait':
            fight_since = None
        if elapsed >= GB_BUDGET:
            trace['left'] = 'a close by the helper (the time of the check)'
            break
        plan = []
        if g.get('mode') == 'walk' and isinstance(g.get('goal'), dict):
            plan = r['walker'].steps(s['pos'], g['goal'], GB_STEPS, elapsed)
            if not r['walker'].blocked:   # the engine's path first; the side step only when the way is blocked
                got = await hcmd(io, r, 'guildboss path', 'guildboss')
                steps = raid_path_steps((got or {}).get('path')) if isinstance(got, dict) and not got.get('err') else []
                plan = steps[:GB_STEPS] or plan
            if r['walker'].stuck(elapsed) >= GB_STUCK:
                trace['stuck'] = (s['pos']['x'], s['pos']['y'])
                break
        for step in plan:
            await raid_walk(io, r, step)
            trace['steps'] += 1
            await io.sleep(RAID_STEP)
            elapsed += RAID_STEP
            since_summon += RAID_STEP
        await io.sleep(RAID_LOOK)
        elapsed += RAID_LOOK
        since_summon += RAID_LOOK
        trace['secs'] = int(elapsed)
    trace['secs'] = int(elapsed)
    after = await io.helper('guildboss close', 'guildboss', ANSWER)
    again = await io.helper('guildboss state', 'guildboss', ANSWER)
    if isinstance(again, dict) and again.get('inside'):
        trace['faults'].append('the bot is still inside the guild boss arena after the close')
    status, text = guildboss_verdict(trace)
    return Result(key, name, cls, status, text, trace.get('fallbacks'))


# ------------------------------------------------------------------------------------------------ the rift, walked (O592)
# The bot walks from where it stands to the temple (a rift is opened in a protection zone), takes a key, uses it and plays the rift like a
# person: the guardian when it is up, else the nearest pack monster of its floor, by the engine's own path. The helper only gives the key
# (`!tester rift key`), reads the screen (`rift state`), gives the path (`rift path`) and closes the run; nothing teleports the bot inside.
RIFT_BUDGET = 420.0       # seconds a rift is played at most
RIFT_BUDGET_TWO = 660.0   # a rift of two floors (O651): the guardian is on the last floor, the way there goes through a hole
RIFT_STAIR_LOOKS = 6      # looks next to the hole (or ladder) with the floor unchanged: the stairs do not take the bot (O651)
RIFT_STEPS = 6
RIFT_OPEN_WAIT = 12.0     # seconds from the key to standing in the rift (the hotkey is sent again twice)
RIFT_FIGHT_MIN = 150.0    # seconds at a monster without a kill
RIFT_STUCK = 30.0
RIFT_MISSES = 6


def rift_walk_verdict(t):
    """(status, text) from the trace of a walked rift: faults, kills (kills made), boss_seen, hp (the guardian's lowest health percent), came
    ('foot' / 'helper'), steps, secs, fought, stuck, floor (a goal on another floor: the stairs are not walked), died, tier, theme, fallbacks"""
    if t.get('faults'):
        return FAIL, '; '.join(t['faults'][:3])
    how = 'tier %s %s, %s the temple, %d step(s) in %d s' % (t.get('tier'), t.get('theme') or '?',
                                                           'walked to' if t.get('came') == 'foot' else 'the helper put the bot at', t.get('steps', 0), t.get('secs', 0))
    if t.get('floors', 1) > 1:
        how += ', %d floors, %d floor change(s) (%d down, %d up, %d ladder use(s))' % (t['floors'], t.get('stairs', 0), t.get('down', 0), t.get('up', 0), t.get('uses', 0))
    if t.get('fallbacks'):
        how += '; teleport in place of walking: ' + ', '.join(t['fallbacks'])
    if t.get('floors', 1) > 1 and t.get('links') and not t.get('stairs') and (t.get('kills', 0) > 0 or (t.get('hp') is not None and t['hp'] < 100)):
        return SKIP, 'killed %d in the first floor of a rift of %d floors and the stairs were not walked in %d s (%s)' % (t.get('kills', 0), t['floors'], t.get('secs', 0), how)
    if t.get('kills', 0) > 0 or (t.get('hp') is not None and t['hp'] < 100):
        what = '%d kill(s)' % t.get('kills', 0)
        if t.get('boss_seen'):
            what += ', the guardian at %s%%' % t.get('hp')
        return PASS, '%s (%s)' % (what, how)
    if t.get('fought', 0) >= RIFT_FIGHT_MIN:
        return FAIL, 'fought %d s in the rift and killed none (damage, targets or the monsters)' % t['fought']
    if t.get('floor'):
        return SKIP, 'the next goal is on another floor of the rift and the layout names no stairs towards it (%s)' % how
    if t.get('stuck'):
        return SKIP, 'the walk was blocked at (%d, %d) for %d s (%s)' % (t['stuck'][0], t['stuck'][1], RIFT_STUCK, how)
    if t.get('died'):
        return SKIP, 'the bot died before it killed a monster (level %s against the rift)' % t.get('level', '?')
    return SKIP, 'no monster was killed in %d s (%s)' % (t.get('secs', 0), how)


async def check_rift_walk(io, name, cls, level):
    """walks to the temple, takes a key, opens a rift, walks through it fighting by the engine's path, closes it"""
    key = 'rift_walk'
    a = await io.helper('rift state', 'rift', ANSWER)
    if not isinstance(a, dict):
        return Result(key, name, cls, SKIP, 'no answer to !tester rift (old helper file)')
    if a.get('err'):
        return Result(key, name, cls, SKIP, str(a['err'])[:80])
    if a.get('inside'):
        # O656: the coverage layer (`!tester enter rift`) leaves a bot inside a rift of its own; a person walks out of one he does not play:
        # the bot closes its own run (the helper ends only the asker's run) and looks again
        await io.helper('rift close', 'rift', ANSWER)
        await io.sleep(1.5)
        a = await io.helper('rift state', 'rift', ANSWER) or a
        if a.get('inside'):
            return Result(key, name, cls, SKIP, 'the bot is inside a rift already')
    if not a.get('tier'):
        return Result(key, name, cls, SKIP, 'level %s opens no rift' % a.get('level'))
    r = {'name': name, 'lead': True, 'walker': RaidWalker(), 'inside': False}
    fallbacks = []
    trace = {'faults': [], 'steps': 0, 'kills': 0, 'boss_seen': False, 'hp': None, 'fought': 0.0, 'stuck': None, 'floor': False, 'died': False,
             'secs': 0, 'came': 'foot', 'tier': a.get('tier'), 'theme': None, 'fallbacks': fallbacks, 'level': a.get('level')}
    io.raid_mode([name], True, keep_flee=True)   # no walk back to the hunt, but the bot may still flee like a person
    try:
        if not a.get('pz'):
            how, got, note = await walk_to_place(io, r, 'temple')
            if how not in ('foot', 'helper'):
                return Result(key, name, cls, SKIP, how[:110])
            if note:
                fallbacks.append(note)
                trace['came'] = 'helper'
            await io.sleep(SETTLE)
            a = await io.helper('rift state', 'rift', ANSWER)
            if not (isinstance(a, dict) and a.get('pz')):
                return Result(key, name, cls, SKIP, 'the bot stands at the temple but not in a protection zone: a rift cannot be opened there', fallbacks)
        k = await io.helper(rift_key_command(a.get('level')), 'rift', HELPER_WAIT)   # O661: the tier the level warning allows, as a person picks it
        if not isinstance(k, dict):
            return Result(key, name, cls, SKIP, 'no answer to !tester rift key', fallbacks)
        if k.get('err'):
            return Result(key, name, cls, SKIP, 'rift key: %s' % str(k['err'])[:80], fallbacks)
        if k.get('held') is False:
            if k.get('bagFull'):
                return Result(key, name, cls, SKIP, 'the bag is full: the key went to the inbox (by design)', fallbacks)
            return Result(key, name, cls, FAIL, 'a rift key of tier %s was given, the backpack holds none' % k.get('tier'), fallbacks)
        trace['tier'] = k.get('tier') or trace['tier']
        # the key is used like a hotkey; sent again when nothing happens (the first use may meet an exhaust or a slot being built)
        opened, waited = None, 0.0
        while waited <= RIFT_OPEN_WAIT and io.alive():
            if waited in (0.0, 5.0, 9.0):
                await io.use_item(k.get('keyClientId'))
            await io.sleep(1.0)
            waited += 1.0
            opened = await io.helper('rift state', 'rift', ANSWER)
            if isinstance(opened, dict) and opened.get('inside'):
                break
        if not (isinstance(opened, dict) and opened.get('inside')):
            return Result(key, name, cls, SKIP, 'the rift did not open in %d s (a slot is busy or being built, or the bot is in a fight)' % int(RIFT_OPEN_WAIT),
                          fallbacks)
        return await rift_walk_play(io, name, cls, r, trace)
    finally:
        await io.helper('rift close', 'rift', ANSWER)   # the run closes, a refunded key is taken out of the backpack again
        io.raid_mode([name], False)
        await io.go('hunt')


async def rift_walk_play(io, name, cls, r, trace):
    key = 'rift_walk'
    elapsed, misses, fight_since, last_kills, looted = 0.0, 0, None, None, 0.0
    first_kills = None
    budget = RIFT_BUDGET
    home = home_rule('rift_walk', name, cls, trace.get('level'))   # O659: the way home of a second retreat
    while io.alive() and elapsed < budget:
        s = await io.helper('rift state', 'rift', ANSWER)
        if not isinstance(s, dict):
            misses += 1
            if misses >= RIFT_MISSES:
                break
            await io.sleep(RAID_LOOK)
            elapsed += RAID_LOOK
            continue
        misses = 0
        run = s.get('run') or {}
        if not s.get('inside') or run.get('state') not in (None, 'running'):
            trace['died'] = not trace['kills'] and elapsed < budget and not trace['boss_seen']
            break
        trace['theme'] = run.get('theme') or trace['theme']
        trace['floors'] = int(run.get('floors') or 1)
        if trace['floors'] > 1:
            budget = RIFT_BUDGET_TWO
        trace['links'] = int(run.get('links') or 0)
        z = (s.get('pos') or {}).get('z')
        if trace.get('z') is not None and z is not None and z != trace['z']:   # the hole took the bot down, the ladder up (O651)
            trace['stairs'] = trace.get('stairs', 0) + 1
            trace['down' if z > trace['z'] else 'up'] = trace.get('down' if z > trace['z'] else 'up', 0) + 1
            trace['at_stairs'] = 0
        trace['z'] = z
        killed = int(run.get('killed') or 0)
        first_kills = killed if first_kills is None else first_kills
        trace['kills'] = max(trace['kills'], killed - first_kills)
        if killed != last_kills:
            last_kills, fight_since = killed, None
            if elapsed - looted >= 3.0:   # the corpses of the pack: the bot takes the loot as it does anywhere
                await io.loot()
                looted = elapsed
        if run.get('boss') == 'alive':
            trace['boss_seen'] = True
            hp = run.get('bossHp')
            if hp is not None:
                trace['hp'] = hp if trace['hp'] is None else min(trace['hp'], hp)
        g = s.get('guide') or {}
        spent = await retreat_or_home(io, r, s, trace, g, home)   # O659: the retreat of the rift loop; a second one goes home
        if trace.get('gone'):
            break
        if spent:
            elapsed += spent
            continue
        if g.get('mode') == 'fight':
            fight_since = elapsed if fight_since is None else fight_since
            trace['fought'] = max(trace['fought'], elapsed - fight_since)
        elif g.get('mode') != 'wait':
            fight_since = None
        if trace['kills'] > 0 and trace['boss_seen'] and trace['hp'] is not None and trace['hp'] < 100:
            break   # a pack monster killed and the guardian hurt: the run has been walked through
        if g.get('area') == 'stairs' and isinstance(g.get('goal'), dict) and raid_near(s.get('pos'), g['goal'], 1):
            trace['at_stairs'] = trace.get('at_stairs', 0) + 1
            if trace['at_stairs'] >= RIFT_STAIR_LOOKS:
                trace['faults'].append('stood next to the %s %d looks and the floor did not change (the stairs do not take the bot)' % (
                    'hole' if g.get('via') == 'hole' else 'ladder', trace['at_stairs']))
                break
        elif g.get('area') != 'stairs':
            trace['at_stairs'] = 0
        plan = []
        if g.get('mode') == 'use' and isinstance(g.get('use'), dict):   # the ladder is used like a click on it, from the tile next to it
            u = g['use']
            await io.use_at((u['x'], u['y'], u['z']), u.get('clientId'), u.get('stack', 1))
            trace['uses'] = trace.get('uses', 0) + 1
        elif g.get('mode') == 'walk' and isinstance(g.get('goal'), dict):
            plan = r['walker'].steps(s['pos'], g['goal'], RIFT_STEPS, elapsed)
            if not r['walker'].blocked:   # the engine's path first (walls, doors); the side step only when the way is blocked
                got = await hcmd(io, r, 'rift path', 'rift')
                if isinstance(got, dict) and str(got.get('err')) == 'another floor':
                    trace['floor'] = True
                    break
                steps = raid_path_steps((got or {}).get('path')) if isinstance(got, dict) and not got.get('err') else []
                plan = steps[:RIFT_STEPS] or plan
            if r['walker'].stuck(elapsed) >= RIFT_STUCK:
                trace['stuck'] = (s['pos']['x'], s['pos']['y'])
                break
        elif g.get('mode') == 'wait' and g.get('area') == 'pack' and not trace['kills']:
            trace['floor'] = True   # the monsters left are on another floor
            break
        for step in plan:
            await raid_walk(io, r, step)
            trace['steps'] += 1
            await io.sleep(RAID_STEP)
            elapsed += RAID_STEP
        await io.sleep(RAID_LOOK)
        elapsed += RAID_LOOK
        trace['secs'] = int(elapsed)
    trace['secs'] = int(elapsed)
    status, text = rift_walk_verdict(trace)
    status, text = home_verdict(trace, status, text)   # O659
    return Result(key, name, cls, status, text, trace.get('fallbacks'))


# ------------------------------------------------------------------------------------------------ the Infinity Tower and the Ember Descent, played (O595)
# Solo content, so they are open checks (CHECKS: no closed mode needed): the bot goes to the temple on foot, opens the window's own door
# (`enter` of the tower, `start` of the descent, which pays with the free run of the day or an Ember Sigil the helper gives), and plays the
# run like a person: the nearest monster by the engine's path, its own rotation, loot, the boon choices (the first card), Continue in a room
# of rest, "Next floor now" between floors. The helper reads the screen (`!tester tower | descent state`), gives the path (`path`) and
# closes the bot's own run; nothing teleports the bot inside. A tester run is refused while the halls are the players' (the reserve) and
# is never mixed with a player; no record, board, season chest, title or broadcast is a tester's (server/README.md "Infinity Tower, Ember
# Descent and the trials for the bots (O595)").
TOWER_BUDGET = 540.0      # seconds a tower run is played at most
TOWER_FLOORS = 2          # floors cleared that make a pass (the gold of the second proves the pause and the skip)
DESCENT_BUDGET = 720.0    # seconds a descent is played at most
DESCENT_ROOMS = 2         # rooms cleared that make a pass (a boon choice answered after each)
SOLO_ENTER_WAIT = 14.0    # seconds from the window's request to standing inside (asked again once)
SOLO_STEPS = 6
SOLO_FIGHT_MIN = 150.0    # seconds in reach of a monster with nothing to show
SOLO_STUCK = 30.0
SOLO_MISSES = 6
SOLO_PICK_TRIES = 3       # answers to one boon choice before it counts as refused


def tower_problems(s, trace):
    """[text] for one inside-the-tower answer: a player in the run, a cleared floor whose gold did not reach the bank. Keeps the
    last floor and bank in the trace"""
    out = []
    run = s.get('run') or {}
    if run.get('players') is not None and run.get('testers') is not None and run['players'] != run['testers']:
        out.append('a player is in the tower run of the testers (%s of %s are testers)' % (run['testers'], run['players']))
    cleared, bank, gold = run.get('cleared'), s.get('bank'), s.get('floorGold')
    prev, was = trace.get('cleared_prev'), trace.get('bank_prev')
    if all(isinstance(v, int) for v in (cleared, bank, gold)) and prev is not None and was is not None and cleared > prev:
        want = gold * sum(range(prev + 1, cleared + 1))
        if bank - was < want:
            out.append('floor %d was cleared and the bank rose by %d, the floor gold is %d' % (cleared, bank - was, want))
    if isinstance(cleared, int):
        trace['cleared_prev'] = cleared
        trace['cleared'] = max(trace.get('cleared', 0), cleared)
    if isinstance(bank, int):
        trace['bank_prev'] = bank
    return out


def descent_problems(s, trace):
    out = []
    run = s.get('run') or {}
    if run.get('players') is not None and run.get('testers') is not None and run['players'] != run['testers']:
        out.append('a player is in the descent run of the testers (%s of %s are testers)' % (run['testers'], run['players']))
    if isinstance(run.get('depth'), int):
        trace['depth'] = max(trace.get('depth', 0), run['depth'])
    return out


def solo_text(t, what):
    return 'level %s, %s the temple, %d step(s) in %d s%s' % (
        t.get('level'), 'walked to' if t.get('came') == 'foot' else 'the helper put the bot at', t.get('steps', 0), t.get('secs', 0),
        ('; teleport in place of walking: ' + ', '.join(t['fallbacks'])) if t.get('fallbacks') else '')


def tower_walk_verdict(t):
    """(status, text) from the trace of a walked tower: faults, cleared (floors), skips, fought, stuck, died, came, steps, secs, level, fallbacks"""
    if t.get('faults'):
        return FAIL, '; '.join(t['faults'][:3])
    how = solo_text(t, 'tower')
    if t.get('cleared', 0) >= 1:
        return PASS, '%d floor(s) cleared%s (%s)' % (t['cleared'], ', the next floor called %d time(s)' % t['skips'] if t.get('skips') else '', how)
    if t.get('fought', 0) >= SOLO_FIGHT_MIN:
        return FAIL, 'fought %d s in the tower and cleared no floor (damage, targets or the monsters)' % t['fought']
    if t.get('stuck'):
        return SKIP, 'the walk was blocked at (%d, %d) for %d s (%s)' % (t['stuck'][0], t['stuck'][1], SOLO_STUCK, how)
    if t.get('died'):
        return SKIP, 'the bot fell before a floor was cleared (level %s against floor 1)' % t.get('level', '?')
    return SKIP, 'no floor was cleared in %d s (%s)' % (t.get('secs', 0), how)


def descent_walk_verdict(t):
    """(status, text) from the trace of a walked descent: faults, depth (rooms cleared), picks, rests, fought, stuck, died, came, steps, secs"""
    if t.get('faults'):
        return FAIL, '; '.join(t['faults'][:3])
    how = solo_text(t, 'descent')
    if t.get('depth', 0) >= 1:
        extra = []
        if t.get('picks'):
            extra.append('%d boon choice(s) answered' % t['picks'])
        if t.get('rests'):
            extra.append('%d room(s) of rest left' % t['rests'])
        return PASS, 'room %d cleared%s (%s)' % (t['depth'], (', ' + ', '.join(extra)) if extra else '', how)
    if t.get('fought', 0) >= SOLO_FIGHT_MIN:
        return FAIL, 'fought %d s in the descent and cleared no room (damage, targets or the monsters)' % t['fought']
    if t.get('stuck'):
        return SKIP, 'the walk was blocked at (%d, %d) for %d s (%s)' % (t['stuck'][0], t['stuck'][1], SOLO_STUCK, how)
    if t.get('died'):
        return SKIP, 'the bot fell before a room was cleared (level %s against room 1)' % t.get('level', '?')
    return SKIP, 'no room was cleared in %d s (%s)' % (t.get('secs', 0), how)


def solo_refusal(a, system, what, level=0):
    """(status, text) when this bot must not play the check, else None: from its `!tester tower | descent` answer"""
    if not isinstance(a, dict):
        return SKIP, 'no answer to !tester %s (old helper file)' % system
    if a.get('err'):
        return SKIP, str(a['err'])[:80]
    have, need = int(a.get('level') or level or 0), int(a.get('minLevel') or 0)
    if have < need:
        return SKIP, 'level %d: the %s needs level %d' % (have, what, need)
    if a.get('inside'):
        return SKIP, 'the bot is inside the %s already' % what
    if a.get('free') is not None and a.get('reserve') is not None and int(a['free']) - 1 < int(a['reserve']):
        return SKIP, 'the halls are kept for the players (%s free, %s reserved)' % (a['free'], a['reserve'])
    return None


async def solo_enter(io, r, trace, system, opname, action, data, reply_expect):
    """sends the window's own request, asked again once, until the helper says the bot is inside; -> the last look or None"""
    s, waited = None, 0.0
    while waited <= SOLO_ENTER_WAIT and io.alive():
        if waited in (0.0, 7.0):
            await io.request(opname, action, data, reply_expect, ANSWER)
        await io.sleep(1.0)
        waited += 1.0
        s = await io.helper('%s state' % system, system, ANSWER)
        if isinstance(s, dict) and s.get('inside'):
            return s
    return s


async def solo_play(io, r, trace, c):
    """the play loop of both checks: look every second; answer a boon choice or a room of rest (descent), call the next floor between
    floors (tower), else walk by the engine path to the nearest monster and fight within reach with the bot's own rotation.
    c: system, budget, done(trace), problems(s, trace), mark(s) (what changes while the bot makes progress)"""
    system = c['system']
    elapsed, misses, fight_since, mark, last_skip, tries = 0.0, 0, None, None, -99.0, {}
    while io.alive() and elapsed < c['budget']:
        s = await io.helper('%s state' % system, system, ANSWER)
        if not isinstance(s, dict):
            misses += 1
            if misses >= SOLO_MISSES:
                break
            await io.sleep(RAID_LOOK)
            elapsed += RAID_LOOK
            continue
        misses = 0
        if not s.get('inside'):
            trace['died'] = not c['made'](trace) and elapsed < c['budget']
            break
        for p in c['problems'](s, trace):
            if p not in trace['faults']:
                trace['faults'].append(p)
        if trace['faults'] or c['done'](trace) or (c.get('stop') and c['stop'](s, trace)):
            break
        g = s.get('guide') or {}
        spent = await retreat_check(io, r, s, trace, g)   # O658: under 30 % health the bot heals and steps back before it goes on
        if spent:
            elapsed += spent
            continue
        m = c['mark'](s)
        if m != mark:
            mark, fight_since = m, None
            if mark is not None:
                await io.loot()   # a corpse of the room: the bot takes the loot as it does anywhere
        mode = g.get('mode')
        if mode == 'fight':
            fight_since = elapsed if fight_since is None else fight_since
            trace['fought'] = max(trace['fought'], elapsed - fight_since)
        elif mode != 'wait':
            fight_since = None
        if mode == 'pick':   # the descent's boon choice: the first card, as when the time runs out
            oid = g.get('offer')
            tries[oid] = tries.get(oid, 0) + 1
            if tries[oid] > SOLO_PICK_TRIES:
                trace['faults'].append('the boon choice %s stayed open after %d answers' % (oid, SOLO_PICK_TRIES))
                break
            await io.request('descent', 'pick', {'offer': oid, 'card': g.get('card') or 1, 'curse': False}, ['hud', 'closeOffer'], ANSWER)
            trace['picks'] = trace.get('picks', 0) + 1
        elif mode == 'ready':   # a room of rest: Continue
            await io.request('descent', 'ready', {}, ['hud'], ANSWER)
            trace['rests'] = trace.get('rests', 0) + 1
        elif mode == 'wait' and g.get('skip') and c.get('skip') and elapsed - last_skip >= 3.0 and trace.get('cleared', 0) >= 1:
            last_skip = elapsed   # "Next floor now": the pause between floors is skipped, as a person presses it
            await io.request('infinitytower', 'skip', {}, ['state'], ANSWER)
            trace['skips'] = trace.get('skips', 0) + 1
        plan = []
        if mode == 'walk' and isinstance(g.get('goal'), dict):
            plan = r['walker'].steps(s['pos'], g['goal'], SOLO_STEPS, elapsed)
            if not r['walker'].blocked:   # the engine's path first (walls, pillars); the side step only when the way is blocked
                got = await hcmd(io, r, '%s path' % system, system)
                steps = raid_path_steps((got or {}).get('path')) if isinstance(got, dict) and not got.get('err') else []
                plan = steps[:SOLO_STEPS] or plan
            if r['walker'].stuck(elapsed) >= SOLO_STUCK:
                trace['stuck'] = (s['pos']['x'], s['pos']['y'])
                break
        for step in plan:
            await raid_walk(io, r, step)
            trace['steps'] += 1
            await io.sleep(RAID_STEP)
            elapsed += RAID_STEP
        await io.sleep(RAID_LOOK)
        elapsed += RAID_LOOK
        trace['secs'] = int(elapsed)
    trace['secs'] = int(elapsed)


async def solo_to_temple(io, r, trace, fallbacks, need_pz=False, system=None):
    """on foot to the temple (the helper's teleport is the counted fallback); -> None, or the reason the check cannot go on"""
    how, got, note = await walk_to_place(io, r, 'temple')
    if how not in ('foot', 'helper'):
        return how[:110]
    if note:
        fallbacks.append(note)
        trace['came'] = 'helper'
    await io.sleep(SETTLE)
    if need_pz:
        a = await io.helper('%s state' % system, system, ANSWER)
        if not (isinstance(a, dict) and a.get('pz')):
            return 'the bot stands at the temple but not in a protection zone: the descent cannot be entered there'
    return None


# ------------------------------------------------------------------------------------------------ the hideout, lived in (O595)
# The window's own requests, as a person uses Character > Hideout: open, Enter (the room is built for the bot), place a decoration of the
# catalogue on a tile the room accepts, take it away again, Leave. The server's rules are the proof: a decoration the bot owns is accepted on
# some free tile, it is listed afterwards (`placed`, the count of the hideout), it goes when removed, and Leave brings the bot out. The side
# rule (a tester never visits a player's hideout, a player never a tester's) is in tests/hideout_test.lua: a bot knows no player to ask.
HIDEOUT_TRIES = 30        # tiles tried for the first decoration
HIDEOUT_WAIT = 6.0


def hideout_text(reply):
    d = (reply or {}).get('data') if isinstance(reply, dict) else None
    return str((d or {}).get('text') or '')[:90]


def hideout_candidates(layout, tries=HIDEOUT_TRIES):
    """tiles [(x, y)] of the room the check tries for a decoration: the floor of the inner room away from the reserved tiles (fixtures,
    the arrival), the middle first, then the rest in rows"""
    w, h = int((layout or {}).get('w') or 0), int((layout or {}).get('h') or 0)
    reserved = {(int(t[0]), int(t[1])) for t in (layout or {}).get('reserved') or [] if isinstance(t, (list, tuple)) and len(t) >= 2}
    arrival = (layout or {}).get('arrival')
    if isinstance(arrival, (list, tuple)) and len(arrival) >= 2:
        reserved.add((int(arrival[0]), int(arrival[1])))
    cells = [(x, y) for y in range(1, h) for x in range(1, w) if (x, y) not in reserved]
    cx, cy = w // 2, h // 2
    cells.sort(key=lambda c: (abs(c[0] - cx) + abs(c[1] - cy), c))
    return cells[:tries]


def hideout_pick(catalogue):
    """the first floor decoration the character owns and may place once more, or None"""
    for d in catalogue or []:
        if isinstance(d, dict) and d.get('owned') and d.get('layer') != 'wall' and (d.get('max') or 0) > (d.get('placed') or 0):
            return d
    return None


async def hideout_state(io, action):
    reply = await io.request('hideout', action, {}, ['state', 'result'], ANSWER)
    if isinstance(reply, dict) and reply.get('action') == 'state':
        return reply.get('data') or {}, reply
    return None, reply


async def check_hideout(io, name, cls, level):
    """opens the hideout window, enters the bot's own room, places a decoration on a tile the room accepts, removes it, leaves"""
    key = 'hideout'
    st, reply = await hideout_state(io, 'open')
    if st is None:
        text = hideout_text(reply)
        if reply is None:
            return Result(key, name, cls, SKIP, 'no answer from the hideout window (not installed)')
        return Result(key, name, cls, SKIP, text or 'the hideout window sent no state')
    if st.get('inside'):
        return Result(key, name, cls, SKIP, 'the bot is inside a hideout already')
    deco = hideout_pick(st.get('catalogue'))
    if deco is None:
        return Result(key, name, cls, SKIP, 'no decoration of the catalogue is owned and free to place')
    cells = hideout_candidates(st.get('layout'))
    if not cells:
        return Result(key, name, cls, SKIP, 'the layout of the room names no free tile')
    inside_room = False
    try:
        io.raid_mode([name], True, keep_flee=True)   # no walk back to the hunt while the bot is in its room
        entered, reply = await hideout_state(io, 'enter')
        await io.sleep(1.0)
        if entered is None or not (entered.get('inside') or {}).get('isOwner'):
            st2, _ = await hideout_state(io, 'get')
            if not isinstance(st2, dict) or not (st2.get('inside') or {}).get('isOwner'):
                return Result(key, name, cls, SKIP, 'the room did not open: %s' % (hideout_text(reply) or 'no text'))
        inside_room = True
        count0 = int(((entered or st).get('hideout') or {}).get('count') or 0)
        # O660: a hideout that was never entered has no decoration in the catalogue's count: the room is built (with its two Ashen Thrones) when the
        # bot enters. The pick is made again from the state of the room, as a person reads the window that is open in front of him.
        await io.sleep(HIDEOUT_LIST_GAP)   # the answer to Enter still carries the catalogue of before the room was built: read the room again
        inside_state, _ = await hideout_state(io, 'get')
        again_deco = hideout_pick((inside_state or {}).get('catalogue')) if isinstance(inside_state, dict) and inside_state.get('catalogue') else deco
        if again_deco is None:
            return Result(key, name, cls, SKIP, 'every decoration of the catalogue is placed to its limit in the new room')
        deco = again_deco
        await io.sleep(HIDEOUT_EDIT_GAP)
        placed, tile, last, lost = None, None, None, False
        refusals = []   # O660: the distinct words of the refusals, in order
        ids0 = {p.get('id') for p in ((inside_state or {}).get('placed') or []) if isinstance(p, dict)}
        for (x, y) in cells:
            last = await io.request('hideout', 'place', {'key': deco['key'], 'x': x, 'y': y, 'r': 0}, ['result'], ANSWER)
            if isinstance(last, dict) and (last.get('data') or {}).get('ok'):
                placed, tile = last, (x, y)
                break
            if last is None:   # O660: no answer at all: the live run saw the window place a decoration and the answer never come; the room says
                await io.sleep(HIDEOUT_LIST_GAP)
                now, _ = await hideout_state(io, 'get')
                new = [p for p in ((now or {}).get('placed') or []) if isinstance(p, dict) and p.get('key') == deco['key'] and p.get('id') not in ids0]
                if new:
                    placed, tile, lost = {'data': {'ok': True, 'text': 'the answer was lost'}}, (new[0].get('x'), new[0].get('y')), True
                    break
            if hideout_text(last) not in refusals:
                refusals.append(hideout_text(last))
            await io.sleep(HIDEOUT_EDIT_GAP)   # O660: the window answers one edit in 250 ms; the next try came at once and was dropped unanswered
        if placed is None:
            return Result(key, name, cls, FAIL, 'no tile of the room took %s in %d tries: %s (the catalogue said %s of %s placed)' % (
                deco.get('name') or deco['key'], len(cells), ' | '.join(r or 'no answer' for r in refusals[:4]) or 'no answer', deco.get('placed'), deco.get('max')))
        await io.sleep(HIDEOUT_LIST_GAP)   # O660: `get` answers once a second (cfg.requestMs.list)
        after, _ = await hideout_state(io, 'get')
        rows = [p for p in ((after or {}).get('placed') or []) if isinstance(p, dict) and p.get('key') == deco['key'] and (p.get('x'), p.get('y')) == tile]
        count1 = int((((after or {}).get('hideout')) or {}).get('count') or 0)
        if not rows or count1 != count0 + 1:
            return Result(key, name, cls, FAIL, '%s was placed at %s and the room lists %d such decoration(s), the count went %s to %s' % (
                deco['key'], tile, len(rows), count0, count1))
        gone = await io.request('hideout', 'remove', {'id': rows[0].get('id')}, ['result'], ANSWER)
        await io.sleep(HIDEOUT_LIST_GAP)
        again, _ = await hideout_state(io, 'get')
        count2 = int((((again or {}).get('hideout')) or {}).get('count') or 0)
        if not (isinstance(gone, dict) and (gone.get('data') or {}).get('ok')) or count2 != count0:
            return Result(key, name, cls, FAIL, 'the decoration was removed and the room counts %s, it counted %s before: %s' % (count2, count0, hideout_text(gone) or 'no text'))
        await io.request('hideout', 'leave', {}, ['state', 'result'], ANSWER)
        await io.sleep(HIDEOUT_LIST_GAP)
        outside, _ = await hideout_state(io, 'get')
        inside_room = bool(isinstance(outside, dict) and outside.get('inside'))
        if inside_room:
            return Result(key, name, cls, FAIL, 'Leave did not bring the bot out of its hideout')
        return Result(key, name, cls, PASS, '%s placed at %s, listed, removed; the room was entered and left%s' % (
            deco.get('name') or deco['key'], tile, ' (the answer to the place never came: the room listed it)' if lost else ''))
    finally:
        if inside_room:
            await io.request('hideout', 'leave', {}, ['state', 'result'], ANSWER)
        io.raid_mode([name], False)
        await io.go('hunt')


TRIAL_BUDGET = 480.0      # seconds a trial is played at most (the first tier lasts 8 minutes)


def trial_problems(s, trace):
    """[text] for one inside-a-trial answer; keeps the kills and the guardian's lowest health in the trace"""
    run = s.get('run') or {}
    if isinstance(run.get('killed'), int):
        trace['killed'] = max(trace.get('killed', 0), run['killed'])
    if isinstance(run.get('bossHp'), int):
        trace['boss_seen'] = True
        trace['hp'] = run['bossHp'] if trace.get('hp') is None else min(trace['hp'], run['bossHp'])
    if run.get('lives') is not None:
        trace['lives'] = run['lives']
    return []


def trial_stop(s, trace):
    """a stage the bots cannot play (seals, marks): the check stops there"""
    if ((s.get('guide') or {}).get('area')) == 'puzzle':
        trace['puzzle'] = (s.get('run') or {}).get('stage')
        return True
    return False


def trial_walk_verdict(t):
    """(status, text) from the trace of a walked trial: faults, killed (kills), boss_seen, hp (the guardian's lowest health percent), tier, family, puzzle,
    fought, stuck, died, came, steps, secs, level, fallbacks"""
    if t.get('faults'):
        return FAIL, '; '.join(t['faults'][:3])
    how = solo_text(t, 'trial')
    what = 'tier %s of %s' % (t.get('tier'), t.get('family') or '?')
    if t.get('killed', 0) >= 1:
        text = '%d kill(s)' % t['killed']
        if t.get('boss_seen'):
            text += ', the guardian at %s%%' % t.get('hp')
        return PASS, '%s: %s (%s)' % (what, text, how)
    if t.get('fought', 0) >= SOLO_FIGHT_MIN:
        return FAIL, 'fought %d s in the trial and killed none (damage, targets or the monsters; %s)' % (t['fought'], what)
    if t.get('puzzle'):
        return SKIP, 'the %s stage is a puzzle the bots do not play (%s)' % (t['puzzle'], what)
    if t.get('stuck'):
        return SKIP, 'the walk was blocked at (%d, %d) for %d s (%s)' % (t['stuck'][0], t['stuck'][1], SOLO_STUCK, how)
    if t.get('died'):
        return SKIP, 'the trial ended before a thrall died (%s lives left, level %s against %s)' % (t.get('lives', '?'), t.get('level', '?'), what)
    return SKIP, 'no monster was killed in %d s (%s)' % (t.get('secs', 0), how)


async def check_trial_walk(io, name, cls, level):
    """walks to the temple, enters the vocation's trial from the tree window, fights its waves and the guardian by the engine's path, leaves"""
    key = 'trial_walk'
    a = await io.helper('trial state', 'trial', ANSWER)
    refused = solo_refusal(a, 'trial', 'trial', level)
    if refused:
        return Result(key, name, cls, refused[0], refused[1])
    if not a.get('family'):
        return Result(key, name, cls, SKIP, 'the vocation of the bot has no trial')
    if a.get('puzzle'):
        return Result(key, name, cls, SKIP, 'the trial of %s has a seals or marks stage: a puzzle the bots do not play' % (a.get('familyName') or a.get('family')))
    if a.get('problem'):
        return Result(key, name, cls, SKIP, str(a['problem'])[:90])
    r = {'name': name, 'lead': True, 'walker': RaidWalker(), 'inside': False}
    fallbacks = []
    trace = {'faults': [], 'steps': 0, 'killed': 0, 'fought': 0.0, 'stuck': None, 'died': False, 'secs': 0, 'came': 'foot', 'fallbacks': fallbacks,
             'level': a.get('level'), 'tier': a.get('tier'), 'family': a.get('family'), 'boss_seen': False, 'hp': None}
    io.raid_mode([name], True, keep_flee=True)
    try:
        why = await solo_to_temple(io, r, trace, fallbacks, need_pz=True, system='trial')
        if why:
            return Result(key, name, cls, SKIP, why.replace('the descent', 'the trial'), fallbacks)
        s = await solo_enter(io, r, trace, 'trial', 'passivetree', 'trialEnter', {'tier': a.get('tier')}, ['trialState', 'sendMessage'])
        if not (isinstance(s, dict) and s.get('inside')):
            return Result(key, name, cls, SKIP, 'the trial did not open in %d s (a fight, the cooldown or the chambers kept for the players)' % int(SOLO_ENTER_WAIT),
                          fallbacks)
        await solo_play(io, r, trace, {
            'system': 'trial', 'budget': TRIAL_BUDGET, 'problems': trial_problems, 'stop': trial_stop,
            'done': lambda t: t.get('killed', 0) >= 1 and t.get('boss_seen') and t.get('hp') is not None and t['hp'] < 100,
            'made': lambda t: t.get('killed', 0) > 0,
            'mark': lambda s: ((s.get('run') or {}).get('stageIdx'), (s.get('run') or {}).get('killed'), (s.get('run') or {}).get('monsters'))})
        await io.helper('trial close', 'trial', ANSWER)
        again = await io.helper('trial state', 'trial', ANSWER)
        if isinstance(again, dict) and again.get('inside'):
            trace['faults'].append('the bot is still inside the trial after the close')
        status, text = trial_walk_verdict(trace)
        return Result(key, name, cls, status, text, fallbacks)
    finally:
        await io.helper('trial close', 'trial', ANSWER)
        io.raid_mode([name], False)
        await io.go('hunt')


async def check_tower_walk(io, name, cls, level):
    """walks to the temple, opens the tower from its window, plays floors by the engine's path, calls the next floor, leaves"""
    key = 'tower_walk'
    a = await io.helper('tower state', 'tower', ANSWER)
    refused = solo_refusal(a, 'tower', 'Infinity Tower', level)
    if refused:
        return Result(key, name, cls, refused[0], refused[1])
    if a.get('canEnter') is False:
        return Result(key, name, cls, SKIP, 'the bot has to wait before it may try the tower again (the try cooldown)')
    r = {'name': name, 'lead': True, 'walker': RaidWalker(), 'inside': False}
    fallbacks = []
    trace = {'faults': [], 'steps': 0, 'cleared': 0, 'skips': 0, 'fought': 0.0, 'stuck': None, 'died': False, 'secs': 0, 'came': 'foot',
             'fallbacks': fallbacks, 'level': a.get('level')}
    io.raid_mode([name], True, keep_flee=True)   # no walk back to the hunt, but the bot may still flee like a person
    try:
        why = await solo_to_temple(io, r, trace, fallbacks)
        if why:
            return Result(key, name, cls, SKIP, why)
        s = await solo_enter(io, r, trace, 'tower', 'infinitytower', 'enter', {}, ['state'])
        if not (isinstance(s, dict) and s.get('inside')):
            return Result(key, name, cls, SKIP, 'the tower did not take the bot in %d s (a fight, a busy hall or the reserve)' % int(SOLO_ENTER_WAIT), fallbacks)
        await solo_play(io, r, trace, {
            'system': 'tower', 'budget': TOWER_BUDGET, 'skip': True, 'problems': tower_problems,
            'done': lambda t: t.get('cleared', 0) >= TOWER_FLOORS, 'made': lambda t: t.get('cleared', 0) > 0,
            'mark': lambda s: ((s.get('run') or {}).get('floor'), (s.get('run') or {}).get('remaining'))})
        after = await io.helper('tower close', 'tower', ANSWER)
        again = await io.helper('tower state', 'tower', ANSWER)
        if isinstance(again, dict) and again.get('inside'):
            trace['faults'].append('the bot is still inside the tower after the close')
        status, text = tower_walk_verdict(trace)
        return Result(key, name, cls, status, text, fallbacks)
    finally:
        await io.helper('tower close', 'tower', ANSWER)   # a bot that is still inside leaves (the Leave button, no countdown)
        io.raid_mode([name], False)
        await io.go('hunt')


async def check_descent_walk(io, name, cls, level):
    """walks to the temple, starts the descent from its window (the free run or a sigil), plays rooms by the engine's path, answers the
    boon choices, leaves rooms of rest, leaves"""
    key = 'descent_walk'
    a = await io.helper('descent state', 'descent', ANSWER)
    refused = solo_refusal(a, 'descent', 'Ember Descent', level)
    if refused:
        return Result(key, name, cls, refused[0], refused[1])
    if not a.get('pay'):   # the free run of the day is used: the helper gives a sigil, as a player who forged one has it
        g = await io.helper('descent sigil', 'descent', HELPER_WAIT)
        if not isinstance(g, dict) or g.get('err') or not g.get('given'):
            return Result(key, name, cls, SKIP, 'no free descent today and no sigil: %s' % str((g or {}).get('err') or 'no answer')[:60])
    r = {'name': name, 'lead': True, 'walker': RaidWalker(), 'inside': False}
    fallbacks = []
    trace = {'faults': [], 'steps': 0, 'depth': 0, 'picks': 0, 'rests': 0, 'fought': 0.0, 'stuck': None, 'died': False, 'secs': 0, 'came': 'foot',
             'fallbacks': fallbacks, 'level': a.get('level')}
    io.raid_mode([name], True, keep_flee=True)
    try:
        why = await solo_to_temple(io, r, trace, fallbacks, need_pz=True, system='descent')
        if why:
            return Result(key, name, cls, SKIP, why, fallbacks)
        reply = None
        s, waited = None, 0.0
        while waited <= SOLO_ENTER_WAIT and io.alive():
            if waited in (0.0, 7.0):
                reply = await io.request('descent', 'start', {'weekly': False}, ['closeInfo', 'msg', 'hud'], ANSWER)
            await io.sleep(1.0)
            waited += 1.0
            s = await io.helper('descent state', 'descent', ANSWER)
            if isinstance(s, dict) and s.get('inside'):
                break
        if not (isinstance(s, dict) and s.get('inside')):
            text = window_text(reply)
            return Result(key, name, cls, SKIP, 'the descent did not start in %d s: %s' % (int(SOLO_ENTER_WAIT), text or 'no text'), fallbacks)
        await solo_play(io, r, trace, {
            'system': 'descent', 'budget': DESCENT_BUDGET, 'problems': descent_problems,
            'done': lambda t: t.get('depth', 0) >= DESCENT_ROOMS, 'made': lambda t: t.get('depth', 0) > 0,
            'mark': lambda s: ((s.get('run') or {}).get('room'), (s.get('run') or {}).get('monsters'), (s.get('run') or {}).get('state'))})
        await io.helper('descent close', 'descent', ANSWER)
        again = await io.helper('descent state', 'descent', ANSWER)
        if isinstance(again, dict) and again.get('inside'):
            trace['faults'].append('the bot is still inside the descent after the close')
        status, text = descent_walk_verdict(trace)
        return Result(key, name, cls, status, text, fallbacks)
    finally:
        await io.helper('descent close', 'descent', ANSWER)
        io.raid_mode([name], False)
        await io.go('hunt')


# ------------------------------------------------------------------------------------------------ the Ascended and Omen arenas, played (O599)
# Boss arenas of the recipe of the guild boss: the bot walks to the temple (a protection zone), gets a sigil or an Omen Key from the TEST ONLY
# grant of the helper (`!tester ascended sigil`, `!tester omen key`: a tester only, logged; the shards and fragments are many Omen kills a
# check cannot repeat), uses it like a hotkey and fights the boss by the engine's path until it is hurt. The helper closes the run after. A
# tester takes an arena only while one stays free for the players and is never in a run with a player; no board row, broadcast or first-kill
# record is a tester's (server/README.md "Tester bots", step 8).
ASC_BUDGET = 420.0        # seconds a boss arena is played at most (the boss comes a few seconds after the arrival)
ASC_OPEN_WAIT = 12.0      # seconds from the use of the sigil / key to standing inside (the hotkey is sent again twice)
BOSS_STOP_HP = 100        # the boss health percent under which it is hurt


def boss_problems(s, trace):
    """[text] for one inside-an-arena answer: a player in the testers' run, a run not marked as the testers'. Keeps the boss's lowest
    health, the phase and the lives in the trace"""
    out = []
    run = s.get('run') or {}
    if run.get('players') is not None and run.get('testers') is not None and run['players'] != run['testers']:
        out.append('a player is in the arena run of the testers (%s of %s are testers)' % (run['testers'], run['players']))
    if 'tester' in run and not run['tester'] and run.get('omen') is None and trace.get('system') == 'ascended':
        out.append('the run of a tester is not marked as the testers\' (a board row or a broadcast would follow)')
    if run.get('boss') == 'alive' or isinstance(run.get('bossHp'), int):
        if isinstance(run.get('bossHp'), int):
            trace['boss_seen'] = True
            trace['hp'] = run['bossHp'] if trace.get('hp') is None else min(trace['hp'], run['bossHp'])
    if run.get('phase') is not None:
        trace['phase'] = max(trace.get('phase') or 0, run['phase'])
    if run.get('lives') is not None:
        trace['lives'] = run['lives']
    return out


def boss_walk_verdict(t, what):
    """(status, text) from the trace of a walked boss arena: faults, boss_seen, hp (the boss's lowest health percent), kind, phase, fought, stuck,
    died, came, steps, secs, level, fallbacks"""
    if t.get('faults'):
        return FAIL, '; '.join(t['faults'][:3])
    how = solo_text(t, what)
    if t.get('boss_seen') and t.get('hp') is not None and t['hp'] < BOSS_STOP_HP:
        return PASS, '%s hurt to %s%%%s (%s)' % (t.get('boss') or 'the boss', t['hp'], ', phase %s' % t['phase'] if t.get('phase') else '', how)
    if t.get('fought', 0) >= SOLO_FIGHT_MIN:
        return FAIL, 'fought %d s at the boss of the %s and took none of its health (damage, targets or the boss)' % (t['fought'], what)
    if t.get('stuck'):
        return SKIP, 'the walk was blocked at (%d, %d) for %d s (%s)' % (t['stuck'][0], t['stuck'][1], SOLO_STUCK, how)
    if t.get('died'):
        return SKIP, 'the bot fell before the boss was hurt (level %s against the %s)' % (t.get('level', '?'), what)
    if not t.get('boss_seen'):
        return SKIP, 'the boss did not come in %d s (%s)' % (t.get('secs', 0), how)
    return SKIP, 'the boss was not hurt in %d s (%s)' % (t.get('secs', 0), how)


def ascended_walk_verdict(t):
    return boss_walk_verdict(t, 'Ascended arena')


def omen_walk_verdict(t):
    return boss_walk_verdict(t, 'omen arena')


def ascended_refusal(a, level=0):
    """(status, text) when this bot must not play the check, else None: from its `!tester ascended` answer"""
    if not isinstance(a, dict):
        return SKIP, 'no answer to !tester ascended (old helper file)'
    if a.get('err'):
        return SKIP, str(a['err'])[:80]
    if a.get('enabled') is False:
        return SKIP, 'the Ascended arenas are closed'
    levels = [int(k.get('minLevel') or 0) for k in a.get('kinds') or []]
    have = int(a.get('level') or level or 0)
    if not levels:
        return SKIP, 'the server lists no Ascended Omen'
    if have < min(levels):
        return SKIP, 'level %d: the Ascended arenas need level %d' % (have, min(levels))
    if a.get('inside'):
        return SKIP, 'the bot is inside an Ascended arena already'
    if a.get('free') is not None and a.get('reserve') is not None and int(a['free']) - 1 < int(a['reserve']):
        return SKIP, 'the arenas are kept for the players (%s free, %s reserved)' % (a['free'], a['reserve'])
    return None


async def boss_use_item(io, system, client_id):
    """uses the sigil / key like a hotkey, again after 5 and 9 s, until the helper says the bot is inside; -> the last look"""
    opened, waited = None, 0.0
    while waited <= ASC_OPEN_WAIT and io.alive():
        if waited in (0.0, 5.0, 9.0):
            await io.use_item(client_id)
        await io.sleep(1.0)
        waited += 1.0
        opened = await io.helper('%s state' % system, system, ANSWER)
        if isinstance(opened, dict) and opened.get('inside'):
            break
    return opened


def boss_play_config(system, trace):
    trace['system'] = system
    return {'system': system, 'budget': ASC_BUDGET, 'problems': boss_problems,
            'done': lambda t: t.get('boss_seen') and t.get('hp') is not None and t['hp'] < BOSS_STOP_HP,
            'made': lambda t: bool(t.get('boss_seen')),
            'mark': lambda s: ((s.get('run') or {}).get('bossHp'), (s.get('run') or {}).get('phase'), (s.get('run') or {}).get('adds'))}


async def check_ascended_walk(io, name, cls, level):
    """walks to the temple, takes the helper's sigil, uses it, walks to the Ascended boss and fights it until it is hurt, closes the run"""
    key = 'ascended_walk'
    a = await io.helper('ascended state', 'ascended', ANSWER)
    refused = ascended_refusal(a, level)
    if refused:
        return Result(key, name, cls, refused[0], refused[1])
    r = {'name': name, 'lead': True, 'walker': RaidWalker(), 'inside': False}
    fallbacks = []
    trace = {'faults': [], 'steps': 0, 'fought': 0.0, 'stuck': None, 'died': False, 'secs': 0, 'came': 'foot', 'fallbacks': fallbacks,
             'level': a.get('level'), 'boss_seen': False, 'hp': None}
    io.raid_mode([name], True, keep_flee=True)
    try:
        why = await solo_to_temple(io, r, trace, fallbacks, need_pz=True, system='ascended')
        if why:
            return Result(key, name, cls, SKIP, why.replace('the descent', 'an Ascended arena'), fallbacks)
        g = await io.helper('ascended sigil', 'ascended', HELPER_WAIT)
        if not isinstance(g, dict):
            return Result(key, name, cls, SKIP, 'no answer to !tester ascended sigil', fallbacks)
        if g.get('err'):
            return Result(key, name, cls, SKIP, 'ascended sigil: %s' % str(g['err'])[:80], fallbacks)
        if not g.get('held'):
            if g.get('bagFull'):
                return Result(key, name, cls, SKIP, 'the bag is full: the sigil went to the inbox (by design)', fallbacks)
            return Result(key, name, cls, FAIL, 'a sigil of %s was given, the backpack holds none' % g.get('kind'), fallbacks)
        trace['boss'] = g.get('kind')
        s = await boss_use_item(io, 'ascended', g.get('sigilClientId'))
        if not (isinstance(s, dict) and s.get('inside')):
            return Result(key, name, cls, SKIP, 'the arena did not open in %d s (a slot is busy, or the bot is in a fight)' % int(ASC_OPEN_WAIT), fallbacks)
        trace['boss'] = ((s.get('run') or {}).get('kind') or trace['boss'])
        await solo_play(io, r, trace, boss_play_config('ascended', trace))
        await io.helper('ascended close', 'ascended', ANSWER)
        again = await io.helper('ascended state', 'ascended', ANSWER)
        if isinstance(again, dict) and again.get('inside'):
            trace['faults'].append('the bot is still inside the Ascended arena after the close')
        status, text = ascended_walk_verdict(trace)
        return Result(key, name, cls, status, text, fallbacks)
    finally:
        await io.helper('ascended close', 'ascended', ANSWER)
        io.raid_mode([name], False)
        await io.go('hunt')


async def check_omen_walk(io, name, cls, level):
    """walks to the temple, takes the helper's Omen Key, uses it, walks to the omen guardian and fights it until it is hurt, closes the run"""
    key = 'omen_walk'
    a = await io.helper('omen state', 'omen', ANSWER)
    refused = solo_refusal(a, 'omen', 'omen arena', level)
    if refused:
        return Result(key, name, cls, refused[0], refused[1])
    r = {'name': name, 'lead': True, 'walker': RaidWalker(), 'inside': False}
    fallbacks = []
    trace = {'faults': [], 'steps': 0, 'fought': 0.0, 'stuck': None, 'died': False, 'secs': 0, 'came': 'foot', 'fallbacks': fallbacks,
             'level': a.get('level'), 'boss_seen': False, 'hp': None}
    io.raid_mode([name], True, keep_flee=True)
    try:
        why = await solo_to_temple(io, r, trace, fallbacks, need_pz=True, system='omen')
        if why:
            return Result(key, name, cls, SKIP, why.replace('the descent', 'an omen arena'), fallbacks)
        k = await io.helper('omen key', 'omen', HELPER_WAIT)
        if not isinstance(k, dict):
            return Result(key, name, cls, SKIP, 'no answer to !tester omen key', fallbacks)
        if k.get('err'):
            return Result(key, name, cls, SKIP, 'omen key: %s' % str(k['err'])[:80], fallbacks)
        if not k.get('held'):
            if k.get('bagFull'):
                return Result(key, name, cls, SKIP, 'the bag is full: the key went to the inbox (by design)', fallbacks)
            return Result(key, name, cls, FAIL, 'an omen key (%s) was given, the backpack holds none' % k.get('kind'), fallbacks)
        trace['boss'] = k.get('kind')
        s = await boss_use_item(io, 'omen', k.get('keyClientId'))
        if not (isinstance(s, dict) and s.get('inside')):
            return Result(key, name, cls, SKIP, 'the omen arena did not open in %d s (a slot is busy, or the bot is in a fight)' % int(ASC_OPEN_WAIT), fallbacks)
        await solo_play(io, r, trace, boss_play_config('omen', trace))
        await io.helper('omen close', 'omen', ANSWER)
        again = await io.helper('omen state', 'omen', ANSWER)
        if isinstance(again, dict) and again.get('inside'):
            trace['faults'].append('the bot is still inside the omen arena after the close')
        status, text = omen_walk_verdict(trace)
        return Result(key, name, cls, status, text, fallbacks)
    finally:
        await io.helper('omen close', 'omen', ANSWER)   # the run closes, a refunded key is taken out of the backpack again
        io.raid_mode([name], False)
        await io.go('hunt')


# ------------------------------------------------------------------------------------------------ the bounty board, hunted (O599)
# The bot reads the board with `!tester bounty` (the hunt contracts of its band that a hunt mark lists: "where does monster X spawn" comes from the
# marks of the map, bounty_core.lua B.spawnMarks), accepts the smallest through the window's own `accept`, walks to the hunt by the engine's
# path, kills monsters of that name with its own rotation and proves the counter moved (BOUNTY_KILLS, not the 50-400 of the contract). The
# contract is abandoned after. Nothing of a tester is on a public board (leaderboard.lua skips testers); its rows are its own.
BOUNTY_BUDGET = 480.0     # seconds the hunt is played at most
BOUNTY_KILLS = 3          # kills the counter must show for a pass
BOUNTY_SPAWN_WAIT = 120.0 # seconds at the hunt with no monster of the contract in sight
BOUNTY_ACCEPT_WAIT = 6.0  # seconds from `accept` to the contract in the list
BOUNTY_BOSS_WAIT = 40.0   # seconds at a boss lair with no boss in sight (a boss comes back every few hours: it is not there most of the time)
BOUNTY_CROWD_WAIT = 20.0  # seconds a bot waits while a player is near the boss, then it leaves: the boss is the players'
BOUNTY_NEED = {'hunt': 3, 'elite': 1, 'boss': 1}   # kills the counter must show for a pass (O650: one elite kill, the boss)


def bounty_walk_verdict(t):
    """(status, text) from the trace of a hunted contract: faults, name, key, base (progress at the accept), progress, required, fought (seconds in
    reach of a monster of it with the counter not moving), waited, stuck, died, came, steps, secs, level, fallbacks"""
    if t.get('faults'):
        return FAIL, '; '.join(t['faults'][:3])
    how = 'level %s, %d step(s) in %d s%s' % (t.get('level'), t.get('steps', 0), t.get('secs', 0),
                                              ('; teleport in place of walking: ' + ', '.join(t['fallbacks'])) if t.get('fallbacks') else '')
    if t.get('waypoints'):
        how += '; by the waypoint ' + ', '.join(t['waypoints'])   # O662
    moved = (t.get('progress') or 0) - (t.get('base') or 0)
    if t.get('no_way') and moved < t.get('need', BOUNTY_KILLS):   # O661: the hunt is far and no teleport leads there: the reason, not a bug
        return SKIP, 'the hunt of %s is far from the bot and has no way there: %s (%s)' % (t.get('name'), t['no_way'], how)
    kind = t.get('kind') or 'hunt'
    if moved >= t.get('need', BOUNTY_KILLS):
        return PASS, '%s: the counter went from %s to %s of %s (%s)' % (t.get('name'), t.get('base'), t.get('progress'), t.get('required'), how)
    if t.get('crowd', 0) >= BOUNTY_CROWD_WAIT:
        return SKIP, 'a player is near %s: the bot left it to the players (%s)' % (t.get('name'), how)
    if t.get('fought', 0) >= SOLO_FIGHT_MIN:
        if kind == 'boss':   # a boss of a level 100 bot is a long fight: no kill in 150 s is no bug
            return SKIP, 'fought %s for %d s and it did not fall (%s)' % (t.get('name'), t['fought'], how)
        return FAIL, 'fought %d s in reach of %s and the contract counter moved %d (kills, credit or the target)' % (t['fought'], t.get('name'), moved)
    if t.get('stuck'):
        return SKIP, 'the walk was blocked at (%d, %d) for %d s (%s)' % (t['stuck'][0], t['stuck'][1], SOLO_STUCK, how)
    if t.get('died'):
        return SKIP, 'the bot died at the hunt of %s (%s)' % (t.get('name'), how)
    if t.get('waited', 0) >= (BOUNTY_BOSS_WAIT if kind == 'boss' else BOUNTY_SPAWN_WAIT):
        return SKIP, 'no %s in sight at its %s for %d s (%s)' % (t.get('name'), 'lair' if kind == 'boss' else 'hunt', t['waited'], how)
    return SKIP, 'the counter of %s moved %d in %d s (%s)' % (t.get('name'), moved, t.get('secs', 0), how)


def bounty_pick(a, kind='hunt'):
    """(row, accepted) the contract to hunt from a `!tester bounty` answer: one of the kind held and not done (already accepted), else the first
    candidate of the kind (hunt, elite or boss: O650); (None, text) when there is none"""
    for row in a.get('active') or []:
        if row.get('status') == 0 and row.get('required') and (row.get('type') or 'hunt') == kind:
            return row, True
    cands = (a.get('candidates') if kind == 'hunt' else a.get(kind)) or []
    if not cands:
        if kind == 'boss':
            return None, "no boss contract of today's board for level %s has an open boss mark (a lair or an island: a raid boss comes with a raid)" % a.get('level')
        return None, "no %s contract of today's board for level %s has a hunt mark that lists its monster" % (kind, a.get('level'))
    if a.get('maxActive') is not None and len(a.get('active') or []) >= int(a['maxActive']):
        return None, 'the bot holds %d contracts already' % len(a['active'])
    return cands[0], False


async def check_bounty_walk(io, name, cls, level):
    """reads the board, accepts the smallest hunt contract with a known hunt, walks there, kills monsters of it and checks the counter moved"""
    return await bounty_play(io, name, cls, level, 'bounty_walk', 'hunt')


async def check_bounty_elite_walk(io, name, cls, level):
    """O650: an elite contract (a monster of a tier, magic or better): the same walk to the hunt of the monster, the bot kills the type until a tier
    monster falls and the counter moves by one"""
    return await bounty_play(io, name, cls, level, 'bounty_elite_walk', 'elite')


async def check_bounty_boss_walk(io, name, cls, level):
    """O650: a boss contract: the bot walks to the boss's lair or island and fights the boss when it is there and no player is near it (the boss is the
    players': a player near it and the bot leaves); the counter moves when the boss falls"""
    return await bounty_play(io, name, cls, level, 'bounty_boss_walk', 'boss')


async def bounty_play(io, name, cls, level, key, kind):
    a = await io.helper('bounty state', 'bounty', ANSWER)
    if not isinstance(a, dict):
        return Result(key, name, cls, SKIP, 'no answer to !tester bounty (old helper file)')
    if a.get('err'):
        return Result(key, name, cls, SKIP, str(a['err'])[:80])
    row, held = bounty_pick(a, kind)
    if row is None:
        return Result(key, name, cls, SKIP, held)
    if kind == 'hunt' and not held and bounty_far(a.get('pos'), (row.get('mark') or {})):   # O661: the contract whose hunt a teleport leads to
        near_row, why = await bounty_near_row(io, a)
        if near_row is None:
            return Result(key, name, cls, SKIP, why)
        row = near_row
    r = {'name': name, 'lead': True, 'walker': RaidWalker(), 'inside': False}
    fallbacks = []
    trace = {'faults': [], 'steps': 0, 'fought': 0.0, 'waited': 0.0, 'stuck': None, 'died': False, 'secs': 0, 'came': 'foot', 'fallbacks': fallbacks,
             'level': a.get('level'), 'name': row.get('name'), 'key': row.get('key'), 'base': row.get('progress') or 0, 'progress': row.get('progress') or 0,
             'required': row.get('required') or row.get('count'), 'kind': kind, 'need': BOUNTY_NEED[kind], 'crowd': 0.0, 'via': row.get('via')}
    spawn_limit = BOUNTY_BOSS_WAIT if kind == 'boss' else BOUNTY_SPAWN_WAIT
    accepted_here = False
    io.raid_mode([name], True, keep_flee=True)
    try:
        if not held:
            reply = await io.request('bounty', 'accept', {'key': row['key']}, ['board', 'progress'], ANSWER)
            waited, listed = 0.0, None
            while waited <= BOUNTY_ACCEPT_WAIT and io.alive():
                await io.sleep(1.0)
                waited += 1.0
                listed = await io.helper('bounty state', 'bounty', ANSWER)
                if isinstance(listed, dict) and any(x.get('key') == row['key'] for x in listed.get('active') or []):
                    break
            if not (isinstance(listed, dict) and any(x.get('key') == row['key'] for x in listed.get('active') or [])):
                return Result(key, name, cls, SKIP, 'the contract %s was not accepted: %s' % (row.get('name'), window_text(reply) or 'no text'))
            accepted_here = True
        trace['base'] = next((x.get('progress') or 0 for x in (listed if accepted_here else a).get('active') or [] if x.get('key') == row['key']), trace['base'])
        trace['progress'] = trace['base']
        elapsed, misses, fight_since, wait_since = 0.0, 0, None, None
        while io.alive() and elapsed < BOUNTY_BUDGET:
            s = await io.helper('bounty state', 'bounty', ANSWER)
            if not isinstance(s, dict):
                misses += 1
                if misses >= SOLO_MISSES:
                    break
                await io.sleep(RAID_LOOK)
                elapsed += RAID_LOOK
                continue
            misses = 0
            mine = next((x for x in s.get('active') or [] if x.get('key') == row['key']), None)
            if mine is None:
                trace['faults'].append('the accepted contract %s left the list' % row.get('name'))
                break
            if (mine.get('progress') or 0) > trace['progress']:
                trace['progress'] = mine['progress']
                fight_since = None
                await io.loot()
            if trace['progress'] - trace['base'] >= trace['need'] or mine.get('status') == 1:
                break
            g = s.get('guide') or {}
            spent = await retreat_check(io, r, s, trace, g)   # O658: under 30 % health the bot heals and steps back before it goes on
            if spent:
                elapsed += spent
                continue
            mode = g.get('mode')
            if mode == 'walk' and trace.get('travel') is None and bounty_far(s.get('pos'), g.get('goal')):   # O661: a hunt far away: the journey's legs
                elapsed += await bounty_travel(io, r, g['goal'], trace, fallbacks)   # O662: by the journey's legs or a waypoint
                if trace.get('travel') != 'foot':
                    break
                continue
            if mode == 'fight':
                fight_since = elapsed if fight_since is None else fight_since
                trace['fought'] = max(trace['fought'], elapsed - fight_since)
            else:
                fight_since = None
            if mode == 'wait' and g.get('area') == 'crowd':   # a player is near the boss: it is theirs, the bot leaves after a while
                trace['crowd'] += RAID_LOOK
                if trace['crowd'] >= BOUNTY_CROWD_WAIT:
                    break
            if mode == 'wait' and g.get('area') == 'spawn':
                wait_since = elapsed if wait_since is None else wait_since
                trace['waited'] = max(trace['waited'], elapsed - wait_since)
                if trace['waited'] >= spawn_limit:
                    break
            else:
                wait_since = None
            plan = []
            if mode == 'walk' and isinstance(g.get('goal'), dict) and isinstance(s.get('pos'), dict):
                plan = r['walker'].steps(s['pos'], g['goal'], SOLO_STEPS, elapsed)
                if not r['walker'].blocked:
                    got = await hcmd(io, r, 'bounty path', 'bounty')
                    steps = raid_path_steps((got or {}).get('path')) if isinstance(got, dict) and not got.get('err') else []
                    plan = steps[:SOLO_STEPS] or plan
                if r['walker'].stuck(elapsed) >= SOLO_STUCK:
                    trace['stuck'] = (s['pos']['x'], s['pos']['y'])
                    break
            for step in plan:
                await raid_walk(io, r, step)
                trace['steps'] += 1
                await io.sleep(RAID_STEP)
                elapsed += RAID_STEP
            await io.sleep(RAID_LOOK)
            elapsed += RAID_LOOK
            trace['secs'] = int(elapsed)
        trace['secs'] = int(elapsed)
        trace['died'] = not io.alive()
        status, text = bounty_walk_verdict(trace)
        return Result(key, name, cls, status, text, fallbacks)
    finally:
        if accepted_here:   # the contract goes back: the bot's own row is deleted with its character
            await io.request('bounty', 'abandon', {'key': row['key']}, ['board'], ANSWER)
        io.raid_mode([name], False)
        await io.go('hunt')


# ------------------------------------------------------------------------------------------------ the main quest, played (O599)
# The first steps of "The Ember Oath" the way a new character plays them: the bot reads the open step (`!tester mainquest`: its condition, where to
# go, what a bot can play: talk | visit | kill | skip), walks there on foot (`path npc NAME`, `path pos X Y Z`), talks to Warden Ysolde, stands on the
# place of a visit step, kills the named monsters of a kill step, and the quest must credit each step (the step number rises, or the kill counter).
# A step the bots do not play (a spell, a window, a stat, a flag, the boss: Vael Ashmourn is the spell trial of the trials engine and no testers'
# instance of it is built) ends the check, named. Rewards are the tester's own; nothing of the quest is on a public board.
MQ_STEPS = 3              # steps played at most
MQ_STEP_WAIT = 14.0       # seconds the quest has to credit a talk or a visit (its think sweep runs every few seconds)
MQ_KILL_BUDGET = 300.0    # seconds a kill step is played at most
MQ_KILL_LOOK = 2.0
MQ_KILLS = 3              # kills the counter must show for a pass of a kill step that does not finish
MQ_CAST_WAIT = 60.0       # seconds a spell step waits for the bot's own rotation to cast at a monster (O650)
MQ_HUNT_BUDGET = 300.0    # seconds a tier-kill stat (a magic or a rare monster) is hunted at most (O650)


def mainquest_verdict(t):
    """(status, text) from the trace of the quest check: faults, first (the step it began at), step (the open step at the end), counted (kills the
    counter moved in a kill step that did not finish), why (the reason it stopped: a step not played, a refused walk), level, fallbacks"""
    if t.get('faults'):
        return FAIL, '; '.join(t['faults'][:3])
    adv = (t.get('step') or 0) - (t.get('first') or 0)
    note = ('; teleport in place of walking: ' + ', '.join(t['fallbacks'])) if t.get('fallbacks') else ''
    if adv >= 1 or t.get('counted', 0) >= 1:
        text = 'steps %s to %s' % (t.get('first'), t.get('step')) if adv >= 1 else 'step %s: the kill counter moved %d' % (t.get('step'), t['counted'])
        if t.get('why'):
            text += ' (stopped: %s)' % t['why']
        return PASS, text + note
    return SKIP, '%s (step %s, level %s)%s' % (t.get('why') or 'no step was credited', t.get('first'), t.get('level'), note)


async def mq_look(io):
    a = await io.helper('mainquest state', 'mainquest', ANSWER)
    return a if isinstance(a, dict) and not a.get('err') else None


async def mq_wait_step(io, step, progress=None, limit=None, loot=False):
    """polls until the quest is past `step` or the progress of the step rose above `progress` (a step of several conditions: one more holds), at most
    `limit` seconds (MQ_STEP_WAIT); -> the last look"""
    waited, a, limit = 0.0, None, (MQ_STEP_WAIT if limit is None else limit)
    while waited <= limit and io.alive():
        a = await mq_look(io)
        if a is None or a.get('step') != step or not a.get('active'):
            return a
        if progress is not None and (a.get('progress') or 0) > progress:
            return a
        if loot:
            await io.loot()
        await io.sleep(1.0)
        waited += 1.0
    return a


def mq_open(after, here, progress=None):
    """True while the step is still open after a wait: the same step, and no more conditions hold than before"""
    return after is not None and bool(after.get('active')) and after.get('step') == here and (progress is None or (after.get('progress') or 0) <= progress)


async def check_mainquest_walk(io, name, cls, level):
    """plays up to MQ_STEPS of the first steps of the main quest: talk to Warden Ysolde, walk to a place, kill the named monsters"""
    key = 'mainquest_walk'
    a = await io.helper('mainquest state', 'mainquest', ANSWER)
    if not isinstance(a, dict):
        return Result(key, name, cls, SKIP, 'no answer to !tester mainquest (old helper file)')
    if a.get('err'):
        return Result(key, name, cls, SKIP, str(a['err'])[:80])
    if not a.get('enabled'):
        return Result(key, name, cls, SKIP, 'the main quest is switched off')
    if a.get('staff'):
        return Result(key, name, cls, SKIP, 'staff walk no quest')
    if not a.get('active'):
        return Result(key, name, cls, SKIP, 'the main quest is %s for this bot (state %s)' % ('finished' if a.get('done') else 'not running', a.get('state')))
    r = {'name': name, 'lead': True, 'walker': RaidWalker(), 'inside': False}
    fallbacks = []
    trace = {'faults': [], 'first': a.get('step'), 'step': a.get('step'), 'counted': 0, 'why': None, 'level': a.get('level'), 'fallbacks': fallbacks}
    io.raid_mode([name], True, keep_flee=True)
    try:
        for _ in range(MQ_STEPS):
            a = await mq_look(io)
            if a is None or not a.get('active'):
                break
            trace['step'] = a.get('step')
            plan = a.get('plan') or {}
            if not a.get('running'):
                trace['why'] = 'level %s: step %s needs level %s' % (a.get('level'), a.get('key'), a.get('stepLevel'))
                break
            action, here = plan.get('action'), a.get('step')
            if action in ('talk', 'bring'):
                how, got, note = await walk_to_place(io, r, 'npc %s' % plan.get('label'))
                if how not in ('foot', 'helper'):
                    trace['why'] = how[:100]
                    break
                if note:
                    fallbacks.append(note)
                await io.sleep(SETTLE)
                await io.say('hi')
                await io.sleep(1.0)
                await io.say('oath')
                after = await mq_wait_step(io, here)
                if mq_open(after, here):
                    if action == 'bring' and not trace.get('killed_step'):   # the drops were not collected in this run: the NPC may take none
                        trace['why'] = 'step %s: the drops of the kill step before it are not in the bag (the NPC takes none)' % a.get('key')
                    else:
                        trace['faults'].append('step %s (%s): the bot said the words next to %s and the quest did not move' % (here, a.get('key'), plan.get('label')))
                    break
            elif action == 'visit':
                c = a.get('cond') or {}
                p = c.get('pos') or {}
                if not p:
                    trace['why'] = 'the visit step %s has no place' % a.get('key')
                    break
                how, got = await walk_by_path(io, r, 'path pos %d %d %d' % (p['x'], p['y'], p['z']), 'path', max(1, int(c.get('radius') or 6) - 2))
                if how != 'foot':
                    trace['why'] = 'no way on foot to %s: %s' % (c.get('label') or 'the place', str((got or {}).get('err') or 'far')[:50])
                    break
                after = await mq_wait_step(io, here)
                if after is not None and after.get('active') and after.get('step') == here:
                    trace['faults'].append('step %s (%s): the bot stands at %s and the quest did not move' % (here, a.get('key'), c.get('label') or 'the place'))
                    break
            elif action == 'kill':
                w = (a.get('where') or {}).get('pos') or {}
                if not w:
                    trace['why'] = 'the kill step %s has no place' % a.get('key')
                    break
                how, got = await walk_by_path(io, r, 'path pos %d %d %d' % (w['x'], w['y'], w['z']), 'path', 6)
                if how != 'foot':
                    trace['why'] = 'no way on foot to the %s: %s' % (plan.get('label') or 'hunt', str((got or {}).get('err') or 'far')[:50])
                    break
                base, waited = a.get('progress') or 0, 0.0
                moved_step = False
                while waited < MQ_KILL_BUDGET and io.alive():
                    await io.sleep(MQ_KILL_LOOK)
                    waited += MQ_KILL_LOOK
                    b = await mq_look(io)
                    if b is None or not b.get('active') or b.get('step') != here:
                        moved_step = True
                        break
                    trace['counted'] = max(trace['counted'], (b.get('progress') or 0) - base)
                    if trace['counted'] >= MQ_KILLS:
                        break
                    await io.loot()
                if not moved_step:
                    if trace['counted'] < 1:
                        trace['why'] = 'no %s died at the place in %d s' % (plan.get('label') or 'monster', int(waited))
                    break   # the step is not over: the check has proved the counter
                trace['killed_step'] = True   # the drops of this step are in the bag: the bring step after it takes them
            elif action == 'go':   # O650: a window to see, an info page to read: the Go button of the tracker, the goals window's own request
                await io.request('goals', 'mqGo', {'step': a.get('key')}, ['welcome', 'mq'], ANSWER)
                after = await mq_wait_step(io, here, a.get('progress') or 0)
                if mq_open(after, here, a.get('progress') or 0):
                    trace['faults'].append('step %s (%s): the Go button was pressed for %s and the quest did not move' % (here, a.get('key'), plan.get('flag')))
                    break
            elif action == 'daily':   # O650: the daily reward claimed in its window
                outcome, text = await daily_claim_do(io)
                if outcome == 'taken':
                    trace['why'] = "step %s: %s (the flag comes with a claim)" % (a.get('key'), text)
                    break
                if outcome == 'skip':
                    trace['why'] = 'step %s: %s' % (a.get('key'), text)
                    break
                if outcome == 'fail':
                    trace['faults'].append('step %s (%s): %s' % (here, a.get('key'), text))
                    break
                after = await mq_wait_step(io, here, a.get('progress') or 0)
                if mq_open(after, here, a.get('progress') or 0):
                    trace['faults'].append('step %s (%s): the daily was claimed and the quest did not move' % (here, a.get('key')))
                    break
            elif action in ('cast', 'hunt'):   # O650: a spell cast / a monster of a tier killed: the bot hunts at the place of the step, its own rotation does it
                w = (a.get('where') or {}).get('pos') or {}
                if w:
                    how, got = await walk_by_path(io, r, 'path pos %d %d %d' % (w['x'], w['y'], w['z']), 'path', 6)
                    if how != 'foot':
                        trace['why'] = 'no way on foot to the hunt of step %s: %s' % (a.get('key'), str((got or {}).get('err') or 'far')[:50])
                        break
                limit = MQ_CAST_WAIT if action == 'cast' else MQ_HUNT_BUDGET
                after = await mq_wait_step(io, here, a.get('progress') or 0, limit, loot=True)
                if mq_open(after, here, a.get('progress') or 0):
                    trace['why'] = 'step %s: %s in %d s' % (a.get('key'), 'no spell was cast' if action == 'cast' else 'no %s monster died' % (plan.get('stat') or 'tier'), int(limit))
                    break
            elif action == 'vael':
                trace['why'] = 'step %s: Vael Ashmourn has his own check (vael_walk)' % a.get('key')
                break
            else:
                trace['why'] = 'step %s: %s' % (a.get('key'), plan.get('reason') or 'not played')
                break
        a = await mq_look(io)
        if a is not None:
            trace['step'] = a.get('step') if a.get('active') else (trace['step'] or 0) + 1
        status, text = mainquest_verdict(trace)
        return Result(key, name, cls, status, text, fallbacks)
    finally:
        io.raid_mode([name], False)
        await io.go('hunt')



# ------------------------------------------------------------------------------------------------ the daily reward, claimed (O650)
# The Daily window as a person uses it: open, claim the slot of the day with the number the window sends for it (the helper reads the account's daily
# and tells it: `!tester daily`), and the day must be taken, the reward in the backpack and the streak one up. The row is the bot's own account's
# (`testers cleanup` deletes it); a milestone title's broadcast naming a tester is dropped by the server. The random request `daily_claim_sets_day`
# proves the taken flag only; this proves the reward and the streak.
def daily_verdict(a, b, reply=None):
    """(status, text) from the daily state before (a) and after (b) a claim; reply: the window's answer to the claim"""
    rw, rw2 = a.get('reward') or {}, (b or {}).get('reward') or {}
    if not isinstance(b, dict) or b.get('err'):
        return SKIP, 'no answer to !tester daily after the claim'
    shown = (((reply or {}).get('data') or {}).get('TakenReward')) if isinstance(reply, dict) else None
    if not b.get('taken'):
        return FAIL, 'the claim of day %s (the window sent %s) left the day open%s' % (a.get('slot'), a.get('value'), ' (the window said TakenReward %s)' % shown if shown is not None else '')
    if rw.get('itemId') and rw2.get('itemId') == rw.get('itemId') and (rw2.get('held') or 0) < (rw.get('held') or 0) + (rw.get('count') or 0):
        return FAIL, 'day %s was taken and %sx %s did not arrive (held %s, now %s)' % (a.get('slot'), rw.get('count'), rw.get('name') or rw.get('itemId'),
                                                                                     rw.get('held'), rw2.get('held'))
    if a.get('next') is not None and b.get('streak') != a.get('next'):
        return FAIL, 'day %s was taken and the streak is %s, it should be %s' % (a.get('slot'), b.get('streak'), a.get('next'))
    return PASS, 'day %s claimed: %sx %s arrived, streak %s' % (a.get('slot'), rw.get('count'), rw.get('name') or rw.get('itemId'), b.get('streak'))


async def daily_claim_do(io):
    """opens the Daily window and claims the day; -> ('claimed', text) | ('taken', text) | ('fail', text) | ('skip', text)"""
    a = await io.helper('daily state', 'daily', ANSWER)
    if not isinstance(a, dict):
        return 'skip', 'no answer to !tester daily (old helper file)'
    if a.get('err'):
        return 'skip', str(a['err'])[:80]
    if a.get('taken'):
        return 'taken', "the account's daily is taken today (day %s, streak %s)" % (a.get('slot'), a.get('streak'))
    await io.request('daily', 'open', {}, ['OpenDailyWindow'], ANSWER)
    reply = await io.request('daily', 'calim', a.get('value'), ['OpenDailyWindow'], ANSWER)
    await io.sleep(1.0)
    b = await io.helper('daily state', 'daily', ANSWER)
    status, text = daily_verdict(a, b, reply)
    if status == FAIL and no_room_said(io):   # O660: the reward did not fit the backpack: the server said so, no bug of the claim
        status, text = SKIP, 'the reward of day %s did not fit the backpack or the capacity (the server said so)' % a.get('slot')
    return {PASS: 'claimed', FAIL: 'fail', SKIP: 'skip'}[status], text


async def check_daily_claim(io, name, cls, level):
    key = 'daily_claim'
    outcome, text = await daily_claim_do(io)
    return Result(key, name, cls, {'claimed': PASS, 'fail': FAIL}.get(outcome, SKIP), text)


# ------------------------------------------------------------------------------------------------ the Ashen Chronicle, opened (O650)
# The Chronicle is the realm's story: a season of chapters that advance with what the players do. A tester's events never enter it (chronicle.lua
# memberList drops a tester) and no tester stands in a book, a top list or a season record. The bot opens the window like a person and the proof
# is the helper's read of the server (`!tester chronicle`: `counted` false, `testersListed` 0, no points of the bot) and the window's own lists.
def chronicle_verdict(a, reply):
    """(status, text) from the probe a and the window's state reply"""
    if not a.get('running'):
        return SKIP, 'no Chronicle season runs'
    names = []
    data = (reply or {}).get('data') if isinstance(reply, dict) else None
    for c in (data or {}).get('chapters') or []:
        names.extend(str(e.get('n') or '') for e in (c.get('top') or []) if isinstance(e, dict))
    for sn in (data or {}).get('record') or []:
        for c in (sn.get('chapters') or []):
            names.extend(str(e.get('n') or '') for e in (c.get('top') or []) if isinstance(e, dict))
    listed = [n for n in names if n.startswith('Tester ')]
    if a.get('counted'):
        return FAIL, 'an event of a tester would enter the chapter (counted)'
    if a.get('testersListed'):
        return FAIL, '%s tester row(s) stand in the books of the season' % a['testersListed']
    if a.get('mine'):
        return FAIL, 'the bot has %s point(s) in the Chronicle' % a['mine']
    if listed:
        return FAIL, 'the window lists a tester: %s' % listed[0][:40]
    seen = 'the window listed %d name(s)' % len(names) if data is not None else 'the window sent no state'
    return PASS, 'season %s, chapter %s of %s: the bot is not counted, no tester in the books (%s)' % (a.get('season'), a.get('chapter'), a.get('chapters'), seen)


async def check_chronicle_walk(io, name, cls, level):
    key = 'chronicle_walk'
    a = await io.helper('chronicle state', 'chronicle', ANSWER)
    if not isinstance(a, dict):
        return Result(key, name, cls, SKIP, 'no answer to !tester chronicle (old helper file)')
    if a.get('err'):
        return Result(key, name, cls, SKIP, str(a['err'])[:80])
    if not a.get('enabled'):
        return Result(key, name, cls, SKIP, 'the Chronicle is switched off')
    try:
        reply = await io.request('chronicle', 'open', {}, ['state'], ANSWER)
        await io.sleep(1.0)
        a = await io.helper('chronicle state', 'chronicle', ANSWER) or a
    finally:
        await io.request('chronicle', 'close', {}, [], ANSWER)
    status, text = chronicle_verdict(a, reply)
    return Result(key, name, cls, status, text)


# ------------------------------------------------------------------------------------------------ the chase: the Nemesis, a goblin, an invasion (O650)
# One loop for the three: a look every second (`!tester <system>`), the engine path to the guide's goal, the fight is the bot's own (its target and
# its rotation). c: cmd, budget, look(s, trace) -> True to stop
async def chase_play(io, r, trace, c):
    cmd = c['cmd']
    elapsed, misses, fight_since = 0.0, 0, None
    while io.alive() and elapsed < c['budget']:
        s = await io.helper('%s state' % cmd, cmd, ANSWER)
        if not isinstance(s, dict) or s.get('err'):
            misses += 1
            if misses >= SOLO_MISSES:
                break
            await io.sleep(RAID_LOOK)
            elapsed += RAID_LOOK
            continue
        misses = 0
        if c['look'](s, trace):
            break
        g = s.get('guide') or {}
        spent = await retreat_check(io, r, s, trace, g)   # O658: under 30 % health the bot heals and steps back before it goes on
        if spent:
            elapsed += spent
            continue
        mode = g.get('mode')
        if mode == 'fight':
            fight_since = elapsed if fight_since is None else fight_since
            trace['fought'] = max(trace['fought'], elapsed - fight_since)
        else:
            fight_since = None
        plan = []
        if mode == 'walk' and isinstance(g.get('goal'), dict) and isinstance(s.get('pos'), dict):
            plan = r['walker'].steps(s['pos'], g['goal'], SOLO_STEPS, elapsed)
            if not r['walker'].blocked:   # the engine's path first (walls, pillars); the side step only when the way is blocked
                got = await hcmd(io, r, '%s path' % cmd, cmd)
                steps = raid_path_steps((got or {}).get('path')) if isinstance(got, dict) and not got.get('err') else []
                plan = steps[:SOLO_STEPS] or plan
            if r['walker'].stuck(elapsed) >= SOLO_STUCK:
                trace['stuck'] = (s['pos']['x'], s['pos']['y'])
                break
        for step in plan:
            await raid_walk(io, r, step)
            trace['steps'] += 1
            await io.sleep(RAID_STEP)
            elapsed += RAID_STEP
        await io.loot()
        await io.sleep(RAID_LOOK)
        elapsed += RAID_LOOK
        trace['secs'] = int(elapsed)
    trace['secs'] = int(elapsed)
    trace['died'] = trace.get('died') or not io.alive()


def chase_text(t):
    return 'level %s, %d step(s) in %d s%s' % (t.get('level'), t.get('steps', 0), t.get('secs', 0),
                                              ('; teleport in place of walking: ' + ', '.join(t['fallbacks'])) if t.get('fallbacks') else '')


def new_trace(a, fallbacks, **extra):
    t = {'faults': [], 'steps': 0, 'fought': 0.0, 'stuck': None, 'died': False, 'secs': 0, 'fallbacks': fallbacks, 'level': a.get('level')}
    t.update(extra)
    return t


# ---- the Nemesis
NEMESIS_BUDGET = 240.0        # seconds the fight is played at most
NEMESIS_SIGHT_WAIT = 60.0     # seconds the bot hunts for a regular monster in sight (the TEST ONLY birth takes its type)
NEMESIS_ARRIVE_WAIT = 12.0    # seconds from the call to the Nemesis in the world (the warning, then the arrival)


def nemesis_look(s, t):
    t['avenged'] = s.get('avenged') if s.get('avenged') is not None else t.get('avenged')
    w = s.get('world')
    if isinstance(w, dict):
        t['seen'] = True
        t['hp'] = w['hp'] if t.get('hp') is None else min(t['hp'], w['hp'])
    if (t.get('avenged') or 0) > (t.get('base') or 0):
        t['killed'] = True
        if s.get('has'):
            t['faults'].append('the Nemesis fell and its record is still there')
        return True
    if t.get('seen') and not isinstance(w, dict) and s.get('has'):
        t['faded'] = True   # it vanished (its lifetime, a floor change): it comes back another time
        return True
    return False


def nemesis_walk_verdict(t):
    """(status, text) from the trace: faults, killed, avenged, base, hp (its lowest health percent), seen, faded, fought, stuck, died, steps, secs, level, name"""
    if t.get('faults'):
        return FAIL, '; '.join(t['faults'][:3])
    how = chase_text(t)
    if t.get('killed'):
        return PASS, '%s slain, avenged %s (the trophy and the title are its own) (%s)' % (t.get('name') or 'its Nemesis', t.get('avenged'), how)
    if t.get('hp') is not None and t['hp'] < 100:
        return PASS, '%s hurt to %s%% (%s)' % (t.get('name') or 'its Nemesis', t['hp'], how)
    if t.get('fought', 0) >= SOLO_FIGHT_MIN:
        return FAIL, 'fought %d s in reach of its Nemesis and its health did not move (damage, targets or the guard)' % t['fought']
    if t.get('stuck'):
        return SKIP, 'the walk was blocked at (%d, %d) for %d s (%s)' % (t['stuck'][0], t['stuck'][1], SOLO_STUCK, how)
    if t.get('died'):
        return SKIP, 'the bot fell to its Nemesis before it was hurt (level %s) (%s)' % (t.get('level'), how)
    if t.get('faded'):
        return SKIP, 'the Nemesis faded back into the shadows (%s)' % how
    return SKIP, 'its Nemesis was not hurt in %d s (%s)' % (t.get('secs', 0), how)


async def check_nemesis_walk(io, name, cls, level):
    """the TEST ONLY birth of a Nemesis from a regular monster in sight, the call that makes it appear, then the fight like a person's"""
    key = 'nemesis_walk'
    a = await io.helper('nemesis state', 'nemesis', ANSWER)
    if not isinstance(a, dict):
        return Result(key, name, cls, SKIP, 'no answer to !tester nemesis (old helper file)')
    if a.get('err'):
        return Result(key, name, cls, SKIP, str(a['err'])[:80])
    if not a.get('enabled'):
        return Result(key, name, cls, SKIP, 'the Nemesis is switched off')
    if int(a.get('level') or level or 0) < int(a.get('minLevel') or 0):
        return Result(key, name, cls, SKIP, 'level %s: a Nemesis is born from level %s' % (a.get('level'), a.get('minLevel')))
    r = {'name': name, 'lead': True, 'walker': RaidWalker(), 'inside': False}
    fallbacks = []
    trace = new_trace(a, fallbacks, base=a.get('avenged') or 0, avenged=a.get('avenged') or 0, seen=False, hp=None)
    io.raid_mode([name], True, keep_flee=True)
    try:
        if a.get('has'):   # a record left by an earlier run is the bot's own: it goes
            await io.helper('nemesis close', 'nemesis', ANSWER)
            a = await io.helper('nemesis state', 'nemesis', ANSWER) or a
        waited, sight = 0.0, a.get('sight')
        while not sight and waited < NEMESIS_SIGHT_WAIT and io.alive():
            await io.sleep(3.0)
            waited += 3.0
            s = await io.helper('nemesis state', 'nemesis', ANSWER)
            sight = s.get('sight') if isinstance(s, dict) else None
        if not sight:
            return Result(key, name, cls, SKIP, 'no regular monster in sight at the hunt in %d s' % int(waited))
        born = await io.helper('nemesis born', 'nemesis', HELPER_WAIT)
        if not isinstance(born, dict) or born.get('err') or not born.get('born'):
            return Result(key, name, cls, SKIP, 'the Nemesis was not born: %s' % str((born or {}).get('err') or 'no answer')[:70])
        called = await io.helper('nemesis appear', 'nemesis', HELPER_WAIT)
        if not isinstance(called, dict) or called.get('err') or not called.get('appear'):
            return Result(key, name, cls, SKIP, 'it was not called: %s' % str((called or {}).get('err') or 'no answer')[:70])
        waited, s = 0.0, None
        while waited <= NEMESIS_ARRIVE_WAIT and io.alive():
            await io.sleep(1.0)
            waited += 1.0
            s = await io.helper('nemesis state', 'nemesis', ANSWER)
            if isinstance(s, dict) and isinstance(s.get('world'), dict):
                break
        if not (isinstance(s, dict) and isinstance(s.get('world'), dict)):
            return Result(key, name, cls, SKIP, 'its Nemesis did not arrive in %d s' % int(NEMESIS_ARRIVE_WAIT))
        trace['name'] = ((s.get('nemesis') or {}).get('name')) or 'its Nemesis'
        await chase_play(io, r, trace, {'cmd': 'nemesis', 'budget': NEMESIS_BUDGET, 'look': nemesis_look})
        status, text = nemesis_walk_verdict(trace)
        return Result(key, name, cls, status, text, fallbacks)
    finally:
        await io.helper('nemesis close', 'nemesis', ANSWER)   # the world and the record go: the next run is born again
        io.raid_mode([name], False)
        await io.go('hunt')


# ---- the treasure goblin
GOBLIN_BUDGET = 180.0         # seconds the goblin is chased at most (it escapes 30 s after the first hit)


def goblin_look(s, t):
    t['killed'] = max(t.get('killed', 0), (s.get('killed') or 0) - t.get('killed0', 0))
    g = s.get('goblin')
    if isinstance(g, dict):
        t['seen'] = True
        t['hit'] = bool(t.get('hit') or g.get('hit'))
    if t['killed'] > 0:
        return True
    if t.get('seen') and not isinstance(g, dict):
        t['gone'] = True   # it escaped (30 s after the first hit) or its time ran out
        return True
    return False


def goblin_walk_verdict(t):
    """(status, text): faults, killed, hit, seen, gone, fought, stuck, died, steps, secs, level, fallbacks"""
    if t.get('faults'):
        return FAIL, '; '.join(t['faults'][:3])
    how = chase_text(t)
    if t.get('killed'):
        return PASS, 'killed the goblin of its own, its hoard is its own corpse (%s)' % how
    if t.get('hit'):
        return PASS, 'hit the goblin of its own, it escaped (%s)' % how
    if t.get('fought', 0) >= SOLO_FIGHT_MIN:
        return FAIL, 'fought %d s in reach of the goblin and did not hit it (damage, targets or the guard)' % t['fought']
    if t.get('stuck'):
        return SKIP, 'the walk was blocked at (%d, %d) for %d s (%s)' % (t['stuck'][0], t['stuck'][1], SOLO_STUCK, how)
    if t.get('died'):
        return SKIP, 'the bot died before it hit the goblin (%s)' % how
    return SKIP, 'the goblin was not hit in %d s (%s)' % (t.get('secs', 0), how)


async def check_goblin_walk(io, name, cls, level):
    """a treasure goblin of the bot's own (TEST ONLY, only while no player is near): it flees and blinks, the bot chases it by the engine path and hits it"""
    key = 'goblin_walk'
    a = await io.helper('goblin state', 'goblin', ANSWER)
    if not isinstance(a, dict):
        return Result(key, name, cls, SKIP, 'no answer to !tester goblin (old helper file)')
    if a.get('err'):
        return Result(key, name, cls, SKIP, str(a['err'])[:80])
    r = {'name': name, 'lead': True, 'walker': RaidWalker(), 'inside': False}
    fallbacks = []
    trace = new_trace(a, fallbacks, killed0=a.get('killed') or 0, killed=0, hit=False, seen=False)
    io.raid_mode([name], True, keep_flee=True)
    try:
        if a.get('goblin'):
            await io.helper('goblin close', 'goblin', ANSWER)
        made = await io.helper('goblin spawn', 'goblin', HELPER_WAIT)
        if not isinstance(made, dict) or made.get('err') or not made.get('spawned'):
            return Result(key, name, cls, SKIP, 'no goblin of its own: %s' % str((made or {}).get('err') or 'no answer')[:70])
        await io.sleep(SETTLE)
        await chase_play(io, r, trace, {'cmd': 'goblin', 'budget': GOBLIN_BUDGET, 'look': goblin_look})
        status, text = goblin_walk_verdict(trace)
        return Result(key, name, cls, status, text, fallbacks)
    finally:
        await io.helper('goblin close', 'goblin', ANSWER)
        io.raid_mode([name], False)
        await io.go('hunt')


# ---- an invasion
INVASION_BUDGET = 150.0       # seconds the bot walks and fights at an invasion at most


def invasion_look(s, t):
    t['cancelled'] = s.get('cancelled') or 0
    t['invader'] = t.get('invader') or isinstance(s.get('invader'), dict)
    if s.get('credited'):
        t['faults'].append('a tester stands in the contribution book of the invasion (it would take a share of the players)')
        return True
    return t['cancelled'] >= 1 or not s.get('running')


def invasion_walk_verdict(t):
    """(status, text): faults, cancelled, invader, fought, stuck, died, steps, secs, level"""
    if t.get('faults'):
        return FAIL, '; '.join(t['faults'][:3])
    how = chase_text(t)
    if t.get('cancelled', 0) >= 1:
        return PASS, '%d hit(s) of the bot on invaders were cancelled, it is in no contribution book (%s)' % (t['cancelled'], how)
    if t.get('fought', 0) >= SOLO_FIGHT_MIN:
        return FAIL, 'fought %d s in reach of an invader and no hit was cancelled (the hits landed: the rule did not hold)' % t['fought']
    if t.get('stuck'):
        return SKIP, 'the walk was blocked at (%d, %d) for %d s (%s)' % (t['stuck'][0], t['stuck'][1], SOLO_STUCK, how)
    if t.get('died'):
        return SKIP, 'the bot died at the invasion (%s)' % how
    return SKIP, 'no hit of the bot reached an invader in %d s (%s)' % (t.get('secs', 0), how)


async def check_invasion_walk(io, name, cls, level):
    """while an invasion runs: the bot walks to it by the engine path and fights the invaders; the invasion is the players', so its hits are cancelled
    and it stands in no contribution book (it takes no share of the reward)"""
    key = 'invasion_walk'
    a = await io.helper('invasion state', 'invasion', ANSWER)
    if not isinstance(a, dict):
        return Result(key, name, cls, SKIP, 'no answer to !tester invasion (old helper file)')
    if a.get('err'):
        return Result(key, name, cls, SKIP, str(a['err'])[:80])
    if not a.get('running'):
        return Result(key, name, cls, SKIP, 'no invasion is running (phase %s)' % a.get('phase'))
    r = {'name': name, 'lead': True, 'walker': RaidWalker(), 'inside': False}
    fallbacks = []
    trace = new_trace(a, fallbacks, cancelled=a.get('cancelled') or 0)
    io.raid_mode([name], True, keep_flee=True)
    try:
        await chase_play(io, r, trace, {'cmd': 'invasion', 'budget': INVASION_BUDGET, 'look': invasion_look})
        status, text = invasion_walk_verdict(trace)
        return Result(key, name, cls, status, text, fallbacks)
    finally:
        io.raid_mode([name], False)
        await io.go('hunt')


# ---- Vael Ashmourn
VAEL_BUDGET = 330.0           # seconds Vael's chamber is played at most (the trial's own clock is longer)


def vael_walk_verdict(t):
    """(status, text): faults, killed (thralls), boss_seen, hp (Vael's lowest health percent), fought, stuck, died, steps, secs, level, came, fallbacks"""
    if t.get('faults'):
        return FAIL, '; '.join(t['faults'][:3])
    how = solo_text(t, 'chamber')
    if t.get('boss_seen') and t.get('hp') is not None and t['hp'] < 100:
        return PASS, "Vael hurt to %s%% (%d thrall(s) killed) (%s)" % (t['hp'], t.get('killed', 0), how)
    if t.get('killed', 0) >= 1:
        return PASS, '%d thrall(s) killed in Vael\'s chamber (%s)' % (t['killed'], how)
    if t.get('fought', 0) >= SOLO_FIGHT_MIN:
        return FAIL, 'fought %d s in Vael\'s chamber and killed none (damage, targets or the monsters)' % t['fought']
    if t.get('puzzle'):
        return SKIP, 'the %s stage is a puzzle the bots do not play' % t['puzzle']
    if t.get('stuck'):
        return SKIP, 'the walk was blocked at (%d, %d) for %d s (%s)' % (t['stuck'][0], t['stuck'][1], SOLO_STUCK, how)
    if t.get('died'):
        return SKIP, "the bot's lives ran out before a thrall died (%s lives left, level %s) (%s)" % (t.get('lives', '?'), t.get('level'), how)
    return SKIP, 'nothing was killed in %d s (%s)' % (t.get('secs', 0), how)


async def check_vael_walk(io, name, cls, level):
    """the boss of the main quest through the TEST ONLY door (a tester from level 500; the quest step and the resistances left out): the temple on
    foot, the chamber, the thralls and Vael by the engine path, the bot's own rotation, the Leave button"""
    key = 'vael_walk'
    a = await io.helper('vael state', 'vael', ANSWER)
    refused = solo_refusal(a, 'vael', "Vael's chamber", level)
    if refused:
        return Result(key, name, cls, refused[0], refused[1])
    if not a.get('family'):
        return Result(key, name, cls, SKIP, 'the vocation of the bot has no trial family')
    if a.get('puzzle'):
        return Result(key, name, cls, SKIP, 'the first stage of the trial of %s is a seals or marks puzzle the bots do not play' % a.get('family'))
    r = {'name': name, 'lead': True, 'walker': RaidWalker(), 'inside': False}
    fallbacks = []
    trace = {'faults': [], 'steps': 0, 'killed': 0, 'fought': 0.0, 'stuck': None, 'died': False, 'secs': 0, 'came': 'foot', 'fallbacks': fallbacks,
             'level': a.get('level'), 'boss_seen': False, 'hp': None}
    io.raid_mode([name], True, keep_flee=True)
    try:
        why = await solo_to_temple(io, r, trace, fallbacks, need_pz=True, system='vael')
        if why:
            return Result(key, name, cls, SKIP, why.replace('the descent', "Vael's door"), fallbacks)
        entered = await io.helper('vael enter', 'vael', HELPER_WAIT)
        if not isinstance(entered, dict) or entered.get('err') or not entered.get('entered'):
            return Result(key, name, cls, SKIP, "Vael's door stayed shut: %s" % str((entered or {}).get('err') or 'no answer')[:70], fallbacks)
        await io.sleep(SETTLE)
        await solo_play(io, r, trace, {
            'system': 'vael', 'budget': VAEL_BUDGET, 'problems': trial_problems, 'stop': trial_stop,
            'done': lambda t: t.get('killed', 0) >= 1 and t.get('boss_seen') and t.get('hp') is not None and t['hp'] < 100,
            'made': lambda t: t.get('killed', 0) > 0,
            'mark': lambda s: ((s.get('run') or {}).get('stageIdx'), (s.get('run') or {}).get('killed'), (s.get('run') or {}).get('monsters'))})
        await io.helper('vael close', 'vael', ANSWER)
        again = await io.helper('vael state', 'vael', ANSWER)
        if isinstance(again, dict) and again.get('inside'):
            trace['faults'].append("the bot is still inside Vael's chamber after the close")
        status, text = vael_walk_verdict(trace)
        return Result(key, name, cls, status, text, fallbacks)
    finally:
        await io.helper('vael close', 'vael', ANSWER)
        io.raid_mode([name], False)
        await io.go('hunt')


# ------------------------------------------------------------------------------------------------ economy, crafting and progression chores (O653)
# What a person does with what the game gave it, played with the windows' own requests and read back from the windows' own answers: no helper grant of
# an item (`!tester found` only READS the backpack and the worn gear). The server side is closed so that a tester never shares a board or a reward
# pool with a player (season ladders skip testers, the weekly chest gives a tester nothing); the checks prove the rest by play.
FOUND_PIECES = 3      # backpack pieces the bot spends its orbs on at most
FOUND_ORBS = 8        # orbs spent on one piece at most
CHORE_NEAR = 3        # tiles from an NPC the walk may end (the shop windows need the NPC near)


def found_next_orb(st, counts):
    """the orb a person spends next on the piece the bench shows (st: the bench's item) from the orbs it holds (counts: orb key -> number):
    (orb key, label) or None. A normal piece gets Gilding or Awakening, a piece with room gets Grafting, then the Whetstone up to the quality cap,
    then Sockets up to the maximum. A unique, a ruined or a corrupted piece gets nothing."""
    if not isinstance(st, dict) or st.get('unique') or st.get('corrupted') or st.get('ruined'):
        return None
    counts = counts if isinstance(counts, dict) else {}

    def have(k):
        return int(counts.get(k) or 0) > 0
    rarity = int(st.get('rarity') or 0)
    mods, room = len(st.get('mods') or []), int(st.get('maxMods') or 0)
    if rarity == 0:
        if have('alchemy'):
            return 'alchemy', 'Orb of Gilding'
        if have('transmutation'):
            return 'transmutation', 'Orb of Awakening'
    elif 0 < rarity <= 2 and mods < room and have('exalted'):
        return 'exalted', 'Orb of Grafting'
    if int(st.get('quality') or 0) < int(st.get('qualityCap') or 0) and have('whetstone'):
        return 'whetstone', 'Whetstone'
    socks = st.get('sockets') if isinstance(st.get('sockets'), dict) else {}
    if int(socks.get('count') or 0) < int(socks.get('max') or 0) and have('sockets'):
        return 'sockets', 'Orb of Sockets'
    return None


def found_totals(rep):
    """(orbs {key: n}, gems, runes) the bot holds, from the answer of `!tester found`"""
    orbs = {str(k): int(v or 0) for k, v in ((rep or {}).get('orbs') or {}).items()}
    gems = sum(int(d.get('n') or 1) for d in (rep or {}).get('drops') or [] if d.get('k') == 'gem')
    runes = sum(int(d.get('n') or 1) for d in (rep or {}).get('drops') or [] if d.get('k') == 'rune')
    return orbs, gems, runes


async def found_look(io):
    """`!tester found`: (answer, None) or (None, the reason)"""
    a = await io.helper('found', 'found', HELPER_WAIT)
    if not isinstance(a, dict):
        return None, 'no answer to !tester found (old helper file)'
    if a.get('err'):
        return None, str(a['err'])[:80]
    return a, None


def craft_found_verdict(t):
    """(status, text) from the trace {'faults', 'orbs' [label], 'gems', 'runes', 'notes', 'had'}"""
    if t['faults']:
        return FAIL, '; '.join(t['faults'][:3])
    if t['orbs'] or t['gems'] or t['runes']:
        parts = []
        if t['orbs']:
            parts.append('%d orb(s) (%s)' % (len(t['orbs']), ', '.join(sorted(set(t['orbs'])))))
        if t['gems']:
            parts.append('%d gem(s) socketed' % t['gems'])
        if t['runes']:
            parts.append('%d rune(s) into a spell' % t['runes'])
        return PASS, 'spent what it found: %s; the tooltip and the bench agree, every orb used was counted off%s' % (
            ', '.join(parts), ' (%s)' % '; '.join(t['notes'][:2]) if t['notes'] else '')
    return SKIP, 'nothing could be spent: %s' % ('; '.join(t['notes'][:3]) or 'no piece in the backpack takes what the bot holds')


async def check_craft_found(io, name, cls, level):
    """the orbs, gems and runes the bot dropped, spent on pieces in its backpack by the windows' own requests (the bench takes no worn piece:
    a person takes the piece off, crafts it and wears it again; gear_chase wears it). SKIP while the bot has dropped nothing to spend."""
    key = 'craft_found'
    bench = Bench(io, name, cls, key)
    rep, why = await found_look(io)
    if rep is None:
        return bench.skip(why)
    orbs, gems, runes = found_totals(rep)
    t = {'faults': [], 'orbs': [], 'gems': 0, 'runes': 0, 'notes': [], 'had': (orbs, gems, runes)}
    if not (sum(orbs.values()) or gems or runes):
        return bench.skip('the bot has dropped no orbs, gems or runes yet (it is given none: the check spends only what it found)')
    pieces = sorted((p for p in rep.get('pieces') or [] if not p.get('unique')), key=lambda p: -int(p.get('chase') or 0))[:FOUND_PIECES]
    await io.open_bag(rep.get('bagClientId'))
    await io.sleep(1.0)
    for p in pieces if sum(orbs.values()) else []:
        item = {'index': p['i'], 'id': p['id'], 'clientId': p['cid']}
        before, st = await bench.view(item)
        if before is None:
            t['notes'].append('no tooltip or bench answer for the piece in slot %s' % p['i'])
            continue
        for _ in range(FOUND_ORBS):
            step = found_next_orb(st, bench.counts)
            if not step:
                break
            orb, label = step
            held = int(bench.counts.get(orb) or 0)
            res = await bench.apply(orb, item, st)
            if res is None:
                t['notes'].append('no answer to the %s' % label)
                break
            if not res.get('ok'):
                t['notes'].append('%s refused: %s' % (label, str(res.get('text'))[:50]))
                break
            after, st2 = await bench.view(item)
            if after is None:
                t['notes'].append('no tooltip or bench answer after the %s' % label)
                break
            problems = orb_problems(orb, before, after)
            if orb != 'sockets' and after['tip'] == before['tip']:
                problems.append('the tooltip did not change')
            if int(bench.counts.get(orb) or 0) != held - 1:
                problems.append('the bench counts %s %s after one was spent, it held %d' % (bench.counts.get(orb), orb, held))
            if problems:
                t['faults'].append('%s: %s' % (label, '; '.join(problems[:3])))
                return Result(key, name, cls, *craft_found_verdict(t))
            t['orbs'].append(label)
            before, st = after, st2
    if gems:
        again, _ = await found_look(io)
        gem = next((d for d in (again or {}).get('drops') or [] if d.get('k') == 'gem'), None)
        ranked = sorted((again or {}).get('pieces') or [], key=lambda p: -int(p.get('chase') or 0))[:FOUND_PIECES] if gem else []
        for p in ranked:
            item = {'index': p['i'], 'id': p['id'], 'clientId': p['cid']}
            before, st = await bench.view(item)
            if before is None or before['sockets'] <= before['socketed']:
                continue
            await io.use_with(gem['i'], gem['cid'], p['i'], p['cid'])
            await io.sleep(1.5)
            item = slot_after_use({'index': gem['i']}, item, gem.get('n'))   # O660: see check_craft_gems
            after, _ = await bench.view(item)
            if after is None:
                t['notes'].append('no tooltip or bench answer after the gem')
            elif after['socketed'] != before['socketed'] + 1:
                t['faults'].append('gems in the sockets %d -> %d after the use-with: expected one more' % (before['socketed'], after['socketed']))
            elif after['tip'] == before['tip']:
                t['faults'].append('the gem sits in the socket but the tooltip did not change')
            else:
                t['gems'] += 1
            break
        else:
            t['notes'].append('no gem drop met a piece with a free socket')
    if runes:
        ans = await io.request('supports', 'open', {}, ('state',), ANSWER)
        spells = [s for s in (((ans or {}).get('data') or {}).get('spells') or []) if isinstance(s, dict)]
        spell = next((s for s in spells if spell_has_room(s)), None)
        rune = next((d for d in rep.get('drops') or [] if d.get('k') == 'rune'), None)
        if spell and rune:
            res = await io.request('supports', 'socket', {'spell': spell['id'], 'rune': rune['id']}, ('result',), ANSWER)
            data = (res or {}).get('data') or {}
            if res is None:
                t['notes'].append('no answer to the rune')
            elif not data.get('ok'):
                t['notes'].append('the rune was refused: %s' % str(data.get('text'))[:50])
            else:
                ans = await io.request('supports', 'open', {}, ('state',), ANSWER)
                now = next((s for s in (((ans or {}).get('data') or {}).get('spells') or []) if isinstance(s, dict) and s.get('id') == spell['id']), None)
                if now is not None and spell_runes(now) != spell_runes(spell) + 1:
                    t['faults'].append('spell %s holds %s runes after the socket, expected %d' % (
                        spell.get('name') or spell['id'], spell_runes(now), spell_runes(spell) + 1))
                else:
                    t['runes'] += 1
        else:
            t['notes'].append('no spell with a free support socket')
    return Result(key, name, cls, *craft_found_verdict(t))


def chase_pick(rep):
    """the piece `!tester found` ranks first: the row of `pieces` that is the answer's `best` (the chase score knows sets, uniques and jewelry),
    or None when nothing beats what is worn"""
    best = (rep or {}).get('best')
    return next((p for p in (rep or {}).get('pieces') or [] if p.get('i') == best), None) if best is not None else None


def chase_kind(p):
    return 'a set piece (%s)' % p['set'] if p.get('set') else 'a unique' if p.get('unique') else 'a jewel' if p.get('jewelry') else 'a better piece'


def gear_chase_verdict(p, a, b):
    """(status, text) for the wear of piece p: a / b the answers of `!tester found` before and after"""
    if not isinstance(b, dict):
        return SKIP, 'no answer to !tester found after the wear'
    slot = p.get('s')
    wn = next((w for w in b.get('worn') or [] if w.get('s') == slot), None)
    wb = next((w for w in a.get('worn') or [] if w.get('s') == slot), None)
    still = next((q for q in b.get('pieces') or [] if q.get('id') == p.get('id') and q.get('i') == p.get('i')), None)
    if still is not None and wn == wb:
        return SKIP, 'the server kept %s in the bag (a level or class rule: not a fault)' % chase_kind(p)
    if wn is None:
        return FAIL, 'the slot %s is empty after %s was moved there' % (slot, chase_kind(p))
    if p.get('set') and (b.get('sets') or {}).get(p['set'], 0) < (a.get('sets') or {}).get(p['set'], 0):
        return FAIL, 'the worn pieces of the set %s fell from %s to %s after one was worn' % (
            p['set'], (a.get('sets') or {}).get(p['set'], 0), (b.get('sets') or {}).get(p['set'], 0))
    return PASS, 'wore %s (chase %s, score %s over %s)%s' % (
        chase_kind(p), p.get('chase'), p.get('sc'), (wb or {}).get('sc', 0),
        ', the set counts %s' % (b.get('sets') or {}).get(p['set']) if p.get('set') else '')


async def check_gear_chase(io, name, cls, level):
    """the piece whose score knows sets, uniques and jewelry beats the worn one: wear it as a person drags it onto the paper doll"""
    key = 'gear_chase'
    a, why = await found_look(io)
    if a is None:
        return Result(key, name, cls, SKIP, why)
    p = chase_pick(a)
    if p is None:
        return Result(key, name, cls, SKIP, 'no piece in the backpack beats what the bot wears (%d piece(s) looked at)' % len(a.get('pieces') or []))
    await io.wear(p['i'], p['cid'], p['s'])
    await io.sleep(1.5)
    b, _ = await found_look(io)
    status, text = gear_chase_verdict(p, a, b)
    return Result(key, name, cls, status, text)


# the daily chores of a character, each played in its window to a result the window shows. A tester is on no season board and gets no chest from the
# pool (the server's rules, tested in Lua); here is the bot's own side: what its windows show and what its requests do.
def faction_verdict(a, b, turned):
    """(status, text) from the faction windows before (a) and after (b) a turn-in of `turned` = (faction key, tokens held) or None"""
    fa = (a or {}).get('factions') or []
    if not fa:
        return SKIP, 'the faction window listed no faction'
    contracts = (a or {}).get('contracts') or []
    for f in fa:
        if f.get('rep') is not None and int(f['rep']) < 0:
            return FAIL, 'faction %s shows %s reputation' % (f.get('k'), f['rep'])
    for c in contracts:
        if int(c.get('p') or 0) > int(c.get('n') or 0) > 0:
            return FAIL, 'contract %s shows %s of %s' % (c.get('key'), c.get('p'), c.get('n'))
    if turned:
        k, held = turned
        fb = next((f for f in (b or {}).get('factions') or [] if f.get('k') == k), None)
        fo = next((f for f in fa if f.get('k') == k), None)
        if fb is None or fo is None:
            return SKIP, 'no answer after the turn-in'
        if int(fb.get('tok') or 0) >= held:
            return FAIL, 'the %s tokens were not taken by the turn-in (%s held before, %s after)' % (k, held, fb.get('tok'))
        if int(fb.get('rep') or 0) <= int(fo.get('rep') or 0) and int(fb.get('wk') or 0) < int(fb.get('wc') or 0):
            return FAIL, 'the turn-in of %s tokens to %s gave no reputation (%s -> %s)' % (held, k, fo.get('rep'), fb.get('rep'))
        return PASS, '%s tokens of %s turned in: reputation %s -> %s, rank %s; %d contract(s) listed' % (
            held, k, fo.get('rep'), fb.get('rep'), fb.get('rn'), len(contracts))
    return PASS, 'the faction window lists %d factions and %d contract(s); nothing to turn in yet' % (len(fa), len(contracts))


async def check_chore_faction(io, name, cls, level):
    """the reputation window: factions, ranks, contracts; the tokens the bot holds are turned in and the reputation must rise"""
    key = 'chore_faction'
    reply = await io.request('factions', 'open', {}, ('state',), ANSWER)
    a = (reply or {}).get('data') if isinstance(reply, dict) else None
    if not isinstance(a, dict):
        return Result(key, name, cls, SKIP, 'no state in the faction window (not open at this level, or no answer)')
    turned = next(((f['k'], int(f['tok'])) for f in a.get('factions') or [] if int(f.get('tok') or 0) > 0 and f.get('k')), None)
    b = a
    try:
        if turned:
            await io.request('factions', 'turnin', {'f': turned[0]}, ('state',), ANSWER)
            await io.sleep(1.0)
            again = await io.request('factions', 'open', {'f': turned[0]}, ('state',), ANSWER)
            b = (again or {}).get('data') if isinstance(again, dict) else None
    finally:
        await io.request('factions', 'close', {}, [], ANSWER)
    status, text = faction_verdict(a, b, turned)
    return Result(key, name, cls, status, text)


def pass_claimable(st):
    """the free tiers a character has reached and not claimed, from the season pass state: [tier]"""
    if not isinstance(st, dict) or not (st.get('season') or {}).get('id'):
        return []
    claimed = (st.get('claimed') or ['', ''])[0] or ''
    return [t for t in range(1, int(st.get('tier') or 0) + 1) if t <= len(claimed) and claimed[t - 1] == '0']


def chore_pass_verdict(a, b):
    """(status, text) from the season pass state before (a) and after (b) a claimAll"""
    if not isinstance(a, dict) or not (a.get('season') or {}).get('id'):
        return SKIP, 'no season pass runs (or the character is under its level)'
    todo = pass_claimable(a)
    if not todo:
        return PASS, 'tier %s reached, every free tier claimed (the window answered, nothing to claim yet)' % a.get('tier')
    if not isinstance(b, dict) or not (b.get('season') or {}).get('id'):
        return SKIP, 'no state after the claim'
    left = pass_claimable(b)
    if len(left) >= len(todo):
        return FAIL, 'claimAll left %d of %d reachable free tier(s) unclaimed' % (len(left), len(todo))
    return PASS, 'claimed %d free tier(s) of %d reachable (tier %s)' % (len(todo) - len(left), len(todo), a.get('tier'))


async def check_chore_pass(io, name, cls, level):
    """the season pass: open, claim what the tier reached holds, read it back; the seasonal journey is a season character's (a tester walks none)"""
    key = 'chore_pass'
    reply = await io.request('seasonPass', 'open', {}, ('state',), ANSWER)
    a = (reply or {}).get('data') if isinstance(reply, dict) else None
    if not isinstance(a, dict):
        return Result(key, name, cls, SKIP, 'no state in the season pass window (below its level, or no answer)')
    b = a
    if pass_claimable(a):
        await io.request('seasonPass', 'claimAll', {}, ('state',), ANSWER)
        await io.sleep(1.0)
        again = await io.request('seasonPass', 'open', {}, ('state',), ANSWER)
        b = (again or {}).get('data') if isinstance(again, dict) else None
    status, text = chore_pass_verdict(a, b)
    return Result(key, name, cls, status, text)


def chests_verdict(week, cache):
    """(status, text) from the Weekly Chest state and the Ember Cache state. A tester never gets the Weekly Chest (the pool is the players'): the
    window opens and shows nothing given and no chest count; the Ember Cache is the bot's own and its book must answer"""
    if not isinstance(week, dict):
        return SKIP, 'no state in the Weekly Chest window'
    if (week.get('chest') or {}).get('given') or int(week.get('chests') or 0) > 0:
        return FAIL, "a tester has a Weekly Chest (given %s, %s opened): the reward pool is the players'" % (
            (week.get('chest') or {}).get('given'), week.get('chests'))
    if int(week.get('got') or 0) > 0:
        return FAIL, 'a tester has %s activities marked in the Weekly Chest' % week.get('got')
    if not isinstance(cache, dict):
        return SKIP, 'the Weekly Chest gave a tester nothing, as it must; no state in the Ember Cache window'
    return PASS, 'Weekly Chest: nothing for a tester (0 of %s activities); Ember Cache window answered (week %s)' % (week.get('need'), cache.get('week'))


async def check_chore_chests(io, name, cls, level):
    key = 'chore_chests'
    try:
        w = await io.request('weeklyChest', 'open', {}, ('state',), ANSWER)
        c = await io.request('emberCache', 'open', {}, ('state',), ANSWER)
    finally:
        await io.request('weeklyChest', 'close', {}, [], ANSWER)
        await io.request('emberCache', 'close', {}, [], ANSWER)
    status, text = chests_verdict((w or {}).get('data') if isinstance(w, dict) else None, (c or {}).get('data') if isinstance(c, dict) else None)
    return Result(key, name, cls, status, text)


def candle_pick(st, level):
    """the offer a person buys with its candlemarks: the cheapest item offer it can pay, has the level for, and has not used up this week"""
    if not isinstance(st, dict):
        return None
    bal = int(st.get('balance') or 0)
    cands = [o for o in st.get('offers') or [] if o.get('kind') == 'item' and not o.get('own') and 0 < int(o.get('p') or 0) <= bal
             and int(o.get('l') or 0) <= int(level or 0) and (int(o.get('w') or 0) == 0 or int(o.get('u') or 0) < int(o.get('w') or 0))]
    cands.sort(key=lambda o: (int(o['p']), str(o.get('k'))))
    return cands[0] if cands else None


def candle_verdict(offer, a, b, res):
    """(status, text) for a purchase: the balance must fall by the price and the window says it worked"""
    d = (res or {}).get('data') if isinstance(res, dict) else None
    if res is None:
        return SKIP, 'no answer to the Candlemarks purchase'
    if isinstance(d, dict) and d.get('ok') is False:
        return SKIP, 'the shop refused %s: %s' % (offer.get('k'), str(d.get('text'))[:60])
    if not isinstance(b, dict):
        return SKIP, 'no state after the purchase'
    spent = int(a.get('balance') or 0) - int(b.get('balance') or 0)
    if spent != int(offer['p']):
        return FAIL, 'bought %s for %s candlemarks and the balance fell by %s (%s -> %s)' % (offer.get('k'), offer['p'], spent, a.get('balance'), b.get('balance'))
    return PASS, 'bought %s for %s candlemarks, balance %s -> %s' % (offer.get('k'), offer['p'], a.get('balance'), b.get('balance'))


async def chore_walk(io, name, npc, near=CHORE_NEAR):
    """on foot to an NPC for a shop window; (None, fallbacks) or (the reason, [])
    O656: a talk (hi, a keyword, a trade by words) needs `near` 1: in the hub the nearest NPC answers a greeting (chaos_npc_focus.lua), and 3 tiles
    away it was Mordecai or Cassian, not the Oracle, the Archivist or the Broker"""
    how, got, note = await walk_to_place(io, {'name': name, 'lead': True}, 'npc ' + npc, None, near)
    if how not in ('foot', 'helper'):
        return how[:110], []
    return None, [note] if note else []


async def check_chore_candlemarks(io, name, cls, level):
    """Osric the Chandler: the window, the cheapest item offer the bot can pay (the candlemarks come from time online: a new bot may have none)"""
    key = 'chore_candlemarks'
    why, fallbacks = await chore_walk(io, name, 'Osric the Chandler')
    if why:
        return Result(key, name, cls, SKIP, why)
    try:
        reply = await io.request('candlemarks', 'open', {}, ('state',), ANSWER)
        a = (reply or {}).get('data') if isinstance(reply, dict) else None
        if not isinstance(a, dict):
            return Result(key, name, cls, SKIP, 'no state in the Candlemarks window', fallbacks)
        offer = candle_pick(a, level)
        if offer is None:
            return Result(key, name, cls, PASS if a.get('offers') else SKIP,
                          'the shop lists %d offer(s); the balance of %s buys none (the marks come with time online)' % (
                              len(a.get('offers') or []), a.get('balance')), fallbacks)
        res = await io.request('candlemarks', 'buy', {'k': offer['k']}, ('result',), ANSWER)
        await io.sleep(1.0)
        again = await io.request('candlemarks', 'open', {}, ('state',), ANSWER)
        status, text = candle_verdict(offer, a, (again or {}).get('data') if isinstance(again, dict) else None, res)
        return Result(key, name, cls, status, text, fallbacks)
    finally:
        await io.request('candlemarks', 'close', {}, [], ANSWER)


def gamble_pick(st):
    """the cheapest unsold piece of the Gambler's stock the bot can pay: the row of `items`, or None"""
    if not isinstance(st, dict):
        return None
    money = int(st.get('money') or 0)
    rows = [e for e in st.get('items') or [] if not e.get('sold') and 0 < int(e.get('p') or 0) <= money]
    rows.sort(key=lambda e: (int(e['p']), int(e.get('i') or 0)))
    return rows[0] if rows else None


def gamble_verdict(row, a, b, used_before, used_after):
    """(status, text) for a purchase: the money falls by the price, the row is marked sold, the backpack holds one more thing"""
    if not isinstance(b, dict):
        return SKIP, 'no state after the purchase'
    spent = int(a.get('money') or 0) - int(b.get('money') or 0)
    if spent != int(row['p']):
        return FAIL, 'bought stock %s for %s gold and the money fell by %s (%s -> %s)' % (row.get('i'), row['p'], spent, a.get('money'), b.get('money'))
    now = next((e for e in b.get('items') or [] if e.get('i') == row.get('i')), None)
    if now is not None and not now.get('sold'):
        return FAIL, 'stock %s was paid for and is not marked sold' % row.get('i')
    if used_before is not None and used_after is not None and used_after <= used_before:
        return FAIL, 'stock %s (%s) was paid for and the backpack holds no new item (%s -> %s slots)' % (row.get('i'), row.get('n'), used_before, used_after)
    return PASS, 'bought %s (%s) for %s gold: marked sold, the bag holds it' % (row.get('n'), row.get('sn'), row['p'])


async def check_chore_gamble(io, name, cls, level):
    """Mordecai Ashwager, the Gambler: the cheapest sealed piece the bot can pay, bought through the window; the item must be in the bag"""
    key = 'chore_gamble'
    why, fallbacks = await chore_walk(io, name, 'Mordecai Ashwager')
    if why:
        return Result(key, name, cls, SKIP, why)
    try:
        reply = await io.request('gamble', 'open', {}, ('state',), ANSWER)
        a = (reply or {}).get('data') if isinstance(reply, dict) else None
        if not isinstance(a, dict):
            return Result(key, name, cls, SKIP, 'no state in the Gambler window (under its level, or no answer)', fallbacks)
        row = gamble_pick(a)
        if row is None:
            return Result(key, name, cls, SKIP, 'the Gambler has %d piece(s); the bot has %s gold for none' % (len(a.get('items') or []), a.get('money')), fallbacks)
        bag0 = await io.helper('bag', 'bag', HELPER_WAIT)
        await io.sleep(GAMBLE_GAP)   # O660: the window answers one request in 300 ms (cfg.requestMs): a buy right after the open is dropped, unanswered
        bought = await io.request('gamble', 'buy', {'i': row['i'], 'w': a.get('w'), 'id': row.get('id')}, ('state', 'result'), ANSWER)
        await io.sleep(1.0)
        again = await io.request('gamble', 'open', {}, ('state',), ANSWER)
        bag1 = await io.helper('bag', 'bag', HELPER_WAIT)
        status, text = gamble_verdict(row, a, (again or {}).get('data') if isinstance(again, dict) else None,
                                      (bag0 or {}).get('used') if isinstance(bag0, dict) else None,
                                      (bag1 or {}).get('used') if isinstance(bag1, dict) else None)
        if status == FAIL and gamble_refused(bought):   # O660: the server said no and charged nothing: a refusal, not a free purchase
            status, text = SKIP, 'the Gambler refused the purchase: %s' % gamble_refusal(bought, None)
        return Result(key, name, cls, status, text, fallbacks)
    finally:
        await io.request('gamble', 'close', {}, [], ANSWER)


def trade_verdict(a, b, res):
    """(status, text) from the Professions state before (a) and after (b) `sellAll` at a Material Broker; res: the window's result"""
    if not isinstance(a, dict):
        return SKIP, 'no state in the Professions window'
    held = sum(int(r.get('h') or 0) for r in a.get('demand') or [])
    if held <= 0:
        return SKIP, 'the bot holds no gathered material to sell (the gathering with a pick, sickle, knife or rod is not played: README O653)'
    left = sum(int(r.get('h') or 0) for r in (b or {}).get('demand') or []) if isinstance(b, dict) else None
    d = (res or {}).get('data') if isinstance(res, dict) else None
    if isinstance(d, dict) and d.get('ok') is False:
        return FAIL, 'the Material Broker refused %s material(s): %s' % (held, str(d.get('text'))[:60])
    if left is None:
        return SKIP, 'no state after the sale'
    if left >= held:
        return FAIL, 'sellAll left all %s material(s) unsold' % held
    return PASS, 'sold %s of %s gathered material(s) to the Material Broker' % (held - left, held)


async def check_chore_trade(io, name, cls, level):
    """the Material Broker: sell what the bot gathered (sellAll); the held count of the window must fall"""
    key = 'chore_trade'
    why, fallbacks = await chore_walk(io, name, 'Material Broker')
    if why:
        return Result(key, name, cls, SKIP, why)
    try:
        reply = await io.request('professions', 'open', {}, ('state',), ANSWER)
        a = (reply or {}).get('data') if isinstance(reply, dict) else None
        res, b = None, None
        if isinstance(a, dict) and sum(int(r.get('h') or 0) for r in a.get('demand') or []) > 0:
            res = await io.request('professions', 'sellAll', {}, ('result',), ANSWER)
            await io.sleep(1.0)
            again = await io.request('professions', 'open', {}, ('state',), ANSWER)
            b = (again or {}).get('data') if isinstance(again, dict) else None
        status, text = trade_verdict(a, b, res)
        return Result(key, name, cls, status, text, fallbacks)
    finally:
        await io.request('professions', 'close', {}, [], ANSWER)


def salvage_pick(rep, items):
    """a rolled piece of no use to the bot, from the bench's list: no better than what it wears (chase 0 or less in `!tester found`), not a unique, not
    locked, with a rarity; the first one listed, or None"""
    useless = {str(p['i']) for p in (rep or {}).get('pieces') or [] if int(p.get('chase') or 0) <= 0 and not p.get('unique')}
    for it in items or []:
        if str(it.get('path')) in useless and int(it.get('rarity') or 0) >= 1 and not it.get('unique') and not it.get('locked'):
            return it
    return None


def salvage_verdict(item, a, b, res):
    """(status, text) from the bench state before (a) and after (b) the salvage of `item`; res: the window's result"""
    d = (res or {}).get('data') if isinstance(res, dict) else None
    if res is None:
        return SKIP, 'no answer to the salvage'
    if isinstance(d, dict) and d.get('ok') is False:
        return SKIP, 'the bench refused %s: %s' % (item.get('name'), str(d.get('text'))[:60])
    if not isinstance(b, dict):
        return SKIP, 'no bench state after the salvage'
    n0, n1 = len(a.get('items') or []), len(b.get('items') or [])
    s0, s1 = int((a.get('salvage') or {}).get('shards') or 0), int((b.get('salvage') or {}).get('shards') or 0)
    if n1 != n0 - 1:
        return FAIL, 'salvaged %s and the bench lists %d items, it listed %d before: expected one less' % (item.get('name'), n1, n0)
    if s1 < s0:
        return FAIL, 'salvaged %s and the Rune Shards fell from %d to %d' % (item.get('name'), s0, s1)
    return PASS, 'salvaged %s (rarity %s): the list shrank by one, shards %d -> %d' % (item.get('name'), item.get('rarityName') or item.get('rarity'), s0, s1)


async def check_chore_salvage(io, name, cls, level):
    """what a person does with a rolled piece it will not wear: break it down at the bench (Salvage) for Rune Shards; the item is the bot's own drop"""
    key = 'chore_salvage'
    rep, why = await found_look(io)
    if rep is None:
        return Result(key, name, cls, SKIP, why)
    await io.open_bag(rep.get('bagClientId'))
    reply = await io.request('crafting', 'open', {}, ('state',), ANSWER)
    a = (reply or {}).get('data') if isinstance(reply, dict) else None
    if not isinstance(a, dict) or not (a.get('salvage') or {}).get('installed', True):
        return Result(key, name, cls, SKIP, 'no bench state with a Salvage mode')
    item = salvage_pick(rep, a.get('items'))
    if item is None:
        return Result(key, name, cls, SKIP, 'no rolled piece in the backpack that the bot would not wear (%d piece(s) looked at)' % len(rep.get('pieces') or []))
    sel = await io.request('crafting', 'select', {'path': str(item['path']), 'id': item['id']}, ('state',), ANSWER)
    sig = (((sel or {}).get('data') or {}).get('item') or {}).get('sig')
    res = await io.request('crafting', 'salvage', {'path': str(item['path']), 'id': item['id'], 'sig': sig}, ('result',), ANSWER)
    await io.sleep(1.0)
    again = await io.request('crafting', 'open', {}, ('state',), ANSWER)
    status, text = salvage_verdict(item, a, (again or {}).get('data') if isinstance(again, dict) else None, res)
    return Result(key, name, cls, status, text)
# ---- PvP among the testers (O652)
# The bots fight each other, only inside a PvP place the rules allow (an arena match, a battleground match, the Marches), only another tester: the
# helper's loop aims at a foe the server names (`!tester pvp`, ChaosTesters.pvpFoe) and the server cancels every other hit (testers.lua). The
# checks play it like people: queue, wait for the match, walk to the foe by the engine path, fight with the bot's own rotation, and read what
# the server holds afterwards: no player in the roster, no tester row in the season ratings.
PVP_BUDGET = {'arena': 150.0, 'zone': 100.0, 'bg': 200.0}   # seconds each fight is played at most
PVP_FIGHT_MIN = 45.0     # seconds within reach of a foe with no foe hurt and the match going on: the hits do not land (damage, targets or the guard)
PVP_STEPS = 6
PVP_STUCK = 30.0
PVP_MISSES = 6
PVP_SECTION = {'arena': 'arena', 'bg': 'battleground', 'zone': 'zone'}
BG_QUEUE_WAIT = 150.0    # seconds a bot waits in the battleground queue for a match of testers (10 at least, level 100 and up)
BG_START_WAIT = 90.0     # seconds from the match to the open fight (the 30 s of preparation, the gates)


def pvp_bot(name, lead):
    return {'name': name, 'lead': lead, 'walker': RaidWalker(), 'inside': False}


def pvp_sec(s, kind):
    sec = s.get(PVP_SECTION[kind]) if isinstance(s, dict) else None
    return sec if isinstance(sec, dict) else {}


def pvp_inside(s, kind):
    sec = pvp_sec(s, kind)
    return bool(sec.get('inside') if kind == 'zone' else sec.get('inMatch'))


def pvp_problems(s, kind):
    """[text] for one `!tester pvp` answer: whatever says the fight is not the testers' own, or a tester entered a ranking"""
    out = []
    sec = pvp_sec(s, kind)
    if pvp_inside(s, kind) and int(sec.get('others') or 0) > 0:
        out.append('%s player(s) are in the testers\' %s (it must hold testers only)' % (sec.get('others'), PVP_SECTION[kind]))
    if int(s.get('seasonListed') or 0) > 0:
        out.append('%s tester row(s) in the season ratings (a tester result never enters a season board)' % s.get('seasonListed'))
    if s.get('place') and pvp_inside(s, kind) and s.get('closed') is False:
        out.append('the bots fight inside a PvP place with the closed switch off')
    return out


def pvp_hurt(s, kind):
    """the lowest health percent among the foes the bot sees (None when it sees none)"""
    sec = pvp_sec(s, kind)
    hps = [f.get('hp') for f in (sec.get('foes') or []) if isinstance(f, dict) and isinstance(f.get('hp'), (int, float))]
    foe = s.get('foe')
    if isinstance(foe, dict) and isinstance(foe.get('hp'), (int, float)):
        hps.append(foe['hp'])
    return min(hps) if hps else None


async def pvp_play(io, squad, kind, trace, budget, stop=None):
    """the bots walk to their foes by the engine path and fight with their own rotation (the helper aims at the foe the rules allow); one
    look per bot, then up to PVP_STEPS steps each. Ends at the budget, a fault, a block, when the server put the bots out (the match is over),
    or when `stop(trace)` says so"""
    elapsed, misses, fight_since = 0.0, 0, None
    while io.alive() and elapsed < budget:
        looks = {}
        for r in squad:
            looks[r['name']] = await hcmd(io, r, 'pvp state', 'pvp')
        lead = looks.get(squad[0]['name'])
        if not isinstance(lead, dict) or lead.get('err'):
            misses += 1
            if misses >= PVP_MISSES:
                break
            await io.sleep(RAID_LOOK)
            elapsed += RAID_LOOK
            continue
        misses = 0
        got = [s for s in looks.values() if isinstance(s, dict) and not s.get('err')]
        for s in got:
            for p in pvp_problems(s, kind):
                if p not in trace['faults']:
                    trace['faults'].append(p)
        if trace['faults']:
            break
        inside = [pvp_inside(s, kind) for s in got]
        if trace.get('was_in') and not any(inside):
            trace['ended'] = True   # the match is over: the server put the bots back where they stood
            break
        trace['was_in'] = trace.get('was_in') or any(inside)
        trace['both'] = trace.get('both') or (len(squad) > 1 and all(inside))
        phase = pvp_sec(lead, kind).get('phase')
        trace['phase'] = phase or trace.get('phase')
        trace['cancelled_player'] = max(trace.get('cancelled_player', 0), int(lead.get('cancelledPlayer') or 0))
        for s in got:
            hp = pvp_hurt(s, kind)
            if hp is not None:
                trace['foe_hp'] = hp if trace.get('foe_hp') is None else min(trace['foe_hp'], hp)
        g = lead.get('guide') or {}
        if g.get('mode') == 'fight' and phase in (None, 'fight'):
            fight_since = elapsed if fight_since is None else fight_since
            trace['fought'] = max(trace['fought'], elapsed - fight_since)
        else:
            fight_since = None
        if stop and stop(trace):
            break
        sent = {}
        for r in squad:
            s = looks.get(r['name'])
            if not isinstance(s, dict) or s.get('err') or not pvp_inside(s, kind):
                continue
            gr = s.get('guide') or {}
            pos = s.get('pos')
            if gr.get('mode') == 'walk' and isinstance(gr.get('goal'), dict) and isinstance(pos, dict):
                plan = r['walker'].steps(pos, gr['goal'], PVP_STEPS, elapsed)
                if not r['walker'].blocked:   # the engine's path first (walls, pillars); the side step only when the way is blocked
                    pg = await hcmd(io, r, 'pvp path', 'pvp')
                    steps = raid_path_steps((pg or {}).get('path')) if isinstance(pg, dict) and not pg.get('err') else []
                    plan = steps[:PVP_STEPS] or plan
                sent[r['name']] = plan
                if r['lead'] and r['walker'].stuck(elapsed) >= PVP_STUCK:
                    trace['stuck'] = (pos['x'], pos['y'])
        if trace.get('stuck'):
            break
        for i in range(PVP_STEPS):
            moved = False
            for r in squad:
                plan = sent.get(r['name']) or []
                if i < len(plan):
                    await raid_walk(io, r, plan[i])
                    trace['steps'] += 1
                    moved = True
            if not moved:
                break
            await io.sleep(RAID_STEP)
            elapsed += RAID_STEP
        await io.sleep(RAID_LOOK)
        elapsed += RAID_LOOK
        trace['secs'] = int(elapsed)
    trace['secs'] = int(elapsed)
    trace['died'] = trace.get('died') or not io.alive()


def pvp_fight_verdict(t, what):
    """(status, text) from the trace: faults, was_in, both, ended, foe_hp, fought, stuck, died, steps, secs, phase, cancelled_player, level"""
    if t.get('faults'):
        return FAIL, '; '.join(t['faults'][:3])
    how = 'level %s, %d step(s) in %d s' % (t.get('level'), t.get('steps', 0), t.get('secs', 0))
    if t.get('cancelled_player'):
        how += '; %d hit(s) on a player were cancelled' % t['cancelled_player']
    hurt = t.get('foe_hp') is not None and t['foe_hp'] < 100
    if t.get('ended') and (hurt or t.get('fought', 0) > 0):
        return PASS, 'the %s was played to its end between testers only (a foe hurt to %s%%), no tester row in the season ratings (%s)' % (
            what, t.get('foe_hp', '?'), how)
    if hurt:
        return PASS, 'a foe tester hurt to %s%% in the %s, the roster held testers only (%s)' % (t['foe_hp'], what, how)
    if t.get('fought', 0) >= PVP_FIGHT_MIN:
        return FAIL, 'fought %d s within reach of a foe tester in the %s and hurt none (damage, targets or the helper\'s aim)' % (t['fought'], what)
    if not t.get('was_in'):
        return SKIP, 'the bot never stood inside the %s' % what
    if t.get('stuck'):
        return SKIP, 'the walk was blocked at (%d, %d) for %d s (%s)' % (t['stuck'][0], t['stuck'][1], PVP_STUCK, how)
    if t.get('died'):
        return SKIP, 'the bot died before it met a foe (%s)' % how
    return SKIP, 'no foe was hurt in %d s (%s)' % (t.get('secs', 0), how)


async def pvp_wait_inside(io, squad, kind, wait):
    """True when every bot of the squad reads inside within `wait` seconds"""
    waited = 0.0
    while waited <= wait and io.alive():
        looks = [await hcmd(io, r, 'pvp state', 'pvp') for r in squad]
        if all(isinstance(s, dict) and pvp_inside(s, kind) for s in looks):
            return True
        await io.sleep(LOOK)
        waited += LOOK
    return False


async def check_closed_arena_fight(io, name, cls, level):
    """two testers queue a 1v1, meet in the arena and fight: the fight is theirs only, nothing of it enters a ranking or a season board"""
    key = 'closed_arena_fight'
    other = await io.partner()
    if not other:
        return Result(key, name, cls, SKIP, 'no free bot in game')
    if not await io.go('town') or not await io.go_of(other, 'town'):
        return Result(key, name, cls, SKIP, 'the helper did not bring both bots to the temple')
    await io.sleep(SETTLE)
    a = await io.request('arena', 'queue', {'mode': '1v1'}, ['state'], ANSWER)
    b = await io.request_of(other, 'arena', 'queue', {'mode': '1v1'}, ['state'], ANSWER)
    if a is None or b is None:
        return Result(key, name, cls, SKIP, 'no answer from the arena window (not installed)')
    squad = [pvp_bot(name, True), pvp_bot(other, False)]
    trace = new_trace({'level': level}, [], was_in=False, both=False, ended=False, foe_hp=None)
    io.raid_mode([name, other], True)
    try:
        if not await pvp_wait_inside(io, squad, 'arena', ARENA_WAIT):
            qa = ((a or {}).get('data') or {}).get('queue') if isinstance(a, dict) else None   # O656: what the window said: in the queue or not
            qb = ((b or {}).get('data') or {}).get('queue') if isinstance(b, dict) else None
            return Result(key, name, cls, SKIP, 'the two queued bots were not in a match in %d seconds (the closed_arena check holds that; queue state: %s / %s)' % (
                int(ARENA_WAIT), 'queued' if qa else 'not queued', 'queued' if qb else 'not queued'))
        await pvp_play(io, squad, 'arena', trace, PVP_BUDGET['arena'], stop=lambda t: t.get('foe_hp') is not None and t['foe_hp'] < 100 and t['fought'] >= PVP_FIGHT_MIN)
        status, text = pvp_fight_verdict(trace, 'arena match')
        return Result(key, name, cls, status, text)
    finally:
        await io.request('arena', 'leave', {}, ['state'], ANSWER)
        await io.request_of(other, 'arena', 'leave', {}, ['state'], ANSWER)
        io.raid_mode([name, other], False)


async def check_closed_pvp_fight(io, name, cls, level):
    """two testers enter the Marches (their own instance) and fight: the kills and defeats are theirs, never a player's"""
    key = 'closed_pvp_fight'
    other = await io.partner()
    if not other:
        return Result(key, name, cls, SKIP, 'no free bot in game')
    if not await io.go('town') or not await io.go_of(other, 'town'):
        return Result(key, name, cls, SKIP, 'the helper did not bring both bots to the temple')
    await io.sleep(SETTLE)
    a = await io.request('pvpZone', 'enter', {'accept': True}, ['*'], ANSWER)
    b = await io.request_of(other, 'pvpZone', 'enter', {'accept': True}, ['*'], ANSWER)
    if a is None or b is None:
        return Result(key, name, cls, SKIP, 'no answer from the Marches window (not installed)')
    squad = [pvp_bot(name, True), pvp_bot(other, False)]
    trace = new_trace({'level': level}, [], was_in=False, both=False, ended=False, foe_hp=None)
    io.raid_mode([name, other], True)
    try:
        if not await pvp_wait_inside(io, squad, 'zone', SETTLE * 3):
            text = str(((a or {}).get('data') or {}).get('text', '') or ((b or {}).get('data') or {}).get('text', ''))[:80]
            return Result(key, name, cls, SKIP, 'both bots were not inside the Marches: %s' % (text or 'no text'))
        await pvp_play(io, squad, 'zone', trace, PVP_BUDGET['zone'], stop=lambda t: t.get('foe_hp') is not None and t['foe_hp'] < 100)
        status, text = pvp_fight_verdict(trace, 'Marches')
        return Result(key, name, cls, status, text)
    finally:
        await io.go('town')   # out the way the helper allows (the carried embers are the tester's own)
        await io.go_of(other, 'town')
        io.raid_mode([name, other], False)


async def check_closed_battleground_match(io, name, cls, level):
    """the bot queues for the battleground and stays: with enough testers queued (10, a roster of 5v5) a match of testers only starts, and it
    plays it (the braziers and the foes); players are never matched with testers (the testers' own realm)"""
    key = 'closed_battleground_match'
    await io.go('town')
    await io.sleep(SETTLE)
    q = await io.request('battleground', 'queue', {}, ['state'], ANSWER)
    if q is None:
        return Result(key, name, cls, SKIP, 'no answer from the battleground window (not installed)')
    r = pvp_bot(name, True)
    trace = new_trace({'level': level}, [], was_in=False, both=False, ended=False, foe_hp=None)
    last = {}
    io.raid_mode([name], True)
    try:
        waited = 0.0
        inside = False
        while waited <= BG_QUEUE_WAIT and io.alive():
            s = await io.helper('pvp state', 'pvp', ANSWER)
            if isinstance(s, dict) and not s.get('err'):
                last = pvp_sec(s, 'bg')
                if pvp_inside(s, 'bg'):
                    inside = True
                    break
                if waited >= 6 and not last.get('queued'):
                    return Result(key, name, cls, SKIP, 'the queue refused the bot (level, zone, deserter)')
            await io.sleep(LOOK * 2)
            waited += LOOK * 2
        if not inside:
            return Result(key, name, cls, SKIP, 'no match in %d s: %s of the %s testers a match needs were queued' % (
                int(BG_QUEUE_WAIT), last.get('queueMembers', '?'), last.get('need', '?')))
        await pvp_play(io, [r], 'bg', trace, BG_START_WAIT + PVP_BUDGET['bg'], stop=lambda t: t.get('foe_hp') is not None and t['foe_hp'] < 100)
        status, text = pvp_fight_verdict(trace, 'battleground match')
        return Result(key, name, cls, status, text)
    finally:
        await io.request('battleground', 'leave', {}, ['state'], ANSWER)
        io.raid_mode([name], False)


# ---- the tester copy of a key boss (O652)
# A world boss, a lair boss and an island boss are the players' content: the bots do not take their shares, loot, kill rows or boards. They play the
# fight on a copy made for one bot (`!tester boss spawn`, TEST ONLY, only while no player is near): its telegraphs, its adds, its enrage are the boss's
# own. The bot walks to it, fights with its own rotation, and when a mark is on its tile it steps to the safe tile the server names (guide `dodge`).
BOSS_BUDGET = 330.0      # seconds the copy is played at most (its own life is 480 s)
BOSS_STEPS = 6
BOSS_DODGE_STEPS = 3     # steps of one dodge (a mark gives 1.5 - 3 s: a person steps, looks, steps)
BOSS_DODGE_LOOK = 0.4


def boss_copy_look(s, t):
    t['killed'] = max(t.get('killed', 0), (s.get('killed') or 0) - t.get('killed0', 0))
    t['points'] = s.get('points') if s.get('points') is not None else t.get('points')
    if s.get('listed'):
        t['faults'].append('%s tester name(s) in a boss board (a copy writes no kill row, no share)' % s['listed'])
    b = s.get('boss')
    if isinstance(b, dict):
        t['seen'] = True
        t['name'] = b.get('name') or t.get('name')
        if isinstance(b.get('hp'), int):
            t['hp'] = b['hp'] if t.get('hp') is None else min(t['hp'], b['hp'])
    d = s.get('danger')
    if isinstance(d, dict):
        labels = tuple(d.get('labels') or ())
        if labels and labels != t.get('last_marks'):
            t['marks'] = t.get('marks', 0) + 1   # a new mark pulse: a person sees the warning
        t['last_marks'] = labels
        if d.get('here'):
            t['stood'] = t.get('stood', 0) + 1
    else:
        t['last_marks'] = None
    if t['killed'] > 0:
        return True
    if t.get('seen') and not isinstance(b, dict) and s.get('killed') is not None:
        t['gone'] = True   # its life ran out
        return True
    return False


async def boss_copy_play(io, r, trace, budget):
    """like chase_play, plus the dodge: when the guide says `dodge` the bot steps to the safe tile at once and looks again quickly"""
    elapsed, misses, fight_since = 0.0, 0, None
    while io.alive() and elapsed < budget:
        s = await io.helper('boss state', 'boss', ANSWER)
        if not isinstance(s, dict) or s.get('err'):
            misses += 1
            if misses >= SOLO_MISSES:
                break
            await io.sleep(RAID_LOOK)
            elapsed += RAID_LOOK
            continue
        misses = 0
        if boss_copy_look(s, trace):
            break
        g = s.get('guide') or {}
        spent = await retreat_check(io, r, s, trace, g)   # O658: under 30 % health the bot heals and steps back before it goes on
        if spent:
            elapsed += spent
            continue
        mode = g.get('mode')
        if mode == 'fight':
            fight_since = elapsed if fight_since is None else fight_since
            trace['fought'] = max(trace['fought'], elapsed - fight_since)
        else:
            fight_since = None
        if mode == 'dodge' and isinstance(g.get('goal'), dict) and isinstance(s.get('pos'), dict):
            trace['dodged'] = trace.get('dodged', 0) + 1
            for step in raid_plan(s['pos'], g['goal'], BOSS_DODGE_STEPS):
                await raid_walk(io, r, step)
                trace['steps'] += 1
                await io.sleep(RAID_STEP)
                elapsed += RAID_STEP
            await io.sleep(BOSS_DODGE_LOOK)
            elapsed += BOSS_DODGE_LOOK
            trace['secs'] = int(elapsed)
            continue
        plan = []
        if mode == 'walk' and isinstance(g.get('goal'), dict) and isinstance(s.get('pos'), dict):
            plan = r['walker'].steps(s['pos'], g['goal'], BOSS_STEPS, elapsed)
            if not r['walker'].blocked:
                got = await hcmd(io, r, 'boss path', 'boss')
                steps = raid_path_steps((got or {}).get('path')) if isinstance(got, dict) and not got.get('err') else []
                plan = steps[:BOSS_STEPS] or plan
            if r['walker'].stuck(elapsed) >= SOLO_STUCK:
                trace['stuck'] = (s['pos']['x'], s['pos']['y'])
                break
        for step in plan:
            await raid_walk(io, r, step)
            trace['steps'] += 1
            await io.sleep(RAID_STEP)
            elapsed += RAID_STEP
        await io.loot()
        await io.sleep(RAID_LOOK)
        elapsed += RAID_LOOK
        trace['secs'] = int(elapsed)
    trace['secs'] = int(elapsed)
    trace['died'] = trace.get('died') or not io.alive()


def boss_copy_verdict(t):
    """(status, text): faults, killed, hp (the copy's lowest health percent), seen, gone, marks (warnings seen), dodged, stood, points, fought, stuck, died, steps, secs, level, name"""
    if t.get('faults'):
        return FAIL, '; '.join(t['faults'][:3])
    how = chase_text(t)
    mech = '%d warning(s) seen, %d dodge(s)' % (t.get('marks', 0), t.get('dodged', 0))
    pts = ''
    if t.get('points0') is not None and t.get('points') is not None and t['points'] != t['points0']:
        pts = ', boss passive points %s -> %s' % (t['points0'], t['points'])
    if t.get('killed'):
        return PASS, 'killed the copy of %s, its loot and kill are the bot\'s own%s (%s; %s)' % (t.get('name') or 'a boss', pts, mech, how)
    if t.get('hp') is not None and t['hp'] < 100:
        return PASS, 'hurt the copy of %s to %s%% (%s; %s)' % (t.get('name') or 'a boss', t['hp'], mech, how)
    if t.get('fought', 0) >= SOLO_FIGHT_MIN:
        return FAIL, 'fought %d s in reach of the boss copy and did not hurt it (damage, targets or the guard)' % t['fought']
    if t.get('stuck'):
        return SKIP, 'the walk was blocked at (%d, %d) for %d s (%s)' % (t['stuck'][0], t['stuck'][1], SOLO_STUCK, how)
    if t.get('died'):
        return SKIP, 'the bot died before it hurt the copy (%s; %s)' % (mech, how)
    return SKIP, 'the copy was not hurt in %d s (%s)' % (t.get('secs', 0), how)


async def check_boss_copy_walk(io, name, cls, level):
    """a copy of a key boss for the bot (TEST ONLY, only while no player is near): it walks to it, fights with its own rotation, steps off the
    telegraph marks the server sends, loots; the copy is the testers' own, so no share, board or kill row names a tester"""
    key = 'boss_copy_walk'
    a = await io.helper('boss state', 'boss', ANSWER)
    if not isinstance(a, dict):
        return Result(key, name, cls, SKIP, 'no answer to !tester boss (old helper file)')
    if a.get('err'):
        return Result(key, name, cls, SKIP, str(a['err'])[:80])
    if not a.get('next'):
        return Result(key, name, cls, SKIP, 'level %s is under the lowest boss copy' % a.get('level'))
    r = {'name': name, 'lead': True, 'walker': RaidWalker(), 'inside': False}
    fallbacks = []
    trace = new_trace(a, fallbacks, killed0=a.get('killed') or 0, killed=0, hp=None, seen=False, marks=0, dodged=0, stood=0, points0=a.get('points'),
                      points=a.get('points'))
    io.raid_mode([name], True, keep_flee=True)
    try:
        if a.get('boss'):
            await io.helper('boss close', 'boss', ANSWER)
        made = await io.helper('boss spawn', 'boss', HELPER_WAIT)
        if isinstance(made, dict) and 'protection zone' in str(made.get('err') or ''):
            await io.go('hunt')   # a copy is not made in a protection zone: out to the hunt, like a person
            await io.sleep(SETTLE)
            made = await io.helper('boss spawn', 'boss', HELPER_WAIT)
        if not isinstance(made, dict) or made.get('err') or not made.get('spawned'):
            return Result(key, name, cls, SKIP, 'no copy of its own: %s' % str((made or {}).get('err') or 'no answer')[:70])
        await io.sleep(SETTLE)
        await boss_copy_play(io, r, trace, BOSS_BUDGET)
        status, text = boss_copy_verdict(trace)
        return Result(key, name, cls, status, text, fallbacks)
    finally:
        await io.helper('boss close', 'boss', ANSWER)
        io.raid_mode([name], False)
        await io.go('hunt')


# ------------------------------------------------------------------------------------------------ pocket bosses and boss passive points (O651)
# The Boss Spawns window's Pocket button, as a person uses it: the bot walks to the temple (a pocket opens in a protection zone), opens the window,
# asks for the pocket of a boss that gives a boss passive point it does not hold (else the lowest one its level opens), plays the private arena
# like a person (to the boss by the engine's path, its own rotation, the loot of the corpse) and checks the daily charge was spent and the boss
# point came. The arenas are one grid the players share: a tester takes one only while `reserve` stay free (the server's rule, read from
# `!tester pocket`), the run is never mixed with a player, and nothing of it is public (server/README.md "The rest of the closed audit (O589)", step 10).
POCKET_BUDGET = 720.0     # seconds a pocket is played at most (the pocket's own limit is 10 to 15 minutes after the boss comes)


def pocket_refusal(a, level=0):
    """(status, text) when this bot must not play the check, else None: from its `!tester pocket` answer"""
    if not isinstance(a, dict):
        return SKIP, 'no answer to !tester pocket (old helper file)'
    if a.get('err'):
        return SKIP, str(a['err'])[:80]
    if a.get('enabled') is False:
        return SKIP, 'the pocket bosses are closed'
    if a.get('inside'):
        return SKIP, 'the bot is inside a pocket already'
    if a.get('free') is not None and a.get('reserve') is not None and int(a['free']) - 1 < int(a['reserve']):
        return SKIP, 'the pocket arenas are kept for the players (%s free, %s reserved)' % (a['free'], a['reserve'])
    if not a.get('bosses'):
        return SKIP, 'level %s opens no pocket with a charge left today' % (a.get('level') or level)
    return None


def pocket_pick(a):
    """the pocket this bot opens: the first row of the answer (a boss with a passive point the bot lacks first, then by level)"""
    rows = [b for b in a.get('bosses') or [] if isinstance(b, dict) and isinstance(b.get('key'), str)]
    return rows[0] if rows else None


def pocket_problems(s, trace):
    """[text] for one inside-a-pocket answer: a player in the testers' pocket. Keeps the boss, its lowest health and the kill in the trace"""
    out = []
    run = s.get('run') or {}
    if run.get('players') is not None and run.get('testers') is not None and run['players'] != run['testers']:
        out.append('a player is in the pocket of the testers (%s of %s are testers)' % (run['testers'], run['players']))
    if run.get('boss') == 'alive' or isinstance(run.get('bossHp'), int):
        trace['boss_seen'] = True
        if isinstance(run.get('bossHp'), int):
            trace['hp'] = run['bossHp'] if trace.get('hp') is None else min(trace['hp'], run['bossHp'])
            series = trace.setdefault('series', [])   # O661: the boss's health at each look, to tell a fight that was lost from a boss that heals
            if len(series) < 60:
                series.append(run['bossHp'])
                trace.setdefault('series_t', []).append(time.monotonic())   # O662: and when, for the bot's damage a second
            if isinstance(run.get('bossMax'), int):
                trace['boss_max'] = run['bossMax']
            if isinstance(run.get('bossNow'), int) and len(trace.setdefault('series_abs', [])) < 60:
                trace['series_abs'].append(run['bossNow'])   # the exact health: a percent is 1 % of 16 million
    if run.get('boss') == 'dead' or run.get('state') == 'success':
        trace['won'] = True
        trace['hp'] = 0
    return out


def pocket_walk_verdict(t):
    """(status, text) from the trace of a played pocket: faults, boss, won, hp (the boss's lowest health percent), boss_seen, point (the boss point before:
    {id, got} or None), point_gain (the points held after minus before), fought, stuck, died, came, steps, secs, level, fallbacks"""
    if t.get('faults'):
        return FAIL, '; '.join(t['faults'][:3])
    how = solo_text(t, 'pocket')
    if t.get('won'):
        pt = t.get('point')
        extra = ''
        if pt and not pt.get('got'):
            extra = ', the boss point came (+%s)' % t.get('point_gain')
        elif pt:
            extra = ', the boss point was held already'
        return PASS, '%s fell in %d s%s (%s)%s' % (t.get('boss') or 'the boss', t.get('secs', 0), extra, how, pocket_dps_text(t))
    if t.get('boss_seen') and t.get('hp') is not None and t['hp'] < 100:
        return SKIP, '%s was hurt to %s%% and did not fall in %d s (%s)%s' % (t.get('boss') or 'the boss', t['hp'], t.get('secs', 0), how,
                                                                             (' [boss health per look: %s]' % ','.join(str(v) for v in t['series'][:30])) if t.get('series') else '') + pocket_dps_text(t)
    if t.get('fought', 0) >= SOLO_FIGHT_MIN:
        return FAIL, 'fought %d s at the boss of the pocket and took none of its health (damage, targets or the boss)' % t['fought']
    if t.get('stuck'):
        return SKIP, 'the walk was blocked at (%d, %d) for %d s (%s)' % (t['stuck'][0], t['stuck'][1], SOLO_STUCK, how)
    if t.get('died'):
        return SKIP, 'the bot was carried out before the boss was hurt (level %s against %s)' % (t.get('level', '?'), t.get('boss') or 'the boss')
    if not t.get('boss_seen'):
        return SKIP, 'the boss did not come in %d s (%s)' % (t.get('secs', 0), how)
    return SKIP, 'the boss was not hurt in %d s (%s)' % (t.get('secs', 0), how)


def pocket_error_text(reply):
    d = (reply or {}).get('data') if isinstance(reply, dict) and reply.get('action') == 'pocketError' else None
    return str((d or {}).get('text') or '')[:90] if d is not None else None


async def check_pocket_walk(io, name, cls, level):
    """walks to the temple, opens the Boss Spawns window, asks for a pocket, plays the private arena to the boss's death, checks the charge and the point"""
    key = 'pocket_walk'
    a = await io.helper('pocket state', 'pocket', ANSWER)
    refused = pocket_refusal(a, level)
    if refused:
        return Result(key, name, cls, refused[0], refused[1])
    pick = pocket_pick(a)
    unfit = pocket_unfit(pick, a.get('level') or level)   # O661: a boss above the bot's level is not played
    if unfit:
        return Result(key, name, cls, SKIP, unfit)
    r = {'name': name, 'lead': True, 'walker': RaidWalker(), 'inside': False}
    fallbacks = []
    trace = {'faults': [], 'steps': 0, 'fought': 0.0, 'stuck': None, 'died': False, 'secs': 0, 'came': 'foot', 'fallbacks': fallbacks, 'level': a.get('level'),
             'boss_seen': False, 'hp': None, 'won': False, 'boss': pick.get('name'), 'point': pick.get('point')}
    points0 = (a.get('points') or {}).get('got')
    io.raid_mode([name], True, keep_flee=True)
    try:
        why = await solo_to_temple(io, r, trace, fallbacks, need_pz=True, system='pocket')
        if why:
            return Result(key, name, cls, SKIP, why.replace('the descent', 'a pocket'), fallbacks)
        await io.request('bossSpawns', 'open', {}, ['list', 'pocket'], ANSWER)   # the window, as a person opens it
        s, waited, refusal = None, 0.0, None
        while waited <= SOLO_ENTER_WAIT and io.alive():
            if waited in (0.0, 7.0):
                reply = await io.request('bossSpawns', 'pocketEnter', {'k': pick['key']}, ['pocketError', 'pocket'], ANSWER)
                refusal = pocket_error_text(reply) or refusal
                if refusal and waited == 0.0 and refusal:
                    break
            await io.sleep(1.0)
            waited += 1.0
            s = await io.helper('pocket state', 'pocket', ANSWER)
            if isinstance(s, dict) and s.get('inside'):
                break
        if not (isinstance(s, dict) and s.get('inside')):
            if refusal and ('never mixed' in refusal or 'Closed test mode' in refusal):
                return Result(key, name, cls, FAIL, 'the pocket refused a lone tester: %s' % refusal, fallbacks)
            return Result(key, name, cls, SKIP, 'the pocket of %s did not open in %d s: %s' % (pick.get('name'), int(SOLO_ENTER_WAIT), refusal or 'no text'), fallbacks)
        await solo_play(io, r, trace, {
            'system': 'pocket', 'budget': POCKET_BUDGET, 'problems': pocket_problems, 'done': lambda t: t.get('won'),
            'made': lambda t: bool(t.get('boss_seen')),
            'mark': lambda s: ((s.get('run') or {}).get('bossHp'), (s.get('run') or {}).get('state'), (s.get('run') or {}).get('boss'))})
        if trace['won']:
            await io.loot()   # the corpse of the boss: the loot is taken as anywhere
            await io.sleep(2.0)
        await io.helper('pocket close', 'pocket', ANSWER)
        after = await io.helper('pocket state', 'pocket', ANSWER)
        if isinstance(after, dict) and after.get('inside'):
            trace['faults'].append('the bot is still inside the pocket after the close')
        if isinstance(after, dict) and not trace['faults']:
            row = next((b for b in after.get('bosses') or [] if isinstance(b, dict) and b.get('key') == pick['key']), None)
            if row is not None and pick.get('left') is not None and row.get('left') is not None and int(row['left']) >= int(pick['left']):
                trace['faults'].append('the pocket of %s was opened and the charges left went %s to %s (a charge is spent when it opens)' % (
                    pick.get('name'), pick['left'], row['left']))
            gained = None
            if points0 is not None and isinstance(after.get('points'), dict) and after['points'].get('got') is not None:
                gained = int(after['points']['got']) - int(points0)
            trace['point_gain'] = gained
            if trace['won'] and pick.get('point') and not pick['point'].get('got') and gained is not None and gained < 1:
                trace['faults'].append('%s fell in a pocket and the first kill gave no boss passive point (%s of %s held)' % (
                    pick.get('name'), after['points'].get('got'), after['points'].get('total')))
        status, text = pocket_walk_verdict(trace)
        return Result(key, name, cls, status, text, fallbacks)
    finally:
        await io.helper('pocket close', 'pocket', ANSWER)
        io.raid_mode([name], False)
        await io.go('hunt')


# ------------------------------------------------------------------------------------------------ a waystone map walked (O651)
# After the take, the use and the run (`waystone_run`, on the game's own code) one map is walked: the bot walks to the temple, the helper's TEST ONLY
# `wsmap enter` stands for the device's pads and teleport (base code, not in the repository) and puts it on the arrival tile of a free map with a plain
# run of the first tier, and the bot clears monsters like a person (the engine's path, its own rotation, the loot). The maps are the shared base map: the
# server lets a tester in only while nobody is in the rectangle and sends it out the moment a player steps in (players first); the check proves the run's
# tier is on the monsters (their level against the tier) and that no player is in the testers' run. The boss lever, the boss and the exit teleport are
# base code and are left (server/README.md step 10).
WSMAP_BUDGET = 420.0      # seconds a map is walked at most
WSMAP_NEED = 3            # monsters of the map that fall (the count of monsters on the map falls by this much)
WSMAP_LEVEL_SLACK = 100   # levels a bot may be under the monsters of the map's tier


def wsmap_refusal(a, level=0):
    """(status, text) when this bot must not play the check, else None: from its `!tester wsmap` answer"""
    if not isinstance(a, dict):
        return SKIP, 'no answer to !tester wsmap (old helper file)'
    if a.get('err'):
        return SKIP, str(a['err'])[:80]
    if a.get('enabled') is False:
        return SKIP, 'the waystone tiers are off'
    have = int(a.get('level') or level or 0)
    if a.get('minLevel') is not None and have < int(a['minLevel']):
        return SKIP, 'level %d: the waystone maps need level %s' % (have, a['minLevel'])
    if a.get('inside'):
        return SKIP, 'the bot is inside a waystone map already'
    if not a.get('arrivals'):
        return SKIP, 'no arrival tile of a waystone map is known (waystone_tiers_config.lua arrivals: audit_waystone_maps.py BASE --arrivals prints them)'
    if a.get('free') is False:
        return SKIP, 'no waystone map is free for the testers: %s' % (a.get('why') or 'in use')
    if a.get('freeTierLevel') is not None and have + WSMAP_LEVEL_SLACK < int(a['freeTierLevel']):
        return SKIP, 'level %d: the free waystone map is tier %s (level %s)' % (have, a.get('freeTier'), a['freeTierLevel'])
    return None


def wsmap_problems(s, trace):
    """[text] for one inside-a-map answer: a player in the testers' map, a monster of the map not at the level of the run's tier. Keeps the fall of the
    monster count (the kills) in the trace"""
    out = []
    run = s.get('run') or {}
    if int(run.get('players') or 0) > 0:
        out.append('%s player(s) are in the waystone map of the testers' % run['players'])
    if run.get('monsterLevel') is not None and run.get('tierLevel') is not None and int(run['monsterLevel']) != int(run['tierLevel']):
        out.append('a monster of the map is level %s, the run is tier %s (level %s)' % (run['monsterLevel'], run.get('tier'), run['tierLevel']))
    if isinstance(run.get('monsters'), int):
        trace['mon0'] = run['monsters'] if trace.get('mon0') is None else trace['mon0']
        trace['kills'] = max(trace.get('kills', 0), trace['mon0'] - run['monsters'])
        trace['tier'], trace['tier_level'] = run.get('tier'), run.get('tierLevel')
        trace['map'] = run.get('map')
    return out


def wsmap_walk_verdict(t):
    """(status, text) from the trace of a walked map: faults, kills, tier, tier_level, map, fought, stuck, died, came, steps, secs, level, fallbacks"""
    if t.get('faults'):
        return FAIL, '; '.join(t['faults'][:3])
    how = solo_text(t, 'map')
    if t.get('kills', 0) >= WSMAP_NEED:
        return PASS, '%d monster(s) of map %s fell at tier %s (level %s) (%s)' % (t['kills'], t.get('map'), t.get('tier'), t.get('tier_level'), how)
    if t.get('fought', 0) >= SOLO_FIGHT_MIN:
        return FAIL, 'fought %d s in the waystone map and killed none (damage, targets or the monsters)' % t['fought']
    if t.get('stuck'):
        return SKIP, 'the walk was blocked at (%d, %d) for %d s (%s)' % (t['stuck'][0], t['stuck'][1], SOLO_STUCK, how)
    if t.get('died'):
        return SKIP, 'the bot was out of the map before it killed a monster: a fall (level %s against tier %s), or the server\'s guard sent it out (a player came)' % (
            t.get('level', '?'), t.get('tier', '?'))
    return SKIP, 'only %d of %d monster(s) fell in %d s (%s)' % (t.get('kills', 0), WSMAP_NEED, t.get('secs', 0), how)


async def check_wsmap_walk(io, name, cls, level):
    """walks to the temple, enters a free waystone map (the TEST ONLY stand-in of the pads), clears monsters by the engine's path, leaves"""
    key = 'wsmap_walk'
    a = await io.helper('wsmap state', 'wsmap', ANSWER)
    refused = wsmap_refusal(a, level)
    if refused:
        return Result(key, name, cls, refused[0], refused[1])
    r = {'name': name, 'lead': True, 'walker': RaidWalker(), 'inside': False}
    fallbacks = []
    trace = {'faults': [], 'steps': 0, 'fought': 0.0, 'stuck': None, 'died': False, 'secs': 0, 'came': 'foot', 'fallbacks': fallbacks, 'level': a.get('level'),
             'kills': 0}
    io.raid_mode([name], True, keep_flee=True)
    try:
        why = await solo_to_temple(io, r, trace, fallbacks)
        if why:
            return Result(key, name, cls, SKIP, why, fallbacks)
        e = await io.helper('wsmap enter %d' % int(a.get('freeTier') or 1), 'wsmap', HELPER_WAIT)
        if not isinstance(e, dict):
            return Result(key, name, cls, SKIP, 'no answer to !tester wsmap enter', fallbacks)
        if e.get('err'):
            return Result(key, name, cls, SKIP, 'wsmap enter: %s' % str(e['err'])[:80], fallbacks)
        fallbacks.append('teleport: the waystone device\'s pads and teleport are base code')
        trace['came'] = 'helper'
        await io.sleep(SETTLE)
        await solo_play(io, r, trace, {
            'system': 'wsmap', 'budget': WSMAP_BUDGET, 'problems': wsmap_problems, 'done': lambda t: t.get('kills', 0) >= WSMAP_NEED,
            'made': lambda t: t.get('kills', 0) > 0,
            'mark': lambda s: ((s.get('run') or {}).get('monsters'), (s.get('run') or {}).get('nearestHp'))})
        await io.helper('wsmap close', 'wsmap', ANSWER)
        again = await io.helper('wsmap state', 'wsmap', ANSWER)
        if isinstance(again, dict) and again.get('inside'):
            trace['faults'].append('the bot is still inside the waystone map after the close')
        status, text = wsmap_walk_verdict(trace)
        return Result(key, name, cls, status, text, fallbacks)
    finally:
        await io.helper('wsmap close', 'wsmap', ANSWER)
        io.raid_mode([name], False)
        await io.go('hunt')




# ------------------------------------------------------------------------------------------------ O655: ascension, spells, tales, tasks, gathering, settings
# The Ascendant Oracle's quest on foot (the Calling, the Proof of Strength, the Trial, the Choice), the support spells of the class, Archivist Maelis's
# tales, the kill task board, gathering with a pick or a sickle, and the settings windows (pouch rules, the Auto Seller, the stash, the Gambler's reroll).
# The windows are the bot's own requests; the modal windows of the Oracle and of the Archivist are answered by id (testers.py parse_modal,
# modal_answer: the 0xFA window the server sends and the 0xF9 answer a person's button press makes). Helper v20: `!tester ascend`, `!tester gather`.
ASC_ORACLE = 'Ascendant Oracle'
ASC_TRIAL_MODAL = 7101      # ascension_quest_config.lua modal
ASC_CHOICE_MODAL = 7102
ASC_CONFIRM_BASE = 7110     # + the vocation id
ASC_ENTER_WAIT = 10.0       # seconds from the press of Enter to standing inside the trial
ASC_TRIAL_BUDGET = 240.0    # seconds the trial is played at most (its own limit is 180 s)
ASC_BACK_WAIT = 16.0        # seconds from the win to the Oracle again (the exit comes after 6 s)
ASC_STEPS = ('calling', 'proof', 'trial', 'locked', 'choice')


def ascension_refusal(a, level=0):
    """(status, text) when this bot must not play the check, else None: from its `!tester ascend` answer"""
    if not isinstance(a, dict):
        return SKIP, 'no answer to !tester ascend (old helper file)'
    if a.get('err'):
        return SKIP, str(a['err'])[:80]
    if a.get('enabled') is False:
        return SKIP, 'the ascension quest is closed'
    if a.get('ascended'):
        return SKIP, '%s is an ascended class already' % (a.get('vocName') or 'the class')
    if not a.get('eligible'):
        if a.get('why') == 'level':
            return SKIP, 'level %s: the ascension needs level %s' % (a.get('level') or level, a.get('minLevel'))
        return SKIP, 'the class has no ascension (%s)' % (a.get('why') or 'no line')
    if int(a.get('stage') or 0) >= 4:
        return SKIP, 'the quest is done already (stage %s)' % a.get('stage')
    if a.get('inside'):
        return SKIP, 'the bot is inside a trial already'
    return None


def asc_choice_plan(choices):
    """(locked, allowed): the choices of the Oracle's window the account may not use (the class lock: they must be refused) and the ones it may (the
    first of them is taken), each as the probe lists it ({i, word, id, name, allowed})"""
    rows = [c for c in choices or [] if isinstance(c, dict) and isinstance(c.get('id'), int) and isinstance(c.get('i'), int)]
    return [c for c in rows if not c.get('allowed')], [c for c in rows if c.get('allowed')]


def ascension_verdict(t):
    """(status, text) from the trace: faults, done (the stages that passed, in order), why (where it stopped), refused (the locked classes the Oracle
    refused), from / to (the class before and after), fallbacks"""
    if t.get('faults'):
        return FAIL, '; '.join(t['faults'][:3])
    note = ('; teleport in place of walking: ' + ', '.join(t['fallbacks'])) if t.get('fallbacks') else ''
    done = t.get('done') or []
    if not done:
        return SKIP, '%s%s' % (t.get('why') or 'no step of the ascension was played', note)
    text = 'steps: %s' % ', '.join(done)
    if t.get('refused'):
        text += '; the class lock refused %s' % ', '.join(t['refused'])
    if t.get('to'):
        text += '; %s became %s' % (t.get('from'), t['to'])
    if t.get('why'):
        text += ' (stopped: %s)' % t['why']
    return PASS, text + note


async def asc_look(io):
    a = await io.helper('ascend state', 'ascend', ANSWER)
    return a if isinstance(a, dict) and not a.get('err') else None


NPC_CHANNEL = 12   # TALKTYPE_PRIVATE_PN: what a player says to the NPC it has greeted goes in the NPC channel (npchandler.lua ignores a plain say from a focused player)
NPC_TALK = {}   # O656: npc name -> the asyncio.Lock of the bot that is talking to it (one focus at a time in the base NPC library)


async def npc_talk_begin(io, npc):
    """O656: one bot talks to one NPC at a time: ten bots said "hi" at the same Archivist in the same seconds and the NPC kept the first focus,
    answered the second with "Another page left blank." (the walk-away line) and the rest with nothing. A person waits for the one before"""
    lock = NPC_TALK.setdefault(npc, asyncio.Lock())
    await lock.acquire()
    held = getattr(io, 'npc_held', None)
    if held is None:
        held = []
        try:
            io.npc_held = held
        except AttributeError:
            pass
    held.append(lock)


async def npc_talk_end(io, bye=True):
    """O656: says bye (the NPC drops its focus) and lets the next bot at the NPC talk"""
    held = list(getattr(io, 'npc_held', None) or [])
    if not held:
        return
    if bye:
        try:
            if io.alive():
                await io.say('bye')
                await io.sleep(1.2)
        except Exception:   # noqa: BLE001 - the lock must go even when the bot is gone
            pass
    io.npc_held[:] = []
    for lock in held:
        if lock.locked():
            lock.release()


async def asc_greet(io, npc=None):
    if npc:
        await npc_talk_begin(io, npc)
    # O656: the talk of a player is limited to one line a second or so ("You are exhausted."): the greeting waits for the NPC's answer, then a pause
    said = getattr(io, 'said_and_heard', None)
    if said is None:
        await io.say('hi')
        await io.sleep(1.0)
        return []
    heard = await said('hi', 2.0)
    await io.sleep(1.5)
    return heard


async def check_ascension_walk(io, name, cls, level):
    """the class ascension as a person plays it: the Calling (words to the Oracle), the Proof of Strength (the TEST ONLY credit: a rare monster does not
    come on demand), the Trial (the modal window answered, the guardian fought), the Choice (a class the account has locked is refused, then an open one)"""
    key = 'ascension_walk'
    a = await io.helper('ascend state', 'ascend', ANSWER)
    refused = ascension_refusal(a, level)
    if refused:
        return Result(key, name, cls, refused[0], refused[1])
    r = {'name': name, 'lead': True, 'walker': RaidWalker(), 'inside': False}
    fallbacks = []
    trace = {'faults': [], 'done': [], 'why': None, 'refused': [], 'from': a.get('vocName'), 'to': None, 'fallbacks': fallbacks, 'steps': 0, 'fought': 0.0,
             'stuck': None, 'died': False, 'secs': 0, 'level': a.get('level'), 'boss_seen': False, 'hp': None, 'system': 'ascend'}
    io.raid_mode([name], True, keep_flee=True)
    try:
        why, notes = await chore_walk(io, name, ASC_ORACLE, 1)
        fallbacks.extend(notes)
        if why:
            return Result(key, name, cls, SKIP, why, fallbacks)
        await io.sleep(SETTLE)
        # 1 the Calling
        if int(a.get('stage') or 0) == 0:
            hi = await asc_greet(io, ASC_ORACLE)
            said = await io.said_and_heard('ascension', 2.5, NPC_CHANNEL)
            b = await asc_look(io)
            await npc_talk_end(io)
            if b is None or int(b.get('stage') or 0) != 1:
                trace['faults'].append('the bot asked the %s about its ascension and the quest is at stage %s, not the Proof of Strength (heard: %s)' % (
                    ASC_ORACLE, (b or {}).get('stage'), ' | '.join(str(h)[:60] for h in (list(hi or []) + list(said or []))[:5]) or 'nothing'))
                return Result(key, name, cls, FAIL, '; '.join(trace['faults']), fallbacks)
            trace['done'].append('calling')
            a = b
        # 2 the Proof of Strength
        if int(a.get('stage') or 0) == 1:
            g = await io.helper('ascend proof', 'ascend', HELPER_WAIT)
            if not isinstance(g, dict) or g.get('err'):
                trace['why'] = 'proof of strength: %s' % str((g or {}).get('err') or 'no answer')[:70]
            elif int(g.get('stage') or 0) != 2:
                trace['faults'].append('the proof of strength was credited (%s of %s) and the quest stays at stage %s' % (g.get('proof'), g.get('needed'), g.get('stage')))
            else:
                trace['done'].append('proof')
                a = g
        if trace['faults'] or int(a.get('stage') or 0) < 2:
            status, text = ascension_verdict(trace)
            return Result(key, name, cls, status, text, fallbacks)
        # 3 the Trial
        if int(a.get('stage') or 0) == 2:
            if int(a.get('wait') or 0) > 0:
                trace['why'] = 'the trial is closed for %s s after the last attempt' % a.get('wait')
            elif int(a.get('free') or 0) - 1 < int(a.get('reserve') or 0) and a.get('tester', True):
                trace['why'] = 'the trial chambers are kept for the players (%s free, %s reserved)' % (a.get('free'), a.get('reserve'))
            else:
                await asc_greet(io, ASC_ORACLE)
                win, heard = await io.say_modal('trial', (ASC_TRIAL_MODAL,), 5.0, NPC_CHANNEL)
                await npc_talk_end(io)
                if win is None:
                    trace['why'] = 'the Oracle opened no trial window (%s)' % (heard[0][:60] if heard else 'it said nothing')
                else:
                    _, heard = await io.modal_answer(ASC_TRIAL_MODAL, 1, 0, 1.0)
                    s, waited = None, 0.0
                    while waited <= ASC_ENTER_WAIT and io.alive():
                        s = await asc_look(io)
                        if isinstance(s, dict) and s.get('inside'):
                            break
                        await io.sleep(1.0)
                        waited += 1.0
                    if not (isinstance(s, dict) and s.get('inside')):
                        trace['why'] = 'Enter was pressed and the trial did not open (%s)' % (heard[0][:60] if heard else 'no message')
                    else:
                        await solo_play(io, r, trace, asc_play_config(trace))
                        await io.helper('ascend close', 'ascend', ANSWER)
                        waited = 0.0
                        while waited <= ASC_BACK_WAIT and io.alive():
                            a = await asc_look(io) or a
                            if not a.get('inside'):
                                break
                            await io.sleep(1.0)
                            waited += 1.0
                        a = await asc_look(io) or a
                        if int(a.get('stage') or 0) >= 3:
                            trace['done'].append('trial')
                        elif trace.get('died'):
                            trace['why'] = 'the bot fell in the trial (level %s)' % trace.get('level')
                        else:
                            trace['why'] = 'the guardian was not broken in %d s (stage %s, cooldown %s s)' % (trace.get('secs', 0), a.get('stage'), a.get('wait'))
        if trace['faults'] or int(a.get('stage') or 0) < 3:
            status, text = ascension_verdict(trace)
            return Result(key, name, cls, status, text, fallbacks)
        # 4 the Choice: the classes the account has locked are refused first, then the first open one is taken
        locked, allowed = asc_choice_plan(a.get('choices'))
        await asc_look(io)
        for kind, c in [('locked', x) for x in locked[:1]] + [('allowed', x) for x in allowed[:1]]:
            why, notes = await chore_walk(io, name, ASC_ORACLE, 1)
            fallbacks.extend(notes)
            if why:
                trace['why'] = why
                break
            await asc_greet(io, ASC_ORACLE)
            win, heard = await io.say_modal('choice', (ASC_CHOICE_MODAL,), 5.0, NPC_CHANNEL)
            await npc_talk_end(io)
            if win is None:
                trace['why'] = 'the Oracle opened no choice window (%s)' % (heard[0][:60] if heard else 'it said nothing')
                break
            if len(win.get('choices') or []) != len(a.get('choices') or []):
                trace['faults'].append('the choice window lists %d classes, the quest has %d' % (len(win.get('choices') or []), len(a.get('choices') or [])))
                break
            conf, heard = await io.modal_answer(ASC_CHOICE_MODAL, 1, c['i'], 3.0, (ASC_CONFIRM_BASE + c['id'],))
            if conf is None:
                trace['faults'].append('%s was chosen in the Oracle\'s window and no confirmation came (%s)' % (c.get('name'), heard[0][:60] if heard else 'no message'))
                break
            _, heard = await io.modal_answer(conf['id'], 1, 0, 3.0)
            b = await asc_look(io)
            if b is None:
                trace['why'] = 'no look after the choice'
                break
            if kind == 'locked':
                if int(b.get('voc') or 0) == c['id'] or b.get('ascended'):
                    trace['faults'].append('%s is locked for the account and the Oracle ascended the bot to it' % c.get('name'))
                    break
                trace['refused'].append('%s (%s)' % (c.get('name'), (heard[0][:50] if heard else 'no text')))
                trace['done'].append('locked')
                a = b
            else:
                if not b.get('ascended') or int(b.get('voc') or 0) != c['id'] or int(b.get('stage') or 0) != 4:
                    trace['faults'].append('%s was confirmed and the bot is %s at stage %s' % (c.get('name'), b.get('vocName'), b.get('stage')))
                    break
                trace['done'].append('choice')
                trace['to'] = b.get('vocName')
        if not allowed and not trace['faults']:
            trace['why'] = 'every class of the line is locked for the account (the refusal was proved)'
        status, text = ascension_verdict(trace)
        return Result(key, name, cls, status, text, fallbacks)
    finally:
        await io.helper('ascend close', 'ascend', ANSWER)
        io.raid_mode([name], False)
        await io.go('hunt')


def asc_play_config(trace):
    trace['system'] = 'ascend'
    return {'system': 'ascend', 'budget': ASC_TRIAL_BUDGET, 'problems': boss_problems, 'done': lambda t: False,
            'stop': lambda s, t: int(s.get('stage') or 0) >= 3, 'made': lambda t: bool(t.get('boss_seen')),
            'mark': lambda s: ((s.get('run') or {}).get('bossHp'), (s.get('run') or {}).get('adds'))}


# the support spells of the class, cast (loadtest.rotation_for skips them: the attack rotation is all a bot casts), and the learned-spell rule
SPELL_CASTS = 6        # support / healing spells cast at most
SPELL_LEARN_CASTS = 2  # needlearn spells tried at most
SPELL_GAP = 2.7        # seconds between two casts (the group cooldown of a support spell is 2 s)
SPELL_REFUSALS = (('unknown', ('must learn', 'not learned', 'learn this')), ('vocation', ('vocation cannot', 'your vocation')), ('premium', ('premium',)),
                  ('level', ('enough level', 'enough magic level', 'magic level')), ('mana', ('enough mana', 'not enough mana')), ('exhausted', ('exhausted',)),
                  ('soul', ('soul',)))


def spell_refusal(texts):
    """the kind of refusal the server's text lines of a cast hold (unknown, vocation, premium, level, mana, exhausted, soul) or None: the cast passed"""
    for t in texts or []:
        low = str(t).lower()
        for kind, words in SPELL_REFUSALS:
            if any(w in low for w in words):
                return kind
    return None


def spell_support_pick(spells, level, count=SPELL_CASTS):
    """the support and healing spells of the class a person casts by hand: not an attack, no parameter, no target, no learning, at the level; one row
    per words, the higher level first"""
    out, seen = [], set()
    for s in sorted(spells or [], key=lambda s: (-int(s.get('level') or 0), str(s.get('words')))):
        if s.get('group') in ('attack', '', None) or s.get('needlearn') or s.get('params') or s.get('needtarget'):
            continue
        if int(s.get('level') or 0) > int(level or 0) or s.get('words') in seen:
            continue
        seen.add(s['words'])
        out.append(s)
        if len(out) >= count:
            break
    return out


def spell_learn_pick(spells, level, count=SPELL_LEARN_CASTS):
    """the spells only a quest teaches (needlearn), at the level: the bot has not learned them and the server must say so"""
    out = [s for s in spells or [] if s.get('needlearn') and not s.get('params') and int(s.get('level') or 0) <= int(level or 0)]
    out.sort(key=lambda s: (int(s.get('level') or 0), str(s.get('words'))))
    return out[:count]


def spell_support_verdict(cast, learn):
    """(status, text): cast: [(spell, kind of refusal or None)] of the support spells, learn: the same for the needlearn ones. A spell the class lists that the
    server calls unknown, of another vocation or premium is a bug; a needlearn spell that is not refused as unlearned is a note (silence is not proof)"""
    if not cast and not learn:
        return SKIP, 'the class lists no support spell and no learned spell at its level'
    bad = [(s, k) for s, k in cast if k in ('unknown', 'vocation', 'premium')]
    if bad:
        return FAIL, 'the server refuses a spell the class lists: %s' % ', '.join('%s (%s)' % (s.get('words'), k) for s, k in bad[:4])
    done = [s for s, k in cast if k is None]
    held = [s for s, k in cast if k in ('mana', 'exhausted', 'level', 'soul')]
    taught = [s for s, k in learn if k == 'unknown']
    quiet = [s for s, k in learn if k is None]
    parts = []
    if cast:
        parts.append('%d of %d support spell(s) cast with no refusal (%s)' % (len(done), len(cast), ', '.join(str(s.get('words')) for s in done[:4]) or 'none'))
    if held:
        parts.append('%d held back by %s' % (len(held), '/'.join(sorted({k for s, k in cast if k in ('mana', 'exhausted', 'level', 'soul')}))))
    if learn:
        parts.append('%d of %d learned-spell(s) refused until the quest teaches them%s' % (len(taught), len(learn), (', %d cast without a word' % len(quiet)) if quiet else ''))
    if not done and not taught:
        return SKIP, '; '.join(parts) or 'no cast went through'
    return PASS, '; '.join(parts)


async def check_spell_support(io, name, cls, level):
    """casts the support and healing spells of the class by their words, as a person on the hotbar, and the spells only a quest teaches"""
    key = 'spell_support'
    spells = io.class_spells()
    if not spells:
        return Result(key, name, cls, SKIP, 'no spell list for the class')
    cast, learn = [], []
    for s in spell_support_pick(spells, level):
        heard = await io.said_and_heard(s['words'], SPELL_GAP)
        cast.append((s, spell_refusal(heard)))
    for s in spell_learn_pick(spells, level):
        heard = await io.said_and_heard(s['words'], SPELL_GAP)
        learn.append((s, spell_refusal(heard)))
    status, text = spell_support_verdict(cast, learn)
    return Result(key, name, cls, status, text)


# Archivist Maelis's tales: the list window (7170), one tale (7171), by the buttons a person presses
TALES_NPC = 'Archivist Maelis'
TALES_LIST_MODAL = 7170
TALES_TALE_MODAL = 7171


def tales_verdict(listing, tale, heard):
    """(status, text) from the list window (a parse_modal dict or None), the tale window after Read (or None) and the text lines of the talk"""
    if listing is None:
        return SKIP, 'the Archivist opened no list of tales (%s)' % (' | '.join(str(h)[:70] for h in heard[:4]) if heard else 'she said nothing')   # O656: every line heard, not the first
    names = [str(t).lower() for _, t in listing.get('buttons') or []]
    if not listing.get('title'):
        return FAIL, 'the list of tales has no title'
    if not any('read' in n for n in names) or not any('close' in n for n in names):
        return FAIL, 'the list of tales has the buttons %s, not Read and Close' % ', '.join(names) if names else 'the list of tales has no buttons'
    if not listing.get('choices'):
        return PASS, 'the list of tales opened with no tale open at this level (Read and Close)'
    if tale is None:
        return FAIL, 'Read was pressed on %s and no tale window came' % str(listing['choices'][0][1])[:40]
    if not tale.get('title') or not tale.get('message'):
        return FAIL, 'the tale window has no title or no text'
    return PASS, 'the list shows %d tale(s); Read opened "%s" (%d characters)' % (len(listing['choices']), str(tale.get('title'))[:40], len(tale.get('message') or ''))


async def check_tales_read(io, name, cls, level):
    """walks to Archivist Maelis, says hi and tales, presses Read on the first tale and closes the window"""
    key = 'tales_read'
    why, fallbacks = await chore_walk(io, name, TALES_NPC, 1)
    if why:
        return Result(key, name, cls, SKIP, why)
    await asc_greet(io, TALES_NPC)
    listing, heard = await io.say_modal('tales', (TALES_LIST_MODAL,), 5.0, NPC_CHANNEL)
    await npc_talk_end(io)
    tale = None
    if listing is not None and listing.get('choices'):
        read = next((b for b, t in listing.get('buttons') or [] if 'read' in str(t).lower()), listing.get('enter') or 1)
        tale, _ = await io.modal_answer(TALES_LIST_MODAL, read, listing['choices'][0][0], 3.0, (TALES_TALE_MODAL,))
        if tale is not None:
            await io.modal_answer(TALES_TALE_MODAL, tale.get('escape') or 0, 255, 1.0)
        await io.modal_answer(TALES_LIST_MODAL, listing.get('escape') or 2, 255, 0.5)
    elif listing is not None:
        await io.modal_answer(TALES_LIST_MODAL, listing.get('escape') or 2, 255, 0.5)
    status, text = tales_verdict(listing, tale, heard)
    return Result(key, name, cls, status, text, fallbacks)


# the kill task board of the Bestiary: accept the first open offer, see it in the active list and the tracker, abandon it
def kill_task_pick(board, level):
    """the offer a person takes: an open one (not held, not done), the level window of a family task round the bot's level first, then the fewest kills"""
    rows = [o for o in (board or {}).get('offers') or [] if isinstance(o, dict) and o.get('key') and o.get('state') == 'open']
    def fits(o):
        lo, hi = int(o.get('lo') or 0), int(o.get('hi') or 0)
        return 0 if (hi and lo <= int(level or 0) <= hi) or not hi else 1
    rows.sort(key=lambda o: (fits(o), int(o.get('required') or 0), str(o.get('key'))))
    return rows[0] if rows else None


def kill_task_verdict(offer, after, gone):
    """(status, text) from the board after the accept (`after`) and after the abandon (`gone`)"""
    if not isinstance(after, dict):
        return SKIP, 'no board after the accept'
    mine = next((t for t in after.get('tasks') or [] if t.get('key') == offer.get('key')), None)
    row = next((o for o in after.get('offers') or [] if o.get('key') == offer.get('key')), None)
    if mine is None:
        return FAIL, 'accepted the kill task %s and it is not in the active list' % offer.get('key')
    if int(mine.get('progress') or 0) != 0 or int(mine.get('required') or 0) != int(offer.get('required') or 0):
        return FAIL, 'the accepted task %s shows %s of %s, the offer asked %s' % (offer.get('key'), mine.get('progress'), mine.get('required'), offer.get('required'))
    if row is not None and row.get('state') != 'active':
        return FAIL, 'the offer %s is "%s" after the accept, not active' % (offer.get('key'), row.get('state'))
    if not isinstance(gone, dict):
        return SKIP, 'no board after the abandon'
    if any(t.get('key') == offer.get('key') for t in gone.get('tasks') or []):
        return FAIL, 'abandoned the kill task %s and it is still in the active list' % offer.get('key')
    return PASS, 'kill task %s (%s x%s): accepted, listed active, abandoned' % (offer.get('key'), str(offer.get('label'))[:30], offer.get('required'))


async def check_kill_task(io, name, cls, level):
    """the kill task board: open, accept an offer of the day, it is active, abandon it (the kills come with the bot's own hunts)"""
    key = 'kill_task'
    reply = await io.request('bestiary', 'board', {}, ('board',), ANSWER)
    board = (reply or {}).get('data') if isinstance(reply, dict) else None
    if not isinstance(board, dict):
        return Result(key, name, cls, SKIP, 'no answer from the Bestiary board')
    offer = kill_task_pick(board, level)
    if offer is None:
        return Result(key, name, cls, SKIP, 'no open kill task on the board (%d offer(s), %d held)' % (len(board.get('offers') or []), len(board.get('tasks') or [])))
    try:
        reply = await io.request('bestiary', 'accept', {'key': offer['key']}, ('board',), ANSWER)
        after = (reply or {}).get('data') if isinstance(reply, dict) else None
        if isinstance(after, dict) and not any(t.get('key') == offer['key'] for t in after.get('tasks') or []):
            return Result(key, name, cls, SKIP, 'the board did not take %s (a limit of tasks held, or the level)' % offer['key'])
    finally:
        reply2 = await io.request('bestiary', 'abandon', {'key': offer['key']}, ('board',), ANSWER)
    gone = (reply2 or {}).get('data') if isinstance(reply2, dict) else None
    status, text = kill_task_verdict(offer, after, gone)
    return Result(key, name, cls, status, text)


# gathering with a pick or a sickle: buy a tool when the bot has none, walk to the nearest node that is ready for it, use it, wait for the channel
GATHER_TOOL_IDS = (2405, 2553)   # sickle, pick (professions_config.lua broker.tools)
GATHER_CHANNEL_WAIT = 10.0       # seconds from the use of the node to the material (the channel is 3 s)


def gather_tool_pick(a):
    """the tool a person buys first: the cheapest pick or sickle of the broker's list that the bot can pay; (row, why)"""
    rows = [t for t in (a or {}).get('buy') or [] if t.get('id') in GATHER_TOOL_IDS and t.get('clientId')]
    rows.sort(key=lambda t: int(t.get('price') or 0))
    if not rows:
        return None, 'the broker lists no pick or sickle'
    bank = a.get('bank')
    if bank is not None and int(bank) < int(rows[0].get('price') or 0):
        return None, 'the bot has %s gold in the bank, a %s costs %s' % (bank, rows[0]['id'], rows[0].get('price'))
    return rows[0], None


def gather_verdict(a, b, channel, texts):
    """(status, text): a = the probe before the use (node, held), b = after, channel = a look showed `gathering`, texts = the server's lines after the use"""
    node = (a or {}).get('node') or {}
    if not isinstance(b, dict):
        return SKIP, 'no look after the use of the node'
    gained = int(b.get('held') or 0) - int(a.get('held') or 0)
    if gained > 0:
        return PASS, 'gathered %d material(s) from a %s node of tier %s' % (gained, node.get('prof'), node.get('tier'))
    low = ' '.join(str(t) for t in texts or []).lower()
    if channel:
        return SKIP, 'the channel started and no material came (interrupted: a monster, a step)'
    if low:
        return SKIP, 'the node said: %s' % str(texts[0])[:70]
    return FAIL, 'the bot stood next to a %s node, used it and no gather started and no word came' % node.get('prof')


async def check_gather_walk(io, name, cls, level):
    """gathering: a pick or a sickle from the Material Broker, the nearest ready node on foot, the use, the material in the bag"""
    key = 'gather_walk'
    a = await io.helper('gather state', 'gather', ANSWER)
    if not isinstance(a, dict):
        return Result(key, name, cls, SKIP, 'no answer to !tester gather (old helper file)')
    if a.get('err'):
        return Result(key, name, cls, SKIP, str(a['err'])[:80])
    if not a.get('enabled') or not a.get('levelOk'):
        return Result(key, name, cls, SKIP, 'level %s: the professions open at level %s' % (a.get('level') or level, a.get('minLevel')))
    r = {'name': name, 'lead': True, 'walker': RaidWalker(), 'inside': False}
    fallbacks = []
    io.raid_mode([name], True, keep_flee=True)
    try:
        if not (a.get('tools') or {}).get('delving') and not (a.get('tools') or {}).get('wortcunning'):
            tool, why = gather_tool_pick(a)
            if tool is None:
                return Result(key, name, cls, SKIP, why)
            why, notes = await chore_walk(io, name, 'Material Broker', 1)
            fallbacks.extend(notes)
            if why:
                return Result(key, name, cls, SKIP, why, fallbacks)
            await npc_talk_begin(io, 'Material Broker')
            items = await io.shop_window('Material Broker')
            io.shop_close()
            if not items or not any(i.get('id') == tool['clientId'] for i in items):
                return Result(key, name, cls, SKIP, 'the Material Broker\'s window does not list the tool (%s)' % ('no window' if not items else 'item %s' % tool['clientId']), fallbacks)
            bought = await io.buy(tool['clientId'])
            await npc_talk_end(io)
            await io.sleep(1.5)
            a = await io.helper('gather state', 'gather', ANSWER) or a
            if not (a.get('tools') or {}).get('delving') and not (a.get('tools') or {}).get('wortcunning'):
                return Result(key, name, cls, FAIL, 'bought item %s (%s gold) from the Material Broker and the backpack holds no pick or sickle (heard: %s)' % (
                    tool['id'], tool.get('price'), ' | '.join(str(h)[:60] for h in (bought or [])[:4]) or 'nothing'), fallbacks)
        node = a.get('node')
        if not node:
            return Result(key, name, cls, SKIP, str((a.get('guide') or {}).get('why') or 'no node ready for the bot')[:90], fallbacks)
        how, got = await walk_by_path(io, r, 'gather path', 'gather', 1)
        if how != 'foot':
            return Result(key, name, cls, SKIP, 'no way on foot to the %s node: %s' % (node.get('prof'), str((got or {}).get('err') or 'far')[:60]), fallbacks)
        await io.sleep(SETTLE)
        a = await io.helper('gather state', 'gather', ANSWER) or a
        node = a.get('node') or node
        dist = node.get('d')
        if dist is None or int(dist) > 1:
            return Result(key, name, cls, SKIP, 'the walk ended %s tiles from the node' % dist, fallbacks)
        before = a
        texts = await io.use_at(node['pos'], node['clientId'], node.get('stackpos') or 1)
        channel, waited, after = False, 0.0, None
        while waited <= GATHER_CHANNEL_WAIT and io.alive():
            await io.sleep(1.0)
            waited += 1.0
            after = await io.helper('gather state', 'gather', ANSWER)
            if isinstance(after, dict):
                channel = channel or bool(after.get('gathering'))
                if int(after.get('held') or 0) > int(before.get('held') or 0):
                    break
        status, text = gather_verdict(before, after, channel, texts)
        return Result(key, name, cls, status, text, fallbacks)
    finally:
        io.raid_mode([name], False)
        await io.go('hunt')


# ------------------------------------------------------------------------------------------------ O657: what O655 left
# The stash moved by the item-position packet, the exercise dummy, the mount, the knife on a corpse, the rod on water and the kill counts of a base
# kill task. Each is a thing a person does with an item or a tool: the bot sends the packets the client sends (an item dragged onto the stash window
# is the window's own `Stash` request with the item's place in the backpack, a tool used on a thing on the map is the use-with packet 0x83 from the
# hotkey place, the mount button is 0xD4) and reads what the server shows. TEST ONLY grants (an exercise weapon, a mount) go through the helper and
# are taken back. A check that cannot play a step says why (SKIP): a corpse is only there after a kill, water only near some hunts.
TOOL_KNIFE, TOOL_ROD = 5908, 2580   # professions_config.lua broker.tools: the obsidian knife, the fishing rod
STASH_WAIT = 2.5       # seconds a stash request collects its answers
DUMMY_RUN = 6.0        # seconds the weapon trains on the dummy (a charge every 0.75 s) before the look
MOUNT_WAIT = 2.5       # seconds from the mount toggle to the look (the server answers within a tick)
FLAY_WAIT = 90.0       # seconds the bot waits at its hunt for a fresh corpse of its own kills
FLAY_CHANNEL = 8.0     # seconds from the use of the knife to the experience (the channel is 2.5 s)
ANGLE_CASTS = 6        # casts of the rod at most (the Angling roll is once every 3 s)
ANGLE_PAUSE = 3.3      # seconds between two casts
TASK_BUDGET = 420.0    # seconds a kill task is hunted at most
TASK_KILLS = 3         # kills of the task's monster the counters must show for a pass
TASK_TRIES = 3         # offers tried until one has a hunt that is known


async def to_temple(io, r, fallbacks):
    """on foot to the temple (the helper's teleport is the counted fallback); None, or the reason the check cannot go on"""
    how, got, note = await walk_to_place(io, r, 'temple')
    if how not in ('foot', 'helper'):
        return how[:110]
    if note:
        fallbacks.append(note)
    await io.sleep(SETTLE)
    return None


# ---- the stash: an item dragged onto the window and taken out again
def stash_items(msgs):
    """the entries of every `addItems` message of the stash window ({'make': 'addItems', 'items': [{id, count, row?, sprite ...}]})"""
    out = []
    for m in msgs or []:
        d = m.get('data') if isinstance(m, dict) else None
        if isinstance(d, dict) and d.get('make') == 'addItems':
            out.extend(i for i in d.get('items') or [] if isinstance(i, dict))
    return out


def stash_units(msgs, item_id):
    """(units, rows) of one item type in a list the window sent: the sum of the counts, and the row ids of the stored whole items; None when the
    window sent no list at all"""
    if not any(isinstance(m, dict) and isinstance(m.get('data'), dict) and m['data'].get('make') == 'addItems' for m in msgs or []):
        return None, []
    ents = [i for i in stash_items(msgs) if i.get('id') == item_id]
    return sum(int(i.get('count') or 0) for i in ents), [i['row'] for i in ents if i.get('row') is not None]


def stash_closed(msgs):
    """the reason the window gave for refusing a deposit (`access`, or the tab list's canDeposit / depositWhy), or None"""
    for m in msgs or []:
        d = m.get('data') if isinstance(m, dict) else None
        if not isinstance(d, dict):
            continue
        if d.get('make') == 'access' and d.get('canDeposit') is False:
            return 'the window sent access canDeposit false'
        if d.get('make') == 'tabs' and d.get('canDeposit') is False:
            return 'deposits are closed here (%s)' % (d.get('depositWhy') or 'no reason given')
    return None


def stash_move_verdict(t):
    """(status, text) from the trace {'name', 'units0', 'units1', 'units2' (stash units of the item before, after the deposit, after the withdrawal;
    None: no list), 'closed' (the window's reason for refusing), 'back' (True / False / None: the backpack holds it again), 'row' (stored whole item)}"""
    if t.get('units0') is None or t.get('units1') is None:
        return SKIP, 'the stash sent no item list (%s)' % t.get('closed') if t.get('closed') else 'the stash sent no item list'
    if t['units1'] != t['units0'] + 1:
        if t.get('closed'):
            return SKIP, 'the stash takes no deposit here: %s' % t['closed']
        return FAIL, 'dragged %s from the backpack onto the stash and it lists %s unit(s), it listed %s before: expected one more' % (
            t.get('name'), t['units1'], t['units0'])
    if t.get('units2') is None:
        return FAIL, 'asked for %s back and the stash sent no list: it stays in the stash' % t.get('name')
    if t['units2'] != t['units0']:
        return FAIL, 'took %s out of the stash and it lists %s unit(s), it listed %s before the deposit' % (t.get('name'), t['units2'], t['units0'])
    if t.get('back') is False:
        return FAIL, 'took %s out of the stash and the backpack does not hold it: the stash lost it' % t.get('name')
    how = 'a stored item' if t.get('row') is not None else 'a stack'
    return PASS, 'deposited %s (%s) and took it out again: the stash went %s -> %s -> %s%s' % (
        t.get('name'), how, t['units0'], t['units1'], t['units2'], ', the backpack holds it' if t.get('back') else '')


async def stash_read(io):
    return await io.collect('stash', 'Stash', [{'make': 'SendItems'}], STASH_WAIT)


async def check_stash_move(io, name, cls, level):
    """a plain piece of the class kit (a TEST ONLY grant of the helper that goes back where it came from) dragged from the backpack onto the stash in
    the temple and taken out again: the stash lists one more, then one less; the backpack holds it again"""
    key = 'stash_move'
    gave = await io.helper('give item', 'give', HELPER_WAIT)
    if not isinstance(gave, dict):
        return Result(key, name, cls, SKIP, 'no answer to !tester give (old helper file)')
    if gave.get('err'):
        return Result(key, name, cls, SKIP, str(gave['err'])[:80])
    item_id, cid, index = gave.get('id'), gave.get('clientId'), gave.get('index')
    if not (item_id and cid and index is not None):
        return Result(key, name, cls, SKIP, 'the helper named no item or slot')
    r = {'name': name, 'lead': True, 'walker': RaidWalker(), 'inside': False}
    fallbacks = []
    t = {'name': 'item %s' % item_id, 'units0': None, 'units1': None, 'units2': None, 'closed': None, 'back': None, 'row': None}
    io.raid_mode([name], True, keep_flee=True)
    try:
        why = await to_temple(io, r, fallbacks)
        if why:
            return Result(key, name, cls, SKIP, why, fallbacks)
        await io.open_bag(gave.get('bagClientId'))
        await io.sleep(1.0)
        t['units0'], rows0 = stash_units(await stash_read(io), item_id)
        dep = await io.collect('stash', 'Stash', [{'make': 'Stash', 'Pos': {'x': 65535, 'y': 64, 'z': int(index), 'stackpos': int(index)},
                                                   'ItemId': int(cid), 'Count': 1, 'UpdateList': True}], STASH_WAIT)
        t['closed'] = stash_closed(dep)
        t['units1'], rows1 = stash_units(await stash_read(io), item_id)
        new = [x for x in rows1 if x not in rows0]
        t['row'] = new[0] if new else None
        if t['units0'] is None or t['units1'] != t['units0'] + 1:
            status, text = stash_move_verdict(t)
            if status == FAIL:   # O660: what the server said to the drag (a slot that holds another item, a full tab ...)
                text += ' (server lines: %s; bag slot %s of item %s)' % (recent_text(io) or 'none', index, item_id)
            return Result(key, name, cls, status, text, fallbacks)
        ask = {'make': 'Redeem', 'row': new[0]} if new else {'make': 'Redeem', 'item': int(item_id), 'count': 1}
        await io.collect('stash', 'Stash', [ask], STASH_WAIT)
        t['units2'], _ = stash_units(await stash_read(io), item_id)
        bag = await io.helper('bag', 'bag', ANSWER)
        if isinstance(bag, dict) and not bag.get('err'):
            rows = bag.get('rows') or []
            if any(x.get('id') == item_id for x in rows):
                t['back'] = True
            elif len(rows) >= int(bag.get('used') or 0):   # the report holds every row: the item is not there
                t['back'] = False
        status, text = stash_move_verdict(t)
        return Result(key, name, cls, status, text, fallbacks)
    finally:
        io.raid_mode([name], False)
        await io.go('hunt')


# ---- the exercise dummy: the weapon on the dummy, the skill tries rise
def dummy_verdict(a, b):
    """(status, text) from the state before (a) and after (b) the use of the exercise weapon on the dummy"""
    if not isinstance(b, dict):
        return SKIP, 'no look after the use of the weapon'
    w0, w1 = a.get('weapon') or {}, b.get('weapon') or {}
    s0, s1 = a.get('skill') or {}, b.get('skill') or {}
    spent = int(w0.get('charges') or 0) - (int(w1.get('charges') or 0) if w1 else 0)
    rose = (int(s1.get('level') or 0), int(s1.get('tries') or 0)) > (int(s0.get('level') or 0), int(s0.get('tries') or 0))
    skill = s0.get('skill') or 'the skill'
    if spent > 0 and rose:
        return PASS, 'the %s weapon on a %s dummy: %d charge(s) spent, %s level %s tries %s -> level %s tries %s' % (
            w0.get('kind'), (a.get('dummy') or {}).get('kind'), spent, skill, s0.get('level'), s0.get('tries'), s1.get('level'), s1.get('tries'))
    if spent > 0:
        return FAIL, 'the exercise weapon spent %d charge(s) on the dummy and %s did not rise (level %s, tries %s)' % (spent, skill, s1.get('level'), s1.get('tries'))
    if rose:
        return FAIL, '%s rose (tries %s -> %s) and the weapon spent no charge' % (skill, s0.get('tries'), s1.get('tries'))
    return SKIP, 'the use of the weapon on the dummy started no training (the chain %s)' % ('runs' if b.get('training') else 'did not start')


async def check_dummy_train(io, name, cls, level):
    """the exercise weapon (a TEST ONLY grant of the class's lowest one) used on the nearest training dummy in a protection zone: charges fall, the skill tries rise"""
    key = 'dummy_train'
    a = await io.helper('dummy state', 'dummy', ANSWER)
    if not isinstance(a, dict):
        return Result(key, name, cls, SKIP, 'no answer to !tester dummy (old helper file)')
    if a.get('err'):
        return Result(key, name, cls, SKIP, str(a['err'])[:80])
    if a.get('locked'):
        return Result(key, name, cls, SKIP, 'the class is locked: nothing is trained')
    r = {'name': name, 'lead': True, 'walker': RaidWalker(), 'inside': False}
    granted = used = False
    io.raid_mode([name], True, keep_flee=True)
    try:
        if not a.get('weapon'):
            g = await io.helper('dummy give', 'dummy', ANSWER)
            if not isinstance(g, dict) or g.get('err') or not g.get('weapon'):
                return Result(key, name, cls, SKIP, 'no exercise weapon for this bot: %s' % str((g or {}).get('err') or 'no answer')[:60])
            granted, a = True, g
        if not a.get('dummy'):
            return Result(key, name, cls, SKIP, str((a.get('guide') or {}).get('why') or 'no training dummy near')[:90])
        if (a.get('guide') or {}).get('mode') == 'walk':
            how, got = await walk_by_path(io, r, 'dummy path', 'dummy', 1)
            if how != 'foot':
                return Result(key, name, cls, SKIP, 'no way on foot to the dummy: %s' % str((got or {}).get('err') or 'far')[:60])
            await io.sleep(SETTLE)
            a = await io.helper('dummy state', 'dummy', ANSWER) or a
        if not a.get('pz'):
            return Result(key, name, cls, SKIP, 'the dummy stands outside a protection zone: nothing is trained there')
        if (a.get('guide') or {}).get('mode') != 'use':
            return Result(key, name, cls, SKIP, str((a.get('guide') or {}).get('why') or 'not within reach of the dummy')[:90])
        w, d = a['weapon'], a['dummy']
        used = True
        await io.use_item_with(w['clientId'], d['pos'], d['clientId'], d.get('stackpos') or 0)
        await io.sleep(DUMMY_RUN)
        b = await io.helper('dummy state', 'dummy', ANSWER)
        status, text = dummy_verdict(a, b)
        return Result(key, name, cls, status, text)
    finally:
        if used:
            await io.step(1, 0)   # a step away ends the chain, as a person walks off the dummy
        if granted:
            await io.helper('dummy clear', 'dummy', ANSWER)
        io.raid_mode([name], False)
        await io.go('hunt')


# ---- the mount: on, off, the speed
def mount_verdict(t):
    """(status, text) from the trace {'before', 'on', 'off' (mount states), 'texts_on' (the server's lines after the toggle on)}"""
    b, on, off = t.get('before') or {}, t.get('on'), t.get('off')
    if not isinstance(on, dict):
        return SKIP, 'no look after the mount toggle'
    said = ' '.join(str(x) for x in t.get('texts_on') or [])
    if not on.get('mounted'):
        if said:
            return SKIP, 'the server refused the mount: %s' % said[:70]
        if on.get('pz'):
            return SKIP, 'the bot stands in a protection zone: a mount is refused there'
        return FAIL, 'the mount (id %s, the current one %s) was toggled outside a protection zone and the bot is not mounted, and no word came' % (b.get('granted'), on.get('current'))
    if int(on.get('speed') or 0) < int(b.get('speed') or 0):
        return FAIL, 'mounted and slower: speed %s -> %s' % (b.get('speed'), on.get('speed'))
    if not isinstance(off, dict):
        return SKIP, 'no look after the dismount'
    if off.get('mounted'):
        return FAIL, 'toggled the mount off and the bot is still mounted (look mount %s)' % off.get('lookMount')
    gain = int(on.get('speed') or 0) - int(b.get('speed') or 0)
    if gain > 0 and int(off.get('speed') or 0) >= int(on.get('speed') or 0):
        return FAIL, 'dismounted and the mount speed stays: %s on foot, %s mounted, %s now' % (b.get('speed'), on.get('speed'), off.get('speed'))
    return PASS, 'mounted (speed %s -> %s) and dismounted (%s)' % (b.get('speed'), on.get('speed'), off.get('speed'))


async def check_mount_ride(io, name, cls, level):
    """a TEST ONLY mount from the helper, put on and off with the mount button's packet outside a protection zone: the outfit's mount, the speed"""
    key = 'mount_ride'
    a = await io.helper('mount state', 'mount', ANSWER)
    if not isinstance(a, dict):
        return Result(key, name, cls, SKIP, 'no answer to !tester mount (old helper file)')
    if a.get('err'):
        return Result(key, name, cls, SKIP, str(a['err'])[:80])
    io.raid_mode([name], True, keep_flee=True)
    try:
        g = await io.helper('mount give', 'mount', ANSWER)
        if not isinstance(g, dict) or g.get('err'):
            return Result(key, name, cls, SKIP, 'no mount for this bot: %s' % str((g or {}).get('err') or 'no answer')[:70])
        before = await io.helper('mount state', 'mount', ANSWER)
        if isinstance(before, dict) and before.get('pz'):   # a mount is refused in a protection zone: out to the hunt spot first
            await io.go('hunt')
            await io.sleep(SETTLE)
            before = await io.helper('mount state', 'mount', ANSWER)
        if not isinstance(before, dict) or before.get('err'):
            return Result(key, name, cls, SKIP, 'no look at the mount before the toggle')
        if before.get('pz'):
            return Result(key, name, cls, SKIP, 'the hunt spot is a protection zone: a mount is refused there')
        t = {'before': before}
        t['texts_on'] = await io.toggle_mount(True, MOUNT_WAIT)
        t['on'] = await io.helper('mount state', 'mount', ANSWER)
        if isinstance(t['on'], dict) and t['on'].get('mounted'):
            await io.toggle_mount(False, MOUNT_WAIT)
            t['off'] = await io.helper('mount state', 'mount', ANSWER)
        status, text = mount_verdict(t)
        return Result(key, name, cls, status, text)
    finally:
        await io.helper('mount clear', 'mount', ANSWER)
        io.raid_mode([name], False)


# ---- the knife on a fresh corpse and the rod on water
def tool_row(a, tool_id):
    """the Material Broker's row of a tool in a `!tester gather` answer: {'id', 'clientId', 'price'} or None"""
    return next((t for t in (a or {}).get('buy') or [] if t.get('id') == tool_id and t.get('clientId')), None)


async def buy_tool(io, name, a, tool_id, fallbacks):
    """the tool from the Material Broker when the bot has none; (the new `!tester gather` answer, None) or (None, the reason)"""
    row = tool_row(a, tool_id)
    if row is None:
        return None, 'the broker lists no tool %s' % tool_id
    bank = a.get('bank')
    if bank is not None and int(bank) < int(row.get('price') or 0):
        return None, 'the bot has %s gold in the bank, tool %s costs %s' % (bank, tool_id, row.get('price'))
    why, notes = await chore_walk(io, name, 'Material Broker')
    fallbacks.extend(notes)
    if why:
        return None, why
    items = await io.shop_window('Material Broker')
    io.shop_close()
    if not items or not any(i.get('id') == row['clientId'] for i in items):
        return None, 'the Material Broker\'s window does not list tool %s (%s)' % (tool_id, 'no window' if not items else 'item %s' % row['clientId'])
    await io.buy(row['clientId'])
    await io.sleep(1.5)
    return await io.helper('gather state', 'gather', ANSWER), None


def prof_mark(a, prof):
    """(level, experience) of a profession in a `!tester gather` answer: a gather that worked raises the pair"""
    p = ((a or {}).get('prof') or {}).get(prof) or {}
    return int(p.get('level') or 0), int(p.get('xp') or 0)


def flay_verdict(a, b, channel, texts):
    """(status, text): a = the look before the use of the knife, b = after, channel = a look showed `gathering`, texts = the server's lines after the use"""
    if not isinstance(b, dict):
        return SKIP, 'no look after the use of the knife'
    corpse = a.get('corpse') or {}
    if prof_mark(b, 'flaying') > prof_mark(a, 'flaying') or int(b.get('held') or 0) > int(a.get('held') or 0):
        return PASS, 'flayed a tier %s corpse: flaying %s -> %s, %d material(s) more' % (
            corpse.get('tier'), '/'.join(str(x) for x in prof_mark(a, 'flaying')), '/'.join(str(x) for x in prof_mark(b, 'flaying')),
            int(b.get('held') or 0) - int(a.get('held') or 0))
    low = ' '.join(str(t) for t in texts or []).lower()
    if channel:
        return SKIP, 'the channel started and nothing came (interrupted: a monster, a step)'
    if low:
        return SKIP, 'the corpse said: %s' % str(texts[0])[:70]
    if b.get('corpse') is None:
        return SKIP, 'the corpse was gone after the use (decayed, or taken by a hand)'
    return FAIL, 'the bot stood next to a fresh corpse, used the knife on it and no flaying started and no word came'


async def check_flay_walk(io, name, cls, level):
    """flaying: the bot waits at its hunt for a fresh corpse of its own kills, takes a knife from the Material Broker when it has none, walks to the corpse
    and uses the knife on it: the Flaying experience or the materials rise"""
    key = 'flay_walk'
    a = await io.helper('gather state', 'gather', ANSWER)
    if not isinstance(a, dict):
        return Result(key, name, cls, SKIP, 'no answer to !tester gather (old helper file)')
    if a.get('err'):
        return Result(key, name, cls, SKIP, str(a['err'])[:80])
    if not a.get('enabled') or not a.get('levelOk'):
        return Result(key, name, cls, SKIP, 'level %s: the professions open at level %s' % (a.get('level') or level, a.get('minLevel')))
    r = {'name': name, 'lead': True, 'walker': RaidWalker(), 'inside': False}
    fallbacks = []
    io.raid_mode([name], True, keep_flee=True)
    try:
        waited = 0.0
        while not a.get('corpse') and waited < FLAY_WAIT and io.alive():
            await io.sleep(3.0)
            waited += 3.0
            a = await io.helper('gather state', 'gather', ANSWER) or a
        if not a.get('corpse'):
            return Result(key, name, cls, SKIP, str((a.get('flayGuide') or {}).get('why') or 'no fresh corpse')[:90], fallbacks)
        if not (a.get('tools') or {}).get('flaying'):
            a2, why = await buy_tool(io, name, a, TOOL_KNIFE, fallbacks)
            if why:
                return Result(key, name, cls, SKIP, why, fallbacks)
            a = a2 or a
            if not (a.get('tools') or {}).get('flaying'):
                return Result(key, name, cls, FAIL, 'bought the obsidian knife from the Material Broker and the backpack holds none', fallbacks)
        knife = tool_row(a, TOOL_KNIFE)
        if knife is None:
            return Result(key, name, cls, SKIP, 'the broker lists no obsidian knife: its client id is unknown', fallbacks)
        a = await io.helper('gather state', 'gather', ANSWER) or a
        if not a.get('corpse'):
            return Result(key, name, cls, SKIP, 'the corpse was gone when the bot came back from the broker', fallbacks)
        if (a.get('flayGuide') or {}).get('mode') == 'walk':
            how, got = await walk_by_path(io, r, 'gather corpse', 'gather', 1)
            if how != 'foot':
                return Result(key, name, cls, SKIP, 'no way on foot to the corpse: %s' % str((got or {}).get('err') or 'far')[:60], fallbacks)
            await io.sleep(1.0)
            a = await io.helper('gather state', 'gather', ANSWER) or a
        corpse = a.get('corpse')
        if not corpse or int(corpse.get('d') or 0) > 1:
            return Result(key, name, cls, SKIP, 'the corpse is gone or %s tiles away after the walk' % (corpse or {}).get('d'), fallbacks)
        before = a
        texts = await io.use_item_with(knife['clientId'], corpse['pos'], corpse['clientId'], corpse.get('stackpos') or 0, 1.5)
        channel, after, waited = False, None, 0.0
        while waited <= FLAY_CHANNEL and io.alive():
            await io.sleep(1.0)
            waited += 1.0
            after = await io.helper('gather state', 'gather', ANSWER)
            if isinstance(after, dict):
                channel = channel or bool(after.get('gathering'))
                if prof_mark(after, 'flaying') > prof_mark(before, 'flaying'):
                    break
        status, text = flay_verdict(before, after, channel, texts)
        return Result(key, name, cls, status, text, fallbacks)
    finally:
        io.raid_mode([name], False)
        await io.go('hunt')


def angle_verdict(a, b, casts, texts):
    """(status, text): a = the look before the first cast of the rod, b = after the last, casts = how many were made, texts = the server's lines meanwhile"""
    if not isinstance(b, dict):
        return SKIP, 'no look after the cast'
    f0, f1 = a.get('fishing') or {}, b.get('fishing') or {}
    skill = (int(f1.get('level') or 0), int(f1.get('tries') or 0)) > (int(f0.get('level') or 0), int(f0.get('tries') or 0))
    xp = prof_mark(b, 'angling') > prof_mark(a, 'angling')
    held = int(b.get('held') or 0) - int(a.get('held') or 0)
    if held > 0 and not xp:
        return FAIL, 'the line brought %d material(s) and the Angling experience did not rise' % held
    if skill or xp or held > 0:
        return PASS, 'angling after %d cast(s): Fishing tries %s -> %s, Angling %s -> %s, %d material(s)' % (
            casts, f0.get('tries'), f1.get('tries'), '/'.join(str(x) for x in prof_mark(a, 'angling')), '/'.join(str(x) for x in prof_mark(b, 'angling')), max(0, held))
    low = ' '.join(str(t) for t in texts or [])
    if low:
        return SKIP, 'the cast said: %s' % low[:70]
    return SKIP, '%d cast(s) of the rod gave no Fishing try and no word (the rod needs bait, or the water is not fishable)' % casts


async def check_angle_walk(io, name, cls, level):
    """angling: the nearest fishable water on foot, a rod from the Material Broker when the bot has none, the rod cast at the water a few times: the
    Fishing skill tries, the Angling experience or the materials rise"""
    key = 'angle_walk'
    a = await io.helper('gather state', 'gather', ANSWER)
    if not isinstance(a, dict):
        return Result(key, name, cls, SKIP, 'no answer to !tester gather (old helper file)')
    if a.get('err'):
        return Result(key, name, cls, SKIP, str(a['err'])[:80])
    if not a.get('enabled') or not a.get('levelOk'):
        return Result(key, name, cls, SKIP, 'level %s: the professions open at level %s' % (a.get('level') or level, a.get('minLevel')))
    if not a.get('water'):
        return Result(key, name, cls, SKIP, str((a.get('angleGuide') or {}).get('why') or 'no fishable water near')[:90])
    r = {'name': name, 'lead': True, 'walker': RaidWalker(), 'inside': False}
    fallbacks = []
    io.raid_mode([name], True, keep_flee=True)
    try:
        if not (a.get('tools') or {}).get('angling'):
            a2, why = await buy_tool(io, name, a, TOOL_ROD, fallbacks)
            if why:
                return Result(key, name, cls, SKIP, why, fallbacks)
            a = a2 or a
            if not (a.get('tools') or {}).get('angling'):
                return Result(key, name, cls, FAIL, 'bought the fishing rod from the Material Broker and the backpack holds none', fallbacks)
        rod = tool_row(a, TOOL_ROD)
        if rod is None:
            return Result(key, name, cls, SKIP, 'the broker lists no fishing rod: its client id is unknown', fallbacks)
        a = await io.helper('gather state', 'gather', ANSWER) or a
        if not a.get('water'):
            return Result(key, name, cls, SKIP, 'no fishable water near after the broker', fallbacks)
        if (a.get('angleGuide') or {}).get('mode') == 'walk':
            how, got = await walk_by_path(io, r, 'gather water', 'gather', 2)
            if how != 'foot':
                return Result(key, name, cls, SKIP, 'no way on foot to the water: %s' % str((got or {}).get('err') or 'far')[:60], fallbacks)
            await io.sleep(1.0)
            a = await io.helper('gather state', 'gather', ANSWER) or a
        water = a.get('water')
        if not water or int(water.get('d') or 0) > 2:
            return Result(key, name, cls, SKIP, 'the walk ended %s tiles from the water' % (water or {}).get('d'), fallbacks)
        before, after, texts, casts = a, None, [], 0
        while casts < ANGLE_CASTS and io.alive():
            texts += await io.use_item_with(rod['clientId'], water['pos'], water['clientId'], water.get('stackpos') or 0, 1.0)
            casts += 1
            await io.sleep(ANGLE_PAUSE)
            after = await io.helper('gather state', 'gather', ANSWER)
            if isinstance(after, dict) and angle_verdict(before, after, casts, [])[0] != SKIP:
                break
        status, text = angle_verdict(before, after, casts, texts)
        return Result(key, name, cls, status, text, fallbacks)
    finally:
        io.raid_mode([name], False)
        await io.go('hunt')


# ---- the kill counts of a base kill task: hunt the monster of an accepted task, its counter and the bestiary entry rise
def task_hunt_pick(board, level, skip=()):
    """the offer to hunt: an open one of a single monster (kind hunt: the task names the monster) first, the fewest kills first, then a family task;
    an offer of `skip` (no hunt known for its monster) is left out"""
    rows = [o for o in (board or {}).get('offers') or [] if isinstance(o, dict) and o.get('key') and o.get('state') == 'open' and o.get('key') not in skip]
    rows.sort(key=lambda o: (0 if o.get('kind') == 'hunt' else 1, int(o.get('required') or 0), str(o.get('key'))))
    return rows[0] if rows else None


def task_kills_verdict(t):
    """(status, text) from the trace: faults, name (the monster), key, base (progress at the accept), progress, required, kills0 / kills (the bestiary entry
    before and after), fought, waited, stuck, died, steps, secs, level, fallbacks"""
    if t.get('faults'):
        return FAIL, '; '.join(t['faults'][:3])
    moved = int(t.get('progress') or 0) - int(t.get('base') or 0)
    how = 'level %s, %d step(s) in %d s' % (t.get('level'), t.get('steps', 0), t.get('secs', 0))
    if moved >= TASK_KILLS:
        k0, k1 = t.get('kills0'), t.get('kills')
        if k0 is not None and k1 is not None and int(k1) <= int(k0):
            return FAIL, 'the task %s counted %d kill(s) and the bestiary entry of %s stays at %s kills' % (t.get('key'), moved, t.get('name'), k1)
        return PASS, '%s: the task counter went from %s to %s of %s, the bestiary entry from %s to %s kills (%s)' % (
            t.get('name'), t.get('base'), t.get('progress'), t.get('required'), k0, k1, how)
    if t.get('fought', 0) >= SOLO_FIGHT_MIN:
        return FAIL, 'fought %d s in reach of %s and the kill task counter moved %d (kills, credit or the target)' % (t['fought'], t.get('name'), moved)
    if t.get('stuck'):
        return SKIP, 'the walk was blocked at (%d, %d) for %d s (%s)' % (t['stuck'][0], t['stuck'][1], SOLO_STUCK, how)
    if t.get('died'):
        return SKIP, 'the bot died at the hunt of %s (%s)' % (t.get('name'), how)
    if t.get('waited', 0) >= BOUNTY_SPAWN_WAIT:
        return SKIP, 'no %s in sight at its hunt for %d s (%s)' % (t.get('name'), t['waited'], how)
    return SKIP, 'the task counter of %s moved %d in %d s (%s)' % (t.get('name'), moved, t.get('secs', 0), how)


async def task_accept(io, offer):
    """accepts the offer through the Bestiary window; the board after it, or None when the task is not in the active list"""
    reply = await io.request('bestiary', 'accept', {'key': offer['key']}, ('board',), ANSWER)
    after = (reply or {}).get('data') if isinstance(reply, dict) else None
    if isinstance(after, dict) and any(t.get('key') == offer['key'] for t in after.get('tasks') or []):
        return after
    return None


async def check_kill_task_kills(io, name, cls, level):
    """a kill task of the Bestiary board accepted and hunted: the bot walks to the hunt that lists the monster (the bounty board's marks), fights it with
    its own rotation and the task counter and the bestiary entry rise (the `kill` message of the window). The task is abandoned after"""
    key = 'kill_task_kills'
    reply = await io.request('bestiary', 'board', {}, ('board',), ANSWER)
    board = (reply or {}).get('data') if isinstance(reply, dict) else None
    if not isinstance(board, dict):
        return Result(key, name, cls, SKIP, 'no answer from the Bestiary board')
    r = {'name': name, 'lead': True, 'walker': RaidWalker(), 'inside': False}
    fallbacks = []
    trace = {'faults': [], 'steps': 0, 'fought': 0.0, 'waited': 0.0, 'stuck': None, 'died': False, 'secs': 0, 'level': level, 'fallbacks': fallbacks}
    held, skip, offer, probe = None, set(), None, None
    io.raid_mode([name], True, keep_flee=True)
    try:
        for _ in range(TASK_TRIES):
            offer = task_hunt_pick(board, level, skip)
            if offer is None:
                break
            after = await task_accept(io, offer)
            if after is None:
                skip.add(offer['key'])
                continue
            held = offer['key']
            probe = await io.helper('task state', 'task', ANSWER)
            mine = next((x for x in (probe or {}).get('active') or [] if x.get('key') == held), None) if isinstance(probe, dict) else None
            g = (probe or {}).get('guide') or {} if isinstance(probe, dict) else {}
            if mine is not None and mine.get('monster') and not (g.get('mode') == 'wait' and 'no hunt lists' in str(g.get('why'))):
                break
            await io.request('bestiary', 'abandon', {'key': held}, ('board',), ANSWER)   # no hunt is known for its monster: the next offer
            skip.add(held)
            held, mine = None, None
            board = ((await io.request('bestiary', 'board', {}, ('board',), ANSWER)) or {}).get('data') or board
        if held is None:
            return Result(key, name, cls, SKIP, 'no open kill task with a monster that a hunt mark lists (%d offer(s) tried)' % len(skip))
        trace.update({'name': mine.get('monster'), 'key': held, 'base': mine.get('progress') or 0, 'progress': mine.get('progress') or 0,
                      'required': mine.get('required'), 'kills0': mine.get('kills'), 'kills': mine.get('kills')})
        elapsed, misses, fight_since, wait_since = 0.0, 0, None, None
        while io.alive() and elapsed < TASK_BUDGET:
            s = await io.helper('task state', 'task', ANSWER)
            if not isinstance(s, dict) or s.get('err'):
                misses += 1
                if misses >= SOLO_MISSES:
                    break
                await io.sleep(RAID_LOOK)
                elapsed += RAID_LOOK
                continue
            misses = 0
            mine = next((x for x in s.get('active') or [] if x.get('key') == held), None)
            if mine is None:
                if trace['progress'] - trace['base'] < TASK_KILLS:
                    trace['faults'].append('the accepted kill task %s left the list before the bot had killed enough' % held)
                break
            if (mine.get('progress') or 0) > trace['progress']:
                trace['progress'] = mine['progress']
                trace['kills'] = mine.get('kills')
                fight_since = None
                await io.loot()
            if trace['progress'] - trace['base'] >= TASK_KILLS:
                break
            g = s.get('guide') or {}
            mode = g.get('mode')
            if mode == 'fight':
                fight_since = elapsed if fight_since is None else fight_since
                trace['fought'] = max(trace['fought'], elapsed - fight_since)
            else:
                fight_since = None
            if mode == 'wait' and g.get('area') == 'spawn':
                wait_since = elapsed if wait_since is None else wait_since
                trace['waited'] = max(trace['waited'], elapsed - wait_since)
                if trace['waited'] >= BOUNTY_SPAWN_WAIT:
                    break
            else:
                wait_since = None
            plan = []
            if mode == 'walk' and isinstance(g.get('goal'), dict) and isinstance(s.get('pos'), dict):
                plan = r['walker'].steps(s['pos'], g['goal'], SOLO_STEPS, elapsed)
                if not r['walker'].blocked:
                    got = await hcmd(io, r, 'task path', 'task')
                    steps = raid_path_steps((got or {}).get('path')) if isinstance(got, dict) and not got.get('err') else []
                    plan = steps[:SOLO_STEPS] or plan
                if r['walker'].stuck(elapsed) >= SOLO_STUCK:
                    trace['stuck'] = (s['pos']['x'], s['pos']['y'])
                    break
            for step in plan:
                await raid_walk(io, r, step)
                trace['steps'] += 1
                await io.sleep(RAID_STEP)
                elapsed += RAID_STEP
            await io.sleep(RAID_LOOK)
            elapsed += RAID_LOOK
            trace['secs'] = int(elapsed)
        trace['secs'] = int(elapsed)
        trace['died'] = not io.alive()
        status, text = task_kills_verdict(trace)
        return Result(key, name, cls, status, text, fallbacks)
    finally:
        if held:   # the task goes back: its rows are the bot's own
            await io.request('bestiary', 'abandon', {'key': held}, ('board',), ANSWER)
        io.raid_mode([name], False)
        await io.go('hunt')


# settings windows: the pouch loot rules, the Auto Seller, the stash window, the Gambler's reroll
def rules_flags(rules):
    return sorted(k for k, v in (rules or {}).items() if isinstance(v, bool))


def pouch_rules_verdict(before, flipped, restored, flag):
    """(status, text): the rule `flag` was turned over and back through the window"""
    if not isinstance(before, dict) or not rules_flags(before):
        return SKIP, 'no loot rules in the pouches window'
    if not isinstance(flipped, dict):
        return SKIP, 'no answer to the change of the rule %s' % flag
    if flipped.get(flag) != (not before[flag]):
        return FAIL, 'the rule %s was turned from %s and the window shows %s' % (flag, before[flag], flipped.get(flag))
    others = [k for k in before if k != flag and flipped.get(k) != before[k]]
    if others:
        return FAIL, 'turning %s changed %s as well' % (flag, ', '.join(sorted(others)))
    if not isinstance(restored, dict) or any(restored.get(k) != v for k, v in before.items()):
        return FAIL, 'the rules were put back and the window shows %s' % (restored,)
    return PASS, 'rule %s turned %s and back; %d other rule(s) kept' % (flag, before[flag], len(before) - 1)


async def check_pouch_rules(io, name, cls, level):
    """the Loot Pouch rules window: open, turn one rule, read it back, put it back"""
    key = 'pouch_rules'
    reply = await io.request('pouches', 'open', {}, ('settings',), ANSWER)
    st = (reply or {}).get('data') if isinstance(reply, dict) else None
    rules = (st or {}).get('rules') if isinstance(st, dict) else None
    if not isinstance(rules, dict) or not rules_flags(rules):
        return Result(key, name, cls, SKIP, 'no rules in the pouches window')
    flag = rules_flags(rules)[0]
    new = dict(rules)
    new[flag] = not rules[flag]
    flipped = restored = None
    try:
        r2 = await io.request('pouches', 'set', {'rules': new}, ('settings',), ANSWER)
        flipped = ((r2 or {}).get('data') or {}).get('rules') if isinstance(r2, dict) else None
    finally:
        await io.sleep(0.5)   # O656: the server answers one 'set' in 200 ms at most (ChaosRateLimit pouches.set): the put-back came at once and got no answer
        r3 = await io.request('pouches', 'set', {'rules': rules}, ('settings',), ANSWER)
        restored = ((r3 or {}).get('data') or {}).get('rules') if isinstance(r3, dict) else None
    status, text = pouch_rules_verdict(rules, flipped, restored, flag)
    return Result(key, name, cls, status, text)


def autosell_verdict(st, after, back):
    """(status, text): st = the window state, after = after the pause switch, back = after the switch is put back"""
    if not isinstance(st, dict):
        return SKIP, 'no answer from the Auto Seller window'
    if not st.get('unlocked'):
        if not isinstance(after, dict):
            return SKIP, 'the Auto Seller is locked and no answer to the switch'
        if bool(after.get('paused')) != bool(st.get('paused')):
            return FAIL, 'the Auto Seller is locked for the bot and its pause switch moved'
        if not after.get('notice'):
            return FAIL, 'the Auto Seller is locked and the refusal says nothing'
        return PASS, 'the Auto Seller is locked for the bot (store item): the switch was refused with "%s"' % str(after['notice'])[:50]
    if not isinstance(after, dict):
        return SKIP, 'no answer to the pause switch'
    if bool(after.get('paused')) == bool(st.get('paused')):
        return FAIL, 'the pause switch of the Auto Seller did not move (paused %s)' % st.get('paused')
    if not isinstance(back, dict) or bool(back.get('paused')) != bool(st.get('paused')):
        return FAIL, 'the pause switch was put back and the window shows paused %s' % (back or {}).get('paused')
    return PASS, 'Auto Seller: corpse selling switched %s and back' % ('on' if st.get('paused') else 'off')


async def check_autosell_rules(io, name, cls, level):
    """the Auto Seller window: its state; a bot without the store unlock is refused, one with it turns the corpse selling over and back"""
    key = 'autosell_rules'
    reply = await io.request('pouches', 'as_open', {}, ('autoseller',), ANSWER)
    st = (reply or {}).get('data') if isinstance(reply, dict) else None
    if not isinstance(st, dict):
        return Result(key, name, cls, SKIP, 'no answer from the Auto Seller window')
    on = bool(st.get('paused'))   # `on` = corpse selling on: the opposite of paused
    await io.sleep(0.5)   # O656: the pouches.autosell limit is 250 ms: the switch right after the open got no answer
    r2 = await io.request('pouches', 'aspause', {'on': on}, ('autoseller',), ANSWER)
    after = (r2 or {}).get('data') if isinstance(r2, dict) else None
    back = None
    if isinstance(after, dict) and st.get('unlocked'):
        await io.sleep(0.5)
        r3 = await io.request('pouches', 'aspause', {'on': not on}, ('autoseller',), ANSWER)
        back = (r3 or {}).get('data') if isinstance(r3, dict) else None
    status, text = autosell_verdict(st, after, back)
    return Result(key, name, cls, status, text)


def stash_verdict(msgs):
    """(status, text) from the stash messages ({'action': 'Stash', 'data': {'make': ...}}) the window got after SendCategories, SendItems and Find"""
    datas = [m.get('data') for m in msgs or [] if isinstance(m, dict) and isinstance(m.get('data'), dict)]
    tabs = next((d for d in datas if d.get('make') == 'tabs'), None)
    if tabs is None:
        return SKIP, 'the stash sent no tab list (%d message(s))' % len(datas)
    rows = [t for t in tabs.get('tabs') or [] if isinstance(t, dict)]
    if not rows:
        return FAIL, 'the stash lists no tab'
    for t in rows:
        if t.get('size') is not None and t.get('used') is not None and int(t['used']) > int(t['size']):
            return FAIL, 'stash tab %s holds %s of %s' % (t.get('name'), t.get('used'), t.get('size'))
    found = next((d for d in datas if d.get('make') == 'found'), None)
    text = 'stash: %d tab(s), withdraw %s, deposit %s' % (len(rows), tabs.get('canWithdraw'), tabs.get('canDeposit'))
    if found is None:
        return PASS, text + '; no answer to the item search'
    if found.get('error') not in (None, 'short', 'long'):
        return FAIL, 'the item search answered with the error %s' % found.get('error')
    return PASS, text + '; the item search found %s' % found.get('total')


async def check_stash_window(io, name, cls, level):
    """the stash window as a person opens it: the tabs, the items, the item search"""
    key = 'stash_window'
    msgs = await io.collect('stash', 'Stash', [{'make': 'SendCategories', 'sendBlocks': True}, {'make': 'SendItems'}, {'make': 'Find', 'q': 'potion', 'page': 1}], 4.0)
    status, text = stash_verdict(msgs)
    return Result(key, name, cls, status, text)


def gamble_reroll_verdict(a, b, res):
    """(status, text): the Gambler's window before (a) and after (b) the reroll for gold; res = the window's result"""
    d = (res or {}).get('data') if isinstance(res, dict) else None
    if res is None:
        return SKIP, 'no answer to the reroll'
    if isinstance(d, dict) and d.get('ok') is False:
        return SKIP, 'the Gambler refused the reroll: %s' % str(d.get('text'))[:60]
    if not isinstance(b, dict):
        return SKIP, 'no state after the reroll'
    if int(b.get('rerolls') or 0) != int(a.get('rerolls') or 0) + 1:
        return FAIL, 'rerolled and the count went %s -> %s' % (a.get('rerolls'), b.get('rerolls'))
    paid = int(a.get('money') or 0) - int(b.get('money') or 0)
    if paid <= 0:
        return FAIL, 'rerolled the stock and the money did not fall (%s -> %s)' % (a.get('money'), b.get('money'))
    first = [(e.get('i'), e.get('id')) for e in a.get('items') or []]
    now = [(e.get('i'), e.get('id')) for e in b.get('items') or []]
    if first and first == now:
        return FAIL, 'rerolled for %s gold and the stock is the same' % paid
    return PASS, 'rerolled the Gambler\'s stock for %s gold: %d piece(s), rerolls %s -> %s' % (paid, len(now), a.get('rerolls'), b.get('rerolls'))


async def check_gamble_reroll(io, name, cls, level):
    """the Gambler's reroll: fresh crates for gold; the count, the money and the stock must move (the bot keeps the gold for supplies: never below 5000)"""
    key = 'gamble_reroll'
    why, fallbacks = await chore_walk(io, name, 'Mordecai Ashwager')
    if why:
        return Result(key, name, cls, SKIP, why)
    try:
        reply = await io.request('gamble', 'open', {}, ('state',), ANSWER)
        a = (reply or {}).get('data') if isinstance(reply, dict) else None
        if not isinstance(a, dict):
            return Result(key, name, cls, SKIP, 'no state in the Gambler window', fallbacks)
        price = a.get('reroll')
        if price is None:
            return Result(key, name, cls, SKIP, 'no more fresh crates before the next stock (%s rerolls used)' % a.get('rerolls'), fallbacks)
        if int(a.get('money') or 0) - int(price) < 5000:
            return Result(key, name, cls, SKIP, 'the reroll costs %s gold and the bot has %s: it keeps 5000 for supplies' % (price, a.get('money')), fallbacks)
        await io.sleep(GAMBLE_GAP)   # O660: see gear_pieces
        res = await io.request('gamble', 'reroll', {'w': a.get('w')}, ('result',), ANSWER)
        await io.sleep(1.0)
        again = await io.request('gamble', 'open', {}, ('state',), ANSWER)
        status, text = gamble_reroll_verdict(a, (again or {}).get('data') if isinstance(again, dict) else None, res)
        return Result(key, name, cls, status, text, fallbacks)
    finally:
        await io.request('gamble', 'close', {}, [], ANSWER)



# the checks of closed mode, run only with --closed: (key, function, applies to the class)
CLOSED_CHECKS = [
    ('closed_guards', check_closed_guards, lambda c: True),
    ('closed_arena', check_closed_arena, lambda c: True),
    ('closed_battleground', check_closed_battleground, lambda c: True),
    ('closed_pvp', check_closed_pvp, lambda c: True),
    ('closed_guild_war', check_closed_guild, lambda c: True),
    ('closed_market', check_closed_market, lambda c: True),
    ('closed_bazaar', check_closed_bazaar, lambda c: True),
    ('closed_groupqueue', check_closed_groupqueue, lambda c: True),   # O589
    ('closed_party_finder', check_closed_party_finder, lambda c: True),   # O589
    ('closed_dungeon', check_closed_dungeon, lambda c: True),   # O589
    ('dungeon_difficulty', check_dungeon_difficulty, lambda c: True),   # O651: difficulty 2 to 6, unlocked on the bot's own progress, the monsters scaled
    ('weekly_challenge', check_weekly_challenge, lambda c: True),   # O651: the Weekly Challenge: the fixed difficulty, no tester on its boards
    ('closed_siege', check_closed_siege, lambda c: True),   # O592
    ('closed_guildboss', check_closed_guildboss, lambda c: True),   # O592
    ('closed_arena_fight', check_closed_arena_fight, lambda c: True),   # O652: two testers fight in the arena, a foe hurt, no season row
    ('closed_pvp_fight', check_closed_pvp_fight, lambda c: True),   # O652: two testers fight in the Marches, only testers inside
    ('closed_battleground_match', check_closed_battleground_match, lambda c: True),   # O652: a match of testers only when 10 queue
    ('closed_raid', check_closed_raid, lambda c: True),   # the longest: last (O588)
]
CLOSED_KEYS = tuple(k for k, _, _ in CLOSED_CHECKS)


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
    ('unique_passive', check_unique_passive, lambda c: True),
    ('dual_fists', check_dual_fists, lambda c: True),
    ('dual_blades', check_dual_blades, lambda c: True),
    ('waystone', check_waystone, lambda c: True),
    ('reward_chest', check_reward_chest, lambda c: True),
    ('cursed_chest', check_cursed_chest, lambda c: True),
    ('auto_setup', check_auto_setup, lambda c: True),
    ('spell_quest', check_spell_quest, lambda c: True),
    ('craft_orbs', check_craft_orbs, lambda c: True),
    ('craft_whetstone', check_craft_whetstone, lambda c: True),
    ('craft_sockets', check_craft_sockets, lambda c: True),
    ('craft_gems', check_craft_gems, lambda c: True),
    ('craft_supports', check_craft_supports, lambda c: True),
    ('craft_charms', check_craft_charms, lambda c: True),
    ('craft_cards', check_craft_cards, lambda c: True),
    ('tower_walk', check_tower_walk, lambda c: True),   # O595: the Infinity Tower on foot, two floors
    ('descent_walk', check_descent_walk, lambda c: True),   # O595: the Ember Descent on foot, two rooms
    ('trial_walk', check_trial_walk, lambda c: True),   # O595: the vocation's trial on foot (the families with no puzzle stage)
    ('hideout', check_hideout, lambda c: True),   # O595: the own hideout: enter, place a decoration, remove it, leave
    ('ascended_walk', check_ascended_walk, lambda c: True),   # O599: the Ascended arena on foot, a sigil from the helper, the boss hurt
    ('omen_walk', check_omen_walk, lambda c: True),   # O599: the omen arena on foot, an Omen Key from the helper, the guardian hurt
    ('bounty_walk', check_bounty_walk, lambda c: True),   # O599: the smallest hunt contract with a known hunt: accept, walk, kill, the counter moves
    ('mainquest_walk', check_mainquest_walk, lambda c: True),   # O599: the first steps of the main quest: talk, walk, kill; O650: the later steps (bring, Go, daily, cast, hunt)
    ('bounty_elite_walk', check_bounty_elite_walk, lambda c: True),   # O650: an elite contract: a tier monster of the type falls, the counter moves
    ('bounty_boss_walk', check_bounty_boss_walk, lambda c: True),   # O650: a boss contract: to the boss's lair, the fight when no player is near
    ('daily_claim', check_daily_claim, lambda c: True),   # O650: the daily window: the claim, the reward in the bag, the streak
    ('chronicle_walk', check_chronicle_walk, lambda c: True),   # O650: the Chronicle: the window opened, no tester in the books
    ('nemesis_walk', check_nemesis_walk, lambda c: True),   # O650: a Nemesis born from a monster in sight (TEST ONLY), the fight
    ('pocket_walk', check_pocket_walk, lambda c: True),   # O651: a pocket boss through the Boss Spawns window: the boss falls, the charge is spent, the boss point comes
    ('wsmap_walk', check_wsmap_walk, lambda c: True),   # O651: a waystone map on a free arrival tile: monsters of the run's tier fall, a player sends the tester out
    ('goblin_walk', check_goblin_walk, lambda c: True),   # O650: a treasure goblin of the bot's own (TEST ONLY), chased and hit
    ('vael_walk', check_vael_walk, lambda c: True),   # O650: Vael Ashmourn through the TEST ONLY door, from level 500
    ('invasion_walk', check_invasion_walk, lambda c: True),   # O650: while an invasion runs: the hits of a tester are cancelled, no share
    ('craft_found', check_craft_found, lambda c: True),   # O653: the orbs, gems and runes the bot dropped, spent on backpack pieces (no helper grant)
    ('gear_chase', check_gear_chase, lambda c: True),   # O653: wears the piece whose score knows sets, uniques and jewelry
    ('chore_faction', check_chore_faction, lambda c: True),   # O653: the reputation window: ranks, contracts, tokens turned in
    ('chore_pass', check_chore_pass, lambda c: True),   # O653: the season pass: claim what the tier holds (a tester is on no season board)
    ('chore_chests', check_chore_chests, lambda c: True),   # O653: the Weekly Chest gives a tester nothing; the Ember Cache answers
    ('chore_candlemarks', check_chore_candlemarks, lambda c: True),   # O653: Osric's shop: the cheapest offer the bot can pay
    ('chore_gamble', check_chore_gamble, lambda c: True),   # O653: the Gambler: the cheapest sealed piece, the item in the bag
    ('chore_trade', check_chore_trade, lambda c: True),   # O653: the Material Broker: sell what was gathered
    ('stash_move', check_stash_move, lambda c: True),   # O657: a plain piece dragged onto the stash in the temple and taken out again (Stash / Redeem by the item's place)
    ('dummy_train', check_dummy_train, lambda c: True),   # O657: the exercise weapon (TEST ONLY grant) on the nearest dummy in a protection zone: charges fall, skill tries rise
    ('mount_ride', check_mount_ride, lambda c: True),   # O657: a TEST ONLY mount on and off with the mount button's packet outside a protection zone, the speed
    ('flay_walk', check_flay_walk, lambda c: True),   # O657: the knife on a fresh corpse of the bot's own kills: the Flaying experience rises
    ('angle_walk', check_angle_walk, lambda c: True),   # O657: the rod cast at the nearest fishable water: Fishing tries and Angling experience rise
    ('kill_task_kills', check_kill_task_kills, lambda c: True),   # O657: an accepted kill task hunted on foot: the task counter and the bestiary entry rise
    ('chore_salvage', check_chore_salvage, lambda c: True),   # O653: a rolled piece the bot will not wear, broken down at the bench
    ('boss_copy_walk', check_boss_copy_walk, lambda c: True),   # O652: a copy of a key boss of its own: walk, fight, step off the marks, loot
    ('spell_support', check_spell_support, lambda c: True),   # O655: the support and healing spells of the class cast by their words; the spells only a quest teaches are refused
    ('tales_read', check_tales_read, lambda c: True),   # O655: Archivist Maelis: the list of tales, Read on one, the windows closed
    ('kill_task', check_kill_task, lambda c: True),   # O655: the kill task board: accept an offer, it is active, abandon it
    ('gather_walk', check_gather_walk, lambda c: True),   # O655: a pick or a sickle from the Material Broker, the nearest ready node on foot, the material in the bag
    ('pouch_rules', check_pouch_rules, lambda c: True),   # O655: the Loot Pouch rules window: one rule turned and back
    ('autosell_rules', check_autosell_rules, lambda c: True),   # O655: the Auto Seller window: locked without the store unlock, else the corpse switch turned and back
    ('stash_window', check_stash_window, lambda c: True),   # O655: the stash window: tabs, items, the item search
    ('gamble_reroll', check_gamble_reroll, lambda c: True),   # O655: the Gambler's fresh crates for gold: the count, the money and the stock move
    ('rift_walk', check_rift_walk, lambda c: True),   # O592: the rift on foot, the longest of the open checks: last
    ('ascension_walk', check_ascension_walk, lambda c: True),   # O655: the Oracle's quest on foot: the Calling, the Proof (TEST ONLY credit), the Trial, the Choice and the class lock; changes the class: after every other check
]
KEYS = tuple(k for k, _, _ in CHECKS)


# ------------------------------------------------------------------------------------------------ gear up, level gates, retreat (O658)
# The O656 live run: a bot made at level 100 to 2000 with the kit weapon and nothing else died within seconds of every hard check, so the
# fights, the Trial, the pocket bosses and the rifts SKIPped ("died before a kill") and the level gates fell away with the deaths. A person
# gears up before a hard fight: wears the best piece he owns, buys potions at the Apothecary and a missing basic piece at the Gambler, and
# leaves a fight that goes badly. The bot does the same, before the checks of FIGHT_KEYS:
#   gear_up      wear the best pieces of the backpack (`!tester found`, the chase score); buy health and mana potions at Veyra the Apothecary
#                (on foot, the trade window, the Buy packet) when the backpack holds fewer than POTION_BUY_BELOW; buy a piece for each empty basic
#                slot (helmet, armor, legs, boots) at the Gambler (on foot, its window); wear them. One `gear_up` result per login in the report.
#   gold         the purchases pay from the bank. A bot that cannot pay is topped up by the helper (`!tester gold to N`, TEST ONLY, never a player):
#                every grant is a named fallback of the result and has its own line in the report.
#   level gates  LEVEL_GATES: a check whose content opens above the bot's level says SKIP "level" before it walks or gears up.
#   retreat      retreat_check in the play loops: under RETREAT_AT percent health the bot drinks or casts a heal (CheckIO.heal_now), steps back
#                the way it came and waits until it is over RETREAT_BACK percent (at most RETREAT_WAIT seconds), RETREAT_MAX times a loop.
#                A death still ends the check as a SKIP that says the bot died (and what the gear-up did).
FIGHT_KEYS = frozenset([
    'closed_dungeon', 'dungeon_difficulty', 'weekly_challenge', 'closed_siege', 'closed_guildboss', 'closed_raid',
    'closed_arena_fight', 'closed_pvp_fight', 'closed_battleground_match',
    'rift_walk', 'tower_walk', 'descent_walk', 'trial_walk', 'ascended_walk', 'omen_walk', 'bounty_walk', 'bounty_elite_walk',
    'bounty_boss_walk', 'mainquest_walk', 'nemesis_walk', 'pocket_walk', 'wsmap_walk', 'goblin_walk', 'vael_walk', 'boss_copy_walk',
    'kill_task_kills', 'ascension_walk',
])
# the level each content opens at (a floor: the helper's own `minLevel` answers still apply after it). Read from the configs by
# tester_checks_test.py (`test_level_gates_hold_the_configs`): a number that drifts fails the test, not a live run.
LEVEL_GATES = {
    'closed_dungeon': 150,       # the first base dungeon (bossspawns_config.lua dungeons[1].level)
    'dungeon_difficulty': 150,
    'weekly_challenge': 800,     # weekly_challenge_config.lua minLevel
    'closed_siege': 100,         # siege_config.lua minLevel
    'closed_guildboss': 150,     # guildboss_config.lua minLevel
    'closed_raid': 800,          # raid_config.lua minLevel
    'rift_walk': 100,            # rift_config.lua tiers[1].minLevel
    'tower_walk': 100,           # weeklychest_config.lua activities: the Infinity Tower run minLevel
    'descent_walk': 100,         # descent_config.lua minLevel
    'trial_walk': 100,           # trials_config.lua normal minLevel
    'nemesis_walk': 50,          # nemesis_config.lua minLevel
    'pocket_walk': 150,          # pocketboss_config.lua raid minLevel (the lowest boss a pocket opens)
    'wsmap_walk': 1000,          # waystone_tiers_config.lua tester.minLevel
    'vael_walk': 500,            # the Oath Chamber (trials_config.lua mq minLevel)
    'ascension_walk': 100,       # Chaos.classes.ascension.minLevel
}
GEAR_SLOTS = {1: 'Helmet', 4: 'Armor', 7: 'Legs', 8: 'Boots'}   # CONST_SLOT_* of the basic pieces -> the Gambler's slot name
GEAR_WEAR_MAX = 8            # pieces worn in one gear-up
POTION_WANT = 100            # the stock the helper keeps (SUPPLIES of tester_helper.lua)
POTION_BUY_BELOW = 90        # the bot walks to the Apothecary when it holds fewer health potions than this
POTION_PRICE_CAP = 100       # gold: the health potion of the stock costs 45; a bot never pays more for one
GAMBLE_MIN = 40              # gamble_config.lua minLevel
GEAR_GRANT_CAP = 8000000     # gold the helper may add to the bank in one gear-up (O660: 3M paid two basic pieces at level 1000; four cost 6M)
GEAR_PIECE_CAP = 4000000     # gold for one piece at the Gambler: a dearer piece is left (the bot keeps what it wears; O660: 1.5M left every armor of a level 900+ bot out)
GEAR_RESERVE = 5000          # gold kept in the bank after the purchases
RETREAT_AT = 30              # percent health: under it the bot heals and steps back
RETREAT_BACK = 50            # percent health the bot waits for before it goes on
RETREAT_WAIT = 12.0          # seconds a retreat waits for the health at most
RETREAT_MAX = 6              # retreats of one play loop
RETREAT_TRAIL = 12           # positions of the loop kept to step back along


def level_gate(key, level):
    """the SKIP text when the check's content opens above `level`, else None (nothing is walked, nothing is bought)"""
    need = LEVEL_GATES.get(key)
    if need is not None and int(level or 0) < need:
        return 'level %d: %s opens at level %d (not walked: a person does not walk to a door he cannot open)' % (int(level or 0), key, need)
    return None


def slot_gaps(found):
    """the basic slots {slot: Gambler name} with no worn piece in the `!tester found` answer"""
    worn = {int(w.get('s')) for w in (found or {}).get('worn') or [] if isinstance(w, dict) and w.get('s') is not None}
    return {slot: name for slot, name in GEAR_SLOTS.items() if slot not in worn}


def gear_pieces_for(rows, names, cap=GEAR_PIECE_CAP):
    """from the Gambler's stock the piece to buy for each name of `names` (a set of slot names): the cheapest unsold one under `cap` gold;
    -> [row] by price"""
    out = []
    for name in sorted(names):
        cands = [e for e in rows or [] if isinstance(e, dict) and not e.get('sold') and e.get('sn') == name and 0 < int(e.get('p') or 0) <= cap]
        cands.sort(key=lambda e: (int(e['p']), int(e.get('i') or 0)))
        if cands:
            out.append(cands[0])
    out.sort(key=lambda e: (int(e['p']), int(e.get('i') or 0)))
    return out


def potion_plan(report):
    """(health to buy, mana to buy) from the `!tester bag` answer's `potions`; (0, 0) when the answer has none"""
    p = (report or {}).get('potions') if isinstance(report, dict) else None
    if not isinstance(p, dict):
        return 0, 0
    h, m = int(p.get('health') or 0), int(p.get('mana') or 0)
    return (POTION_WANT - h if h < POTION_BUY_BELOW else 0), (POTION_WANT - m if m < POTION_BUY_BELOW else 0)


def potion_rows(shop):
    """the rows of Veyra's window that are the stock health and mana potion (by name): (health row, mana row)"""
    hp = mp = None
    for i in shop or []:
        n = str(i.get('name') or '').lower()
        if int(i.get('buy') or 0) <= 0:
            continue
        if n == 'health potion':
            hp = i
        elif n == 'mana potion':
            mp = i
    return hp, mp


async def gold_bank(io):
    """the bank balance of `!tester gold`, or None"""
    a = await io.helper('gold', 'gold', HELPER_WAIT)
    return int(a['bank']) if isinstance(a, dict) and not a.get('err') and a.get('bank') is not None else None


async def gold_enough(io, g, need, why):
    """True when the bank holds `need` gold: a bot that is short is topped up by the helper (`!tester gold to N`, TEST ONLY: the named
    fallback of the gear-up, counted in the result and in the report); False when it cannot be had"""
    bank = await gold_bank(io)
    if bank is None:
        g['notes'].append('no answer to !tester gold (old helper file)')
        return False
    if bank >= need:
        return True
    if g['granted'] + (need - bank) > GEAR_GRANT_CAP:
        g['notes'].append('%s: %d gold needed, the bank holds %d and the grant limit of a gear-up is used up' % (why, need, bank))
        return False
    a = await io.helper('gold to %d' % need, 'gold', HELPER_WAIT)
    given = int((a or {}).get('granted') or 0) if isinstance(a, dict) else 0
    if given > 0:
        g['granted'] += given
        g['fallbacks'].append('grant %d gold (%s; the bank held %d)' % (given, why, bank))
    if given <= 0 and not (isinstance(a, dict) and int(a.get('bank') or 0) >= need):
        g['notes'].append('%s: no gold (%s)' % (why, str((a or {}).get('refused') or (a or {}).get('err') or 'no answer')[:60]))
        return False
    return True


async def gear_wear(io, g, refused):
    """wears the best piece of the backpack, again and again until none beats what is worn (a person drags it onto the paper doll; the server's
    class and level rules decide: a piece it keeps in the bag is not worn twice). -> the last `!tester found` answer, None when it gave none"""
    for _ in range(GEAR_WEAR_MAX):
        if not io.alive():
            return None
        a, why = await found_look(io)
        if a is None:
            g['notes'].append(why)
            return None
        p = chase_pick(a)
        if p is None or (p.get('id'), p.get('i')) in refused:
            return a
        await io.wear(p['i'], p['cid'], p['s'])
        await io.sleep(1.2)
        b, _ = await found_look(io)
        status, text = gear_chase_verdict(p, a, b)
        refused.add((p.get('id'), p.get('i')))
        if status == PASS:
            g['worn'] += 1
            g['pieces'].append(chase_kind(p))
        elif status == FAIL:
            g['notes'].append(text)
    return None


async def gear_potions(io, name, g):
    """potions at Veyra the Apothecary: on foot, the trade window, the Buy packet; the backpack count must rise"""
    bag = await io.helper('bag', 'bag', HELPER_WAIT)
    want_h, want_m = potion_plan(bag)
    if not (want_h or want_m):
        if isinstance(bag, dict) and isinstance(bag.get('potions'), dict):
            g['potions'] = 'held (%s health, %s mana)' % (bag['potions'].get('health'), bag['potions'].get('mana'))
        return
    npc = 'Veyra the Apothecary'
    why, falls = await chore_walk(io, name, npc)
    g['fallbacks'].extend(falls)
    if why:
        g['notes'].append('no walk to %s: %s' % (npc, why))
        return
    await npc_talk_begin(io, npc)
    try:
        shop = await io.shop_window(npc)
        hp, mp = potion_rows(shop)
        if not (hp or mp):
            g['notes'].append('%s: no trade window or no potions in it' % npc)
            return
        for row, n, label in ((hp, want_h, 'health'), (mp, want_m, 'mana')):
            if row is None or n <= 0:
                continue
            if int(row['buy']) > POTION_PRICE_CAP:
                g['notes'].append('the %s potion costs %s gold: not bought' % (label, row['buy']))
                continue
            if not await gold_enough(io, g, n * int(row['buy']) + GEAR_RESERVE, 'potions'):
                continue
            await io.buy(row['id'], n)
            g['bought'].append('%d %s potion(s)' % (n, label))
    finally:
        if hasattr(io, 'shop_close'):
            io.shop_close()
        await npc_talk_end(io)
    after = await io.helper('bag', 'bag', HELPER_WAIT)
    if isinstance(after, dict) and isinstance(after.get('potions'), dict) and isinstance(bag, dict) and isinstance(bag.get('potions'), dict):
        g['potions'] = 'health %s -> %s, mana %s -> %s' % (bag['potions'].get('health'), after['potions'].get('health'),
                                                             bag['potions'].get('mana'), after['potions'].get('mana'))


async def gear_pieces(io, name, g, found, level):
    """a piece for each empty basic slot at the Gambler (Mordecai Ashwager): on foot, the window's Buy; wearing it is the next gear_wear"""
    gaps = slot_gaps(found)
    if not gaps:
        return
    if int(level or 0) < GAMBLE_MIN:
        g['notes'].append('level %d: the Gambler opens at level %d' % (int(level or 0), GAMBLE_MIN))
        g['gap_why'].update({n: 'the Gambler opens at level %d' % GAMBLE_MIN for n in gaps.values()})   # O659
        return
    npc = 'Mordecai Ashwager'
    why, falls = await chore_walk(io, name, npc)
    g['fallbacks'].extend(falls)
    if why:
        g['notes'].append('no walk to %s: %s' % (npc, why))
        return
    try:
        reply = await io.request('gamble', 'open', {}, ('state',), ANSWER)
        a = (reply or {}).get('data') if isinstance(reply, dict) else None
        if not isinstance(a, dict):
            g['notes'].append('no state in the Gambler window')
            return
        for n in sorted(set(gaps.values())):   # O659: the slots the stock cannot fill, with the reason
            w = gear_gap_why(a.get('items'), n, level, g.get('cls'))
            if w:
                g['gap_why'][n] = w
        for row in gear_pieces_for(a.get('items'), set(gaps.values()), GEAR_PIECE_CAP):
            if not io.alive():
                break
            if not await gold_enough(io, g, int(row['p']) + GEAR_RESERVE, 'a %s of the Gambler' % row.get('sn')):
                continue
            await io.sleep(GAMBLE_GAP)   # O660: the Gambler's window drops a request that follows another within 300 ms
            bought = await io.request('gamble', 'buy', {'i': row['i'], 'w': a.get('w'), 'id': row.get('id')}, ('state', 'result'), ANSWER)
            await io.sleep(1.0)
            again = await io.request('gamble', 'open', {}, ('state',), ANSWER)
            b = (again or {}).get('data') if isinstance(again, dict) else None
            now = next((e for e in (b or {}).get('items') or [] if e.get('i') == row.get('i')), None) if isinstance(b, dict) else None
            if now is not None and now.get('sold'):
                g['bought'].append('%s for %d gold' % (row.get('sn'), int(row['p'])))
                a = b
            else:
                g['notes'].append('the %s of the Gambler was not sold (%s)' % (row.get('sn'), gamble_refusal(bought, b)))   # O660: the server's own words
    finally:
        await io.request('gamble', 'close', {}, [], ANSWER)


async def heal_rule_ready(io, g):
    """the heal rule of the bot (keep_alive) drinks the stock health potion by its client id from `!tester info`: make sure it is known"""
    bot = getattr(io, 'bot', None)
    have = (((getattr(bot, 'helper', None) or {}).get('info') or {}).get('potions') or {}).get('health') if bot is not None else None
    if not have:
        a = await io.helper('info', 'info', HELPER_WAIT)
        have = ((a or {}).get('potions') or {}).get('health') if isinstance(a, dict) else None
    g['heal'] = 'health potion %s on the heal rule' % have if have else None
    if not have:
        g['notes'].append('the heal rule knows no potion id')


async def gear_up(io, name, cls, level):
    """the gear-up before a hard check: -> the Result 'gear_up' (PASS: what was done, or nothing was needed; SKIP: a step that could not be done,
    with its reason) with the fallbacks (walks by the helper, gold grants) named"""
    key = 'gear_up'
    g = {'worn': 0, 'pieces': [], 'bought': [], 'potions': None, 'granted': 0, 'notes': [], 'fallbacks': [], 'heal': None,
         'cls': cls, 'gap_why': {}, 'after': None}
    refused = set()
    free = await make_room(io, 'gear_up')   # O660: a purchase that finds the backpack full goes to the inbox (gamble.lua deliver), and a piece there is never worn
    if free is not None and free < ROOM_NEED:
        g['notes'].append('the backpack has %d free slot(s): a piece bought now may go to the inbox' % free)
    found = await gear_wear(io, g, refused)
    if io.alive():
        await gear_potions(io, name, g)
    if io.alive():
        await gear_tree(io, g)   # O661: the free passive points on the Defense build, as a person does
    if io.alive():
        await gear_tree_rest(io, g)   # O662: what is left of the points goes on the damage build
    if io.alive() and found is not None:
        found, _ = await found_look(io)
        if found is not None:
            await gear_pieces(io, name, g, found, level)
            if io.alive():
                await gear_weapon(io, name, g, found, level)   # O662: the weapon of the bot's class and level band, from the Gambler
            if io.alive():
                g['after'] = await gear_wear(io, g, refused)
    if io.alive():
        await heal_rule_ready(io, g)
    parts = []
    if g['pieces']:
        parts.append('wore %d piece(s) (%s)' % (g['worn'], ', '.join(g['pieces'][:3])))
    if g['bought']:
        parts.append('bought ' + ', '.join(g['bought']))
    if g['potions']:
        parts.append('potions ' + g['potions'])
    if g['heal']:
        parts.append(g['heal'])
    if g.get('tree'):
        parts.append(g['tree'])
    if g.get('tree_rest'):
        parts.append(g['tree_rest'])
    if g.get('weapon'):
        parts.append(g['weapon'])
    if not parts:
        parts.append('nothing to wear or buy')
    text = '; '.join(parts)
    if g['granted']:
        text += '; TEST ONLY gold grant %d' % g['granted']
    gap = gear_gap_text(g, g['after'])   # O659: the slots no piece fits, named; no gear is ever granted
    if gap:
        text += '; ' + gap
    if g['notes']:
        text += '; open: ' + '; '.join(dict.fromkeys(g['notes']))[:200]
    status = SKIP if g['notes'] and not (g['worn'] or g['bought']) else PASS
    return Result(key, name, cls, status, text, g['fallbacks'])


def retreat_step(trail, pos, goal=None):
    """one walk step (dx, dy) away from the danger: back toward a position of the trail a few looks ago, else away from the guide's goal; None
    when neither says"""
    if not isinstance(pos, dict):
        return None
    old = next((t for t in reversed(trail[:-1]) if (t[0], t[1]) != (pos['x'], pos['y'])), None) if len(trail) >= 2 else None
    dx = dy = 0
    if old is not None:
        dx, dy = old[0] - pos['x'], old[1] - pos['y']
    elif isinstance(goal, dict):
        dx, dy = pos['x'] - goal['x'], pos['y'] - goal['y']
    if abs(dx) >= abs(dy) and dx:
        return (1 if dx > 0 else -1, 0)
    if dy:
        return (0, 1 if dy > 0 else -1)
    return None


async def retreat_check(io, r, s, trace, g=None):
    """O658: under RETREAT_AT percent health the bot drinks or casts a heal, steps back and waits for RETREAT_BACK percent; -> the seconds
    spent (0.0 when it did not retreat). The trail of looks lives in `r`; a loop retreats at most RETREAT_MAX times"""
    pos = s.get('pos') if isinstance(s, dict) else None
    trail = r.setdefault('trail', [])
    if isinstance(pos, dict) and 'x' in pos and 'y' in pos:
        if not trail or (trail[-1][0], trail[-1][1]) != (pos['x'], pos['y']):
            trail.append((pos['x'], pos['y']))
            del trail[:-RETREAT_TRAIL]
    hp = getattr(io, 'health', None)
    heal = getattr(io, 'heal_now', None)
    if hp is None or heal is None or hp >= retreat_at() or not io.alive() or trace.get('retreats', 0) >= RETREAT_MAX:
        return 0.0
    trace['retreats'] = trace.get('retreats', 0) + 1
    io.retreats = getattr(io, 'retreats', 0) + 1
    spent = 0.0
    how = await heal()
    step = retreat_step(trail, pos, (g or {}).get('goal'))
    if step is not None:
        await raid_walk(io, r, step)
        trace['steps'] = trace.get('steps', 0) + 1
        await io.sleep(RAID_STEP)
        spent += RAID_STEP
    trace.setdefault('retreat_heals', []).append(how or 'none')
    while io.alive() and spent < RETREAT_WAIT and (getattr(io, 'health', None) or 100) < RETREAT_BACK:
        await io.sleep(1.0)
        spent += 1.0
        await heal()
    return max(spent, 1.0)


class CheckRun:
    """the checks of one bot; results go on after a death (a check cut off by it is done again) like the keystone scenario"""

    def __init__(self, name, cls, level, only=None, closed=False, gear=True):
        self.name, self.cls, self.level = name, cls, level
        self.gear = gear       # O658: gear up before the checks of FIGHT_KEYS (once per login)
        self.geared = False    # the creature id of the login that was geared up (None for an io with no bot)
        self.only = set(only) if only else None
        self.table = CHECKS + (CLOSED_CHECKS if closed else [])   # the closed-mode checks only in a --closed run (O582)
        self.done = set()
        self.results = []
        self.resets = []

    def todo(self):
        return [k for k, _, ok in self.table if ok(self.cls) and k not in self.done and (not self.only or k in self.only)]

    async def run(self, io):
        """True when no check failed; stops early when the bot is gone"""
        for key, fn, ok in self.table:
            if key in self.done or not ok(self.cls) or (self.only and key not in self.only):
                continue
            if not io.alive():
                return False
            lvl = int(getattr(getattr(io, 'bot', None), 'level', 0) or 0) or self.level   # O658: the level now (a death takes some)
            gated = level_gate(key, lvl)
            if gated:   # O658: the content opens above the bot's level: no walk, no gear-up, no death to find it out
                self.results.append(Result(key, self.name, self.cls, SKIP, gated))
                self.done.add(key)
                continue
            if self.gear and key in FIGHT_KEYS and self.gear_due(io):
                await self.gear_once(io, lvl)
                if not io.alive():
                    return False
            await settle_in_town(io, key)   # O660: the bot waits in the temple between the checks
            if key in ROOM_KEYS:   # O660: room in the backpack before the helper hands items out
                await make_room(io, key)
            try:
                r = await fn(io, self.name, self.cls, lvl)
            except Exception as e:  # noqa: BLE001 - a check that breaks is a result, not a crash of the run
                r = Result(key, self.name, self.cls, SKIP, 'the check broke: %s' % e)
            if r.status == SKIP and key in FIGHT_KEYS and getattr(io, 'retreats', 0) and 'retreated home' not in r.detail:
                r.detail += ' (the bot retreated %d time(s) to heal)' % io.retreats
            await npc_talk_end(io, bye=False)   # O656: a check that ended with the NPC's focus held lets go of it
            if not io.alive() and r.status != PASS:
                give_up = cut_verdict(self, key, io, r)   # O660: the same check killed the bot CUT_MAX times: SKIP with the count, go on
                if give_up is not None:
                    self.results.append(give_up)
                    self.done.add(key)
                return False   # cut off by the bot's own death: not a result, done again after the next login
            self.results.append(r)
            self.done.add(key)
        return not any(r.status == FAIL for r in self.results)

    def gear_due(self, io):
        """O658: true until this login (the creature id of the bot) has been geared up"""
        return not (self.geared is not False and self.geared == getattr(getattr(io, 'bot', None), 'cid', None))

    async def gear_once(self, io, level):
        """O658: the gear-up of this login, its result in the list (a gear-up cut off by the bot's death is done again after the next login)"""
        try:
            r = await gear_up(io, self.name, self.cls, level)
        except Exception as e:  # noqa: BLE001 - a gear-up that breaks is a result, not a crash of the run
            r = Result('gear_up', self.name, self.cls, SKIP, 'the gear-up broke: %s' % e)
        if io.alive():
            self.geared = getattr(getattr(io, 'bot', None), 'cid', None)
            self.results.append(r)

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
    tele, grants = {}, {}
    for r in results:
        for f in r.get('fallbacks') or []:
            into = grants if f.startswith('grant ') else tele   # O658: a gold grant of the gear-up is not a teleport
            into[(r['check'], f)] = into.get((r['check'], f), 0) + 1
    if grants:
        L.append('  gold granted by the helper (TEST ONLY fallback of gear_up: the bank was short): %d grant(s)' % sum(grants.values()))
        for (key, f), n in sorted(grants.items()):
            L.append('    %-18s %3dx %s' % (key, n, f[:100]))
    if tele:
        L.append('  helper teleports in place of walking: %d (a person walks; the path failed or did not arrive)' % sum(tele.values()))
        for (key, f), n in sorted(tele.items()):
            L.append('    %-18s %3dx %s' % (key, n, f[:100]))
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


# ------------------------------------------------------------------------------------------------ retreat in every fight loop, home, empty slots (O659)
# O658 gave four play loops the retreat (a bot under 30 % health heals and steps back). O659 adds it to the rift loop, the dungeon loops
# (closed_dungeon, dungeon_difficulty, weekly_challenge) and the raid loop, and a second step: a bot that must retreat a second time in one loop
# goes home like a person who has had enough. The way home is the one the journey takes (tester_journey.py leave): the Town Portal spell
# (the portal beside the bot is walked into). The server refuses that spell inside a rift, a dungeon and an instance (townportal_core.lua), so in
# these three contents the cast is the probe and the content's own door is the way out: the raid has a Leave button (`raid leave`, refused in the
# middle of a boss fight); a rift and a dungeon have none (the exit teleport comes after the boss), so the content holds the bot: the answer is
# named in the result and the plain retreat goes on. A bot that got out restocks with the gear-up of O658 (wear, potions, a piece for an empty
# slot; a gold grant is a named TEST ONLY fallback) and walks back when the content has a way back (`back` of HOME_RULES: none of the three has
# one: a run the bot left is closed for it); else the check ends as SKIP "retreated home" with the count. Nothing is granted but gold for the
# purchases, never a piece of gear.
HOME_AT = 2                 # the retreat of one loop that goes home (the second)
HOME_MAX = 2                # trips home of one loop (a content with a way back)
HOME_WORDS = 'ash domh'     # the Town Portal words (spells_chaos.xml), every class from level 1 (tester_journey.TOWN_WORDS)
HOME_CAST = 3.6             # seconds of the channel (tester_journey.PORTAL_CAST)
HOME_LOOKS = 3              # looks at the portal beside the bot after the cast


async def home_look_rift(io, r):
    return await hcmd(io, r, 'rift state', 'rift')


async def home_leave_raid(io, r):
    """the raid's Leave button (a person's way out): (True, None) when the server ended the bot's raid, else (False, its text)"""
    reply = await (io.request('raid', 'leave', {}, ['end', 'msg'], ANSWER) if r['lead']
                   else io.request_of(r['name'], 'raid', 'leave', {}, ['end', 'msg'], ANSWER))
    if isinstance(reply, dict) and reply.get('action') == 'end':
        return True, None
    text = ((reply or {}).get('data') or {}).get('text') if isinstance(reply, dict) else None
    return False, str(text or 'no answer to the Leave button')[:60]


# what each content allows: `look` the state ({inside}), `leave` the content's own door (None when it has none), `back` the walk back into the
# content after a trip home (None: the run the bot left is closed for it), `why` the reason for the README and the result
HOME_RULES = {
    'rift_walk': {'look': home_look_rift, 'leave': None, 'back': None,
                  'why': 'a rift has no Leave button and the Town Portal is refused inside; a run left is closed and needs a new key'},
    'closed_dungeon': {'look': dungeon_look, 'leave': None, 'back': None,
                       'why': 'a dungeon has no Leave button and the Town Portal is refused inside; the exit teleport comes after the boss'},
    'closed_raid': {'look': raid_look, 'leave': home_leave_raid, 'back': None,
                    'why': 'the raid has a Leave button (not in a boss fight); a raid the bot left is its own run no more'},
}
HOME_RULES['dungeon_difficulty'] = HOME_RULES['weekly_challenge'] = HOME_RULES['closed_dungeon']


def home_rule(key, name, cls, level):
    """the way home of content `key` for this bot, or None (no retreat home: only the plain retreat)"""
    rule = HOME_RULES.get(key)
    if rule is None:
        return None
    return dict(rule, key=key, name=name, cls=cls, level=level)


async def home_inside(home, io, r):
    """True / False from the content's state, None when it gave no answer"""
    s = await home['look'](io, r)
    return bool(s.get('inside')) if isinstance(s, dict) else None


async def home_portal(io, r, s, home):
    """the Town Portal: cast, walk into the portal beside the bot; -> (out, seconds, why): out is True when the bot left the content"""
    spent = 0.0
    await io.say(HOME_WORDS)
    await io.sleep(HOME_CAST)
    spent += HOME_CAST
    for _ in range(HOME_LOOKS):
        a = await io.helper('journey', 'journey', ANSWER)
        portal = a.get('portal') if isinstance(a, dict) else None
        if not isinstance(portal, dict):
            return False, spent, 'the Town Portal opened no portal (the content holds the bot)'
        for step in raid_plan((a or {}).get('pos') or (s or {}).get('pos'), portal, 8):
            await raid_walk(io, r, step)
            await io.sleep(RAID_STEP)
            spent += RAID_STEP
        await io.sleep(1.0)
        spent += 1.0
        if await home_inside(home, io, r) is False:
            return True, spent, None
    return False, spent, 'the portal beside the bot did not take it'


async def retreat_home(io, r, s, trace, home):
    """O659: the second retreat of a loop goes home. -> the seconds spent (0.0 when nothing was tried); sets trace['gone'] when the bot is out
    and stays out, trace['home_log'] (one row per trip: how, the gear-up text, whether it came back), trace['home_refused'] (why not)"""
    heal = getattr(io, 'heal_now', None)
    if heal is not None:
        await heal()   # a person heals before he casts a channel of 3 seconds
    out, spent, why = await home_portal(io, r, s, home)
    how = 'the Town Portal'
    if not out and home.get('leave') is not None and io.alive():
        out, text = await home['leave'](io, r)
        how = "the raid's Leave button"
        why = None if out else '%s; %s' % (why, text)
    if not out:
        trace['home_refused'] = why or 'no way out'
        return spent
    trace['retreats'] = trace.get('retreats', 0) + 1
    io.retreats = getattr(io, 'retreats', 0) + 1
    row = {'how': how, 'gear': None, 'back': None}
    trace.setdefault('home_log', []).append(row)
    if io.alive():
        lvl = int(getattr(getattr(io, 'bot', None), 'level', 0) or 0) or int(home.get('level') or 0)
        try:
            res = await gear_up(io, home['name'], home['cls'], lvl)
            row['gear'] = '%s: %s' % (res.status, res.detail[:160])
            if isinstance(trace.get('fallbacks'), list):
                trace['fallbacks'].extend(res.fallbacks or [])
        except Exception as e:  # noqa: BLE001 - a restock that breaks is a line of the result, not a crash
            row['gear'] = 'the gear-up broke: %s' % e
    if io.alive() and home.get('back') is not None:
        row['back'] = bool(await home['back'](io, r, home, trace))
    trace['gone'] = not row['back']
    return spent + 1.0


async def retreat_or_home(io, r, s, trace, g=None, home=None):
    """O659: the retreat of a fight loop: the plain one (retreat_check) for the first, the way home for the second; a content that holds the
    bot is asked once a loop, then the plain retreat goes on. -> the seconds spent (0.0 when the bot did not retreat)"""
    hp = getattr(io, 'health', None)
    spent = 0.0
    if (home is not None and r.get('lead') and hp is not None and hp < retreat_at() and io.alive() and trace.get('retreats', 0) >= HOME_AT - 1
            and not trace.get('home_refused') and len(trace.get('home_log') or []) < HOME_MAX):
        trips = len(trace.get('home_log') or [])
        spent = await retreat_home(io, r, s, trace, home)
        if len(trace.get('home_log') or []) > trips:   # the bot was out (and came back, or stays out): the look of this round is stale
            return spent
    return spent + await retreat_check(io, r, s, trace, g or None)


def home_verdict(trace, status, text):
    """O659: the result of a loop that went home or was held: a bot that is out and stays out ends as SKIP "retreated home" with the count (a FAIL
    stays); a bot that came back says so; a content that held it says so on a SKIP"""
    log = trace.get('home_log') or []
    n = trace.get('retreats', 0)
    if trace.get('gone') and log and status != FAIL:
        return SKIP, 'retreated home (%d retreat(s) under %d %% health, out by %s; restock: %s; the content allows no return)' % (
            n, retreat_at(), log[-1]['how'], log[-1]['gear'] or 'none')
    if log and status != FAIL:
        text += '; went home %d time(s) and came back (%d retreat(s))' % (len(log), n)
    if trace.get('home_refused') and status == SKIP:
        text += ' (the bot tried to go home after %d retreat(s): %s)' % (n, trace['home_refused'][:100])
    return status, text


def gear_gap_why(rows, name, level, cls, cap=GEAR_PIECE_CAP):
    """O659: why no piece of the Gambler's stock can fill the empty slot `name` for this class and level, or None when one can. The window lists
    only what the character may wear (class and level rule), so an empty list is the gap; nothing is granted"""
    mine = [e for e in rows or [] if isinstance(e, dict) and e.get('sn') == name]
    if not mine:
        return "no %s in the Gambler's stock for a level %d %s" % (name, int(level or 0), cls or 'bot')
    free = [e for e in mine if not e.get('sold')]
    if not free:
        return 'every %s of the stock is sold' % name
    cheapest = min(int(e.get('p') or 0) for e in free)
    if cheapest > cap:
        return 'the cheapest %s costs %d gold (limit %d)' % (name, cheapest, cap)
    return None


def gear_gap_text(g, final):
    """O659: the empty basic slots left after the gear-up, with the reason known for each: -> the text, or None when none is empty.
    `final` is the last `!tester found` answer (None: unknown, nothing is said)"""
    if final is None:
        return None
    left = slot_gaps(final)
    if not left:
        return None
    why = g.get('gap_why') or {}
    return '%d basic slot(s) stay empty: %s' % (len(left), ', '.join('%s (%s)' % (n, why.get(n) or 'not bought, see open') for n in sorted(left.values())))


if __name__ == '__main__':
    print(json.dumps({'checks': list(KEYS)}))


# ------------------------------------------------------------------------------------------------ live run fixes (O660)
# The first live run with the gear-up (README step 19) showed what a person would never do: the checks ran at the hunt spot of a bot with
# no gear (a pack killed it within seconds, 511 deaths in 515 logins), the backpack filled with the plain items the helper hands out for
# each retry ("no room for the item" in 60 checks), and a refused purchase was read as "the money did not fall".
#   gamble_refused / gamble_refusal   the server's own words of a refused Gambler purchase (the `result` of the window)
#   make_room                         before a check that is given items (or whose reward needs the bag), the bot clears the bag as a person does:
#                                     sell at the Loot Buyer, wear what is better, drop junk (`Bot.do_keep`), at most ROOM_ROUNDS times
ROOM_KEYS = frozenset([
    'craft_orbs', 'craft_whetstone', 'craft_sockets', 'craft_gems', 'craft_supports', 'craft_charms', 'craft_cards', 'craft_found',
    'stash_move', 'dummy_train', 'ascended_walk', 'omen_walk', 'chore_gamble', 'daily_claim', 'chore_salvage', 'gear_chase', 'angle_walk', 'mount_ride',
    'gear_up',   # not a check of the list: gear_up asks for the room itself, before it buys
])
ROOM_NEED = 4       # free backpack slots a check of ROOM_KEYS wants before it asks the helper for items
ROOM_ROUNDS = 2     # keep rounds (sell, wear, drop) the bot makes to get them


def gamble_refused(reply):
    """true when the Gambler's `result` message of a buy says ok = false"""
    d = (reply or {}).get('data') if isinstance(reply, dict) else None
    return isinstance(d, dict) and d.get('ok') is False


def gamble_refusal(reply, state):
    """the words of a refused purchase: the server's text, else what the window state shows"""
    d = (reply or {}).get('data') if isinstance(reply, dict) else None
    if isinstance(d, dict) and d.get('text'):
        return 'refused: %s' % str(d.get('text'))[:80]
    if reply is None:
        return 'no answer' if state is None else 'no answer to the buy, the stock row is not marked sold'
    return 'refused'


def bag_free(report):
    """free backpack slots from a `!tester bag` answer; None when it has no size"""
    if not isinstance(report, dict) or not report.get('size'):
        return None
    return int(report.get('size') or 0) - int(report.get('used') or 0)


async def make_room(io, key):
    """O660: before a check of ROOM_KEYS the bot clears its backpack like a person (`Bot.do_keep`: the Loot Buyer, a better piece worn, junk
    dropped) until ROOM_NEED slots are free, at most ROOM_ROUNDS rounds; -> the free slots at the end (None: no bag report, nothing to do).
    A bag it cannot clear is left to the check, which says SKIP "no room"."""
    if key not in ROOM_KEYS or not io.alive():
        return None
    keep = getattr(getattr(io, 'bot', None), 'do_keep', None)
    free = None
    for n in range(ROOM_ROUNDS + 1):
        rep = await io.helper('bag', 'bag', HELPER_WAIT)
        free = bag_free(rep)
        if free is None or free >= ROOM_NEED or n >= ROOM_ROUNDS or keep is None or not io.alive():
            break
        await keep(getattr(io, 'clock', None))
    return free


async def settle_in_town(io, key):
    """O660: between two checks the bot waits in the temple (a protection zone), the way a person waits for the next errand; the checks that
    need the hunt ask for it themselves. Nothing for an io with no `go`"""
    go = getattr(io, 'go', None)
    if go is None or not io.alive() or key in FIGHT_KEYS:
        return False
    return bool(await go('town'))


def no_room_said(io):
    """true when one of the last server lines the bot read says the backpack or the capacity could not take something"""
    lines = getattr(getattr(io, 'bot', None), 'recent', None) or []
    return any(('room or capacity' in str(l)) or ('enough room' in str(l)) or ('Your backpack is full' in str(l)) for l in list(lines)[-8:])


GAMBLE_GAP = 0.4          # seconds between two requests to the Gambler's window (gamble_config.lua requestMs = 300: the next one is dropped)
HIDEOUT_EDIT_GAP = 0.3    # seconds between two edits of the hideout window (hideout_config.lua requestMs.edit = 250 ms; a faster one is dropped)
HIDEOUT_LIST_GAP = 1.1    # seconds between two `get` / `open` of it (requestMs.list = 1000 ms)
SUPPORT_TRIES = 6         # spells the rune of the helper is tried on (it fits some by their shape only)
SUPPORT_GAP = 0.5         # seconds between two tries (the window answers a request every few hundred ms)
CUT_MAX = 3         # deaths inside one check before it is given up (SKIP with the count): a person does not walk into the same pack for ever


def cut_verdict(run, key, io, r):
    """O660: a check the bot's death cut off is done again after the next login; the CUT_MAX-th death in the same check ends it: -> the SKIP
    Result (what it was doing, the deaths, the level now), else None. The counts live on the CheckRun"""
    cuts = run.__dict__.setdefault('cuts', {})
    cuts[key] = cuts.get(key, 0) + 1
    if cuts[key] < CUT_MAX:
        return None
    lvl = int(getattr(getattr(io, 'bot', None), 'level', 0) or 0) or run.level
    why = str(getattr(r, 'detail', '') or '')[:100]
    return Result(key, run.name, run.cls, SKIP, 'the bot died %d times in this check (level %d, %s)%s' % (
        cuts[key], lvl, 'geared up' if getattr(run, 'geared', False) not in (False, None) else 'no gear-up', ('; last: ' + why) if why else ''))


def upheaval_count_only(orb, before, after, problems):
    """O660: the Orb of Upheaval rolls the rarity's own count of modifiers again (data/lib/chaos_crafting.lua C.forge: M.modCount(rarity)): an item the Orb
    of Grafting had filled up loses the extra one. The rarity stays and at least one modifier is there. The check's old rule ("a reroll keeps both")
    failed on every run; the description of the orb ("rerolls every modifier that is not bound") and the comment of C.upheave ("an extra slot stays")
    do not agree with the code: a question for the owner (README step 19), not a bug of the bot. True when that is the only problem"""
    if orb != 'chaos' or not problems or any('a reroll keeps both' not in p and 'tooltip' not in p for p in problems):
        return False
    nb, na = len(before.get('mods') or []), len(after.get('mods') or [])
    return after.get('rarity') == before.get('rarity') and 1 <= na < nb


def upheaval_note(before, after):
    return 'Upheaval rolled the rarity\'s own count: modifiers %d -> %d, the Grafting extra is lost (owner question)' % (
        len(before.get('mods') or []), len(after.get('mods') or []))


def sock_names(st):
    """the gems the bench lists in an item's sockets: 'name, name' or 'none' (a diagnostic of the failure text)"""
    socks = (st or {}).get('sockets') if isinstance(st, dict) else None
    rows = (socks or {}).get('list') if isinstance(socks, dict) else None
    names = [str(g.get('name') or g.get('id') or sorted(g)[:3]) if isinstance(g, dict) else repr(g)[:30] for g in (rows or [])]   # a row that is no object is shown as it is
    return ', '.join(names[:3]) or 'none'


def recent_text(io, n=3):
    """the last `n` server text lines the bot read, joined (a diagnostic for a failure text); '' for an io with no bot"""
    lines = getattr(getattr(io, 'bot', None), 'recent', None) or []
    return ' | '.join(str(l)[:80] for l in list(lines)[-n:])


def spell_runes(s):
    """the runes inside a spell of the Supports window (`runes`: one row per socketed rune)"""
    return len((s or {}).get('runes') or [])


def spell_has_room(s):
    """true when a spell of the Supports window has a free open socket: `count` is the number of sockets the spell has open for the character's
    level (supports.lua spellView), `runes` what sits in them. O660: the checks read `count` as the runes inside and compared it to `max`: a spell
    with all its open sockets full still looked free, and a rune that went in did not move the count the check watched"""
    return spell_runes(s) < int((s or {}).get('count') or 0)


def slot_after_use(used, item, count):
    """O660: the backpack slot of `item` after one unit of the stack `used` was used on it: a stack of one leaves its slot, so everything behind
    it moves one slot forward. The live run read the gem's socket from the old slot (the bench said "no sockets" there) and FAILed craft_gems on
    every bot. -> a copy of item with the new index"""
    out = dict(item)
    if int(count or 1) <= 1 and int(used.get('index', 0)) < int(item.get('index', 0)):
        out['index'] = int(item['index']) - 1
        out['path'] = str(out['index'])
    return out


# ------------------------------------------------------------------------------------------------ the passive tree, spent (O661)
# A person who dies in a pack of his level opens the passive tree window and presses Auto build, Defense. The bots never did: a character made
# at level 1400 held its points and had 0 resistance to every element (the death recap: `res r 0`, 12 hits in 1.5 s), while the survival model
# (survival_model.py) reads the tank role of the tree. The gear-up spends the free points on the Defense focus build (`autobuildApply`, mode
# `add`: free, takes nothing back, a build is cut to the points the character owns).
TREE_BUILD = 'focus_defense'
TREE_DONE = ('autobuildApplied', 'autobuildError')


def tree_build_text(ans, build=TREE_BUILD):
    """-> (done, text) from the answer of autobuildApply: done is True when nodes were taken, text names the server's words"""
    if not isinstance(ans, dict):
        return False, 'passive tree: no answer'
    d = ans.get('data') if isinstance(ans.get('data'), dict) else {}
    if ans.get('action') == 'autobuildApplied':
        return True, 'passive tree %s: %s' % (build, str(d.get('message') or 'applied')[:80])
    return False, 'passive tree %s: %s' % (build, str(d.get('message') or 'refused')[:80])


async def gear_tree(io, g, build=TREE_BUILD):
    """spend the free passive points on the Defense build once per gear-up; the result text goes in g['tree'], a refusal in g['notes'] only when it is
    not "nothing would change" (no free point is not a fault)"""
    ans = await io.request('passivetree', 'autobuildApply', {'build': build, 'mode': 'add', 'cost': 0}, TREE_DONE, ANSWER)
    done, text = tree_build_text(ans, build)
    g['tree'] = text if done else None
    if not done and 'Nothing would change' not in text and 'no answer' not in text:
        g['notes'].append(text)
    return done


# ------------------------------------------------------------------------------------------------ the rift tier a person picks (O661)
# The rift key the helper gives is of the highest tier the level OPENS (rift_config.lua `tiers` minLevel), and the game warns a solo player below
# the RECOMMENDED level of that tier (`warn.levels`: the guardian's biggest hit stays under 60 % of the pool from there). A level 700 character
# opens tier 8 and is told to be 760. A person reads the warning and takes a lower key; the bot does the same: the highest tier whose
# recommended level it has reached, tier 1 when none.
RIFT_WARN_LEVELS = (180, 240, 290, 420, 520, 640, 740, 760, 860, 990, 990, 990, 990, 1000, 1025)


def rift_tier_for(level):
    """-> the highest tier whose recommended solo level (RIFT_WARN_LEVELS) is at most `level`; 1 when the level is below all of them"""
    try:
        lv = int(level)
    except (TypeError, ValueError):
        return None
    tier = 1
    for t, need in enumerate(RIFT_WARN_LEVELS, 1):
        if lv >= need:
            tier = t
    return tier


def rift_key_command(level):
    """the helper command for the rift key: `rift key N` for the tier the level warning allows, the plain `rift key` when the level is unknown"""
    tier = rift_tier_for(level)
    return 'rift key' if tier is None else 'rift key %d' % tier


# ------------------------------------------------------------------------------------------------ a dungeon queue out of a fight (O661)
# O660 left closed_dungeon at 1 of 10: the queue refused 9 bots. The server's words (carried by the SKIP since O659) were "You cannot enter a
# dungeon while you are in a fight." (dungeons.lua: the run teleports from wherever the player stands, so a fight cannot be left by queueing; Chaos.inCombat:
# a pz lock, or the fight condition outside a protection zone). The bots come to the entrance straight from a hunt, a pocket or a trial. A person
# waits at the door until the fight is over and asks again; the bot does the same: the refusal is asked again every DUNGEON_CALM_GAP seconds until it
# says something else, at most DUNGEON_CALM_WAIT (the condition lasts 60 s).
DUNGEON_CALM_WAIT = 75.0
DUNGEON_CALM_GAP = 5.0
DUNGEON_CALM_TEMPLE = 10.0   # seconds of refusals before the bot walks back to the temple (a protection zone) and asks from there
IN_A_FIGHT = 'while you are in a fight'
IN_THE_BOX = 'from inside the dungeon'   # O662: dungeons.lua inBox: the entrance tile the helper's `enter dungeon` leaves the bot on


def queue_refusal(reply):
    """-> the server's refusal text of a dungeon queue answer ('' when the bot joined, or there is no answer)"""
    d = (reply or {}).get('data') if isinstance(reply, dict) else None
    if isinstance(d, dict) and d.get('joined') is False:
        return str(d.get('text') or d.get('why') or '')
    return ''


async def queue_dungeon_calm(io, r, data):
    """the dungeon queue request of the squad member `r`; a refusal because the bot is in a fight is asked again after a pause (the bot stands still).
    -> (reply, waited seconds)"""
    waited, at_temple = 0.0, False
    while True:
        reply = await (io.request('dungeons', 'queue', data, ['queue'], ANSWER) if r['lead']
                       else io.request_of(r['name'], 'dungeons', 'queue', data, ['queue'], ANSWER))
        # the queue answer is {id, joined: false}: the words come as the cancel message of the server (dungeons.lua), the last lines the bot read
        said = queue_refusal(reply) or (recent_text(io, 3) if isinstance(reply, dict) and (reply.get('data') or {}).get('joined') is False else '')
        if IN_THE_BOX in said and not at_temple and io.alive():   # O662: the helper put the bot inside the dungeon's own box: leave it, ask from the temple
            at_temple = True
            await walk_to_place(io, r, 'temple')
            continue
        if (IN_A_FIGHT not in said and IN_THE_BOX not in said) or waited >= DUNGEON_CALM_WAIT or not io.alive():
            return reply, waited
        if not at_temple and waited >= DUNGEON_CALM_TEMPLE:
            # the bot at the door goes on fighting what is near it (its rotation, the helper's target): the fight condition never runs out there. A person
            # steps back into the temple, where a fight does not count (Chaos.inCombat: a protection zone), and asks from there
            at_temple = True
            await walk_to_place(io, r, 'temple')
        await io.sleep(DUNGEON_CALM_GAP)
        waited += DUNGEON_CALM_GAP


# ------------------------------------------------------------------------------------------------ the pocket boss of the bot's own level (O661)
def pocket_unfit(pick, level):
    """O661: the SKIP text when the pocket the helper sorted first has a boss above the bot's level (`bl`: the level the boss is spawned with; the
    helper puts the bosses at or under the level first, so this means none fits), else None. A pocket of the raid category opens at level 150 whatever
    the boss: Ul'thazmor (level 2400) carried a level 600 bot out by a lethal hit within 10 s, the boss at 99 %"""
    try:
        bl, lv = int(pick.get('bl')), int(level)
    except (TypeError, ValueError, AttributeError):
        return None
    if bl > lv:
        return 'no pocket boss at or under level %d is open today (the lowest is %s, level %d): a person does not walk into it' % (lv, pick.get('name'), bl)
    return None


# ------------------------------------------------------------------------------------------------ the way to a bounty hunt (O661)
# O660: the contract's hunt is about 1300 tiles from the temple (`!tester bounty state`: mark at x 33007, y 33360, the temple at x 32957, y 32076): the
# engine's path search is bounded ("no path"), the bot walked 0 steps in 480 s and the loop had no jump. A hunt of the map is reached through the
# temple's great teleport, the hall and the hunt's own teleport (the levelling journey does exactly that). The bounty loop does the same now: when the
# guide's goal is far, the bot goes by the journey's legs to the hunt whose arrival is nearest to the goal (`!tester journey near X Y Z`, the hunts the
# level may enter), the helper's jump only as the journey's own counted fallback; a hunt no teleport leads to is a SKIP with the reason.
BOUNTY_NEAR = 150          # tiles: a goal farther than this is no walk on foot (the engine path search is bounded)
BOUNTY_TRAVEL_BUDGET = 240.0   # seconds the legs to the hunt may take
BOUNTY_TRAVEL_MAX = 120    # tiles from the hunt's arrival (or a waypoint) to the goal that are walked on foot (O662: 25 before; the engine path search covers BOUNTY_NEAR)


def bounty_far(pos, goal):
    """True when the goal is too far for a walk on foot (the larger axis, or another floor with a long way: > BOUNTY_NEAR)"""
    if not (isinstance(pos, dict) and isinstance(goal, dict)):
        return False
    try:
        return max(abs(int(pos['x']) - int(goal['x'])), abs(int(pos['y']) - int(goal['y']))) > BOUNTY_NEAR
    except (KeyError, TypeError, ValueError):
        return False


def travel_command(goal):
    """-> `journey near X Y Z` for the goal {x, y, z}"""
    return 'journey near %d %d %d' % (int(goal['x']), int(goal['y']), int(goal['z']))


class _Clocked:
    """an io with a clock (`now`), for the journey's legs inside a check: everything else is the check's own io"""

    def __init__(self, io):
        self._io = io

    def now(self):
        return time.monotonic()

    def __getattr__(self, name):
        return getattr(self._io, name)


async def bounty_travel_leg(io, r, goal, trace, fallbacks):
    """the journey's legs from where the bot stands to the hunt nearest to `goal`: the temple first (on foot, the helper's teleport is a counted
    fallback), then the temple teleport, the hall and the hunt's teleport. Sets trace['travel'] to 'foot' (arrived) or 'no way' (trace['no_way'] says why)
    -> seconds spent"""
    import tester_journey as TJ   # lazily: tester_journey imports this module
    t0 = time.monotonic()
    cio = _Clocked(io)
    near = (int(goal['x']), int(goal['y']), int(goal['z']))

    class Travel(TJ.Journey):
        async def look(self, io_):
            s = await io_.helper(travel_command(goal), 'journey', TJ.ANSWER)
            if not isinstance(s, dict) or s.get('err') or TJ.pos_of(s.get('pos')) is None:
                self.misses += 1
                if self.misses >= TJ.MISSES:
                    self.note('no answer of the helper to `journey near`: %s' % ((s or {}).get('err', 'none') if isinstance(s, dict) else 'none'))
                    return False
                await io_.sleep(TJ.LOOK)
                return None
            self.misses = 0
            now = io_.now()
            self.seen(now)
            self.arrive(s, now)
            return s

    j = Travel(r['name'], 'bounty', int(trace.get('level') or 0))
    trace['travel'] = None
    while io.alive() and time.monotonic() - t0 < BOUNTY_TRAVEL_BUDGET:
        s = await j.look(cio)
        if s is False:
            trace['travel'], trace['no_way'] = 'no way', 'the helper gave no answer to `journey near` (an old helper file)'
            break
        if s is None:
            continue
        pick = s.get('pick') if isinstance(s.get('pick'), dict) else None
        if pick is None or not pick.get('t'):
            trace['travel'], trace['no_way'] = 'no way', 'no hunt of the teleport room is open to level %s' % trace.get('level')
            break
        arrival = pick.get('a')
        if isinstance(arrival, dict) and max(abs(arrival['x'] - near[0]), abs(arrival['y'] - near[1])) > BOUNTY_TRAVEL_MAX and not j.hunt:
            trace['travel'], trace['no_way'] = 'no way', 'no hunt teleport leads to (%d, %d): the nearest, %s, arrives %d tiles away' % (
                near[0], near[1], pick.get('n'), max(abs(arrival['x'] - near[0]), abs(arrival['y'] - near[1])))
            break
        if s.get('zone') == 'other' and j.hunt:
            trace['travel'] = 'foot'
            break
        if s.get('zone') == 'other' and not j.hunt:
            # standing somewhere else already (a street, a hunt): the way to the temple first, as a person does
            how, _got, note = await walk_to_place(io, r, 'temple')
            if note:
                fallbacks.append(note)
            if how not in ('foot', 'helper'):
                trace['travel'], trace['no_way'] = 'no way', 'no way to the temple: %s' % how[:60]
                break
            continue
        await j.act(cio, s)
    if trace.get('travel') is None:
        trace['travel'], trace['no_way'] = 'no way', 'the legs to the hunt took more than %d s' % int(BOUNTY_TRAVEL_BUDGET)
    trace['steps'] = trace.get('steps', 0) + j.steps
    for f in j.fallbacks:
        fallbacks.append(f)
    return time.monotonic() - t0


async def bounty_near_row(io, a):
    """O661: of the hunt contracts a board lists (`candidates`, each with the mark of the hunt that lists its monster), the one whose mark is nearest to
    the arrival of a hunt teleport the bot's level may enter (`journey near X Y Z` answers that hunt and its arrival): a person takes the contract he can
    walk to. -> (row, None) with row['arrival'] the tiles from the arrival to the mark, or (None, text) when no mark is within BOUNTY_TRAVEL_MAX of an
    arrival (the text names the nearest)"""
    best, near_text, seen = None, None, 0
    for c in a.get('candidates') or []:
        m = c.get('mark') if isinstance(c, dict) else None
        if not (isinstance(m, dict) and all(isinstance(m.get(k), int) for k in ('x', 'y', 'z'))):
            continue
        got = await io.helper(travel_command(m), 'journey', ANSWER)
        pick = got.get('pick') if isinstance(got, dict) else None
        arr = pick.get('a') if isinstance(pick, dict) else None
        if not isinstance(arr, dict):
            wp = waypoint_for(m)   # O662: no hunt teleport is open to the level: the waypoint may still lead there
            if wp is not None and wp[4] <= BOUNTY_TRAVEL_MAX and (best is None or wp[4] < best['arrival']):
                best = dict(c, arrival=wp[4], via='waypoint')
            continue
        seen += 1
        d = max(abs(arr['x'] - m['x']), abs(arr['y'] - m['y'])) + (1000 if arr.get('z') != m['z'] else 0)
        via, town = 'teleport', '%s arrives' % pick.get('n')
        wp = waypoint_for(m)   # O662: the waypoint portal of a town near the mark, the other way a person travels
        if wp is not None and wp[4] < d:
            d, via, town = wp[4], 'waypoint', 'the waypoint of %s is' % wp[0]
        if near_text is None or d < near_text[0]:
            near_text = (d, c.get('name'), town)
        if d <= BOUNTY_TRAVEL_MAX and (best is None or d < best['arrival']):
            best = dict(c, arrival=d, via=via)
    if best is not None:
        return best, None
    if not seen:
        return None, 'no hunt teleport is open to level %s, or an old helper file' % a.get('level')
    return None, 'none of the %d hunt contract(s) has a hunt a teleport leads to (the nearest: %s, %s %d tiles from its hunt)' % (
        seen, near_text[1], near_text[2], near_text[0])


# ------------------------------------------------------------------------------------------------ the weapon and the tree of the bot's level (O662)
# O661 left the bots with the kit weapon: the pocket boss lost about 0.1 % a second and Ember Descent room 1 killed them. A player of the level
# carries a weapon of the level band; the Gambler (Mordecai Ashwager, from level 40) sells exactly that: the stock window lists only what the
# class and the level may wear (the base of the highest level band, an item level of the gate of the level). So the gear-up buys the best weapon
# of the stock for the gold of the bank (the TEST ONLY gold top-up of O658 is the only grant, never an item: `gold_enough`), drags it onto the weapon
# hand like any piece, and the old weapon goes to the bag. Whatever is left of the passive points after the Defense build goes on the damage build.
GEAR_WEAPON_CAP = 6000000      # gold for one weapon (a piece costs at most GEAR_PIECE_CAP; the weapon is the one piece that decides the damage)
WEAPON_TRIES = (6, 6, 5)       # the slots a weapon is dragged to, in turn, until it is in a hand (6 CONST_SLOT_LEFT, 5 CONST_SLOT_RIGHT)
HAND_SLOT = 6                  # CONST_SLOT_LEFT: the weapon hand (the kit weapon sits there; a bow too, the quiver in the other hand)
TREE_GAP = 1.3                 # seconds between two Auto build requests (passive_builds.lua rateMs 1000: the next one is refused "Too fast")
TREE_REST = 'focus_damage'     # the build that takes what the Defense build left (a build is cut to the points the character owns)


def hand_weapon(hands):
    """the worn weapon row of the `hands` of `!tester found` (the one in the weapon hand), or None"""
    worn = [w for w in (hands or {}).get('worn') or [] if isinstance(w, dict)]
    return next((w for w in worn if w.get('s') == HAND_SLOT), None) or (worn[0] if worn else None)


def weapon_pick(rows, worn_il, cap=GEAR_WEAPON_CAP):
    """from the Gambler's stock the weapon to buy: the unsold 'Weapon' row of the highest item level above the worn weapon's, under `cap` gold
    (the cheaper on a tie); None when none is better. The window lists only what the class and the level may wear"""
    cands = [e for e in rows or [] if isinstance(e, dict) and not e.get('sold') and e.get('sn') == 'Weapon'
             and 0 < int(e.get('p') or 0) <= cap and int(e.get('l') or 0) > int(worn_il or 0)]
    cands.sort(key=lambda e: (-int(e.get('l') or 0), int(e['p']), int(e.get('i') or 0)))
    return cands[0] if cands else None


def weapon_in_bag(hands, item_id):
    """the backpack weapon row of `hands` with the server item id `item_id` (the best score when several), or None"""
    rows = [w for w in (hands or {}).get('bag') or [] if isinstance(w, dict) and w.get('id') == item_id]
    rows.sort(key=lambda w: -int(w.get('sc') or 0))
    return rows[0] if rows else None


def weapon_worn_text(before, after, row):
    """(worn, text): did the weapon move into the hand; `before` / `after` the worn weapon rows"""
    if isinstance(after, dict) and after.get('id') == row.get('id') and (before or {}).get('id') != row.get('id'):
        return True, 'wore a weapon (item level %s over %s)' % (row.get('l'), (before or {}).get('il', 0))
    return False, 'the weapon stayed in the bag (a level, class or two-handed rule: not a fault)'


def weapon_held(hands, worn_il, skip=()):
    """the best weapon the backpack holds already (an earlier login's purchase, a drop) that is above the worn weapon's item level, or None; `skip`
    holds the (id, index) of rows already tried"""
    rows = [w for w in (hands or {}).get('bag') or [] if isinstance(w, dict) and int(w.get('il') or 0) > int(worn_il or 0) and (w.get('id'), w.get('i')) not in skip]
    rows.sort(key=lambda w: (-int(w.get('il') or 0), -int(w.get('sc') or 0), int(w.get('i') or 0)))
    return rows[0] if rows else None


async def wear_weapon(io, g, mine, worn, row=None):
    """drags the backpack weapon `mine` onto a hand, again (and onto the other hand) when it did not move, after the backpack has a free slot for the
    weapon that is taken off (a full backpack answers "Sorry, not possible."). -> True when it is in a hand; the text goes in g['weapon'], a failure in g['notes']"""
    await make_room(io, 'gear_up')
    row = row or mine
    ok, text, after, tried = False, '', None, []
    after, _ = await found_look(io)   # the drag names the backpack as container 0: when the helper says it is not open, the bot opens it as a person does
    for slot in WEAPON_TRIES:   # a person drags again when the weapon did not move: the same hand, later, then the other hand
        if isinstance(after, dict) and after.get('bagOpen') is False and after.get('bagClientId'):
            await io.open_bag(after['bagClientId'])
            await io.sleep(1.0)
        await io.wear(mine['i'], mine['cid'], slot)
        await io.sleep(1.5)
        after, _ = await found_look(io)
        in_hand = next((w for w in ((after or {}).get('hands') or {}).get('worn') or [] if isinstance(w, dict) and w.get('id') == mine.get('id')), None)
        ok, text = weapon_worn_text(worn, in_hand, dict(row, id=mine.get('id'), l=mine.get('il', row.get('l'))))
        tried.append(slot)
        if ok:
            break
        mine = weapon_in_bag((after or {}).get('hands'), mine.get('id')) or mine
    if ok:
        g['weapon'] = text
        g['worn'] += 1
        g['pieces'].append('a weapon')
        if len(tried) > 1:
            g['notes'].append('the weapon moved at try %d (slot %s)' % (len(tried), tried[-1]))
        return True
    lines = [str(l) for l in list(getattr(getattr(io, 'bot', None), 'recent', None) or [])[-8:] if not str(l).startswith(('[tester-helper]', '{'))]
    said = ' | '.join(l[:60] for l in lines[-2:])   # the helper's own answers are text lines too: only the server's words
    g['notes'].append('weapon %s not worn after %d tries (%s)' % (mine.get('id'), len(tried), said or 'no word'))
    return False


async def gear_weapon(io, name, g, found, level):
    """a weapon of the bot's class and level band: the best one the backpack holds above the worn one, else the best of the Gambler's stock for the
    gold of the bank, worn at once. The text goes in g['weapon'], a bought piece in g['bought'], what could not be done in g['notes']. Nothing is
    bought when the hand holds the best weapon there is for the bot"""
    hands = (found or {}).get('hands') if isinstance(found, dict) else None
    if not isinstance(hands, dict):
        return   # a helper file of before O662 reads no weapons: the kit weapon stays (the report's gear-up line has no weapon text)
    worn = hand_weapon(hands)
    have = int((worn or {}).get('il') or 0)
    held = weapon_held(hands, have)
    if held is not None and await wear_weapon(io, g, held, worn):
        return
    if int(level or 0) < GAMBLE_MIN or not io.alive():
        return
    npc = 'Mordecai Ashwager'
    why, falls = await chore_walk(io, name, npc)
    g['fallbacks'].extend(falls)
    if why:
        g['notes'].append('no walk to %s: %s' % (npc, why))
        return
    row = None
    try:
        reply = await io.request('gamble', 'open', {}, ('state',), ANSWER)
        a = (reply or {}).get('data') if isinstance(reply, dict) else None
        if not isinstance(a, dict):
            g['notes'].append('no state in the Gambler window')
            return
        row = weapon_pick(a.get('items'), have)
        if row is None:
            mine = [e for e in a.get('items') or [] if isinstance(e, dict) and e.get('sn') == 'Weapon']
            g['weapon'] = 'no better weapon in the Gambler\'s stock (%d weapon row(s), worn item level %d)' % (len(mine), have)
            return
        if not await gold_enough(io, g, int(row['p']) + GEAR_RESERVE, 'a weapon of the Gambler'):
            row = None
            return
        await io.sleep(GAMBLE_GAP)
        bought = await io.request('gamble', 'buy', {'i': row['i'], 'w': a.get('w'), 'id': row.get('id')}, ('state', 'result'), ANSWER)
        await io.sleep(1.0)
        again = await io.request('gamble', 'open', {}, ('state',), ANSWER)
        b = (again or {}).get('data') if isinstance(again, dict) else None
        now = next((e for e in (b or {}).get('items') or [] if e.get('i') == row.get('i')), None) if isinstance(b, dict) else None
        if not (now is not None and now.get('sold')):
            g['notes'].append('the weapon of the Gambler was not sold (%s)' % gamble_refusal(bought, b))
            row = None
            return
        g['bought'].append('a weapon (item level %s) for %d gold' % (row.get('l'), int(row['p'])))
    finally:
        await io.request('gamble', 'close', {}, [], ANSWER)
    if row is None or not io.alive():
        return
    seen, why = await found_look(io)
    mine = weapon_in_bag((seen or {}).get('hands'), row.get('id')) if seen else None
    if mine is None:
        g['notes'].append('the bought weapon is not in the backpack (%s)' % (why or 'it may lie in the inbox'))
        return
    await wear_weapon(io, g, mine, worn, row)


async def gear_tree_rest(io, g, build=TREE_REST):
    """what is left of the passive points after the Defense build: the damage build, mode add (free, nothing taken back, cut to the points owned).
    Nothing is asked when the Defense build said it needed more points than the character owns (there is nothing left)"""
    if 'need more points' in str(g.get('tree') or ''):
        return False
    await io.sleep(TREE_GAP)
    ans = await io.request('passivetree', 'autobuildApply', {'build': build, 'mode': 'add', 'cost': 0}, TREE_DONE, ANSWER)
    done, text = tree_build_text(ans, build)
    g['tree_rest'] = text if done else None
    if not done and 'Nothing would change' not in text and 'no answer' not in text:
        g['notes'].append(text)
    return done


# ------------------------------------------------------------------------------------------------ a retreat scenario (O662)
# The raid's Leave button and the Town Portal refusal inside a dungeon are the answers to a SECOND retreat of one loop. A bot with a weapon now
# lives through the loops, so no live run reached a second retreat. `testers.py run --retreat-at N` is the scenario that forces it: the bots
# retreat under N percent health instead of 30 (a timid player), so the second retreat comes at the first hits and the way home is asked.
RETREAT_AT_RUN = [None]


def retreat_at():
    """the percent health a bot retreats under: RETREAT_AT, or the scenario's `--retreat-at`"""
    return RETREAT_AT_RUN[0] if RETREAT_AT_RUN[0] is not None else RETREAT_AT


def set_retreat_at(value):
    RETREAT_AT_RUN[0] = int(value) if value else None


# ------------------------------------------------------------------------------------------------ the way to a hunt no teleport reaches (O662)
# O661: the marks of the bounty hunts were 47 and 584 tiles from the arrival of the nearest hunt teleport, so the bounty walk was a SKIP. A person
# has more ways than the hunt teleports: the last leg on foot (the engine path search covers 150 tiles: a mark within BOUNTY_TRAVEL_MAX of an
# arrival is walked, not skipped), and the waypoint portals of the 18 towns (every waypoint is open for everyone, waypoints_config.lua
# unlockAll): the portal beside the temple opens the window of the base script (customs/waypoints/waypoint.lua: modal 5000, a choice per town,
# button 110 Select), the town is picked, the walk goes on from there. The table is the base script's own (the base tree is not in git: the live
# run checks it, a bot that arrives elsewhere says so). A hunt no way leads to within the cap is a SKIP with the three distances.
WAYPOINTS = (
    ('Mirewake', 32954, 32074, 7), ('Cinderhold', 32372, 32233, 7), ('Anvildeep', 32654, 31923, 11), ('Thornmere', 32358, 31783, 7),
    ('Gloamroot', 32715, 31631, 7), ('Kindle Isle', 32096, 32219, 6), ('Saltgrave', 32319, 32824, 7), ('Fevergate', 32591, 32746, 7),
    ('Dunescar', 33197, 32846, 8), ('Scorchveil', 33211, 32451, 1), ('Bellwatch', 33216, 31816, 8), ('Rimeholt', 32214, 31131, 7),
    ('Hollowspire', 32788, 31265, 7), ('Slagdelve', 33028, 31522, 11), ('Ashstrand', 33449, 31322, 9), ('Nightwrack', 33519, 32367, 7),
    ('Brassgate', 33597, 31893, 6), ('Wyrmscar', 33656, 31663, 8),
)
WAYPOINT_MODAL = 5000     # the base script's window id
WAYPOINT_SELECT = 110     # its Select button
WAYPOINT_BESIDE = 40      # tiles: a waypoint portal this near the bot is the one beside its temple (each town's portal stands next to its temple)
WAYPOINT_WAIT = 3.0       # seconds the window may take to open after the step onto the portal
WAYPOINT_TRIES = 5        # steps onto the portal (a bot that stands on it blocks it for the others)


def waypoint_for(mark):
    """the waypoint town nearest to a mark {x, y, z}: (name, x, y, z, tiles, list index of the base script, 1 based), or None. Another floor does
    not count (a waypoint is on the ground of its town: a cave floor of the mark is a walk down from there, not a short one)"""
    if not (isinstance(mark, dict) and all(isinstance(mark.get(k), int) for k in ('x', 'y', 'z'))):
        return None
    best = None
    for i, (n, x, y, z) in enumerate(WAYPOINTS, 1):
        if z != mark['z']:
            continue
        d = max(abs(x - mark['x']), abs(y - mark['y']))
        if best is None or d < best[4]:
            best = (n, x, y, z, d, i)
    return best


def waypoint_beside(pos):
    """the waypoint (name, x, y, z) whose portal stands within WAYPOINT_BESIDE tiles of `pos` on the same floor (the nearest), or None"""
    if not (isinstance(pos, dict) and all(isinstance(pos.get(k), int) for k in ('x', 'y', 'z'))):
        return None
    best = None
    for n, x, y, z in WAYPOINTS:
        d = max(abs(x - pos['x']), abs(y - pos['y']))
        if z == pos['z'] and d <= WAYPOINT_BESIDE and (best is None or d < best[4]):
            best = (n, x, y, z, d)
    return best


def waypoint_choice(window, town):
    """the choice id of the town in the waypoint window dict of parse_modal ((id, text) choices), or None"""
    for cid, text in (window or {}).get('choices') or []:
        if str(text).strip().lower() == str(town).strip().lower():
            return cid
    return None


async def bounty_waypoint_leg(io, r, goal, trace, fallbacks):
    """the waypoint leg: the temple, the portal beside it (on foot, the engine path), the window, the town nearest to the goal, a look at where the
    bot stands. Sets trace['travel'] to 'foot' (arrived) or 'no way' (trace['no_way'] says why). -> seconds spent"""
    t0 = time.monotonic()
    wp = waypoint_for(goal)
    trace['travel'] = None
    if wp is None:
        trace['travel'], trace['no_way'] = 'no way', 'no waypoint on the floor of the goal'
        return time.monotonic() - t0
    how, _got, note = await walk_to_place(io, r, 'temple')
    if note:
        fallbacks.append(note)
    if how not in ('foot', 'helper'):
        trace['travel'], trace['no_way'] = 'no way', 'no way to the temple: %s' % how[:60]
        return time.monotonic() - t0
    await io.sleep(SETTLE)   # the helper's teleport to the temple (when the bot stood on another floor) is settled before the path is asked
    here = await io.helper('bounty state', 'bounty', ANSWER)
    home = waypoint_beside((here or {}).get('pos') if isinstance(here, dict) else None)   # the portal of the bot's own town, beside its temple
    if home is None:
        trace['travel'], trace['no_way'] = 'no way', 'no waypoint portal beside the temple the bot stands at (%s)' % (
            '%s,%s,%s' % tuple((here or {}).get('pos', {}).get(k) for k in 'xyz') if isinstance(here, dict) and isinstance((here or {}).get('pos'), dict) else 'no position')
        return time.monotonic() - t0
    if home[0] == wp[0]:
        trace['travel'] = 'foot'   # the temple of the bot's town is the town the hunt is nearest to: no portal needed
        return time.monotonic() - t0
    how, got = await walk_by_path(io, r, 'path pos %d %d %d' % home[1:4], 'path', 0)
    if how != 'foot' and (got or {}).get('err') and 'floor' in str((got or {}).get('err')):
        await io.sleep(SETTLE)
        how, got = await walk_by_path(io, r, 'path pos %d %d %d' % home[1:4], 'path', 0)
    if how != 'foot':
        trace['travel'], trace['no_way'] = 'no way', 'the walk to the waypoint of %s did not arrive: %s' % (home[0], str((got or {}).get('err') or how)[:60])
        return time.monotonic() - t0
    dest = {'x': home[1], 'y': home[2], 'z': home[3]}
    win = None
    for _ in range(WAYPOINT_TRIES):   # the portal is one tile: another bot may stand on it, the step is tried again after a pause
        a = await io.helper('bounty state', 'bounty', ANSWER)
        pos = (a or {}).get('pos') if isinstance(a, dict) else None
        if isinstance(pos, dict) and (pos.get('x'), pos.get('y')) != (dest['x'], dest['y']):
            for step in raid_plan(pos, dest, 1):   # the path answer says `here` one tile short: the last step is onto the portal, which opens the window
                await raid_walk(io, r, step)
            await io.sleep(1.0)
        end = time.monotonic() + WAYPOINT_WAIT
        while win is None and time.monotonic() < end and io.alive():
            win = next((w for w in reversed(list(getattr(getattr(io, 'bot', None), 'modals', []) or [])) if w.get('id') == WAYPOINT_MODAL), None)
            if win is None:
                await io.sleep(0.3)
        if win is not None or not io.alive():
            break
        await io.sleep(2.0)
    if win is None:
        trace['travel'], trace['no_way'] = 'no way', 'the portal of %s opened no window' % home[0]
        return time.monotonic() - t0
    choice = waypoint_choice(win, wp[0])
    if choice is None:
        trace['travel'], trace['no_way'] = 'no way', 'the waypoint window lists no %s' % wp[0]
        return time.monotonic() - t0
    await io.modal_answer(WAYPOINT_MODAL, WAYPOINT_SELECT, choice, 2.0)
    await io.sleep(1.5)
    a = await io.helper('bounty state', 'bounty', ANSWER)
    pos = (a or {}).get('pos') if isinstance(a, dict) else None
    if isinstance(pos, dict) and pos.get('z') == wp[3] and max(abs(pos['x'] - wp[1]), abs(pos['y'] - wp[2])) <= 6:
        trace['travel'] = 'foot'
        trace.setdefault('waypoints', []).append('%s -> %s' % (home[0], wp[0]))
    else:
        trace['travel'], trace['no_way'] = 'no way', 'the waypoint window did not take the bot to %s (it stands at %s)' % (
            wp[0], '%s,%s,%s' % (pos.get('x'), pos.get('y'), pos.get('z')) if isinstance(pos, dict) else 'an unknown place')
    return time.monotonic() - t0


async def bounty_travel(io, r, goal, trace, fallbacks):
    """the legs to a far hunt: by a waypoint when the contract was picked for one (trace['via']), else by the journey's legs"""
    if trace.get('via') == 'waypoint':
        return await bounty_waypoint_leg(io, r, goal, trace, fallbacks)
    return await bounty_travel_leg(io, r, goal, trace, fallbacks)


# ---- the bot's damage a second at the pocket boss (O662): the boss's health lost between the first and the last look, over the seconds between them
def pocket_dps(t):
    """-> (damage a second, seconds, health lost) of the pocket fight from the trace's health looks (`series` percent, `series_t` clock, `boss_max`
    the boss's health), or None when the boss did not lose health or the helper gave no maximum. Healing is not seen: it is a lower bound"""
    s, ts, mx = t.get('series') or [], t.get('series_t') or [], t.get('boss_max')
    if not mx or len(s) < 2 or len(ts) != len(s):
        return None
    ab = t.get('series_abs') or []
    if len(ab) == len(s):
        s, mx = ab, 100.0   # exact health: `lost` below is then the health itself
    top = max(range(len(s)), key=lambda i: (s[i], -i))
    low = min(range(top, len(s)), key=lambda i: (s[i], i))
    secs = ts[low] - ts[top]
    lost = (s[top] - s[low]) * mx / 100.0
    if secs < 5.0 or lost <= 0:
        return None
    return lost / secs, secs, lost


def pocket_dps_text(t):
    d = pocket_dps(t)
    return '' if d is None else ' [bot damage about %d a second: %d health in %d s]' % (round(d[0]), round(d[2]), round(d[1]))
