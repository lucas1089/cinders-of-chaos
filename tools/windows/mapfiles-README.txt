Cinders of Chaos: map files
===========================

Everything a 10.98 map editor needs to open the Cinders of Chaos map, without the editor itself.
The full Windows zip of the same release has the same files with the map editor itself, set up for it
(open-map-editor.bat, README.txt there).

world\       the map as the server loads it: the .otbm, its -spawn.xml and -house.xml
data\1098\   the client data the editor reads:
               Tibia.dat, Tibia.spr   the merged Cinders of Chaos sprites (one single .spr, not shards)
               Tibia.otfi             tells the editor how to read them: extended, transparency (the .spr
                                      has an alpha channel), frame durations, frame groups. Keep it next to
                                      Tibia.dat: without it the items show as black boxes or stripes
               items.otb, items.xml   every item, Chaos items included
               creatures.xml          every monster and NPC of the game for the creature list
data\versions.xml  the versions list sprite and item editors read: dat and spr signatures, otb version,
                   read from the files above at build time

The client is version 10.98: items.otb 10.98, OTBM version 3, Tibia.dat signature 0x42A3, Tibia.spr 0x57BBD603.
An editor that has no .otfi support needs these four set by hand for 10.98: extended on, transparency on, frame
durations on, frame groups on.

An editor that takes one client folder with Tibia.dat, Tibia.spr and items.otb (the one of the full Windows zip):
choose data\1098 of this zip as the 10.98 client folder, then open the .otbm in world\. Copy creatures.xml and
items.xml over the ones of its own 10.98 data folder to have every monster, NPC and item name.
An editor with a client + server workspace: make an empty folder (for example C:\ChaosMap) with these copies
  C:\ChaosMap\data\world\       the files of world\
  C:\ChaosMap\data\items\       items.otb and items.xml from data\1098\
and choose data\1098 of this zip as the client folder and C:\ChaosMap as the server folder.
Keep the -spawn.xml and -house.xml next to the .otbm: the editor reads and saves them with it.
A map you edit goes back to the server through the map master (docs/MAP_GUIDE.md "Editing the live map").
