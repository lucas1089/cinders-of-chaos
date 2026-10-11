#!/usr/bin/env python3
"""Hang watchdog for the game server (server/deploy/chaos-watchdog.service, .timer; docs/LAUNCH.md "Running it").

systemd already starts the engine again when it exits or crashes (chaos-server.service, Restart=always). This catches the
other case: the process is still alive but the game loop is stuck, so players freeze and nothing restarts it.

Every run (the timer runs it once a minute) asks the status protocol for its "info" document. The engine answers that
request from its dispatcher thread, so a stuck game loop never answers. After `--failures` misses in a row (default 3)
the watchdog restarts the service and writes a line to the crash log. Right after a start the map is still loading, so
the first `--grace` seconds (default 300) of a run are skipped.

usage: python3 -I server/tools/chaos_watchdog.py [--host 127.0.0.1] [--port 7171] [--timeout 10] [--failures 3]
                                                 [--grace 300] [--unit chaos-server] [--state FILE] [--dry-run]
"""
import json
import os
import socket
import subprocess
import sys
import time

STATUS_REQUEST = bytes([0x06, 0x00, 0xFF, 0xFF]) + b'info'


def ask_status(host, port, timeout):
    """True when the server answers the status "info" request with its XML document."""
    return is_status_reply(fetch_status(host, port, timeout))


def fetch_status(host, port, timeout):
    """The raw reply to the status "info" request (b'' when nothing came back). server/tools/chaos_health.py reads the
    player count from it."""
    data = b''
    try:
        with socket.create_connection((host, port), timeout=timeout) as s:
            s.settimeout(timeout)
            s.sendall(STATUS_REQUEST)
            deadline = time.monotonic() + timeout
            while time.monotonic() < deadline:
                chunk = s.recv(4096)
                if not chunk:
                    break
                data += chunk
                if b'</tsqp>' in data:
                    break
    except OSError:
        pass
    return data


def is_status_reply(data):
    return b'<tsqp' in data and b'</tsqp>' in data


def load_state(path):
    try:
        with open(path) as f:
            state = json.load(f)
        return {'misses': int(state.get('misses', 0))}
    except (OSError, ValueError):
        return {'misses': 0}


def save_state(path, state):
    tmp = path + '.tmp'
    with open(tmp, 'w') as f:
        json.dump(state, f)
    os.replace(tmp, path)


def decide(ok, state, failures):
    """The next state and whether to restart now: a restart happens on the `failures`-th miss in a row."""
    if ok:
        return {'misses': 0}, False
    misses = state['misses'] + 1
    if misses >= failures:
        return {'misses': 0}, True
    return {'misses': misses}, False


def unit_uptime(unit):
    """Seconds since the unit became active, or None when it is not active (systemctl show)."""
    try:
        out = subprocess.run(['systemctl', 'show', unit, '--property=ActiveState,ActiveEnterTimestampMonotonic'],
                             capture_output=True, text=True, timeout=10).stdout
    except (OSError, subprocess.SubprocessError):
        return None
    props = dict(line.split('=', 1) for line in out.splitlines() if '=' in line)
    if props.get('ActiveState') != 'active':
        return None
    try:
        since_us = int(props.get('ActiveEnterTimestampMonotonic', '0'))
    except ValueError:
        return None
    return time.clock_gettime(time.CLOCK_MONOTONIC) - since_us / 1e6


def log(path, text):
    line = time.strftime('%Y-%m-%d %H:%M:%S') + ' ' + text
    print(line)
    try:
        with open(path, 'a') as f:
            f.write(line + '\n')
    except OSError:
        pass


def main(argv):
    opts = {'--host': '127.0.0.1', '--port': '7171', '--timeout': '10', '--failures': '3', '--grace': '300',
            '--unit': 'chaos-server', '--state': '/var/lib/chaos/watchdog.json',
            '--log': '/var/log/chaos/crashes/watchdog.log'}
    dry = False
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == '--dry-run':
            dry = True
        elif a in opts and i + 1 < len(argv):
            opts[a] = argv[i + 1]
            i += 1
        else:
            print(__doc__)
            return 2
        i += 1
    unit = opts['--unit']
    uptime = unit_uptime(unit)
    if uptime is None:
        print('%s is not active: nothing to watch (systemd restarts it on its own)' % unit)
        return 0
    if uptime < float(opts['--grace']):
        print('%s started %d s ago: still in the grace period' % (unit, uptime))
        return 0
    ok = ask_status(opts['--host'], int(opts['--port']), float(opts['--timeout']))
    state, restart = decide(ok, load_state(opts['--state']), int(opts['--failures']))
    if not dry:
        os.makedirs(os.path.dirname(opts['--state']), exist_ok=True)
        save_state(opts['--state'], state)
    if ok:
        print('status answered')
        return 0
    if not restart:
        log(opts['--log'], 'no status answer (%d in a row)' % state['misses'])
        return 0
    log(opts['--log'], 'no status answer %s times in a row: restarting %s' % (opts['--failures'], unit))
    if dry:
        print('dry run: would run systemctl restart ' + unit)
        return 0
    subprocess.run(['systemctl', 'restart', unit], timeout=300)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
