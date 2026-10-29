<?php
/**
 * Database setup for the Cinders of Chaos website. Run by website/install_site.sh
 * with the ZnoteX folder as the working directory:
 *
 *   php <repo>/website/setup/chaos_setup.php
 *
 * Idempotent. Steps:
 *   1. checks the game server's schema is there (accounts, players)
 *   2. SQL/znote_schema.sql: CREATE TABLE IF NOT EXISTS; seed INSERTs only into empty tables (the rule of
 *      ZnoteX's own installer, step 4)
 *   3. migrations: every pending one is run (tolerating "already exists" answers, since a fresh schema holds part
 *      of them) and recorded
 *   4. the Cinders of Chaos plugin (plugins/chaos): install.sql, enabled; the legal texts' version into the game's
 *      server_config (chaos_legal_version, for the in-game notice of legal_notice.lua)
 *   5. the layout: CHAOS_LAYOUT (default "chaos", our child of the purple "void" layout)
 *   6. the menu entries and the editable Rules page, once each (never overwritten); ZnoteX's entries of the pages
 *      this server does not use (shop, points, creatures, spells, forum) switched off once
 *   7. theme options from the environment (Discord URL)
 */
if (PHP_SAPI !== 'cli') {
	exit(1);
}
ob_start(); // ZnoteX starts a session on load, which must not happen after output; messages are printed at the end
$out = '';
$Z = getcwd();
$_SERVER += array('REQUEST_METHOD' => 'GET', 'REQUEST_URI' => '/', 'SCRIPT_NAME' => '/index.php', 'HTTP_HOST' => 'localhost', 'REMOTE_ADDR' => '127.0.0.1');
$config = array();
require $Z . '/config.php'; // pulls in config.local.php last

function finish(string $out, int $code): void {
	while (ob_get_level() > 0) {
		ob_end_clean();
	}
	echo $out;
	exit($code);
}

mysqli_report(MYSQLI_REPORT_OFF);
$link = @new mysqli($config['sqlHost'], $config['sqlUser'], $config['sqlPassword'], $config['sqlDatabase']);
if ($link->connect_errno) {
	finish('database: ' . $link->connect_error . "\n", 1);
}
$link->set_charset('utf8mb4');

$tableExists = static function (string $t) use ($link): bool {
	$r = $link->query("SHOW TABLES LIKE '" . $link->real_escape_string($t) . "'");
	return $r && $r->num_rows > 0;
};

// 1. the game schema
foreach (array('accounts', 'players') as $t) {
	if (!$tableExists($t)) {
		finish("The game database has no `$t` table. Import the game server's schema.sql (and server/sql/*.sql) first.\n", 1);
	}
}
// salted password hashes (about 90 characters) need more than the stock CHAR(40); the same as
// server/sql/chaos_passwords.sql, here too in case the site is installed before that file was imported
$col = $link->query("SHOW COLUMNS FROM `accounts` LIKE 'password'");
$colType = $col ? strtolower((string)($col->fetch_assoc()['Type'] ?? '')) : '';
if ($colType !== 'varchar(255)') {
	if (!$link->query('ALTER TABLE `accounts` MODIFY `password` VARCHAR(255) NOT NULL')) {
		finish('accounts.password: ' . $link->error . "\n", 1);
	}
	$out .= "accounts.password: $colType -> varchar(255) (salted password hashes)\n";
}

// 2. ZnoteX schema
$fresh = !$tableExists('znote_config');
$sql = str_replace(array("\r\n", "\r"), "\n", (string)file_get_contents($Z . '/SQL/znote_schema.sql'));
$sql = preg_replace('/^--.*$/m', '', $sql);
$ran = $skipped = 0;
$errors = array();
foreach (array_filter(array_map('trim', explode(";\n", $sql))) as $st) {
	$st = trim($st, "; \t\n\r");
	if ($st === '') {
		continue;
	}
	if (stripos($st, 'INSERT INTO') === 0 && preg_match('/INSERT INTO `([a-z_]+)`/i', $st, $m)) {
		$r = @$link->query('SELECT 1 FROM `' . $m[1] . '` LIMIT 1');
		if ($r !== false && $r->num_rows > 0) {
			$skipped++;
			continue;
		}
	}
	if ($link->query($st)) {
		$ran++;
	} else {
		$errors[] = $link->error . ' in: ' . substr((string)preg_replace('/\s+/', ' ', $st), 0, 90);
	}
}
$out .= "ZnoteX schema: $ran statements run, $skipped seed inserts skipped, " . count($errors) . " errors\n";
foreach ($errors as $e) {
	$out .= "  $e\n";
}
if ($errors) {
	finish($out, 1);
}

