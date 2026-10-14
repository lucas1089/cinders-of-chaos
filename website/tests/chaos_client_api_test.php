<?php
// php website/tests/chaos_client_api_test.php : the client's account API (chaos_client_api.php,
// plugins/chaos/client_api_lib.php) and the character creation code it shares with the website form
// (engine/function/chaos_character.php, patches/znotex-chaos-character-create.patch). Login (wrong password, unknown
// account, the login guard's lock, replays), the state (looks, class lock, slots, season, terms), creation and its
// refusals (bad name, taken name, locked class, too many characters, bad token, Terms, season mode, the hourly limits,
// the per-minute flood limit, a password change ending the token) and the class look of new characters.
// php-cli with pdo_sqlite; ZnoteX's functions are small stand-ins with ZnoteX's behaviour (no ZnoteX checkout).
$repo = realpath(__DIR__ . '/../..');
$data = sys_get_temp_dir() . '/chaos_client_api_test_' . getmypid();
@mkdir($data . '/XML', 0700, true);
@symlink($repo . '/server/data/scripts', $data . '/scripts');
file_put_contents($data . '/XML/shaders.xml', "<?xml version=\"1.0\"?>\n<shaders>\n    <shader id=\"1\" name=\"ember_glow\" premium=\"no\" />\n</shaders>\n");

$config = array(
	'chaos' => array('server_data' => $data),
	'site_url' => 'https://www.example.org',
	'minL' => 3, 'maxL' => 20, 'maxW' => 3,
	'invalidNameTags' => array('god', 'gm', 'admin'),
	'creatureNameTags' => array('dragon', 'rat'),
	'available_vocations' => array(4, 3, 1, 11),
	'available_towns' => array(2),
	'max_characters' => 5,
	'validate_IP' => true,
	'log_ip' => false,
	'vocations' => array(1 => array('name' => 'Mystic'), 3 => array('name' => 'Ranger'), 4 => array('name' => 'Warrior'),
		11 => array('name' => 'Thief'), 17 => array('name' => 'Monk'), 20 => array('name' => 'Necromancer'), 23 => array('name' => 'Templar')),
	'towns' => array(2 => 'Ashfall'),
	'mailserver' => array('register' => false),
	'chaos_client_api' => array('per_ip_minute' => 1000),
	'chaos_password_iterations' => 1000,
);
$GLOBALS['config'] = $config;

