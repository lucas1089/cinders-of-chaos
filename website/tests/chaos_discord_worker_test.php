<?php
// php website/tests/chaos_discord_worker_test.php : the Discord sender (plugins/chaos/discord_lib.php) against an
// in-memory SQLite database and a MOCK HTTP ENDPOINT: a local `php -S 127.0.0.1:<port>` with a router that answers like
// a Discord webhook (204, 429 with retry_after, 500, the rate limit headers) and logs every request. Nothing leaves
// this machine. Also: the settings from the environment (only Discord webhook URLs), the embed (brand colours, no
// pings, field limits), event switches, channels without a webhook, retries with backoff, failure after the attempts,
// the Character Bazaar scan (first run only notes the log, then new listings and sales), the cleanup, the downloads
// page's Discord step. Exit status 0 when every check passes.
$GLOBALS['config'] = array('chaos' => array('server_data' => __DIR__ . '/../../server/data', 'discord_url' => 'https://discord.gg/abcDEF'));
require __DIR__ . '/../overlay/plugins/chaos/lib.php';
require __DIR__ . '/../overlay/plugins/chaos/discord_lib.php';

$failed = 0;
function check(bool $ok, string $what): void {
	global $failed;
	if (!$ok) {
		$failed++;
		echo "FAIL: $what\n";
	}
}

// ------------------------------------------------------------------ the mock webhook endpoint
$dir = sys_get_temp_dir() . '/chaos_discord_mock_' . getmypid();
@mkdir($dir);
$logFile = $dir . '/requests.log';
$router = $dir . '/router.php';
file_put_contents($router, <<<'PHP'
<?php
// a Discord webhook stand-in: the token's first word picks the answer
$path = parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH);
$body = file_get_contents('php://input');
$dir = __DIR__;
file_put_contents($dir . '/requests.log', json_encode(array('path' => $path, 'method' => $_SERVER['REQUEST_METHOD'],
	'type' => $_SERVER['CONTENT_TYPE'] ?? '', 'body' => $body)) . "\n", FILE_APPEND);
$token = basename($path);
if (strpos($token, 'busy') === 0) {
	$n = (int)@file_get_contents($dir . '/busy.count');
	file_put_contents($dir . '/busy.count', (string)($n + 1));
	if ($n === 0) {
		http_response_code(429);
		header('Content-Type: application/json');
		echo json_encode(array('message' => 'You are being rate limited.', 'retry_after' => 2.5, 'global' => false));
		return;
	}
}
if (strpos($token, 'broken') === 0) {
	http_response_code(500);
	echo 'internal error';
	return;
}
if (strpos($token, 'last') === 0) {
	header('X-RateLimit-Remaining: 0');
	header('X-RateLimit-Reset-After: 3.2');
}
http_response_code(204);
PHP);
$port = 0;
$proc = null;
for ($try = 0; $try < 5 && !$proc; $try++) {
	$candidate = random_int(20000, 45000);
	$p = proc_open(array(PHP_BINARY, '-S', '127.0.0.1:' . $candidate, $router), array(array('pipe', 'r'),
		array('file', $dir . '/server.out', 'a'), array('file', $dir . '/server.out', 'a')), $pipes);
	for ($i = 0; $i < 50; $i++) {
		$s = @fsockopen('127.0.0.1', $candidate, $errno, $errstr, 0.1);
		if ($s) {
			fclose($s);
			$proc = $p;
			$port = $candidate;
			break;
		}
		usleep(100000);
	}
	if (!$proc) {
		proc_terminate($p);
	}
}
check($proc !== null, 'the mock endpoint started');
if (!$proc) {
	exit(1);
}
register_shutdown_function(static function () use ($proc, $dir): void {
	proc_terminate($proc);
	proc_close($proc);
	array_map('unlink', glob($dir . '/*') ?: array());
	@rmdir($dir);
});
$base = 'http://127.0.0.1:' . $port . '/api/webhooks/';
function requests(): array {
	global $logFile;
	$out = array();
	foreach (file_exists($logFile) ? file($logFile, FILE_IGNORE_NEW_LINES) : array() as $line) {
		$out[] = json_decode($line, true);
	}
	return $out;
}

