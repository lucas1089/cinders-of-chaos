<?php
// php website/tests/chaos_recovery_test.php : account recovery by a one-time link (plugins/chaos/recovery_lib.php,
// recovery_page.php, website/README.md "Mail") over an in-memory SQLite database with a fake mail transport: the same
// answer for every entry (no account enumeration), the limits per address and per account, reCAPTCHA, the link (our
// site address, never the Host header), the token (stored hashed, 30 minutes, once), the new password hashed as typed,
// the notice mail, mail off. php-cli with pdo_sqlite, no ZnoteX, no network.
$failed = 0;
function check(bool $ok, string $what): void {
	global $failed;
	if (!$ok) { $failed++; echo "FAIL: $what\n"; }
}
$root = dirname(__DIR__);
$_SERVER['HTTP_HOST'] = 'evil.example'; // a forged Host header must never reach a link
$GLOBALS['config'] = $config = array(
	'site_title' => 'Cinders of Chaos',
	'site_url' => 'https://www.example.org/',
	'use_captcha' => false,
	'mailserver' => array('host' => 'smtp.relay.example', 'port' => 587, 'username' => 'apikey', 'password' => 'SMTP-SECRET-2',
		'email' => 'no-reply@example.org', 'fromName' => 'Cinders of Chaos'),
	'chaos_mail' => array('enabled' => true, 'tls' => 'starttls', 'reset_minutes' => 30, 'per_ip_hour' => 5, 'per_account_hour' => 3),
	'chaos_register_limit' => array('per_ip' => 3, 'window_seconds' => 3600),
);
require $root . '/overlay/plugins/chaos/lib.php';
require $root . '/overlay/plugins/chaos/register_guard.php';
require $root . '/overlay/plugins/chaos/mail_lib.php';
require $root . '/overlay/plugins/chaos/recovery_lib.php';
require $root . '/overlay/engine/function/chaos_password.php';

