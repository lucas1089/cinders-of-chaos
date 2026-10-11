#!/usr/bin/env python3
"""The base server's autosave and logout writes (server/README.md "Autosave in steps").

usage: python3 -I patch_base_save.py DATA_DIR [--dry-run]

1. data/globalevents/scripts/save.lua (the hourly autosave): the three warnings stay as they are (same text, 5, 3 and
   1 minute before). The save itself becomes Game.saveIncremental() (engine src-patch 0026: players in small batches
   over several ticks, then only the houses that changed), and the line that set the game state back to normal goes,
   so a server closed with /closeserver stays closed. Without the engine patch the stock full save runs (saveServer).
2. data/creaturescripts/scripts/login.lua + logout.lua: the logout's UPDATE of the outfit columns (wings_id, shader_id,
   aura_id) runs only when they differ from what the login read from the database.
3. data/scripts/customs/znote/player_history.lua: the logout's skill history row is inserted only when level,
   experience, magic level, skills, balance, town, skull or blessings changed since the login. Only a character that
   already had a history row at the login is compared, so the first logout of a new character always writes its row.
   The statement itself is the stock one, untouched; the row at a death stays as it was.

Every change carries a marker and is made once (a second run changes nothing). A file that is missing is skipped; a
file whose stock lines are not found (and that has no marker) is reported and the exit status is 1.
"""
import os
import re
import sys

MARK = 'Chaos (patch_base_save.py)'

SAVE_RE = re.compile(r'^([ \t]*)saveServer\(\)[ \t]*\r?\n[ \t]*Game\.setGameState\(GAME_STATE_NORMAL\)[ \t]*\r?\n', re.M)
SAVE_NEW = (
    '{i}-- %s: the autosave in small steps (engine src-patch 0026), no long freeze; the game\n'
    '{i}-- state is kept (a closed server stays closed). Without the engine patch: the stock full save.\n'
    '{i}if Game.saveIncremental then\n'
    '{i}{t}Game.saveIncremental()\n'
    '{i}else\n'
    '{i}{t}saveServer()\n'
    '{i}end\n') % MARK

LOGIN_RE = re.compile(r'^([ \t]*)local auraId = result\.getDataInt\(resultId, "aura_id"\)[^\n]*\n', re.M)
LOGIN_NEW = (
    '{i}-- %s: the outfit columns as the database holds them (logout.lua writes them only on a change)\n'
    '{i}ChaosOutfitColumns = ChaosOutfitColumns or {{}}\n'
    '{i}ChaosOutfitColumns[playerId] = tostring(wingsId) .. ":" .. tostring(shaderId) .. ":" .. tostring(auraId)\n') % MARK

LOGOUT_RE = re.compile(r'^([ \t]*)local query = "UPDATE players SET wings_id = "[^\n]*\n[ \t]*db\.query\(query\)[ \t]*\r?\n', re.M)
LOGOUT_NEW = (
    '{i}-- %s: written only when the columns differ from what the login read\n'
    '{i}local chaosOutfitKey = tostring(wingsClientId) .. ":" .. tostring(shaderClientId) .. ":" .. tostring(auraClientId)\n'
    '{i}if not ChaosOutfitColumns or ChaosOutfitColumns[playerId] ~= chaosOutfitKey then\n'
    '{i}{t}{old}'
    '{i}{t}db.query(query)\n'
    '{i}end\n'
    '{i}if ChaosOutfitColumns then\n'
    '{i}{t}ChaosOutfitColumns[playerId] = nil\n'
    '{i}end\n') % MARK

HISTORY_HELPER_RE = re.compile(r'^local player_history_skill = CreatureEvent\("player_history_skill"\)[ \t]*\r?\n', re.M)
HISTORY_HELPER = (
    '-- %s: what a history row records about the character (not the times or the address); the\n'
    '-- logout writes a row only when this differs from the login. The base magic level: the row\'s effective one\n'
    '-- moves with equipment and effects that the login applies after this event.\n'
    'local chaosHistoryAtLogin = {}\n'
    'local function chaosHistoryKey(player)\n'
    '\tlocal blessdec, i = 0, 0\n'
    '\twhile player:hasBlessing(i + 1) do\n'
    '\t\tblessdec = blessdec + 2 ^ i\n'
    '\t\ti = i + 1\n'
    '\tend\n'
    '\tlocal town = player:getTown()\n'
    '\treturn table.concat({town and town:getId() or 0, player:getSkull(), blessdec, player:getBankBalance(),\n'
    '\t\tplayer:getLevel(), player:getExperience(), player:getBaseMagicLevel(), player:getSkillLevel(SKILL_FIST),\n'
    '\t\tplayer:getSkillLevel(SKILL_CLUB), player:getSkillLevel(SKILL_SWORD), player:getSkillLevel(SKILL_AXE),\n'
    '\t\tplayer:getSkillLevel(SKILL_DISTANCE), player:getSkillLevel(SKILL_SHIELD), player:getSkillLevel(SKILL_FISHING)}, ":")\n'
    'end\n'
    '\n') % MARK
