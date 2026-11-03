Cinders of Chaos scripts for the map editor
===========================================

Our area generator and our area plans, run inside the map editor (Tools > Lua Scripts). The editor writes the
result into the open map as one change: Undo removes it. Nothing is saved until you save the map.

Before the first run
  open-map-editor.bat (in the package folder) already chose this folder's generate_area.lua as the editor's script.
  Open a map first (the server's map, or File > New for a test map with the 10.98 client).

New area (generate_area.lua)
  1. Open generate_area.lua in Notepad and change the values at the top: biome, width, height, floors, seed, level,
     decoration, light, boss. Save it.
  2. In the editor: Tools > Lua Scripts. Mode "Custom Lua script", "Choose Lua script": generate_area.lua.
  3. Set Destination X / Y (the top-left corner of the area) and Destination floor (the deepest floor of the area).
     Pick a place with no map around it (the area replaces what is on its tiles).
  4. Generate. The log shows the size, the floors, the arrival, the exit portal, the holes and ladders and the spawns.
     Nothing is in the map yet.
  5. Apply writes it. Look at it; Undo (Ctrl+Z) takes it out again. Try another seed, then Generate again.
  The editor cannot place creatures: the spawns are in the log and in generated_spawns.txt, with positions counted
  from the Destination. Add them with the creature palette. The exit portal has no target yet: set it by hand.

Area plan (paint_plan.lua)
  plans\index.txt lists our plans. Set plan = "<id>" at the top of paint_plan.lua, run it like above. The log says
  which Destination puts it exactly where the server has it. plans\<id>-notes.txt lists what the editor cannot
  write: monsters, boss, NPCs, action ids of chests and portals, teleport targets, protection zone tiles.
  A plan over 100,000 tiles is painted one floor per run: floor = <z> (index.txt says which plans).

Limits of the editor
  100,000 tiles, 500,000 items and 120 seconds per run. The editor checks every item id against the loaded
  items.otb: our ids are the server's, so use the 10.98 client of this package (mapeditor\client).

The files under data\ and tools\ are copies of the server's generator and tables; the package build makes this
folder (server/tools/gen_editor_scripts.py). Edit the scripts here only for a try: the next package replaces them.
