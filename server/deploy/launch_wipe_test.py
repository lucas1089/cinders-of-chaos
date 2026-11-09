#!/usr/bin/env python3
"""Tests for server/deploy/launch_wipe.py and its table policy launch_wipe_tables.json (docs/BETA.md section 9,
server/README.md "Launch wipe (O438)").

No database: the tool runs against a fake runner that holds row counts and applies a transaction only at COMMIT (a
failed statement drops it, like the real server rolling back). Checks: the policy covers every table that
server/sql/*.sql and the other CREATE TABLE places make (a new table needs a decision), every entry has an action and
a one-line reason, an owner decision never wipes, the policy validator refuses unsafe names, the SQL text (one
transaction, DELETE and never TRUNCATE, the keep tables never touched, FOREIGN_KEY_CHECKS off, the partial rules), the
AUTO_INCREMENT reset (keep_ids honoured), every refusal of --execute on its own (confirm, backup missing, empty or old,
server running, players online), the server detection, the mysql client call (the password only in a temporary option
file), the dry run (no write), execute (counts, baseline file, idempotent second run, rollback, a failed reset is a
warning), --verify, and the exit code 2 for a table the policy does not name.

usage: python3 -I server/deploy/launch_wipe_test.py
"""
import contextlib
import io
import json
import os
import re
import stat
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)
import launch_wipe as lw  # noqa: E402

POLICY_FILE = os.path.join(HERE, 'launch_wipe_tables.json')
CREATE = re.compile(r'CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?[`"]?([A-Za-z_][A-Za-z_0-9]*)', re.I)


def source_tables():
    """chaos_* and znote_* tables that the repository creates: server/sql, the revscripts, the website installer"""
    names = set()
    roots = [os.path.join(REPO, 'server', 'sql'), os.path.join(REPO, 'server', 'data', 'scripts'),
             os.path.join(REPO, 'website', 'overlay'), os.path.join(REPO, 'website', 'setup')]
    for root in roots:
        for d, _dirs, files in os.walk(root):
            for f in files:
                if not f.endswith(('.sql', '.lua', '.php')):
                    continue
                with open(os.path.join(d, f), encoding='utf-8', errors='replace') as fh:
                    for m in CREATE.finditer(fh.read()):
                        if m.group(1).startswith(('chaos_', 'znote_')):
                            names.add(m.group(1))
    # the table names of chaos_constants.lua Chaos.tables
    with open(os.path.join(REPO, 'server', 'data', 'scripts', 'chaos', 'chaos_constants.lua'), encoding='utf-8') as fh:
        text = fh.read()
    start = text.index('Chaos.tables = {')
    block = text[start:text.index('\n}', start)]
    names |= set(re.findall(r'"(chaos_[a-z0-9_]+)"', block))
    names |= set(re.findall(r'^Chaos\.tables\.\w+ = "(chaos_[a-z0-9_]+)"', text, re.M))
    return names


# a mini base schema: the tables of section 9 steps 5 and 6 that CREATE TABLE of this repository does not make
BASE_TABLES = ['accounts', 'account_viplist', 'players', 'players_online', 'player_items', 'player_depotitems',
               'player_inboxitems', 'player_storage', 'player_spells', 'player_deaths', 'player_namelocks',
               'guilds', 'guild_membership', 'guild_ranks', 'guild_invites', 'guild_wars', 'guildwar_kills',
               'houses', 'house_lists', 'tile_store', 'market_offers', 'market_history', 'server_config',
               'account_bans', 'account_ban_history', 'ip_bans']


