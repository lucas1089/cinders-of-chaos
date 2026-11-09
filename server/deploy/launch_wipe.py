#!/usr/bin/env python3
"""Launch wipe (O438): the beta wipe of docs/BETA.md section 9, as a tool with a policy and a test.

Run as root on the game server, with the game stopped and a fresh backup. Python 3 standard library, the mysql client.

usage: python3 -I launch_wipe.py                       dry run (default): per table the action, the rows now, the rows
                                                       that would go, the owner decisions; nothing is written
       python3 -I launch_wipe.py --verify              only the checks of section 9 step 6
       python3 -I launch_wipe.py --execute --confirm "WIPE <database>" --backup DUMP
                                [--backup-max-age-minutes 120] [--baseline FILE]
options: --env-file FILE (default CHAOS_ENV or /etc/chaos/chaos.env: CHAOS_DB_* like chaos-ctl.sh and backup.sh)
         --db NAME (default CHAOS_DB_NAME)  --policy FILE (default launch_wipe_tables.json next to this file)

The policy (launch_wipe_tables.json) names every table once: wipe (DELETE every row), keep (never touched) or partial
(a named rule: accounts, houses, znote_accounts, server_config). A table in the database that the policy does not name
stops the tool with exit code 2 and the list: a new table needs a decision.

--execute refuses (one line on stderr, exit 1, nothing changed) unless: --confirm is exactly "WIPE <database>" for the
real database name; --backup is an existing non-empty file modified within --backup-max-age-minutes; the game server is
not running (the unit, the engine's pid file, any tfs process; not checked for a rehearsal copy: --db other than the
game's CHAOS_DB_NAME) and players_online is empty. The wipe is one transaction
of DELETE and UPDATE statements with FOREIGN_KEY_CHECKS off, so a failure rolls everything back. Afterwards the tool
resets AUTO_INCREMENT of the wiped tables (a failure there is a warning), then runs the checks and exits 1 naming any
mismatch. The row counts before the wipe go to --baseline (default /var/lib/chaos/launch-wipe-<db>.json) so that
--verify can compare the kept tables later.

Exit: 0 ok, 1 refused or a check failed, 2 unknown table(s), 3 setup or database error (the wipe rolled back).
"""
import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_POLICY = os.path.join(HERE, 'launch_wipe_tables.json')
DEFAULT_ENV = '/etc/chaos/chaos.env'
ACTIONS = ('wipe', 'keep', 'partial')
IDENT = re.compile(r'^[A-Za-z0-9_]+$')
PATTERN = re.compile(r'^[A-Za-z0-9_%]+$')
VALUE = re.compile(r'^[A-Za-z0-9_.-]*$')
ESC = '!'


class PolicyError(Exception):
    pass


class DbError(Exception):
    pass


# ---------------------------------------------------------------- policy

def validate_policy(data):
    """the decoded JSON -> {table: entry}; PolicyError on anything that is not one explicit, safe decision"""
    if not isinstance(data, dict) or not isinstance(data.get('tables'), dict) or not data['tables']:
        raise PolicyError('policy: no "tables" object')
    out = {}
    for name, e in data['tables'].items():
        if not IDENT.match(name):
            raise PolicyError('policy: bad table name %r' % name)
        if not isinstance(e, dict) or e.get('action') not in ACTIONS:
            raise PolicyError('policy: %s needs an action of %s' % (name, '/'.join(ACTIONS)))
        reason = e.get('reason')
        if not isinstance(reason, str) or not reason.strip() or '\n' in reason:
            raise PolicyError('policy: %s needs a one-line reason' % name)
        if e.get('owner_decision') not in (None, True, False):
            raise PolicyError('policy: %s owner_decision must be true or false' % name)
        if e.get('keep_ids') and e['action'] != 'wipe':
            raise PolicyError('policy: %s keep_ids only on a wipe table' % name)
        if e['action'] == 'partial':
            ok = False
            for col, val in (e.get('set') or {}).items():
                if not IDENT.match(col) or not isinstance(val, int) or isinstance(val, bool):
                    raise PolicyError('policy: %s set %r' % (name, col))
                ok = True
            for pat in e.get('delete_like') or []:
                if not PATTERN.match(pat):
                    raise PolicyError('policy: %s delete_like %r' % (name, pat))
                ok = True
            for key in e.get('delete_in') or []:
                if not IDENT.match(key):
                    raise PolicyError('policy: %s delete_in %r' % (name, key))
                ok = True
            for key, val in (e.get('set_rows') or {}).items():
                if not IDENT.match(key) or not isinstance(val, str) or not VALUE.match(val):
                    raise PolicyError('policy: %s set_rows %r' % (name, key))
                ok = True
            if not ok:
                raise PolicyError('policy: %s is partial and has no rule' % name)
            if (e.get('delete_like') or e.get('delete_in') or e.get('set_rows')) and name != 'server_config':
                raise PolicyError('policy: row rules only for server_config')
        out[name] = e
    return out


