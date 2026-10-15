#!/usr/bin/env python3
"""Move every character's depot into the stash, offline (server/README.md "Stash", "Depot migration").

usage: python3 -I server/tools/migrate_depot_stash.py SERVER_DIR --server-stopped [--dry-run] [--sql FILE]
                                                      [--db NAME] [--db-host HOST] [--db-port PORT] [--db-user USER]
                                                      [--mysql PATH]

Run it with the game server STOPPED: a running server keeps the depots of the online characters in memory and writes
them back at their next save, which would give those items twice. --server-stopped says you did; without it the tool
only prints what it would do.

In ONE transaction:
  1. chaos_stash_log gets one row per character with the number of items moved (action "migrate_tool")
  2. chaos_stash_items gets one row per item of player_depotitems, except the depot tab boxes themselves
     (depot_config.lua boxIds; their contents move, the empty boxes stay): source "depot", codec "blob" with the
     engine's own attributes column as hex (the same form as item:serializeAttributes, engine patch 0017), tab 0
  3. those items leave player_depotitems
The inbox, the store inbox and the market are not touched. The stash describes and places the rows when the character
next opens it (stash.lua ChaosStash.normalize): plain stacks merge into chaos_stash, every other item goes to its tab,
and what fits no tab goes to the withdraw-only Old depot tab. Nothing is deleted.

Idempotent: a second run finds only what came into a depot since (nothing, while stash_config.lua depot.withdrawOnly
is on) and moves that too. The game itself does the same per character at the first depot locker opening
(ChaosStash.migrateDepot), so the tool is optional; it moves everyone at once, offline.

Rollback: take the database backup made before (server/tools/backup.sh). Without one, the rows of source "depot"
can be put back by hand: their `data` is the hex of player_depotitems.attributes (UNHEX), but the nesting of bags
inside bags is not kept (every item lands loose in the chest of town 1).

The database settings come from SERVER_DIR/config.lua (mysqlDatabase, mysqlHost, mysqlPort, mysqlUser), the password
from CHAOS_DB_PASS, else MYSQL_PWD, else config.lua's mysqlPass; it goes to the mysql client through a temporary
option file (mode 0600), never on the command line. --sql FILE writes the SQL to FILE instead of running it.
"""
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO_SERVER = os.path.dirname(HERE)
DEPOT_CONFIG = os.path.join(REPO_SERVER, 'data', 'scripts', 'chaos', 'depot_config.lua')
STASH_SQL = os.path.join(REPO_SERVER, 'sql', 'chaos_stash.sql')


def read(path):
    with open(path, encoding='utf-8') as f:
        return f.read()


def box_ids(text=None):
    """the depot tab box ids of depot_config.lua (boxIds = {...})"""
    text = read(DEPOT_CONFIG) if text is None else text
    m = re.search(r'boxIds\s*=\s*\{([^}]*)\}', text)
    if not m:
        raise ValueError('depot_config.lua: no boxIds')
    ids = [int(x) for x in re.findall(r'\d+', m.group(1))]
    if not ids:
        raise ValueError('depot_config.lua: boxIds is empty')
    return ids


def config_value(text, key):
    """a config.lua string/number setting; os.getenv("X") or "default" reads the environment"""
    m = re.search(r'^\s*%s\s*=\s*(.+?)\s*(?:--.*)?$' % re.escape(key), text, re.M)
    if not m:
        return None
    expr = m.group(1)
    env = re.match(r'(?:tonumber\(\s*)?os\.getenv\(\s*["\']([^"\']+)["\']\s*\)\s*\)?\s*(?:or\s*(.+))?$', expr)
    if env:
        if os.environ.get(env.group(1)):
            return os.environ[env.group(1)]
        expr = env.group(2) or '""'
    lit = re.match(r'^"([^"]*)"$|^\'([^\']*)\'$|^(\d+)$', expr.strip())
    if not lit:
        return None
    return next(g for g in lit.groups() if g is not None)


def db_settings(server, args):
    cfg = os.path.join(server, 'config.lua')
    text = read(cfg) if os.path.isfile(cfg) else ''
    db = {'host': config_value(text, 'mysqlHost'), 'port': config_value(text, 'mysqlPort'),
          'user': config_value(text, 'mysqlUser'), 'database': config_value(text, 'mysqlDatabase'),
          'password': os.environ.get('CHAOS_DB_PASS') or os.environ.get('MYSQL_PWD') or config_value(text, 'mysqlPass')}
    for key, opt in (('database', '--db'), ('host', '--db-host'), ('port', '--db-port'), ('user', '--db-user')):
        if args.get(opt):
            db[key] = args[opt]
    return db


