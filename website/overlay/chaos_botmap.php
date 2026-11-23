<?php
/**
 * The staff's live bot map data (website/README.md "Bot live map (O727)"; logic in plugins/chaos/botmap_lib.php):
 *   GET /chaos_botmap.php            -> {"ok":true,"now":..,"bots":[..]}   our test bots, read from the game server's data/chaos_botlive
 *   GET /chaos_botmap.php?a=meta     -> {"ok":true,"now":..,"map":{..}}    where the map tiles are, their geometry, the towns
 * Staff only (admin panel account with a character of group 4+, the session of the site); anyone else gets 404 {"ok":false,"error":"not_found"},
 * the answer of a page that does not exist. Never cached; no account, password or address of anyone in it, and no player: bots only.
 */
header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store');
header('X-Content-Type-Options: nosniff');
if (!in_array($_SERVER['REQUEST_METHOD'] ?? '', array('GET', 'HEAD'), true)) {
	http_response_code(405);
	header('Allow: GET, HEAD');
	exit('{"ok":false,"error":"method"}');
}
chdir(__DIR__);
require_once __DIR__ . '/engine/init.php';
require_once __DIR__ . '/plugins/chaos/botmap_lib.php';
while (ob_get_level() > 0) {
	ob_end_clean();
}
header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store');
try {
	$chaosBotmapUser = function_exists('getSession') ? (int)getSession('user_id') : 0;
	[$chaosBotmapCode, $chaosBotmapBody] = chaos_botmap_handle($config, $chaosBotmapUser, $_GET, time());
} catch (Throwable $e) {
	error_log('[chaos botmap] ' . $e->getMessage());
	[$chaosBotmapCode, $chaosBotmapBody] = array(500, array('ok' => false, 'error' => 'server'));
}
http_response_code($chaosBotmapCode);
echo $_SERVER['REQUEST_METHOD'] === 'HEAD' ? '' : json_encode($chaosBotmapBody, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE | JSON_INVALID_UTF8_SUBSTITUTE);