$pdo = new PDO('sqlite::memory:');
$pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
final class ChaosApiFakeDb {
	public PDO $pdo;
	public function __construct(PDO $pdo) { $this->pdo = $pdo; }
	private function run(string $sql, array $p): PDOStatement {
		// MariaDB's LIKE escapes with a backslash by default; SQLite needs ESCAPE for that (chaos_seasons' overrides)
		$sql = str_replace("LIKE 'chaos\\_season\\_%'", "LIKE 'chaos\\_season\\_%' ESCAPE '\\'", $sql);
		$st = $this->pdo->prepare($sql);
		foreach (array_values($p) as $i => $v) {
			$st->bindValue($i + 1, $v, is_int($v) ? PDO::PARAM_INT : PDO::PARAM_STR);
		}
		$st->execute();
		return $st;
	}
	public function fetchOne(string $sql, array $p = array()) {
		if (strpos($sql, 'information_schema') !== false) { return array('n' => 1); }
		$r = $this->run($sql, $p)->fetch(PDO::FETCH_ASSOC);
		return $r === false ? false : $r;
	}
	public function fetchAll(string $sql, array $p = array()) { return $this->run($sql, $p)->fetchAll(PDO::FETCH_ASSOC); }
	public function execute(string $sql, array $p = array()) { $this->run($sql, $p); return true; }
}
$DB = new ChaosApiFakeDb($pdo);
function db() { return $GLOBALS['DB']; }
foreach (array(
	'CREATE TABLE accounts (id INTEGER PRIMARY KEY, name TEXT NOT NULL, password TEXT NOT NULL, type INT NOT NULL DEFAULT 1, premium_ends_at INT NOT NULL DEFAULT 0, email TEXT NOT NULL DEFAULT \'\')',
	'CREATE TABLE players (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL UNIQUE, account_id INT NOT NULL, level INT NOT NULL DEFAULT 1, vocation INT NOT NULL DEFAULT 0, sex INT NOT NULL DEFAULT 1, town_id INT NOT NULL DEFAULT 1, looktype INT NOT NULL DEFAULT 136, lookhead INT NOT NULL DEFAULT 0, lookbody INT NOT NULL DEFAULT 0, looklegs INT NOT NULL DEFAULT 0, lookfeet INT NOT NULL DEFAULT 0, lookaddons INT NOT NULL DEFAULT 0, lastlogin INT NOT NULL DEFAULT 0, deletion INT NOT NULL DEFAULT 0, wings_id INT NOT NULL DEFAULT 0, aura_id INT NOT NULL DEFAULT 0, shader_id INT NOT NULL DEFAULT 0)',
	'CREATE TABLE chaos_class_unlocks (account_id INT NOT NULL, class_key TEXT NOT NULL, source TEXT NOT NULL DEFAULT \'\', created INT NOT NULL DEFAULT 0)',
	'CREATE TABLE chaos_account_extras (account_id INT NOT NULL, extra_key TEXT NOT NULL, amount INT NOT NULL DEFAULT 0)',
	'CREATE TABLE chaos_legal_acceptance (id INTEGER PRIMARY KEY AUTOINCREMENT, account_id INT NOT NULL, version TEXT NOT NULL, accepted_at INT NOT NULL)',
	'CREATE TABLE server_config (config TEXT PRIMARY KEY, value TEXT NOT NULL)',
	'CREATE TABLE chaos_season_players (player_id INT PRIMARY KEY, account_id INT NOT NULL, season INT NOT NULL, joined_at INT NOT NULL, migrated_at INT NOT NULL DEFAULT 0)',
	'CREATE TABLE chaos_season_requests (player_id INT PRIMARY KEY, season INT NOT NULL, mode TEXT NOT NULL, requested_at INT NOT NULL)',
	'CREATE TABLE chaos_client_tokens (token_hash TEXT PRIMARY KEY, account_id INT NOT NULL, pass_mark TEXT NOT NULL, ip TEXT NOT NULL, created INT NOT NULL, expires INT NOT NULL)',
	'CREATE TABLE chaos_client_api_log (id INTEGER PRIMARY KEY AUTOINCREMENT, ip TEXT NOT NULL, account_id INT NOT NULL DEFAULT 0, action TEXT NOT NULL, ok INT NOT NULL DEFAULT 0, created INT NOT NULL)',
	'CREATE TABLE chaos_client_nonces (nonce TEXT PRIMARY KEY, created INT NOT NULL)',
	'CREATE TABLE znote_login_attempts (id INTEGER PRIMARY KEY AUTOINCREMENT, ip TEXT NOT NULL, username TEXT NOT NULL, success INT NOT NULL, created_at INT NOT NULL)',
) as $sql) {
	$pdo->exec($sql);
}

