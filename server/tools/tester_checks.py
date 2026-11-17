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
        'socketed': len(socks.get('list') or []),
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
    if not await io.go('hunt'):
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
    after, st2 = await bench.view(item)
    if after is None:
        return bench.skip('no tooltip or bench answer after the gem')
    if after['socketed'] != before['socketed'] + 1:
        return bench.fail('gems in the sockets %d -> %d after the use-with: expected one more' % (before['socketed'], after['socketed']))
    if after['tip'] == before['tip']:
        return bench.fail('the gem sits in the socket but the tooltip did not change')
    return Result('craft_gems', name, cls, PASS, 'a gem socketed by use-with (%d of %d sockets), the tooltip shows it' % (
        after['socketed'], after['sockets']))


async def check_craft_supports(io, name, cls, level):
    """a support rune into a spell of the class through the support window: the spell lists it afterwards"""
    bench = Bench(io, name, cls, 'craft_supports')
    if not await io.go('hunt'):
        return bench.skip(not_at_hunt(io))
    ans = await io.request('supports', 'open', {}, ('state',), ANSWER)
    spells = [s for s in (((ans or {}).get('data') or {}).get('spells') or []) if isinstance(s, dict)]
    if not spells:
        return bench.skip('no state or no spell in the support window')
    spell = next((s for s in spells if int(s.get('count') or 0) < int(s.get('max') or 0)), None)
    if spell is None:
        return bench.skip('every spell has its sockets full')
    rune = await bench.give('rune', 'rune')
    if not rune:
        return bench.skip('no rune from the helper (%s)' % bench.err)
    res = await io.request('supports', 'socket', {'spell': spell['id'], 'rune': rune['id']}, ('result',), ANSWER)
    data = (res or {}).get('data') or {}
    if res is None:
        return bench.skip('no answer to the rune')
    if not data.get('ok'):
        return bench.skip('the rune was refused: %s' % str(data.get('text'))[:60])
    ans = await io.request('supports', 'open', {}, ('state',), ANSWER)
    now = next((s for s in (((ans or {}).get('data') or {}).get('spells') or []) if isinstance(s, dict) and s.get('id') == spell['id']), None)
    if now is None:
        return bench.skip('no state after the rune')
    if int(now.get('count') or 0) != int(spell.get('count') or 0) + 1:
        return bench.fail('spell %s holds %s runes after the socket, expected %d' % (
            spell.get('name') or spell['id'], now.get('count'), int(spell.get('count') or 0) + 1))
    return Result('craft_supports', name, cls, PASS, 'a rune socketed into %s: %s runes now' % (spell.get('name') or spell['id'], now.get('count')))


async def check_craft_charms(io, name, cls, level):
    """a charm into the grid and out again: the bag, the grid and the totals move one by one"""
    bench = Bench(io, name, cls, 'craft_charms')
    if not await io.go('hunt'):
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
    ok = [d for d in a.get('list') or [] if isinstance(d, dict) and isinstance(d.get('id'), int)]
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


async def dungeon_play(io, name, cls, a, dg, partners):
    key = 'closed_dungeon'
    size = max(1, int(dg.get('size') or 1))
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
    # queue, each bot from its own window; the run starts when the group is full or the solo wait is over
    for r in squad:
        data = {'id': dg['id'], 'difficulty': 1}
        reply = await (io.request('dungeons', 'queue', data, ['queue'], ANSWER) if r['lead']
                       else io.request_of(r['name'], 'dungeons', 'queue', data, ['queue'], ANSWER))
        if reply is not None and (reply.get('data') or {}).get('joined') is False and r['lead']:
            return Result(key, name, cls, SKIP, 'the queue refused the bot (level, a cooldown, a fight or the dungeon\'s own rule)', fallbacks)
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
            await (io.request('dungeons', 'queue', {'id': dg['id'], 'difficulty': 1}, ['queue'], ANSWER) if r['lead']
                   else io.request_of(r['name'], 'dungeons', 'queue', {'id': dg['id'], 'difficulty': 1}, ['queue'], ANSWER))
        return Result(key, name, cls, SKIP, 'the dungeon did not start in %d s (a run of players is ahead of the testers)' % int(DUNGEON_QUEUE_WAIT), fallbacks)
    for r in squad:
        s = state if r['lead'] else await dungeon_look(io, r)
        r['inside'] = bool(isinstance(s, dict) and s.get('inside'))
    trace = {'faults': [], 'steps': 0, 'percent': 0, 'unlocked': False, 'won': False, 'fought': 0.0, 'stuck': None, 'secs': 0,
             'left': '?', 'members': sum(1 for r in squad if r['inside']), 'title': dg.get('title'), 'died': False,
             'level': a.get('level'), 'came': 'foot' if all(h == 'foot' for h in came.values()) else 'helper',
             'size': size, 'fallbacks': fallbacks}
    res = await dungeon_walk_all(io, name, cls, squad, trace)
    return res