// ------------------------------------------------------------------ settings from the environment
$good = 'https://discord.com/api/webhooks/123456789012345678/' . str_repeat('aB3_-', 12);
check(ChaosDiscordWorker::validHook($good), 'a Discord webhook URL');
check(!ChaosDiscordWorker::validHook('http://discord.com/api/webhooks/123456789012345678/' . str_repeat('a', 60)), 'http refused');
check(!ChaosDiscordWorker::validHook('https://evil.example/api/webhooks/123456789012345678/' . str_repeat('a', 60)), 'another host refused');
check(!ChaosDiscordWorker::validHook($good . "'; rm -rf /"), 'junk after the token refused');
[$hooks, $off, $name, $site] = ChaosDiscordWorker::settingsFromEnv(array(
	'CHAOS_DISCORD_WEBHOOK_RECORDS' => $good, 'CHAOS_DISCORD_WEBHOOK_STATUS' => 'https://example.org/hook',
	'CHAOS_DISCORD_WEBHOOK_DEFAULT' => $good, 'CHAOS_DISCORD_OFF' => 'level, bazaar_list,nonsense',
	'CHAOS_DISCORD_NAME' => 'Cinders', 'CHAOS_SITE_URL' => 'https://www.example.org/'));
check(isset($hooks['records'], $hooks['default']) && !isset($hooks['status']), 'only valid webhooks are taken');
check($off === array('level', 'bazaar_list'), 'off kinds: known ones only');
check($name === 'Cinders' && $site === 'https://www.example.org/', 'name and site');

// ------------------------------------------------------------------ the database
$pdo = new PDO('sqlite::memory:');
$db = new ChaosPayPdo($pdo);
foreach (explode(";\n", file_get_contents(__DIR__ . '/../../server/sql/chaos_discord.sql')) as $stmt) {
	if (preg_match('/CREATE TABLE IF NOT EXISTS `(\w+)` \((.*)\) ENGINE/s', $stmt, $m)) {
		$sql = $m[2];
		$sql = str_replace('`id` int unsigned NOT NULL AUTO_INCREMENT', '`id` INTEGER PRIMARY KEY AUTOINCREMENT', $sql);
		$sql = preg_replace('/, PRIMARY KEY \(`id`\)/', '', $sql);
		$sql = preg_replace('/, KEY `\w+` \([^)]*\)/', '', $sql);
		$pdo->exec("CREATE TABLE `{$m[1]}` ($sql)");
	}
}
$pdo->exec("CREATE TABLE chaos_bazaar_listings (id INTEGER PRIMARY KEY AUTOINCREMENT, player_id INT, seller_account_id INT,
	min_price INT, buyout INT DEFAULT 0, current_bid INT DEFAULT 0, status TEXT DEFAULT 'active', created_at INT, ends_at INT,
	player_name TEXT DEFAULT '', level INT DEFAULT 0, vocation INT DEFAULT 0)");
$pdo->exec("CREATE TABLE chaos_bazaar_log (id INTEGER PRIMARY KEY AUTOINCREMENT, at INT, listing_id INT DEFAULT 0, account_id INT DEFAULT 0,
	player_id INT DEFAULT 0, action TEXT, detail TEXT DEFAULT '')");
