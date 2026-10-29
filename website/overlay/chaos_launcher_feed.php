<?php
/**
 * The launcher feed (website/README.md "Launcher feed"; logic in plugins/chaos/launcher_feed_lib.php):
 *   GET https://<site>/chaos_launcher_feed.php   -> JSON with the latest news and the changelog, pt-BR and en.
 * Public, no account data, cached for 5 minutes. The launcher reads it with the key "feed" of launcher.json.
 */
if (!in_array($_SERVER['REQUEST_METHOD'] ?? '', array('GET', 'HEAD'), true)) {
	http_response_code(405);
	header('Allow: GET, HEAD');
	header('Content-Type: application/json; charset=utf-8');
	exit('{"ok":false,"error":"method"}');
}
chdir(__DIR__);
require_once __DIR__ . '/engine/init.php';
require_once __DIR__ . '/plugins/chaos/launcher_feed_lib.php';
while (ob_get_level() > 0) {
	ob_end_clean();
}
header_remove('Set-Cookie');
header('Content-Type: application/json; charset=utf-8');
header('X-Content-Type-Options: nosniff');
try {
	$chaosFeed = chaos_launcher_feed_cached(static function () {
		return chaos_launcher_feed_live(time());
	}, sys_get_temp_dir() . '/chaos_launcher_feed_' . substr(md5(__DIR__), 0, 8) . '.json',
		chaos_launcher_feed_limits()['ttl'], time());
	header('Cache-Control: public, max-age=' . chaos_launcher_feed_limits()['ttl']);
} catch (Throwable $e) {
	error_log('[chaos launcher feed] ' . $e->getMessage());
	http_response_code(500);
	header('Cache-Control: no-store');
	$chaosFeed = '{"ok":false,"error":"server"}';
}
echo $_SERVER['REQUEST_METHOD'] === 'HEAD' ? '' : $chaosFeed;
