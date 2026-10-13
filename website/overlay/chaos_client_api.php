<?php
/**
 * The game client's account API (website/README.md "Client API"; logic in plugins/chaos/client_api_lib.php):
 *   POST https://<site>/chaos_client_api.php   body: JSON {"action": "login" | "state" | "create" | "logout", ...}
 * Answers JSON only, never cached. The client's URL setting is Services.account in its init.lua (docs/LAUNCH.md).
 * ZnoteX is loaded as for a page (database, settings, the plugin's hooks), so character creation runs the website
 * form's own code (engine/function/chaos_character.php).
 */
header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store');
header('X-Content-Type-Options: nosniff');
if (($_SERVER['REQUEST_METHOD'] ?? '') !== 'POST') {
	http_response_code(405);
	header('Allow: POST');
	exit('{"ok":false,"error":"method","message":"POST only."}');
}
$chaosApiRaw = (string)file_get_contents('php://input', false, null, 0, 8193);
if (strlen($chaosApiRaw) > 8192) {
	http_response_code(413);
	exit('{"ok":false,"error":"size","message":"Request too large."}');
}
$chaosApiReq = json_decode($chaosApiRaw, true);
if (!is_array($chaosApiReq)) {
	http_response_code(400);
	exit('{"ok":false,"error":"json","message":"Bad request."}');
}

chdir(__DIR__);
require_once __DIR__ . '/engine/init.php';
require_once __DIR__ . '/engine/function/chaos_character.php';
require_once __DIR__ . '/plugins/chaos/client_api_lib.php';
while (ob_get_level() > 0) {
	ob_end_clean();
}
header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store');
try {
	[$chaosApiCode, $chaosApiBody] = chaos_client_api_handle($chaosApiReq, (string)($_SERVER['REMOTE_ADDR'] ?? ''), time());
} catch (Throwable $e) {
	error_log('[chaos client api] ' . $e->getMessage());
	[$chaosApiCode, $chaosApiBody] = array(500, array('ok' => false, 'error' => 'server', 'message' => 'The website could not answer. Please try again later.'));
}
http_response_code($chaosApiCode);
echo json_encode($chaosApiBody, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);
