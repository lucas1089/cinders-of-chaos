#!/usr/bin/env python3
"""Opcode coverage of the Unity client (O433 phase 5, track S).
Every client-facing extended opcode (ChaosOpcodes of server/data/scripts/chaos/chaos_constants.lua, and the opcodes the
main client modules register) must be handled in Unity or sit in tools/ci/unity_opcodes_allowlist.txt with a reason.
Handled means: an Ext.On( / OnText( registration with that number or a named constant, a panel base(e, OpcodeId) or
new XState(e, Opcode) call, a parser branch (op == NAME), a send by name (SendExtended(NAME, / Ext.Send(NAME,) or a member
of class HudOp. A name resolves to the nearest constant of that name above the call in the same file. The allowlist can only
shrink: an entry that Unity handles now, or that no longer exists, fails the check.
Allowlist lines: NUMBER | reason   (# starts a comment). Reasons starting "not ported yet" are the open work.
python3 -I tools/ci/check_unity_opcodes.py        # check (exit 1 on a problem)
python3 -I tools/ci/check_unity_opcodes.py --list # print the table
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CONSTANTS = os.path.join('server', 'data', 'scripts', 'chaos', 'chaos_constants.lua')
MODULES = os.path.join('client', 'overlay', 'modules')
UNITY = os.path.join('unity', 'Client', 'Assets', 'Chaos')
ALLOW = os.path.join('tools', 'ci', 'unity_opcodes_allowlist.txt')


def read(root, rel):
    with open(os.path.join(root, rel), encoding='utf-8', errors='replace') as f:
        return f.read()


def walk(root, rel, ext):
    out = []
    for d, _, files in os.walk(os.path.join(root, rel)):
        for n in sorted(files):
            if n.endswith(ext):
                out.append(os.path.relpath(os.path.join(d, n), root))
    return sorted(out)


def strip_lua_comment(line):
    i = line.find('--')
    return line if i < 0 else line[:i]


def server_opcodes(root=ROOT):
    """{number: [names]} from the ChaosOpcodes table and the ChaosOpcodes.name = N lines."""
    text = read(root, CONSTANTS)
    out = {}
    m = re.search(r'ChaosOpcodes\s*=\s*\{(.*?)\n\}', text, re.S)
    if m:
        for line in m.group(1).splitlines():
            mm = re.match(r'\s*([A-Za-z_]\w*)\s*=\s*(\d+)', strip_lua_comment(line))
            if mm:
                out.setdefault(int(mm.group(2)), []).append('ChaosOpcodes.' + mm.group(1))
    for line in text.splitlines():
        mm = re.match(r'\s*ChaosOpcodes\.([A-Za-z_]\w*)\s*=\s*(\d+)\s*$', strip_lua_comment(line))
        if mm:
            out.setdefault(int(mm.group(2)), []).append('ChaosOpcodes.' + mm.group(1))
    return out


def client_opcodes(root=ROOT):
    """{number: [module]} from registerExtendedOpcode(ARG, ...) with ARG a number or a name defined as a number in the file."""
    out = {}
    for rel in walk(root, MODULES, '.lua'):
        if rel.endswith('_test.lua'):
            continue
        text = read(root, rel)
        for m in re.finditer(r'registerExtendedOpcode\(\s*([\w.]+)\s*,', text):
            if text[max(0, m.start() - 2):m.start()] == 'un' or 'unregister' in text[max(0, m.start() - 3):m.start()].lower():
                continue
            arg = m.group(1)
            num = None
            if arg.isdigit():
                num = int(arg)
            else:
                name = arg.split('.')[-1]
                d = re.search(r'\b' + re.escape(name) + r'\s*=\s*(\d+)\s*(?:--.*)?$', text, re.M)
                if d:
                    num = int(d.group(1))
            if num is not None and 0 < num < 256:
                out.setdefault(num, []).append(rel.split(os.sep)[-2])
    return out


def _num(text):
    return int(text, 16) if text.lower().startswith('0x') else int(text)


def unity_handled(root=ROOT):
    """Set of opcode numbers Unity registers: the first argument of On( / OnText( (a number, or a named constant), the opcode argument
    of base(e, N) / new XState(e, N), a parser branch (op == NAME), a send by name (SendExtended(NAME,), and the members of class HudOp. A name is resolved to the nearest constant of that name above the
    call in the same file, else to the one constant of that name in the project."""
    files = [(rel, read(root, rel)) for rel in walk(root, UNITY, '.cs')]
    consts = {}  # name -> [(file, pos, value)]
    for rel, text in files:
        for m in re.finditer(r'\b(?:const|static\s+readonly)\s+(?:byte|int|uint|ushort)\s+([^;(]+);', text):
            for part in m.group(1).split(','):
                d = re.match(r'\s*(\w+)\s*=\s*(0[xX][0-9A-Fa-f]+|\d+)\s*$', part)
                if d:
                    consts.setdefault(d.group(1), []).append((rel, m.start(), _num(d.group(2))))
    handled = set()

    def resolve(rel, pos, arg):
        arg = arg.strip()
        arg = re.sub(r'^\(\s*byte\s*\)\s*', '', arg)
        if re.fullmatch(r'0[xX][0-9A-Fa-f]+|\d+', arg):
            return [_num(arg)]
        if not re.fullmatch(r'[A-Za-z_][\w.]*', arg):
            return []
        name = arg.split('.')[-1]
        cands = consts.get(name, [])
        same = [c for c in cands if c[0] == rel and c[1] < pos]
        if same:
            return [max(same, key=lambda c: c[1])[2]]
        vals = {c[2] for c in cands}
        return list(vals) if len(vals) == 1 else []

    call = re.compile(r'\b(?:On|OnText)\(\s*(?:\(\s*byte\s*\)\s*)?([^,()]+(?:\([^()]*\))?[^,()]*),|:\s*base\(\s*\w+\s*,\s*([^,)]+)\)|\bnew\s+\w+State\(\s*\w+\s*,\s*([^,)]+)\)|\bop\s*==\s*([\w.]+)\b|\b(?:SendExtended|SendText|Ext\.Send|ext\.Send|Send)\(\s*([\w.]+)\s*,')
    for rel, text in files:
        for m in call.finditer(text):
            arg = m.group(1) or m.group(2) or m.group(3) or m.group(4) or m.group(5)
            handled.update(v for v in resolve(rel, m.start(), arg) if 0 < v < 256)
        hud = re.search(r'class\s+HudOp\s*\{(.*?)\n\s*\}', text, re.S)
        if hud:
            for m in re.finditer(r'\b[A-Z]\w*\s*=\s*(\d+)\b', re.sub(r'///.*', '', hud.group(1))):
                handled.add(int(m.group(1)))
    return handled


def load_allow(root=ROOT):
    """{number: reason}. Raises ValueError on a line without a reason."""
    out = {}
    path = os.path.join(root, ALLOW)
    if not os.path.exists(path):
        return out
    for n, line in enumerate(read(root, ALLOW).splitlines(), 1):
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        num, _, reason = line.partition('|')
        if not num.strip().isdigit() or not reason.strip():
            raise ValueError('%s:%d: want "NUMBER | reason": %r' % (ALLOW, n, line))
        if int(num) in out:
            raise ValueError('%s:%d: opcode %s listed twice' % (ALLOW, n, num.strip()))
        out[int(num)] = reason.strip()
    return out


def problems(server, client, handled, allow):
    bad = []
    wanted = dict()
    for num, names in server.items():
        wanted.setdefault(num, []).extend(names)
    for num, mods in client.items():
        wanted.setdefault(num, []).extend('module ' + m for m in mods)
    for num in sorted(wanted):
        if num in handled and num in allow:
            bad.append('opcode %d is handled in Unity now: remove it from %s' % (num, ALLOW))
        elif num not in handled and num not in allow:
            bad.append('opcode %d (%s) has no Unity handler and no entry in %s' % (num, ', '.join(sorted(set(wanted[num]))), ALLOW))
    for num in sorted(allow):
        if num not in wanted:
            bad.append('allowlist opcode %d is not a client-facing opcode any more: remove it' % num)
        if len(allow[num]) < 8:
            bad.append('allowlist opcode %d needs a real reason' % num)
    return bad


def main(argv):
    server, client, handled, allow = server_opcodes(), client_opcodes(), unity_handled(), load_allow()
    if '--list' in argv:
        for num in sorted(set(server) | set(client)):
            names = sorted(set(server.get(num, [])) | set('module ' + m for m in client.get(num, [])))
            state = 'handled' if num in handled else 'allowlist: ' + allow.get(num, 'MISSING')
            print('%3d  %-9s %s' % (num, 'ok' if num in handled else 'open', ', '.join(names)) + ('' if num in handled else '  [' + state + ']'))
        return 0
    bad = problems(server, client, handled, allow)
    total = len(set(server) | set(client))
    if bad:
        print('check_unity_opcodes: %d problem(s)' % len(bad))
        for b in bad:
            print('  ' + b)
        return 1
    open_work = sum(1 for r in allow.values() if r.startswith('not ported yet'))
    print('check_unity_opcodes: ok (%d opcodes, %d handled in Unity, %d on the allowlist, %d of them not ported yet)' % (total, total - len(allow), len(allow), open_work))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
