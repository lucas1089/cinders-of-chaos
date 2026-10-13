"""The themed equipment sets of gen_theme_art.py: names, looks (materials, motif, shapes) and which kinds each set has.

Ten sets, our own names and designs. The first six have one piece of every kind; the last four come as three class
kits each (a heavy melee kit, a caster kit, a ranged kit) plus a shared amulet, ring and backpack.
Keys are stable: they name the art, the client things and the server items (server/data/items/theme_items.csv).
"""

FULL = ['sword', 'axe', 'club', 'bow', 'crossbow', 'wand', 'rod', 'shield', 'helmet', 'armor', 'legs', 'boots', 'amulet',
        'ring', 'backpack', 'spellbook', 'arrow', 'bolt']

NAMES = {   # the item name per kind ("%s" = the set's adjective)
    'sword': '%s blade', 'axe': '%s axe', 'club': '%s mace', 'bow': '%s bow', 'crossbow': '%s crossbow',
    'wand': '%s wand', 'rod': '%s rod', 'shield': '%s shield', 'helmet': '%s helmet', 'armor': '%s armor',
    'legs': '%s legs', 'boots': '%s boots', 'amulet': '%s amulet', 'ring': '%s ring', 'backpack': '%s backpack',
    'spellbook': '%s spellbook', 'arrow': '%s arrow', 'bolt': '%s bolt',
}

# kit pieces of the last four sets: (kit, kind, style, name pattern)
KITS = [
    ('melee', 'helmet', None, '%s warhelm'), ('melee', 'armor', None, '%s plate'), ('melee', 'legs', None, '%s greaves'),
    ('melee', 'boots', None, '%s sabatons'), ('melee', 'sword', None, '%s blade'), ('melee', 'shield', None, '%s bulwark'),
    ('caster', 'helmet', 'hat', '%s hat'), ('caster', 'armor', 'robe', '%s robe'), ('caster', 'legs', 'skirt', '%s kilt'),
    ('caster', 'boots', None, '%s slippers'), ('caster', 'rod', None, '%s staff'), ('caster', 'spellbook', None, '%s grimoire'),
    ('ranged', 'helmet', 'hood', '%s hood'), ('ranged', 'armor', 'jerkin', '%s jerkin'), ('ranged', 'legs', 'leather', '%s leggings'),
    ('ranged', 'boots', None, '%s striders'), ('ranged', 'bow', None, '%s longbow'), ('ranged', 'crossbow', None, '%s arbalest'),
    ('shared', 'amulet', None, '%s amulet'), ('shared', 'ring', None, '%s ring'), ('shared', 'backpack', None, '%s backpack'),
]