$pdo->exec("INSERT INTO chaos_bazaar_listings (player_id, seller_account_id, min_price, buyout, created_at, ends_at, player_name, level, vocation)
	VALUES (7, 3, 500, 0, 1791000000, 1791259200, 'Old Seller', 200, 4)");
$pdo->exec("INSERT INTO chaos_bazaar_log (at, listing_id, action) VALUES (1791000000, 1, 'list')");

$now = 1791100000;
$q = function (string $kind, string $channel, string $title, string $body, string $fields = '[]', int $at = 0) use ($pdo, $now): int {
	$st = $pdo->prepare('INSERT INTO chaos_discord_queue (created_at, kind, channel, title, body, fields) VALUES (?, ?, ?, ?, ?, ?)');
	$st->execute(array($at ?: $now, $kind, $channel, $title, $body, $fields));
	return (int)$pdo->lastInsertId();
};
$row = function (int $id) use ($pdo) {
	return $pdo->query('SELECT * FROM chaos_discord_queue WHERE id = ' . $id)->fetch(PDO::FETCH_ASSOC);
};

// ------------------------------------------------------------------ the embed
$slept = array();
$w = new ChaosDiscordWorker($db, array('records' => $base . '111111/okRecords', 'bosses' => $base . '222222/busyBosses',
	'status' => $base . '333333/brokenStatus', 'players' => $base . '444444/lastPlayers', 'bazaar' => $base . '555555/okBazaar'),
	array('season_end'), 'Cinders of Chaos', 'https://www.example.org', null,
	static function (int $ms) use (&$slept): void { $slept[] = $ms; });
$p = $w->payload(array('kind' => 'worldboss_kill', 'title' => 'Ashmaw slain', 'body' => '@everyone Arwen has slain Ashmaw.',
	'fields' => json_encode(array(array('name' => 'Time', 'value' => '5:12', 'inline' => true), array('bad' => 1))), 'created_at' => 1791000000));
check($p['allowed_mentions'] === array('parse' => array()), 'posts never ping (a name cannot mention @everyone)');
check($p['embeds'][0]['color'] === 0xE03A1E && $p['embeds'][0]['title'] === 'Ashmaw slain', 'embed title and brand colour');
check(count($p['embeds'][0]['fields']) === 1 && $p['embeds'][0]['fields'][0]['inline'] === true, 'fields: malformed ones dropped');
check($p['embeds'][0]['timestamp'] === gmdate('Y-m-d\TH:i:s\Z', 1791000000), 'timestamp of the event');
check(!isset($w->payload(array('kind' => 'x', 'title' => 't', 'body' => 'b', 'fields' => '{}', 'created_at' => 1))['embeds'][0]['fields']), 'no fields: none sent');

// ------------------------------------------------------------------ a run against the mock endpoint
$a = $q('record', 'records', 'New record', 'Ashmaw in 4:12 by Arwen.');
$b = $q('first', 'records', 'Realm first', 'First: Ashmaw.');
$c = $q('worldboss_spawn', 'bosses', 'World boss: Ashmaw', 'Ashmaw stirs.');
$d = $q('worldboss_kill', 'bosses', 'Ashmaw slain', 'Second one, same webhook.');
$e = $q('status_up', 'status', 'Server online', 'Up.');
$f = $q('season_end', 'announce', 'Season over', 'Off in this test.');
$g = $q('level', 'nochannel', 'Level 500', 'No webhook for this channel.');
$h = $q('level', 'players', 'Level 500', 'Arwen reached level 500.');
$i = $q('level', 'players', 'Level 1000', 'Bram reached level 1000.');
$s = $w->run($now);
$req = requests();
check($s['sent'] === 3, 'sent: two records and one level (' . json_encode($s) . ')');
check($s['queued'] === 0, 'the first bazaar scan only notes the log');
check($row($a)['status'] === 'sent' && (int)$row($a)['sent_at'] === $now && $row($b)['status'] === 'sent', 'records sent');
check(count($slept) >= 1 && max($slept) <= 600, 'posts to one webhook are spaced');
check($row($c)['status'] === 'new' && (int)$row($c)['next_at'] === $now + 3 && $row($c)['error'] === 'rate limited', '429: retry after retry_after (2.5 s rounded up)');
check($row($d)['status'] === 'new' && (int)$row($d)['next_at'] === $now + 3, 'the same webhook waits too, without a request');
check($row($e)['status'] === 'new' && (int)$row($e)['attempts'] === 1 && (int)$row($e)['next_at'] === $now + 60 && strpos($row($e)['error'], 'HTTP 500') === 0, '500: retried later');
check($row($f)['status'] === 'off', 'an event switched off is not posted');
check($row($g)['status'] === 'nohook', 'no webhook for its channel');
check($row($h)['status'] === 'sent' && $row($i)['status'] === 'new' && (int)$row($i)['next_at'] === $now + 4, 'X-RateLimit-Remaining 0: the next waits for the reset');
$paths = array_column($req, 'path');
check(count(array_keys($paths, '/api/webhooks/222222/busyBosses')) === 1, 'one request to the limited webhook');
check(!in_array('/api/webhooks/0/none', $paths, true), 'nothing else was called');
$first = json_decode($req[0]['body'], true);
check($req[0]['method'] === 'POST' && strpos($req[0]['type'], 'application/json') === 0, 'a JSON POST');
check($first['embeds'][0]['description'] === 'Ashmaw in 4:12 by Arwen.' && $first['username'] === 'Cinders of Chaos', 'the posted embed');

// later: the 429 and the reset are over, the 500 comes back again until it fails
$s = $w->run($now + 5);
check($row($c)['status'] === 'sent' && $row($d)['status'] === 'sent' && $row($i)['status'] === 'sent', 'after the waits: sent');
check($row($e)['status'] === 'new', 'the 500 is not due yet');
for ($k = 1; $k <= 6; $k++) {
	$w->run($now + 100000 * $k);
}
check($row($e)['status'] === 'failed' && (int)$row($e)['attempts'] === 5, 'failed after five attempts');

// ------------------------------------------------------------------ the bazaar
$pdo->exec("INSERT INTO chaos_bazaar_listings (player_id, seller_account_id, min_price, buyout, created_at, ends_at, player_name, level, vocation)
	VALUES (8, 4, 1200, 5000, 1791100000, 1791359200, 'Arwen', 512, 8)");
$pdo->exec("INSERT INTO chaos_bazaar_log (at, listing_id, action) VALUES (1791100000, 2, 'list'), (1791100001, 2, 'bid'),
	(1791100002, 1, 'sold')");
$pdo->exec("UPDATE chaos_bazaar_listings SET current_bid = 900, status = 'sold' WHERE id = 1");
$before = count(requests());
$s = $w->run($now + 900000);
check($s['queued'] === 2, 'a new listing and a sale queued (the bid is not posted)');
$posted = array_slice(requests(), $before);
$bodies = array_map(static function ($r) { return json_decode($r['body'], true)['embeds'][0]; }, $posted);
$texts = implode("\n", array_column($bodies, 'description'));
check(strpos($texts, 'Arwen, level 512 Juggernaut is up for auction.') !== false, 'listing text with the class name');
check(strpos($texts, 'Old Seller, level 200 Warrior was sold.') !== false, 'sale text');
check(strpos($texts, 'https://www.example.org/page.php?plugin=chaos&p=bazaar') !== false, 'a link to the bazaar');
check(count(array_filter($posted, static function ($r) { return $r['path'] === '/api/webhooks/555555/okBazaar'; })) === 2, 'to the bazaar webhook');
$s = $w->run($now + 900100);
check($s['queued'] === 0, 'the cursor moved: nothing twice');

// a kind switched off by CHAOS_DISCORD_OFF is not even queued from the bazaar
$w2 = new ChaosDiscordWorker($db, array('default' => $base . '666666/okDefault'), array('bazaar_list'), '', '', null,
	static function (int $ms): void {});
$pdo->exec("INSERT INTO chaos_bazaar_log (at, listing_id, action) VALUES (1791200000, 2, 'list')");
$s = $w2->run($now + 900200);
check($s['queued'] === 0, 'bazaar_list off: nothing queued');
$id = $q('first', 'records', 'x', 'y', '[]', $now + 900200);
$s = $w2->run($now + 900300);
check($row($id)['status'] === 'sent', 'the default webhook takes channels without their own');

// cleanup: sent rows after 14 days, failed and nohook after 28
$w2->run($now + 20 * 86400);
check($row($a) === false || $row($a) === array(), 'old sent rows are deleted');
check(is_array($row($e)) && $row($e)['status'] === 'failed', 'a failed row stays a while longer');
$w2->run($now + 40 * 86400);
check($pdo->query('SELECT COUNT(*) FROM chaos_discord_queue WHERE created_at <= ' . ($now + 900200))->fetchColumn() == 0, 'everything old is gone');

// a missing bazaar table only skips the scan
$pdo->exec('DROP TABLE chaos_bazaar_log');
$w3 = new ChaosDiscordWorker($db, array('default' => $base . '666666/okDefault'), array(), '', '', null, static function (int $ms): void {});
$s = $w3->run($now + 41 * 86400);
check(strpos(implode(' ', $w3->log), 'bazaar scan skipped') !== false, 'no bazaar: the scan is skipped, the run goes on');

// ------------------------------------------------------------------ the downloads page shows the Discord invite
function znote_download_entries(): array { return array(); }
ob_start();
include __DIR__ . '/../overlay/layouts/chaos/views/downloads.php';
$html = (string)ob_get_clean();
check(strpos($html, 'href="https://discord.gg/abcDEF"') !== false, 'downloads: the Discord invite when configured');
$GLOBALS['config']['chaos']['discord_url'] = '';
ob_start();
include __DIR__ . '/../overlay/layouts/chaos/views/downloads.php';
$html = (string)ob_get_clean();
check(strpos($html, 'discord') === false, 'downloads: no Discord step without an invite');
$GLOBALS['config']['chaos']['discord_url'] = 'javascript:alert(1)';
ob_start();
include __DIR__ . '/../overlay/layouts/chaos/views/downloads.php';
$html = (string)ob_get_clean();
check(strpos($html, 'javascript:') === false, 'downloads: only an https invite is linked');

if ($failed > 0) {
	echo "$failed check(s) failed\n";
	exit(1);
}
echo "chaos_discord_worker_test: all checks passed\n";
