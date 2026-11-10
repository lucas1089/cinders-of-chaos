#!/usr/bin/env python3
"""Unit test of the launch rehearsal (O441): the pure part of tools/ci/launch_rehearsal_core.py, the reading of the module
replies in tools/ci/launch_rehearsal_probe.py, and a few static rules of tools/ci/launch_rehearsal.sh. No server, no database,
no network, no libfaketime. Run: python3 -I tools/ci/launch_rehearsal_test.py"""
import copy
import datetime
import json
import os
import re
import struct
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..', '..'))
sys.dont_write_bytecode = True
sys.path.insert(0, HERE)
import launch_rehearsal_core as C  # noqa: E402
import launch_rehearsal_probe as P  # noqa: E402

SERVER = os.path.join(REPO, 'server')
B = C.read_boundaries(SERVER)
RUNS = C.plan(B)
D = datetime.datetime


def secs(a, b):
    return (a - b).total_seconds()


def stamp_of(run, at):
    return C.stamp(run['start'] + datetime.timedelta(seconds=at))


def sample(run, at, **kw):
    s = {'at': at, 'fake': stamp_of(run, at), 'founder': {'listed': False}, 'season': {'status': 'upcoming', 'id': 1},
         'pvp': {'id': 1, 'endsIn': None}, 'weekend': {'running': False, 'preview': False},
         'broadcasts': {'season_begun': 0, 'weekend_begins': 0, 'weekend_preview': 0, 'save_first': 0, 'save_any': 0}}
    s.update(kw)
    return s


def good_obs():
    """what a correct launch looks like to the probe, run by run"""
    by = {r['id']: r for r in RUNS}
    obs = {}
    r = by['launch']
    at0, at1 = r['samples']
    f0, f1 = r['start'] + datetime.timedelta(seconds=at0), r['start'] + datetime.timedelta(seconds=at1)
    obs['launch'] = {
        'facts': {'start_line': {'time': stamp_of(r, 27), 'offset': -180, 'lines': 1, 'warnings': 0},
                  'season_start_lines': 1, 'season_end_lines': 0, 'season_running_line': 1, 'season_members': 0,
                  'db_start_rows': 1, 'members_before': 0, 'sentinel_rows': 1, 'sentinel_value': 77, 'db_members': 1,
                  'creator_shares': {'before': 100, 'start': 150, 'last': 150, 'after': 100},
                  'launch_check': {'dates_season': 'OK', 'dates_pvp': 'OK', 'dates_founder': 'OK', 'dates_creator': 'OK',
                                   'timezone': 'OK', 'beta_config': 'FAIL'}},
        'samples': [
            sample(r, at0, season={'status': 'upcoming', 'id': 1, 'startsIn': secs(B['season_start'], f0), 'endsIn': None},
                   pvp={'id': 1, 'endsIn': secs(B['pvp_end'], f0)}),
            sample(r, at1, founder={'listed': True}, season={'status': 'active', 'id': 1, 'startsIn': None,
                                                              'endsIn': secs(B['season_end'], f1)},
                   pvp={'id': 1, 'endsIn': secs(B['pvp_end'], f1)},
                   broadcasts={'season_begun': 1, 'weekend_begins': 0, 'weekend_preview': 0, 'save_first': 0, 'save_any': 0})]}
    r = by['again']
    obs['again'] = {
        'facts': {'season_start_lines': 0, 'season_end_lines': 0, 'season_running_line': 1, 'season_members': 1,
                  'db_start_rows': 1, 'db_end_rows': 0, 'db_migrated_rows': 0, 'sentinel_rows': 1, 'sentinel_value': 77,
                  'db_members': 1},
        'samples': [sample(r, 55, founder={'listed': True}, season={'status': 'active', 'id': 1})]}
    r = by['weekend_on']
    obs['weekend_on'] = {'facts': {'weekend_begin_lines': 1}, 'samples': [
        sample(r, 55, weekend={'running': False, 'preview': True}),
        sample(r, 200, weekend={'running': True, 'preview': True},
               broadcasts={'season_begun': 0, 'weekend_begins': 2, 'weekend_preview': 1, 'save_first': 0, 'save_any': 0})]}
    r = by['founder_end']
    obs['founder_end'] = {'facts': {}, 'samples': [sample(r, 55, founder={'listed': True}),
                                                    sample(r, 200, founder={'listed': False})]}
    r = by['weekend_off']
    obs['weekend_off'] = {'facts': {}, 'samples': [sample(r, 55, weekend={'running': True, 'preview': False}),
                                                    sample(r, 200, weekend={'running': False, 'preview': False})]}
    r = by['save']
    obs['save'] = {'facts': {'exit_after': 300}, 'samples': [
        sample(r, 55), sample(r, 200, broadcasts={'season_begun': 0, 'weekend_begins': 0, 'weekend_preview': 0,
                                                  'save_first': 1, 'save_any': 2})]}
    return obs


