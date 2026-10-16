#!/usr/bin/env python3
"""Test of fresh_db_check.py and patch_base_migrations.py: a made-up server folder whose schema already has the
columns its migrations add (the base server's state: schema.sql at db_version 33 with the columns of 33-40) and a
migration on a table that is missing (41, the website's znote_shop_orders).
  * the stock migrations on a fresh database: the check reports the "Duplicate column" and "doesn't exist" errors
    (exit 1), as the engine printed them at the first start (start log 2026-10-16)
  * after patch_base_migrations.py: no error, db_version runs to the file that returns false (exit 0); a column the
    schema lacks is still added; a second patch run changes nothing
  * the website tables (server/sql/chaos_website_tables.sql) load and the shop orders get their mountid column
The pure rewrite is checked without a database; the database part needs MariaDB (mariadb-install-db, mariadbd) and
luajit or lua5.3, and is skipped without them.
Run: python3 -I server/tools/fresh_db_check_test.py"""
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
CHECK = os.path.join(HERE, 'fresh_db_check.py')
PATCH = os.path.join(HERE, 'patch_base_migrations.py')
WEB_SQL = os.path.join(REPO, 'server', 'sql', 'chaos_website_tables.sql')
sys.path.insert(0, HERE)
import patch_base_migrations as M  # noqa: E402

fails = []


def check(cond, what):
    if not cond:
        fails.append(what)
        print('FAIL ' + what)


SCHEMA = '''CREATE TABLE `server_config` (`config` varchar(50) NOT NULL, `value` varchar(256) NOT NULL DEFAULT '',
  PRIMARY KEY (`config`)) ENGINE=InnoDB;
INSERT INTO `server_config` (`config`, `value`) VALUES ('db_version', '5');
CREATE TABLE `players` (`id` int NOT NULL AUTO_INCREMENT, `name` varchar(255) NOT NULL,
  `skill_a` int unsigned NOT NULL DEFAULT 10, `skill_a_tries` bigint unsigned NOT NULL DEFAULT 0,
  `wings_id` int(11) NOT NULL DEFAULT 0, PRIMARY KEY (`id`)) ENGINE=InnoDB;
'''
MIGRATIONS = {
    5: 'function onUpdateDatabase()\n\tprint("> Updating database to version 5 (skill a)")\n'
       '\tdb.query("ALTER TABLE `players` ADD COLUMN `skill_a` INT UNSIGNED NOT NULL DEFAULT 10, ADD COLUMN '
       '`skill_a_tries` bigint UNSIGNED NOT NULL DEFAULT 0")\n\treturn true\nend\n',
    6: 'function onUpdateDatabase()\n\tprint("> Updating database to version 6, wings save.")\n'
       '\tdb.query("ALTER TABLE `players` ADD `wings_id` int(11) NOT NULL DEFAULT 0;")\n\treturn true\nend\n',
    7: 'function onUpdateDatabase()\n\tprint("> Updating database to version 7, new column")\n'
       '\tdb.query("ALTER TABLE `players` ADD `fresh_col` int(11) NOT NULL DEFAULT 3")\n\treturn true\nend\n',
    8: 'function onUpdateDatabase()\n\tprint("> Updating database to version 8 (orders)")\n'
       '\tdb.query("ALTER TABLE `web_orders` ADD COLUMN `mountid` TINYINT NULL AFTER `itemid`;")\n\treturn true\nend\n',
    9: 'function onUpdateDatabase()\n\tlocal r = db.storeQuery("SELECT `fresh_col` FROM `players` LIMIT 1")\n'
       '\tif r then result.free(r) end\n\tdb.query("ALTER TABLE `players` ADD INDEX `name_i` (`name`)")\n'
       '\treturn true\nend\n',
    10: 'function onUpdateDatabase()\n\treturn false\nend\n',
}


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w', newline='') as f:
        f.write(text)


def run(args):
    p = subprocess.run([sys.executable, '-I'] + args, capture_output=True, text=True)
    return p.returncode, p.stdout + p.stderr


