<?php
/**
 * Settings and wiring of the donation flow (website/README.md "Donations").
 *
 * Credentials NEVER live in the repository or in the web root. They come from the environment, or from a settings
 * file outside the web root (default /etc/chaos/payments.env, other path in CHAOS_PAY_ENV; format KEY=value, one per
 * line, # comments; website/payments.env.example lists every key). A variable set in the real environment wins over
 * the file. The webhook (run by the web server) and the worker (systemd) read the same file.
 */

require_once __DIR__ . '/Provider.php';
require_once __DIR__ . '/Db.php';
require_once __DIR__ . '/Service.php';
require_once __DIR__ . '/MercadoPago.php';
require_once __DIR__ . '/PayPal.php';
require_once __DIR__ . '/Mock.php';

const CHAOS_PAY_KEYS = array(
	'CHAOS_PAY_PIX_PROVIDER', 'CHAOS_PAY_PAYPAL_PROVIDER', 'CHAOS_PAY_SITE_URL', 'CHAOS_PAY_PAYER_EMAIL',
	'CHAOS_PAY_RECONCILE_SECONDS', 'CHAOS_PAY_LOG', 'CHAOS_PAY_PAYER_SALT',
	'CHAOS_MP_ACCESS_TOKEN', 'CHAOS_MP_WEBHOOK_SECRET', 'CHAOS_MP_NOTIFICATION_URL', 'CHAOS_MP_SIGNATURE_TOLERANCE',
	'CHAOS_PAYPAL_CLIENT_ID', 'CHAOS_PAYPAL_CLIENT_SECRET', 'CHAOS_PAYPAL_WEBHOOK_ID', 'CHAOS_PAYPAL_ENV',
	'CHAOS_PAYPAL_CATEGORY', 'CHAOS_PAYPAL_BRAND',
	'CHAOS_PAY_MOCK_APPROVE_AFTER', 'CHAOS_PAY_MOCK_STATE', 'CHAOS_PAY_MOCK_SECRET', 'CHAOS_PAY_MOCK_URL', 'CHAOS_PAY_ALLOW_MOCK',
);

/**
 * The mock provider approves charges nobody paid, so it only runs on a local site (localhost, 127.0.0.1, ::1) or with
 * CHAOS_PAY_ALLOW_MOCK=1 (a demo server that knows what it does). $siteUrl: the site's address.
 */
function chaos_pay_mock_allowed(array $s, string $siteUrl): bool {
	if (($s['CHAOS_PAY_ALLOW_MOCK'] ?? '') === '1') {
		return true;
	}
	$host = strtolower(trim((string)parse_url($siteUrl, PHP_URL_HOST), '[]'));
	return in_array($host, array('localhost', '127.0.0.1', '::1'), true);
}

/** The site's address of the settings: CHAOS_PAY_SITE_URL, else ZnoteX's site_url. */
function chaos_pay_site_url(array $s, ?array $config = null): string {
	$config = $config ?? (array)($GLOBALS['config'] ?? array());
	return ($s['CHAOS_PAY_SITE_URL'] ?? '') !== '' ? (string)$s['CHAOS_PAY_SITE_URL'] : (string)($config['site_url'] ?? '');
}

/** KEY=value lines of a settings file (quotes around a value are removed). */
function chaos_pay_read_env_file(string $path): array {
	$out = array();
	if ($path === '' || !is_file($path) || !is_readable($path)) {
		return $out;
	}
	foreach (file($path, FILE_IGNORE_NEW_LINES) as $line) {
		$line = trim($line);
		if ($line === '' || $line[0] === '#' || !preg_match('/^(?:export\s+)?([A-Z0-9_]+)\s*=\s*(.*)$/', $line, $m)) {
			continue;
		}
		$v = trim($m[2]);
		if (strlen($v) >= 2 && ($v[0] === '"' || $v[0] === "'") && substr($v, -1) === $v[0]) {
			$v = substr($v, 1, -1);
		} else {
			$v = preg_replace('/\s+#.*$/', '', $v);
		}
		$out[$m[1]] = $v;
	}
	return $out;
}

/** The settings: real environment first, then the file. */
function chaos_pay_settings(?string $file = null): array {
	$file = $file ?? (getenv('CHAOS_PAY_ENV') ?: '/etc/chaos/payments.env');
	$fromFile = chaos_pay_read_env_file($file);
	$s = array();
	foreach (CHAOS_PAY_KEYS as $k) {
		$env = getenv($k);
		$s[$k] = ($env !== false && $env !== '') ? (string)$env : (string)($fromFile[$k] ?? '');
	}
	return $s;
}

