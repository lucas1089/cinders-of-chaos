<?php
/**
 * The donation worker (website/README.md "Donations"). Run it from the installed site as the web server's user:
 *
 *   php <site>/plugins/chaos/pay/worker.php --site <site> --loop       (systemd: server/deploy/chaos-payworker.service)
 *   php <site>/plugins/chaos/pay/worker.php --site <site> --once       (cron, every minute: slower to show the QR code)
 *
 * Each round: makes the charge of every new order the game server wrote (the game server has no HTTPS client), checks
 * open orders with the provider (a lost webhook is caught here), expires and cancels. The webhook is the fast path for
 * confirmations; the game server credits paid orders by itself.
 *
 * Test helpers (mock provider only): --mock-refund <order id>, --mock-dispute <order id> refund or charge back a paid
 * mock charge and apply it at once. --status prints the open orders and the settings in use (no secrets).
 */
if (PHP_SAPI !== 'cli') {
	http_response_code(404);
	exit;
}

$opts = getopt('', array('site:', 'loop', 'once', 'interval:', 'mock-refund:', 'mock-dispute:', 'status'));
$site = rtrim((string)($opts['site'] ?? dirname(__DIR__, 3)), '/');
if (!is_file($site . '/config.local.php')) {
	fwrite(STDERR, "No config.local.php in $site (pass --site <the website folder>).\n");
	exit(2);
}
$config = array();
require $site . '/config.local.php';
$GLOBALS['config'] = $config;
require_once dirname(__DIR__) . '/lib.php';
require_once __DIR__ . '/bootstrap.php';

$settings = chaos_pay_settings();
$service = chaos_pay_service($config, $settings);

if (isset($opts['status'])) {
	printf("Pix: %s, PayPal: %s, site: %s\n", $settings['CHAOS_PAY_PIX_PROVIDER'] ?: 'off', $settings['CHAOS_PAY_PAYPAL_PROVIDER'] ?: 'off',
		$settings['CHAOS_PAY_SITE_URL'] ?: ($config['site_url'] ?? ''));
	printf("Methods on: %s\n", implode(', ', array_keys($service->methods())) ?: 'none');
	exit(0);
}

foreach (array('mock-refund' => 'refunded', 'mock-dispute' => 'charged_back') as $opt => $status) {
	if (isset($opts[$opt])) {
		$db = ChaosPayMysqli::fromConfig($config);
		$r = $db->rows('SELECT psp, psp_id FROM chaos_coin_payments WHERE order_id = ?', array((int)$opts[$opt]));
		$provider = $r ? $service->providerByName($r[0]['psp']) : null;
		if (!$provider instanceof ChaosPayMock || !$provider->reverse($r[0]['psp_id'], $status)) {
			fwrite(STDERR, "Order {$opts[$opt]}: not a paid mock charge.\n");
			exit(1);
		}
		echo 'Order ' . (int)$opts[$opt] . ': ' . $service->sync((int)$opts[$opt]) . "\n";
		exit(0);
	}
}

$interval = max(1, (int)($opts['interval'] ?? 2));
$stop = false;
if (function_exists('pcntl_async_signals')) {
	pcntl_async_signals(true);
	pcntl_signal(SIGTERM, static function () use (&$stop) { $stop = true; });
	pcntl_signal(SIGINT, static function () use (&$stop) { $stop = true; });
}
do {
	try {
		$stats = $service->runOnce();
		if (array_sum($stats) > 0) {
			echo gmdate('H:i:s') . ' ' . json_encode($stats) . "\n";
		}
	} catch (Throwable $e) {
		fwrite(STDERR, gmdate('H:i:s') . ' round failed: ' . $e->getMessage() . "\n");
		if (isset($opts['loop'])) {
			sleep(10);
			$service = chaos_pay_service($config, $settings); // a new database connection
		}
	}
	if (!isset($opts['loop'])) {
		break;
	}
	sleep($interval);
} while (!$stop);
