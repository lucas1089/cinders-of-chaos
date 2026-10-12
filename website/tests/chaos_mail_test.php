<?php
// php website/tests/chaos_mail_test.php : website mail (website/README.md "Mail"): the SMTP settings written into
// config.local.php from the environment (setup/write_config.php), mail off without a host, wrong settings refused, the
// plugin's sender (plugins/chaos/mail_lib.php) with a fake transport, ZnoteX's Mail class sent through it (patch), and
// the PHPMailer install step. php-cli only, no database, no network.
$failed = 0;
function check(bool $ok, string $what): void {
	global $failed;
	if (!$ok) { $failed++; echo "FAIL: $what\n"; }
}
$root = dirname(__DIR__);

/** Runs write_config.php with these settings: array(exit code, config array, stdout, stderr). */
function run_config(array $env): array {
	$base = array('CHAOS_DB_USER' => 'u', 'CHAOS_DB_NAME' => 'n', 'CHAOS_DB_HOST' => '127.0.0.1', 'CHAOS_DB_PORT' => '1',
		'CHAOS_START_TOWNS' => '1', 'CHAOS_SITE_URL' => 'https://www.example.org');
	$cmd = 'env -i PATH=' . escapeshellarg((string)getenv('PATH'));
	foreach ($env + $base as $k => $v) {
		$cmd .= ' ' . $k . '=' . escapeshellarg($v);
	}
	$cmd .= ' ' . escapeshellarg(PHP_BINARY) . ' ' . escapeshellarg(dirname(__DIR__) . '/setup/write_config.php');
	$proc = proc_open($cmd, array(1 => array('pipe', 'w'), 2 => array('pipe', 'w')), $pipes);
	$out = stream_get_contents($pipes[1]);
	$err = stream_get_contents($pipes[2]);
	fclose($pipes[1]);
	fclose($pipes[2]);
	$code = proc_close($proc);
	$config = array('mailserver' => array('host' => 'stock.invalid', 'password' => 'stock'), 'twoFactorV2' => array('email_otp_enabled' => true));
	if ($code === 0) {
		eval('?>' . $out);
	}
	return array($code, $config, (string)$out, (string)$err);
}

// ---------------------------------------------------------------- no host: no mail, cleanly
[$code, $c, $out, $err] = run_config(array());
check($code === 0, 'no SMTP settings: the config is still written');
check($c['chaos_mail']['enabled'] === false && $c['mailserver']['accountRecovery'] === false, 'no host: mail and recovery off');
check($c['mailserver']['host'] === '' && $c['mailserver']['password'] === '' && $c['mailserver']['username'] === '', 'no host: no stock host or password left');
check($c['twoFactorV2']['email_otp_enabled'] === false, 'no host: no e-mail login codes (a player could not receive them)');
check($c['mailserver']['register'] === false && $c['mailserver']['myaccount_verify_email'] === false, 'no activation mail, no verify mail');
check(strpos($err, 'CHAOS_SMTP_HOST is empty') !== false, 'the installer says mail is off');

// ---------------------------------------------------------------- full settings
$secret = "pa'ss\"wo\\rd\$x";
[$code, $c, $out] = run_config(array('CHAOS_SMTP_HOST' => 'smtp.relay.example', 'CHAOS_SMTP_USER' => 'apikey', 'CHAOS_SMTP_PASSWORD' => $secret,
	'CHAOS_MAIL_FROM' => 'no-reply@example.org'));
check($code === 0, 'mail on: written');
$m = $c['mailserver'];
check($m['host'] === 'smtp.relay.example' && $m['port'] === 587 && $m['securityType'] === 'tls', 'default: STARTTLS on 587');
check($m['username'] === 'apikey' && $m['password'] === $secret, 'password written exactly (quotes, backslash, dollar)');
check($m['email'] === 'no-reply@example.org' && $m['fromName'] === 'Cinders of Chaos', 'From address and our name');
check($m['accountRecovery'] === true && $c['chaos_mail']['enabled'] === true && $c['chaos_mail']['tls'] === 'starttls', 'recovery on');
check($c['chaos_mail']['reset_minutes'] === 30 && $c['chaos_mail']['per_ip_hour'] === 5 && $c['chaos_mail']['per_account_hour'] === 3, 'recovery limits');
check($m['debug'] === false, 'no SMTP debug output to visitors');
check($c['twoFactorV2']['email_otp_enabled'] === true, 'e-mail login codes allowed with mail on');

[$code, $c] = run_config(array('CHAOS_SMTP_HOST' => 'smtp.relay.example', 'CHAOS_SMTP_TLS' => 'tls', 'CHAOS_MAIL_FROM' => 'a@example.org',
	'CHAOS_MAIL_FROM_NAME' => 'Cinders of Chaos Staff'));
