-- Mentors (data/scripts/chaos/mentor.lua; rules in mentor_config.lua; see server/README.md "Mentors").
-- Safe to run more than once; mentor.lua creates the same tables at startup.
-- chaos_mentors: one row per mentor character. active = 0 after a retire (marks and graduates stay). accepting = new
--   apprentices may pick it from the list; public = shown on the website's Mentors page. marks = the balance, earned =
--   every mark ever earned, graduates = apprentices graduated with enough shared time. day_* = today's shared hunting
--   minutes and hunt marks (day_key YYYYMMDD), month_* = the marks of the month (month_key YYYYMM, the monthly cap).
-- chaos_mentor_links: one row per link. status: active, dismissed (by the apprentice), released (by the mentor or
--   staff), graduated. source: list, invite, referral. shared_minutes = minutes hunted together with the bonus.
-- chaos_mentor_milestones: one row per apprentice character and milestone (or 'graduation'). state: paid, unearned
--   (not enough shared time), capped (the mentor's monthly cap), before (reached before the link). notified = the
--   mentor was told.
-- chaos_mentor_purchases: the Mentor Marks shop (titles, cosmetics, supplies; the weekly limits count these rows).
-- chaos_mentor_log: registrations, links, refusals, milestones, graduations, marks, purchases, staff unlinks.

CREATE TABLE IF NOT EXISTS `chaos_mentors` (
  `player_id` int(11) NOT NULL,
  `account_id` int(11) NOT NULL,
  `active` tinyint(1) NOT NULL DEFAULT 1,
  `accepting` tinyint(1) NOT NULL DEFAULT 1,
  `public` tinyint(1) NOT NULL DEFAULT 1,
  `lang` varchar(32) NOT NULL DEFAULT '',
  `hours` varchar(32) NOT NULL DEFAULT '',
  `note` varchar(96) NOT NULL DEFAULT '',
  `marks` int(11) NOT NULL DEFAULT 0,
  `earned` int(11) NOT NULL DEFAULT 0,
  `graduates` int(11) NOT NULL DEFAULT 0,
  `day_key` int(11) NOT NULL DEFAULT 0,
  `day_minutes` int(11) NOT NULL DEFAULT 0,
  `day_marks` int(11) NOT NULL DEFAULT 0,
  `month_key` int(11) NOT NULL DEFAULT 0,
  `month_marks` int(11) NOT NULL DEFAULT 0,
  `registered_at` bigint(20) NOT NULL DEFAULT 0,
  PRIMARY KEY (`player_id`),
  KEY `account_id` (`account_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE IF NOT EXISTS `chaos_mentor_links` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `mentor_id` int(11) NOT NULL,
  `mentor_account` int(11) NOT NULL,
  `apprentice_id` int(11) NOT NULL,
  `apprentice_account` int(11) NOT NULL,
  `status` varchar(10) NOT NULL DEFAULT 'active',
  `source` varchar(8) NOT NULL DEFAULT 'list',
  `start_level` int(11) NOT NULL DEFAULT 0,
  `shared_minutes` int(11) NOT NULL DEFAULT 0,
  `linked_at` bigint(20) NOT NULL DEFAULT 0,
  `ended_at` bigint(20) NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  KEY `mentor_id` (`mentor_id`, `status`),
  KEY `apprentice_id` (`apprentice_id`, `status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE IF NOT EXISTS `chaos_mentor_milestones` (
  `apprentice_id` int(11) NOT NULL,
  `milestone` varchar(16) NOT NULL,
  `link_id` int(11) NOT NULL DEFAULT 0,
  `mentor_id` int(11) NOT NULL DEFAULT 0,
  `state` varchar(10) NOT NULL DEFAULT 'paid',
  `marks` int(11) NOT NULL DEFAULT 0,
  `reached_at` bigint(20) NOT NULL DEFAULT 0,
  `notified` tinyint(1) NOT NULL DEFAULT 0,
  PRIMARY KEY (`apprentice_id`, `milestone`),
  KEY `mentor_id` (`mentor_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE IF NOT EXISTS `chaos_mentor_purchases` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `player_id` int(11) NOT NULL,
  `account_id` int(11) NOT NULL,
  `offer` varchar(32) NOT NULL,
  `cost` int(11) NOT NULL DEFAULT 0,
  `at` bigint(20) NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  KEY `player_id` (`player_id`, `offer`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE IF NOT EXISTS `chaos_mentor_log` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `at` bigint(20) NOT NULL,
  `player_id` int(11) NOT NULL DEFAULT 0,
  `other_id` int(11) NOT NULL DEFAULT 0,
  `action` varchar(16) NOT NULL,
  `detail` varchar(128) NOT NULL DEFAULT '',
  PRIMARY KEY (`id`),
  KEY `player_id` (`player_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
