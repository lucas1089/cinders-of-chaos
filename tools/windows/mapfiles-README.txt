Cinders of Chaos: map files
===========================

Everything a 10.98 map editor needs to open the Cinders of Chaos map, without the editor itself.
The full Windows zip of the same release has the same files with the editor already set up.

world\       the map as the server loads it: the .otbm, its -spawn.xml and -house.xml
data\1098\   the client data the editor reads:
               Tibia.dat, Tibia.spr   the merged Cinders of Chaos sprites (one single .spr, not shards)
               items.otb, items.xml   every item, Chaos items included
               creatures.xml          the Chaos monsters for the creature palette
               tibia.otfi             the dat/spr format flags (extended, transparency, frame durations and groups)
               the editor's brush, border and tileset lists for 10.98
data\clients.xml   the client versions list: 10.98 = otb 10.98, otbm version 3, dat 0x42A3, spr 0x57BBD603

In the editor, point the 10.98 client data folder at data\1098 and open world\<map>.otbm.
Keep the -spawn.xml and -house.xml next to the .otbm: the editor reads and saves them with it.
A map you edit goes back to the server through the map master (docs/MAP_GUIDE.md "Editing the live map").
