#!/usr/bin/env python3
"""Fresh-database check: load the SQL a new game database gets, then run the engine's migrations on it as the engine's
database manager does at its first start, and report every SQL error (exit status 1 when there is one).

usage: python3 -I fresh_db_check.py SERVER_DIR [--sql-dir DIR | --sql FILE ...] [--socket PATH] [--lua PATH] [--keep]

SERVER_DIR is a server folder with data/migrations. The SQL comes from --sql-dir (default SERVER_DIR/sql-setup, the
Windows package's first-start files, loaded in name order) or the --sql files in the given order (a Linux install:
SQL_Server/schema.sql, the other schema_*.sql / sql_*.sql, then server/sql/chaos.sql and the other server/sql/*.sql).

Without --socket it starts a throwaway MariaDB (mariadb-install-db and mariadbd from PATH, a temporary data folder,
a socket only, no TCP port) and removes it afterwards (--keep leaves the folder and prints where). With --socket it
uses that server as root and makes and drops a database chaos_fresh_check_<pid>.

The migration run follows DatabaseManager::updateDatabase: from server_config's db_version, data/migrations/<v>.lua is
loaded, onUpdateDatabase() called, and on true db_version becomes v + 1; it stops at the first file that returns false
(or is missing). db.query / db.storeQuery / db.tableExists / db.escapeString and result.* are the engine's, run through
the mysql client (Lua: --lua, default luajit, else lua5.3). A failed query prints the engine's own lines
"[Error - mysql_real_query] Query: ... / Message: ...". Tests: fresh_db_check_test.py.
"""
import os
import shutil
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))

# the engine side of a migration, run as `lua DRIVER MIGRATION_FILE`; CHECK_MYSQL is the mysql command line
DRIVER = r'''
local cmd = os.getenv("CHECK_MYSQL")
local tmp = os.getenv("CHECK_TMP")
local n = 0
local function file(name, text)
	local f = assert(io.open(name, "wb"))
	f:write(text)
	f:close()
end
local function slurp(name)
	local f = io.open(name, "rb")
	if not f then return "" end
	local s = f:read("*a")
	f:close()
	return s
end
local function run(sql, store)
	n = n + 1
	local q, e, o = tmp .. "/q" .. n .. ".sql", tmp .. "/e" .. n .. ".txt", tmp .. "/o" .. n .. ".txt"
	file(q, sql)
	local r = os.execute(cmd .. (store and " -B" or "") .. " < '" .. q .. "' > '" .. o .. "' 2> '" .. e .. "'")
	local okRun = r == 0 or r == true
	local err = ""
	for line in slurp(e):gmatch("[^\n]+") do
		if line:find("^ERROR") then
			err = line:gsub("^ERROR %d+ %(%w+%) at line %d+: ", "")
		elseif err == "" and not line:find("^%-%-%-") and line:find("%S") then
			err = line
		end
	end
	if not okRun or err ~= "" then
		print("[Error - mysql_real_query] Query: " .. sql:sub(1, 300))
		print("Message: " .. err)
		return false
	end
	return true, slurp(o)
end
local results, nextId = {}, 0
db = {}
function db.query(sql) return (run(sql)) end
function db.storeQuery(sql)
	local ok, out = run(sql, true)
	if not ok then return false end
	local lines = {}
	for line in out:gmatch("[^\n]+") do lines[#lines + 1] = line end
	if #lines < 2 then return false end
	local head, rows = {}, {}
	for c in (lines[1] .. "\t"):gmatch("([^\t]*)\t") do head[#head + 1] = c end
	for i = 2, #lines do
		local row, j = {}, 0
		for c in (lines[i] .. "\t"):gmatch("([^\t]*)\t") do j = j + 1 row[head[j]] = c end
		rows[#rows + 1] = row
	end
	nextId = nextId + 1
	results[nextId] = {rows = rows, i = 1}
	return nextId
end
function db.escapeString(s)
	return "'" .. tostring(s):gsub("\\", "\\\\"):gsub("'", "\\'") .. "'"
end
function db.tableExists(name)
	local id = db.storeQuery("SELECT `TABLE_NAME` FROM `information_schema`.`tables` WHERE `TABLE_SCHEMA` = DATABASE() AND `TABLE_NAME` = " .. db.escapeString(name) .. " LIMIT 1")
	if id then result.free(id) return true end
	return false
end
db.asyncQuery = db.query
result = {}
local function cur(id) local r = results[id] return r and r.rows[r.i] end
function result.getNumber(id, col) local row = cur(id) return row and tonumber(row[col]) or 0 end
function result.getString(id, col) local row = cur(id) return row and row[col] or "" end
result.getStream = result.getString
function result.getBoolean(id, col) return result.getNumber(id, col) ~= 0 end
function result.next(id) local r = results[id] if not r then return false end r.i = r.i + 1 return r.rows[r.i] ~= nil end
function result.free(id) results[id] = nil return true end
local ok, err = pcall(dofile, arg[1])
if not ok then
	print("[Error - DatabaseManager::updateDatabase] " .. tostring(err))
	print("CHECK_RESULT=false")
	return
end
local okCall, ret = pcall(onUpdateDatabase)
if not okCall then
	print("[Error - DatabaseManager::updateDatabase] " .. tostring(ret))
	ret = false
end
print("CHECK_RESULT=" .. tostring(ret == true))
'''