def load_policy(path):
    try:
        with open(path, encoding='utf-8') as f:
            data = json.load(f)
    except (OSError, ValueError) as err:
        raise PolicyError('policy: cannot read %s: %s' % (path, err))
    return validate_policy(data)


def unknown_tables(db_tables, policy):
    """the tables of the database that the policy does not name (fail closed)"""
    return sorted(t for t in db_tables if t not in policy)


# ---------------------------------------------------------------- environment and the mysql client

def parse_env(text):
    """the KEY=VALUE lines of chaos.env (comments, 'export', quotes) -> dict"""
    env = {}
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        if line.startswith('export '):
            line = line[7:].lstrip()
        if '=' not in line:
            continue
        key, _, val = line.partition('=')
        key, val = key.strip(), val.strip()
        if len(val) >= 2 and val[0] == val[-1] and val[0] in '"\'':
            val = val[1:-1]
        if IDENT.match(key):
            env[key] = val
    return env


def ini_quote(s):
    return s.replace('\\', '\\\\').replace('"', '\\"')


def client_cnf(env):
    """the option file text: the password goes here, never on a command line"""
    lines = ['[client]']
    sock = env.get('CHAOS_DB_SOCKET', '')
    if sock:
        lines.append('socket="%s"' % ini_quote(sock))
    else:
        lines.append('host="%s"' % ini_quote(env.get('CHAOS_DB_HOST') or '127.0.0.1'))
        lines.append('port=%d' % int(env.get('CHAOS_DB_PORT') or 3306))
    lines.append('user="%s"' % ini_quote(env.get('CHAOS_DB_USER') or 'chaos'))
    if env.get('CHAOS_DB_PASS'):
        lines.append('password="%s"' % ini_quote(env['CHAOS_DB_PASS']))
    return '\n'.join(lines) + '\n'


def unescape_batch(s):
    """one field of mysql --batch output: NULL, \\t \\n \\\\ \\0"""
    if s == 'NULL':
        return None
    if '\\' not in s:
        return s
    return re.sub(r'\\(.)', lambda m: {'t': '\t', 'n': '\n', '0': '\0', '\\': '\\'}.get(m.group(1), m.group(1)), s)


def parse_rows(text):
    return [[unescape_batch(f) for f in line.split('\t')] for line in text.splitlines() if line != '']


def find_mysql(env, which=None):
    import shutil
    which = which or shutil.which
    want = env.get('CHAOS_MYSQL')
    for c in ([want] if want else []) + ['mysql', 'mariadb']:
        if c and which(c):
            return which(c)
    raise DbError('no mysql client (set CHAOS_MYSQL)')


class Mysql:
    """query(sql) -> rows, script(sql) -> None. The password is in a 0600 option file during each call only."""

    def __init__(self, env, db, mysql_bin=None, run=subprocess.run):
        self.env, self.db, self.run = env, db, run
        self.mysql = mysql_bin or find_mysql(env)

    def _call(self, sql, force=False):
        fd, cnf = tempfile.mkstemp(prefix='launch-wipe-', suffix='.cnf')
        try:
            with os.fdopen(fd, 'w') as f:
                f.write(client_cnf(self.env))
            argv = [self.mysql, '--defaults-extra-file=' + cnf, '--batch', '--skip-column-names',
                    '--default-character-set=utf8mb4']
            if force:
                argv.append('--force')
            argv.append(self.db)
            p = self.run(argv, input=sql, stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True)
        except OSError as err:
            raise DbError('cannot run %s: %s' % (self.mysql, err))
        finally:
            try:
                os.unlink(cnf)
            except OSError:
                pass
        return p

    def query(self, sql):
        p = self._call(sql)
        if p.returncode != 0:
            raise DbError(first_line(p.stderr) or 'mysql failed')
        return parse_rows(p.stdout)

    def script(self, sql, force=False):
        """run a script; returns the error lines (empty = ok). Without force the first error ends it (exit != 0)."""
        p = self._call(sql, force)
        errs = [l for l in (p.stderr or '').splitlines() if l.startswith('ERROR')]
        if p.returncode != 0 and not errs:
            errs = [first_line(p.stderr) or 'mysql failed']
        return errs


