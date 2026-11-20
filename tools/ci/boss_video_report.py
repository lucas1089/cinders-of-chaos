#!/usr/bin/env python3
"""The text side of the boss fight video (O689, tools/ci/boss_video.sh, .github/workflows/boss-video.yml).

  report   the fight report: what the testers' activity log says about the pinnacle fight (time to kill or wipe, the boss's health taken, who was
           carried out when), what the spectator's client log saw (the fight states of /instances, the boss health samples), all with no account,
           password, key or database login in it
  redact   a log with the same secrets cut out (the client log)
  level    the character level that opens a pinnacle boss (the table of tools/ci/unity_live_check.sh pinnacle_level, held to pinnacle_config.lua by the test)

  python3 -I tools/ci/boss_video_report.py report --boss malgrath --level 1900 --party "Tester Aka,..." --activity FILE --client-log FILE \
      --secrets-file FILE [--state-json FILE] [--seconds N] --out FILE
  python3 -I tools/ci/boss_video_report.py redact --in FILE --secrets-file FILE [--state-json FILE] --out FILE

The secrets file has one value a line (made by boss_video.sh, mode 600, never an argument). --state-json is the state.json of testers.py: its accounts and
passwords are cut too. Anything shaped like a tester account (tstbot + 10 hex digits), a guard key (64 hex digits) or a made-up live account of
tools/ci/unity_live_check.sh (lcp / lcq / lcn / lct / lcu / lcs / lcw + number + 6 hex digits) is cut whether it is listed or not. Standard library only.
"""
import json
import os
import re
import sys

BOSS_LEVELS = {'malgrath': 1900, 'vhoss': 2100, 'talath': 2300, 'varkhul': 2500}
SHAPES = (re.compile(r'tstbot[0-9a-f]{10}'), re.compile(r'\b[0-9a-fA-F]{64}\b'), re.compile(r'\blc[pqnstuw]\d+[0-9a-f]{6}\b'))
REMOVED = '<removed>'
FIGHT_KINDS = ('CHECK', 'BUG', 'DEATH')
MAX_LINES = 60
MAX_LINE = 900


def secrets_of(path, state_json=None):
    """the values to cut: the lines of the secrets file (6 characters or more) and the accounts and passwords of a testers.py state.json"""
    out = set()
    if path and os.path.isfile(path):
        with open(path, encoding='utf-8', errors='replace') as f:
            out.update(line.strip() for line in f if len(line.strip()) >= 6)
    if state_json and os.path.isfile(state_json):
        try:
            with open(state_json, encoding='utf-8') as f:
                for b in json.load(f).get('bots', []):
                    for k in ('account', 'password'):
                        if len(str(b.get(k) or '')) >= 6:
                            out.add(str(b[k]))
        except (OSError, ValueError):
            pass
    return sorted(out, key=len, reverse=True)


def redact(text, secrets):
    for s in secrets:
        text = text.replace(s, REMOVED)
    for rx in SHAPES:
        text = rx.sub(REMOVED, text)
    return text


def fight_lines(activity):
    """[line] of the activity log that belong to the fight report: the check results (the verdict of pinnacle_party), BUG lines and deaths. The
    activity log's line is `HH:MM:SS Tester Xxx (L1900 Class) KIND text`"""
    out = []
    for raw in activity.splitlines():
        m = re.match(r'^\d\d:\d\d:\d\d .*? \(L\d+ [^)]*\) (\S+) ', raw)
        if m and m.group(1) in FIGHT_KINDS:
            out.append(raw[:MAX_LINE])
    return out


def verdict_of(lines):
    """the facts of the pinnacle_party verdict among `lines`: {'result': 'killed' | 'not killed' | 'unknown', 'seconds', 'boss_left', 'falls', 'out': [(name, s)], 'status', 'text'}.
    The texts are tester_checks.pinnacle_walk_verdict and pinnacle_party_verdict"""
    best = None
    for line in lines:
        m = re.search(r' CHECK (PASS|FAIL|SKIP) pinnacle_party: (.*)$', line)
        if m and not m.group(2).startswith('played as a member'):
            best = (m.group(1), m.group(2))
    if best is None:
        return {'result': 'unknown', 'seconds': None, 'boss_left': None, 'falls': None, 'out': [], 'status': None, 'text': ''}
    status, text = best
    v = {'result': 'unknown', 'seconds': None, 'boss_left': None, 'falls': None, 'out': [], 'status': status, 'text': text}
    k = re.search(r' down in (\d+) s, (\d+) fall', text)
    h = re.search(r' hurt to (\d+)% in (\d+|\?) s, not down \((\d+) fall', text)
    if k:
        v.update(result='killed', seconds=int(k.group(1)), falls=int(k.group(2)), boss_left=0)
    elif h:
        v.update(result='not killed', boss_left=int(h.group(1)), falls=int(h.group(3)), seconds=int(h.group(2)) if h.group(2).isdigit() else None)
    elif status != 'PASS':
        v['result'] = 'not killed'
    c = re.search(r'carried out: (.*?)(?:; party:|$)', text)
    if c:
        for name, secs in re.findall(r'(Tester [A-Z][a-z]{2}) at (\d+) s', c.group(1)):
            v['out'].append((name, int(secs)))
    return v