def decide(obs):
    return {r['name']: r for r in C.decide_all(B, RUNS, obs)}


class Boundaries(unittest.TestCase):
    def test_dates_come_from_the_real_configs(self):
        launch = D(2026, 11, 20, 15, 0)
        self.assertEqual(launch, D.strptime(C.LAUNCH, '%Y-%m-%d %H:%M'))
        for k in ('season_start', 'pvp_start', 'founder_start', 'creator_start'):
            self.assertEqual(B[k], launch, k)
        self.assertEqual(B['founder_end'], D(2026, 12, 18, 15, 0))
        self.assertEqual(B['creator_end'], D(2026, 12, 20, 15, 0))
        self.assertEqual(B['season_end'], D(2027, 2, 19, 15, 0))
        self.assertEqual(B['pvp_end'], D(2027, 1, 15, 15, 0))
        self.assertEqual((B['creator_pct'], B['creator_base']), (15, 10))

    def test_weekend(self):
        start, end = C.weekend_window(B, B['season_start'])
        self.assertEqual(start, D(2026, 11, 20, 18, 0))   # Friday, after the launch minute
        self.assertEqual(end, D(2026, 11, 23, 0, 0))      # the last minute is Sunday 23:59
        self.assertEqual(C.lua_wday(start), 6)
        self.assertEqual(C.weekend_theme(B, start), 'Ritual of Training')

    def test_unreadable_config_is_an_error(self):
        import tempfile
        with tempfile.TemporaryDirectory() as d:
            os.makedirs(os.path.join(d, 'data', 'scripts', 'chaos'))
            with self.assertRaises(ValueError):
                C.read_boundaries(d)

    def test_creator_instants(self):
        got = dict(C.creator_instants(B))
        self.assertEqual(got['start'], 1795197600)          # 2026-11-20 18:00:00 UTC is 15:00 in Brasilia
        self.assertEqual(got['before'], got['start'] - 1)
        self.assertEqual(got['after'] - got['start'], 30 * 86400)
        self.assertEqual(got['last'], got['after'] - 1)


class Plan(unittest.TestCase):
    def test_runs(self):
        ids = [r['id'] for r in RUNS]
        self.assertEqual(ids, ['launch', 'again', 'weekend_on', 'weekend_off', 'save', 'founder_end'])
        by = {r['id']: r for r in RUNS}
        self.assertEqual(by['launch']['start'], D(2026, 11, 20, 14, 58))
        self.assertEqual(by['launch']['samples'], [C.READY, C.LEAD + C.SETTLE])
        self.assertEqual(by['again']['start'], D(2026, 11, 20, 15, 2))
        self.assertIsNone(by['again']['cross'])
        self.assertEqual(by['weekend_on']['start'], D(2026, 11, 20, 17, 58))
        self.assertEqual(by['founder_end']['start'], D(2026, 12, 18, 14, 58))
        self.assertEqual(by['weekend_off']['start'], D(2026, 11, 22, 23, 58))
        self.assertEqual(by['save']['start'], D(2026, 11, 23, 5, 58))
        self.assertGreater(by['save']['wait_exit'], C.NOTIFY_MINUTES * 60)

    def test_every_sample_is_on_the_right_side(self):
        for r in RUNS:
            if r['cross'] is None:
                continue
            self.assertLess(r['samples'][0], r['cross'])
            self.assertGreater(r['samples'][1], r['cross'] + 60)   # the season check runs every 60 s

    def test_save_time_follows_the_option(self):
        runs = C.plan(B, (7, 30))
        self.assertEqual({r['id']: r for r in runs}['save']['boundary'], D(2026, 11, 23, 7, 30))

    def test_tsv(self):
        lines = C.plan_tsv(RUNS).split('\n')
        self.assertEqual(len(lines), 6)
        self.assertEqual(lines[0].split('\t'), ['launch', '2026-11-20 14:58:00', '55,200', '120', '0'])
        self.assertEqual(lines[1].split('\t')[3], '-')
        starts = [ln.split('\t')[1] for ln in lines]
        self.assertEqual(starts, sorted(starts))      # chronological: the clock never goes back in one database


