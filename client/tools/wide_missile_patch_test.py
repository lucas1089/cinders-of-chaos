#!/usr/bin/env python3
"""Guard for client base patch 0208: missile ids above 255, the client side (O737; server src-patch 0094).

The client engine already reads a u16 missile id in 0x85 under its feature GameDistanceEffectU16 (77). The patch only makes the login ask
for it and clears the feature before every 1098 login. This test reads the patch text and checks that
  * it is the only patch numbered 0208, touches only protocolgamesend.cpp and only adds lines,
  * the "W" block (u16 length 1, "W", u8 with bit 0) is written right after the capability byte of patch 0100, only for protocol 1098, only
    with the encrypted login and only when its 4 bytes fit the RSA block (the server's chaoswidemissile.h holds the same 4 and 'W'),
  * feature 77 is cleared next to the other negotiated features, only for protocol 1098 (the 8.60 profile keeps it),
  * every hunk has as many leading as trailing context lines,
and applies the patch to a tree rebuilt from its own context with patch -p1 --fuzz=0. With BASE_TREE=<client source root with 0001-0207
applied> it also runs patch --dry-run on the real tree (client/BASE.md "Missile ids above 255 (O737)").
Run: python3 -I client/tools/wide_missile_patch_test.py (standard library only)."""
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
PATCHES = os.path.join(HERE, '..', 'base-patches')
SERVER_PATCH = os.path.join(HERE, '..', '..', 'server', 'src-patches', '0094-wide-missile-ids.patch')
NAME = '0208-wide-missile-ids.patch'
fails = 0


def check(cond, what):
    global fails
    if not cond:
        fails += 1
        print('FAIL ' + what)


files = sorted(f for f in os.listdir(PATCHES) if f.endswith('.patch'))
check([f for f in files if f.startswith('0208-')] == [NAME], 'one patch numbered 0208')
text = open(os.path.join(PATCHES, NAME), encoding='utf-8').read()
body = text[text.index('diff --git'):]
touched = re.findall(r'^diff --git a/(\S+) b/\S+', body, re.M)
check(touched == ['src/client/protocolgamesend.cpp'], 'the files the patch touches: %r' % touched)
removed = [l for l in body.splitlines() if l.startswith('-') and not l.startswith('---')]
check(removed == [], 'the patch removes no line')
for f in files:
    if f > NAME:
        gone = [l for l in open(os.path.join(PATCHES, f), encoding='utf-8').read().splitlines()
                if l.startswith('-') and not l.startswith('---')]
        check(not any('CHAOS_CAPABILIT' in l and '2' in l or 'base patch 0208' in l for l in gone), 'no later patch removes 0208: ' + f)

check('constexpr auto CHAOS_CAPABILITIES2_MARKER = "W";' in body, 'the marker W')
check('constexpr uint8 CHAOS_CAPABILITY2_MISSILE_U16 = 1U << 0;' in body, 'bit 0 asks for 16-bit missiles')
check('constexpr int CHAOS_CAPABILITIES2_BYTES = 4;' in body, 'the block is 4 bytes')
block = ('         msg->addU8(ASTRA_CAPABILITIES);\n'
         '+        // Chaos (base patch 0208)')
check(block in body, 'the "W" block right after the capability byte of patch 0100')
check('+        if (g_game.getProtocolVersion() == 1098 && encryptLogin && chaosPayload + CHAOS_CAPABILITIES2_BYTES <= rsaSize) {' in body,
      'only for 1098, encrypted, and when it fits the RSA block')
check('+        const int chaosPayload = static_cast<int>(msg->getMessageSize()) - offset;' in body, 'the payload counts from the block start')
i_str = body.find('+            msg->addString(std::string(CHAOS_CAPABILITIES2_MARKER));')
i_u8 = body.find('+            msg->addU8(CHAOS_CAPABILITY2_MISSILE_U16);')
check(0 <= i_str < i_u8, 'the string, then the byte')
check('     g_game.disableFeature(Otc::GameChaosImpactText);' in body and
      '+    if (g_game.getProtocolVersion() == 1098)\n+        g_game.disableFeature(Otc::GameDistanceEffectU16);' in body,
      'feature 77 cleared before a 1098 login, next to the other negotiated features')
check('enableFeature' not in ''.join(l for l in body.splitlines() if l.startswith('+')), 'the client never turns 77 on by itself')

server = open(SERVER_PATCH, encoding='utf-8').read()
check("static constexpr char MARKER = 'W';" in server and 'static constexpr size_t MARKER_BYTES = 4;' in server and
      'static constexpr uint8_t CAPABILITY_MISSILE_U16 = 1 << 0;' in server and
      'static constexpr uint8_t FEATURE_DISTANCE_EFFECT_U16 = 77;' in server,
      'the server reads the same marker, size, bit and feature (src-patch 0094)')

for h in re.split(r'(?m)^(?=@@ )', body)[1:]:
    kinds = [l[:1] for l in h.splitlines()[1:]]
    lead = 0
    while lead < len(kinds) and kinds[lead] == ' ':
        lead += 1
    trail = 0
    while trail < len(kinds) and kinds[len(kinds) - 1 - trail] == ' ':
        trail += 1
    check(lead == trail and lead >= 2, 'hunk %r has %d leading and %d trailing context lines' % (h.splitlines()[0][:40], lead, trail))

patch = shutil.which('patch')
if patch:
    tmp = tempfile.mkdtemp()
    try:
        path = os.path.join(tmp, 'src', 'client', 'protocolgamesend.cpp')
        os.makedirs(os.path.dirname(path))
        out = []
        for n, h in enumerate(re.split(r'(?m)^(?=@@ )', body)[1:], 1):
            out.append('// filler before hunk %d' % n)
            out += [l[1:] for l in h.splitlines()[1:] if l[:1] in (' ', '-')]
            out.append('// filler after hunk %d' % n)
        with open(path, 'w', encoding='utf-8') as fh:
            fh.write('\n'.join(out) + '\n')
        r = subprocess.run([patch, '-p1', '--fuzz=0', '-i', os.path.join(PATCHES, NAME)], cwd=tmp, capture_output=True, text=True)
        check(r.returncode == 0, 'patch -p1 --fuzz=0 applies to a tree of its own context: ' + r.stdout + r.stderr)
        if r.returncode == 0:
            check('CHAOS_CAPABILITY2_MISSILE_U16' in open(path, encoding='utf-8').read(), 'applied')
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
base = os.environ.get('BASE_TREE')
if base:
    r = subprocess.run(['patch', '-p1', '--fuzz=0', '--dry-run', '-i', os.path.join(PATCHES, NAME)], cwd=base, capture_output=True, text=True)
    check(r.returncode == 0, 'patch --dry-run on BASE_TREE: ' + r.stdout + r.stderr)

if fails:
    print('%d failed' % fails)
    sys.exit(1)
print('wide missile client patch tests: ok')
