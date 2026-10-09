# Sprite libraries (assets only, not code)

Converted sprite libraries for later use: 10.98 Tibia.dat + Tibia.spr pairs (our format), with catalogue.csv
(library id, source id, size, frames, flags, short description, sprite hash), skipped.csv, build.log and contact
sheets with library ids. Built and used by client/tools/sprites/import_donor_things.py (main branch); see
client/MANIFEST.md "Donor art libraries". Catalogue rows tagged "named character" are recognisable characters of
other works: library only, never live.

Restore one library (X = B, C, D, ...):

    cat donorX/donorX.tar.xz.part* | xz -d | tar -x      # -> donorX/

| folder | source (generic name) | outfits / items / effects / missiles | notes |
|---|---|---|---|
| donorB | 64px-style donor | 7,031 / 20,809 / 3,200 / 290 | |
| donorC | 10.98 donor C | 1,234 / 26,117 / 1,546 / 109 | 444 outfits tagged named character |
| donorD | 10.98 donor without alpha | 1,255 / 20,098 / 351 / 76 | some rows tagged named character |
| donorE | 7.72 donor | 992 / 30,430 / 340 / 146 | every row: library only (commercial server art) |
| donorF | 10.98 donor F | 457 / 5,846 / 266 / 23 | |
| donorG | custom-signature donor G | 675 / 3,746 / 199 / 17 | 258 outfits tagged named character |
| donorH | 7.72 donor H | 253 / 6,122 / 65 / 35 | |
| donorI | 8.60 donor I | 297 / 14 / 28 / 0 | wings and auras |
| donorJ | 10.10-style donor J | 372 / 6,682 / 111 / 38 | dark walls and lava grounds (tagged requested) |
| donorK | 8.60 donor K | 88 / 250 / 106 / 45 | |
| donorM | scrambled 8.x donor M | 361 / 5,035 / 116 / 34 | most flags unknown: set ground/wall flags before use |
| donorN | 15.x donor N | 13 / 156 / 0 / 0 | |
| donorO | newer build of donor G | 0 / 29 / 0 / 0 | only what G lacks |
| donorQ | 10.98 donor Q | 495 / 2,077 / 508 / 107 | 2,197 rows: library only (retail-style art) |

Each library is deduplicated against the live client pair and every library above it. LIBRARY_MD5 has the md5 of
each Tibia.dat / Tibia.spr; SHA256SUMS lists the parts.