def migration_sql(boxes):
    """the statements of one run: the tables (chaos_stash.sql), then one transaction"""
    keep = ', '.join(str(int(b)) for b in boxes)
    moving = '`itemtype` NOT IN (%s)' % keep
    return [read(STASH_SQL), '\n'.join([
        'START TRANSACTION;',
        'INSERT INTO `chaos_stash_log` (`player_id`, `action`, `moved`, `overflow`, `kept`, `detail`, `at`)',
        "  SELECT `player_id`, 'migrate_tool', COUNT(*), 0, 0, 'offline', UNIX_TIMESTAMP() FROM `player_depotitems`",
        '  WHERE %s GROUP BY `player_id`;' % moving,
        'INSERT INTO `chaos_stash_items` (`player_id`, `item_id`, `count`, `codec`, `data`, `tab`, `classes`, `name`, `info`,',
        '  `rarity`, `state`, `seq`, `source`, `created_at`)',
        "  SELECT `player_id`, `itemtype`, GREATEST(`count`, 1), 'blob', LOWER(HEX(`attributes`)), 0, '', '', '', 0, 0, 0,",
        "  'depot', UNIX_TIMESTAMP() FROM `player_depotitems` WHERE %s;" % moving,
        'DELETE FROM `player_depotitems` WHERE %s;' % moving,
        'COMMIT;',
        ''])]


def count_sql(boxes):
    keep = ', '.join(str(int(b)) for b in boxes)
    return ('SELECT COUNT(DISTINCT `player_id`), COUNT(*) FROM `player_depotitems` WHERE `itemtype` NOT IN (%s);' % keep)


def parse_args(argv):
    args = {'server': None}
    i = 0
    while i < len(argv):
        a = argv[i]
        if a in ('--dry-run', '--server-stopped'):
            args[a] = True
        elif a in ('--db', '--db-host', '--db-port', '--db-user', '--mysql', '--sql'):
            if i + 1 >= len(argv):
                raise SystemExit('%s needs a value' % a)
            args[a] = argv[i + 1]
            i += 1
        elif a in ('-h', '--help'):
            print(__doc__)
            raise SystemExit(0)
        elif a.startswith('-'):
            raise SystemExit('unknown option %s' % a)
        elif args['server'] is None:
            args['server'] = a
        else:
            raise SystemExit('one SERVER_DIR only')
        i += 1
    if not args['server']:
        raise SystemExit(__doc__)
    return args


def run_mysql(mysql, db, statements):
    fd, opt = tempfile.mkstemp(prefix='chaos_my_', suffix='.cnf')
    try:
        os.chmod(opt, 0o600)
        with os.fdopen(fd, 'w') as f:
            f.write('[client]\n')
            for key in ('host', 'port', 'user', 'password'):
                if db.get(key) not in (None, ''):
                    f.write('%s="%s"\n' % (key, str(db[key]).replace('\\', '\\\\').replace('"', '\\"')))
        base = [mysql, '--defaults-extra-file=' + opt, '--batch', '--skip-column-names', db['database']]
        out = []
        for sql in statements:
            proc = subprocess.run(base, input=sql.encode('utf-8'), stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
            text = proc.stdout.decode('utf-8', 'replace').strip()
            if proc.returncode != 0:
                return False, text
            out.append(text)
        return True, '\n'.join(t for t in out if t)
    finally:
        os.unlink(opt)


def main(argv):
    args = parse_args(argv)
    boxes = box_ids()
    statements = migration_sql(boxes)
    if args.get('--sql'):
        with open(args['--sql'], 'w', encoding='utf-8') as f:
            f.write('\n'.join(statements))
        print('wrote %s (%d depot box ids kept: %d..%d)' % (args['--sql'], len(boxes), min(boxes), max(boxes)))
        return 0
    db = db_settings(args['server'], args)
    if not db.get('database'):
        print('no database name (config.lua mysqlDatabase or --db)')
        return 1
    mysql = args.get('--mysql', 'mysql')
    if not shutil.which(mysql):
        print('mysql client not found (%s); install it or pass --mysql PATH' % mysql)
        return 1
    ok, counts = run_mysql(mysql, db, [count_sql(boxes)])
    if not ok:
        print('cannot read player_depotitems: %s' % counts)
        return 1
    print('depot items to move: %s (characters, items)' % (counts.replace('\t', ', ') or '0, 0'))
    if args.get('--dry-run') or not args.get('--server-stopped'):
        if not args.get('--dry-run'):
            print('nothing changed: stop the game server first and pass --server-stopped')
        return 0
    ok, out = run_mysql(mysql, db, statements)
    if not ok:
        print('the migration failed and was rolled back: %s' % out)
        return 1
    print('moved into chaos_stash_items (source "depot"); the stash places them at each character\'s next opening')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