check($code === 0 && $c['mailserver']['port'] === 465 && $c['mailserver']['securityType'] === 'ssl', 'tls: implicit TLS on 465');
check($c['mailserver']['fromName'] === 'Cinders of Chaos Staff' && $c['mailserver']['username'] === '', 'From name; no login');
[$code, $c] = run_config(array('CHAOS_SMTP_HOST' => 'localhost', 'CHAOS_SMTP_TLS' => 'none', 'CHAOS_SMTP_PORT' => '25', 'CHAOS_MAIL_FROM' => 'a@example.org'));
check($code === 0 && $c['mailserver']['securityType'] === '' && $c['mailserver']['port'] === 25, 'none: a local relay on port 25');

// ---------------------------------------------------------------- wrong settings stop the installer
$bad = array(
	'TLS off to a remote host' => array('CHAOS_SMTP_HOST' => 'smtp.relay.example', 'CHAOS_SMTP_TLS' => 'none', 'CHAOS_MAIL_FROM' => 'a@example.org'),
	'unknown TLS mode' => array('CHAOS_SMTP_HOST' => 'smtp.relay.example', 'CHAOS_SMTP_TLS' => 'ssl3', 'CHAOS_MAIL_FROM' => 'a@example.org'),
	'no From address' => array('CHAOS_SMTP_HOST' => 'smtp.relay.example'),
	'bad From address' => array('CHAOS_SMTP_HOST' => 'smtp.relay.example', 'CHAOS_MAIL_FROM' => 'no-reply'),
	'host with a newline' => array('CHAOS_SMTP_HOST' => "smtp.relay.example\nX", 'CHAOS_MAIL_FROM' => 'a@example.org'),
	'From name with a newline' => array('CHAOS_SMTP_HOST' => 'smtp.relay.example', 'CHAOS_MAIL_FROM' => 'a@example.org', 'CHAOS_MAIL_FROM_NAME' => "A\r\nBcc: x@example.org"),
	'password without user' => array('CHAOS_SMTP_HOST' => 'smtp.relay.example', 'CHAOS_MAIL_FROM' => 'a@example.org', 'CHAOS_SMTP_PASSWORD' => 'p'),
	'port out of range' => array('CHAOS_SMTP_HOST' => 'smtp.relay.example', 'CHAOS_MAIL_FROM' => 'a@example.org', 'CHAOS_SMTP_PORT' => '70000'),
);
foreach ($bad as $what => $env) {
	[$code, , $out, $err] = run_config($env + array('CHAOS_SMTP_PASSWORD' => 'Secret-Never-Printed', 'CHAOS_SMTP_USER' => 'u'));
	if ($what === 'password without user') {
		[$code, , $out, $err] = run_config($env);
	}
	check($code !== 0 && $out === '', "refused: $what");
	check(strpos($err, 'Mail settings') !== false && strpos($err, 'Secret-Never-Printed') === false, "message without the password: $what");
}

// ---------------------------------------------------------------- the sender
$GLOBALS['config'] = $config = array('site_title' => 'Cinders of Chaos',
	'mailserver' => array('host' => 'smtp.relay.example', 'port' => 587, 'username' => 'apikey', 'password' => 'SMTP-SECRET-1',
		'email' => 'no-reply@example.org', 'fromName' => 'Cinders of Chaos'),
	'chaos_mail' => array('enabled' => false, 'tls' => 'starttls'));
require $root . '/overlay/plugins/chaos/lib.php';
require $root . '/overlay/plugins/chaos/mail_lib.php';
$sent = array();
$GLOBALS['chaos_mail_transport'] = static function (array $m) use (&$sent): bool { $sent[] = $m; return true; };

check(!chaos_mail_enabled(), 'disabled in the config: off');
check(chaos_mail_send('player@example.org', 'Player', 'Hi', 'text') === false && $sent === array(), 'off: nothing sent, the transport is not called');
$GLOBALS['config']['chaos_mail']['enabled'] = true;
$GLOBALS['config']['mailserver']['email'] = 'not-an-address';
check(!chaos_mail_enabled(), 'on but no valid From: off');
$GLOBALS['config']['mailserver']['email'] = 'no-reply@example.org';
$GLOBALS['config']['mailserver']['host'] = '';
check(!chaos_mail_enabled(), 'on but no host: off');
$GLOBALS['config']['mailserver']['host'] = 'smtp.relay.example';
check(chaos_mail_enabled(), 'host and From: on');