def first_line(text):
    for line in (text or '').splitlines():
        if line.strip():
            return line.strip()
    return ''


# ---------------------------------------------------------------- SQL text (pure)

def tables_sql():
    return ("SELECT table_name, engine, auto_increment FROM information_schema.tables "
            "WHERE table_schema = DATABASE() AND table_type <> 'VIEW' ORDER BY table_name")


def columns_sql(names):
    return ("SELECT table_name, column_name FROM information_schema.columns WHERE table_schema = DATABASE() "
            "AND table_name IN (%s)" % ', '.join("'%s'" % n for n in sorted(names)))


def like_sql(pat):
    return "`config` LIKE '%s' ESCAPE '%s'" % (pat.replace('_', ESC + '_'), ESC)


def delete_where(entry):
    """the server_config rows a partial rule deletes"""
    parts = [like_sql(p) for p in entry.get('delete_like') or []]
    keys = entry.get('delete_in') or []
    if keys:
        parts.append('`config` IN (%s)' % ', '.join("'%s'" % k for k in keys))
    return ' OR '.join(parts)


def partial_columns(entry, existing):
    """[(column, value)] of the set rule that exist in this schema"""
    return [(c, v) for c, v in sorted((entry.get('set') or {}).items()) if c in existing]


def measure_items(policy, present, columns):
    """[(label, 'FROM ... [WHERE ...]')]: t:T rows, hit:T rows a partial rule still has to change, del:T rows a delete
    rule matches, set:T:K 1 when a set row already has its value"""
    items = [('t:' + n, 'FROM `%s`' % n) for n in sorted(present)]
    for name in sorted(policy):
        e = policy[name]
        if e['action'] != 'partial' or name not in present:
            continue
        cols = partial_columns(e, columns.get(name, ()))
        if cols:
            items.append(('hit:' + name, 'FROM `%s` WHERE %s' % (
                name, ' OR '.join('NOT (`%s` <=> %d)' % (c, v) for c, v in cols))))
        if e.get('delete_like') or e.get('delete_in'):
            items.append(('del:' + name, 'FROM `%s` WHERE %s' % (name, delete_where(e))))
        for key, val in sorted((e.get('set_rows') or {}).items()):
            items.append(('set:%s:%s' % (name, key),
                          "FROM `%s` WHERE `config` = '%s' AND `value` = '%s'" % (name, key, val)))
    return items


def measure_sql(items):
    return ' UNION ALL '.join("SELECT '%s', COUNT(*) %s" % (label, frm) for label, frm in items)


def wipe_script(policy, info):
    """the one transaction: DELETE of every wipe table, the partial rules, then COMMIT. Only tables the database has."""
    lines = ['SET SESSION sql_safe_updates = 0;', 'SET SESSION foreign_key_checks = 0;',
             'SET SESSION innodb_lock_wait_timeout = 120;', 'START TRANSACTION;']
    for name in sorted(policy):
        e = policy[name]
        if name not in info['tables']:
            continue
        if e['action'] == 'wipe':
            lines.append('DELETE FROM `%s`;' % name)
        elif e['action'] == 'partial':
            cols = partial_columns(e, info['columns'].get(name, ()))
            if cols:
                lines.append('UPDATE `%s` SET %s;' % (name, ', '.join('`%s` = %d' % cv for cv in cols)))
            if e.get('delete_like') or e.get('delete_in'):
                lines.append('DELETE FROM `%s` WHERE %s;' % (name, delete_where(e)))
            for key, val in sorted((e.get('set_rows') or {}).items()):
                lines.append("INSERT INTO `%s` (`config`, `value`) VALUES ('%s', '%s') "
                             "ON DUPLICATE KEY UPDATE `value` = VALUES(`value`);" % (name, key, val))
    lines += ['COMMIT;', 'SET SESSION foreign_key_checks = 1;']
    return '\n'.join(lines) + '\n'


