<?php
/**
 * Payment provider webhooks of the donation flow (website/README.md "Donations"):
 *   https://<site>/chaos_pay_webhook.php?psp=mercadopago   (Mercado Pago: Your integrations > Webhooks, topic Payments)
 *   https://<site>/chaos_pay_webhook.php?psp=paypal        (PayPal: the app's webhook, its id in CHAOS_PAYPAL_WEBHOOK_ID)
 * A call with a bad or missing signature is refused (401), an id we never charged too (404). A valid call only names
 * a charge: the charge is fetched again from the provider and checked against our order before anything changes.
 * Standalone: no session, no ZnoteX page, nothing printed but a short status word.
 */
if (($_SERVER['REQUEST_METHOD'] ?? '') !== 'POST') {
	http_response_code(405);
	exit('POST only');
}
$config = array();
require __DIR__ . '/config.local.php';
$GLOBALS['config'] = $config;
require_once __DIR__ . '/plugins/chaos/lib.php';
require_once __DIR__ . '/plugins/chaos/pay/bootstrap.php';

$headers = array();
foreach ($_SERVER as $k => $v) {
	if (strncmp($k, 'HTTP_', 5) === 0) {
		$headers[strtolower(str_replace('_', '-', substr($k, 5)))] = (string)$v;
	}
}
$body = (string)file_get_contents('php://input', false, null, 0, 65536);
$psp = preg_replace('/[^a-z-]/', '', (string)($_GET['psp'] ?? ''));
if ($psp === '') { // a provider that drops our own query string: tell it by its headers
	$psp = isset($headers['paypal-transmission-id']) ? 'paypal' : (isset($headers['x-signature']) ? 'mercadopago' : '');
}
try {
	[$code, $text] = chaos_pay_service($config)->webhook($psp, $headers, $body, (string)($_SERVER['QUERY_STRING'] ?? ''));
} catch (Throwable $e) {
	error_log('[chaos pay] webhook error: ' . $e->getMessage());
	[$code, $text] = array(500, 'error'); // the provider retries later
}
http_response_code($code);
header('Content-Type: text/plain');
echo $text;