HISTORY_LOGOUT_RE = re.compile(r'^([ \t]*)historyLogoutEvent\(player\)[ \t]*\r?\n(?=[ \t]*return true[ \t]*\r?\nend[ \t]*\r?\nplayer_history_skill:register\(\))', re.M)
HISTORY_LOGOUT_NEW = (
    '{i}-- %s: no row when nothing it records changed since the login\n'
    '{i}local chaosGuid = player:getGuid()\n'
    '{i}local chaosSame = chaosHistoryAtLogin[chaosGuid] == chaosHistoryKey(player)\n'
    '{i}chaosHistoryAtLogin[chaosGuid] = nil\n'
    '{i}if not chaosSame then\n'
    '{i}{t}historyLogoutEvent(player)\n'
    '{i}end\n') % MARK
# the end of the stock login event: `resultId` is false when the character had no history row yet (the stock INSERT
# ... SELECT then tries to add one; it needs the website's tables). Only a character that had a row gets a login
# record, so the first logout of a new character always writes its row.
HISTORY_LOGIN_RE = re.compile(r'^([ \t]*)return true[ \t]*\r?\nend[ \t]*\r?\n(?=player_history_skill_login:register\(\))', re.M)
HISTORY_LOGIN_NEW = (
    '{i}-- %s: the login record, only when the character already had a history row\n'
    '{i}if resultId then\n'
    '{i}{t}chaosHistoryAtLogin[player:getGuid()] = chaosHistoryKey(player)\n'
    '{i}end\n'
    '{i}return true\n'
    'end\n') % MARK


def step(indent):
    """one more level in the file's own style: a tab after tabs, else four spaces"""
    return '\t' if indent.startswith('\t') else '    '


def crlf(text, new):
    return new.replace('\n', '\r\n') if '\r\n' in text else new


def sub_once(text, regex, build):
    m = regex.search(text)
    if not m:
        return None
    return text[:m.start()] + crlf(text, build(m)) + text[m.end():]


def patch_save(text):
    if MARK in text:
        return text, 'already'
    new = sub_once(text, SAVE_RE, lambda m: SAVE_NEW.format(i=m.group(1), t=step(m.group(1))))
    if new is None:
        return text, 'ERROR: stock "saveServer() / Game.setGameState(GAME_STATE_NORMAL)" not found'
    return new, 'patched'


def patch_login(text):
    if MARK in text:
        return text, 'already'
    new = sub_once(text, LOGIN_RE, lambda m: m.group(0) + LOGIN_NEW.format(i=m.group(1)))
    if new is None:
        return text, 'ERROR: stock line "local auraId = result.getDataInt(resultId, "aura_id")" not found'
    return new, 'patched'


def patch_logout(text):
    if MARK in text:
        return text, 'already'

    def build(m):
        first = m.group(0).split('\n', 1)[0].strip()
        return LOGOUT_NEW.format(i=m.group(1), t=step(m.group(1)), old=first + '\n')
    new = sub_once(text, LOGOUT_RE, build)
    if new is None:
        return text, 'ERROR: stock outfit UPDATE + db.query(query) not found'
    return new, 'patched'


def patch_history(text):
    if MARK in text:
        return text, 'already'
    new = sub_once(text, HISTORY_HELPER_RE, lambda m: HISTORY_HELPER + m.group(0))
    if new is not None:
        new = sub_once(new, HISTORY_LOGOUT_RE, lambda m: HISTORY_LOGOUT_NEW.format(i=m.group(1), t=step(m.group(1))))
    if new is not None:
        new = sub_once(new, HISTORY_LOGIN_RE, lambda m: HISTORY_LOGIN_NEW.format(i=m.group(1), t=step(m.group(1))))
    if new is None:
        return text, 'ERROR: stock logout / login events of the skill history not found'
    return new, 'patched'


FILES = [
    ('globalevents/scripts/save.lua', patch_save),
    ('creaturescripts/scripts/login.lua', patch_login),
    ('creaturescripts/scripts/logout.lua', patch_logout),
    ('scripts/customs/znote/player_history.lua', patch_history),
]


def main(argv):
    args = [a for a in argv if not a.startswith('--')]
    dry = '--dry-run' in argv
    if len(args) != 1 or not os.path.isdir(args[0]):
        print(__doc__.strip().splitlines()[2])
        return 2
    data = args[0]
    status = 0
    for rel, fn in FILES:
        path = os.path.join(data, *rel.split('/'))
        if not os.path.isfile(path):
            print('data/%s: not found, skipped' % rel)
            continue
        with open(path, encoding='utf-8', errors='surrogateescape', newline='') as f:
            text = f.read()
        new, st = fn(text)
        if st.startswith('ERROR'):
            status = 1
        if st == 'patched' and not dry:
            with open(path, 'w', encoding='utf-8', errors='surrogateescape', newline='') as f:
                f.write(new)
        print('data/%s: %s%s' % (rel, st, ' (dry run, not written)' if dry and st == 'patched' else ''))
    return status


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