class FakeDb:
    """row counts per table; query() answers what the tool asks, script() applies a transaction at COMMIT"""

    def __init__(self, policy, db='chaos_test'):
        self.db = db
        self.policy = policy
        self.tables = {}
        for n, e in policy.items():
            self.tables[n] = {'engine': 'InnoDB', 'auto_increment': 7 if e['action'] == 'wipe' else None,
                              'rows': 5 if e['action'] != 'wipe' else 3}
        self.columns = {'accounts': {'id', 'name', 'premium_ends_at', 'coins'}, 'houses': {'id', 'owner', 'paid', 'bid'},
                        'znote_accounts': {'id', 'points'}, 'server_config': {'config', 'value'}}
        self.hit = {'accounts': 4, 'houses': 2, 'znote_accounts': 1}
        self.dels = 3
        self.setrow = {'chaos_discord_season': 0}
        self.scripts = []
        self.queries = []
        self.fail_at = None
        self.fail_alter = False
        self.unknown = []
        self.online = 0
        self.resets = []

    # --- queries
    def query(self, sql):
        self.queries.append(sql)
        if sql == 'SELECT DATABASE()':
            return [[self.db]]
        if sql.startswith('SELECT table_name, engine'):
            rows = [[n, t['engine'], None if t['auto_increment'] is None else str(t['auto_increment'])]
                    for n, t in sorted(self.tables.items())]
            return rows + [[u, 'InnoDB', None] for u in self.unknown]
        if sql.startswith('SELECT table_name, column_name'):
            return [[t, c] for t in sorted(self.columns) for c in sorted(self.columns[t]) if "'%s'" % t in sql]
        if sql.startswith('SELECT COUNT(*) FROM `players_online`'):
            return [[str(self.online)]]
        if sql.startswith("SELECT '"):
            out = []
            for label in re.findall(r"SELECT '([^']+)', COUNT\(\*\)", sql):
                kind, _, rest = label.partition(':')
                if kind == 't':
                    out.append([label, str(self.tables[rest]['rows'])])
                elif kind == 'hit':
                    out.append([label, str(self.hit[rest])])
                elif kind == 'del':
                    out.append([label, str(self.dels)])
                elif kind == 'set':
                    out.append([label, str(self.setrow[rest.split(':')[1]])])
            return out
        raise AssertionError('unexpected query ' + sql)

    # --- scripts
    def script(self, sql, force=False):
        self.scripts.append(sql)
        stmts = [s.strip() for s in sql.split(';\n') if s.strip()]
        if stmts and stmts[0].startswith('ALTER TABLE'):
            errs = []
            for s in stmts:
                name = re.search(r'`([^`]+)`', s).group(1)
                if self.fail_alter:
                    errs.append("ERROR 1146 (42S02): Table '%s' doesn't exist" % name)
                else:
                    self.tables[name]['auto_increment'] = 1
                    self.resets.append(name)
            return errs
        buf, in_tx = [], False
        for s in stmts:
            s = s.rstrip(';')
            if self.fail_at and self.fail_at in s:
                return ['ERROR 1451 (23000): Cannot delete or update a parent row']
            if s.startswith('START TRANSACTION'):
                in_tx = True
            elif s == 'COMMIT':
                self._apply(buf)
                in_tx = False
            elif in_tx and not s.startswith('SET'):
                buf.append(s)
        return []

    def _apply(self, buf):
        for s in buf:
            if s.startswith('DELETE FROM `server_config` WHERE'):
                self.tables['server_config']['rows'] -= self.dels
                self.dels = 0
            elif s.startswith('DELETE FROM'):
                self.tables[re.search(r'`([^`]+)`', s).group(1)]['rows'] = 0
            elif s.startswith('UPDATE'):
                self.hit[re.search(r'`([^`]+)`', s).group(1)] = 0
            elif s.startswith('INSERT INTO `server_config`'):
                key = re.search(r"VALUES \('([^']+)'", s).group(1)
                if not self.setrow.get(key):
                    self.tables['server_config']['rows'] += 1
                self.setrow[key] = 1

    def snapshot(self):
        return ({n: t['rows'] for n, t in self.tables.items()}, dict(self.hit), self.dels, dict(self.setrow))


def run_main(argv, db, **kw):
    out, err = io.StringIO(), io.StringIO()
    kw.setdefault('server_check', lambda: [])
    kw.setdefault('now', 1000000.0)
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        code = lw.main(argv, runner=db, **kw)
    return code, out.getvalue(), err.getvalue()


class Base(unittest.TestCase):
    def setUp(self):
        self.policy = lw.load_policy(POLICY_FILE)
        self.tmp = tempfile.mkdtemp(prefix='lwtest-')
        self.env = os.path.join(self.tmp, 'chaos.env')
        with open(self.env, 'w') as f:
            f.write('CHAOS_DB_NAME=chaos_test\nCHAOS_DB_USER=chaos\nCHAOS_DB_PASS=never-printed\n')
        self.backup = os.path.join(self.tmp, 'dump.sql.gz')
        with open(self.backup, 'wb') as f:
            f.write(b'dump')
        os.utime(self.backup, (1000000.0 - 600, 1000000.0 - 600))
        self.baseline = os.path.join(self.tmp, 'baseline.json')
        self.db = FakeDb(self.policy)

    def args(self, *extra):
        return ['--env-file', self.env, '--baseline', self.baseline] + list(extra)

    def execute_args(self, **over):
        a = {'confirm': 'WIPE chaos_test', 'backup': self.backup}
        a.update(over)
        out = ['--execute']
        if a['confirm'] is not None:
            out += ['--confirm', a['confirm']]
        if a['backup'] is not None:
            out += ['--backup', a['backup']]
        return self.args(*out)