// ---------------------------------------------------------------- ZnoteX stand-ins (ZnoteX 2.0.5 behaviour)
function getSession(string $k) { return null; }
function config($k) { return $GLOBALS['config'][$k] ?? null; }
function t(string $key, array $vars = array()): string { return $key . ($vars ? ':' . implode(',', $vars) : ''); }
final class Token { public static function isValid($t): bool { return $t === 'form-token'; } }
function validate_name($string) { return (str_word_count(trim($string)) > (config('maxW') ?? 3)) ? false : trim($string); }
function user_character_exist($name) { $r = db()->fetchOne('SELECT `id` FROM `players` WHERE `name` = ?;', [$name]); return $r !== false ? $r['id'] : false; }
function vocation_id_to_name($id) { $v = config('vocations'); return isset($v[$id]['name']) ? $v[$id]['name'] : "{$id} - Unknown"; }
function town_id_to_name($id) { $t = config('towns'); return array_key_exists($id, $t) ? $t[$id] : 'Missing Town'; }
function gender_exist($g) { return $g >= 0 && $g <= 1; }
function user_character_list_count($accountId) { $r = db()->fetchOne('SELECT COUNT(`id`) AS `id` FROM `players` WHERE `account_id` = ?', [$accountId]); return $r !== false ? $r['id'] : 0; }
function is_admin($userData) { return false; }
function getIP() { return $_SERVER['REMOTE_ADDR'] ?? ''; }
function validate_ip($ip) { return filter_var($ip, FILTER_VALIDATE_IP) !== false; }
function getIPLong() { return 0; }
function format_character_name($name) { return ucwords(strtolower($name)); }
function znote_visitor_insert_detailed_data($n) {}
function user_create_character($d) {
	db()->execute('INSERT INTO `players` (`name`, `account_id`, `vocation`, `town_id`, `sex`, `looktype`, `lookhead`, `lookbody`, `looklegs`, `lookfeet`) VALUES (?, ?, ?, ?, ?, ?, 78, 68, 58, 76);',
		[$d['name'], (int)$d['account_id'], (int)$d['vocation'], (int)$d['town_id'], (int)$d['sex'], (int)$d['sex'] === 1 ? 128 : 136]);
}
$HOOKS = array();
function znote_hook_register(string $name, callable $fn): void { $GLOBALS['HOOKS'][$name][] = $fn; }
function znote_hook(string $name, array $data): void { foreach ($GLOBALS['HOOKS'][$name] ?? array() as $fn) { $fn($data); } }
function user_exist($name) { return db()->fetchOne('SELECT `id` FROM `accounts` WHERE `name` = ?;', [(string)$name]) !== false; }
function user_data($id) { $r = db()->fetchOne('SELECT * FROM `accounts` WHERE `id` = ?;', [(int)$id]); return $r === false ? array() : $r; }
final class FakeAdapter {
	public function login(string $u, string $p) {
		$r = db()->fetchOne('SELECT `id`, `password` FROM `accounts` WHERE `name` = ?;', [$u]);
		return ($r !== false && chaos_password_verify($p, (string)$r['password'])) ? (int)$r['id'] : false;
	}
}
function znote_server_adapter() { return new FakeAdapter(); }
// the login guard (engine/function/login_guard.php with patches/znotex-chaos-passwords.patch): 5 per IP, 10 per name
function znote_login_guard_ip(): string { return (string)($_SERVER['REMOTE_ADDR'] ?? ''); }
function znote_login_guard_record(string $ip, string $username, bool $success): void {
	db()->execute('INSERT INTO `znote_login_attempts` (`ip`, `username`, `success`, `created_at`) VALUES (?, ?, ?, ?);', [$ip, $username, $success ? 1 : 0, time()]);
}
function znote_login_guard_lockout_remaining(string $ip): int {
	$r = db()->fetchOne('SELECT COUNT(*) AS `f`, MAX(`created_at`) AS `l` FROM `znote_login_attempts` WHERE `ip` = ? AND `success` = 0 AND `created_at` >= ?;', [$ip, time() - 900]);
	return (int)$r['f'] < 5 ? 0 : max(0, (int)$r['l'] + 900 - time());
}
function znote_login_guard_account_lockout_remaining(string $u): int {
	$r = db()->fetchOne('SELECT COUNT(*) AS `f`, MAX(`created_at`) AS `l` FROM `znote_login_attempts` WHERE `username` = ? AND `success` = 0 AND `created_at` >= ?;', [$u, time() - 900]);
	return (int)$r['f'] < 10 ? 0 : max(0, (int)$r['l'] + 900 - time());
}

require $repo . '/website/overlay/engine/function/chaos_password.php';
require $repo . '/website/overlay/plugins/chaos/plugin.php';
require $repo . '/website/overlay/engine/function/chaos_character.php';
require $repo . '/website/overlay/plugins/chaos/client_api_lib.php';

