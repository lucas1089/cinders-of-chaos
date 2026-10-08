-- Patch notes (data/scripts/chaos/patchnotes.lua): the last week each account has seen and its
-- "Don't show automatically" setting. patchnotes.lua also creates this table at startup if it is missing.
CREATE TABLE IF NOT EXISTS `chaos_patchnotes` (
  `account_id` int(11) NOT NULL,
  `seen_key` varchar(80) NOT NULL DEFAULT '',
  `auto_open` tinyint(1) NOT NULL DEFAULT 1,
  `updated` bigint(20) NOT NULL DEFAULT 0,
  PRIMARY KEY (`account_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
