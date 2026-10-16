#!/usr/bin/env python3
"""Test of harden_vps.sh against a fake file system (HARDEN_ROOT) with stub commands on PATH: the dry run changes
nothing and runs nothing; a real run writes the expected files, opens exactly the expected ports, fixes the modes of the
private files and warns about public listeners; a second run changes nothing; SSH is locked only when a key, the sudo
group and a key login are there (never otherwise); --cloudflare turns the web jail off and sets mod_remoteip.

  python3 -I tools/linux/harden_vps_test.py      (bash; no root, nothing outside a temporary folder is touched)
"""
import hashlib
import os
import shutil
import stat
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, 'harden_vps.sh')
fails = 0

# a syntactically valid ed25519 public key line (no private key exists for it)
PUBKEY = 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGVnaW5lZXJpbmd0ZXN0a2V5Zm9yaGFyZGVudnBzdGVzdHM= owner@pc\n'

STUBS = {
    # read-only answers
    'dpkg': '[ -f "$HARDEN_ROOT/.installed" ]',          # installed once the apt-get stub ran
    'sshd': '[ "$1" = -T ] && echo "port 22"; exit 0',
    'ss': 'printf "LISTEN 0 80 0.0.0.0:3307 0.0.0.0:*\\nLISTEN 0 5 127.0.0.1:8090 0.0.0.0:*\\n'
          'LISTEN 0 128 0.0.0.0:7171 0.0.0.0:*\\n"',
    'ufw': '[ "$1" = status ] && printf "Status: active\\n\\nTo Action From\\n8090/tcp ALLOW Anywhere\\n"; exit 0',
    'getent': '[ "$2" = admin ] && echo "admin:x:1000:1000::/home/admin:/bin/bash"; [ "$2" = nosudo ] && '
              'echo "nosudo:x:1001:1001::/home/nosudo:/bin/bash"; exit 0',
    'id': 'if [ "$1" = -u ]; then echo 1000; elif [ "$2" = admin ]; then echo "admin sudo"; else echo "$2"; fi',
    'curl': 'case "$*" in *ips-v4*) printf "173.245.48.0/20\\n103.21.244.0/22\\n";; *) printf "2400:cb00::/32\\n";; esac',
    'journalctl': 'exit 0',
    # changing commands: as much state as the script reads back
    'a2enmod': 'for m in "$@"; do [ "$m" = -q ] || touch "$HARDEN_ROOT/etc/apache2/mods-enabled/$m.load"; done',
    'a2enconf': 'for c in "$@"; do [ "$c" = -q ] || touch "$HARDEN_ROOT/etc/apache2/conf-enabled/$c.conf"; done',
    'env': 'touch "$HARDEN_ROOT/.installed"',
}
MUTATING = ('apt-get', 'env', 'sysctl', 'fail2ban-client', 'systemctl', 'a2enmod', 'a2enconf', 'apache2ctl')


def check(cond, what):
    global fails
    if not cond:
        fails += 1
        print('FAIL: ' + what)


def make_root(d, auth_log=True, key=True):
    root = os.path.join(d, 'root')
    for sub in ('etc/apache2/mods-enabled', 'etc/apache2/conf-enabled', 'etc/fail2ban/jail.d', 'etc/ssh/sshd_config.d', 'var/log',
                'home/admin/.ssh', 'home/chaos/CindersOfChaos-Server-Linux/server', 'var/www/chaos', 'etc/chaos/rsa',
                'etc/mysql/mariadb.conf.d'):
        os.makedirs(os.path.join(root, sub), exist_ok=True)
    w = lambda rel, text, mode=0o644: (open(os.path.join(root, rel), 'w').write(text), os.chmod(os.path.join(root, rel), mode))
    w('etc/os-release', 'ID=ubuntu\nVERSION_ID="24.04"\n')
    if key:
        w('home/admin/.ssh/authorized_keys', PUBKEY, 0o600)
    if auth_log:
        w('var/log/auth.log', 'Oct 16 10:00:00 vps sshd[1]: Accepted publickey for admin from 203.0.113.9 port 5 ssh2\n')
    pkg = 'home/chaos/CindersOfChaos-Server-Linux'
    w(pkg + '/chaos.env', 'CHAOS_DB_PASS=secret-value-never-printed\nCHAOS_CLIENT_KEY=\n'
      'CHAOS_RSA_KEY_FILE=/etc/chaos/rsa/login.pem\n', 0o644)
    w(pkg + '/first-start-account.txt', 'Staff account ...\n', 0o600)
    w('etc/chaos/rsa/login.pem', '-----BEGIN RSA PRIVATE KEY-----\nx\n-----END RSA PRIVATE KEY-----\n', 0o640)
    w('var/www/chaos/config.local.php', '<?php // password\n', 0o644)
    w('etc/mysql/mariadb.conf.d/50-server.cnf', '[mysqld]\nbind-address = 127.0.0.1\n')
    return root


