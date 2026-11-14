#!/usr/bin/env python3
"""python3 -I server/tools/install_fun_looks_test.py : install_fun_looks.py (O566, install step `funlooks`) and the pair 72 manifest of
install_auras.py on a synthetic server folder: the moth ids read from chaos_fun_costumes.lua, the client pair guard end to end (missing
or 71: nothing written and a WARNING line; 72: the Dusk Moth file moves from look 213 to 3523, the Rune Seal aura 32 from client look 2186
to 3524 with its aura id and name kept), idempotent, a file with another look stops the step, a missing file stops it, --dry-run writes
nothing, lowering the record puts the aura block back. No base server needed."""
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import install_fun_looks as F  # noqa: E402
import install_auras as A  # noqa: E402

REPO = os.path.dirname(os.path.dirname(HERE))
TOOL = os.path.join(HERE, 'install_fun_looks.py')
AURAS = os.path.join(HERE, 'install_auras.py')
failed = 0

MOTH = ('<?xml version="1.0" encoding="UTF-8"?>\n<!-- Dusk Moth -->\n<monster name="Dusk Moth" nameDescription="a dusk moth" race="venom">\n'
        '\t<health now="40" max="40" />\n\t<look type="%d" corpse="0" />\n</monster>\n')
BASE_AURAS = '<?xml version="1.0"?>\n<auras>\n\t<aura id="1" clientid="932" name="Fire Essence" speed="20" />\n</auras>\n'


def check(ok, what):
    global failed
    if not ok:
        failed += 1
        print('FAIL:', what)


def run(tool, *args):
    p = subprocess.run([sys.executable, '-I', tool] + list(args), stdout=subprocess.PIPE, stderr=subprocess.STDOUT, universal_newlines=True)
    return p.returncode, p.stdout


def server(tmp, name, pair, look=213):
    srv = os.path.join(tmp, name)
    data = os.path.join(srv, 'data')
    os.makedirs(os.path.join(data, 'monster', 'monsters', 'chaos', 'pets'))
    os.makedirs(os.path.join(data, 'monster', 'monsters', 'other'))
    os.makedirs(os.path.join(data, 'XML'))
    open(os.path.join(data, 'monster', 'monsters', 'chaos', 'pets', 'dusk_moth.xml'), 'w').write(MOTH % look)
    # another monster with look 213 must stay alone
    open(os.path.join(data, 'monster', 'monsters', 'other', 'butterfly.xml'), 'w').write(MOTH.replace('Dusk Moth', 'Butterfly') % 213)
    open(os.path.join(data, 'XML', 'auras.xml'), 'w').write(BASE_AURAS)
    if pair is not None:
        open(os.path.join(srv, 'config.lua'), 'w').write('chaosClientPair = %d\n' % pair)
    return data


def moth(data):
    return open(os.path.join(data, 'monster', 'monsters', 'chaos', 'pets', 'dusk_moth.xml')).read()


def main():
    old, new = F.moth_looks()
    check((old, new) == (213, 3523), 'the moth looks of chaos_fun_costumes.lua: %s' % ((old, new),))
    check(F.retype(MOTH % 213, 213, 3523)[1] == 'moved' and F.retype(MOTH % 3523, 213, 3523)[1] == 'done'
          and F.retype(MOTH % 7, 213, 3523)[1] == 'other', 'retype states')
    with tempfile.TemporaryDirectory() as tmp:
        # guard: no config.lua, pair 71
        for name, pair in (('none', None), ('p71', 71)):
            data = server(tmp, name, pair)
            rc, out = run(TOOL, data)
            check(rc == 0 and 'WARNING: funlooks skipped' in out and 'client-pair set 72' in out, '%s: skipped with a WARNING: %s' % (name, out))
            check(moth(data) == MOTH % 213, '%s: the moth file is unchanged' % name)
            rc, out = run(AURAS, data)
            xml = open(os.path.join(data, 'XML', 'auras.xml')).read()
            check(rc == 0 and 'WARNING: auras (round Rune Seal) skipped' in out and 'clientid="2186"' in xml and 'clientid="3524"' not in xml,
                  '%s: the aura keeps the old ring: %s' % (name, out))
        # pair 72
        data = server(tmp, 'p72', 72)
        rc, out = run(TOOL, data, '--dry-run')
        check(rc == 0 and 'dry run' in out and moth(data) == MOTH % 213, 'dry run writes nothing')
        rc, out = run(TOOL, data)
        check(rc == 0 and '1 moved to look 3523' in out and moth(data) == MOTH % 3523, 'pair 72: the pet moves to 3523: %s' % out)
        butterfly = open(os.path.join(data, 'monster', 'monsters', 'other', 'butterfly.xml')).read()
        check(butterfly == MOTH.replace('Dusk Moth', 'Butterfly') % 213, 'another monster on look 213 is left alone')
        rc, out = run(TOOL, data)
        check(rc == 0 and '0 moved' in out and '1 already there' in out and moth(data) == MOTH % 3523, 'a second run changes nothing')
        rc, out = run(AURAS, data)
        xml = open(os.path.join(data, 'XML', 'auras.xml')).read()
        check(rc == 0, 'install_auras runs: %s' % out)
        check('<aura id="32" clientid="3524" name="Rune Seal" speed="20" />' in xml and 'clientid="2186"' not in xml, 'pair 72: aura 32 is the round ring')
        check(xml.count('id="32"') == 1 and '<aura id="31" clientid="2185" name="Blood Vortex"' in xml, 'one aura 32, the Blood Vortex stays')
        rc, out = run(AURAS, data)
        check(rc == 0 and open(os.path.join(data, 'XML', 'auras.xml')).read() == xml, 'a second aura run changes nothing')
        # the record is lowered again (a rollback of the client): the aura goes back to 2186
        open(os.path.join(os.path.dirname(data), 'config.lua'), 'w').write('chaosClientPair = 71\n')
        rc, out = run(AURAS, data)
        xml = open(os.path.join(data, 'XML', 'auras.xml')).read()
        check(rc == 0 and '<aura id="32" clientid="2186" name="Rune Seal"' in xml and '3524' not in xml, 'pair 71 again: the old ring is back')
        # a moth file with another look, a missing file
        data = server(tmp, 'odd', 72, look=77)
        rc, out = run(TOOL, data)
        check(rc == 1 and 'expected 213 or 3523' in out and moth(data) == MOTH % 77, 'another look stops the step')
        data = server(tmp, 'gone', 72)
        os.remove(os.path.join(data, 'monster', 'monsters', 'chaos', 'pets', 'dusk_moth.xml'))
        rc, out = run(TOOL, data)
        check(rc == 1 and 'no monster file of Dusk Moth' in out, 'a missing file stops the step')
        rc, out = run(TOOL)
        check(rc == 1, 'no data folder prints the help')
    # the shipped manifest
    rows = A.read_manifest(A.PAIR72_MANIFEST)
    check(rows == [(32, 3524, 'Rune Seal')], 'the pair 72 manifest: %s' % rows)
    if failed:
        print('%d failures' % failed)
        sys.exit(1)
    print('install_fun_looks_test: OK')


if __name__ == '__main__':
    main()