// 3. migrations (needs the full engine). Every pending migration is run statement by statement. A fresh schema
// already holds part of what they add, so "already exists" answers (table, column, key, duplicate seed row) are
// accepted, and on a fresh install seed INSERTs only go into empty tables; any other error stops the installer. Each migration is then recorded with ZnoteX's checksum.
require_once $Z . '/engine/init.php';
znote_migrations_table_ensure();
$tolerated = array(1050, 1060, 1061, 1062, 1068, 1091, 1826);
$n = 0;
foreach (znote_migrations_files() as $name => $f) {
	if (isset(znote_migrations_applied()[$name])) {
		continue;
	}
	foreach (znote_migration_split_sql((string)file_get_contents($f['path'])) as $i => $st) {
		// seed rows on a fresh install: like the schema, only into an empty table (the schema already has its seeds)
		if ($fresh && preg_match('/^\s*INSERT\s+(?:IGNORE\s+)?INTO\s+`?([a-z0-9_]+)`?/i', $st, $m)) {
			$r = @$link->query('SELECT 1 FROM `' . $m[1] . '` LIMIT 1');
			if ($r !== false && $r->num_rows > 0) {
				continue;
			}
		}
		try {
			$ok = $link->query($st);
			$errno = $link->errno;
			$error = $link->error;
		} catch (mysqli_sql_exception $e) { // engine/init.php switches mysqli to exceptions
			$ok = false;
			$errno = (int)$e->getCode();
			$error = $e->getMessage();
		}
		if (!$ok && !in_array($errno, $tolerated, true)) {
			finish($out . "migration $name, statement " . ($i + 1) . ": $error\n", 1);
		}
	}
	db()->execute('INSERT INTO `znote_migrations` (`migration`, `checksum`, `executed_at`, `execution_time_ms`) VALUES (?, ?, ?, 0);', [$name, $f['checksum'], time()]);
	$n++;
}
$out .= "migrations: $n run" . ($fresh ? ' (fresh install)' : '') . "\n";
// the per-account login throttling (patches/znotex-chaos-passwords.patch) counts failures by account name
$r = $link->query("SHOW INDEX FROM `znote_login_attempts` WHERE `Key_name` = 'username_time'");
if ($r && $r->num_rows === 0) {
	$link->query('ALTER TABLE `znote_login_attempts` ADD KEY `username_time` (`username`, `created_at`)');
	$out .= "znote_login_attempts: key username_time added\n";
}