$failed = 0;
$checks = 0;
function check(bool $ok, string $what): void {
	global $failed, $checks;
	$checks++;
	if (!$ok) {
		$failed++;
		echo "FAIL: $what\n";
	}
}
function nonce(): string { return bin2hex(random_bytes(16)); }
$IP = '203.0.113.7';
$_SERVER['REMOTE_ADDR'] = $IP;
function api(array $req, ?string $ip = null): array { return chaos_client_api_handle($req, $ip ?? $GLOBALS['IP'], time()); }

$now = time();
$pdo->exec("INSERT INTO accounts (id, name, password) VALUES (7, 'ashwalker', '" . chaos_password_hash('right horse', 1000) . "'), (8, 'newbie', '" . chaos_password_hash('pw newbie', 1000) . "')");
chaos_legal_insert(7, $now);
$pdo->exec("INSERT INTO players (name, account_id, level, vocation, sex, looktype, lookhead, lookbody, looklegs, lookfeet, lookaddons, lastlogin, wings_id, aura_id, shader_id) VALUES ('Old Guard', 7, 312, 8, 1, 2161, 94, 77, 79, 114, 3, " . ($now - 3600) . ", 937, 932, 1)");
// a season running now (the /season start override of server_config, as the game writes it)
$pdo->exec("INSERT INTO server_config (config, value) VALUES ('chaos_season_1_start', '" . ($now - 86400) . "'), ('chaos_season_1_end', '" . ($now + 86400 * 30) . "')");

// ---------------------------------------------------------------- the patch moves the form's code unchanged
$patch = (string)file_get_contents($repo . '/website/patches/znotex-chaos-character-create.patch');
$fn = (string)file_get_contents($repo . '/website/overlay/engine/function/chaos_character.php');
$norm = static function (string $line): string {
	$line = str_replace(array('$_POST', '$session_user_id', '$user_data'), array('$post', '$accountId', '$userData'), trim($line));
	return preg_replace('/\$post\[\'(\w+)\'\](?! =)/', '$post[\'$1\']', $line);
};
$fnLines = array_map($norm, explode("\n", $fn));
$moved = 0;
$missing = array();
foreach (explode("\n", $patch) as $line) {
	if (strpos($line, '-') !== 0 || strpos($line, '---') === 0 || trim(substr($line, 1)) === '') {
		continue;
	}
	$want = $norm(substr($line, 1));
	$found = in_array($want, $fnLines, true);
	if (!$found) {
		// a defaulted read of the same field (?? null / ?? 0 / (string)) counts as the same line
		$loose = preg_replace('/\s+/', '', preg_replace('/\$post\[\'(\w+)\'\]/', 'P', $want));
		foreach ($fnLines as $have) {
			$h = preg_replace('/\s+/', '', preg_replace(array('/\(string\)\(\$post\[\'(\w+)\'\] \?\? \'\'\)/', '/\(\$post\[\'(\w+)\'\] \?\? [^)]*\)/', '/\$post\[\'(\w+)\'\] \?\? [-0-9a-z]+/', '/\$post\[\'(\w+)\'\]/'), array('P', 'P', 'P', 'P'), $have));
			$h = str_replace(array('$checkToken&&', '(P)', '((int)P)'), array('', 'P', '(int)P'), $h);
			if ($h === str_replace(array('(P)', '((int)P)'), array('P', '(int)P'), $loose)) {
				$found = true;
				break;
			}
		}
	}
	$moved++;
	if (!$found) {
		$missing[] = $want;
	}
}
check($moved > 60 && !$missing, 'every line the patch takes out of createcharacter.php is in chaos_character.php: ' . implode(' | ', array_slice($missing, 0, 4)));
check(strpos($patch, 'chaos_character_form_errors($_POST, (int)$session_user_id, (array)$user_data)') !== false, 'the page calls the shared checks');
check(strpos($patch, 'chaos_character_create($_POST, (int)$session_user_id)') !== false, 'the page calls the shared creation');