def client_facts(client_log):
    """what the spectator's client wrote: the fight states, the boss health samples (percent, seconds in the fight) and its last word"""
    facts = {'states': [], 'boss': [], 'done': None, 'ready': False}
    for line in client_log.splitlines():
        if 'bosstour: ready' in line:
            facts['ready'] = True
        m = re.search(r'bosstour: fight state (.*)$', line)
        if m:
            facts['states'].append(m.group(1).strip())
        m = re.search(r'bosstour: boss (\d+)% at (\d+) s', line)
        if m:
            facts['boss'].append((int(m.group(1)), int(m.group(2))))
        m = re.search(r'bosstour: done (ok|fail) (.*)$', line)
        if m:
            facts['done'] = (m.group(1), m.group(2).strip())
    return facts


def build_report(boss, level, party, activity, client_log, seconds=None, secrets=()):
    lines = fight_lines(activity)
    v = verdict_of(lines)
    c = client_facts(client_log)
    out = ['Fight report (O689): %s, level %s, a party of %d testers' % (boss, level, len(party)), '']
    out.append('party: %s' % (', '.join(party) or 'unknown'))
    if v['result'] == 'killed':
        out.append('result: the boss was killed in %s s after it came (%s fall(s))' % (v['seconds'], v['falls']))
    elif v['result'] == 'not killed':
        taken = ''
        if v['boss_left'] is not None:
            taken = ', %d%% of its health taken (%d%% left)' % (100 - v['boss_left'], v['boss_left'])
        when = (' after %s s' % v['seconds']) if v['seconds'] is not None else ''
        out.append('result: the boss was NOT killed%s%s (%s fall(s))' % (when, taken, v['falls'] if v['falls'] is not None else '?'))
    else:
        out.append('result: unknown (the testers wrote no verdict of the check pinnacle_party)')
    if v['out']:
        out.append('carried out (a fall, healed and sent back): %s' % ', '.join('%s at %d s' % (n, s) for n, s in v['out']))
    elif v['result'] != 'unknown':
        out.append('carried out: nobody')
    if v['text']:
        out.append('the check says (%s): %s' % (v['status'], v['text'][:700]))
    out.append('')
    if c['ready']:
        out.append('the spectator saw the fight open; fight states of /instances pinnacle: %s' % (', '.join(c['states']) or 'none logged'))
        if c['boss']:
            out.append('boss health seen from the camera (percent at seconds): %s' % ', '.join('%d%% at %d s' % b for b in c['boss'][:40]))
        else:
            out.append('boss health seen from the camera: no sample (the boss was out of sight or the log has none)')
        if c['done']:
            out.append('the tour ended %s: %s' % c['done'])
    else:
        out.append('the spectator never saw the fight open (no ready line in the client log)')
    if seconds is not None:
        out.append('recorded: %s s' % seconds)
    out += ['', 'lines of the testers\' activity log (checks, bugs, deaths):']
    out += ['  ' + l for l in lines[:MAX_LINES]] or ['  none']
    if len(lines) > MAX_LINES:
        out.append('  [%d more lines left out]' % (len(lines) - MAX_LINES))
    return redact('\n'.join(out) + '\n', list(secrets))


def _arg(argv, name, default=None):
    if name in argv:
        i = argv.index(name)
        if i + 1 < len(argv):
            return argv[i + 1]
    return default


def _read(path):
    try:
        with open(path, encoding='utf-8', errors='replace') as f:
            return f.read()
    except OSError:
        return ''


def main(argv):
    if len(argv) < 2 or argv[1] not in ('report', 'redact', 'level'):
        print(__doc__)
        return 2
    cmd = argv[1]
    if cmd == 'level':
        boss = argv[2] if len(argv) > 2 else ''
        if boss not in BOSS_LEVELS:
            print('boss: %s' % ', '.join(sorted(BOSS_LEVELS)), file=sys.stderr)
            return 2
        print(BOSS_LEVELS[boss])
        return 0
    secrets = secrets_of(_arg(argv, '--secrets-file'), _arg(argv, '--state-json'))
    out = _arg(argv, '--out')
    if not out:
        print('--out FILE', file=sys.stderr)
        return 2
    if cmd == 'redact':
        text = redact(_read(_arg(argv, '--in', '')), secrets)
    else:
        seconds = _arg(argv, '--seconds')
        text = build_report(_arg(argv, '--boss', '?'), _arg(argv, '--level', '?'), [n for n in (_arg(argv, '--party', '') or '').split(',') if n],
                            _read(_arg(argv, '--activity', '')), _read(_arg(argv, '--client-log', '')), seconds, secrets)
    fd = os.open(out, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o644)
    with os.fdopen(fd, 'w', encoding='utf-8') as f:
        f.write(text)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
