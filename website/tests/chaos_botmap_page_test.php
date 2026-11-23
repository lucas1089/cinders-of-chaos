<?php
// php website/tests/chaos_botmap_page_test.php : the staff's live bot map (plugins/chaos/botmap_lib.php, pages/botmap.php, chaos_botmap.php; O727) with
// php-cli over an in-memory SQLite database and a temp server data folder: who may see it (an admin panel account with a group 4+ character, nobody
// else, on the page and on the endpoint), the bots read from the folder (live, stale, dropped, a name that is not a tester's, a link, a broken or a big
// file, every field cut to its limits, no key the page does not know), the map pointer checks, the endpoint answers (404 for everyone else, 400, 405),
// the endpoint script run as a request, and the page shell (Leaflet pinned by integrity hash, our two scripts, no data inside the page).
// No ZnoteX, no network. Exit status 0 when every check passes.
ob_start();   // the page sets a response code: no output may have gone out before it
$tmp = sys_get_temp_dir() . '/chaos_botmap_test_' . getmypid();
@mkdir($tmp . '/data/chaos_botlive', 0777, true);
$config = array('chaos' => array('server_data' => $tmp . '/data'), 'page_admin_access' => array('gmacc', 'adminacc', 'tutoracc'));
$GLOBALS['config'] = $config;
require __DIR__ . '/../overlay/plugins/chaos/lib.php';
require __DIR__ . '/../overlay/plugins/chaos/botmap_lib.php';

$failed = 0;
function check(bool $ok, string $what): void {
	global $failed;
	if (!$ok) { $failed++; echo "FAIL: $what\n"; }
}
function rrmdir(string $d): void {
	foreach (@scandir($d) ?: array() as $f) {
		if ($f === '.' || $f === '..') { continue; }
		$p = $d . '/' . $f;
		is_dir($p) && !is_link($p) ? rrmdir($p) : @unlink($p);
	}
	@rmdir($d);
}
register_shutdown_function(static function () use ($tmp) { rrmdir($tmp); });

$pdo = new PDO('sqlite::memory:');
$pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
final class FakeZnoteDb {
	public PDO $pdo;
	public function __construct(PDO $pdo) { $this->pdo = $pdo; }
	private function run(string $sql, array $p): PDOStatement {
		$st = $this->pdo->prepare($sql);
		foreach (array_values($p) as $i => $v) {
			$st->bindValue($i + 1, $v, is_int($v) ? PDO::PARAM_INT : PDO::PARAM_STR);
		}
		$st->execute();
		return $st;
	}
	public function fetchOne(string $sql, array $p = array()) {
		$r = $this->run($sql, $p)->fetch(PDO::FETCH_ASSOC);
		return $r === false ? false : $r;
	}
	public function fetchAll(string $sql, array $p = array()) { return $this->run($sql, $p)->fetchAll(PDO::FETCH_ASSOC); }
	public function execute(string $sql, array $p = array()) { $this->run($sql, $p); return true; }
}
$DB = new FakeZnoteDb($pdo);
function db() { return $GLOBALS['DB']; }
$pdo->exec("CREATE TABLE accounts (id INTEGER PRIMARY KEY, name TEXT NOT NULL)");
$pdo->exec("INSERT INTO accounts (id, name) VALUES (1, 'gmacc'), (2, 'player'), (3, 'adminacc'), (4, 'tutoracc')");
$pdo->exec("CREATE TABLE players (id INTEGER PRIMARY KEY, name TEXT, account_id INT, group_id INT)");
$pdo->exec("INSERT INTO players (id, name, account_id, group_id) VALUES (10, 'Gm Jo', 1, 4), (11, 'Grimtooth', 2, 1), (12, 'Admin Al', 3, 5), (13, 'Tutor Ty', 4, 2)");