// ---------------------------------------------------------------- the website form still works through the functions
$form = array('name' => '  Ember Child ', 'selected_vocation' => '4', 'selected_town' => '2', 'selected_gender' => '1', 'token' => 'form-token');
check(chaos_character_form_errors($form, 7, array(), true) === array() && $form['name'] === 'Ember Child', 'form: valid, name trimmed in place');
$bad = $form; $bad['token'] = 'x';
check(chaos_character_form_errors($bad, 7, array(), true) === array('login.token_invalid'), 'form: the page token is checked');
check(chaos_character_form_errors($bad, 7, array(), false) === array(), 'API: no page token');

// ---------------------------------------------------------------- login
[$code, $body] = api(array('action' => 'login', 'account' => 'ashwalker', 'password' => 'wrong', 'nonce' => nonce()));
check($code === 401 && $body['error'] === 'auth', 'wrong password: 401');
[$code2, $body2] = api(array('action' => 'login', 'account' => 'nosuchone', 'password' => 'wrong', 'nonce' => nonce()));
check($code2 === 401 && $body2['message'] === $body['message'], 'unknown account: the same answer as a wrong password');
[$code, $body] = api(array('action' => 'login', 'account' => 'ashwalker', 'password' => 'right horse'));
check($code === 409 && $body['error'] === 'replay', 'login without a nonce: refused');
$n = nonce();
[$code, $body] = api(array('action' => 'login', 'account' => 'ashwalker', 'password' => 'right horse', 'nonce' => $n));
check($code === 200 && $body['ok'] && preg_match('/^[0-9a-f]{64}$/', $body['token']), 'login: a token');
$token = $body['token'];
check(!is_array($pdo->query("SELECT * FROM chaos_client_tokens WHERE token_hash = '$token'")->fetch()), 'only the hash of the token is stored');
[$code, $b] = api(array('action' => 'login', 'account' => 'ashwalker', 'password' => 'right horse', 'nonce' => $n));
check($code === 409 && $b['error'] === 'replay', 'the same login body again: replay refused');

// the state
$acc = $body['account'];
$look = $body['looks']['Old Guard'] ?? array();
check(($look['type'] ?? 0) === 2161 && $look['addons'] === 3 && $look['head'] === 94 && $look['wings'] === 937 && $look['aura'] === 932, 'looks: outfit, colours, addons, wings, aura');
check($look['shader'] === 'ember_glow' && $look['level'] === 312 && $look['vocation'] === 8 && $look['lastLogin'] === $now - 3600, 'looks: shader name, level, class, last login');
$locked = array();
foreach ($acc['classes'] as $c) { $locked[$c['id']] = $c['locked']; }
check($acc['classes'][0]['male'] === 2073 && $acc['classes'][0]['female'] === 2074, 'classes: the look a new character of the class wears');
check($locked[4] === false && $locked[20] === true && $locked[17] === true && $locked[23] === true && count($locked) === 7, 'classes: the three locked lines locked');
check($acc['slots'] === array('used' => 1, 'limit' => 5) && $acc['terms'] === true, 'slots and terms');
check(is_array($acc['season']) && $acc['season']['id'] === 1 && count($acc['season']['modes']) === 4 && $acc['season']['modes'][2]['hc'] === true, 'the running season and its modes');
check(str_ends_with($acc['season']['modes'][1]['warning'], 'and the Self-Found ladder.'), 'a mode warning written as Lua string pieces comes whole: ' . $acc['season']['modes'][1]['warning']);
check($acc['rules'] === array('minL' => 3, 'maxL' => 20, 'maxW' => 3), 'name rules');