$pdo = new PDO('sqlite::memory:');
$pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
final class FakeZnoteDb {
	public PDO $pdo;
	public int $writes = 0;
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
	public function fetchAll(string $sql, array $p = array()) { return $this->run($sql, $p)->fetchAll(PDO::FETCH_ASSOC) ?: false; }
	public function execute(string $sql, array $p = array()) { $this->writes++; $this->run($sql, $p); return true; }
}
$DB = new FakeZnoteDb($pdo);
function db() { return $GLOBALS['DB']; }
$pdo->exec("CREATE TABLE accounts (id INTEGER PRIMARY KEY, name TEXT NOT NULL, password TEXT NOT NULL DEFAULT '', email TEXT NOT NULL DEFAULT '')");
$pdo->exec("INSERT INTO accounts (id, name, email) VALUES (1, 'emberwolf', 'wolf@example.org'), (2, 'nomail', ''), (3, 'twin1', 'twins@example.org'),
	(4, 'twin2', 'twins@example.org')");
// the tables as in install.sql (SQLite types)
$pdo->exec("CREATE TABLE chaos_password_resets (account_id INTEGER PRIMARY KEY, token_hash TEXT NOT NULL UNIQUE, created INT NOT NULL, expires INT NOT NULL)");
$pdo->exec("CREATE TABLE chaos_recovery_requests (id INTEGER PRIMARY KEY AUTOINCREMENT, ip TEXT NOT NULL, account_id INT NOT NULL DEFAULT 0, created INT NOT NULL)");
$sql = (string)file_get_contents($root . '/overlay/plugins/chaos/install.sql');
check(strpos($sql, 'CREATE TABLE IF NOT EXISTS `chaos_password_resets`') !== false && strpos($sql, 'CREATE TABLE IF NOT EXISTS `chaos_recovery_requests`') !== false, 'install.sql creates both tables');

$sent = array();
$GLOBALS['chaos_mail_transport'] = static function (array $m) use (&$sent): bool { $sent[] = $m; return true; };
$captchaCalls = 0;
$captchaOk = static function (string $r) use (&$captchaCalls): bool { $captchaCalls++; return $r === 'good'; };
$passwords = array();
$setPassword = static function (int $id, string $pw) use (&$passwords, $pdo): void {
	$passwords[$id] = $pw;
	$pdo->prepare('UPDATE accounts SET password = ? WHERE id = ?')->execute(array(chaos_password_hash($pw, 1000), $id));
};
$now = 1800000000;
$ip = '203.0.113.9';
/** One request through the page logic; the queued mails are sent like the page does. */
function page(string $method, array $get, array $post, string $ip, int $now): string {
	global $captchaOk, $setPassword;
	$r = chaos_recovery_handle($method, $get, $post, $ip, $now, $captchaOk, $setPassword);
	chaos_recovery_send($r['mails']);
	return $r['html'];
}
function token_of(array $mail): string {
	return preg_match('~https://www\.example\.org/recovery\?reset=([A-Za-z0-9_-]{43})~', (string)$mail['text'], $m) ? $m[1] : '';
}

// ---------------------------------------------------------------- the form
$form = page('GET', array(), array(), $ip, $now);
check(strpos($form, 'name="who"') !== false && strpos($form, 'method="post"') !== false, 'request form');
check(strpos($form, 'g-recaptcha') === false, 'no reCAPTCHA widget while it is off');

// ---------------------------------------------------------------- the same answer for every entry
$found = page('POST', array(), array('who' => 'emberwolf'), $ip, $now);
check(count($sent) === 1, 'a known account name: one mail');
$answers = array(
	'unknown name' => page('POST', array(), array('who' => 'nobody-here'), '198.51.100.1', $now),
	'unknown e-mail' => page('POST', array(), array('who' => 'nobody@example.org'), '198.51.100.1', $now),
	'account without e-mail' => page('POST', array(), array('who' => 'nomail'), '198.51.100.1', $now),
);
foreach ($answers as $what => $html) {
	check($html === $found, "same answer: $what");
}
check(count($sent) === 1, 'no mail for those');
check(strpos($found, 'If an account matches') !== false && strpos($found, '30 minutes') !== false, 'the answer says "if an account matches"');

// ---------------------------------------------------------------- the mail
$mail = $sent[0];
$token = token_of($mail);
check($mail['to'] === 'wolf@example.org' && $mail['to_name'] === 'emberwolf', 'to the account e-mail');
check($mail['subject'] === 'Cinders of Chaos: reset your password', 'subject with our name');
check($token !== '', 'the link uses the configured site address');
check(strpos($mail['html'], 'https://www.example.org/recovery?reset=' . $token) !== false, 'the HTML part has the same link');
check(strpos($mail['text'] . $mail['html'], 'evil.example') === false, 'never the request Host header');
check(strpos($mail['text'], 'emberwolf') !== false && strpos($mail['text'], 'Cinders of Chaos') !== false && strpos($mail['text'], '30 minutes') !== false,
	'the mail names the account, our site and the lifetime');
check(stripos($mail['text'] . $mail['html'], 'znote') === false && stripos($mail['text'] . $mail['html'], 'ZnoteX') === false, 'no other name in the mail');
check(strpos(json_encode($sent), 'SMTP-SECRET-2') === false, 'no SMTP secret in a mail');
$row = $pdo->query('SELECT * FROM chaos_password_resets WHERE account_id = 1')->fetch(PDO::FETCH_ASSOC);
check(is_array($row) && $row['token_hash'] === hash('sha256', $token) && strpos(json_encode($row), $token) === false, 'only the token hash is stored');
check((int)$row['expires'] === $now + 1800, 'the link lasts 30 minutes');

// an e-mail shared by two accounts: one link each
$sent = array();
page('POST', array(), array('who' => 'twins@example.org'), '198.51.100.2', $now);
check(count($sent) === 2 && $sent[0]['to_name'] === 'twin1' && $sent[1]['to_name'] === 'twin2' && token_of($sent[0]) !== token_of($sent[1]), 'one link per account of an address');

// ---------------------------------------------------------------- the link
$bad = chaos_recovery_texts()['bad'];
$html = page('GET', array('reset' => $token), array(), $ip, $now + 60);
check(strpos($html, 'Choose a new password') !== false && strpos($html, 'emberwolf') !== false, 'the link opens the password form');
check(strpos($html, 'name="token"') === false && strpos($html, 'name="reset" value="' . $token . '"') !== false, 'the form keeps the token (not the CSRF field name)');
check(chaos_recovery_check($token, $now + 60) !== null, 'opening the link does not use it up');
check(strpos(page('GET', array('reset' => str_repeat('A', 43)), array(), $ip, $now), $bad) !== false, 'a wrong token: not valid');
check(strpos(page('GET', array('reset' => array('x')), array(), $ip, $now), 'name="who"') !== false, 'a token array is ignored');
check(strpos(page('GET', array('reset' => $token), array(), $ip, $now + 1801), $bad) !== false, 'expired after 30 minutes');

$sent = array();
$html = page('POST', array(), array('reset' => $token, 'password' => 'abc', 'password_again' => 'abc'), $ip, $now + 120);
check(strpos($html, '6 to 29') !== false && chaos_recovery_check($token, $now + 120) !== null, 'a short password: refused, the link still works');
$html = page('POST', array(), array('reset' => $token, 'password' => 'secret-one', 'password_again' => 'secret-two'), $ip, $now + 120);
check(strpos($html, 'not the same') !== false, 'two different passwords: refused');
$typed = "Ash<&>'\"pw 9";
$html = page('POST', array(), array('reset' => $token, 'password' => $typed, 'password_again' => $typed), $ip, $now + 120);
check(strpos($html, 'Your password was changed') !== false, 'password changed');
check(($passwords[1] ?? null) === $typed, 'the password is set exactly as typed');
$stored = (string)$pdo->query('SELECT password FROM accounts WHERE id = 1')->fetchColumn();
check(strpos($stored, 'pbkdf2-sha256$') === 0 && chaos_password_verify($typed, $stored), 'stored as PBKDF2 (the game format)');
check(count($sent) === 1 && $sent[0]['subject'] === 'Cinders of Chaos: your password was changed' && $sent[0]['to'] === 'wolf@example.org'
	&& strpos($sent[0]['text'] . $sent[0]['html'], $typed) === false, 'a notice mail, without the password');
check(strpos(page('POST', array(), array('reset' => $token, 'password' => 'another1', 'password_again' => 'another1'), $ip, $now + 130), $bad) !== false
	&& ($passwords[1] ?? '') === $typed, 'the link works once');
check((int)$pdo->query('SELECT COUNT(*) FROM chaos_password_resets WHERE account_id = 1')->fetchColumn() === 0, 'the used row is gone');

// a new request replaces the older link
$sent = array();
page('POST', array(), array('who' => 'twin1'), '198.51.100.3', $now + 200);
$newer = token_of($sent[0]);
check(chaos_recovery_check($newer, $now + 200) !== null, 'the newest link works');
$older = $pdo->query("SELECT COUNT(*) FROM chaos_password_resets WHERE account_id = 3")->fetchColumn();
check((int)$older === 1, 'one link per account');
// two posts of the same link at once: only one wins
check(chaos_recovery_consume($newer, $now + 201) !== null && chaos_recovery_consume($newer, $now + 201) === null, 'consumed once only');

// ---------------------------------------------------------------- limits
$pdo->exec('DELETE FROM chaos_recovery_requests');
$sent = array();
$t0 = $now + 4000;
for ($i = 0; $i < 3; $i++) {
	page('POST', array(), array('who' => 'emberwolf'), '192.0.2.' . (10 + $i), $t0 + $i);
}
check(count($sent) === 3, '3 links an hour for an account');
$fourth = page('POST', array(), array('who' => 'emberwolf'), '192.0.2.50', $t0 + 10);
check(count($sent) === 3 && $fourth === $found, 'the 4th: no mail, and the same answer (no hint)');
check(count($sent) === 3 && page('POST', array(), array('who' => 'emberwolf'), '192.0.2.51', $t0 + 3700) === $found && count($sent) === 4, 'again after an hour');

$pdo->exec('DELETE FROM chaos_recovery_requests');
$limited = chaos_recovery_texts()['limited'];
for ($i = 0; $i < 5; $i++) {
	check(strpos(page('POST', array(), array('who' => 'x' . $i), '2001:db8:5:6::' . ($i + 1), $t0), 'If an account matches') !== false, 'request ' . ($i + 1) . ' from one address');
}
check(strpos(page('POST', array(), array('who' => 'x9'), '2001:db8:5:6:ffff::1', $t0 + 5), $limited) !== false, 'the 6th from the same address (IPv6 /64): limited');
check(strpos(page('POST', array(), array('who' => 'x9'), '198.51.100.77', $t0 + 5), 'If an account matches') !== false, 'another address is not limited');
check(strpos(page('POST', array(), array('who' => 'x9'), '2001:db8:5:6::1', $t0 + 3601), 'If an account matches') !== false, 'the address again after an hour');
check(strpos(page('POST', array(), array('who' => '   '), '198.51.100.78', $t0), 'Please enter') !== false, 'an empty entry');

// ---------------------------------------------------------------- reCAPTCHA
$GLOBALS['config']['use_captcha'] = true;
$GLOBALS['config']['captcha_site_key'] = 'site"key';
$form = page('GET', array(), array(), $ip, $now);
check(strpos($form, 'data-sitekey="site&quot;key"') !== false && strpos($form, 'https://www.google.com/recaptcha/api.js') !== false, 'the widget and its script, key escaped');
$rows = (int)$pdo->query('SELECT COUNT(*) FROM chaos_recovery_requests')->fetchColumn();
$sent = array();
check(strpos(page('POST', array(), array('who' => 'emberwolf'), '198.51.100.90', $t0 + 9000), 'captcha') !== false, 'no captcha answer: refused');
check(strpos(page('POST', array(), array('who' => 'emberwolf', 'g-recaptcha-response' => 'bad'), '198.51.100.90', $t0 + 9000), 'captcha') !== false, 'a wrong captcha: refused');
check($sent === array() && (int)$pdo->query('SELECT COUNT(*) FROM chaos_recovery_requests')->fetchColumn() === $rows, 'nothing recorded or sent');
check(page('POST', array(), array('who' => 'emberwolf', 'g-recaptcha-response' => 'good'), '198.51.100.90', $t0 + 9000) === $found && count($sent) === 1, 'solved: the request goes on');
$GLOBALS['config']['use_captcha'] = false;

// ---------------------------------------------------------------- mail off
$GLOBALS['config']['chaos_mail']['enabled'] = false;
$sent = array();
$writes = $DB->writes;
$off = chaos_recovery_texts()['off'];
check(strpos(page('GET', array(), array(), $ip, $now), $off) !== false, 'mail off: the page says recovery by e-mail is not available');
check(strpos(page('POST', array(), array('who' => 'emberwolf'), $ip, $now), $off) !== false && $sent === array() && $DB->writes === $writes, 'mail off: a post sends and writes nothing');
check(strpos(page('GET', array('reset' => $newer), array(), $ip, $now), $off) !== false, 'mail off: links are not taken');
$GLOBALS['config']['chaos_mail']['enabled'] = true;

// ---------------------------------------------------------------- the page and the patch
$pagePhp = (string)file_get_contents($root . '/overlay/plugins/chaos/recovery_page.php');
check(strpos($pagePhp, 'znote_csrf_protect_public_post();') !== false && strpos($pagePhp, 'logged_in_redirect();') !== false, 'page: CSRF and logged-in redirect');
check(strpos($pagePhp, "'REMOTE_ADDR'") !== false && stripos($pagePhp, 'forwarded') === false, 'page: the address is REMOTE_ADDR, never a header');
check(strpos($pagePhp, 'Referrer-Policy: no-referrer') !== false && strpos($pagePhp, 'Cache-Control: no-store') !== false, 'page: no Referer, no cache');
check(strpos($pagePhp, 'fastcgi_finish_request') !== false, 'page: mails after the answer');
check(strpos($pagePhp, "user_change_password(\$accountId, \$password)") !== false, "page: ZnoteX's password write (PBKDF2 patch)");
$patch = (string)file_get_contents($root . '/patches/znotex-chaos-recovery-mail.patch');
check(strpos($patch, "+	require __DIR__ . '/plugins/chaos/recovery_page.php';\n+}\n+http_response_code(404);\n+exit;\n znote_csrf_protect_public_post();") !== false,
	'patch: recovery.php hands over at once; the stock modes never run');
check(strpos((string)file_get_contents($root . '/overlay/plugins/chaos/plugin.php'), "require_once __DIR__ . '/recovery_lib.php';") !== false, 'the plugin loads the recovery');

echo $failed === 0 ? "chaos_recovery_test: OK\n" : "chaos_recovery_test: $failed failed\n";
exit($failed === 0 ? 0 : 1);