SETS = [
    dict(key='cryptbone', name='Cryptbone', adj='cryptbone',
         desc='Bone and grave iron, lit by a sick green soul fire.',
         th=dict(metal='bone', trim='ironblk', grip='leather', haft='ironblk', cloth='grave', gem='necro', glowcol='#6cf29a',
                 motif='skull', blade='serrated', axe='bone', club='skull', shield='round_spiked', helm='skull',
                 armor='ribs', legs='plate', shieldface='grave', bowmat='bone', bowtip='skull', wandmat='bone',
                 wandhead='skull', rodmat='ironblk', rodhead='skull', bookmat='grave', packmat='grave', packflap='bone',
                 headmat='bone', fletch='grave', pommel='skull', edgeglow=None, spikes=True, bootmat='ironblk',
                 beltmat='grave', tasset='bone')),
    dict(key='voidmourn', name='Voidmourn', adj='voidmourn',
         desc='Black steel from the far side of a rift; blue light leaks from every seam.',
         th=dict(metal='voidsteel', trim='voidsteel', grip='voidcloth', haft='voidcloth', cloth='voidcloth', gem='voidglow',
                 glowcol='#4a9cff', motif='eye', blade='wavy', axe='jagged', club='orb', shield='kite', helm='void',
                 armor='plate', legs='plate', shieldface='voidcloth', bowmat='voidsteel', bowtip=None, wandmat='voidsteel',
                 wandhead='star', rodmat='voidcloth', rodhead='claw', bookmat='voidcloth', packmat='voidcloth',
                 packflap='voidsteel', headmat='voidglow', fletch='voidcloth', edgeglow='voidglow', bootmat='voidsteel',
                 beltmat='voidcloth', bowtrim='voidglow')),
    dict(key='wildroot', name='Wildroot', adj='wildroot',
         desc='Living wood, bark and leaf of the old groves, bound in bronze.',
         th=dict(metal='bronze', trim='bronze', grip='leather', haft='wood', cloth='leaf', gem='amber', glowcol=None,
                 motif='tree', blade='leaf', axe='bearded', club='gnarled', shield='round_wood', helm='hood',
                 armor='leaf', legs='leather', jerkinmat='leather', shieldface='wood', bowmat='wood', bowtip='leaf', wandmat='wood',
                 wandhead='leaf', rodmat='wood', rodhead='branch', bookmat='leaf', packmat='leather', packflap='leaf',
                 headmat='bronze', fletch='leaf', scale='leaf', guardstyle='thorn', bootmat='leather', hoodleaf='leaf',
                 beltmat='leather')),
    dict(key='moonsilver', name='Moonsilver', adj='moonsilver',
         desc='Pale silver and night-blue cloth under a crescent moon.',
         th=dict(metal='silver', trim='silver', grip='moonblue', haft='moonblue', cloth='moonblue', gem='moonglow',
                 glowcol='#7cb8ff', motif='crescent', blade='slim', axe='crescent', club='flanged', shield='round',
                 helm='winged', armor='plate', legs='plate', shieldface='moonblue', bowmat='silver', bowtip='crescent',
                 wandmat='silver', wandhead='crescent', rodmat='silver', rodhead='crescent', bookmat='moonblue',
                 packmat='moonblue', packflap='silver', headmat='silver', fletch='moonblue', guardstyle='crescent',
                 wingmat='silver', bowtrim='moonglow', beltmat='moonblue', skirt='moonblue')),
    dict(key='sunsworn', name='Sunsworn', adj='sunsworn',
         desc='Gold and crimson of a sun cult; a ruby at every heart.',
         th=dict(metal='gold', trim='gold', grip='crimson', haft='crimson', cloth='crimson', gem='ruby', glowcol=None,
                 motif='sun', blade='broad', axe='winged', club='flanged', shield='heater', helm='plumed',
                 armor='plate', legs='plate', shieldface='ivory', bowmat='gold', bowtip='wing', wandmat='gold',
                 wandhead='gem', rodmat='gold', rodhead='sun', bookmat='crimson', packmat='crimson', packflap='gold',
                 headmat='gold', fletch='crimson', fuller='crimson', plume='crimson', beltmat='crimson',
                 skirt='crimson', tasset='crimson', bowtrim='ivory')),
    dict(key='oathsteel', name='Oathsteel', adj='oathsteel',
         desc='Plain steel and a red cross: the gear of the oathbound crusaders.',
         th=dict(metal='steel', trim='steel', grip='leather', haft='wood', cloth='red', gem='ruby', glowcol=None,
                 motif='cross', blade='long', axe='bearded', club='hammer', shield='heater', helm='great',
                 armor='tabard', legs='plate', shieldface='white', quarter=None, bowmat='wood', bowtip=None,
                 wandmat='wood', wandhead='gem', rodmat='wood', rodhead='claw', bookmat='leather', packmat='leather',
                 packflap='red', headmat='steel', fletch='red', plume='red', bootmat='steel', beltmat='leather')),
    # ---- the four kit sets (three class kits each)
    dict(key='rimeglass', name='Rimeglass', adj='rimeglass', kits=True,
         desc='Armour grown from blue glacier crystal that never melts.',
         th=dict(metal='ice', trim='icedeep', grip='icedeep', haft='icedeep', cloth='icedeep', gem='ice', glowcol='#7ccaf6',
                 motif='snow', blade='crystal', shield='crystal', helm='crystal', armor='crystal', legs='plate',
                 shieldface='icedeep', bowmat='ice', bowtip='crystal', wandmat='ice', rodmat='icedeep', rodhead='crystal',
                 bookmat='icedeep', packmat='icedeep', packflap='ice', headmat='ice', fletch='white', bootmat='ice',
                 beltmat='icedeep', bowtrim='white')),
    dict(key='emeraldine', name='Emeraldine', adj='emeraldine', kits=True,
         desc='Royal gold set with cut emeralds.',
         th=dict(metal='gold', trim='gold', grip='emerald', haft='emerald', cloth='emerald', gem='emerald', glowcol=None,
                 motif='emerald', blade='broad', shield='tower', helm='crown', armor='plate', legs='plate',
                 shieldface='emerald', bowmat='gold', bowtip=None, wandmat='gold', rodmat='gold', rodhead='claw',
                 bookmat='emerald', packmat='emerald', packflap='gold', headmat='gold', fletch='emerald',
                 bootmat='gold', beltmat='emerald', fuller='emerald', skirt='emerald', bowtrim='emerald')),
    dict(key='starwing', name='Starwing', adj='starwing', kits=True,
         desc='Winged gold of the sky wardens, with teal star stones.',
         th=dict(metal='ivorygold', trim='gold', grip='teal', haft='teal', cloth='teal', gem='teal', glowcol='#4ee0d8',
                 motif='wing', blade='broad', shield='kite', helm='winged', armor='plate', legs='plate',
                 shieldface='teal', bowmat='ivorygold', bowtip='wing', wandmat='gold', rodmat='gold', rodhead='wing',
                 bookmat='teal', packmat='teal', packflap='ivorygold', headmat='gold', fletch='white', wingmat='ivorygold',
                 guardstyle='wing', bootwing='ivorygold', bootmat='ivorygold', beltmat='teal', bowtrim='teal')),
    dict(key='thornwild', name='Thornwild', adj='thornwild', kits=True,
         desc='Green leaf armour on orange heartwood, with a living green glow.',
         th=dict(metal='green', trim='orangewood', grip='orangewood', haft='orangewood', cloth='green', gem='lime',
                 glowcol='#a6ff4a', motif='sprout', blade='leaf', shield='round_wood', helm='crown', armor='leaf',
                 legs='leather', shieldface='orangewood', bowmat='orangewood', bowtip='leaf', wandmat='orangewood',
                 rodmat='orangewood', rodhead='branch', bookmat='green', packmat='orangewood', packflap='green',
                 headmat='lime', fletch='green', scale='green', guardstyle='thorn', bootmat='green', hoodleaf='green',
                 beltmat='orangewood')),
]


def pieces(s):
    """-> [(key, kind, style, name, kit)] of a set, in atlas order"""
    out = []
    if s.get('kits'):
        for kit, kind, style, pat in KITS:
            key = '%s_%s_%s' % (s['key'], kit, kind) if kit != 'shared' else '%s_%s' % (s['key'], kind)
            out.append((key, kind, style, pat % s['adj'], kit))
    else:
        for kind in FULL:
            out.append(('%s_%s' % (s['key'], kind), kind, None, NAMES[kind] % s['adj'], None))
    return out