// ---------------------------------------------------------------- create: refusals
function create(array $fields, ?string $tok = null): array {
	return api($fields + array('action' => 'create', 'token' => $tok ?? $GLOBALS['token'], 'nonce' => nonce(), 'sex' => 1, 'vocation' => 4));
}
[$code, $b] = create(array('name' => 'X'));
check($code === 400 && in_array('acc.name_length:3,20', $b['errors'], true) && in_array('reg.words_too_short', $b['errors'], true), 'bad name: too short');
[$code, $b] = create(array('name' => 'Ash3n'));
check($code === 400 && in_array('acc.name_letters', $b['errors'], true), 'bad name: digits');
[$code, $b] = create(array('name' => 'One Two Three Four'));
check($code === 400 && $b['errors'] === array('acc.name_max_words'), 'bad name: too many words');
[$code, $b] = create(array('name' => 'Gm Ash'));
check($code === 400 && in_array('reg.restricted_word', $b['errors'], true), 'bad name: restricted word');
[$code, $b] = create(array('name' => 'Old Guard'));
check($code === 400 && in_array('acc.name_taken', $b['errors'], true), 'taken name');
[$code, $b] = create(array('name' => 'Bone Weaver', 'vocation' => 20));
check($code === 400 && $b['errors'] === array('The Necromancer is locked for your account. Unlock it in the game store (Classes).'), 'locked class: a clear refusal');
[$code, $b] = create(array('name' => 'Bone Weaver', 'vocation' => 21));
check($code === 400 && in_array('createchar.bad_vocation', $b['errors'], true), 'an ascension cannot be created');
[$code, $b] = create(array('name' => 'Neutral One', 'sex' => 5));
check($code === 400 && in_array('createchar.bad_gender', $b['errors'], true), 'bad sex');
[$code, $b] = create(array('name' => 'Season Hopper', 'season' => 1, 'mode' => 'hc'));
check($code === 400 && $b['errors'] === array('Hardcore has one life: tick "I understand" to choose it.'), 'hardcore needs the confirmation');
[$code, $b] = create(array('name' => 'Season Hopper', 'season' => 2));
check($code === 400 && strpos($b['message'], 'not running') !== false, 'a season that is not running');
[$code, $b] = create(array('name' => 'Season Hopper', 'season' => 1, 'mode' => 'turbo'));
check($code === 400 && $b['errors'] === array('Unknown season mode.'), 'unknown mode');
[$code, $b] = create(array('name' => 'Bad Token'), str_repeat('ab', 32));
check($code === 401 && $b['error'] === 'token', 'bad token: 401');
[$code, $b] = create(array('name' => 'Bad Token'), 'not a token');
check($code === 401, 'malformed token: 401');
check((int)$pdo->query("SELECT COUNT(*) FROM players")->fetchColumn() === 1, 'nothing created by a refusal');

// ---------------------------------------------------------------- create: success
$pdo->exec("INSERT INTO chaos_class_unlocks (account_id, class_key) VALUES (7, 'necromancer')");
[$code, $b] = create(array('name' => 'bone weaver', 'vocation' => 20, 'sex' => 0));
check($code === 200 && $b['ok'] && $b['name'] === 'Bone Weaver', 'unlocked class: created, name formatted');
$row = $pdo->query("SELECT * FROM players WHERE name = 'Bone Weaver'")->fetch(PDO::FETCH_ASSOC);
check((int)$row['looktype'] === 2184 && (int)$row['lookaddons'] === 3 && (int)$row['lookhead'] === 78, 'class look of a female Necromancer (pair 20), both addons, starter colours');
check(($b['look']['type'] ?? 0) === 2184, 'the answer carries the new look');
[$code, $b] = create(array('name' => 'Ash Runner', 'vocation' => 11, 'season' => 1, 'mode' => 'hcssf', 'hardcore' => true));
check($code === 200 && strpos($b['message'], 'season') !== false, 'created with a season join');
$req = $pdo->query("SELECT r.season, r.mode FROM chaos_season_requests r JOIN players p ON p.id = r.player_id WHERE p.name = 'Ash Runner'")->fetch(PDO::FETCH_ASSOC);
check(is_array($req) && (int)$req['season'] === 1 && $req['mode'] === 'hcssf', 'the season request row');
[$code, $st] = api(array('action' => 'state', 'token' => $token));
check($code === 200 && $st['looks']['Ash Runner']['season'] === '[S1]' && (int)$st['looks']['Ash Runner']['type'] === 2175, 'state after creation: the season tag and the Thief look');

