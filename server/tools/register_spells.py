#!/usr/bin/env python3
"""Install the chaos spells into a TFS data folder (idempotent).

usage: python3 -I register_spells.py [DATA_DIR] [--dry-run]

DATA_DIR defaults to ../data next to this tool (server/data) and must contain spells/spells.xml.
Steps:
  1. copies   <DATA_DIR>/spells/chaos/**/*.lua  ->  <DATA_DIR>/spells/scripts/chaos/**/*.lua
     (the <instant script="chaos/..."> paths in the XML are relative to data/spells/scripts, and the
      scripts dofile('data/spells/scripts/chaos/_common.lua'), so this target path is mandatory)
  2. inserts  <DATA_DIR>/spells/chaos/spells_chaos.xml  into <DATA_DIR>/spells/spells.xml before </spells>,
     wrapped in marker comments; re-running replaces that block, it never duplicates.
Refuses (exit 1) if a chaos spellid, words or name is already used by a spell outside the marker block.
A base spell whose script is one of the ammunition conjure scripts (chaos_archery_config.lua conjureScripts: Arrow Call
176, Fletch Crystal Arrows 192, Fletch Wraith Bolts 193 ...) does not hold its spellid: the "archery" step
(patch_base_archery.py, right after this one) comments those spells out of spells.xml, so the ids are free for the
Chaos block. The Necromancer's three summon spells use 176, 192 and 193 (every other id below 256 is taken).
"""
import os, re, shutil, sys

BEGIN = '\t<!-- BEGIN chaos spells (tools/register_spells.py) -->\n'
END = '\t<!-- END chaos spells -->\n'
INSTANT = re.compile(r'<instant\b[^>]*?(?:/>|>.*?</instant>)', re.S)


def attrs(block):
    head = re.match(r'<instant\b([^>]*)', block, re.S).group(1)
    return dict(re.findall(r'(\w+)="([^"]*)"', head))


def ammo_conjure_scripts(data):
    """script file names of the conjure spells patch_base_archery.py switches off (chaos_archery_config.lua), read from
    the installed lib folder, else from this repository"""
    for p in (os.path.join(data, 'lib', 'chaos_archery_config.lua'),
              os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'data', 'lib', 'chaos_archery_config.lua')):
        if os.path.isfile(p):
            m = re.search(r'\bconjureScripts\s*=\s*\{(.*?)\}', open(p, encoding='utf-8').read(), re.S)
            if m:
                return set(re.findall(r'"([^"]+)"', m.group(1)))
    return set()


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    dry = '--dry-run' in sys.argv
    here = os.path.dirname(os.path.abspath(__file__))
    data = os.path.abspath(args[0] if args else os.path.join(here, '..', 'data'))
    src = os.path.join(data, 'spells', 'chaos')
    frag_path = os.path.join(src, 'spells_chaos.xml')
    xml_path = os.path.join(data, 'spells', 'spells.xml')
    dst = os.path.join(data, 'spells', 'scripts', 'chaos')
    for p in (frag_path, xml_path):
        if not os.path.isfile(p):
            sys.exit(f'missing file: {p}')

    frag = open(frag_path, encoding='utf-8').read()
    blocks = INSTANT.findall(re.sub(r'<!--.*?-->', '', frag, flags=re.S))
    if not blocks:
        sys.exit('no <instant> found in fragment')

    text = open(xml_path, encoding='utf-8', errors='ignore').read()
    if BEGIN in text and END in text:
        a = text.index(BEGIN)
        b = text.index(END) + len(END)
        text = text[:a] + text[b:]
    others = [attrs(b) for b in INSTANT.findall(re.sub(r'<!--.*?-->', '', text, flags=re.S))]
    ammo = ammo_conjure_scripts(data)
    used_id = {o['spellid'] for o in others
               if 'spellid' in o and os.path.basename(o.get('script', '')) not in ammo}
    used_words = {o['words'].lower() for o in others if 'words' in o}
    used_name = {o['name'].lower() for o in others if 'name' in o}

    errors, seen = [], set()
    for b in blocks:
        a = attrs(b)
        for key, pool in (('spellid', used_id), ('words', used_words), ('name', used_name)):
            v = a[key].lower() if key != 'spellid' else a[key]
            if v in pool or (key, v) in seen:
                errors.append(f'{a["name"]}: {key}="{a[key]}" already used')
            seen.add((key, v))
        script = os.path.join(src, a['script'].replace('chaos/', '', 1))
        if not os.path.isfile(script):
            errors.append(f'{a["name"]}: script source missing: {script}')
    if errors:
        sys.exit('refusing to register:\n  ' + '\n  '.join(errors))

    if '</spells>' not in text:
        sys.exit('no </spells> in spells.xml')
    new = text.replace('</spells>', BEGIN + frag.rstrip('\n') + '\n' + END + '</spells>', 1)

    n_files = 0
    for root, _, files in os.walk(src):
        for f in files:
            if f.endswith('.lua'):
                rel = os.path.relpath(os.path.join(root, f), src)
                n_files += 1
                if not dry:
                    os.makedirs(os.path.dirname(os.path.join(dst, rel)), exist_ok=True)
                    shutil.copyfile(os.path.join(root, f), os.path.join(dst, rel))
    if not dry:
        open(xml_path, 'w', encoding='utf-8').write(new)
    print(f'{"[dry-run] " if dry else ""}{len(blocks)} spells registered in {xml_path}; '
          f'{n_files} scripts copied to {dst}')


if __name__ == '__main__':
    main()
