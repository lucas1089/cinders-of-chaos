# Sprite libraries (assets only, not code)

Converted sprite libraries for later use: 10.98 Tibia.dat + Tibia.spr pairs (our format), with catalogue.csv
(library id, source id, size, frames, flags, short description, sprite hash), skipped.csv, build.log and contact
sheets with library ids. Built and used by client/tools/sprites/import_donor_things.py (main branch); see
client/MANIFEST.md "Donor art libraries". Catalogue rows tagged "named character" are recognisable characters of
other works: library only, never live.

Restore one library:

    cat donorB/donorB.tar.xz.part* | xz -d | tar -x      # -> donorB/
    cat donorC/donorC.tar.xz.part* | xz -d | tar -x      # -> donorC/

| folder | things | sprites | spr size |
|---|---|---|---|
| donorB | 7,031 outfits, 20,809 items, 3,200 effects, 290 missiles | 535,781 | 854 MB |
| donorC | 1,234 outfits, 26,117 items, 1,546 effects, 109 missiles | 274,559 | 549 MB |

SHA256SUMS lists the parts.