// a replayed create
$n = nonce();
[$code] = api(array('action' => 'create', 'token' => $token, 'nonce' => $n, 'name' => 'Copy One', 'vocation' => 4, 'sex' => 1));
[$code2, $b] = api(array('action' => 'create', 'token' => $token, 'nonce' => $n, 'name' => 'Copy One', 'vocation' => 4, 'sex' => 1));
check($code === 200 && $code2 === 409 && $b['error'] === 'replay', 'a replayed create is refused');

// too many characters: 5 of 5 used (Old Guard, Bone Weaver, Ash Runner, Copy One, Fifth Wheel)
$pdo->exec('UPDATE chaos_client_api_log SET created = created - 7200');
$pdo->exec("INSERT INTO players (name, account_id, vocation) VALUES ('Fifth Wheel', 7, 4)");
[$code, $b] = create(array('name' => 'Sixth Sense'));
check($code === 400 && in_array('createchar.max_chars:5', $b['errors'], true), 'too many characters');
$pdo->exec("INSERT INTO chaos_account_extras (account_id, extra_key, amount) VALUES (7, 'charSlots', 5)");
[$code, $b] = create(array('name' => 'Sixth Sense'));
check($code === 200, 'a bought Character Slot: created');
[$c7] = create(array('name' => 'Seventh Seal'));
[$c8] = create(array('name' => 'Eighth Wonder'));
[$c9, $b] = create(array('name' => 'Ninth Gate'));
check($c7 === 200 && $c8 === 200 && $c9 === 429 && $b['error'] === 'limit', 'three new characters this hour: the hourly limit per account');
$pdo->exec('UPDATE chaos_client_api_log SET created = created - 7200');
[$code] = create(array('name' => 'Ninth Gate'));
check($code === 200, 'an hour later: allowed again');

// ---------------------------------------------------------------- Terms, password change, logout
[$code, $b] = api(array('action' => 'login', 'account' => 'newbie', 'password' => 'pw newbie', 'nonce' => nonce()));
check($code === 200 && $b['account']['terms'] === false, 'an account without the current Terms logs in, terms false');
[$code, $b] = create(array('name' => 'Fresh Face'), $b['token']);
check($code === 403 && $b['error'] === 'terms' && $b['url'] === 'https://www.example.org/page.php?plugin=chaos&p=accept', 'create without the Terms: 403 with the accept page');
$pdo->exec("UPDATE accounts SET password = '" . chaos_password_hash('new horse', 1000) . "' WHERE id = 7");
[$code, $b] = api(array('action' => 'state', 'token' => $token));
check($code === 401, 'a password change ends the token');
[$code, $b] = api(array('action' => 'login', 'account' => 'ashwalker', 'password' => 'new horse', 'nonce' => nonce()));
$t2 = $b['token'];
[$code] = api(array('action' => 'logout', 'token' => $t2));
[$code2] = api(array('action' => 'state', 'token' => $t2));
check($code === 200 && $code2 === 401, 'logout ends the token');
$pdo->exec("UPDATE chaos_client_tokens SET expires = 0");
[$code] = api(array('action' => 'state', 'token' => $token));
check($code === 401, 'an expired token');

