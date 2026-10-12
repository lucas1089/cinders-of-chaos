<?php
/**
 * Website mail (website/README.md "Mail"). Loaded by plugin.php.
 *
 *  - One sender for the whole site: the recovery page (recovery_lib.php) and ZnoteX's own Mail class
 *    (patches/znotex-chaos-recovery-mail.patch sends it here: the 2FA e-mail codes).
 *  - SMTP through PHPMailer, which install_site.sh puts into vendor/phpmailer/phpmailer/src (pinned, hash checked).
 *  - Off when config.local.php has no SMTP host ($config['chaos_mail']['enabled'] false, setup/write_config.php):
 *    every send returns false at once and nothing connects anywhere.
 *  - A send waits at most 15 s for the SMTP server. A failure is logged without the password.
 *  - Tests set $GLOBALS['chaos_mail_transport'] = callable(array $message): bool; nothing goes to the network then.
 */

if (!function_exists('chaos_mail_settings')) {

/** The mail settings: ZnoteX's $config['mailserver'] (host, port, account, From) and ours ($config['chaos_mail']). */
function chaos_mail_settings(): array {
	$server = (array)($GLOBALS['config']['mailserver'] ?? array());
	$own = (array)($GLOBALS['config']['chaos_mail'] ?? array());
	$tls = (string)($own['tls'] ?? 'starttls');
	return array(
		'enabled'   => !empty($own['enabled']),
		'host'      => (string)($server['host'] ?? ''),
		'port'      => (int)($server['port'] ?? 587),
		'tls'       => in_array($tls, array('starttls', 'tls', 'none'), true) ? $tls : 'starttls',
		'username'  => (string)($server['username'] ?? ''),
		'password'  => (string)($server['password'] ?? ''),
		'from'      => (string)($server['email'] ?? ''),
		'from_name' => (string)($server['fromName'] ?? ($GLOBALS['config']['site_title'] ?? 'Cinders of Chaos')),
		'timeout'   => max(5, min(60, (int)($own['timeout'] ?? 15))),
	);
}

/** True when the site can send mail: switched on, a host and a valid From address. */
function chaos_mail_enabled(): bool {
	$s = chaos_mail_settings();
	return $s['enabled'] && $s['host'] !== '' && filter_var($s['from'], FILTER_VALIDATE_EMAIL) !== false;
}

/** The site's name in mails. */
function chaos_mail_site_name(): string {
	$name = (string)($GLOBALS['config']['site_title'] ?? '');
	return $name !== '' ? $name : 'Cinders of Chaos';
}

/** Plain text of an HTML body (line breaks kept). */
function chaos_mail_text_of(string $html): string {
	$text = preg_replace('~<br\s*/?>|</p>|</h[1-6]>|<hr\s*/?>~i', "\n", $html);
	$text = html_entity_decode(strip_tags((string)$text), ENT_QUOTES | ENT_HTML5, 'UTF-8');
	return trim((string)preg_replace("/\n{3,}/", "\n\n", $text));
}

/** No line breaks in a header value (subject, names). */
function chaos_mail_header_value(string $value): string {
	return trim((string)preg_replace('/[\r\n\t]+/', ' ', $value));
}

/**
 * Sends one mail. Returns false when mail is off, the address is not valid or the server refused it; never throws.
 */
function chaos_mail_send(string $to, string $toName, string $subject, string $text, string $html = ''): bool {
	if (!chaos_mail_enabled() || filter_var($to, FILTER_VALIDATE_EMAIL) === false) {
		return false;
	}
	$s = chaos_mail_settings();
	$message = array(
		'to'        => $to,
		'to_name'   => chaos_mail_header_value($toName),
		'from'      => $s['from'],
		'from_name' => chaos_mail_header_value($s['from_name']),
		'subject'   => chaos_mail_header_value($subject),
		'text'      => $text,
		'html'      => $html,
	);
	$transport = $GLOBALS['chaos_mail_transport'] ?? null;
	if (is_callable($transport)) {
		return (bool)$transport($message);
	}
	return chaos_mail_smtp($message, $s);
}

/** The SMTP transport (PHPMailer). */
function chaos_mail_smtp(array $m, array $s): bool {
	if (!class_exists('PHPMailer\\PHPMailer\\PHPMailer')) {
		error_log('Cinders of Chaos mail: PHPMailer is missing; run website/install_site.sh again.');
		return false;
	}
	try {
		$mail = new \PHPMailer\PHPMailer\PHPMailer(true);
		$mail->isSMTP();
		$mail->SMTPDebug = 0;
		$mail->Host = $s['host'];
		$mail->Port = $s['port'];
		$mail->Timeout = $s['timeout'];
		$mail->SMTPAuth = $s['username'] !== '';
		$mail->Username = $s['username'];
		$mail->Password = $s['password'];
		if ($s['tls'] === 'starttls') {
			$mail->SMTPSecure = 'tls';     // STARTTLS, usually port 587
		} elseif ($s['tls'] === 'tls') {
			$mail->SMTPSecure = 'ssl';     // TLS from the first byte, usually port 465
		} else {
			$mail->SMTPSecure = '';        // a relay on this machine only (write_config.php refuses another host)
			$mail->SMTPAutoTLS = false;
		}
		$mail->CharSet = 'UTF-8';
		$mail->XMailer = ' ';              // no mailer header
		$mail->setFrom($m['from'], $m['from_name'], false);
		$mail->addAddress($m['to'], $m['to_name']);
		$mail->Subject = $m['subject'];
		if ($m['html'] !== '') {
			$mail->isHTML(true);
			$mail->Body = $m['html'];
			$mail->AltBody = $m['text'];
		} else {
			$mail->Body = $m['text'];
		}
		return $mail->send();
	} catch (\Throwable $e) {
		// PHPMailer's messages name the step that failed, never the password
		error_log('Cinders of Chaos mail: not sent: ' . str_replace(array("\r", "\n"), ' ', $e->getMessage()));
		return false;
	}
}

}

// PHPMailer from vendor/ (install_site.sh), when no composer autoloader brought it already
spl_autoload_register(static function (string $class): void {
	$prefix = 'PHPMailer\\PHPMailer\\';
	if (strncmp($class, $prefix, strlen($prefix)) !== 0) {
		return;
	}
	$short = substr($class, strlen($prefix));
	$file = dirname(__DIR__, 2) . '/vendor/phpmailer/phpmailer/src/' . $short . '.php';
	if (preg_match('/^[A-Za-z]+$/', $short) === 1 && is_file($file)) {
		require_once $file;
	}
});