$now = 1800000000;
$dir = $tmp . '/data/chaos_botlive';
function bot(string $name, int $t, array $over = array()): array {
	return $over + array('v' => 1, 'name' => $name, 'class' => 'Ranger', 'level' => 120, 'pos' => array(32369, 32241, 7), 'goal' => 'Hunt',
		'goal_since' => $t - 600, 'why' => 'level 120 is inside levels 90-160', 'spot' => 'Cave Rats (levels 90-160)', 'now' => 'hunt ok',
		'plan' => array('Keep hunting', 'Trip to town'), 'log' => array(array($t - 30, 'do: hunt tried'), array($t - 5, 'do: hunt ok')), 't' => $t, 'src' => 'py');
}
function put(string $file, $data): void {
	global $dir;
	file_put_contents($dir . '/' . $file, is_string($data) ? $data : json_encode($data) . "\n");
}
put('tester-abc.json', bot('Tester Abc', $now - 3));
put('tester-bcd.json', bot('Tester Bcd', $now - 300, array('goal' => 'Town trip')));                        // stale
put('tester-cde.json', bot('Tester Cde', $now - 601));                                                      // dropped
put('tester-def.json', bot('Grimtooth', $now - 1));                                                         // a player's name: not a bot
put('tester-efg.json', bot('Tester Efg', $now - 2, array('pos' => array(70000, 5, 7))));                    // a position out of range
put('tester-fgh.json', bot('Tester Fgh', $now - 2, array('password' => 'hunter2', 'account' => 'tstbot0123456789', 'ip' => '10.1.2.3')));   // keys the page must not echo
put('tester-ghi.json', '{broken');                                                                          // broken
put('tester-hij.json', bot('Tester Hij', $now - 2, array('why' => str_repeat('x', 5000), 'plan' => array_fill(0, 30, 'step'), 'level' => 'high',
	'log' => array_map(static function ($i) use ($now) { return array($now - 100 + $i, 'line ' . $i); }, range(0, 99)))));
put('tester-ijk.json', str_repeat(' ', 70000) . json_encode(bot('Tester Ijk', $now - 2)));                  // bigger than 64 KB
put('Bad Name.json', bot('Tester Jkl', $now - 2));                                                          // not a bot file name
put('tester-klm.txt', bot('Tester Klm', $now - 2));                                                         // not json
put('.hidden.json', bot('Tester Lmn', $now - 2));
put('tester-mno.json', bot('Tester Mno', $now - 2, array('why' => "bad\x00text\n<script>alert(1)</script>\x1b[31m", 'now' => "caf\xc3\xa9 \xe2\x80\x94 ok")));
symlink($tmp . '/data/chaos_botlive/tester-abc.json', $dir . '/tester-nop.json');                           // a link: never followed

// ---- the folder
$bots = chaos_botmap_read($dir, $now);
$names = array_map(static function ($b) { return $b['name']; }, $bots);
check($names === array('Tester Abc', 'Tester Bcd', 'Tester Efg', 'Tester Fgh', 'Tester Hij', 'Tester Mno'), 'bots read, sorted by name: ' . implode(',', $names));
$by = array();
foreach ($bots as $b) { $by[$b['name']] = $b; }
check($by['Tester Abc']['state'] === 'live' && $by['Tester Abc']['age'] === 3, 'a fresh bot is live');
check($by['Tester Bcd']['state'] === 'stale' && $by['Tester Bcd']['age'] === 300 && $by['Tester Bcd']['goal'] === 'Town trip', 'a bot with no news for 2 minutes is stale');
check(!isset($by['Tester Cde']), 'a bot with no news for 10 minutes is dropped');
check(!isset($by['Grimtooth']) && !in_array('Tester Jkl', $names, true) && !in_array('Tester Klm', $names, true) && !in_array('Tester Lmn', $names, true), 'a player name, a bad file name, a txt file and a hidden file show nothing');
check(!in_array('Tester Nop', $names, true) && count($bots) === 6, 'a link is not followed');
check($by['Tester Abc']['pos'] === array(32369, 32241, 7) && $by['Tester Abc']['level'] === 120 && $by['Tester Abc']['class'] === 'Ranger', 'fields of a bot');
check($by['Tester Abc']['plan'] === array('Keep hunting', 'Trip to town') && count($by['Tester Abc']['log']) === 2 && $by['Tester Abc']['log'][1] === array($now - 8, 'do: hunt ok'), 'plan and log, newest last');
check($by['Tester Abc']['goal_since'] === $now - 603 && $by['Tester Abc']['src'] === 'py', 'goal since and source');
check($by['Tester Efg']['pos'] === null, 'a position out of range is none, the bot stays');
$wanted = array('name', 'class', 'level', 'pos', 'goal', 'goal_since', 'why', 'spot', 'now', 'plan', 'log', 't', 'age', 'state', 'src');
$keys = array_keys($by['Tester Fgh']);
sort($keys);
$w = $wanted;
sort($w);
check($keys === $w, 'only the known keys: ' . implode(',', $keys));
$json = json_encode($bots);
foreach (array('hunter2', 'tstbot0123456789', '10.1.2.3', 'password', '"account"', '"ip"') as $secret) {
	check(strpos($json, $secret) === false, "nothing of '$secret' in the answer");
}
check($by['Tester Hij']['level'] === 0 && mb_strlen($by['Tester Hij']['why']) === 240 && count($by['Tester Hij']['plan']) === CHAOS_BOTMAP_PLAN_MAX, 'a bad level is 0, why and plan are cut');
check(count($by['Tester Hij']['log']) === CHAOS_BOTMAP_LOG_MAX && $by['Tester Hij']['log'][49][1] === 'line 99' && $by['Tester Hij']['log'][0][1] === 'line 50', 'the last 50 log lines');
check($by['Tester Mno']['why'] === 'bad text <script>alert(1)</script> [31m' && $by['Tester Mno']['now'] === "caf\xc3\xa9 \xe2\x80\x94 ok" && json_encode($by['Tester Mno']) !== false, 'control characters are cleaned, UTF-8 is kept');
check(chaos_botmap_clean_entry(bot('Tester Abc', $now - 3, array('pos' => array(1, 2))), $now)['pos'] === null
	&& chaos_botmap_clean_entry(bot('Tester Abc', $now - 3, array('pos' => array(1, 2, 16))), $now)['pos'] === null
	&& chaos_botmap_clean_entry(bot('Tester Abc', $now - 3, array('pos' => array('1', 2, 7))), $now)['pos'] === null, 'a position out of range or of the wrong type is none');
