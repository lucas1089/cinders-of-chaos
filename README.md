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
| donorM | Frontiers of Fantasy (confirmed): scrambled 8.x donor M | 361 / 5,035 / 116 / 34 | most flags unknown: set ground/wall flags before use |
| donorN | 15.x donor N | 13 / 156 / 0 / 0 | |
| donorO | newer build of donor G | 0 / 29 / 0 / 0 | only what G lacks |
| donorQ | 10.98 donor Q | 495 / 2,077 / 508 / 107 | 2,197 rows: library only (retail-style art) |
| donorR | Cyntara: 10.98 donor R (XOR'd dat, keyless spr) | 233 / 3,997 / 45 / 28 | 4,217 rows: library only (retail-style art); usable: wings (outfits 171-209), footstep trails (210-233), effects 34-45, missiles 11-19, 22, 27 |
| donorS | Exodus-Online: 10.98 donor S | 56 / 751 / 23 / 11 | 447 rows: library only (retail-style art); usable: upgrade items 203-343, gem/orb icons 580-799, items 843-850, 14 effects, all missiles |

Each library is deduplicated against the live client pair and every library above it. LIBRARY_MD5 has the md5 of
each Tibia.dat / Tibia.spr; SHA256SUMS lists the parts.

## vfx_packs: raw effect and missile art (PNG sheets, not converted)

Free pixel-art packs from the owner's Drive (permission given by the owner), kept as delivered (PNG sheets only;
GIF previews, duplicates and off-style parts left out). Each folder has `contact_sheet.png` (all kept sheets on a
dark background). The packs came without licence or readme files. Nothing here is in the client pair yet: cut the
frames, scale to our 32 px grid (16 px art: Scale2x; 64 px cells: 2x2 effect or 50% downscale) and import with the
vfx tools of the main branch.

| folder | holds | suggested use |
|---|---|---|
| Pixel_Holy_Spell_Effect_32x32_Pack_3 | 2 sheets, 12 effects of 7-19 frames in 64x64 cells (art up to 64 px despite the name) | holy/arcane bursts, sigils and wards: 2x2 effects or downscaled 32 px; light and holy spells, shields, buffs |
| Free_Effect_Bullet_Impact_Explosion_32x32_V1 | 5 colour variants (blue, green, purple, red, yellow), 640x512 each, about 240 32x32 frames per colour (impacts, bursts, flames, slashes, bolts, rings) | straight 32 px: impact and hit effects per element (red fire, blue ice/energy, green poison/nature, purple dark/arcane, yellow holy/lightning); bolt rows as missiles |
| Super_Package_Retro_Pixel_Effects_32x32_pack_2 | 35 sheets 192x64 = 12 frames of 32x32 each (fire, ice, arcane, poison, earth, dust, wind) | ready 32 px spell effects: explosions, fire fields (05), ice bursts, dust/earth puffs, arcane pulses |
| Effect_and_Bullet_16x16 | 4 colour variants (fire, green, purple, water), 576x208 = 36x13 cells of 16 px | Scale2x to 32 px: small hits, flames, sparkles, orbs and bolts as missiles; fire/poison/dark/ice sets |
| New_All_Fire_Bullet_Pixel_16x16 | 8 colour variants (orange, red, blue, green, yellow, violet, grey, rose), 640x400 = 40x25 cells of 16 px, about 790 frames each | missiles: bolts, arrows, orbs and comets drawn facing right; Scale2x or pad to 32 px, rotate/mirror for the 8 directions (fire, ice, poison, holy, arcane, shadow bolts) |
| Free_Smoke_Fx_Pixel_2 | 4 sheets of 64x64 cells (8-16 frames per row, about 730 frames), white silhouettes | tint per element: smoke, poof, dust, teleport and death puffs, dark-mist rings; 2x2 effects or downscaled 32 px |
| Trap_and_Weapon | kept subset only: `00 All_throwing_stars_crop.png` (52 throwing stars, 48 px cells, cut from the pack's `00 All.png`), `Suriken.png` (spinning saw, 8 frames 32 px), `Spear.png`, `SpikeBall.png`, `Fire.png` | throwing stars as distance-weapon items and spinning missiles; saw/spike ball as trap or missile art; the platformer traps, cannons and rockets were left out |
