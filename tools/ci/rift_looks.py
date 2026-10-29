"""Rift looks the client pair can draw (O309). Used by check_content.py.

rift_config.lua `looks` sets outfits at runtime (family looks, rank variants, big guardians), so the monster files never
name them and the pair pruning of pair 51 retired some as "unused": a rift monster in a blank outfit is invisible. This
reads the looks block and returns the problems: every look a run can wear, after `undrawn` (the replacement table), must
be a real, non-blank outfit of the pair. bigGuardians count only with bigGuardiansOn = true.
"""
import re


def _block(text, key, open_ch='{'):
    """the text of `key = { ... }` (balanced braces, first match), or ''"""
    m = re.search(r'\b' + key + r'\s*=\s*\{', text)
    if not m:
        return ''
    depth, i = 1, m.end()
    while i < len(text) and depth:
        c = text[i]
        depth += (c == '{') - (c == '}')
        i += 1
    return text[m.end():i - 1]


def looks(text):
    """({where: look} of the configured looks, {from: to} undrawn, big guardians on)"""
    block = _block(text, 'looks')
    undrawn = {int(a): int(b) for a, b in re.findall(r'\[(\d+)\]\s*=\s*(\d+)', _block(block, 'undrawn'))}
    out = {}
    for fam, body in re.findall(r'\["([^"]+)"\]\s*=\s*\{((?:minion|brute|elite|guardian)[^}]*)\}', _block(block, 'families')):
        for rank, v in re.findall(r'(minion|brute|elite|guardian)\s*=\s*(\d+)', body):
            out[f'{fam} {rank}'] = int(v)
    for look, name in re.findall(r'look\s*=\s*(\d+),\s*name\s*=\s*"([^"]+)"', _block(block, 'variants')):
        out[f'variant {name}'] = int(look)
    on = re.search(r'bigGuardiansOn\s*=\s*true', block) is not None
    if on:
        for a, b in re.findall(r'\[(\d+)\]\s*=\s*(\d+)', _block(block, 'bigGuardians')):
            out[f'big guardian {a}'] = int(b)
    return out, undrawn, on


def problems(text, blank, max_outfit):
    """messages for the looks a rift would wear that the pair does not draw"""
    out, undrawn, _on = looks(text)
    msgs = []
    if not out:
        return ['no rift looks found in rift_config.lua (looks block changed shape?)']
    for where, v in sorted(out.items()):
        w = undrawn.get(v, v)
        tag = f'{where}: look {v}' + (f' (worn as {w})' if w != v else '')
        if w > max_outfit:
            msgs.append(f'{tag} is above the {max_outfit} outfits of the pair')
        elif w in blank:
            msgs.append(f'{tag} is a blank outfit of the pair (the monster would be invisible)')
    for a, b in sorted(undrawn.items()):
        if b in blank or b > max_outfit or b in undrawn:
            msgs.append(f'undrawn {a} -> {b}: the replacement is not a drawn outfit')
    return msgs
