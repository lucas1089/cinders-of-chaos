#!/usr/bin/env python3
"""Live test of the equip hotkey and the two ring slots (src-patch 0023, server/README.md "Second ring slot").

TEST SERVER ONLY. Needs a running server and its database. Not part of CI. Standard library only.

  python3 -I server/tools/loadtest.py setup --count 1 --db DB --pos X,Y,Z     # once: the bot "Loadbot Aaa"
  python3 -I server/tools/ring_hotkey_test.py --db DB [loadtest run options: --host, --port, --key, --dev-key, ...]
  python3 -I server/tools/loadtest.py cleanup --db DB                         # afterwards

The database is reached as loadtest.py reaches it (CHAOS_DB_HOST / _PORT / _USER / _PASS). Each case writes the
bot's inventory while it is offline, logs it in over the 10.98 protocol (loadtest.py), sends the equip hotkey
(0x77, u16 client id), logs out and reads player_items back: where each ring is now (slot 9, slot 10 or a container).
The bot's inventory is overwritten. Exit status 0 when every case passed.

Item ids are the base server's: backpack 1988, wedding ring 2121 (client id 3004), ring of wishes 2357 (client id
3245). Both rings have no worn id and no might ring key, so only the slot rules are tested.
"""
import asyncio
import os
import struct
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import loadtest as lt  # noqa: E402

BACKPACK = 1988
RING, RING_CID = 2121, 3004
OTHER, OTHER_CID = 2357, 3245
NAME = lt.bot_name(0)


def query(args, statement):
    """the rows of one SELECT, header line dropped"""
    lines = lt.sql(args, [statement]).splitlines()
    return [line.split('\t') for line in lines[1:] if line]


def player_id(args):
    rows = query(args, "SELECT `id` FROM `players` WHERE `name` = '%s';" % NAME)
    if not rows:
        sys.exit('no character "%s": run loadtest.py setup --count 1 first' % NAME)
    return int(rows[0][0])


def online(args, pid):
    return bool(query(args, "SELECT 1 FROM `players_online` WHERE `player_id` = %d;" % pid))


def set_items(args, pid, rows):
    st = ["DELETE FROM `player_items` WHERE `player_id` = %d;" % pid]
    for parent, sid, itemtype in rows:
        st.append("INSERT INTO `player_items` (`player_id`, `pid`, `sid`, `itemtype`, `count`, `attributes`) "
                  "VALUES (%d, %d, %d, %d, 1, '');" % (pid, parent, sid, itemtype))
    lt.sql(args, st)


def where(args, pid, itemtype):
    """'slot N' for an inventory slot, 'backpack' for a container, one entry per item of that type"""
    rows = query(args, "SELECT `pid` FROM `player_items` WHERE `player_id` = %d AND `itemtype` = %d;" % (pid, itemtype))
    return sorted('slot %s' % r[0] if int(r[0]) <= 10 else 'backpack' for r in rows)


async def drain(conn):
    while True:
        await conn.read_message()


async def session(args, hotkeys):
    bot = lt.Bot(0, args, args.n_rsa, {})
    session_key, world = await bot.login_server()
    conn = await bot.enter_game(session_key, world)
    reader = asyncio.ensure_future(drain(conn))
    try:
        await asyncio.sleep(1.5)
        for cid in hotkeys:
            conn.send(b'\x77' + struct.pack('<H', cid))
            await conn.w.drain()
            await asyncio.sleep(1.0)
        conn.send(b'\x14')  # logout
        await conn.w.drain()
        await asyncio.sleep(2.0)
    finally:
        reader.cancel()
        conn.w.close()


def case(args, pid, title, rows, hotkeys, want):
    for _ in range(40):
        if not online(args, pid):
            break
        time.sleep(0.5)
    else:
        sys.exit('"%s" is still online' % NAME)
    set_items(args, pid, rows)
    for attempt in range(3):
        time.sleep(5)  # the engine refuses quick reconnects from one address
        try:
            asyncio.run(session(args, hotkeys))
            break
        except (OSError, asyncio.IncompleteReadError, asyncio.TimeoutError, RuntimeError) as e:
            print('  retry after %r' % e)
    else:
        print('FAIL  %s: the bot could not log in' % title)
        return False
    for _ in range(40):
        if not online(args, pid):
            break
        time.sleep(0.5)
    got = {RING: where(args, pid, RING), OTHER: where(args, pid, OTHER)}
    ok = all(got[k] == sorted(v) for k, v in want.items())
    print('%s  %s: %s' % ('PASS' if ok else 'FAIL', title, got))
    return ok


CASES = [
    ('ring in slot 9, slot 10 empty: the hotkey takes it off',
     [(3, 101, BACKPACK), (9, 102, RING)], [RING_CID], {RING: ['backpack'], OTHER: []}),
    ('ring in slot 10, slot 9 empty: the hotkey takes it off',
     [(3, 101, BACKPACK), (10, 102, RING)], [RING_CID], {RING: ['backpack'], OTHER: []}),
    ('ring in the backpack, both slots empty: the hotkey puts it in slot 9',
     [(3, 101, BACKPACK), (101, 102, RING)], [RING_CID], {RING: ['slot 9'], OTHER: []}),
    ('another ring in slot 9: the hotkey puts the ring in slot 10',
     [(3, 101, BACKPACK), (9, 102, OTHER), (101, 103, RING)], [RING_CID], {RING: ['slot 10'], OTHER: ['slot 9']}),
    ('rings in both slots: the hotkey of the slot 9 ring takes it off, slot 10 stays',
     [(3, 101, BACKPACK), (9, 102, RING), (10, 103, OTHER)], [RING_CID], {RING: ['backpack'], OTHER: ['slot 10']}),
    ('ring in slot 9, the hotkey twice: off, then on again into slot 9',
     [(3, 101, BACKPACK), (9, 102, RING)], [RING_CID, RING_CID], {RING: ['slot 9'], OTHER: []}),
]


def main(argv):
    if argv and argv[0] in ('-h', '--help'):
        print(__doc__)
        return 0
    args = lt.parse(['run', '--count', '1'] + argv)
    args.n_rsa = lt.modulus_from_pem(args.key) if args.key else lt.OT_RSA_N
    pid = player_id(args)
    results = [case(args, pid, *c) for c in CASES]
    print('%d/%d passed' % (sum(results), len(results)))
    return 0 if all(results) else 1


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