class LogFacts(unittest.TestCase):
    def test_start_line(self):
        text = '>> Timezone: local time 2026-11-20 14:58:27, UTC-03:00 (expected America/Sao_Paulo, UTC-03:00)\n'
        r = C.parse_start_line(text)
        self.assertEqual((r['time'], r['offset'], r['warnings']), ('2026-11-20 14:58:27', -180, 0))
        w = C.parse_start_line('>> Timezone: local time 2026-11-20 17:58:27, UTC+00:00 (x)\n>> TIMEZONE WARNING: this machine\n')
        self.assertEqual((w['offset'], w['warnings']), (0, 1))
        self.assertEqual(C.parse_start_line('nothing')['time'], None)
        self.assertEqual(C.parse_start_line('>> Timezone: local time 2026-11-20 14:58:27, UTC+05:30 (x)')['offset'], 330)

    def test_counts_only(self):
        text = '\n'.join(['[Chaos season] Season of Ash running, 3 season character(s)',
                          '[Chaos season] start: season 1, player 0 season started',
                          '[Chaos season] end: season 1, player 0 season ended',
                          '[Error - Whatever] x', 'Lua Script Error: y'])
        r = C.parse_log(text)
        self.assertEqual(r, {'season_start_lines': 1, 'season_end_lines': 1, 'season_running_line': 1, 'season_members': 3,
                             'weekend_begin_lines': 0, 'lua_errors': 2})
        self.assertEqual(C.parse_log('[Chaos weekend] WEEKEND RITUAL: the weekend begins! Ritual of X')['weekend_begin_lines'], 1)
        self.assertNotIn('Ash', json.dumps(r))     # a count, never a log line
        self.assertEqual(C.parse_log('')['season_members'], None)

    def test_lcfacts(self):
        rep = {'checks': [{'status': 'OK', 'name': 'dates_season', 'text': 't'}, {'status': 'FAIL', 'name': 'beta_config', 'text': 'u'}]}
        self.assertEqual(C.lc_facts(rep), {'dates_season': 'OK', 'beta_config': 'FAIL'})