// 4. our plugin
$err = znote_plugin_install('chaos');
if ($err !== '') {
	finish($out . "plugin chaos: $err\n", 1);
}
znote_plugin_set_enabled('chaos', true);
$out .= "plugin chaos: installed and enabled\n";
// Character Bazaar: one open listing per character, held by the database (two list requests at once both passed the
// "already listed" check). A table made before this (the game server's bazaar.lua, an older install.sql) gets the
// generated `active_player_id` and its unique key; a character listed twice keeps its oldest listing, the others are
// cancelled by the staff path (every escrow refunded) first.
if ($tableExists('chaos_bazaar_listings')) {
	$r = $link->query("SHOW COLUMNS FROM `chaos_bazaar_listings` LIKE 'active_player_id'");
	if ($r && $r->num_rows === 0) {
		require_once $Z . '/plugins/chaos/bazaar_lib.php';
		$dups = chaos_bazaar($config)->cancelDuplicateListings();
		if ($dups) {
			$out .= 'chaos_bazaar_listings: duplicate listings cancelled and refunded: ' . implode(', ', $dups) . "\n";
		}
		try {
			$ok = $link->query("ALTER TABLE `chaos_bazaar_listings` ADD COLUMN `active_player_id` int(11) GENERATED ALWAYS AS "
				. "(CASE WHEN `status` IN ('active', 'settling') THEN `player_id` ELSE NULL END) STORED, "
				. 'ADD UNIQUE KEY `chaos_bazaar_listings_active` (`active_player_id`)');
			$error = $link->error;
		} catch (mysqli_sql_exception $e) {
			$ok = false;
			$error = $e->getMessage();
		}
		if (!$ok) {
			finish($out . 'chaos_bazaar_listings.active_player_id: ' . $error . "\n", 1);
		}
		$out .= "chaos_bazaar_listings: one open listing per character (unique key)\n";
	}
	// at most maxActivePerAccount open listings per seller, held by the database too (two characters of one account
	// listed at once both passed the count): `seller_slot`, the generated `active_seller_id` and their unique key. Open
	// listings made before get a slot first (bazaar_lib.php assignSellerSlots), then the key is added.
	// (keyed on the index, so a run stopped between the steps finishes them the next time)
	$r = $link->query("SHOW INDEX FROM `chaos_bazaar_listings` WHERE `Key_name` = 'chaos_bazaar_listings_seller_slot'");
	if ($r && $r->num_rows === 0) {
		require_once $Z . '/plugins/chaos/bazaar_lib.php';
		try {
			$c = $link->query("SHOW COLUMNS FROM `chaos_bazaar_listings` LIKE 'active_seller_id'");
			$ok = $c && $c->num_rows > 0 ? true : $link->query('ALTER TABLE `chaos_bazaar_listings` ADD COLUMN `seller_slot` tinyint(3) unsigned DEFAULT NULL, '
				. "ADD COLUMN `active_seller_id` int(11) GENERATED ALWAYS AS (CASE WHEN `status` IN ('active', 'settling') THEN `seller_account_id` ELSE NULL END) STORED");
			if ($ok) {
				$slotted = chaos_bazaar($config)->assignSellerSlots();
				if ($slotted) {
					$out .= "chaos_bazaar_listings: seller slots given to $slotted open listings\n";
				}
				$ok = $link->query('ALTER TABLE `chaos_bazaar_listings` ADD UNIQUE KEY `chaos_bazaar_listings_seller_slot` (`active_seller_id`, `seller_slot`)');
			}
			$error = $link->error;
		} catch (mysqli_sql_exception $e) {
			$ok = false;
			$error = $e->getMessage();
		}
		if (!$ok) {
			finish($out . 'chaos_bazaar_listings.active_seller_id: ' . $error . "\n", 1);
		}
		$out .= "chaos_bazaar_listings: auction limit per seller (unique key)\n";
	}
}
// the version of the legal texts for the game server: server_config chaos_legal_version. The game's legal_notice.lua
// tells an account without an acceptance of this version, at login, to accept on the website (legal_lib.php).
require_once $Z . '/plugins/chaos/legal_lib.php';
if ($tableExists('server_config') && chaos_legal_dir() !== '') {
	$v = $link->real_escape_string(chaos_legal_version());
	if (!$link->query("INSERT INTO `server_config` (`config`, `value`) VALUES ('chaos_legal_version', '$v') ON DUPLICATE KEY UPDATE `value` = '$v'")) {
		finish($out . 'server_config chaos_legal_version: ' . $link->error . "\n", 1);
	}
	$out .= "legal texts: version $v\n";
}

// 5. layout
$layout = theme_sanitize((string)(getenv('CHAOS_LAYOUT') ?: 'chaos'));
if ($layout === '' || !is_dir($Z . '/layouts/' . $layout)) {
	finish($out . "layout '$layout' is not installed\n", 1);
}
setting_set('layout', $layout);
$out .= "layout: $layout\n";

