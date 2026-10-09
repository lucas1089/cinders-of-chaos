#!/usr/bin/env python3
"""Turn the base server's stock config.lua into the production config of a public Cinders of Chaos server (idempotent).

usage: python3 -I server/tools/prod_config.py SERVER_DIR --ip HOST [--name NAME] [--motd TEXT] [--max-players N]
                                              [--pvp pvp|no-pvp|pvp-enforced] [--save-time HH:MM] [--owner NAME]
                                              [--email ADDRESS] [--url URL] [--location TEXT] [--dry-run]

SERVER_DIR is the folder with config.lua (and data/globalevents/globalevents.xml for --save-time). Every setting below is
written as `key = value  -- Chaos production (server/tools/prod_config.py)`; a second run with the same options changes
nothing, a run with other options updates the same lines. Settings that are not listed stay as the base server has them.

What it sets, and why (docs/LAUNCH.md has the full checklist):
  ip                      the address players connect to (public IP or DNS name); the login server hands it out in
                          the character list, so 127.0.0.1 works only on the server machine itself
  loginProtocolPort 7171, gameProtocolPort 7172, statusProtocolPort 7171
                          the stock ports; open exactly these (plus the login-screen HTTP port) in the firewall
  serverName, motd        what the character list and the login box show (the base server ships its own name)
  ownerName, ownerEmail, url, location
                          the status protocol answer (server lists); the base server ships someone else's values
  maxPlayers              0 = unlimited in the engine; set a real cap from the load test (server/tools/loadtest.py)
  worldType               "pvp" (default), "no-pvp" or "pvp-enforced"; the arena and the guild siege work in every
                          type (they never use real deaths)
  allowClones = false, onePlayerOnlinePerAccount = false
                          the multi-client rules live in data/scripts/chaos/multiclient.lua (2 characters per IP, a
                          second character cannot attack players or enter dungeons); the engine setting stays off so
                          two characters of one account can be online together, as that script expects
  serverSaveShutdown = true, serverSaveClose = false, serverSaveCleanMap = false
                          the daily save (data/globalevents/globalevents.xml "Server Save", 08:00 in the base server)
                          saves and then SHUTS THE SERVER DOWN. That is kept on purpose: the service manager starts it
                          again (server/deploy/chaos-server.service, Restart=always), so every day begins with a fresh
                          process, a clean map and released memory. --save-time moves it (pick a quiet hour, and keep
                          the backup timer 15 minutes after it)
  mysqlHost, mysqlPort, mysqlUser, mysqlPass, mysqlDatabase
                          read from the environment at start: os.getenv("CHAOS_DB_HOST") ... The engine runs config.lua
                          as Lua with the standard libraries, so os.getenv works there. The service reads the variables
                          from /etc/chaos/chaos.env (mode 0600); no password is ever written into config.lua
  mapName                 checked, not set: a cropped test map (a name starting with "zcrop") is refused
  startupDatabaseOptimization = false, showScriptsLogInConsole = false
                          faster start; quiet console (the log file is the console output)
  passwordType = "pbkdf2-sha256", passwordHashIterations = 120000
                          account passwords are salted PBKDF2-HMAC-SHA256 (engine patch 0014, the website the same);
                          passwordHashIterations is what the engine uses for new hashes (keep CHAOS_PASSWORD_ITERATIONS
                          of the website equal), passwordType only documents the scheme (the engine does not read it).
                          Old SHA-1 passwords keep working and are re-hashed at the next login

Exit status 1 (nothing written) when --ip is missing or the map is a cropped test map.
"""
import os
import re
import sys

MARK = '-- Chaos production (server/tools/prod_config.py)'
ENV_DB = [
    ('mysqlHost', 'CHAOS_DB_HOST', '"127.0.0.1"'),
    ('mysqlPort', 'CHAOS_DB_PORT', '3306'),
    ('mysqlUser', 'CHAOS_DB_USER', '"chaos"'),
    ('mysqlPass', 'CHAOS_DB_PASS', '""'),
    ('mysqlDatabase', 'CHAOS_DB_NAME', '"chaos"'),
]


def lua_string(text):
    return '"' + text.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n') + '"'