class Decisions(unittest.TestCase):
    def test_a_correct_launch_passes_every_check(self):
        res = decide(good_obs())
        self.assertEqual(set(res), set(C.CHECKS))
        for name, r in res.items():
            self.assertTrue(r['ok'], '%s: %s' % (name, r['text']))
        self.assertEqual(C.exit_code(list(res.values())), 0)

    def test_start_line_fails(self):
        for bad in ({'offset': 0}, {'warnings': 1}, {'time': None}, {'time': '2026-11-20 17:58:27'}):
            o = good_obs()
            o['launch']['facts']['start_line'].update(bad)
            self.assertFalse(decide(o)['start_line']['ok'], bad)

    def test_founder_window(self):
        o = good_obs()
        o['launch']['samples'][1]['founder']['listed'] = False      # never opens
        self.assertFalse(decide(o)['founder']['ok'])
        o = good_obs()
        o['launch']['samples'][0]['founder']['listed'] = True       # open too early
        self.assertFalse(decide(o)['founder']['ok'])
        o = good_obs()
        o['founder_end']['samples'][1]['founder']['listed'] = True  # never closes
        r = decide(o)['founder']
        self.assertFalse(r['ok'])
        self.assertIn('2026-12-18 15:00', r['text'])
        o = good_obs()
        del o['founder_end']
        self.assertFalse(decide(o)['founder']['ok'])

    def test_season(self):
        o = good_obs()
        o['launch']['samples'][1]['season']['status'] = 'upcoming'
        self.assertFalse(decide(o)['season']['ok'])
        o = good_obs()
        o['launch']['samples'][0]['season']['startsIn'] += 3 * 3600  # a clock three hours off (UTC)
        self.assertFalse(decide(o)['season']['ok'])
        o = good_obs()
        o['launch']['facts']['season_start_lines'] = 2
        self.assertFalse(decide(o)['season']['ok'])
        o = good_obs()
        o['launch']['samples'][1]['broadcasts']['season_begun'] = 0
        self.assertFalse(decide(o)['season']['ok'])

    def test_season_starts_once(self):
        for key, bad in (('season_start_lines', 1), ('db_start_rows', 2), ('db_end_rows', 1), ('db_migrated_rows', 1),
                         ('sentinel_rows', 0), ('sentinel_value', 0), ('season_members', 0)):
            o = good_obs()
            o['again']['facts'][key] = bad
            self.assertFalse(decide(o)['season_once']['ok'], key)
        o = good_obs()
        o['again']['samples'][0]['season']['status'] = 'upcoming'
        self.assertFalse(decide(o)['season_once']['ok'])
        o = good_obs()
        del o['again']
        self.assertFalse(decide(o)['season_once']['ok'])

    def test_pvp(self):
        o = good_obs()
        o['launch']['samples'][1]['pvp']['endsIn'] += 86400     # still before the epoch
        self.assertFalse(decide(o)['pvp']['ok'])
        o = good_obs()
        o['launch']['samples'][1]['pvp']['endsIn'] = B['pvp_weeks'] * 7 * 86400 + 5
        self.assertFalse(decide(o)['pvp']['ok'])
        o = good_obs()
        o['launch']['samples'][1]['pvp']['id'] = 2
        self.assertFalse(decide(o)['pvp']['ok'])
        o = good_obs()
        o['launch']['samples'][0]['pvp']['endsIn'] = None
        self.assertFalse(decide(o)['pvp']['ok'])

    def test_creator(self):
        for key, bad in (('before', 150), ('start', 100), ('last', 100), ('after', 150), ('after', None)):
            o = good_obs()
            o['launch']['facts']['creator_shares'][key] = bad
            self.assertFalse(decide(o)['creator']['ok'], key)

    def test_weekend(self):
        o = good_obs()
        o['weekend_on']['samples'][1]['weekend']['running'] = False
        self.assertFalse(decide(o)['weekend']['ok'])
        o = good_obs()
        o['weekend_on']['samples'][0]['weekend']['running'] = True
        self.assertFalse(decide(o)['weekend']['ok'])
        o = good_obs()
        o['weekend_on']['facts']['weekend_begin_lines'] = 2   # announced twice by the server
        self.assertFalse(decide(o)['weekend']['ok'])
        o = good_obs()
        o['weekend_on']['samples'][1]['broadcasts']['weekend_begins'] = 0   # the client never saw it
        self.assertFalse(decide(o)['weekend']['ok'])
        o = good_obs()
        o['weekend_on']['samples'][0]['weekend']['preview'] = False         # no login line before the start
        self.assertFalse(decide(o)['weekend']['ok'])
        o = good_obs()
        o['weekend_off']['samples'][1]['weekend']['running'] = True
        self.assertFalse(decide(o)['weekend']['ok'])
        o = good_obs()
        del o['weekend_off']
        self.assertFalse(decide(o)['weekend']['ok'])

    def test_save(self):
        for bad in ({'exit_after': None}, {'exit_after': 5}, {'exit_after': 900}):
            o = good_obs()
            o['save']['facts'].update(bad)
            self.assertFalse(decide(o)['save']['ok'], bad)
        o = good_obs()
        o['save']['samples'][1]['broadcasts']['save_first'] = 2    # fired twice
        self.assertFalse(decide(o)['save']['ok'])
        o = good_obs()
        o['save']['samples'][0]['broadcasts']['save_first'] = 1    # fired before the boundary
        self.assertFalse(decide(o)['save']['ok'])

    def test_launch_check(self):
        o = good_obs()
        o['launch']['facts']['launch_check']['dates_founder'] = 'FAIL'
        self.assertFalse(decide(o)['launch_check']['ok'])
        o = good_obs()
        del o['launch']['facts']['launch_check']['timezone']
        self.assertFalse(decide(o)['launch_check']['ok'])
        o = good_obs()
        o['launch']['facts']['launch_check']['beta_config'] = 'FAIL'    # not a date: the rehearsal does not judge it
        self.assertTrue(decide(o)['launch_check']['ok'])

    def test_a_missing_run_fails_never_passes(self):
        res = decide({})
        self.assertTrue(all(not r['ok'] for r in res.values()))
        self.assertEqual(C.exit_code(list(res.values())), 1)

    def test_decisions_do_not_depend_on_the_machine_zone(self):
        old = os.environ.get('TZ')
        try:
            for tz in ('UTC', 'America/Sao_Paulo', 'Asia/Tokyo'):
                os.environ['TZ'] = tz
                if hasattr(__import__('time'), 'tzset'):
                    __import__('time').tzset()
                self.assertTrue(all(r['ok'] for r in decide(good_obs()).values()), tz)
        finally:
            if old is None:
                os.environ.pop('TZ', None)
            else:
                os.environ['TZ'] = old
            if hasattr(__import__('time'), 'tzset'):
                __import__('time').tzset()


