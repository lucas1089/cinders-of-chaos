#!/usr/bin/env python3
"""Tests of check_launcher_only.py: python3 -I tools/ci/check_launcher_only_test.py
The repository passes, and each way of forgetting the wiring is caught."""
import os
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import check_launcher_only as c  # noqa: E402

KEYS = ('.github/workflows/windows-package.yml', '.github/workflows/windows-client.yml',
        '.github/workflows/android-client.yml', 'client/base-patches/0198-launcher-start-only.patch',
        'tools/windows/package/start-client.bat')


def real():
    return {k: c.read(k) for k in KEYS}


class LauncherOnly(unittest.TestCase):
    def test_the_repository_is_wired(self):
        self.assertEqual(c.problems(), [])

    def broken(self, key, old, new, count=1):
        f = real()
        self.assertIn(old, f[key], old)
        f[key] = f[key].replace(old, new, count)
        return c.problems(f)

    def test_the_windows_configure_lines_need_the_option(self):
        for wf in KEYS[:2]:
            p = self.broken(wf, '-DCHAOS_REQUIRE_LAUNCHER=ON', '', 5)
            self.assertTrue(any('without -DCHAOS_REQUIRE_LAUNCHER=ON' in x for x in p), (wf, p))

    def test_android_never_gets_it(self):
        f = real()
        f['.github/workflows/android-client.yml'] += '\n          cmake -DCHAOS_REQUIRE_LAUNCHER=ON ..\n'
        self.assertTrue(any('android' in x for x in c.problems(f)))

    def test_the_patch_option_defaults_off_and_main_calls_the_check(self):
        k = 'client/base-patches/0198-launcher-start-only.patch'
        self.assertTrue(any('default to OFF' in x for x in self.broken(k, '" OFF)', '" ON)')))
        self.assertTrue(any('requireOrExit' in x for x in self.broken(k, 'chaoslauncher::requireOrExit()', 'x()', 9)))
        self.assertTrue(any('Android' in x for x in self.broken(k, '&& !defined(ANDROID)', '', 9)))

    def test_the_launcher_is_built_with_the_key_and_kept_in_the_package(self):
        k = '.github/workflows/windows-package.yml'
        self.assertTrue(any('without CHAOS_CLIENT_KEY' in x for x in
                            self.broken(k, 'CHAOS_CLIENT_KEY: ${{ secrets.CHAOS_CLIENT_KEY }}\n        run: |\n          # the facts of the setup program',
                                        'FOO: 1\n        run: |\n          # the facts of the setup program')))
        f = real()
        f[k] += '\n          rm -f "$P/client/CindersLauncher.exe"\n'
        self.assertTrue(any('must keep CindersLauncher.exe' in x for x in c.problems(f)))
        self.assertTrue(any('chaos_build.txt' in x for x in self.broken(k, 'chaos_build.txt', 'other.txt', 9)))

    def test_the_bat_starts_the_launcher(self):
        k = 'tools/windows/package/start-client.bat'
        self.assertTrue(any('--play-local' in x for x in self.broken(k, '--play-local', '', 9)))
        f = real()
        f[k] += 'start "" "%~dp0client\\Chaos.exe"\n'
        self.assertTrue(any('directly' in x for x in c.problems(f)))


if __name__ == '__main__':
    unittest.main(verbosity=1)
