<?php
/**
 * Prints ZnoteX's config.local.php for Project Chaos, built from environment
 * variables (see website/README.md). Run by website/install_site.sh:
 *
 *   php website/setup/write_config.php > <site>/config.local.php
 *
 * Every value is written with var_export(), so quotes or backslashes in a
 * password cannot break the file. Secrets come from the environment only and
 * are never stored in the repository.
 */
if (PHP_SAPI !== 'cli') {
	exit(1);
}

function env(string $name, string $default = ''): string {
	$v = getenv($name);
	return ($v === false || $v === '') ? $default : (string)$v;
}

function int_list(string $csv): array {
	$out = array();
	foreach (preg_split('/[\s,]+/', $csv, -1, PREG_SPLIT_NO_EMPTY) as $p) {
		if (ctype_digit($p)) {
			$out[] = (int)$p;
		}
	}
	return $out;
}

function export($value): string {
	return var_export($value, true);
}

$db = array(
	'host' => env('CHAOS_DB_HOST', '127.0.0.1'),
	'user' => env('CHAOS_DB_USER'),
	'pass' => env('CHAOS_DB_PASSWORD', env('CHAOS_DB_PASS')), // CHAOS_DB_PASS: the game server's /etc/chaos/chaos.env
	'port' => (int)env('CHAOS_DB_PORT', '3306'),
	'name' => env('CHAOS_DB_NAME'),
);
if ($db['user'] === '' || $db['name'] === '') {
	fwrite(STDERR, "CHAOS_DB_USER and CHAOS_DB_NAME are required.\n");
	exit(1);
}

// Towns: the server writes its towns table from the map at startup. New characters land on the tutorial island at
// their first login (newplayer_tutorial.lua) and are sent to their town's temple afterwards.
$towns = array();
mysqli_report(MYSQLI_REPORT_OFF);
$link = @new mysqli($db['host'], $db['user'], $db['pass'], $db['name'], $db['port']);
if (!$link->connect_errno) {
	$res = $link->query('SELECT `id`, `name` FROM `towns` ORDER BY `id`');
	if ($res) {
		while ($row = $res->fetch_assoc()) {
			$towns[(int)$row['id']] = (string)$row['name'];
		}
	}
	$link->close();
}
$wanted = int_list(env('CHAOS_START_TOWNS', '1'));
if (!$towns) {
	fwrite(STDERR, "note: the towns table is empty (the game server fills it at its first start); using generic town names.\n");
	foreach ($wanted as $id) {
		$towns[$id] = 'Town ' . $id;
	}
}
$start = array_values(array_filter($wanted, static function (int $id) use ($towns): bool {
	return isset($towns[$id]);
}));
if (!$start) {
	$start = array((int)array_key_first($towns));
	fwrite(STDERR, 'note: none of CHAOS_START_TOWNS exists in the towns table; using town ' . $start[0] . ".\n");
}

// Classes (server/data/scripts/chaos/chaos_constants.lua, Chaos.classes). fromVoc is false for every class on
// purpose: ZnoteX's highscores group one promotion per base vocation, and every Chaos base class has two
// ascensions, so each class is its own highscore group (the class lines are on the Leaderboards page).
$classes = array(
	0 => 'None',
	4 => 'Warrior', 8 => 'Juggernaut', 14 => 'Berserker',
	3 => 'Ranger', 7 => 'Deadeye', 15 => 'Beastmaster',
	1 => 'Mystic', 5 => 'Elementalist', 10 => 'Illusionist',
	11 => 'Thief', 12 => 'Ninja', 13 => 'Samurai',
	17 => 'Monk', 18 => 'Shadowfist', 19 => 'Iron Sage',
	20 => 'Necromancer', 21 => 'Lich', 22 => 'Bone Lord',
	23 => 'Templar', 24 => 'Inquisitor', 25 => 'Sentinel',
);
// stat gains per level (server/data/XML/chaos_vocations*.xml: gainhp / gainmana / gaincap)
$gains = array(
	0 => array(5, 5, 10),
	4 => array(15, 5, 25), 8 => array(15, 5, 25), 14 => array(14, 6, 25),
	3 => array(10, 15, 20), 7 => array(10, 15, 20), 15 => array(11, 14, 21),
	1 => array(5, 30, 10), 5 => array(5, 30, 10), 10 => array(7, 27, 12),
	11 => array(12, 10, 22), 12 => array(12, 10, 22), 13 => array(13, 9, 24),
	17 => array(12, 10, 22), 18 => array(12, 10, 22), 19 => array(14, 9, 25),
	20 => array(8, 26, 13), 21 => array(7, 28, 12), 22 => array(9, 24, 15),
	23 => array(14, 8, 25), 24 => array(13, 10, 24), 25 => array(14, 7, 25),
);
$vocations = array();
$vocGains = array();
$skills = array();
foreach ($classes as $id => $name) {
	$vocations[$id] = array('name' => $name, 'fromVoc' => false);
	$vocGains[$id] = array('hp' => $gains[$id][0], 'mp' => $gains[$id][1], 'cap' => $gains[$id][2]);
	$skills[$id] = array('magic' => 0, 'fist' => 10, 'club' => 10, 'axe' => 10, 'sword' => 10, 'dist' => 10, 'shield' => 10, 'fishing' => 10);
}