class Report(unittest.TestCase):
    def test_text(self):
        res = C.decide_all(B, RUNS, good_obs())
        text = C.report_text(B, res)
        self.assertEqual(len([ln for ln in text.split('\n') if ln.startswith('OK  ')]), len(C.CHECKS))
        self.assertIn('launch rehearsal: 0 FAIL, %d OK' % len(C.CHECKS), text)
        self.assertIn('Ritual of Training', text)
        o = good_obs()
        o['save']['facts']['exit_after'] = None
        text = C.report_text(B, C.decide_all(B, RUNS, o))
        self.assertIn('FAIL save:', text)
        self.assertIn('1 FAIL', text)

    def test_no_secret_shaped_words_in_a_report(self):
        text = C.report_text(B, C.decide_all(B, RUNS, good_obs())).lower()
        for word in ('password', 'account', 'character name', 'secret', 'token'):
            self.assertNotIn(word, text)

    def test_load_obs(self):
        import tempfile
        with tempfile.TemporaryDirectory() as d:
            with open(os.path.join(d, 'launch.json'), 'w') as f:
                json.dump(good_obs()['launch'], f)
            with open(os.path.join(d, 'again.json'), 'w') as f:
                f.write('not json')
            got = C.load_obs(d, RUNS)
            self.assertEqual(list(got), ['launch'])