check(chaos_botmap_clean_entry(bot('Tester Abc', $now - 3, array('t' => 'yesterday')), $now) === null && chaos_botmap_clean_entry('x', $now) === null
	&& chaos_botmap_clean_entry(array('name' => 'Tester Abc'), $now) === null, 'no time or not an object: no bot');
check(chaos_botmap_clean_entry(bot('Tester ABC', $now), $now) === null && chaos_botmap_clean_entry(bot('Tester Ab', $now), $now) === null
	&& chaos_botmap_clean_entry(bot('Tester Abc ', $now), $now) === null, 'the tester name rule');
check(chaos_botmap_read($tmp . '/nothing', $now) === array() && chaos_botmap_read('', $now) === array(), 'a missing folder is no bots');
check(chaos_botmap_age_state($now, $now) === 'live' && chaos_botmap_age_state($now - 120, $now) === 'live' && chaos_botmap_age_state($now - 121, $now) === 'stale'
	&& chaos_botmap_age_state($now - 600, $now) === 'stale' && chaos_botmap_age_state($now - 601, $now) === 'gone' && chaos_botmap_age_state(null, $now) === 'gone', 'the staleness rule: 2 minutes grey, 10 dropped');
check(chaos_botmap_dir() === $tmp . '/data/chaos_botlive', 'the folder is data/chaos_botlive of the server');

// ---- the cap
$big = $tmp . '/many';
mkdir($big);
for ($i = 0; $i < CHAOS_BOTMAP_MAX_BOTS + 20; $i++) {
	$n = 'Tester ' . chr(65 + intdiv($i, 26 * 26) % 26) . chr(97 + intdiv($i, 26) % 26) . chr(97 + $i % 26);
	file_put_contents($big . '/' . strtolower(str_replace(' ', '-', $n)) . '.json', json_encode(bot($n, $now - 1)));
}
check(count(chaos_botmap_read($big, $now)) === CHAOS_BOTMAP_MAX_BOTS, 'at most ' . CHAOS_BOTMAP_MAX_BOTS . ' bots');

// ---- the map pointer
$pointer = array('v' => 1, 'tile' => 256, 'minZoom' => 0, 'maxZoom' => 4, 'cell' => 8, 'origin' => array(31008, 31008), 'span0' => 512, 'bbox' => array(31040, 31040, 33500, 33000),
	'floors' => array(array('z' => 7, 'tiles' => 100, 'bbox' => array(1, 2, 3, 4)), array('z' => 99, 'tiles' => 1), array('z' => 8, 'tiles' => 50)),
	'towns' => array(array('id' => 1, 'name' => 'Cinderhold', 'x' => 32369, 'y' => 32241, 'z' => 7), array('name' => 'No pos'), array('name' => "Evil\n<b>", 'x' => 1, 'y' => 2, 'z' => 7)),
	'built' => 1799999999, 'url' => 'botmap-0123456789abcdef0123456789abcdef', 'estimate_mb' => 12.5);
