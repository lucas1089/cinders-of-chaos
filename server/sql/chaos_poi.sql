-- Points of interest (server/data/scripts/chaos/poi.lua; README "Map markers"). poi.lua runs the same statement at
-- startup.
-- chaos_poi_seen: one row per character, the points of interest it discovered: keys of 10 characters (poi_core.lua
-- P.key: a kind letter and the position in hex), comma-separated and sorted.
CREATE TABLE IF NOT EXISTS `chaos_poi_seen` (
  `player_id` int(11) NOT NULL,
  `seen` mediumtext NOT NULL,
  PRIMARY KEY (`player_id`),
  CONSTRAINT `chaos_poi_seen_players_fk` FOREIGN KEY (`player_id`) REFERENCES `players` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