check(chaos_mail_send('player@example.org', "Pla\r\nyer", "Subject\r\nBcc: victim@example.org", 'Body text', '<p>Body</p>') === true, 'sent through the transport');
$m = $sent[0] ?? array();
check(($m['to'] ?? '') === 'player@example.org' && ($m['from'] ?? '') === 'no-reply@example.org' && ($m['from_name'] ?? '') === 'Cinders of Chaos', 'recipient and sender');
check(strpbrk((string)($m['subject'] ?? "\n"), "\r\n") === false && strpbrk((string)($m['to_name'] ?? "\n"), "\r\n") === false, 'no line breaks in subject or name (no header injection)');
check(strpos(json_encode($m), 'SMTP-SECRET-1') === false, 'the SMTP password is never in a message');
check(chaos_mail_send('not an address', 'x', 's', 't') === false && count($sent) === 1, 'an invalid recipient is not sent');
check(chaos_mail_text_of('<h1>Title</h1><p>a &amp; b<br>c</p>') === "Title\na & b\nc", 'plain text of an HTML body');

// the SMTP transport without PHPMailer: false, logged, no exception and no connection
unset($GLOBALS['chaos_mail_transport']);
ini_set('error_log', '/dev/null');
check(chaos_mail_send('player@example.org', 'Player', 'Hi', 'text') === false, 'PHPMailer missing: false, no exception');
$GLOBALS['chaos_mail_transport'] = static function (array $m) use (&$sent): bool { $sent[] = $m; return true; };

// ---------------------------------------------------------------- ZnoteX's Mail class goes through the sender
$patch = (string)file_get_contents($root . '/patches/znotex-chaos-recovery-mail.patch');
check(strpos($patch, "+        if (function_exists('chaos_mail_send')) {\n+            return chaos_mail_send(\$to, \$accname, \$title, chaos_mail_text_of(\$html), \$html);") !== false,
	'patch: Mail::sendMail hands over to chaos_mail_send');
// the patched method, rebuilt from the patch's lines, sends through the fake transport
$class = "class ZnoteMailUnderTest { public function sendMail(string \$to, string \$title, string \$html, string \$accname = ''): bool {\n";
foreach (explode("\n", $patch) as $line) {
	if (strpos($line, '+        ') === 0 && strpos($line, '+        //') !== 0) {
		$class .= substr($line, 1) . "\n";
	}
}
$class .= "return false; } }";
eval($class);
$before = count($sent);
check((new ZnoteMailUnderTest())->sendMail('p2@example.org', 'Cinders of Chaos - Login verification code', '<p>Your code is:</p><h2>123456</h2>', 'acc') === true
	&& count($sent) === $before + 1 && $sent[$before]['text'] === "Your code is:\n123456", "ZnoteX's mails (2FA codes) use the same sender");

// ---------------------------------------------------------------- the installer
$sh = (string)file_get_contents($root . '/install_site.sh');
check(strpos($sh, 'PHPMAILER_COMMIT="1bc1716a507a65e039d4ac9d9adebbbd0d346e15"') !== false, 'PHPMailer pinned to a commit');
check(preg_match_all('/^(PHPMAILER_FILES=")?(src\/[A-Za-z]+\.php|LICENSE):[0-9a-f]{64}"?$/m', $sh) === 4, 'every PHPMailer file has a SHA-256');
check(strpos($sh, 'checksum mismatch') !== false && strpos($sh, '$SITE/vendor/phpmailer/phpmailer') !== false, 'checked, into vendor/ (denied by the web server)');
check(strpos($sh, '3c. PHPMailer') < strpos($sh, '4. config.local.php'), 'installed before the config is written');
$env = (string)file_get_contents($root . '/site.env.example');
foreach (array('CHAOS_SMTP_HOST', 'CHAOS_SMTP_PORT', 'CHAOS_SMTP_TLS', 'CHAOS_SMTP_USER', 'CHAOS_SMTP_PASSWORD', 'CHAOS_MAIL_FROM', 'CHAOS_MAIL_FROM_NAME') as $k) {
	check(preg_match('/^' . $k . '=/m', $env) === 1, "site.env.example has $k");
}
check(preg_match('/^CHAOS_SMTP_(HOST|USER|PASSWORD)=\S/m', $env) === 0 && preg_match('/^CHAOS_MAIL_FROM=\S/m', $env) === 0, 'site.env.example: no real host, user, password or From');
$plugin = (string)file_get_contents($root . '/overlay/plugins/chaos/plugin.php');
check(strpos($plugin, "require_once __DIR__ . '/mail_lib.php';") !== false, 'the plugin loads the sender');

echo $failed === 0 ? "chaos_mail_test: OK\n" : "chaos_mail_test: $failed failed\n";
exit($failed === 0 ? 0 : 1);