check(chaos_botmap_pointer() === null, 'no pointer file: no map');
file_put_contents($tmp . '/data/chaos_botmap.json', json_encode($pointer));
$p = chaos_botmap_pointer();
check(is_array($p) && $p['url'] === 'botmap-0123456789abcdef0123456789abcdef' && $p['span0'] === 512 && $p['origin'] === array(31008, 31008) && $p['maxZoom'] === 4, 'pointer read');
check(count($p['floors']) === 2 && $p['floors'][0]['z'] === 7 && $p['floors'][1]['z'] === 8, 'a floor out of 0-15 is dropped');
check(count($p['towns']) === 2 && $p['towns'][0]['name'] === 'Cinderhold' && $p['towns'][1]['name'] === 'Evil <b>', 'towns need a position, names are one clean line');
check(!isset($p['estimate_mb']) && !isset($p['cell']), 'the pointer is cut to the keys the page uses');
foreach (array('../x', '/etc/passwd', 'http://evil.example/x', 'a b', 'a/../b', '') as $bad) {
	file_put_contents($tmp . '/data/chaos_botmap.json', json_encode(array('url' => $bad) + $pointer));
	check(chaos_botmap_pointer() === null, "pointer url '$bad' refused");
}
foreach (array(array('v' => 2), array('span0' => 3), array('origin' => array(1)), array('maxZoom' => 99), array('bbox' => 'x')) as $bad) {
	file_put_contents($tmp . '/data/chaos_botmap.json', json_encode($bad + $pointer));
	check(chaos_botmap_pointer() === null, 'a bad pointer is refused: ' . json_encode(array_keys($bad)));
}
file_put_contents($tmp . '/data/chaos_botmap.json', '{not json');
check(chaos_botmap_pointer() === null, 'a broken pointer is no map');
file_put_contents($tmp . '/data/chaos_botmap.json', json_encode($pointer));

// ---- access
check(chaos_botmap_group($config, 1) === 4 && chaos_botmap_group($config, 3) === 5, 'gamemaster and administrator may see it');
check(chaos_botmap_group($config, 2) === 0 && chaos_botmap_group($config, 4) === 0 && chaos_botmap_group($config, 0) === 0 && chaos_botmap_group($config, 99) === 0, 'a player, a tutor, nobody: no');

// ---- the endpoint (the function the script calls)
[$code, $body] = chaos_botmap_handle($config, 0, array(), $now);
check($code === 404 && $body === array('ok' => false, 'error' => 'not_found'), 'logged out: the answer of a page that does not exist');
[$code, $body] = chaos_botmap_handle($config, 2, array('a' => 'meta'), $now);
check($code === 404 && !isset($body['map']) && !isset($body['bots']), 'a player gets neither bots nor map');
[$code, $body] = chaos_botmap_handle($config, 4, array(), $now);
check($code === 404, 'a tutor (group 2) gets nothing');
[$code, $body] = chaos_botmap_handle($config, 1, array(), $now);
check($code === 200 && $body['ok'] === true && $body['now'] === $now && $body['count'] === 6 && $body['stale'] === 1 && count($body['bots']) === 6, 'staff: the bots');
[$code, $body] = chaos_botmap_handle($config, 3, array('a' => 'meta'), $now);
check($code === 200 && $body['map']['url'] === 'botmap-0123456789abcdef0123456789abcdef' && !isset($body['bots']), 'staff: the map pointer');
[$code, $body] = chaos_botmap_handle($config, 1, array('a' => "meta' OR 1=1"), $now);
check($code === 400 && $body['error'] === 'bad_request', 'an unknown action is a 400');
unlink($tmp . '/data/chaos_botmap.json');
[$code, $body] = chaos_botmap_handle($config, 1, array('a' => 'meta'), $now);
check($code === 200 && $body['map'] === null, 'no map built: map null (the page lists the bots without a map)');
rename($dir, $dir . '.off');
[$code, $body] = chaos_botmap_handle($config, 1, array(), $now);
check($code === 200 && $body['bots'] === array() && $body['count'] === 0, 'no folder: no bots');
rename($dir . '.off', $dir);