def settings(opts):
    s = [
        ('ip', lua_string(opts['--ip'])),
        ('loginProtocolPort', '7171'),
        ('gameProtocolPort', '7172'),
        ('statusProtocolPort', '7171'),
        ('serverName', lua_string(opts.get('--name', 'Cinders of Chaos'))),
        ('motd', lua_string(opts.get('--motd',
                                     'Welcome to Cinders of Chaos. The world was not ended. It was broken.'))),
        ('ownerName', lua_string(opts.get('--owner', ''))),
        ('ownerEmail', lua_string(opts.get('--email', ''))),
        ('url', lua_string(opts.get('--url', ''))),
        ('location', lua_string(opts.get('--location', ''))),
        ('maxPlayers', str(int(opts.get('--max-players', '300')))),
        ('worldType', lua_string(opts.get('--pvp', 'pvp'))),
        ('allowClones', 'false'),
        ('onePlayerOnlinePerAccount', 'false'),
        ('serverSaveShutdown', 'true'),
        ('serverSaveClose', 'false'),
        ('serverSaveCleanMap', 'false'),
        ('startupDatabaseOptimization', 'false'),
        ('showScriptsLogInConsole', 'false'),
        ('passwordType', '"pbkdf2-sha256"'),
        ('passwordHashIterations', '120000'),
    ]
    for key, env, default in ENV_DB:
        expr = 'os.getenv("%s")' % env
        s.append((key, '%s or %s' % ('tonumber(%s)' % expr if key == 'mysqlPort' else expr, default)))
    return s


def apply(text, key, value):
    line = '%s = %s %s' % (key, value, MARK)
    pat = re.compile(r'^[ \t]*%s[ \t]*=.*$' % re.escape(key), re.M)
    if pat.search(text):
        return pat.sub(lambda m: line, text, count=1)
    return text.rstrip('\n') + '\n' + line + '\n'


def save_time(server, hhmm, dry):
    path = os.path.join(server, 'data', 'globalevents', 'globalevents.xml')
    if not os.path.isfile(path):
        return 'missing %s' % path
    text = open(path, encoding='utf-8', errors='surrogateescape').read()
    new = re.sub(r'(<globalevent\s+name="Server Save"\s+time=")[^"]*(")', lambda m: m.group(1) + hhmm + ':00' + m.group(2),
                 text)
    if new == text:
        return 'globalevents.xml: Server Save already at %s (or no such entry)' % hhmm
    if not dry:
        open(path, 'w', encoding='utf-8', errors='surrogateescape', newline='').write(new)
    return 'globalevents.xml: Server Save at %s' % hhmm


def main(argv):
    opts, pos, i = {}, [], 0
    while i < len(argv):
        a = argv[i]
        if a == '--dry-run':
            opts[a] = True
        elif a.startswith('--'):
            if i + 1 >= len(argv):
                sys.exit('%s needs a value' % a)
            opts[a] = argv[i + 1]
            i += 1
        else:
            pos.append(a)
        i += 1
    if len(pos) != 1 or '--ip' not in opts:
        print(__doc__)
        return 1
    if opts.get('--pvp', 'pvp') not in ('pvp', 'no-pvp', 'pvp-enforced'):
        sys.exit('--pvp must be pvp, no-pvp or pvp-enforced')
    if '--save-time' in opts and not re.match(r'^([01]\d|2[0-3]):[0-5]\d$', opts['--save-time']):
        sys.exit('--save-time must be HH:MM')
    server = pos[0]
    path = os.path.join(server, 'config.lua')
    text = open(path, encoding='utf-8', errors='surrogateescape').read()
    m = re.search(r'^\s*mapName\s*=\s*"([^"]*)"', text, re.M)
    if m and m.group(1).lower().startswith('zcrop'):
        print('config.lua: mapName "%s" is a cropped TEST map; set the real map first. Nothing written.' % m.group(1))
        return 1
    new = text
    changed = []
    for key, value in settings(opts):
        after = apply(new, key, value)
        if after != new:
            changed.append(key)
        new = after
    dry = bool(opts.get('--dry-run'))
    if new != text and not dry:
        open(path, 'w', encoding='utf-8', errors='surrogateescape', newline='').write(new)
    print('config.lua: %s' % ('%d setting(s) %s: %s' % (len(changed), 'would change' if dry else 'set', ', '.join(changed))
                              if changed else 'already the production settings'))
    if '--save-time' in opts:
        print(save_time(server, opts['--save-time'], dry))
    print('The database settings are read from CHAOS_DB_HOST / CHAOS_DB_PORT / CHAOS_DB_USER / CHAOS_DB_PASS / '
          'CHAOS_DB_NAME (server/deploy/chaos.env.example).')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