// ---------------------------------------------------------------- brute force and floods
$pdo->exec('DELETE FROM znote_login_attempts');
$_SERVER['REMOTE_ADDR'] = '198.51.100.9';
for ($i = 0; $i < 5; $i++) {
	api(array('action' => 'login', 'account' => 'ashwalker', 'password' => 'guess ' . $i, 'nonce' => nonce()), '198.51.100.9');
}
$_SERVER['REMOTE_ADDR'] = '198.51.100.9';
[$code, $b] = api(array('action' => 'login', 'account' => 'ashwalker', 'password' => 'new horse', 'nonce' => nonce()), '198.51.100.9');
check($code === 429 && $b['error'] === 'locked', 'five failures from one address: that address is locked (the right password too)');
for ($i = 0; $i < 5; $i++) {
	$_SERVER['REMOTE_ADDR'] = '192.0.2.' . (10 + $i);
	api(array('action' => 'login', 'account' => 'ashwalker', 'password' => 'guess ' . $i, 'nonce' => nonce()), $_SERVER['REMOTE_ADDR']);
}
$_SERVER['REMOTE_ADDR'] = '192.0.2.99';
[$code, $b] = api(array('action' => 'login', 'account' => 'ashwalker', 'password' => 'new horse', 'nonce' => nonce()), '192.0.2.99');
check($code === 429 && $b['error'] === 'locked', 'ten failures on one name from many addresses: the name is locked');
$_SERVER['REMOTE_ADDR'] = $IP;
$GLOBALS['config']['chaos_client_api']['per_ip_minute'] = 3;
$pdo->exec('DELETE FROM chaos_client_api_log');
for ($i = 0; $i < 3; $i++) {
	api(array('action' => 'state', 'token' => 'x'), '2001:db8:1:2::' . ($i + 1));
}
[$code, $b] = api(array('action' => 'state', 'token' => 'x'), '2001:db8:1:2:ffff::1');
check($code === 429 && $b['error'] === 'busy', 'the per-minute limit, IPv6 counted by its /64');
[$code] = api(array('action' => 'state', 'token' => 'x'), '2001:db8:1:3::1');
check($code === 401, 'another /64 is not limited');
$GLOBALS['config']['chaos_client_api']['enabled'] = false;
[$code, $b] = api(array('action' => 'login'));
check($code === 503 && $b['error'] === 'off', 'switched off');

// ---------------------------------------------------------------- the class look table follows class_looks_core.lua
check(chaos_class_look(4, 1) === 2073 && chaos_class_look(4, 0) === 2074, 'Warrior: base looks');
check(chaos_class_look(8, 1) === 2161 && chaos_class_look(23, 0) === 2180, 'pair 19 and pair 20 looks with the switches on');
check(chaos_class_look(0, 1) === null && chaos_class_look(2, 1) === null, 'no look for no class or a retired id');
$lua = trim((string)shell_exec('command -v luajit || command -v lua5.3 || command -v lua'));
$lua = $lua === '' ? '' : strtok($lua, "\n");
$luaCheck = $lua === '' ? '' : trim((string)shell_exec('cd ' . escapeshellarg($repo . '/server') . ' && ' . escapeshellarg($lua) . ' -e '
	. escapeshellarg('Chaos = {classes = {}}; dofile("data/scripts/chaos/class_looks_core.lua"); local t = {}; for v = 1, 25 do for s = 0, 1 do t[#t + 1] = v .. ":" .. s .. "=" .. tostring((ChaosClassLooks.lookFor(v, s)) or "nil") end end; io.write(table.concat(t, " "))') . ' 2>/dev/null'));
if ($luaCheck !== '') {
	$php = array();
	for ($v = 1; $v <= 25; $v++) {
		for ($s = 0; $s <= 1; $s++) {
			$php[] = $v . ':' . $s . '=' . (chaos_class_look($v, $s) ?? 'nil');
		}
	}
	check(implode(' ', $php) === $luaCheck, 'every class and sex: the same look as ChaosClassLooks.lookFor');
} else {
	echo "note: no Lua interpreter, the class look comparison with class_looks_core.lua was skipped\n";
}

@unlink($data . '/scripts');
@unlink($data . '/XML/shaders.xml');
@rmdir($data . '/XML');
@rmdir($data);
echo $failed === 0 ? "chaos_client_api_test: all $checks checks passed\n" : "chaos_client_api_test: $failed of $checks checks FAILED\n";
exit($failed === 0 ? 0 : 1);