// 6. menu entries (location main; the shell shows parents with drop-downs), added once
// Clean addresses (README "Web server"): an entry of a top-level page with .php ("highscores.php", "page.php?p=rules",
// ZnoteX's own and the ones older runs of this setup added) gets the same address without it, once; the web server
// rules serve both, the .php form through a 301. Only the form changes, so an entry the owner edited keeps its page.
// patches/znotex-chaos-clean-urls.patch makes ZnoteX's menu checks read both forms.
require_once $Z . '/plugins/chaos/lib.php';
$cleaned = 0;
foreach ((array)db()->fetchAll('SELECT `id`, `url` FROM `znote_menu` WHERE `url` LIKE ?;', ['%.php%']) as $row) {
	$clean = chaos_clean_url((string)$row['url']);
	if ($clean !== (string)$row['url']) {
		db()->execute('UPDATE `znote_menu` SET `url` = ? WHERE `id` = ?;', [$clean, (int)$row['id']]);
		$cleaned++;
	}
}
if ($cleaned > 0) {
	$out .= "menu: $cleaned address(es) without .php\n";
}
$menu = static function (string $label, string $url, string $icon, int $sort, int $parent = 0, string $visibility = 'all'): int {
	$find = static function () use ($label, $url) {
		return db()->fetchOne('SELECT `id` FROM `znote_menu` WHERE `location` = ? AND `label` = ? AND `url` = ? LIMIT 1;', ['main', $label, $url]);
	};
	$row = $find();
	if (is_array($row)) {
		return (int)$row['id']; // kept as the owner left it (moved, renamed icon, switched off)
	}
	db()->execute('INSERT INTO `znote_menu` (`location`, `parent_id`, `label`, `url`, `icon`, `visibility`, `sort_order`) VALUES (?, ?, ?, ?, ?, ?, ?);',
		['main', $parent, $label, $url, $icon, $visibility, $sort]);
	$row = $find();
	return is_array($row) ? (int)$row['id'] : 0;
};
// the player wiki (plugins/chaos/pages/wiki.php): guides and the reference generated from the game data
$menu('Wiki', 'page?plugin=chaos&p=wiki', 'fa-book', 14);
$out .= "menu: Wiki\n";
$world = $menu('The World', 'serverinfo?world', 'fa-fire', 15);
$menu('Server Info', 'serverinfo', 'fa-book', 1, $world);
$menu('Patch Notes', 'page?plugin=chaos&p=patchnotes', 'fa-file-text-o', 2, $world);
$menu('Leaderboards', 'page?plugin=chaos&p=leaderboards', 'fa-trophy', 3, $world);
$menu('Seasons', 'page?plugin=chaos&p=seasons', 'fa-hourglass-half', 4, $world);
$menu('Rules', 'page?p=rules', 'fa-gavel', 5, $world);
$out .= "menu: The World (Server Info, Patch Notes, Leaderboards, Seasons, Rules)\n";
// the community goal and the week's world modifiers (plugins/chaos/pages/community.php, read from the game's tables)
$menu('Community', 'page?plugin=chaos&p=community', 'fa-fire', 6, $world);
$out .= "menu: The World > Community\n";
// the Ashen Chronicle and the Capital Memorial (plugins/chaos/pages/chronicle.php, memorial.php; read from the game's tables)
$menu('Chronicle', 'page?plugin=chaos&p=chronicle', 'fa-book', 6, $world);
$menu('Memorial', 'page?plugin=chaos&p=memorial', 'fa-university', 6, $world);
$out .= "menu: The World > Chronicle, Memorial\n";
// the guild wars declared in game: current wars and the history (plugins/chaos/pages/guildwars.php)
$menu('Guild Wars', 'page?plugin=chaos&p=guildwars', 'fa-shield', 7, $world);
$out .= "menu: The World > Guild Wars\n";
// the mentors who opted in to be shown (plugins/chaos/pages/mentors.php, read from the game's chaos_mentor* tables)
$menu('Mentors', 'page?plugin=chaos&p=mentors', 'fa-users', 8, $world);
$out .= "menu: The World > Mentors\n";
// player-to-player character auctions for Chaos Coins (plugins/chaos/pages/bazaar.php, bazaar_lib.php)
$menu('Character Bazaar', 'page?plugin=chaos&p=bazaar', 'fa-gavel', 9, $world);
$out .= "menu: The World > Character Bazaar\n";
// creator codes and the account's referral link (plugins/chaos/pages/creator.php, creator_lib.php)
$menu('Creator Codes', 'page?plugin=chaos&p=creator', 'fa-star', 10, $world);
$out .= "menu: The World > Creator Codes\n";
// the fair-play pledge, the calendar and the creator program (plugins/chaos/pages/fairplay.php, calendar.php, creators.php)
$menu('Calendar', 'page?plugin=chaos&p=calendar', 'fa-calendar', 11, $world);
$menu('Creator Program', 'page?plugin=chaos&p=creators', 'fa-video-camera', 12, $world);
$menu('Fair Play', 'page?plugin=chaos&p=fairplay', 'fa-balance-scale', 13, $world);
$out .= "menu: The World > Calendar, Creator Program, Fair Play\n";
// the donation page (plugins/chaos/pages/coins.php): Chaos Coins are a thank-you for a voluntary donation
$menu('Donate', 'page?plugin=chaos&p=coins', 'fa-heart', 16);
$out .= "menu: Donate\n";
// the staff's player reports and anti-bot log (plugins/chaos/pages/reports.php): admin accounts only, under ZnoteX's
// "Admin Panel" entry when it is there
$adminEntry = db()->fetchOne('SELECT `id` FROM `znote_menu` WHERE `location` = ? AND `url` = ? AND `parent_id` = 0 LIMIT 1;', ['main', 'admin/index.php']);
$menu('Player Reports', 'page?plugin=chaos&p=reports', 'fa-flag', 17, is_array($adminEntry) ? (int)$adminEntry['id'] : 0, 'admin');
$out .= "menu: Player Reports (staff only)\n";
// balance telemetry for the staff (plugins/chaos/pages/telemetry.php): admin accounts with a group 5+ character only
$menu('Balance Telemetry', 'page?plugin=chaos&p=telemetry', 'fa-line-chart', 18, is_array($adminEntry) ? (int)$adminEntry['id'] : 0, 'admin');
$out .= "menu: Balance Telemetry (staff only)\n";

