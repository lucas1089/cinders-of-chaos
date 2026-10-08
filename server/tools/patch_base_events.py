#!/usr/bin/env python3
"""Make the base server's Player:onGainExperience run the script callbacks (EventCallback onGainExperience).

usage: python3 -I patch_base_events.py DATA_DIR [--dry-run]

The base server's data/events/scripts/player.lua computes experience itself (stages, stamina, the double
experience potion, pets) and never calls EVENT_CALLBACK_ONGAINEXPERIENCE, so every Chaos experience bonus
registered as an EventCallback (Blood Moon in events_schedule.lua, the passive tree, monster tiers, world
buffs from the store) was silently ignored. This inserts the dispatch after the potion bonus, before the
pet share, so the bonuses multiply the staged experience and the pet gets its share of the result.

Idempotent: the inserted block carries a marker comment and is not added twice.
"""
import os, re, sys

MARKER = '-- Chaos: experience bonuses registered as EventCallback (patch_base_events.py)'
BLOCK = (
    '\t' + MARKER + '\n'
    '\tif hasEventCallback(EVENT_CALLBACK_ONGAINEXPERIENCE) then\n'
    '\t\texp = EventCallback(EVENT_CALLBACK_ONGAINEXPERIENCE, self, source, exp, rawExp) or exp\n'
    '\tend\n\n'
)


def patch(text):
    """returns (new text, status) with status 'patched', 'already' or an error message"""
    if MARKER in text:
        return text, 'already'
    start = text.find('function Player:onGainExperience(')
    if start < 0:
        return text, 'Player:onGainExperience not found'
    end = text.find('\nend', start)
    body = text[start:end]
    # before the pet share when there is one, else before the final return
    m = re.search(r'\n([ \t]*)local pet = self:getPet\(\)', body)
    if not m:
        m = re.search(r'\n([ \t]*)return exp\s*$', body)
    if not m:
        return text, 'no insertion point (pet share or final return) in Player:onGainExperience'
    at = start + m.start() + 1
    return text[:at] + BLOCK + text[at:], 'patched'


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    if len(args) != 1:
        print(__doc__)
        return 1
    path = os.path.join(args[0], 'events', 'scripts', 'player.lua')
    text = open(path, encoding='utf-8', errors='surrogateescape').read()
    new, status = patch(text)
    if status == 'patched' and '--dry-run' not in sys.argv:
        open(path, 'w', encoding='utf-8', errors='surrogateescape').write(new)
    print(f'{path}: {status}')
    return 0 if status in ('patched', 'already') else 1


if __name__ == '__main__':
    sys.exit(main())
