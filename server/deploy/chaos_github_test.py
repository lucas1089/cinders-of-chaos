#!/usr/bin/env python3
"""Tests for server/deploy/chaos_github.sh (O530: the repository is private, the VPS reaches GitHub with one token).

The library is sourced by bash in a throwaway folder with a fake curl and a recording git. Checks: the token file (the
settings in order, a file that holds no token is no token), the credential helper of git (answers for https://github.com
only, reads the file at the moment git asks, no token no helper), that the token is on no command line and not in
.git/config, the words of a refused answer (private-repo, token-refused, no-access, github-unreachable), the slug of a
remote URL, the API call (the token on curl's stdin, none with CHAOS_GH_NOAUTH), and a release asset download (the API
asks for a signed address with the token, the download of that address carries no token; every failure has its reason).

usage: python3 -I server/deploy/chaos_github_test.py
"""
import os
import shutil
import stat
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
LIB = os.path.join(HERE, 'chaos_github.sh')
TOKEN = 'github_pat_11ABCDEFG0aBcDeFgHiJkL_mNoPqRsTuVwXyZ0123456789aBcDeFgHiJkLmNoPqRsTuVwXyZ01234'
TOKEN2 = 'ghp_' + 'a1B2c3D4e5' * 4

failures = 0


def check(cond, label):
    global failures
    if not cond:
        failures += 1
        print('FAIL', label)


CURL = r'''#!/usr/bin/env python3
import json, os, re, shutil, sys
stub = os.environ['STUB']
args = sys.argv[1:]
cfg = sys.stdin.read() if '-K' in args else ''
open(os.path.join(stub, 'calls'), 'a').write('curl ' + ' '.join(args) + '\n')
open(os.path.join(stub, 'cfg.log'), 'a').write(cfg + '--\n')
out = args[args.index('-o') + 1] if '-o' in args else None
m = re.search(r'url = "([^"]+)"', cfg)
url = m.group(1) if m else ''
def read(name, default=''):
    p = os.path.join(stub, name)
    return open(p).read() if os.path.exists(p) else default
def api(code, body=''):
    if out and out != '/dev/null':
        open(out, 'w').write(body)
    sys.stdout.write(str(code))
    sys.exit(0)
if re.search(r'/repos/o/r$', url):
    api(read('repo.code', '200').strip(), '{}')
if re.search(r'/repos/o/r/releases/tags/v1$', url):
    api(read('tag.code', '200').strip(), read('tag.json', '{}'))
m = re.search(r'/repos/o/r/releases/assets/(\d+)$', url)
if m:
    sys.stdout.write(read('asset.out', '302 https://objects.example.org/signed/%s?sig=S' % m.group(1)).strip())
    sys.exit(0)
if url.startswith('https://objects.example.org/signed/'):
    if os.path.exists(os.path.join(stub, 'dl.fail')):
        sys.exit(22)
    open(out, 'w').write('the asset bytes')
    sys.exit(0)
api(404)
'''

GIT = r'''#!/usr/bin/env bash
echo "git $*" >> "$STUB/calls"
env | grep -E '^(GIT_TERMINAL_PROMPT|CHAOS_GH_FILE)=' >> "$STUB/gitenv" || true
exec "$REALGIT" "$@"
'''


