-- Infinite arrows and quivers (server/README.md "Infinite arrows and quivers"): quivers stop being containers
-- (server/tools/patch_base_archery.py changes their items.otb group). The engine drops, at login, every saved item
-- whose parent is no container any more, so what players kept inside a quiver moves out first:
--   a quiver inside a container (player_items pid >= 100): its contents go into that container;
--   a quiver in an inventory slot (pid < 100): its contents go into the backpack (the item in slot 3);
--   a quiver in a depot chest, the inbox or the store inbox: its contents go next to it.
-- Arrows and bolts among them are turned into gold at the next login (data/scripts/chaos/archery.lua). Run it with the
-- server stopped, before the first start with the patched items.otb (install_all.py runs every server/sql file).
-- Safe to run more than once: once no item has a quiver as parent, nothing matches.
-- The quiver ids are the `quivers` of server/data/lib/chaos_archery_config.lua (tests/archery_test.lua checks them).

UPDATE `player_items` AS c
  JOIN `player_items` AS q ON q.`player_id` = c.`player_id` AND q.`sid` = c.`pid`
  SET c.`pid` = q.`pid`
  WHERE q.`pid` >= 100
    AND q.`itemtype` IN (28693, 27651, 27694, 27696, 27663, 27686, 27676, 28379, 27695, 29566, 28050, 29873);

UPDATE `player_items` AS c
  JOIN `player_items` AS q ON q.`player_id` = c.`player_id` AND q.`sid` = c.`pid`
  JOIN `player_items` AS b ON b.`player_id` = q.`player_id` AND b.`pid` = 3
  SET c.`pid` = b.`sid`
  WHERE q.`pid` < 100
    AND q.`itemtype` IN (28693, 27651, 27694, 27696, 27663, 27686, 27676, 28379, 27695, 29566, 28050, 29873);

UPDATE `player_depotitems` AS c
  JOIN `player_depotitems` AS q ON q.`player_id` = c.`player_id` AND q.`sid` = c.`pid`
  SET c.`pid` = q.`pid`
  WHERE q.`itemtype` IN (28693, 27651, 27694, 27696, 27663, 27686, 27676, 28379, 27695, 29566, 28050, 29873);

UPDATE `player_inboxitems` AS c
  JOIN `player_inboxitems` AS q ON q.`player_id` = c.`player_id` AND q.`sid` = c.`pid`
  SET c.`pid` = q.`pid`
  WHERE q.`itemtype` IN (28693, 27651, 27694, 27696, 27663, 27686, 27676, 28379, 27695, 29566, 28050, 29873);

UPDATE `player_storeinboxitems` AS c
  JOIN `player_storeinboxitems` AS q ON q.`player_id` = c.`player_id` AND q.`sid` = c.`pid`
  SET c.`pid` = q.`pid`
  WHERE q.`itemtype` IN (28693, 27651, 27694, 27696, 27663, 27686, 27676, 28379, 27695, 29566, 28050, 29873);