class PolicyTests(Base):
    def test_every_source_table_has_a_decision(self):
        missing = sorted(t for t in source_tables() if t not in self.policy)
        self.assertEqual(missing, [], 'tables created in the repository but not in launch_wipe_tables.json: %s' % missing)

    def test_no_stale_chaos_entries(self):
        src = source_tables()
        stale = sorted(t for t in self.policy if t.startswith(('chaos_', 'znote_')) and t not in src)
        self.assertEqual(stale, [], 'policy tables no CREATE TABLE makes (typo?): %s' % stale)

    def test_base_tables_of_section_9_are_named(self):
        for t in BASE_TABLES:
            self.assertIn(t, self.policy, t)

    def test_entries_are_explicit(self):
        for name, e in self.policy.items():
            self.assertIn(e['action'], ('wipe', 'keep', 'partial'), name)
            self.assertTrue(e['reason'].strip() and '\n' not in e['reason'], name)

    def test_owner_decision_never_wipes(self):
        marked = [n for n, e in self.policy.items() if e.get('owner_decision')]
        self.assertTrue(marked)
        for n in marked:
            self.assertNotEqual(self.policy[n]['action'], 'wipe', n)
            self.assertTrue(self.policy[n].get('owner_note'), n)

    def test_kept_by_decision(self):
        for n in ('chaos_beta_testers', 'chaos_admin_log', 'chaos_patchnotes', 'chaos_referral_codes',
                  'chaos_creator_codes', 'chaos_creator_applications', 'chaos_creator_log', 'chaos_legal_acceptance',
                  'chaos_pay_payers', 'chaos_coin_orders', 'chaos_coin_payments', 'chaos_discord_state'):
            self.assertEqual(self.policy[n]['action'], 'keep', n)
        for n in ('players', 'chaos_shop_coins', 'chaos_season_players', 'chaos_bank', 'chaos_market_offers'):
            self.assertEqual(self.policy[n]['action'], 'wipe', n)
        for n in ('accounts', 'houses', 'znote_accounts', 'server_config'):
            self.assertEqual(self.policy[n]['action'], 'partial', n)

    def test_cursor_tables_keep_their_ids(self):
        # chaos_discord_state holds a cursor into chaos_bazaar_log; chaos_founder_revokes holds purchase ids
        self.assertTrue(self.policy['chaos_bazaar_log'].get('keep_ids'))
        self.assertTrue(self.policy['chaos_shop_purchases'].get('keep_ids'))
        self.assertTrue(self.policy['players'].get('keep_ids'))

    def test_validator_refuses(self):
        def bad(entry, name='t1'):
            with self.assertRaises(lw.PolicyError):
                lw.validate_policy({'tables': {name: entry}})
        bad({'action': 'maybe', 'reason': 'x'})
        bad({'action': 'wipe'})
        bad({'action': 'wipe', 'reason': ''})
        bad({'action': 'wipe', 'reason': 'two\nlines'})
        bad({'action': 'keep', 'reason': 'x', 'keep_ids': True})
        bad({'action': 'partial', 'reason': 'x'})
        bad({'action': 'partial', 'reason': 'x', 'set': {'a b': 0}})
        bad({'action': 'partial', 'reason': 'x', 'set': {'a': 'zero'}})
        bad({'action': 'partial', 'reason': 'x', 'delete_like': ["x' OR 1=1 --"]})
        bad({'action': 'partial', 'reason': 'x', 'delete_in': ['a;b']})
        bad({'action': 'partial', 'reason': 'x', 'set_rows': {'k': "v'"}})
        bad({'action': 'partial', 'reason': 'x', 'delete_in': ['a']}, name='accounts')
        bad({'action': 'wipe', 'reason': 'x'}, name='bad name;')
        with self.assertRaises(lw.PolicyError):
            lw.validate_policy({'tables': {}})
        with self.assertRaises(lw.PolicyError):
            lw.load_policy(os.path.join(self.tmp, 'missing.json'))

    def test_unknown_tables(self):
        self.assertEqual(lw.unknown_tables(['players', 'zz_new', 'aa_new'], self.policy), ['aa_new', 'zz_new'])
        self.assertEqual(lw.unknown_tables(['players'], self.policy), [])