// ---- the endpoint script as a request
$site = $tmp . '/site';
mkdir($site . '/engine', 0777, true);
mkdir($site . '/plugins/chaos', 0777, true);
copy(__DIR__ . '/../overlay/chaos_botmap.php', $site . '/chaos_botmap.php');
foreach (array('lib.php', 'botmap_lib.php', 'reports_lib.php') as $f) {
	copy(__DIR__ . '/../overlay/plugins/chaos/' . $f, $site . '/plugins/chaos/' . $f);
}
$harness = $site . '/engine/init.php';
file_put_contents($harness, '<?php
$config = array("chaos" => array("server_data" => ' . var_export($tmp . '/data', true) . '), "page_admin_access" => array("gmacc", "adminacc"));
$GLOBALS["config"] = $config;
require_once __DIR__ . "/../plugins/chaos/lib.php";
$pdo = new PDO("sqlite:" . ' . var_export($tmp . '/site.sqlite', true) . ');
final class FakeZnoteDb2 {
	public function __construct(public PDO $pdo) {}
	public function fetchOne(string $sql, array $p = array()) { $s = $this->pdo->prepare($sql); $s->execute(array_values($p)); $r = $s->fetch(PDO::FETCH_ASSOC); return $r === false ? false : $r; }
}
function db() { static $d = null; return $d ??= new FakeZnoteDb2($GLOBALS["pdo"]); }
function getSession(string $k) { return $k === "user_id" ? (int)getenv("BOTMAP_USER") : null; }
');
$db2 = new PDO('sqlite:' . $tmp . '/site.sqlite');
$db2->exec("CREATE TABLE accounts (id INTEGER PRIMARY KEY, name TEXT NOT NULL); INSERT INTO accounts VALUES (1, 'gmacc'), (2, 'player');
	CREATE TABLE players (id INTEGER PRIMARY KEY, name TEXT, account_id INT, group_id INT); INSERT INTO players VALUES (10, 'Gm Jo', 1, 4), (11, 'Grimtooth', 2, 1);");
function request(string $site, int $user, string $query = '', string $method = 'GET'): array {
	$code = '<?php register_shutdown_function(static function () { fwrite(STDERR, "CODE=" . http_response_code()); }); $_SERVER["REQUEST_METHOD"] = ' . var_export($method, true) . '; parse_str(' . var_export($query, true) . ', $_GET); require ' . var_export($site . '/chaos_botmap.php', true) . ';';
	file_put_contents($site . '/run.php', $code);
	$desc = array(1 => array('pipe', 'w'), 2 => array('pipe', 'w'));
	$proc = proc_open(array(PHP_BINARY, $site . '/run.php'), $desc, $pipes, $site, array('BOTMAP_USER' => (string)$user, 'PATH' => getenv('PATH')));
	$out = stream_get_contents($pipes[1]);
	$err = stream_get_contents($pipes[2]);
	proc_close($proc);
	preg_match('/CODE=(\d+)/', $err, $m);
	return array((int)($m[1] ?? 0), $out);
}
[$c, $o] = request($site, 1);
$d = json_decode($o, true);
check($c === 200 && is_array($d) && $d['ok'] === true && count($d['bots']) >= 4, 'the script answers staff with the bots: ' . substr($o, 0, 80));
[$c, $o] = request($site, 2);
check($c === 404 && $o === '{"ok":false,"error":"not_found"}', 'the script answers a player 404: ' . $o);
[$c, $o] = request($site, 0);
check($c === 404 && strpos($o, 'Tester') === false, 'the script answers a logged out visitor 404');
[$c, $o] = request($site, 1, '', 'POST');
check($c === 405 && strpos($o, 'Tester') === false, 'POST is refused');
check(strpos(file_get_contents(__DIR__ . '/../overlay/chaos_botmap.php'), 'no-store') !== false, 'the answer is never cached');

// ---- the page
$SESSION_USER = 0;
function getSession(string $k) { global $SESSION_USER; return $k === 'user_id' ? $SESSION_USER : null; }
function znote_plugin_asset(string $plugin, string $path): string { return 'plugins/' . $plugin . '/assets/' . $path; }
function render(): string {
	global $config;
	ob_start();
	include __DIR__ . '/../overlay/plugins/chaos/pages/botmap.php';
	return (string)ob_get_clean();
}
foreach (array(0, 2, 4) as $u) {
	$SESSION_USER = $u;
	$html = render();
	check(strpos($html, 'Not found') !== false && strpos($html, 'leaflet') === false && strpos($html, 'chaos-botmap') === false && strpos($html, 'Tester') === false, "user $u: not found, no map, no script");
}
$SESSION_USER = 1;
$html = render();
check(strpos($html, 'id="chaos-botmap"') !== false && strpos($html, 'data-endpoint="chaos_botmap.php"') !== false && strpos($html, 'data-poll="3000"') !== false, 'staff: the page shell, polling every 3 s');
check(strpos($html, 'https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.9.4/leaflet.min.js') !== false && strpos($html, 'https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.9.4/leaflet.min.css') !== false, 'Leaflet 1.9.4 from cdnjs, an exact version');
check(preg_match_all('/integrity="sha512-[A-Za-z0-9+\/=]{86}=="/', $html) === 2 && substr_count($html, 'crossorigin="anonymous"') === 2, 'both Leaflet files carry their integrity hash');
check(strpos($html, 'plugins/chaos/assets/js/chaos-botmap-core.js') !== false && strpos($html, 'plugins/chaos/assets/js/chaos-botmap.js') !== false && strpos($html, 'css/chaos-botmap.css') !== false, 'our scripts and style');
check(strpos($html, 'Tester Abc') === false && strpos($html, 'Cave Rats') === false, 'no bot data inside the page: it comes from the endpoint');
foreach (array('chaos-bm-map', 'chaos-bm-floors', 'chaos-bm-roster', 'chaos-bm-panel', 'chaos-bm-p-name', 'chaos-bm-p-fields', 'chaos-bm-p-plan', 'chaos-bm-p-log', 'chaos-bm-status', 'chaos-bm-follow', 'chaos-bm-nomap', 'chaos-bm-error', 'chaos-bm-empty', 'chaos-bm-p-class', 'chaos-bm-p-state', 'chaos-bm-p-noplan', 'chaos-bm-p-nolog') as $id) {
	check(strpos($html, 'id="' . $id . '"') !== false, "the script's element $id is in the page");
}
check(strpos($html, 'Plan') !== false && strpos($html, 'Last logs') !== false, 'the panel has Plan and Last logs');
// every element the script looks up exists in the page
$js = file_get_contents(__DIR__ . '/../overlay/plugins/chaos/assets/js/chaos-botmap.js');
preg_match_all("/\\$\\('(chaos-bm-[a-z-]+)'\\)/", $js, $m);
foreach (array_unique($m[1]) as $id) {
	check(strpos($html, 'id="' . $id . '"') !== false, "the script reads #$id and the page has it");
}
check(strpos($js, 'innerHTML') === false && strpos($js, 'insertAdjacentHTML') === false && strpos($js, 'document.write') === false, 'the script never puts server text in as HTML');
check(substr_count($js, 'textContent') > 10, 'it uses textContent');

// ---- wiring
$ht = file_get_contents(__DIR__ . '/../overlay/.htaccess');
check(strpos($ht, 'chaos_launcher_feed|chaos_botmap)') !== false, '.htaccess: the endpoint is not redirected to a clean address');
check(strpos(file_get_contents(__DIR__ . '/../setup/router.php'), "'chaos_botmap'") !== false, 'router.php: the same');
check(strpos(file_get_contents(__DIR__ . '/../setup/write_seo_files.php'), 'Disallow: /chaos_botmap.php') !== false
	&& strpos(file_get_contents(__DIR__ . '/../setup/write_seo_files.php'), 'Disallow: /botmap-') !== false, 'robots.txt keeps the endpoint and the tile folder out');
check(strpos(file_get_contents(__DIR__ . '/../setup/chaos_setup.php'), "'page?plugin=chaos&p=botmap'") !== false, 'a staff menu entry');
check(in_array('page_chaos_botmap', chaos_seo_private_pages_for_test(), true), 'the page is private for search engines');
function chaos_seo_private_pages_for_test(): array {
	require_once __DIR__ . '/../overlay/plugins/chaos/seo_lib.php';
	return chaos_seo_private_pages();
}

ob_end_flush();
echo $failed ? "chaos_botmap_page_test: $failed FAILED\n" : "chaos_botmap_page_test: OK\n";
exit($failed ? 1 : 0);
