-- Progress metrics (data/scripts/chaos/metrics.lua; server/README.md "Progress metrics (O253)"). metrics.lua also creates
-- the table at startup when it is missing (metrics_core.lua M.createSql, the same columns). Run once:
-- mysql -u USER -p DB < chaos_progress_metrics.sql
--
-- Aggregate counters only: no row belongs to a character, an account, an IP or a chat. One row per (kind, k1, k2):
--   death_area     k1 area (an instance label or the nearest hunt), k2 level band, n deaths
--   death_monster  k1 killer monster ("Player (PvP)", "Player's summon", "Environment or unknown" otherwise), k2 level band
--   session1       k1 minutes bucket (upper limit, "inf" last) of a new character's first session, n characters
--   ttl            k1 milestone level, k2 played-minutes bucket at the first time a character reached it, n characters
--   churn          k1 level band, k2 gone | active, n characters (a snapshot, rewritten daily from `players`)
--   cohort         k1 YYYYMMDD of a first login (server time), n new characters (O258)
--   return         k1 d1 | d3 | d7, k2 YYYYMMDD of the cohort day, n characters that logged in on day first + N or later (O258)
--   first          k1 system (dungeon, rift, ...), k2 "level band|played-minutes bucket" of the first use, n characters (O258)
--   stop           k1 area, k2 level band, n gone characters last seen there (a snapshot, rewritten daily; O258)
--   meta           k1 churn_at (unix time of the snapshot) | churn_days, n the value
CREATE TABLE IF NOT EXISTS `chaos_progress_metrics` (
  `kind` varchar(16) NOT NULL,
  `k1` varchar(64) NOT NULL,
  `k2` varchar(64) NOT NULL DEFAULT '',
  `n` bigint(20) unsigned NOT NULL DEFAULT 0,
  PRIMARY KEY (`kind`, `k1`, `k2`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