def make_stubs(d):
    bindir = os.path.join(d, 'bin')
    os.makedirs(bindir, exist_ok=True)
    log = os.path.join(d, 'calls.log')
    names = set(STUBS) | set(MUTATING) | {'ssh-keygen'}
    for name in names:
        body = STUBS.get(name, 'exit 0')
        if name == 'ssh-keygen':
            body = 'grep -c "^ssh-" "$3" >/dev/null && echo "256 SHA256:x owner@pc (ED25519)"'
        path = os.path.join(bindir, name)
        with open(path, 'w') as f:
            f.write('#!/bin/bash\necho "%s $*" >> "%s"\n%s\n' % (name, log, body))
        os.chmod(path, 0o755)
    return bindir, log


def snapshot(root):
    out = {}
    for dp, _, fs in os.walk(root):
        for f in fs:
            p = os.path.join(dp, f)
            out[os.path.relpath(p, root)] = (hashlib.sha256(open(p, 'rb').read()).hexdigest(), stat.S_IMODE(os.stat(p).st_mode))
    return out


def run(d, root, bindir, log, *args):
    if os.path.exists(log):
        os.remove(log)
    env = dict(os.environ, HARDEN_ROOT=root, PATH=bindir + os.pathsep + os.environ['PATH'])
    env.pop('SUDO_USER', None)
    p = subprocess.run(['bash', SCRIPT] + list(args), capture_output=True, text=True, env=env)
    calls = open(log).read().splitlines() if os.path.exists(log) else []
    return p.returncode, p.stdout + p.stderr, calls


def read(root, rel):
    p = os.path.join(root, rel)
    return open(p).read() if os.path.exists(p) else None


def mode(root, rel):
    return stat.S_IMODE(os.stat(os.path.join(root, rel)).st_mode)


