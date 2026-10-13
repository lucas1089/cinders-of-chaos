<?php
/**
 * The Character Bazaar's clock (website/README.md "Character Bazaar"): ends the auctions whose time ran out (expire,
 * or move the character to the winner and pay the seller). The bazaar page does the same for the listings it shows,
 * so this only makes ends happen on time when nobody looks. Run it from the installed site as the web server's user:
 *
 *   * * * * * www-data php <site>/plugins/chaos/bazaar_worker.php --site <site>      (cron, every minute)
 */
if (PHP_SAPI !== 'cli') {
	http_response_code(404);
	exit;
}
$opts = getopt('', array('site:'));
$site = rtrim((string)($opts['site'] ?? dirname(__DIR__, 2)), '/');
if (!is_file($site . '/config.local.php')) {
	fwrite(STDERR, "No config.local.php in $site (pass --site <the website folder>).\n");
	exit(2);
}
$config = array();
require $site . '/config.local.php';
$GLOBALS['config'] = $config;
require_once __DIR__ . '/lib.php';
require_once __DIR__ . '/mail_lib.php';
require_once __DIR__ . '/bazaar_lib.php';
try {
	$n = chaos_bazaar($config)->settleDue();
	if ($n > 0) {
		echo gmdate('H:i:s') . " bazaar: $n auction(s) ended\n";
	}
} catch (Throwable $e) {
	fwrite(STDERR, gmdate('H:i:s') . ' bazaar round failed: ' . $e->getMessage() . "\n");
	exit(1);
}