def reset_ids_script(policy, info):
    """ALTER TABLE ... AUTO_INCREMENT = 1 for the wipe tables that have a counter, unless keep_ids"""
    out = []
    for name in sorted(policy):
        e = policy[name]
        t = info['tables'].get(name)
        if e['action'] == 'wipe' and t and t['auto_increment'] is not None and not e.get('keep_ids'):
            out.append('ALTER TABLE `%s` AUTO_INCREMENT = 1;' % name)
    return '\n'.join(out) + ('\n' if out else '')


# ---------------------------------------------------------------- reading the database

def read_info(runner, policy):
    """tables (engine, auto_increment), the columns of the partial tables, and every measure"""
    tables = {}
    for r in runner.query(tables_sql()):
        tables[r[0]] = {'engine': r[1], 'auto_increment': None if r[2] in (None, '') else int(r[2])}
    part = [n for n, e in policy.items() if e['action'] == 'partial' and n in tables]
    columns = {}
    if part:
        for t, c in runner.query(columns_sql(part)):
            columns.setdefault(t, set()).add(c)
    known = {n: v for n, v in tables.items() if n in policy}
    items = measure_items(policy, set(known), columns)
    measures = {}
    if items:
        for label, n in runner.query(measure_sql(items)):
            measures[label] = int(n)
    return {'tables': tables, 'columns': columns, 'measures': measures}


def count(info, name):
    return info['measures'].get('t:' + name)


# ---------------------------------------------------------------- plan (dry run)

def build_plan(policy, info):
    rows, warnings, absent = [], [], []
    for name in sorted(policy):
        e = policy[name]
        if name not in info['tables']:
            absent.append(name)
            continue
        now = count(info, name)
        goes, detail = 0, ''
        if e['action'] == 'wipe':
            goes = now
            if now and (info['tables'][name]['engine'] or '').lower() != 'innodb':
                warnings.append('%s is %s, not InnoDB: a rollback would not undo its DELETE' % (
                    name, info['tables'][name]['engine']))
            detail = 'ids kept' if e.get('keep_ids') else ''
        elif e['action'] == 'partial':
            cols = partial_columns(e, info['columns'].get(name, ()))
            parts = []
            if cols:
                hit = info['measures'].get('hit:' + name, 0)
                goes += hit
                parts.append('%d row(s) to reset: %s' % (hit, ', '.join('%s=%d' % cv for cv in cols)))
            elif e.get('set'):
                warnings.append('%s: none of the columns %s exist; nothing to reset' % (name, ', '.join(sorted(e['set']))))
            if e.get('delete_like') or e.get('delete_in'):
                dels = info['measures'].get('del:' + name, 0)
                goes += dels
                parts.append('%d row(s) deleted' % dels)
            for key in sorted(e.get('set_rows') or {}):
                already = info['measures'].get('set:%s:%s' % (name, key), 0)
                if not already:
                    goes += 1
                parts.append('%s set to %s%s' % (key, e['set_rows'][key], ' (already)' if already else ''))
            detail = '; '.join(parts)
        rows.append({'name': name, 'action': e['action'], 'now': now, 'goes': goes, 'detail': detail,
                     'reason': e['reason'], 'owner': bool(e.get('owner_decision')), 'note': e.get('owner_note', '')})
    return {'rows': rows, 'warnings': warnings, 'absent': absent}


def render_plan(plan, db):
    w = max([len(r['name']) for r in plan['rows']] + [5])
    out = ['launch wipe dry run, database %s: nothing is written' % db,
           '%-8s %-*s %10s %10s  %s' % ('action', w, 'table', 'rows now', 'rows go', 'note')]
    for r in plan['rows']:
        note = r['detail'] or r['reason']
        if r['owner']:
            note = (note + '; ' if r['detail'] else '') + 'OWNER DECISION: ' + (r['note'] or r['reason'])
        out.append('%-8s %-*s %10d %10d  %s' % (r['action'], w, r['name'], r['now'], r['goes'], note))
    tot = {a: sum(1 for r in plan['rows'] if r['action'] == a) for a in ACTIONS}
    out.append('')
    out.append('%d tables: %d wipe (%d rows go), %d keep, %d partial; %d policy table(s) not in this database' % (
        len(plan['rows']), tot['wipe'], sum(r['goes'] for r in plan['rows'] if r['action'] == 'wipe'),
        tot['keep'], tot['partial'], len(plan['absent'])))
    owner = [r for r in plan['rows'] if r['owner']]
    if owner:
        out.append('owner decisions (the safer action is set):')
        for r in owner:
            out.append('  %s %s: %s' % (r['action'], r['name'], r['note'] or r['reason']))
    for wmsg in plan['warnings']:
        out.append('warning: ' + wmsg)
    return '\n'.join(out)