/** The providers the settings switch on: method => provider. */
function chaos_pay_providers(array $s, ?callable $http = null, ?callable $now = null, ?string $siteUrl = null): array {
	$out = array();
	$mockOk = chaos_pay_mock_allowed($s, $siteUrl ?? chaos_pay_site_url($s));
	foreach (array('CHAOS_PAY_PIX_PROVIDER', 'CHAOS_PAY_PAYPAL_PROVIDER') as $k) {
		if (($s[$k] ?? '') === 'mock' && !$mockOk) {
			error_log("[chaos pay] $k=mock refused: the site is not local (set CHAOS_PAY_ALLOW_MOCK=1 for a demo server)");
			$s[$k] = 'off';
		}
	}
	$mockState = $s['CHAOS_PAY_MOCK_STATE'] !== '' ? $s['CHAOS_PAY_MOCK_STATE'] : sys_get_temp_dir() . '/chaos_pay_mock.json';
	$mockAfter = $s['CHAOS_PAY_MOCK_APPROVE_AFTER'] !== '' ? (int)$s['CHAOS_PAY_MOCK_APPROVE_AFTER'] : 20;
	$mockUrl = $s['CHAOS_PAY_MOCK_URL'] !== '' ? $s['CHAOS_PAY_MOCK_URL'] : 'https://www.example.invalid/mock-donation/';
	switch ($s['CHAOS_PAY_PIX_PROVIDER']) {
		case 'mercadopago':
			$out['pix'] = new ChaosPayMercadoPago($s['CHAOS_MP_ACCESS_TOKEN'], $s['CHAOS_MP_WEBHOOK_SECRET'], $s['CHAOS_MP_NOTIFICATION_URL'],
				$s['CHAOS_MP_SIGNATURE_TOLERANCE'] !== '' ? (int)$s['CHAOS_MP_SIGNATURE_TOLERANCE'] : 600, $http, $now);
			break;
		case 'mock':
			$out['pix'] = new ChaosPayMock('pix', $mockAfter, $mockState, $s['CHAOS_PAY_MOCK_SECRET'], $mockUrl, $now);
			break;
	}
	switch ($s['CHAOS_PAY_PAYPAL_PROVIDER']) {
		case 'paypal':
			$out['paypal'] = new ChaosPayPayPal($s['CHAOS_PAYPAL_CLIENT_ID'], $s['CHAOS_PAYPAL_CLIENT_SECRET'], $s['CHAOS_PAYPAL_WEBHOOK_ID'],
				$s['CHAOS_PAYPAL_ENV'] === 'live' ? 'live' : 'sandbox', $s['CHAOS_PAYPAL_CATEGORY'] !== '' ? $s['CHAOS_PAYPAL_CATEGORY'] : 'DONATION',
				$s['CHAOS_PAYPAL_BRAND'], $http, $now, ChaosPayPayPal::tokenCachePath($s['CHAOS_PAYPAL_CLIENT_ID'], $s['CHAOS_PAYPAL_CLIENT_SECRET'],
					$s['CHAOS_PAYPAL_ENV']));
			break;
		case 'mock':
			$out['paypal'] = new ChaosPayMock('paypal', $mockAfter, $mockState, $s['CHAOS_PAY_MOCK_SECRET'], $mockUrl, $now);
			break;
	}
	return $out;
}

/** Packs keyed by key, from the game server's shop_coins_config.lua (lib.php). */
function chaos_pay_packs(): array {
	$out = array();
	foreach (chaos_coin_packs() as $p) {
		$out[$p['key']] = $p;
	}
	return $out;
}

function chaos_pay_logger(array $s): callable {
	$file = $s['CHAOS_PAY_LOG'];
	return static function (string $line) use ($file): void {
		$line = gmdate('Y-m-d H:i:s') . ' ' . $line;
		if ($file !== '') {
			@file_put_contents($file, $line . "\n", FILE_APPEND | LOCK_EX);
		} else {
			error_log('[chaos pay] ' . $line);
		}
	};
}

/** The service for the site / worker / webhook. $config: ZnoteX's $config (database, $config['chaos']). */
function chaos_pay_service(array $config, ?array $settings = null, ?ChaosPayDb $db = null): ChaosPayService {
	$GLOBALS['config'] = $GLOBALS['config'] ?? $config;
	$s = $settings ?? chaos_pay_settings();
	$site = chaos_pay_site_url($s, $config);
	return new ChaosPayService($db ?? ChaosPayMysqli::fromConfig($config), chaos_pay_providers($s, null, null, $site), chaos_pay_packs(), chaos_pay_config(),
		array('site_url' => $site, 'payer_email' => $s['CHAOS_PAY_PAYER_EMAIL'],
			'reconcile_seconds' => $s['CHAOS_PAY_RECONCILE_SECONDS'] !== '' ? (int)$s['CHAOS_PAY_RECONCILE_SECONDS'] : 60,
			'payer_salt' => (string)($s['CHAOS_PAY_PAYER_SALT'] ?? '')),
		null, chaos_pay_logger($s));
}
