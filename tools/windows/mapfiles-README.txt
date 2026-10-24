Cinders of Chaos: map files
===========================

Everything a 10.98 map editor needs to open the Cinders of Chaos map, without the editor itself.
The full Windows zip of the same release has the same files, set up for the editor
(open-map-editor.bat; the editor is a separate download, README.txt there).

world\       the map as the server loads it: the .otbm, its -spawn.xml and -house.xml
data\1098\   the client data the editor reads:
               Tibia.dat, Tibia.spr   the merged Cinders of Chaos sprites (one single .spr, not shards)
               items.otb, items.xml   every item, Chaos items included
               creatures.xml          the Chaos monsters for the creature list
data\versions.xml  the versions list sprite and item editors read: dat and spr signatures, otb version,
                   read from the files above at build time

The client is version 10.98: items.otb 10.98, OTBM version 3, Tibia.dat signature 0x42A3, Tibia.spr 0x57BBD603.

Map editor with a client + server workspace: make an empty folder (for example C:\ChaosMap) with these copies
  C:\ChaosMap\data\world\       the files of world\
  C:\ChaosMap\data\items\       items.otb and items.xml from data\1098\
Choose data\1098 of this zip as the client folder and C:\ChaosMap as the server folder, then open the .otbm.
Put creatures.xml in the editor's data\user\data\1098 folder to have the Chaos monsters in its creature list.
Keep the -spawn.xml and -house.xml next to the .otbm: the editor reads and saves them with it.
A map you edit goes back to the server through the map master (docs/MAP_GUIDE.md "Editing the live map").