# ---------------------------------------------------------------- the rewrite (no database)
text, done = M.patch(MIGRATIONS[5] + MIGRATIONS[6] + MIGRATIONS[8] + MIGRATIONS[9])
check('if db.tableExists("players") then db.query("ALTER TABLE `players` ADD COLUMN IF NOT EXISTS `skill_a` INT '
      'UNSIGNED NOT NULL DEFAULT 10, ADD COLUMN IF NOT EXISTS `skill_a_tries` bigint UNSIGNED NOT NULL DEFAULT 0") end'
      in text, 'two columns: each IF NOT EXISTS, the table checked')
check('ADD COLUMN IF NOT EXISTS `wings_id` int(11) NOT NULL DEFAULT 0;") end' in text, 'ADD without COLUMN, trailing ;')
check('if db.tableExists("web_orders")' in text, 'a migration on another table checks that table')
check('db.query("ALTER TABLE `players` ADD INDEX `name_i` (`name`)")' in text and 'IF NOT EXISTS `name_i`' not in text,
      'an ADD INDEX statement stays as it is')
check(done == ['players.skill_a', 'players.skill_a_tries', 'players.wings_id', 'web_orders.mountid'], 'reported: %r' % done)
check(M.patch(text)[0] == text, 'a second rewrite changes nothing')
check(M.rewrite_sql('ADD `a` DECIMAL(10,2) NOT NULL DEFAULT 0, ADD `b` varchar(3) DEFAULT \'x,y\'') ==
      'ADD COLUMN IF NOT EXISTS `a` DECIMAL(10,2) NOT NULL DEFAULT 0, ADD COLUMN IF NOT EXISTS `b` varchar(3) DEFAULT \'x,y\'',
      'commas inside () and quotes')
check(M.rewrite_sql('DROP `a`, ADD `b` int') is None, 'a mixed statement stays')

# ---------------------------------------------------------------- on a fresh database
lua = shutil.which('luajit') or shutil.which('lua5.3')
if not (shutil.which('mariadb-install-db') or shutil.which('mysql_install_db')) or not shutil.which('mariadbd') or not lua:
    print('fresh_db_check_test: MariaDB or Lua not found, database part skipped')
else:
    with tempfile.TemporaryDirectory() as tmp:
        srv = os.path.join(tmp, 'server')
        for v, body in MIGRATIONS.items():
            write(os.path.join(srv, 'data', 'migrations', '%d.lua' % v), body)
        write(os.path.join(srv, 'sql-setup', '00-schema.sql'), SCHEMA)

        rc, out = run([CHECK, srv])
        check(rc == 1, 'stock migrations: exit 1 (%d)\n%s' % (rc, out))
        check("Duplicate column name 'skill_a'" in out and "Duplicate column name 'wings_id'" in out,
              'stock: the duplicate columns reported')
        check("web_orders' doesn't exist" in out, 'stock: the missing table reported')
        check('db_version 5 -> 10, 3 error(s)' in out, 'stock: three errors, version 10 reached: ' + out[-400:])

        rc, out = run([PATCH, os.path.join(srv, 'data')])
        check(rc == 0 and '4 file(s) changed' in out, 'patch: 4 files (the ADD INDEX one stays): ' + out)
        rc, out = run([PATCH, os.path.join(srv, 'data')])
        check(rc == 0 and 'nothing to change' in out, 'patch twice: nothing to change: ' + out)

        rc, out = run([CHECK, srv])
        check(rc == 0, 'patched: exit 0 (%d)\n%s' % (rc, out))
        check('db_version 5 -> 10, 0 error(s)' in out, 'patched: no error, version 10: ' + out[-400:])

        # the website tables: loaded after the schema, the shop orders get mountid from our file and the migration
        write(os.path.join(srv, 'sql-setup', '50-web.sql'), open(WEB_SQL).read())
        write(os.path.join(srv, 'data', 'migrations', '8.lua'), MIGRATIONS[8].replace('web_orders', 'znote_shop_orders'))
        run([PATCH, os.path.join(srv, 'data')])
        rc, out = run([CHECK, srv])
        check(rc == 0 and '50-web.sql' in out and 'ERROR' not in out, 'website tables load, no error: ' + out[-600:])

if fails:
    print('fresh_db_check_test: %d check(s) failed' % len(fails))
    sys.exit(1)
print('fresh_db_check_test: all checks passed')
