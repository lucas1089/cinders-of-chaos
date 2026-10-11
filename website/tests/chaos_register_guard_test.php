<?php
// php website/tests/chaos_register_guard_test.php : account creation (plugins/chaos/register_guard.php): the per-IP
// limit (3 per hour by default, IPv6 counted by /64), the refusal reaching register.php's errors through the
// register_header view, the generic e-mail message, and reCAPTCHA on the form. php-cli only, no database.
$failed = 0;
function check(bool $ok, string $what): void {
	global $failed;
	if (!$ok) { $failed++; echo "FAIL: $what\n"; }
}
$GLOBALS['config'] = $config = array('chaos_register_limit' => array('per_ip' => 3, 'window_seconds' => 3600));
require __DIR__ . '/../overlay/plugins/chaos/register_guard.php';

check(chaos_register_ip_key('203.0.113.7') === '203.0.113.7', 'IPv4 key');
check(chaos_register_ip_key('2001:db8:1:2:aaaa:bbbb:cccc:dddd') === '2001:db8:1:2::/64', 'IPv6 counted by /64');
check(chaos_register_ip_key('2001:db8:1:2::9') === chaos_register_ip_key('2001:db8:1:2:ffff::1'), 'same /64, same key');

// an in-memory log: key => list of times
$log = array();
$count = static function (string $key, int $since) use (&$log): int {
	return count(array_filter($log[$key] ?? array(), static function (int $t) use ($since): bool { return $t >= $since; }));
};
$now = 1800000000;
foreach (array(0, 60, 120) as $i => $d) {
	check(chaos_register_allowed('198.51.100.1', $now + $d, $count), 'account ' . ($i + 1) . ' allowed');
	$log[chaos_register_ip_key('198.51.100.1')][] = $now + $d;
}
check(!chaos_register_allowed('198.51.100.1', $now + 300, $count), 'the 4th account in the hour refused');
check(chaos_register_allowed('198.51.100.2', $now + 300, $count), 'another address is not affected');
check(chaos_register_allowed('198.51.100.1', $now + 3601, $count), 'allowed again once the first one is an hour old');
$GLOBALS['config']['chaos_register_limit']['per_ip'] = 0;
check(chaos_register_allowed('198.51.100.1', $now + 300, $count), 'per_ip 0 = no limit');

// the refusal reaches register.php's $errors through our register_header view (before the account is created)
function t(string $k): string { return $k; }
$GLOBALS['errors'] = array();
$GLOBALS['chaos_register_error'] = 'Too many accounts were created from your address. Please try again later.';
ob_start();
include __DIR__ . '/../overlay/layouts/chaos/views/register_header.php';
ob_end_clean();
check(($GLOBALS['errors'][0] ?? '') === 'Too many accounts were created from your address. Please try again later.', 'error added by the header view');
check(($GLOBALS['chaos_register_error'] ?? '') === '', 'added once');

// the e-mail messages: the same text for a malformed and a taken address, never "in use"
$locale = include __DIR__ . '/../overlay/layouts/chaos/locale/en.php';
check(isset($locale['reg.email_taken'], $locale['reg.email_invalid']) && $locale['reg.email_taken'] === $locale['reg.email_invalid'], 'one e-mail message');
check(stripos((string)($locale['reg.email_taken'] ?? 'in use'), 'use another') !== false && stripos($locale['reg.email_taken'], 'in use') === false, 'no "already in use"');

// reCAPTCHA: the form loads Google's script and escapes the site key
$form = (string)file_get_contents(__DIR__ . '/../overlay/layouts/chaos/views/register_form.php');
check(strpos($form, 'https://www.google.com/recaptcha/api.js') !== false, 'reCAPTCHA script on the form');
check(strpos($form, "htmlspecialchars((string)\$config['captcha_site_key']") !== false, 'site key escaped');
// the table exists (install.sql runs on every install)
check(strpos((string)file_get_contents(__DIR__ . '/../overlay/plugins/chaos/install.sql'), 'CREATE TABLE IF NOT EXISTS `chaos_web_registrations`') !== false, 'install.sql creates the log');
check(strpos((string)file_get_contents(__DIR__ . '/../overlay/plugins/chaos/plugin.php'), "require_once __DIR__ . '/register_guard.php';") !== false, 'plugin loads the guard');

echo $failed === 0 ? "chaos_register_guard_test: OK\n" : "chaos_register_guard_test: $failed failed\n";
exit($failed === 0 ? 0 : 1);