def main():
    real_git = shutil.which('git')
    with tempfile.TemporaryDirectory() as tmp:
        stub = os.path.join(tmp, 'stub')
        os.makedirs(stub)
        for name, body in (('curl', CURL), ('git', GIT)):
            p = os.path.join(stub, name)
            with open(p, 'w') as f:
                f.write(body)
            os.chmod(p, 0o755)
        tfile = os.path.join(tmp, 'github.token')
        base = dict(os.environ, PATH=stub + ':' + os.environ['PATH'], STUB=stub, REALGIT=real_git,
                    GIT_CONFIG_GLOBAL='/dev/null', GIT_CONFIG_SYSTEM='/dev/null')
        for k in ('CHAOS_GITHUB_TOKEN_FILE', 'CHAOS_ENGINE_TOKEN_FILE', 'CHAOS_GH_NOAUTH'):
            base.pop(k, None)

        def sh(script, stdin=None, **extra):
            env = dict(base, **extra)
            return subprocess.run(['bash', '-c', '. "%s"; %s' % (LIB, script)], env=env, input=stdin,
                                  capture_output=True, text=True)

        def put(name, text):
            with open(os.path.join(stub, name), 'w') as f:
                f.write(text)

        def drop(name):
            if os.path.exists(os.path.join(stub, name)):
                os.remove(os.path.join(stub, name))

        def calls():
            p = os.path.join(stub, 'calls')
            return open(p).read() if os.path.exists(p) else ''

        def cfgs():
            p = os.path.join(stub, 'cfg.log')
            return [c for c in open(p).read().split('--\n') if c.strip()] if os.path.exists(p) else []

        # ---- the token file: the settings in order
        other = os.path.join(tmp, 'engine.token')
        r = sh('chaos_gh_token_file', CHAOS_GITHUB_TOKEN_FILE=tfile, CHAOS_ENGINE_TOKEN_FILE=other)
        check(r.stdout == tfile, 'CHAOS_GITHUB_TOKEN_FILE wins: ' + r.stdout)
        r = sh('chaos_gh_token_file', CHAOS_ENGINE_TOKEN_FILE=other)
        check(r.stdout == other, 'CHAOS_ENGINE_TOKEN_FILE is the name of before: ' + r.stdout)
        if not os.path.exists('/etc/chaos/engine-build.token') and not os.path.exists('/etc/chaos/github.token'):
            r = sh('chaos_gh_token_file')
            check(r.stdout == '/etc/chaos/github.token', 'the default: ' + r.stdout)
        r = sh('chaos_gh_token_files', CHAOS_GITHUB_TOKEN_FILE=tfile)
        check(r.stdout.split() == [tfile], 'an explicit file is the only one to remove')
        r = sh('chaos_gh_token_files')
        check(r.stdout.split() == ['/etc/chaos/github.token', '/etc/chaos/engine-build.token'], 'both default files are removed')

        # ---- the token: a file that holds no token is no token
        check(sh('chaos_gh_token', CHAOS_GITHUB_TOKEN_FILE=tfile).stdout == '', 'no file, no token')
        for junk in ('x"\nheader = "Evil: 1\n', 'github_pat_short\n', TOKEN + '"\n', ''):
            with open(tfile, 'w') as f:
                f.write(junk)
            check(sh('chaos_gh_token', CHAOS_GITHUB_TOKEN_FILE=tfile).stdout == '', 'junk is no token: %r' % junk[:20])
        with open(tfile, 'w') as f:
            f.write(' ' + TOKEN + ' \r\n')
        os.chmod(tfile, 0o600)
        check(sh('chaos_gh_token', CHAOS_GITHUB_TOKEN_FILE=tfile).stdout == TOKEN, 'a token with white space around it')
        with open(tfile, 'w') as f:
            f.write(TOKEN2 + '\n')
        check(sh('chaos_gh_token', CHAOS_GITHUB_TOKEN_FILE=tfile).stdout == TOKEN2, 'a classic token shape')
        with open(tfile, 'w') as f:
            f.write(TOKEN + '\n')

        # ---- the credential helper of git: git itself runs it (git credential fill)
        env = dict(CHAOS_GITHUB_TOKEN_FILE=tfile)

        def fill(host, proto='https', **extra):
            return sh('chaos_gh_git credential fill', stdin='protocol=%s\nhost=%s\n\n' % (proto, host), **dict(env, **extra))

        r = fill('github.com')
        check(r.returncode == 0 and 'username=x-access-token\n' in r.stdout and 'password=' + TOKEN + '\n' in r.stdout,
              'the helper answers for https://github.com: ' + r.stdout + r.stderr)
        r = fill('evil.example.org')
        check('password=' not in r.stdout and TOKEN not in r.stdout + r.stderr, 'no token for another host: ' + r.stdout)
        r = fill('github.com', proto='http')
        check(TOKEN not in r.stdout + r.stderr, 'no token over plain http')
        r = fill('github.com.evil.example.org')
        check(TOKEN not in r.stdout + r.stderr, 'no token for a host that only starts with github.com')
        with open(tfile, 'w') as f:
            f.write(TOKEN2 + '\n')
        r = fill('github.com')
        check('password=' + TOKEN2 + '\n' in r.stdout, 'the file is read at the moment git asks')
        with open(tfile, 'w') as f:
            f.write(TOKEN + '\n')
        os.remove(tfile)
        r = fill('github.com')
        check(r.returncode != 0 and 'password=' not in r.stdout, 'no token file: no password and no prompt: ' + r.stdout + r.stderr)
        with open(tfile, 'w') as f:
            f.write(TOKEN + '\n')

        # ---- the token is on no command line and not in .git/config; a plain git when there is no token
        repo = os.path.join(tmp, 'repo')
        origin = os.path.join(tmp, 'origin.git')
        gitenv = dict(base, GIT_AUTHOR_NAME='t', GIT_AUTHOR_EMAIL='t@e.org', GIT_COMMITTER_NAME='t', GIT_COMMITTER_EMAIL='t@e.org')
        subprocess.run([real_git, 'init', '-q', '--bare', '-b', 'main', origin], env=gitenv, check=True)
        subprocess.run([real_git, 'clone', '-q', origin, repo], env=gitenv, check=True, capture_output=True)
        with open(os.path.join(repo, 'a.txt'), 'w') as f:
            f.write('a\n')
        subprocess.run([real_git, '-C', repo, 'add', '-A'], env=gitenv, check=True)
        subprocess.run([real_git, '-C', repo, 'commit', '-q', '-m', 'one'], env=gitenv, check=True)
        subprocess.run([real_git, '-C', repo, 'push', '-q', 'origin', 'HEAD:main'], env=gitenv, check=True, capture_output=True)
        put('calls', '')
        r = sh('chaos_gh_git -C "%s" fetch --quiet origin main' % repo, **env)
        check(r.returncode == 0, 'a fetch with the helper in place: ' + r.stderr)
        check(TOKEN not in calls() and 'github_pat' not in calls(), 'the token is on no command line: ' + calls())
        check('credential.helper' in calls() and 'GIT_TERMINAL_PROMPT=0' in open(os.path.join(stub, 'gitenv')).read(),
              'the helper and the no-prompt setting are given')
        check(TOKEN not in open(os.path.join(repo, '.git', 'config')).read(), 'nothing in .git/config')
        put('calls', '')
        os.remove(tfile)
        r = sh('chaos_gh_git -C "%s" fetch --quiet origin main' % repo, **env)
        check(r.returncode == 0 and 'credential.helper' not in calls(), 'no token: plain git, no helper: ' + calls())
        with open(tfile, 'w') as f:
            f.write(TOKEN + '\n')

        # ---- the words of a refused answer
        def why(code, token=True, repo='o/r'):
            e = dict(env) if token else dict(CHAOS_GITHUB_TOKEN_FILE=os.path.join(tmp, 'none'))
            return sh('chaos_gh_explain %s %s' % (code, repo), **e).stdout

        check(why(200) == '' and why(302) == '', 'a good answer says nothing')
        for code in ('401', '403', '404'):
            check(why(code, token=False).startswith('private-repo:') and 'github-token-set' in why(code, token=False),
                  'no token, %s: private-repo' % code)
        check(why('401').startswith('token-refused:'), 'token, 401: token-refused')
        check(why('403').startswith('no-access:') and why('404').startswith('no-access:'), 'token, 403 / 404: no-access')
        check(why('500').startswith('github-unreachable: HTTP 500') and why('000').startswith('github-unreachable'), '5xx and no answer')
        check(TOKEN not in why('404'), 'a refusal never holds the token')

        # ---- the slug of a remote URL
        for url, slug in (('https://github.com/o/r.git', 'o/r'), ('https://github.com/o/r', 'o/r'), ('git@github.com:o/r.git', 'o/r'),
                          ('ssh://git@github.com/o/r.git', 'o/r'), ('/srv/git/origin.git', ''), ('https://example.org/o/r.git', ''),
                          ('https://github.com/o/r/extra', '')):
            check(sh('chaos_gh_slug "%s"' % url).stdout == slug, 'slug of %s' % url)

        # ---- the API call
        put('cfg.log', '')
        r = sh('chaos_gh_api GET /repos/o/r "%s/body"' % tmp, **env)
        check(r.stdout == '200', 'api: the code: ' + r.stdout)
        c = cfgs()[-1]
        check('url = "https://api.github.com/repos/o/r"' in c and 'Authorization: Bearer ' + TOKEN in c, 'api: the token is a config line')
        check(TOKEN not in calls(), 'api: never on a command line')
        put('cfg.log', '')
        r = sh('CHAOS_GH_NOAUTH=1 chaos_gh_api GET /repos/o/r "%s/body"' % tmp, **env)
        check('Authorization' not in cfgs()[-1], 'api: CHAOS_GH_NOAUTH leaves the token out')
        put('repo.code', '404')
        check(sh('chaos_gh_api GET /repos/o/r "%s/body"' % tmp, **env).stdout == '404', 'api: a refusal is the code')
        check(sh('chaos_gh_git_why o/r', **env).stdout.startswith('no-access:'), 'git failed, token, 404: no-access')
        check(sh('chaos_gh_git_why o/r', CHAOS_GITHUB_TOKEN_FILE=os.path.join(tmp, 'none')).stdout.startswith('private-repo:'),
              'git failed, no token, 404: private-repo')
        check(sh('chaos_gh_git_why ""', **env).stdout == '', 'git failed on a remote that is not GitHub: no probe, no word')
        put('repo.code', '200')
        check(sh('chaos_gh_git_why o/r', **env).stdout.startswith('no-access:') and 'Contents read' in sh('chaos_gh_git_why o/r', **env).stdout,
              'git failed but GitHub knows the repo: the token lacks Contents')
        check(sh('chaos_gh_git_why o/r', CHAOS_GITHUB_TOKEN_FILE=os.path.join(tmp, 'none')).stdout == '',
              'git failed, no token, a public repository: no word')
        drop('repo.code')

        # ---- a release asset
        put('tag.json', '{"assets": [{"id": 7, "name": "a.zip"}, {"id": 8, "name": "b.zip"}]}')
        dest = os.path.join(tmp, 'a.zip')
        put('cfg.log', '')
        r = sh('chaos_gh_release_asset o/r v1 b.zip "%s" 100; echo "rc=$? why=[$CHAOS_GH_WHY]"' % dest, **env)
        check('rc=0 why=[]' in r.stdout and open(dest).read() == 'the asset bytes', 'release asset: ' + r.stdout + r.stderr)
        cs = cfgs()
        check(len(cs) == 3 and 'releases/tags/v1' in cs[0] and 'releases/assets/8' in cs[1] and 'objects.example.org/signed/8' in cs[2],
              'release asset: tag, asset, signed address, in that order')
        check('Authorization: Bearer ' + TOKEN in cs[0] and 'Authorization: Bearer ' + TOKEN in cs[1]
              and 'Accept: application/octet-stream' in cs[1], 'release asset: the API questions carry the token')
        check('Authorization' not in cs[2], 'release asset: the signed address gets no token')
        check('--proto =https' in calls() and '--proto-redir =https' in calls() and '--max-filesize 100' in calls(), 'release asset: https only, size cap')
        check('SIGNED' not in calls() and 'sig=S' not in calls(), 'release asset: the signed address is on no command line')
        r = sh('chaos_gh_release_asset o/r v1 c.zip "%s" 100; echo "rc=$? why=[$CHAOS_GH_WHY]"' % dest, **env)
        check('rc=1' in r.stdout and 'no-asset:' in r.stdout, 'release asset: a missing name: ' + r.stdout)
        put('tag.code', '404')
        r = sh('chaos_gh_release_asset o/r v1 a.zip "%s"; echo "rc=$? why=[$CHAOS_GH_WHY]"' % dest, **env)
        check('rc=1' in r.stdout and 'no-release:' in r.stdout, 'release asset: no such release, with a token: ' + r.stdout)
        r = sh('chaos_gh_release_asset o/r v1 a.zip "%s"; echo "rc=$? why=[$CHAOS_GH_WHY]"' % dest,
               CHAOS_GITHUB_TOKEN_FILE=os.path.join(tmp, 'none'))
        check('rc=1' in r.stdout and 'private-repo:' in r.stdout, 'release asset: 404 without a token: private-repo: ' + r.stdout)
        drop('tag.code')
        put('asset.out', '404 ')
        r = sh('chaos_gh_download o/r 7 "%s"; echo "rc=$? why=[$CHAOS_GH_WHY]"' % dest, **env)
        check('rc=1' in r.stdout and 'no-access:' in r.stdout, 'download: the asset question refused: ' + r.stdout)
        put('asset.out', '200 ')
        r = sh('chaos_gh_download o/r 7 "%s"; echo "rc=$? why=[$CHAOS_GH_WHY]"' % dest, **env)
        check('rc=1' in r.stdout and 'download-failed' in r.stdout, 'download: no address given: ' + r.stdout)
        put('asset.out', '302 http://objects.example.org/plain')
        r = sh('chaos_gh_download o/r 7 "%s"; echo "rc=$? why=[$CHAOS_GH_WHY]"' % dest, **env)
        check('rc=1' in r.stdout, 'download: a redirect to plain http is refused')
        drop('asset.out')
        put('dl.fail', '')
        r = sh('chaos_gh_download o/r 7 "%s"; echo "rc=$? why=[$CHAOS_GH_WHY]"' % dest, **env)
        check('rc=1' in r.stdout and 'download-failed' in r.stdout, 'download: the transfer failed: ' + r.stdout)
        drop('dl.fail')
        r = sh('chaos_gh_download o/r "7;id" "%s"; echo "rc=$?"' % dest, **env)
        check('rc=1' in r.stdout, 'download: an asset id is digits only')

    print('chaos_github_test: %d failures' % failures)
    return 1 if failures else 0


if __name__ == '__main__':
    sys.exit(main())