$admins = array_values(array_filter(array_map('trim', explode(',', env('CHAOS_ADMIN_ACCOUNTS')))));
$serverData = env('CHAOS_SERVER_DATA');
$winUrl = env('CHAOS_CLIENT_WINDOWS_URL', '#download-coming-soon');
$linuxUrl = env('CHAOS_CLIENT_LINUX_URL', '#download-coming-soon');

$out = "<?php\n"
	. "// Written by website/install_site.sh (website/setup/write_config.php) on " . date('Y-m-d H:i:s') . ".\n"
	. "// Regenerated on every run: change the environment variables (website/README.md), not this file.\n\n"
	. "\$config['sqlHost'] = " . export($db['host']) . ";\n"
	. "\$config['sqlUser'] = " . export($db['user']) . ";\n"
	. "\$config['sqlPassword'] = " . export($db['pass']) . ";\n"
	. "\$config['sqlDatabase'] = " . export($db['name']) . ";\n"
	. ($db['port'] !== 3306 ? "ini_set('mysqli.default_port', " . export((string)$db['port']) . "); // ZnoteX connects without a port\n" : '')
	. "\n"
	. "\$config['ServerEngine'] = 'TFS_10'; // TFS 1.4 based\n"
	. "\$config['client'] = 1098;\n"
	. "\$config['site_title'] = 'Project Chaos';\n"
	. "\$config['site_title_context'] = 'The world was not ended. It was broken, and the pieces still bleed.';\n"
	. "\$config['site_url'] = " . export(env('CHAOS_SITE_URL', 'http://localhost')) . ";\n"
	. "\$config['cache']['memory'] = false; // no APCu needed\n"
	. "\$config['language_selector'] = false; // the site is written in English\n"
	. "\$config['page_admin_access'] = " . export($admins) . "; // account NAMES with the admin panel\n\n"
	. "// Classes, not the stock vocations\n"
	. "\$config['vocations'] = " . export($vocations) . ";\n"
	. "\$config['vocations_gain'] = " . export($vocGains) . ";\n"
	. "// The four base classes. The plugin plugins/chaos adds the Monk (17), Necromancer (20) and Templar (23) for\n"
	. "// accounts with a row in chaos_class_unlocks, on every request, before createcharacter.php validates.\n"
	. "\$config['available_vocations'] = array(4, 3, 1, 11);\n\n"
	. "// New characters: level 1 (the tutorial island, the starter kits and the season join rule expect it); the\n"
	. "// position 0,0,0 makes the server use the town's temple, and the tutorial island takes over at the first login.\n"
	. "\$config['towns'] = " . export($towns) . ";\n"
	. "\$config['available_towns'] = " . export($start) . ";\n"
	. "\$config['default_pos'] = array('x' => 0, 'y' => 0, 'z' => 0);\n"
	. "\$config['player']['base'] = array('level' => 1, 'health' => 150, 'mana' => 0, 'cap' => 400, 'soul' => 100);\n"
	. "\$config['player']['create']['level'] = 1;\n"
	. "\$config['player']['create']['novocation'] = array('level' => 1, 'forceTown' => false, 'townId' => " . export($start[0]) . ");\n"
	. "\$config['player']['create']['skills'] = " . export($skills) . ";\n\n"
	. "// Downloads (placeholders until the owner sets CHAOS_CLIENT_*_URL)\n"
	. "\$config['client_download'] = " . export($winUrl) . ";\n"
	. "\$config['client_download_linux'] = " . export($linuxUrl) . ";\n"
	. "\$config['downloads']['entries'] = " . export(array(
		array('key' => 'windows_client', 'label' => 'Windows client', 'section' => 'client', 'enabled' => true, 'url' => $winUrl, 'image' => '', 'description' => 'The Project Chaos client for Windows 10 and 11 (64-bit).'),
		array('key' => 'linux_client', 'label' => 'Linux client', 'section' => 'client', 'enabled' => true, 'url' => $linuxUrl, 'image' => '', 'description' => 'The Project Chaos client for 64-bit Linux.'),
	)) . ";\n\n"
	. "// Outfit images are drawn by an external service; off until the owner picks one he trusts.\n"
	. "\$config['show_outfits'] = array('shop' => false, 'highscores' => false, 'characterprofile' => false, 'onlinelist' => false, 'imageServer' => '');\n\n"
	. "// Project Chaos (plugins/chaos)\n"
	. "\$config['chaos'] = " . export(array(
		'server_data' => $serverData,
		'game_host' => env('CHAOS_GAME_HOST'),
		'game_port' => (int)env('CHAOS_GAME_PORT', '7171'),
		'discord_url' => env('CHAOS_DISCORD_URL'),
		'staff_group' => 4,
		'staff_account_type' => 5,
		'base_classes' => array(4, 3, 1, 11),
		'depot_boxes' => env('CHAOS_DEPOT_BOXES', '0') === '1',
	)) . ";\n";

echo $out;