class SqlTests(Base):
    def info(self):
        return lw.read_info(self.db, self.policy)

    def test_wipe_script_is_one_transaction(self):
        sql = lw.wipe_script(self.policy, self.info())
        lines = sql.splitlines()
        self.assertNotIn('TRUNCATE', sql.upper())
        self.assertEqual(lines.index('START TRANSACTION;') < lines.index('COMMIT;'), True)
        self.assertEqual(sql.count('COMMIT;'), 1)
        self.assertIn('SET SESSION foreign_key_checks = 0;', lines)
        self.assertLess(lines.index('SET SESSION foreign_key_checks = 0;'), lines.index('START TRANSACTION;'))
        self.assertEqual(lines[-1], 'SET SESSION foreign_key_checks = 1;')
        self.assertNotIn('ALTER', sql.upper())

    def test_wipe_script_touches_only_wipe_tables(self):
        sql = lw.wipe_script(self.policy, self.info())
        deleted = set(re.findall(r'^DELETE FROM `([^`]+)`;$', sql, re.M))
        wipe = {n for n, e in self.policy.items() if e['action'] == 'wipe'}
        self.assertEqual(deleted, wipe)
        for n in ('chaos_beta_testers', 'chaos_creator_codes', 'chaos_legal_acceptance', 'chaos_coin_orders',
                  'chaos_coin_payments', 'chaos_pay_payers', 'chaos_admin_log', 'chaos_patchnotes',
                  'chaos_referral_codes', 'chaos_discord_state', 'accounts', 'account_bans'):
            self.assertNotIn('`%s`' % n, sql.replace('UPDATE `accounts`', ''), n)
        self.assertIn('DELETE FROM `players`;', sql)
        self.assertIn('DELETE FROM `chaos_shop_coins`;', sql)

    def test_partial_rules_use_only_existing_columns(self):
        sql = lw.wipe_script(self.policy, self.info())
        self.assertIn('UPDATE `accounts` SET `coins` = 0, `premium_ends_at` = 0;', sql)
        self.assertNotIn('premdays', sql)
        self.assertIn('UPDATE `houses` SET `bid` = 0, `owner` = 0, `paid` = 0;', sql)
        self.assertIn('UPDATE `znote_accounts` SET `points` = 0;', sql)
        self.assertIn("`config` LIKE 'chaos!_season!_%' ESCAPE '!'", sql)
        self.assertIn("`config` IN ('chaos_community_override'", sql)
        self.assertIn("INSERT INTO `server_config` (`config`, `value`) VALUES ('chaos_discord_season', '0')", sql)
        self.assertNotIn('players_record', sql)

    def test_missing_tables_are_skipped(self):
        del self.db.tables['chaos_bank']
        sql = lw.wipe_script(self.policy, self.info())
        self.assertNotIn('chaos_bank`', sql)

    def test_reset_ids(self):
        sql = lw.reset_ids_script(self.policy, self.info())
        altered = set(re.findall(r'ALTER TABLE `([^`]+)`', sql))
        self.assertIn('chaos_bank', altered)
        for n in ('players', 'chaos_bazaar_log', 'chaos_shop_purchases', 'chaos_creator_codes', 'accounts'):
            self.assertNotIn(n, altered)
        self.db.tables['chaos_bank']['auto_increment'] = None
        self.assertNotIn('chaos_bank', lw.reset_ids_script(self.policy, self.info()))

    def test_measure_sql_is_one_statement(self):
        info = self.info()
        sql = lw.measure_sql(lw.measure_items(self.policy, set(info['tables']), info['columns']))
        self.assertTrue(sql.startswith("SELECT 't:"))
        self.assertNotIn(';', sql)


class RefusalTests(Base):
    def facts(self, **over):
        f = {'db': 'chaos_test', 'now': 1000000.0, 'backup': {'file': True, 'size': 10, 'mtime': 1000000.0 - 60},
             'server': [], 'online': 0}
        f.update(over)
        return f

    def reasons(self, confirm='WIPE chaos_test', backup='/x/dump', age=120, **over):
        return lw.refusals(confirm, backup, age, self.facts(**over))

    def test_all_good(self):
        self.assertEqual(self.reasons(), [])

    def test_confirm(self):
        self.assertIn('--confirm must be exactly "WIPE chaos_test"', self.reasons(confirm='WIPE chaos')[0])
        self.assertTrue(self.reasons(confirm=None))
        self.assertTrue(self.reasons(confirm='wipe chaos_test'))
        self.assertTrue(self.reasons(confirm='WIPE chaos_test '))

    def test_backup(self):
        def why(backup, st, age=120):
            return lw.refusals('WIPE chaos_test', backup, age, self.facts(backup=st))
        good = {'file': True, 'size': 9, 'mtime': 1000000.0 - 60}
        self.assertIn('--backup DUMP is required', why(None, good)[0])
        self.assertIn('does not exist', why('/x/none', None)[0])
        self.assertIn('is empty', why('/x/d', dict(good, size=0))[0])
        self.assertIn('is not a regular file', why('/x/d', dict(good, file=False))[0])
        self.assertIn('121 minutes old, the limit is 120', why('/x/d', dict(good, mtime=1000000.0 - 121 * 60))[0])
        self.assertEqual(why('/x/d', dict(good, mtime=1000000.0 - 119 * 60)), [])
        self.assertEqual(why('/x/d', dict(good, mtime=1000000.0 - 200 * 60), age=300), [])

    def test_server_and_players(self):
        self.assertIn('game server is running (unit chaos-server is active)',
                      self.reasons(server=['unit chaos-server is active'])[0])
        self.assertIn('players_online has 2 row(s)', self.reasons(online=2)[0])
        self.assertIn('cannot read players_online', self.reasons(online=None)[0])