# ---------------------------------------------------------------- refusals (pure)

def backup_problems(path, max_age_minutes, st, now):
    """st: None (missing) or {'file': bool, 'size': int, 'mtime': float}"""
    if not path:
        return ['--backup DUMP is required']
    if st is None:
        return ['backup file %s does not exist' % path]
    if not st['file']:
        return ['backup %s is not a regular file' % path]
    if st['size'] <= 0:
        return ['backup file %s is empty' % path]
    age = (now - st['mtime']) / 60.0
    if age > max_age_minutes:
        return ['backup file %s is %d minutes old, the limit is %d (make a new one: backup.sh)' % (
            path, age, max_age_minutes)]
    return []


def refusals(confirm, backup, max_age, facts):
    """the reasons --execute refuses, first one first. facts: db, now, backup (stat), server (list), online (int|None)"""
    out = []
    want = 'WIPE ' + facts['db']
    if confirm != want:
        out.append('--confirm must be exactly "%s"' % want)
    out += backup_problems(backup, max_age, facts['backup'], facts['now'])
    if facts['server']:
        out.append('the game server is running (%s): stop it first (Painel > Servidor)' % '; '.join(facts['server']))
    if facts['online'] is None:
        out.append('cannot read players_online')
    elif facts['online'] > 0:
        out.append('players_online has %d row(s)' % facts['online'])
    return out


def stat_backup(path, stat=os.stat):
    try:
        s = stat(path)
    except (OSError, TypeError, ValueError):
        return None
    import stat as st
    return {'file': st.S_ISREG(s.st_mode), 'size': s.st_size, 'mtime': s.st_mtime}


def detect_server(unit, pidfile, proc='/proc', systemctl=None):
    """why the game server counts as running, like chaos-ctl.sh status: the unit, the engine's pid file, any tfs process"""
    why = []
    if systemctl is None:
        def systemctl(u):
            try:
                p = subprocess.run(['systemctl', 'is-active', u], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                                   universal_newlines=True)
                return p.stdout.strip()
            except OSError:
                return 'unknown'
    state = systemctl(unit)
    if state in ('active', 'activating', 'reloading', 'deactivating'):
        why.append('unit %s is %s' % (unit, state))
    try:
        with open(pidfile) as f:
            pid = re.sub(r'\D', '', f.read(20))
    except OSError:
        pid = ''
    if pid and comm(proc, pid) == 'tfs':
        why.append('engine pid %s from %s' % (pid, pidfile))
    try:
        names = os.listdir(proc)
    except OSError:
        names = []
    for n in sorted(x for x in names if x.isdigit()):
        if n != pid and comm(proc, n) == 'tfs':
            why.append('tfs process %s' % n)
    return why


def comm(proc, pid):
    try:
        with open(os.path.join(proc, pid, 'comm')) as f:
            return f.read().strip()
    except OSError:
        return ''


# ---------------------------------------------------------------- checks (section 9 step 6)