async def dungeon_walk_all(io, name, cls, squad, trace):
    """the play loop: look, then each bot walks, waits or fights by what the screen says, until the run is over or the time is"""
    key = 'closed_dungeon'
    elapsed, misses = 0.0, 0
    fight_since, progress, boss_seen, looted = None, None, False, 0.0
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
        trace['faults'] += [p for p in dungeon_problems(lead, trace['size']) if p not in trace['faults']]
        if trace['faults']:
            break
        run = lead.get('run') or {}
        guide = lead.get('guide') or {}
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
    return Result(key, name, cls, status, text, trace.get('fallbacks'))


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
    if t.get('fallbacks'):
        how += '; teleport in place of walking: ' + ', '.join(t['fallbacks'])
    if t.get('kills', 0) > 0 or (t.get('hp') is not None and t['hp'] < 100):
        what = '%d kill(s)' % t.get('kills', 0)
        if t.get('boss_seen'):
            what += ', the guardian at %s%%' % t.get('hp')
        return PASS, '%s (%s)' % (what, how)
    if t.get('fought', 0) >= RIFT_FIGHT_MIN:
        return FAIL, 'fought %d s in the rift and killed none (damage, targets or the monsters)' % t['fought']
    if t.get('floor'):
        return SKIP, 'the next goal is on another floor of the rift: the stairs are not walked yet (%s)' % how
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
        k = await io.helper('rift key', 'rift', HELPER_WAIT)
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
    while io.alive() and elapsed < RIFT_BUDGET:
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
            trace['died'] = not trace['kills'] and elapsed < RIFT_BUDGET and not trace['boss_seen']
            break
        trace['theme'] = run.get('theme') or trace['theme']
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
        if g.get('mode') == 'fight':
            fight_since = elapsed if fight_since is None else fight_since
            trace['fought'] = max(trace['fought'], elapsed - fight_since)
        elif g.get('mode') != 'wait':
            fight_since = None
        if trace['kills'] > 0 and trace['boss_seen'] and trace['hp'] is not None and trace['hp'] < 100:
            break   # a pack monster killed and the guardian hurt: the run has been walked through
        plan = []
        if g.get('mode') == 'walk' and isinstance(g.get('goal'), dict):
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
        placed, tile, last = None, None, None
        for (x, y) in cells:
            last = await io.request('hideout', 'place', {'key': deco['key'], 'x': x, 'y': y, 'r': 0}, ['result'], ANSWER)
            if isinstance(last, dict) and (last.get('data') or {}).get('ok'):
                placed, tile = last, (x, y)
                break
        if placed is None:
            return Result(key, name, cls, FAIL, 'no tile of the room took %s in %d tries: %s' % (deco.get('name') or deco['key'], len(cells), hideout_text(last) or 'no answer'))
        after, _ = await hideout_state(io, 'get')
        rows = [p for p in ((after or {}).get('placed') or []) if isinstance(p, dict) and p.get('key') == deco['key'] and (p.get('x'), p.get('y')) == tile]
        count1 = int((((after or {}).get('hideout')) or {}).get('count') or 0)
        if not rows or count1 != count0 + 1:
            return Result(key, name, cls, FAIL, '%s was placed at %s and the room lists %d such decoration(s), the count went %s to %s' % (
                deco['key'], tile, len(rows), count0, count1))
        gone = await io.request('hideout', 'remove', {'id': rows[0].get('id')}, ['result'], ANSWER)
        again, _ = await hideout_state(io, 'get')
        count2 = int((((again or {}).get('hideout')) or {}).get('count') or 0)
        if not (isinstance(gone, dict) and (gone.get('data') or {}).get('ok')) or count2 != count0:
            return Result(key, name, cls, FAIL, 'the decoration was removed and the room counts %s, it counted %s before: %s' % (count2, count0, hideout_text(gone) or 'no text'))
        await io.request('hideout', 'leave', {}, ['state', 'result'], ANSWER)
        await io.sleep(1.0)
        outside, _ = await hideout_state(io, 'get')
        inside_room = bool(isinstance(outside, dict) and outside.get('inside'))
        if inside_room:
            return Result(key, name, cls, FAIL, 'Leave did not bring the bot out of its hideout')
        return Result(key, name, cls, PASS, '%s placed at %s, listed, removed; the room was entered and left' % (deco.get('name') or deco['key'], tile))
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
    ('closed_siege', check_closed_siege, lambda c: True),   # O592
    ('closed_guildboss', check_closed_guildboss, lambda c: True),   # O592
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
    ('rift_walk', check_rift_walk, lambda c: True),   # O592: the rift on foot, the longest of the open checks: last
]
KEYS = tuple(k for k, _, _ in CHECKS)


class CheckRun:
    """the checks of one bot; results go on after a death (a check cut off by it is done again) like the keystone scenario"""

    def __init__(self, name, cls, level, only=None, closed=False):
        self.name, self.cls, self.level = name, cls, level
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
    tele = {}
    for r in results:
        for f in r.get('fallbacks') or []:
            tele[(r['check'], f)] = tele.get((r['check'], f), 0) + 1
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


if __name__ == '__main__':
    print(json.dumps({'checks': list(KEYS)}))