with tempfile.TemporaryDirectory() as d:
    root = make_root(d)
    bindir, log = make_stubs(d)

    # dry run: nothing changes, nothing mutating runs, the plan is printed, no secret is printed
    before = snapshot(root)
    rc, out, calls = run(d, root, bindir, log, '--dry-run', '--admin-user', 'admin', '--lock-ssh')
    check(rc == 0, 'dry run exit 0: ' + out[-500:])
    check(snapshot(root) == before, 'dry run changes no file')
    check(not [c for c in calls if c.split()[0] in MUTATING or c.startswith('ufw ') and 'status' not in c],
          'dry run runs no changing command: %s' % calls)
    check('would write /etc/ssh/sshd_config.d/10-chaos-hardening.conf' in out, 'dry run shows the SSH lock')
    check('would run: ufw allow 7172/tcp' in out and 'would run: ufw limit 22/tcp' in out, 'dry run shows the ports')
    check('secret-value-never-printed' not in out and 'BEGIN RSA' not in out, 'no secret in the output')
    check('dry run: nothing changed' in out, 'dry run says so')

    # real run (in the fake root)
    rc, out, calls = run(d, root, bindir, log, '--admin-user', 'admin', '--lock-ssh')
    check(rc == 0, 'real run exit 0: ' + out[-800:])
    ssh = read(root, 'etc/ssh/sshd_config.d/10-chaos-hardening.conf') or ''
    check('PasswordAuthentication no' in ssh and 'PermitRootLogin no' in ssh, 'SSH lock written')
    check('systemctl reload ssh' in calls, 'ssh reloaded')
    opened = sorted(c.split()[2] for c in calls if c.startswith('ufw allow ') or c.startswith('ufw limit '))
    check(opened == sorted(['22/tcp', '80/tcp', '443/tcp', '7171/tcp', '7172/tcp']), 'ufw opens exactly: %s' % opened)
    check('ufw delete allow 8090/tcp' in calls, 'an open 8090 rule is removed')
    check('ufw --force enable' in calls and 'ufw default deny incoming' in calls, 'ufw on, deny by default')
    check(not any(p in c for c in calls if c.startswith('ufw allow') for p in ('3306', '3307', '8090')),
          'local ports never opened')
    jail = read(root, 'etc/fail2ban/jail.d/chaos.local') or ''
    check('[sshd]' in jail and '[chaos-site-forms]' in jail and 'banaction = ufw' in jail, 'fail2ban jails')
    check('fail2ban-client -t' in calls, 'fail2ban config tested')
    sec = read(root, 'etc/apache2/conf-available/chaos-security.conf') or ''
    check('ServerTokens Prod' in sec and 'ServerSignature Off' in sec and 'TraceEnable Off' in sec, 'Apache conf')
    check('apache2ctl configtest' in calls and 'systemctl reload apache2' in calls, 'Apache tested and reloaded')
    check('a2enmod -q headers' in calls and 'a2enconf -q chaos-security' in calls, 'Apache modules on')
    check('net.ipv4.tcp_syncookies = 1' in (read(root, 'etc/sysctl.d/90-chaos-hardening.conf') or ''), 'sysctl file')
    check('Unattended-Upgrade "1"' in (read(root, 'etc/apt/apt.conf.d/20auto-upgrades') or ''), 'unattended-upgrades on')
    check('Automatic-Reboot "false"' in (read(root, 'etc/apt/apt.conf.d/52chaos-unattended') or ''), 'no auto reboot')
    check(any('apt-get install' in c and 'fail2ban' in c for c in calls), 'packages installed')
    check(mode(root, 'home/chaos/CindersOfChaos-Server-Linux/chaos.env') == 0o600, 'chaos.env fixed to 600')
    check(mode(root, 'etc/chaos/rsa/login.pem') == 0o600, 'the RSA key named in chaos.env fixed to 600')
    check(mode(root, 'var/www/chaos/config.local.php') == 0o640, 'config.local.php: world bits removed only')
    check('port 3307 listens on 0.0.0.0:3307' in out, 'a public MariaDB is reported')
    check('ok: port 8090 listens on 127.0.0.1:8090' in out, 'local services are ok')
    check('CHAOS_CLIENT_KEY is empty' in out, 'empty client guard key reported')
    check('first-start-account.txt holds' in out, 'first-start-account.txt reported')
    check('secret-value-never-printed' not in out, 'no secret in the output (real run)')

    # second run: idempotent
    after = snapshot(root)
    rc, out, calls = run(d, root, bindir, log, '--admin-user', 'admin', '--lock-ssh')
    check(rc == 0 and snapshot(root) == after, 'second run changes no file')
    check('files written: 0' in out, 'second run writes nothing: ' + out[-300:])
    check('systemctl reload ssh' not in calls and 'systemctl reload apache2' not in calls
          and 'systemctl restart fail2ban' not in calls, 'second run reloads nothing: %s' % calls)

    # --cloudflare: the web jail off, mod_remoteip with the published ranges
    rc, out, calls = run(d, root, bindir, log, '--admin-user', 'admin', '--cloudflare')
    check('[chaos-site-forms]' not in (read(root, 'etc/fail2ban/jail.d/chaos.local') or 'x'), 'cloudflare: web jail off')
    cf = read(root, 'etc/apache2/conf-available/chaos-cloudflare.conf') or ''
    check('RemoteIPHeader CF-Connecting-IP' in cf and 'RemoteIPTrustedProxy 173.245.48.0/20' in cf, 'cloudflare remoteip')

for case, kwargs, args, why in (
        ('no key', {'key': False}, ['--admin-user', 'admin', '--lock-ssh'], 'no valid public key'),
        ('no key login', {'auth_log': False}, ['--admin-user', 'admin', '--lock-ssh'], 'no key login of admin'),
        ('no sudo', {}, ['--admin-user', 'nosudo', '--lock-ssh'], 'not in the sudo group'),
        ('no user', {}, ['--lock-ssh'], '--admin-user NAME')):
    with tempfile.TemporaryDirectory() as d:
        root = make_root(d, **kwargs)
        if 'nosudo' in args:
            os.makedirs(os.path.join(root, 'home/nosudo/.ssh'))
            shutil.copy(os.path.join(root, 'home/admin/.ssh/authorized_keys'), os.path.join(root, 'home/nosudo/.ssh/'))
        bindir, log = make_stubs(d)
        rc, out, calls = run(d, root, bindir, log, *args)
        check(read(root, 'etc/ssh/sshd_config.d/10-chaos-hardening.conf') is None, '%s: SSH not locked' % case)
        check(why in out and 'SSH: NOT locked' in out, '%s: says why (%s)' % (case, why))
        check('systemctl reload ssh' not in calls, '%s: ssh not reloaded' % case)

with tempfile.TemporaryDirectory() as d:  # an explicit --key-login-tested replaces the log evidence
    root = make_root(d, auth_log=False)
    bindir, log = make_stubs(d)
    rc, out, calls = run(d, root, bindir, log, '--admin-user', 'admin', '--lock-ssh', '--key-login-tested')
    check(read(root, 'etc/ssh/sshd_config.d/10-chaos-hardening.conf') is not None, '--key-login-tested locks')
    rc, out, calls = run(d, root, bindir, log, '--bogus')
    check(rc != 0, 'an unknown option fails')

if fails:
    print('%d failure(s)' % fails)
    sys.exit(1)
print('harden_vps_test: ok')