def evaluate(policy, info, baseline):
    """[(name, ok, detail)]. baseline: {table: rows before the wipe} or None (kept tables are then not compared)."""
    out = []

    def add(name, ok, detail=''):
        out.append((name, bool(ok), detail))

    def table_zero(name, label):
        n = count(info, name)
        add(label, n == 0, 'missing table' if n is None else '%d row(s)' % n)

    table_zero('players', 'players is empty')
    table_zero('players_online', 'players_online is empty')
    if baseline is None:
        add('kept tables and accounts unchanged', True, 'not compared: no baseline file (run --execute first)')
    else:
        keep = [n for n in sorted(policy) if n in info['tables'] and (policy[n]['action'] == 'keep' or
                                                                       policy[n]['action'] == 'partial')]
        for must in ('accounts', 'chaos_beta_testers'):
            if must in info['tables']:
                add('%s count unchanged' % must, baseline.get(must) == count(info, must),
                    '%s before, %s now' % (baseline.get(must), count(info, must)))
        bad = []
        for n in keep:
            if n == 'server_config':
                continue
            if n in baseline and baseline[n] != count(info, n):
                bad.append('%s %s -> %s' % (n, baseline[n], count(info, n)))
        add('every keep and partial table unchanged', not bad, '%d table(s) compared%s' % (
            len(keep), ('; changed: ' + ', '.join(bad)) if bad else ''))
    wiped = [n for n in sorted(policy) if policy[n]['action'] == 'wipe' and n in info['tables']]
    left = ['%s %d' % (n, count(info, n)) for n in wiped if count(info, n)]
    add('every wipe table is empty', not left, '%d table(s)%s' % (len(wiped), ('; not empty: ' + ', '.join(left)) if left else ''))
    coin = count(info, 'chaos_shop_coins')
    add('0 coins: chaos_shop_coins empty', coin in (None, 0), '%s row(s)' % coin)
    for name in sorted(policy):
        e = policy[name]
        if e['action'] != 'partial' or name not in info['tables']:
            continue
        cols = partial_columns(e, info['columns'].get(name, ()))
        if cols:
            hit = info['measures'].get('hit:' + name, 0)
            label = {'accounts': '0 premium and 0 coins in accounts', 'znote_accounts': '0 points in znote_accounts',
                     'houses': '0 owned houses (owner, rent, bids cleared)'}.get(name, '%s reset' % name)
            add(label, hit == 0, '%d row(s) not reset' % hit)
        if e.get('delete_like') or e.get('delete_in'):
            n = info['measures'].get('del:' + name, 0)
            add('%s beta state rows gone' % name, n == 0, '%d row(s) left' % n)
        for key, val in sorted((e.get('set_rows') or {}).items()):
            ok = info['measures'].get('set:%s:%s' % (name, key), 0) == 1
            add('%s %s = %s' % (name, key, val), ok, 'set' if ok else 'not set')
    return out


def render_checks(checks):
    return '\n'.join('%s %s: %s' % ('ok  ' if ok else 'FAIL', name, detail) for name, ok, detail in checks)


# ---------------------------------------------------------------- baseline file

def baseline_path(arg, db):
    return arg or '/var/lib/chaos/launch-wipe-%s.json' % re.sub(r'[^A-Za-z0-9_.-]', '_', db)


def save_baseline(path, db, info, now):
    data = {'db': db, 'at': int(now), 'counts': {n[2:]: v for n, v in info['measures'].items() if n.startswith('t:')}}
    try:
        d = os.path.dirname(path)
        if d:
            os.makedirs(d, mode=0o700, exist_ok=True)
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, 'w') as f:
            json.dump(data, f, sort_keys=True)
        return None
    except OSError as err:
        return 'baseline not saved (%s): --verify will not compare the kept tables' % err


def load_baseline(path, db):
    try:
        with open(path) as f:
            data = json.load(f)
    except (OSError, ValueError):
        return None
    if not isinstance(data, dict) or data.get('db') != db or not isinstance(data.get('counts'), dict):
        return None
    return data['counts']


# ---------------------------------------------------------------- main

class Parser(argparse.ArgumentParser):
    def error(self, message):
        sys.stderr.write('launch_wipe: %s\n' % message)
        sys.exit(3)


def make_parser():
    p = Parser(prog='launch_wipe.py', description='Launch wipe (O438). Dry run unless --execute or --verify.')
    p.add_argument('--env-file', default=None)
    p.add_argument('--db', default=None)
    p.add_argument('--policy', default=DEFAULT_POLICY)
    p.add_argument('--verify', action='store_true')
    p.add_argument('--execute', action='store_true')
    p.add_argument('--confirm', default=None)
    p.add_argument('--backup', default=None)
    p.add_argument('--backup-max-age-minutes', type=int, default=120)
    p.add_argument('--baseline', default=None)
    return p


def say(msg):
    sys.stdout.write(msg + '\n')


def die(code, msg):
    sys.stderr.write('launch_wipe: %s\n' % msg)
    return code