class DetectServerTests(Base):
    def proc(self, procs):
        root = os.path.join(self.tmp, 'proc')
        os.makedirs(root, exist_ok=True)
        for pid, name in procs.items():
            os.makedirs(os.path.join(root, str(pid)), exist_ok=True)
            with open(os.path.join(root, str(pid), 'comm'), 'w') as f:
                f.write(name + '\n')
        return root

    def test_stopped(self):
        root = self.proc({1: 'systemd', 22: 'bash'})
        self.assertEqual(lw.detect_server('chaos-server', os.path.join(self.tmp, 'none.pid'), root, lambda u: 'inactive'), [])
        self.assertEqual(lw.detect_server('chaos-server', os.path.join(self.tmp, 'none.pid'), root, lambda u: 'unknown'), [])

    def test_unit_active(self):
        root = self.proc({1: 'systemd'})
        why = lw.detect_server('chaos-server', os.path.join(self.tmp, 'none.pid'), root, lambda u: 'active')
        self.assertEqual(why, ['unit chaos-server is active'])
        self.assertTrue(lw.detect_server('chaos-server', os.path.join(self.tmp, 'none.pid'), root, lambda u: 'activating'))

    def test_pid_file_and_process_scan(self):
        root = self.proc({1: 'systemd', 4242: 'tfs', 77: 'tfs'})
        pidfile = os.path.join(self.tmp, 'server.pid')
        with open(pidfile, 'w') as f:
            f.write('4242\n')
        why = lw.detect_server('chaos-server', pidfile, root, lambda u: 'inactive')
        self.assertEqual(why, ['engine pid 4242 from %s' % pidfile, 'tfs process 77'])
        with open(pidfile, 'w') as f:
            f.write('1\n')  # a pid file naming another program: not the engine
        self.assertEqual(lw.detect_server('chaos-server', pidfile, root, lambda u: 'inactive'), ['tfs process 4242', 'tfs process 77'])


class ClientTests(Base):
    def test_env_parse(self):
        env = lw.parse_env('# c\nexport CHAOS_DB_USER=u1\nCHAOS_DB_PASS="p w\\d"\nCHAOS_DB_NAME=\'n\'\nbad line\nCHAOS_DB_PORT=3307\n')
        self.assertEqual(env['CHAOS_DB_USER'], 'u1')
        self.assertEqual(env['CHAOS_DB_PASS'], 'p w\\d')
        self.assertEqual(env['CHAOS_DB_NAME'], 'n')
        self.assertEqual(env['CHAOS_DB_PORT'], '3307')

    def test_cnf(self):
        text = lw.client_cnf({'CHAOS_DB_HOST': '10.0.0.5', 'CHAOS_DB_PORT': '3307', 'CHAOS_DB_USER': 'u', 'CHAOS_DB_PASS': 'a"b\\c'})
        self.assertIn('host="10.0.0.5"', text)
        self.assertIn('port=3307', text)
        self.assertIn('password="a\\"b\\\\c"', text)
        self.assertIn('socket="/run/m.sock"', lw.client_cnf({'CHAOS_DB_SOCKET': '/run/m.sock', 'CHAOS_DB_HOST': 'x'}))
        self.assertNotIn('host=', lw.client_cnf({'CHAOS_DB_SOCKET': '/run/m.sock'}))

    def test_batch_rows(self):
        self.assertEqual(lw.parse_rows('a\tNULL\t3\nb\\tc\\n\\\\\t\t0\n'), [['a', None, '3'], ['b\tc\n\\', '', '0']])

    def test_password_only_in_the_option_file(self):
        seen = {}

        class P:
            returncode = 0
            stdout = 'x\t1\n'
            stderr = ''

        def fake_run(argv, input=None, **kw):
            seen['argv'] = list(argv)
            seen['input'] = input
            cnf = [a for a in argv if a.startswith('--defaults-extra-file=')][0].split('=', 1)[1]
            seen['cnf'] = cnf
            seen['mode'] = stat.S_IMODE(os.stat(cnf).st_mode)
            with open(cnf) as f:
                seen['cnf_text'] = f.read()
            return P()

        m = lw.Mysql({'CHAOS_DB_PASS': 'S3cret-pass', 'CHAOS_DB_USER': 'u'}, 'chaos_test', mysql_bin='/usr/bin/mysql',
                     run=fake_run)
        self.assertEqual(m.query('SELECT 1'), [['x', '1']])
        self.assertEqual(seen['argv'][0], '/usr/bin/mysql')
        self.assertTrue(seen['argv'][1].startswith('--defaults-extra-file='))
        self.assertNotIn('S3cret-pass', ' '.join(seen['argv']))
        self.assertIn('S3cret-pass', seen['cnf_text'])
        self.assertEqual(seen['mode'], 0o600)
        self.assertEqual(seen['argv'][-1], 'chaos_test')
        self.assertFalse(os.path.exists(seen['cnf']), 'option file removed after the call')
        m.script('DELETE FROM x;', force=True)
        self.assertIn('--force', seen['argv'])

    def test_db_error_has_no_password(self):
        class P:
            returncode = 1
            stdout = ''
            stderr = "ERROR 1045 (28000): Access denied for user 'u'@'localhost'\n"

        m = lw.Mysql({'CHAOS_DB_PASS': 'S3cret-pass'}, 'd', mysql_bin='/usr/bin/mysql', run=lambda *a, **k: P())
        with self.assertRaises(lw.DbError) as cm:
            m.query('SELECT 1')
        self.assertNotIn('S3cret-pass', str(cm.exception))
        self.assertEqual(m.script('X;'), ["ERROR 1045 (28000): Access denied for user 'u'@'localhost'"])