def which(*names):
    for n in names:
        p = shutil.which(n)
        if p:
            return p
    return None


class Server:
    """a throwaway MariaDB on a socket"""

    def __init__(self, keep=False):
        self.keep = keep
        self.dir = tempfile.mkdtemp(prefix='chaos_fresh_db_')
        self.sock = os.path.join(self.dir, 'db.sock')
        self.proc = None

    def start(self):
        install, daemon = which('mariadb-install-db', 'mysql_install_db'), which('mariadbd')
        if not install or not daemon:
            raise RuntimeError('MariaDB not found (mariadb-install-db, mariadbd)')
        data = os.path.join(self.dir, 'data')
        r = subprocess.run([install, '--no-defaults', '--datadir=' + data, '--auth-root-authentication-method=normal',
                            '--skip-test-db'], capture_output=True, text=True)
        if r.returncode != 0:
            raise RuntimeError('mariadb-install-db: ' + (r.stderr or r.stdout)[-800:])
        args = [daemon, '--no-defaults', '--datadir=' + data, '--socket=' + self.sock, '--skip-networking',
                '--pid-file=' + os.path.join(self.dir, 'db.pid'), '--skip-log-bin', '--innodb-buffer-pool-size=64M',
                '--log-error=' + os.path.join(self.dir, 'db.log')]
        if hasattr(os, 'geteuid') and os.geteuid() == 0:
            args.append('--user=root')
        self.proc = subprocess.Popen(args, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        for _ in range(300):
            if os.path.exists(self.sock) and mysql(self.sock, None, 'SELECT 1')[0] == 0:
                return
            if self.proc.poll() is not None:
                break
            time.sleep(0.1)
        raise RuntimeError('mariadbd did not start (%s)' % os.path.join(self.dir, 'db.log'))

    def stop(self):
        if self.proc and self.proc.poll() is None:
            self.proc.terminate()
            try:
                self.proc.wait(30)
            except subprocess.TimeoutExpired:
                self.proc.kill()
        if self.keep:
            print('kept: ' + self.dir)
        else:
            shutil.rmtree(self.dir, ignore_errors=True)


def mysql_cmd(sock, db):
    client = which('mariadb', 'mysql') or 'mysql'
    return [client, '--no-defaults', '-uroot', '-S', sock] + ([db] if db else [])


def mysql(sock, db, sql=None, path=None):
    """(return code, output); sql through -e, or the file at path on stdin"""
    cmd = mysql_cmd(sock, db)
    if path:
        with open(path, 'rb') as f:
            r = subprocess.run(cmd, stdin=f, capture_output=True)
    else:
        r = subprocess.run(cmd + ['-N', '-B', '-e', sql], capture_output=True)
    return r.returncode, (r.stdout + r.stderr).decode('utf-8', 'replace')


def run_migrations(server_dir, sock, db, lua):
    """(start version, end version, [error lines], [log lines])"""
    rc, out = mysql(sock, db, "SELECT `value` FROM `server_config` WHERE `config` = 'db_version'")
    try:
        version = start = int(out.strip())
    except ValueError:
        return None, None, ['no db_version in server_config: ' + out.strip()], []
    tmp = tempfile.mkdtemp(prefix='chaos_fresh_lua_')
    driver = os.path.join(tmp, 'driver.lua')
    with open(driver, 'w') as f:
        f.write(DRIVER)
    env = dict(os.environ, CHECK_TMP=tmp,
               CHECK_MYSQL=' '.join("'%s'" % a for a in mysql_cmd(sock, db)))
    errors, log = [], []
    try:
        while True:
            path = os.path.join(server_dir, 'data', 'migrations', '%d.lua' % version)
            if not os.path.isfile(path):
                log.append('no migrations/%d.lua: the engine stops here' % version)
                break
            r = subprocess.run([lua, driver, path], capture_output=True, text=True, env=env,
                               cwd=server_dir)
            lines = (r.stdout + r.stderr).splitlines()
            result = 'CHECK_RESULT=true' in lines
            for line in lines:
                if line.startswith('CHECK_RESULT='):
                    continue
                log.append(line)
                if line.startswith('[Error'):
                    errors.append('migrations/%d.lua: %s' % (version, line))
                elif line.startswith('Message:') and errors:
                    errors[-1] += ' / ' + line
            if not result:
                break
            version += 1
            log.append('> Database has been updated to version %d.' % version)
            mysql(sock, db, "UPDATE `server_config` SET `value` = '%d' WHERE `config` = 'db_version'" % version)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    return start, version, errors, log


def main(argv):
    opts, sqls, args, i = {}, [], [], 0
    while i < len(argv):
        a = argv[i]
        if a in ('--sql-dir', '--socket', '--lua', '--sql'):
            if i + 1 >= len(argv):
                print(__doc__)
                return 1
            if a == '--sql':
                sqls.append(argv[i + 1])
            else:
                opts[a] = argv[i + 1]
            i += 2
            continue
        if a == '--keep':
            opts[a] = True
        elif a.startswith('-'):
            print(__doc__)
            return 1
        else:
            args.append(a)
        i += 1
    if len(args) != 1:
        print(__doc__)
        return 1
    server_dir = os.path.abspath(args[0])
    if not os.path.isdir(os.path.join(server_dir, 'data', 'migrations')):
        print('%s: no data/migrations' % server_dir)
        return 1
    if not sqls:
        d = opts.get('--sql-dir', os.path.join(server_dir, 'sql-setup'))
        if not os.path.isdir(d):
            print('%s: no SQL folder' % d)
            return 1
        sqls = [os.path.join(d, f) for f in sorted(os.listdir(d)) if f.endswith('.sql')]
    lua = opts.get('--lua') or which('luajit', 'lua5.1', 'lua5.3', 'lua')
    if not lua:
        print('no Lua interpreter (luajit or lua5.3)')
        return 1
    server = None
    sock = opts.get('--socket')
    db = 'chaos' if not sock else 'chaos_fresh_check_%d' % os.getpid()
    try:
        if not sock:
            server = Server(keep=opts.get('--keep'))
            server.start()
            sock = server.sock
        rc, out = mysql(sock, None, 'CREATE DATABASE `%s`' % db)
        if rc != 0:
            print('create database: ' + out.strip())
            return 1
        for path in sqls:
            rc, out = mysql(sock, db, path=path)
            print('  %s%s' % (os.path.basename(path), '' if rc == 0 else ': ERROR ' + out.strip()[:500]))
            if rc != 0:
                return 1
        start, end, errors, log = run_migrations(server_dir, sock, db, lua)
        for line in log:
            print('    ' + line)
        if start is None:
            print('FAILED: ' + errors[0])
            return 1
        print('migrations: db_version %d -> %d, %d error(s)' % (start, end, len(errors)))
        for e in errors:
            print('  ' + e)
        return 1 if errors else 0
    except RuntimeError as e:
        print(str(e))
        return 2
    finally:
        if sock and not server:
            mysql(sock, None, 'DROP DATABASE IF EXISTS `%s`' % db)
        if server:
            server.stop()


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
