#!/usr/bin/env python3
"""The game starts only through the launcher (O552 phase D, client base patch 0198): the release wiring must not be forgotten.

  python3 -I tools/ci/check_launcher_only.py

A Windows exe that is built without -DCHAOS_REQUIRE_LAUNCHER=ON is an exe anyone can start by hand, with no check at all. This
reads the workflows and the package files and fails when
  * a workflow that builds the Windows client (windows-package.yml, windows-client.yml) does not pass the option ON,
  * android-client.yml passes it (a phone has no launcher; the option is compiled out there),
  * the base patch 0198 is missing, or its CMake option is not OFF by default,
  * windows-package.yml builds the launcher without the client key secret in its environment (a launcher built without it makes
    tickets only a development client accepts),
  * the full local package's start-client.bat starts Chaos.exe directly instead of through CindersLauncher.exe --play-local,
    or windows-package.yml still removes the launcher from that package or forgets chaos_build.txt.
Exit 0 when the wiring is right.
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def read(rel):
    with open(os.path.join(ROOT, rel), encoding='utf-8') as f:
        return f.read()


def problems(files=None):
    """files: relative path -> text, or None to read the repository. Returns a list of problems."""
    def get(rel):
        if files is not None:
            return files.get(rel)
        return read(rel) if os.path.exists(os.path.join(ROOT, rel)) else None

    out = []
    for wf in ('.github/workflows/windows-package.yml', '.github/workflows/windows-client.yml'):
        text = get(wf)
        if text is None:
            out.append(f'{wf}: missing')
            continue
        cmakes = [l for l in text.splitlines() if re.search(r'cmake\s+-B\s+build', l) and 'CHAOS_CLIENT_BUILD' in l]
        if not cmakes:
            out.append(f'{wf}: no configure line of the Windows client found (cmake -B build ... -DCHAOS_CLIENT_BUILD=)')
        for l in cmakes:
            if '-DCHAOS_REQUIRE_LAUNCHER=ON' not in l:
                out.append(f'{wf}: the client is configured without -DCHAOS_REQUIRE_LAUNCHER=ON: {l.strip()[:90]}...')
    android = get('.github/workflows/android-client.yml')
    if android is not None and re.search(r'CHAOS_REQUIRE_LAUNCHER=(ON|1|TRUE)', android, re.I):
        out.append('.github/workflows/android-client.yml: a phone has no launcher, the option must stay off')

    patch = get('client/base-patches/0198-launcher-start-only.patch')
    if patch is None:
        out.append('client/base-patches/0198-launcher-start-only.patch: missing')
    else:
        if 'option(CHAOS_REQUIRE_LAUNCHER' not in patch or not re.search(r'option\(CHAOS_REQUIRE_LAUNCHER "[^"]*" OFF\)', patch):
            out.append('0198: the CMake option CHAOS_REQUIRE_LAUNCHER must exist and default to OFF')
        if 'chaoslauncher::requireOrExit()' not in patch:
            out.append('0198: main() does not call chaoslauncher::requireOrExit()')
        if not re.search(r'#if defined\(CHAOS_REQUIRE_LAUNCHER\) && !defined\(ANDROID\)', patch):
            out.append('0198: the check must be compiled out on Android')

    pkg = get('.github/workflows/windows-package.yml') or ''
    m = re.search(r'- name: Build the launcher \(O314\)(.*?)(?=\n      #|\n      - name:)', pkg, re.S)
    if not m:
        out.append('windows-package.yml: the step "Build the launcher (O314)" is missing')
    elif 'CHAOS_CLIENT_KEY: ${{ secrets.CHAOS_CLIENT_KEY }}' not in m.group(1):
        out.append('windows-package.yml: the launcher is built without CHAOS_CLIENT_KEY (its tickets would only open a development client)')
    if re.search(r'rm -f "\$P/client/CindersLauncher\.exe"', pkg):
        out.append('windows-package.yml: the full local package must keep CindersLauncher.exe (start-client.bat needs it)')
    if 'chaos_build.txt' not in pkg:
        out.append('windows-package.yml: the full local package gets no chaos_build.txt (the build number --play-local puts in the ticket)')

    bat = get('tools/windows/package/start-client.bat')
    if bat is None:
        out.append('tools/windows/package/start-client.bat: missing')
    else:
        if 'CindersLauncher.exe' not in bat or '--play-local' not in bat:
            out.append('start-client.bat must start the game with CindersLauncher.exe --play-local')
        if re.search(r'start\s+""\s+"[^"]*Chaos\.exe"', bat):
            out.append('start-client.bat starts Chaos.exe directly: the game would refuse (no ticket)')
    return out


def main():
    bad = problems()
    for p in bad:
        print('FAIL ' + p)
    print('launcher-only wiring: %s' % ('FAIL' if bad else 'ok'))
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main())