class DryRunTests(Base):
    def test_dry_run_writes_nothing(self):
        code, out, err = run_main(self.args(), self.db)
        self.assertEqual(code, 0, err)
        self.assertEqual(self.db.scripts, [])
        self.assertFalse(os.path.exists(self.baseline))
        self.assertIn('nothing is written', out)
        self.assertRegex(out, r'wipe\s+players\s+3\s+3')
        self.assertRegex(out, r'keep\s+chaos_creator_codes\s+5\s+0')
        self.assertRegex(out, r'partial\s+accounts\s+5\s+4\s+4 row\(s\) to reset: coins=0, premium_ends_at=0')
        self.assertIn('OWNER DECISION', out)
        self.assertIn('owner decisions (the safer action is set):', out)
        self.assertIn('players_record', out)
        self.assertIn('for --execute: server stopped yes; players_online rows 0', out)
        self.assertNotIn('never-printed', out + err)

    def test_dry_run_shows_a_running_server(self):
        code, out, _ = run_main(self.args(), self.db, server_check=lambda: ['unit chaos-server is active'])
        self.assertEqual(code, 0)
        self.assertIn('server stopped NO (unit chaos-server is active)', out)

    def test_dry_run_warns_about_a_non_innodb_wipe_table(self):
        self.db.tables['chaos_bank']['engine'] = 'MyISAM'
        _, out, _ = run_main(self.args(), self.db)
        self.assertIn('warning: chaos_bank is MyISAM, not InnoDB', out)

    def test_unknown_table_exit_2_in_every_mode(self):
        self.db.unknown = ['chaos_brand_new']
        for extra in ([], ['--verify'], ['--execute', '--confirm', 'WIPE chaos_test', '--backup', self.backup]):
            self.db.scripts = []
            code, out, err = run_main(self.args(*extra), self.db)
            self.assertEqual(code, 2, extra)
            self.assertIn('chaos_brand_new', err)
            self.assertEqual(self.db.scripts, [])

    def test_bad_flags_and_missing_files(self):
        code, _, err = run_main(self.args('--verify', '--execute'), self.db)
        self.assertEqual(code, 3)
        code, _, err = run_main(['--env-file', os.path.join(self.tmp, 'nope.env')], self.db)
        self.assertEqual(code, 3)
        self.assertIn('cannot read', err)
        with self.assertRaises(SystemExit) as cm:
            with contextlib.redirect_stderr(io.StringIO()):
                lw.main(['--no-such-flag'], runner=self.db)
        self.assertEqual(cm.exception.code, 3)


