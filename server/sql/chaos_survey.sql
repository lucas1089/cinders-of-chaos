-- New player survey (data/scripts/chaos/survey.lua; server/README.md "New player funnel and survey (O374)"). survey.lua
-- also creates the table at startup when it is missing (survey_core.lua S.createSql, the same columns). Run once:
-- mysql -u USER -p DB < chaos_survey.sql
--
-- One row per account and stage (level 20 / 50), written once: answered or skipped. account_id is only the unique key
-- (never shown: chaos-ctl.sh survey reads stage, status, the answers, level, minutes and the time).
--   fun        "How fun is it?" 1-5, 0 = not answered
--   recommend  "Would you recommend it?" 1 yes, 0 no, -1 not answered
--   confused   "What confused you so far?" up to 200 characters, cleaned by the server (survey_core.lua S.cleanText)
--   level      the character's level when it answered; minutes: its played minutes
CREATE TABLE IF NOT EXISTS `chaos_survey` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `account_id` int(10) unsigned NOT NULL,
  `stage` smallint(5) unsigned NOT NULL,
  `status` varchar(8) NOT NULL,
  `fun` tinyint(3) NOT NULL DEFAULT 0,
  `recommend` tinyint(3) NOT NULL DEFAULT -1,
  `confused` varchar(200) NOT NULL DEFAULT '',
  `level` int(10) unsigned NOT NULL DEFAULT 0,
  `minutes` int(10) unsigned NOT NULL DEFAULT 0,
  `created_at` int(10) unsigned NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `account_stage` (`account_id`, `stage`),
  KEY `created_at` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
