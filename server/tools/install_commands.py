#!/usr/bin/env python3
"""Take the players' spoken commands of the base server out: every one of them is in the client's menu now (the Info &
Services window, client game_chaosinfo, server data/scripts/chaos/commands_ui.lua, which loads these scripts itself).

usage: python3 -I install_commands.py DATA_DIR [--dry-run]

1. data/talkactions/talkactions.xml: every <talkaction> whose words start with "!" (the players' commands: !commands,
   !online, !buyhouse, !ancestralstore ..., and the stock !autoloot the autoloot step already handles) is commented out
   with the marker "chaos-menu". Staff commands ("/..." words) stay. The scripts stay where they are: the window reads
   the commented line to find them.
2. data/scripts/** (not scripts/chaos): in every TalkAction(...) the "!" words are taken out; an object left without
   words keeps its code but its :register() line is commented out ("-- chaos-menu"). A mixed one such as
   TalkAction("/pos", "!pos") keeps its staff word.
3. Player-facing texts that tell players to type a command: the login lines of creaturescripts/scripts/login.lua
   ("To see the commands use: !commands ...") are commented out; the double experience potion's "type: !exp" and the
   task NPCs' "Say {!ancestral}" point to the menu instead.

Idempotent: a second run changes nothing. --dry-run prints what would change and writes nothing.
"""
import os
import re
import sys

MARK = 'chaos-menu'
XML_LINE = re.compile(r'^(?P<indent>[ \t]*)(?P<tag><talkaction\s[^>]*words="(?P<words>[^"]*)"[^>]*/>)[ \t]*(?=\r?$)', re.M)
TALK_CTOR = re.compile(r'(?P<lhs>(?:local\s+)?(?P<var>[A-Za-z_][\w]*)\s*=\s*)TalkAction\((?P<args>[^()]*)\)')
STRING = re.compile(r'"([^"]*)"|\'([^\']*)\'')

# exact text swaps in base files: (path relative to DATA_DIR, old, new); a missing file or text is skipped
TEXTS = [
    ('scripts/customs/actions/double_exp_potion.lua', 'type: !exp to show the remaining time.',
     'Character > Character Info shows the remaining time.'),
]
NPC_DIR = 'npc/scripts'
NPC_OLD = 'Say {!ancestral} to see information about your current task.'
NPC_NEW = 'Your current task: Character > Character Info, in the menu.'


def player_words(words):
    return [w for w in words.split(';') if w.strip().startswith('!')]


def fix_xml(text):
    """talkactions.xml text -> (new text, list of commented words)."""
    done = []

    def repl(m):
        words = m.group('words')
        if not player_words(words):
            return m.group(0)
        done.append(words)
        return '%s<!-- %s (Info & Services window): %s -->' % (m.group('indent'), MARK, m.group('tag'))
    return XML_LINE.sub(repl, text), done


def fix_revscript(text):
    """A revscript's text -> (new text, list of removed words)."""
    removed = []
    dead = []

    def repl(m):
        args = m.group('args')
        words = [a or b for a, b in STRING.findall(args)]
        if not words or len(STRING.sub('', args).replace(',', '').strip()) > 0:
            return m.group(0)  # not a plain list of strings: leave it
        keep = [w for w in words if not w.startswith('!')]
        gone = [w for w in words if w.startswith('!')]
        if not gone:
            return m.group(0)
        removed.extend(gone)
        if not keep:
            dead.append(m.group('var'))
            return m.group(0)  # kept as is (the window loads its onSay); only the registration goes
        return '%sTalkAction(%s)' % (m.group('lhs'), ', '.join('"%s"' % w for w in keep))
    out = TALK_CTOR.sub(repl, text)
    for var in dead:
        out = re.sub(r'(?m)^([ \t]*)(%s:register\(\))[ \t]*(\r?)$' % re.escape(var),
                     r'\1-- \2 -- %s (Info & Services window)\3' % MARK, out)
    return out, removed


def fix_login(text):
    out, n = [], 0
    for line in text.split('\n'):
        if '!commands' in line and 'sendTextMessage' in line and not line.lstrip().startswith('--'):
            indent = line[:len(line) - len(line.lstrip())]
            line = '%s-- %s -- %s (every command is in the menu)' % (indent, line.lstrip(), MARK)
            n += 1
        out.append(line)
    return '\n'.join(out), n


def main(argv):
    args = [a for a in argv if not a.startswith('--')]
    dry = '--dry-run' in argv
    if len(args) != 1:
        print(__doc__)
        return 2
    data = args[0]
    if not os.path.isdir(data):
        print('not a folder: ' + data)
        return 1
    changes = []

    def write(path, old, new, what):
        if new == old:
            return
        changes.append('%s: %s' % (os.path.relpath(path, data), what))
        if not dry:
            with open(path, 'w', encoding='utf-8', newline='') as f:
                f.write(new)

    def read(path):
        with open(path, encoding='utf-8', errors='surrogateescape', newline='') as f:
            return f.read()

    xml = os.path.join(data, 'talkactions', 'talkactions.xml')
    if os.path.isfile(xml):
        old = read(xml)
        new, done = fix_xml(old)
        write(xml, old, new, 'commented out ' + ', '.join(done))

    scripts = os.path.join(data, 'scripts')
    for root, dirs, files in os.walk(scripts):
        rel = os.path.relpath(root, scripts).replace(os.sep, '/')
        if rel == 'chaos' or rel.startswith('chaos/'):
            dirs[:] = []
            continue
        dirs.sort()
        for name in sorted(files):
            if not name.endswith('.lua'):
                continue
            path = os.path.join(root, name)
            old = read(path)
            if 'TalkAction(' not in old:
                continue
            new, removed = fix_revscript(old)
            write(path, old, new, 'player words out: ' + ', '.join(removed))

    login = os.path.join(data, 'creaturescripts', 'scripts', 'login.lua')
    if os.path.isfile(login):
        old = read(login)
        new, n = fix_login(old)
        write(login, old, new, '%d command hint line(s) commented out' % n)

    for rel, a, b in TEXTS:
        path = os.path.join(data, rel)
        if os.path.isfile(path):
            old = read(path)
            write(path, old, old.replace(a, b), 'hint points to the menu')
    npc = os.path.join(data, NPC_DIR)
    if os.path.isdir(npc):
        for name in sorted(os.listdir(npc)):
            path = os.path.join(npc, name)
            if name.endswith('.lua') and os.path.isfile(path):
                old = read(path)
                if NPC_OLD in old:
                    write(path, old, old.replace(NPC_OLD, NPC_NEW), 'hint points to the menu')

    for c in changes:
        print(('would change ' if dry else 'changed ') + c)
    if not changes:
        print('nothing to do (the spoken commands are already out)')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