def main(argv=None, runner=None, now=None, server_check=None, environ=None):
    args = make_parser().parse_args(argv)
    environ = os.environ if environ is None else environ
    if args.verify and args.execute:
        return die(3, '--verify and --execute are separate modes')
    now = time.time() if now is None else now
    try:
        policy = load_policy(args.policy)
    except PolicyError as err:
        return die(3, str(err))
    env_path = args.env_file or environ.get('CHAOS_ENV') or DEFAULT_ENV
    try:
        with open(env_path, encoding='utf-8') as f:
            env = parse_env(f.read())
    except OSError as err:
        return die(3, 'cannot read %s: %s' % (env_path, err))
    for k in ('CHAOS_MYSQL',):
        if environ.get(k):
            env.setdefault(k, environ[k])
    dbname = args.db or env.get('CHAOS_DB_NAME') or 'chaos'
    if not IDENT.match(dbname):
        return die(3, 'bad database name')
    try:
        if runner is None:
            runner = Mysql(env, dbname)
        rows = runner.query('SELECT DATABASE()')
        db = rows[0][0] if rows and rows[0] else None
        if not db:
            return die(3, 'no database selected')
        unknown = unknown_tables([r[0] for r in runner.query(tables_sql())], policy)
        if unknown:
            sys.stderr.write('launch_wipe: %d table(s) in %s that launch_wipe_tables.json does not name; add each '
                             'with wipe, keep or partial and a reason:\n' % (len(unknown), db))
            for t in unknown:
                sys.stderr.write('  %s\n' % t)
            return 2
        info = read_info(runner, policy)
        bpath = baseline_path(args.baseline, db)
        if args.verify:
            checks = evaluate(policy, info, load_baseline(bpath, db))
            say(render_checks(checks))
            bad = [c for c in checks if not c[1]]
            if bad:
                return die(1, 'verify failed: ' + '; '.join(c[0] for c in bad))
            say('verify ok')
            return 0
        unit = env.get('CHAOS_UNIT') or environ.get('CHAOS_UNIT') or 'chaos-server'
        root = env.get('CHAOS_ROOT') or environ.get('CHAOS_ROOT') or '/opt/chaos'
        pidfile = env.get('CHAOS_PID_FILE') or environ.get('CHAOS_PID_FILE') or os.path.join(root, 'run', 'server.pid')
        server = (server_check or (lambda: detect_server(unit, pidfile)))()
        # a rehearsal on a copy (--db other than the game's CHAOS_DB_NAME) does not care whether the game runs
        game_db = env.get('CHAOS_DB_NAME') or 'chaos'
        if db != game_db:
            server = []
        orows = runner.query('SELECT COUNT(*) FROM `players_online`') if 'players_online' in info['tables'] else []
        online = int(orows[0][0]) if orows else None
        if not args.execute:
            plan = build_plan(policy, info)
            say(render_plan(plan, db))
            say('')
            say('for --execute: server stopped %s; players_online rows %s' % (
                'NO (%s)' % '; '.join(server) if server else ('yes' if db == game_db else 'not checked: %s is not the game database %s' % (db, game_db)), online))
            say('next: python3 -I launch_wipe.py --execute --confirm "WIPE %s" --backup DUMP' % db)
            return 0
        facts = {'db': db, 'now': now, 'backup': stat_backup(args.backup), 'server': server, 'online': online}
        why = refusals(args.confirm, args.backup, args.backup_max_age_minutes, facts)
        if why:
            return die(1, 'refused: ' + why[0])
        warn = save_baseline(bpath, db, info, now)
        if warn:
            sys.stderr.write('launch_wipe: warning: %s\n' % warn)
        errs = runner.script(wipe_script(policy, info))
        if errs:
            return die(3, 'the wipe failed and was rolled back, nothing changed: ' + errs[0])
        say('wiped: %d wipe tables emptied, partial rules applied, committed' % sum(
            1 for n, e in policy.items() if e['action'] == 'wipe' and n in info['tables']))
        resets = reset_ids_script(policy, info)
        if resets:
            rerrs = runner.script(resets, force=True)
            for e in rerrs:
                sys.stderr.write('launch_wipe: warning: AUTO_INCREMENT reset: %s\n' % e)
            say('AUTO_INCREMENT reset on %d table(s)%s' % (resets.count('\n'), ' (%d warning(s))' % len(rerrs) if rerrs else ''))
        after = read_info(runner, policy)
        before = {n[2:]: v for n, v in info['measures'].items() if n.startswith('t:')}
        checks = evaluate(policy, after, before)
        say(render_checks(checks))
        bad = [c for c in checks if not c[1]]
        if bad:
            return die(1, 'checks failed after the wipe: ' + '; '.join(c[0] for c in bad))
        say('wipe done, every check ok. Next: BETA.md section 9 step 7 (beta switch off, launch install).')
        return 0
    except DbError as err:
        return die(3, 'database error: %s' % err)


if __name__ == '__main__':
    sys.exit(main())
