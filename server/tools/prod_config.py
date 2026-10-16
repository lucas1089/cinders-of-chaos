#!/usr/bin/env python3
"""Turn the base server's stock config.lua into the production config of a public Cinders of Chaos server (idempotent).

usage: python3 -I server/tools/prod_config.py SERVER_DIR --public-host HOST [--name NAME] [--motd TEXT] [--max-players N]
                                              [--pvp pvp|no-pvp|pvp-enforced] [--save-time HH:MM] [--owner NAME]
                                              [--email ADDRESS] [--url URL] [--location TEXT]
                                              [--client-url URL] [--client-builds LIST] [--client-manifest PATH]
                                              [--client-staff-ips LIST] [--proxy-trusted LIST]
                                              [--proxy-required yes|no] [--spawn-near-players yes|no]
                                              [--spawn-min-distance N] [--dry-run]

SERVER_DIR is the folder with config.lua (and data/globalevents/globalevents.xml for --save-time). Every setting below is
written as `key = value  -- Chaos production (server/tools/prod_config.py)`; a second run with the same options changes
nothing, a run with other options updates the same lines. Settings that are not listed stay as the base server has them.

What it sets, and why (docs/LAUNCH.md has the full checklist):
  ip                      --public-host (or --ip, the same): the address players connect to for the game world. The
                          login server hands it out in the character list as text and the client resolves it itself,
                          so a DNS name works and a DNS change needs no restart. Behind gateways (docs/LAUNCH.md
                          "Gateways and DDoS") it is the gateways' public name (e.g. play.example.com, DNS round-robin
                          over the gateways), never this machine's own IP; 127.0.0.1 works only on the server machine
  loginProtocolPort 7171, gameProtocolPort 7172, statusProtocolPort 7171
                          the stock ports; open exactly these (plus the login-screen HTTP port) in the firewall
  serverName, motd        what the character list and the login box show (the base server ships its own name)
  ownerName, ownerEmail, url, location
                          the status protocol answer (server lists); the base server ships someone else's values
  maxPlayers              --max-players, default 400: the launch cap from the full-map load test (server/README.md
                          "Load test on the full map": the game loop's one thread fills up at 500-600 bots on the
                          4-core test machine; real players cost more than bots). The beta runs with --max-players
                          300 (docs/BETA.md). 0 = unlimited in the engine
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
  armorPercent = true, armorPercentConstant = 250, armorPercentMax = 80
                          a player's armour takes armour / (armour + 250) of a physical hit, at most 80% (engine patch
                          0016, server/README.md "Percent armour"); armorPercent = false is the stock random flat reduction
  energyShieldRechargeDelay = 2000, energyShieldOpcode = 224
                          the energy shield (engine patch 0015, README "Energy shield") recharges 2 s after the last hit;
                          its value goes to the client on extended opcode 224 (ChaosOpcodes.energyShield)
  minPlayerSpeed = 120, maxPlayerSpeed = 2600, playerSpeedBonus = 50, playerSpeedPerTenLevels = 25,
  playerSpeedSoftLevel = 300, playerSpeedPerTenLevelsAbove = 10
                          movement speed (engine patch 0018, README "Movement speed"): a player walks between about
                          1 and 10 tiles/s on normal ground; base speed = vocation + 50, 2.5 per level to 300, 1 after
  rateSpawn = 3           how many monsters one spawn may bring back per check (the engine checks a spawn every shortest
                          spawntime of it). The stock 1 refilled a pack of five in five spawntimes; 3 brings most packs
                          back in one or two. Not a time multiplier: the timers are in the spawn file
                          (tools/patch_base_spawns.py, server/README.md "Spawn density and respawn")
  cooldownChannels = true, moveItemDelay = 50, runeChannelDelay = 1000, potionChannelDelay = 1000
                          the cooldown channels (engine patch 0042, README "Cooldown channels"): attack, healing and
                          support runes, potions, item moves and other uses each wait only for their own channel, the
                          auto attack for none of them; the numbers are each channel's anti-spam delay in ms (floor 50)
  spawnNearPlayers = true, spawnMinPlayerDistance = 2
                          monsters respawn while a player sees the spot (engine patch 0041, README "Respawn near
                          players"): on a free tile (no creature, no blocking item, no protection zone), at least N sqm
                          from every player (2 = never next to one), with a teleport effect. --spawn-near-players no is
                          the stock rule (no respawn in a player's view). --spawn-min-distance N (0-7). Not given: the
                          value already in config.lua is kept (true and 2 on a first run)
  clientGuardMode = "enforce", clientGuardKey = os.getenv("CHAOS_CLIENT_KEY") or "", clientGuardAllowDevKey = false,
  clientGuardTimeout = 10, clientGuardDownloadUrl, clientGuardBuilds, clientGuardManifest, clientGuardStaffIps
                          only the official client plays (engine patch 0021, README "Client guard"): the key is read from
                          the environment (/etc/chaos/chaos.env, CHAOS_CLIENT_KEY: the same 64 hex digits as the GitHub
                          secret the Windows client is built with), never written into config.lua; the public
                          development key is refused. --client-url is the download page named in the refusal message
                          (default: --url); --client-builds the accepted client builds, e.g. "4,5" during an update window
                          (default: any); --client-manifest the updater's manifest.json on this machine, whose
                          min_package then refuses older builds too (default: none); --client-staff-ips the IPs from
                          which staff accounts may use another client (default: none). Without CHAOS_CLIENT_KEY in the
                          environment every player is kicked at the handshake (the console says so at startup)
  proxyProtocolTrusted, proxyProtocolRequired
                          the gateways in front of the server (engine patch 0025, README "Gateways and the PROXY
                          protocol"). --proxy-trusted: the gateways' IPv4 addresses (a.b.c.d or a.b.c.d/nn, comma
                          separated); a connection from one must start with a PROXY header and the engine takes the
                          player's real address from it (bans, 2 characters per IP, staff IPs, logs). "" turns it off.
                          --proxy-required yes: every other address is refused (127.0.0.0/8 excepted: the watchdog and
                          the health check), so the real server cannot be played directly even if its firewall is
                          wrong. Not given: the value already in config.lua is kept (off on a first run)
  rsaKeyFile = os.getenv("CHAOS_RSA_KEY_FILE") or "key.pem"
                          the login's RSA key (engine patch 0046, README "Login encryption (RSA, XTEA)"): our own key,
                          made on this machine with tools/rsa_key.py gen, its path in /etc/chaos/chaos.env; without it
                          the base key.pem (the public default key: the console warns) as before

Exit status 1 (nothing written) when --public-host is missing or the map is a cropped test map.
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


IPV4_RANGE = re.compile(r'^(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}(/([12]?\d|3[0-2]))?$')
YES = ('yes', 'true', 'on', '1')
NO = ('no', 'false', 'off', '0')


def proxy_list(text):
    """The --proxy-trusted value as the engine reads it ("a, b" -> "a,b"), or None when an entry is not IPv4 / CIDR."""
    items = [x for x in re.split(r'[\s,;]+', text.strip()) if x]
    if not all(IPV4_RANGE.match(x) for x in items):
        return None
    return ','.join(items)


def current(text, key):
    """The value of `key` in config.lua (the expression after =, without a trailing comment), or None."""
    m = re.search(r'^[ \t]*%s[ \t]*=[ \t]*(.*?)[ \t]*(--.*)?$' % re.escape(key), text, re.M)
    return m.group(1) if m else None


def settings(opts, text=''):
    host = opts.get('--public-host', opts.get('--ip'))
    trusted = (lua_string(proxy_list(opts['--proxy-trusted'])) if '--proxy-trusted' in opts
               else current(text, 'proxyProtocolTrusted') or '""')
    required = (('true' if opts['--proxy-required'].lower() in YES else 'false') if '--proxy-required' in opts
                else current(text, 'proxyProtocolRequired') or 'false')
    near = (('true' if opts['--spawn-near-players'].lower() in YES else 'false') if '--spawn-near-players' in opts
            else current(text, 'spawnNearPlayers') or 'true')
    near_dist = (str(int(opts['--spawn-min-distance'])) if '--spawn-min-distance' in opts
                 else current(text, 'spawnMinPlayerDistance') or '2')
    s = [
        ('ip', lua_string(host)),
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
        ('maxPlayers', str(int(opts.get('--max-players', '400')))),
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
        ('armorPercent', 'true'),
        ('armorPercentConstant', '250'),
        ('armorPercentMax', '80'),
        ('energyShieldRechargeDelay', '2000'),
        ('energyShieldOpcode', '224'),
        ('minPlayerSpeed', '120'),
        ('maxPlayerSpeed', '2600'),
        ('playerSpeedBonus', '50'),
        ('playerSpeedPerTenLevels', '25'),
        ('playerSpeedSoftLevel', '300'),
        ('playerSpeedPerTenLevelsAbove', '10'),
        ('rateSpawn', '3'),
        ('cooldownChannels', 'true'),
        ('moveItemDelay', '50'),
        ('runeChannelDelay', '1000'),
        ('potionChannelDelay', '1000'),
        ('spawnNearPlayers', near),
        ('spawnMinPlayerDistance', near_dist),
        ('clientGuardMode', '"enforce"'),
        ('clientGuardKey', 'os.getenv("CHAOS_CLIENT_KEY") or ""'),
        ('clientGuardAllowDevKey', 'false'),
        ('clientGuardTimeout', '10'),
        ('clientGuardDownloadUrl', lua_string(opts.get('--client-url', opts.get('--url', '')))),
        ('clientGuardBuilds', lua_string(opts.get('--client-builds', ''))),
        ('clientGuardManifest', lua_string(opts.get('--client-manifest', ''))),
        ('clientGuardStaffIps', lua_string(opts.get('--client-staff-ips', ''))),
        ('proxyProtocolTrusted', trusted),
        ('proxyProtocolRequired', required),
        ('rsaKeyFile', 'os.getenv("CHAOS_RSA_KEY_FILE") or "key.pem"'),
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
    if len(pos) != 1 or not (opts.get('--public-host') or opts.get('--ip')):
        print(__doc__)
        return 1
    if opts.get('--pvp', 'pvp') not in ('pvp', 'no-pvp', 'pvp-enforced'):
        sys.exit('--pvp must be pvp, no-pvp or pvp-enforced')
    if '--client-builds' in opts and not re.match(r'^\s*(\d{1,5}\s*(,\s*\d{1,5}\s*)*)?$', opts['--client-builds']):
        sys.exit('--client-builds must be build numbers separated by commas, e.g. 4,5')
    if '--proxy-trusted' in opts and proxy_list(opts['--proxy-trusted']) is None:
        sys.exit('--proxy-trusted must be IPv4 addresses or a.b.c.d/nn ranges separated by commas (or "" for off)')
    if '--proxy-required' in opts and opts['--proxy-required'].lower() not in YES + NO:
        sys.exit('--proxy-required must be yes or no')
    if '--spawn-near-players' in opts and opts['--spawn-near-players'].lower() not in YES + NO:
        sys.exit('--spawn-near-players must be yes or no')
    if '--spawn-min-distance' in opts and not re.match(r'^[0-7]$', opts['--spawn-min-distance'].strip()):
        sys.exit('--spawn-min-distance must be a number of sqm from 0 to 7')
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
    for key, value in settings(opts, text):
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
    print('The client guard key is read from CHAOS_CLIENT_KEY (the same value as the GitHub secret CHAOS_CLIENT_KEY; '
          'server/README.md "Client guard").')
    print('The RSA login key file is read from CHAOS_RSA_KEY_FILE (default key.pem; server/tools/rsa_key.py, '
          'server/README.md "Login encryption (RSA, XTEA)").')
    trusted = current(new, 'proxyProtocolTrusted') or '""'
    if current(new, 'proxyProtocolRequired') == 'true' and trusted in ('""', "''"):
        print('WARNING: proxyProtocolRequired = true with no proxyProtocolTrusted gateway: only 127.0.0.1 can connect.')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