class ExecuteTests(Base):
    def test_refusals_change_nothing(self):
        cases = [
            (self.execute_args(confirm='WIPE other'), None, '--confirm must be exactly "WIPE chaos_test"'),
            (self.execute_args(confirm=None), None, '--confirm must be exactly'),
            (self.execute_args(backup=None), None, '--backup DUMP is required'),
            (self.execute_args(backup=os.path.join(self.tmp, 'missing.sql')), None, 'does not exist'),
            (self.execute_args(), ['unit chaos-server is active'], 'the game server is running'),
        ]
        empty = os.path.join(self.tmp, 'empty.sql')
        open(empty, 'w').close()
        os.utime(empty, (1000000.0, 1000000.0))
        cases.append((self.execute_args(backup=empty), None, 'is empty'))
        old = os.path.join(self.tmp, 'old.sql')
        with open(old, 'w') as f:
            f.write('x')
        os.utime(old, (1000000.0 - 3 * 3600, 1000000.0 - 3 * 3600))
        cases.append((self.execute_args(backup=old), None, '180 minutes old, the limit is 120'))
        cases.append((self.execute_args(backup=self.tmp), None, 'is not a regular file'))
        for argv, server, text in cases:
            before = self.db.snapshot()
            code, out, err = run_main(argv, self.db, server_check=(lambda s=server: s or []))
            self.assertEqual(code, 1, (text, err))
            self.assertEqual(err.count('\n'), 1, 'one line')
            self.assertIn('refused:', err)
            self.assertIn(text, err)
            self.assertEqual(self.db.scripts, [])
            self.assertEqual(self.db.snapshot(), before)
            self.assertFalse(os.path.exists(self.baseline))
        self.db.online = 3
        code, _, err = run_main(self.execute_args(), self.db)
        self.assertEqual((code, 'players_online has 3 row(s)' in err, self.db.scripts), (1, True, []))

    def test_rehearsal_copy_ignores_a_running_game(self):
        # --db other than the game's CHAOS_DB_NAME (chaos_test in the env file): the game does not use this database
        self.db.db = 'scratch'
        argv = self.args('--db', 'scratch', '--execute', '--confirm', 'WIPE scratch', '--backup', self.backup)
        code, out, err = run_main(argv, self.db, server_check=lambda: ['unit chaos-server is active'])
        self.assertEqual(code, 0, out + err)
        self.db.db = 'chaos_test'
        code, out, err = run_main(self.execute_args(), self.db, server_check=lambda: ['unit chaos-server is active'])
        self.assertEqual(code, 1)
        self.assertIn('the game server is running', err)

    def test_max_age_flag(self):
        old = os.path.join(self.tmp, 'old.sql')
        with open(old, 'w') as f:
            f.write('x')
        os.utime(old, (1000000.0 - 3 * 3600, 1000000.0 - 3 * 3600))
        code, _, err = run_main(self.execute_args(backup=old) + ['--backup-max-age-minutes', '240'], self.db)
        self.assertEqual(code, 0, err)

    def test_execute_wipes_and_checks(self):
        keep_before = {n: t['rows'] for n, t in self.db.tables.items() if self.policy[n]['action'] == 'keep'}
        code, out, err = run_main(self.execute_args(), self.db)
        self.assertEqual(code, 0, out + err)
        for n, t in self.db.tables.items():
            e = self.policy[n]
            if e['action'] == 'wipe':
                self.assertEqual(t['rows'], 0, n)
            elif e['action'] == 'keep':
                self.assertEqual(t['rows'], keep_before[n], n)
        self.assertEqual(self.db.tables['accounts']['rows'], 5)
        self.assertEqual(self.db.hit, {'accounts': 0, 'houses': 0, 'znote_accounts': 0})
        self.assertEqual(self.db.setrow['chaos_discord_season'], 1)
        self.assertIn('wipe done, every check ok', out)
        self.assertIn('ok   players is empty', out)
        self.assertIn('ok   chaos_beta_testers count unchanged', out)
        self.assertIn('ok   0 owned houses', out)
        self.assertNotIn('never-printed', out + err)
        # ids: reset except keep_ids
        self.assertIn('chaos_bank', self.db.resets)
        for n in ('players', 'chaos_bazaar_log', 'chaos_shop_purchases'):
            self.assertNotIn(n, self.db.resets)
        # baseline file: private, counts before the wipe
        self.assertEqual(stat.S_IMODE(os.stat(self.baseline).st_mode), 0o600)
        with open(self.baseline) as f:
            data = json.load(f)
        self.assertEqual(data['db'], 'chaos_test')
        self.assertEqual(data['counts']['players'], 3)
        self.assertEqual(data['counts']['chaos_creator_codes'], 5)

    def test_second_execute_is_idempotent(self):
        self.assertEqual(run_main(self.execute_args(), self.db)[0], 0)
        snap = self.db.snapshot()
        code, out, err = run_main(self.execute_args(), self.db)
        self.assertEqual(code, 0, out + err)
        self.assertEqual(self.db.snapshot(), snap)

    def test_failure_rolls_back(self):
        self.db.fail_at = 'DELETE FROM `chaos_shop_coins`'
        before = self.db.snapshot()
        code, out, err = run_main(self.execute_args(), self.db)
        self.assertEqual(code, 3)
        self.assertIn('rolled back, nothing changed', err)
        self.assertEqual(self.db.snapshot(), before)
        self.assertEqual(self.db.resets, [])

    def test_failed_id_reset_is_a_warning(self):
        self.db.fail_alter = True
        code, out, err = run_main(self.execute_args(), self.db)
        self.assertEqual(code, 0, out + err)
        self.assertIn('warning: AUTO_INCREMENT reset', err)
        self.assertEqual(self.db.tables['players']['rows'], 0)

    def test_a_check_failure_exits_1_and_names_it(self):
        orig = self.db._apply

        def lossy(buf):
            orig([s for s in buf if '`chaos_bank`' not in s])  # the wipe "forgets" a table

        self.db._apply = lossy
        code, out, err = run_main(self.execute_args(), self.db)
        self.assertEqual(code, 1)
        self.assertIn('FAIL every wipe table is empty', out)
        self.assertIn('not empty: chaos_bank 3', out)
        self.assertIn('checks failed after the wipe', err)

    def test_baseline_not_writable_is_a_warning(self):
        bad = os.path.join(self.tmp, 'file-not-dir', 'b.json')
        open(os.path.join(self.tmp, 'file-not-dir'), 'w').close()
        argv = ['--env-file', self.env, '--baseline', bad, '--execute', '--confirm', 'WIPE chaos_test', '--backup', self.backup]
        code, out, err = run_main(argv, self.db)
        self.assertEqual(code, 0, out + err)
        self.assertIn('baseline not saved', err)


