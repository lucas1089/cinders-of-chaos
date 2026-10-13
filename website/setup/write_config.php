<?php
/**
 * Prints ZnoteX's config.local.php for Cinders of Chaos, built from environment
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

$iterations = max(1000, min(10000000, (int)env('CHAOS_PASSWORD_ITERATIONS', '120000')));
$admins = array_values(array_filter(array_map('trim', explode(',', env('CHAOS_ADMIN_ACCOUNTS')))));
$serverData = env('CHAOS_SERVER_DATA');
// no default: a missing address must not turn into "http://localhost" (recovery and PayPal links to localhost, and
// the donation mock's local-site gate open on a live server); install_site.sh refuses to run without it
$siteUrl = env('CHAOS_SITE_URL');
if ($siteUrl === '') {
	fwrite(STDERR, "note: CHAOS_SITE_URL is empty: links in mails and from PayPal will not work.\n");
}
// Sprite images (README "Sprite images"): install_site.sh sets CHAOS_SPRITES=1 when chaos-sprites/index.json is there.
$sprites = env('CHAOS_SPRITES') === '1';
$https = stripos($siteUrl, 'https://') === 0;
$captchaSite = env('CHAOS_RECAPTCHA_SITE_KEY');
$captchaSecret = env('CHAOS_RECAPTCHA_SECRET');
$captcha = $captchaSite !== '' && $captchaSecret !== '';
// Content-Security-Policy (README "Web server"). script-src keeps 'unsafe-inline': the parent layout (Void) and
// ZnoteX's pages and admin panel carry inline scripts and onclick handlers we do not own. Everything else is 'self'
// (plus Google's reCAPTCHA hosts when it is on, and YouTube frames for the news [youtube] BBCode).
$google = $captcha ? ' https://www.google.com https://www.gstatic.com' : '';
$csp = "default-src 'self'; script-src 'self' 'unsafe-inline'" . $google . "; style-src 'self' 'unsafe-inline'; "
	. "img-src 'self' data: https:; font-src 'self' data:; connect-src 'self'; "
	. "frame-src 'self' https://www.youtube.com https://www.youtube-nocookie.com" . $google . "; "
	. "form-action 'self'; frame-ancestors 'self'; object-src 'none'; base-uri 'self'";
// Mail (README "Mail"): on when CHAOS_SMTP_HOST is set. Wrong settings stop the installer here, so a typo never
// leaves a site that fails on every mail; no host = no mail (the recovery page says it is not available).
$smtpHost = env('CHAOS_SMTP_HOST');
$smtpTls = strtolower(env('CHAOS_SMTP_TLS', 'starttls'));
$smtpPort = (int)env('CHAOS_SMTP_PORT', $smtpTls === 'tls' ? '465' : '587');
$smtpUser = env('CHAOS_SMTP_USER');
$smtpPass = env('CHAOS_SMTP_PASSWORD');
$mailFrom = env('CHAOS_MAIL_FROM');
$mailFromName = env('CHAOS_MAIL_FROM_NAME', 'Cinders of Chaos');
$mailOn = $smtpHost !== '';
if ($mailOn) {
	$mailErrors = array();
	if (preg_match('/^[A-Za-z0-9.-]+$|^\[[0-9A-Fa-f:.]+\]$/', $smtpHost) !== 1) {
		$mailErrors[] = 'CHAOS_SMTP_HOST must be a host name or address.';
	}
	if (!in_array($smtpTls, array('starttls', 'tls', 'none'), true)) {
		$mailErrors[] = 'CHAOS_SMTP_TLS must be starttls (port 587), tls (port 465) or none.';
	}
	if ($smtpTls === 'none' && !in_array(strtolower($smtpHost), array('localhost', '127.0.0.1', '[::1]'), true)) {
		$mailErrors[] = 'CHAOS_SMTP_TLS=none sends the password in clear: only for a relay on this machine (localhost).';
	}
	if ($smtpPort < 1 || $smtpPort > 65535) {
		$mailErrors[] = 'CHAOS_SMTP_PORT must be 1-65535.';
	}
	if (filter_var($mailFrom, FILTER_VALIDATE_EMAIL) === false) {
		$mailErrors[] = 'CHAOS_MAIL_FROM must be an e-mail address (e.g. no-reply@your-domain).';
	}
	if (preg_match('/[\r\n]/', $mailFromName . $smtpUser) === 1) {
		$mailErrors[] = 'CHAOS_MAIL_FROM_NAME and CHAOS_SMTP_USER must be one line.';
	}
	if ($smtpPass !== '' && $smtpUser === '') {
		$mailErrors[] = 'CHAOS_SMTP_PASSWORD is set but CHAOS_SMTP_USER is empty.';
	}
	if ($mailErrors) {
		fwrite(STDERR, "Mail settings:\n  " . implode("\n  ", $mailErrors) . "\nFix them in site.env, or empty CHAOS_SMTP_HOST to run without mail.\n");
		exit(1);
	}
} else {
	fwrite(STDERR, "note: CHAOS_SMTP_HOST is empty: no mail; account recovery by e-mail is off (README \"Mail\").\n");
}
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
	. "\$config['site_title'] = 'Cinders of Chaos';\n"
	. "\$config['site_title_context'] = 'The world was not ended. It was broken, and the pieces still bleed.';\n"
	. "\$config['site_url'] = " . export($siteUrl) . ";\n"
	. "\$config['cache']['memory'] = false; // no APCu needed\n"
	. "\$config['language_selector'] = false; // the site is written in English\n"
	. "// English only: the Void layout shows its flag switcher whenever two languages are enabled (it does not read\n"
	. "// language_selector), and ?lang=pt_br would translate ZnoteX's strings around our English pages\n"
	. "\$config['languages_enabled'] = array('en');\n"
	. "\$config['page_admin_access'] = " . export($admins) . "; // account NAMES with the admin panel\n\n"
	. "// Passwords: salted PBKDF2-SHA256 shared with the game server (engine patch 0014, README \"Passwords\");\n"
	. "// the same number as passwordHashIterations in the server's config.lua\n"
	. "\$config['chaos_password_iterations'] = " . export($iterations) . ";\n"
	. "// Failed website logins: 5 per IP or 10 per account name in 15 minutes lock that IP / name out for 15 minutes\n"
	. "\$config['login_guard'] = " . export(array('enabled' => true, 'threshold' => 5, 'account_threshold' => 10, 'window_minutes' => 15, 'lockout_minutes' => 15)) . ";\n"
	. "// The JSON login service is for 12.x clients; ours (10.98) logs in through the game's login server\n"
	. "\$config['login_web_service'] = false;\n\n"
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
		array('key' => 'windows_client', 'label' => 'Windows client', 'section' => 'client', 'enabled' => true, 'url' => $winUrl, 'image' => '', 'description' => 'The Cinders of Chaos client for Windows 10 and 11 (64-bit).'),
		array('key' => 'linux_client', 'label' => 'Linux client', 'section' => 'client', 'enabled' => true, 'url' => $linuxUrl, 'image' => '', 'description' => 'The Cinders of Chaos client for 64-bit Linux.'),
	)) . ";\n\n"
	. ($sprites
		? "// Outfit and item images drawn from our own client pair (README \"Sprite images\"): chaos_outfit.php and chaos-sprites/\n"
			. "\$config['show_outfits'] = array('shop' => true, 'highscores' => true, 'characterprofile' => true, 'onlinelist' => true, 'imageServer' => '/chaos_outfit.php');\n"
			. "\$config['shop']['imageServer'] = '/chaos-sprites/items';\n"
			. "\$config['shop']['imageType'] = 'png';\n\n"
		: "// No sprite images on this site (CHAOS_SPRITE_PAIR not set, README \"Sprite images\"): outfit images off.\n"
			. "\$config['show_outfits'] = array('shop' => false, 'highscores' => false, 'characterprofile' => false, 'onlinelist' => false, 'imageServer' => '');\n\n")
	. "// Not used on this server (README \"Not used on this server\"): the store is in the game and donations are the Donate\n"
	. "// page, so no website shop, points or house purchase with points; no forum. Their pages lead to plugins/chaos/pages/notused.php.\n"
	. "\$config['shop']['enabled'] = false;\n"
	. "\$config['buypoints_enabled'] = false;\n"
	. "\$config['houseConfig']['shopPoints']['enabled'] = false;\n"
	. "\$config['forum']['enabled'] = false;\n"
	. "\$config['forum']['guildboard'] = false;\n"
	. "// The stock payment callbacks are sent away by the plugin (chaos_unused_pages) or stopped by a patch; a random\n"
	. "// PayGol secret (new on every run) in place of the stock 'xxxx-xxxx-xxxx-xxxx' as defence in depth.\n"
	. "\$config['paygol']['enabled'] = false;\n"
	. "\$config['paygol']['secretKey'] = " . export(bin2hex(random_bytes(32))) . ";\n"
	. "\$config['pagseguro']['enabled'] = false;\n"
	. "\$config['paypal']['enabled'] = false;\n\n"
	. "// Browser security (README \"Web server\"). With an https:// site address the session cookie is Secure and HSTS\n"
	. "// is sent; behind a TLS proxy PHP must still be told the request was HTTPS (fastcgi_param HTTPS on).\n"
	. ($https ? "\$config['session']['cookie_secure'] = true;\n" : '')
	. "\$config['security']['hsts'] = " . export($https) . ";\n"
	. "\$config['security']['content_type_options'] = true;\n"
	. "\$config['security']['referrer_policy'] = 'strict-origin-when-cross-origin';\n"
	. "\$config['security']['content_security_policy'] = " . export($csp) . ";\n\n"
	. "// reCAPTCHA on the account creation form when both keys are set (CHAOS_RECAPTCHA_SITE_KEY / CHAOS_RECAPTCHA_SECRET)\n"
	. "\$config['use_captcha'] = " . export($captcha) . ";\n"
	. ($captcha ? "\$config['captcha_site_key'] = " . export($captchaSite) . ";\n"
		. "\$config['captcha_secret_key'] = " . export($captchaSecret) . ";\n"
		. "\$config['captcha_use_curl'] = false; // ZnoteX's cURL path turns certificate checks off; file_get_contents keeps them\n" : '')
	. "// Mail (README \"Mail\"): ZnoteX's keys, read by the plugin's sender (plugins/chaos/mail_lib.php). Recovery is the\n"
	. "// plugin's one-time link (recovery_lib.php). No activation mail at registration (the game does not check it) and\n"
	. "// no e-mail check on the account page; e-mail login codes of the website 2FA only with mail on.\n"
	. "\$config['mailserver'] = " . export(array(
		'register' => false,
		'accountRecovery' => $mailOn,
		'myaccount_verify_email' => false,
		'verify_email_points' => 0,
		'host' => $mailOn ? $smtpHost : '',
		'securityType' => $smtpTls === 'starttls' ? 'tls' : ($smtpTls === 'tls' ? 'ssl' : ''),
		'port' => $smtpPort,
		'email' => $mailOn ? $mailFrom : '',
		'username' => $mailOn ? $smtpUser : '',
		'password' => $mailOn ? $smtpPass : '',
		'debug' => false,
		'fromName' => $mailFromName,
	)) . ";\n"
	. "\$config['chaos_mail'] = " . export(array('enabled' => $mailOn, 'tls' => $smtpTls, 'timeout' => 15,
		'reset_minutes' => 30, 'per_ip_hour' => 5, 'per_account_hour' => 3)) . ";\n"
	. "\$config['twoFactorV2']['email_otp_enabled'] = " . export($mailOn) . ";\n\n"
	. "// Account creation: at most this many accounts per IP address per hour (plugins/chaos/register_guard.php)\n"
	. "\$config['chaos_register_limit'] = " . export(array('per_ip' => max(0, (int)env('CHAOS_REGISTER_PER_IP_HOUR', '3')), 'window_seconds' => 3600)) . ";\n\n"
	. "// The client's account API (chaos_client_api.php, plugins/chaos/client_api_lib.php): character looks and creation\n"
	. "\$config['chaos_client_api'] = " . export(array('enabled' => env('CHAOS_CLIENT_API', '1') !== '0', 'token_seconds' => 1800,
		'per_ip_minute' => 30, 'create_per_account_hour' => 3, 'create_per_ip_hour' => 5)) . ";\n\n"
	. "// Cinders of Chaos (plugins/chaos)\n"
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