class ProbeReading(unittest.TestCase):
    def frame(self, op, obj, prefix=b''):
        body = prefix + (obj if isinstance(obj, bytes) else json.dumps(obj).encode())
        return bytes([0x32, op]) + struct.pack('<H', len(body)) + body

    def test_replies_and_counts(self):
        s = P.Session()
        shop = {'action': 'categories', 'data': [{'name': 'Starter packs'}, {'name': 'Founder Pack', 'size': 2}]}
        season = {'action': 'state', 'data': {'season': {'status': 'active', 'id': 1, 'endsIn': 5000}}}
        bg = {'action': 'state', 'data': {'season': {'id': 1, 'endsIn': 4000}}}
        s.feed(b'\x00\x01' + self.frame(P.OP_SHOP, shop) + b'junk' + self.frame(P.OP_SEASON, season) + self.frame(P.OP_BG, bg))
        self.assertTrue(P.founder_listed(s.last(P.OP_SHOP, 'categories')))
        self.assertEqual(P.season_view(s.last(P.OP_SEASON, 'state'))['status'], 'active')
        self.assertEqual(P.pvp_view(s.frames[P.OP_BG][-1]), {'id': 1, 'endsIn': 4000})
        s.feed(b'..Sakura has begun! New characters can join in Adventure > Season...WEEKEND RITUAL: the weekend begins! x')
        s.feed(b'Server is saving game in 5  minute(s). Please logout.')
        s.feed(b'Server is saving game in 4  minute(s). Please logout.')
        self.assertEqual((s.counts['season_begun'], s.counts['weekend_begins'], s.counts['save_first'], s.counts['save_any']),
                         (1, 1, 1, 2))

    def test_no_founder_category(self):
        self.assertFalse(P.founder_listed({'data': [{'name': 'Starter packs'}]}))
        self.assertIsNone(P.founder_listed(None))

    def test_chunked_reply(self):
        s = P.Session()
        text = json.dumps({'action': 'state', 'data': {'season': {'status': 'upcoming', 'id': 1, 'startsIn': 77}}}).encode()
        a, b, c = text[:20], text[20:40], text[40:]
        s.feed(self.frame(P.OP_SEASON, a, b'S'))
        s.feed(self.frame(P.OP_SEASON, b, b'P'))
        self.assertEqual(s.frames[P.OP_SEASON], [])
        s.feed(self.frame(P.OP_SEASON, c, b'E'))
        self.assertEqual(P.season_view(s.last(P.OP_SEASON, 'state'))['startsIn'], 77)

    def test_weekend_status_line(self):
        s = P.Session()
        s.feed(b'[weekend] Running: Ritual of Training, until 2026-11-22 23:59 (2 days left).')
        self.assertEqual(s.weekend, 'running')
        s = P.Session()
        s.feed(b'[weekend] Next start: 2026-11-20 18:00, Ritual of Training.')
        self.assertEqual(s.weekend, 'off')

    def test_broken_frames_are_ignored(self):
        s = P.Session()
        s.feed(bytes([0x32, P.OP_SHOP]) + struct.pack('<H', 500) + b'{"a":1}')      # length beyond the packet
        s.feed(self.frame(P.OP_SHOP, b'{broken'))
        self.assertEqual(s.frames[P.OP_SHOP], [])


class Script(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with open(os.path.join(HERE, 'launch_rehearsal.sh')) as f:
            cls.text = f.read()

    def test_strict_mode_and_trap(self):
        self.assertIn('set -euo pipefail', self.text)
        self.assertIn('trap cleanup EXIT', self.text)

    def test_every_rm_has_a_guarded_path(self):
        for line in self.text.split('\n'):
            code = line.split('#')[0]
            if re.search(r'(^|[;&|(]\s*|\s)rm\s', code):
                self.assertRegex(code, r'\$\{[A-Z_]+:\?\}', line)

    def test_no_log_or_secret_printing(self):
        for line in self.text.split('\n'):
            code = line.strip()
            if code.startswith('#'):
                continue
            self.assertNotRegex(code, r'\b(cat|tail|head|less)\b[^|;]*\.log', line)
            self.assertNotRegex(code, r'echo[^|;]*(PASSWORD|CHARACTER|ACCOUNT|KEY)', line)
            self.assertNotIn('set -x', code)

    def test_reuses_the_live_check_not_a_fork(self):
        self.assertIn('unity_live_check.sh" --serve-only', self.text)
        self.assertIn('--stop', self.text)
        self.assertLess(len(self.text.split('\n')), 400)

    def test_every_check_has_a_name_in_the_header(self):
        for name in C.CHECKS:
            self.assertIn('#   %s' % name, self.text)


if __name__ == '__main__':
    unittest.main(verbosity=1)
