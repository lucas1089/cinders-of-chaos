#!/usr/bin/env python3
"""Tests for chaos_watchdog.py: the status probe against fake servers, and the restart decision.
Run: python3 -I server/tools/chaos_watchdog_test.py"""
import os
import socket
import sys
import tempfile
import threading

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import chaos_watchdog as W  # noqa: E402

checks = 0


def ok(cond, what):
    global checks
    checks += 1
    if not cond:
        print('FAIL: ' + what)
        sys.exit(1)


def fake_server(mode):
    """A one-shot TCP server: 'answer' replies with a status document, 'silent' reads and never replies (a hung
    dispatcher), 'close' closes at once. Returns its port."""
    srv = socket.socket()
    srv.bind(('127.0.0.1', 0))
    srv.listen(1)
    port = srv.getsockname()[1]

    def run():
        conn, _ = srv.accept()
        data = conn.recv(64)
        if mode == 'answer' and data == W.STATUS_REQUEST:
            conn.sendall(b'<?xml version="1.0"?><tsqp version="1.0"><serverinfo uptime="5"/>')
            conn.sendall(b'<players online="3"/></tsqp>')
        elif mode == 'silent':
            threading.Event().wait(3)
        conn.close()
        srv.close()

    threading.Thread(target=run, daemon=True).start()
    return port


ok(W.ask_status('127.0.0.1', fake_server('answer'), 2), 'a server that answers is up')
ok(not W.ask_status('127.0.0.1', fake_server('silent'), 1), 'a server that never answers is hung')
ok(not W.ask_status('127.0.0.1', fake_server('close'), 1), 'a server that closes at once is not up')
free = socket.socket()
free.bind(('127.0.0.1', 0))
port = free.getsockname()[1]
free.close()
ok(not W.ask_status('127.0.0.1', port, 1), 'nothing listening is not up')
ok(W.is_status_reply(b'<tsqp></tsqp>') and not W.is_status_reply(b'<tsqp>'), 'a reply needs the whole document')

state = {'misses': 0}
state, restart = W.decide(False, state, 3)
ok(state['misses'] == 1 and not restart, 'first miss: no restart')
state, restart = W.decide(False, state, 3)
ok(state['misses'] == 2 and not restart, 'second miss: no restart')
state, restart = W.decide(True, state, 3)
ok(state['misses'] == 0 and not restart, 'an answer resets the count')
for _ in range(2):
    state, restart = W.decide(False, state, 3)
state, restart = W.decide(False, state, 3)
ok(restart and state['misses'] == 0, 'third miss in a row: restart, count starts over')

with tempfile.TemporaryDirectory() as d:
    path = os.path.join(d, 'state.json')
    ok(W.load_state(path) == {'misses': 0}, 'no state file: zero misses')
    W.save_state(path, {'misses': 2})
    ok(W.load_state(path) == {'misses': 2}, 'state survives between runs')
    with open(path, 'w') as f:
        f.write('not json')
    ok(W.load_state(path) == {'misses': 0}, 'a broken state file counts as zero')

print('chaos_watchdog_test: %d checks OK' % checks)