class VerifyTests(Base):
    def wiped(self):
        self.assertEqual(run_main(self.execute_args(), self.db)[0], 0)

    def test_verify_after_execute(self):
        self.wiped()
        scripts = len(self.db.scripts)
        code, out, err = run_main(self.args('--verify'), self.db)
        self.assertEqual(code, 0, out + err)
        self.assertIn('verify ok', out)
        self.assertEqual(len(self.db.scripts), scripts, '--verify writes nothing')

    def test_verify_before_the_wipe_fails(self):
        code, out, err = run_main(self.args('--verify'), self.db)
        self.assertEqual(code, 1)
        self.assertIn('FAIL players is empty', out)
        self.assertIn('FAIL every wipe table is empty', out)
        self.assertIn('not compared: no baseline file', out)
        self.assertIn('verify failed', err)

    def test_verify_catches_each_mismatch(self):
        self.wiped()
        cases = [
            (lambda: self.db.tables['players'].update(rows=1), 'players is empty'),
            (lambda: self.db.tables['accounts'].update(rows=6), 'accounts count unchanged'),
            (lambda: self.db.tables['chaos_beta_testers'].update(rows=4), 'chaos_beta_testers count unchanged'),
            (lambda: self.db.tables['chaos_creator_codes'].update(rows=0), 'every keep and partial table unchanged'),
            (lambda: self.db.tables['chaos_shop_coins'].update(rows=2), '0 coins: chaos_shop_coins empty'),
            (lambda: self.db.hit.update(houses=1), '0 owned houses'),
            (lambda: self.db.hit.update(accounts=2), '0 premium and 0 coins in accounts'),
            (lambda: setattr(self.db, 'dels', 1), 'server_config beta state rows gone'),
            (lambda: self.db.setrow.update(chaos_discord_season=0), 'server_config chaos_discord_season = 0'),
            (lambda: self.db.tables['chaos_bank'].update(rows=1), 'every wipe table is empty'),
        ]
        for mutate, name in cases:
            snap = self.db.snapshot()
            mutate()
            code, out, err = run_main(self.args('--verify'), self.db)
            self.assertEqual(code, 1, name)
            self.assertIn('FAIL ' + name, out)
            self.assertIn(name, err)
            # put it back
            self.db.tables.update({n: dict(self.db.tables[n], rows=r) for n, r in snap[0].items()})
            self.db.hit.update(snap[1])
            self.db.dels = snap[2]
            self.db.setrow.update(snap[3])
        self.assertEqual(run_main(self.args('--verify'), self.db)[0], 0)

    def test_baseline_of_another_database_is_ignored(self):
        self.wiped()
        with open(self.baseline) as f:
            data = json.load(f)
        data['db'] = 'someone_else'
        with open(self.baseline, 'w') as f:
            json.dump(data, f)
        self.assertIsNone(lw.load_baseline(self.baseline, 'chaos_test'))


class RealPolicyShape(Base):
    def test_counts(self):
        acts = [e['action'] for e in self.policy.values()]
        self.assertGreaterEqual(len(acts), 200)
        self.assertGreater(acts.count('wipe'), acts.count('keep'))

    def test_json_is_sorted_and_plain(self):
        with open(POLICY_FILE, encoding='ascii') as f:
            data = json.load(f)
        names = list(data['tables'])
        self.assertEqual(names, sorted(names))


if __name__ == '__main__':
    unittest.main(verbosity=1)