// ZnoteX's own entries that lead to pages this server does not use (README "Not used on this server"): the shop and
// its points, the creature and spell lists (both in the client) and the forum. Switched off once per install, on a
// fresh install and at the next run on an existing one; the marker keeps an entry the owner switches back on in
// Admin Panel > Menus on. A parent left with no entry switched on (Library) goes too.
if (setting('chaos:stock_menu_hidden', '') !== '1') {
	$hidden = 0;
	$parents = array();
	foreach (array('shop', 'buypoints', 'creatures', 'spells', 'forum', 'shop.php', 'buypoints.php', 'creatures.php', 'spells.php', 'forum.php') as $url) {
		foreach ((array)db()->fetchAll('SELECT `id`, `parent_id`, `active` FROM `znote_menu` WHERE `location` = ? AND `url` = ?;', ['main', $url]) as $row) {
			if ((int)$row['active'] === 1) {
				db()->execute('UPDATE `znote_menu` SET `active` = 0 WHERE `id` = ?;', [(int)$row['id']]);
				$hidden++;
			}
			if ((int)$row['parent_id'] > 0) {
				$parents[(int)$row['parent_id']] = true;
			}
		}
	}
	foreach (array_keys($parents) as $pid) {
		$on = db()->fetchOne('SELECT COUNT(*) AS `n` FROM `znote_menu` WHERE `parent_id` = ? AND `active` = 1;', [$pid]);
		$parent = db()->fetchOne('SELECT `active` FROM `znote_menu` WHERE `id` = ? AND `parent_id` = 0;', [$pid]);
		if (is_array($on) && (int)$on['n'] === 0 && is_array($parent) && (int)$parent['active'] === 1) {
			db()->execute('UPDATE `znote_menu` SET `active` = 0 WHERE `id` = ?;', [$pid]);
			$hidden++;
		}
	}
	setting_set('chaos:stock_menu_hidden', '1');
	$out .= "menu: $hidden stock entries switched off (Shop, Buy points, Library > Creatures / Spells, Community > Forum)\n";
}

// the Rules page: an editable page (Admin Panel > Pages), added once and never overwritten
if (znote_table_exists('znote_pages')) {
	$has = db()->fetchOne('SELECT `id` FROM `znote_pages` WHERE `slug` = ? LIMIT 1;', ['rules']);
	if (!is_array($has)) {
		$rules = (string)file_get_contents(__DIR__ . '/rules.bbcode');
		db()->execute('INSERT INTO `znote_pages` (`slug`, `title`, `body`, `created`, `updated`, `player_id`, `access`, `active`) VALUES (?, ?, ?, ?, ?, 0, 0, 1);',
			['rules', 'Rules', $rules, time(), time()]);
		$out .= "rules page: added (edit it in Admin Panel > Pages)\n";
	}
}

// 7. theme options from the environment
$discord = (string)getenv('CHAOS_DISCORD_URL');
if ($discord !== '') {
	setting_set(theme_option_key('chaos', 'discord_url'), $discord);
	setting_set(theme_option_key('void', 'discord_url'), $discord);
	$out .= "discord: set\n";
}

finish($out, 0);
