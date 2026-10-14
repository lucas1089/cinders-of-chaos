<?php
// php website/tests/chaos_qa_security_test.php : regressions found by the security QA of the site and the donation flow
// (php-cli with pdo_sqlite, a fake HTTP transport, no network). Exit status 0 when every check passes.
//  - Mercado Pago: a partial refund leaves the payment "approved" (status_detail partially_refunded). It must count
//    as a refund: before crediting nothing is credited, after crediting the refunded share is flagged for the game
//    server (which takes those coins back).
//  - A second, larger refund (or a chargeback after a partial refund) flags the order again; credited orders are asked
//    again once a day for 180 days; PayPal webhooks are checked (certificate host, time) before any call and the token
//    is kept between requests; no localhost default for the site address; sessions end on a password change; the
//    login guard counts IPv6 by /64.
$GLOBALS['config'] = array('chaos' => array('server_data' => __DIR__ . '/../../server/data'));
require __DIR__ . '/../overlay/plugins/chaos/lib.php';
require __DIR__ . '/../overlay/plugins/chaos/pay/bootstrap.php';
require __DIR__ . '/chaos_pay_test_db.php';

$failed = 0;
function check(bool $ok, string $what): void {
	global $failed;
	if (!$ok) {
		$failed++;
		echo "FAIL: $what\n";
	}
}

// ------------------------------------------------------------------ Mercado Pago partial refund
$approved = array('id' => 555, 'status' => 'approved', 'status_detail' => 'partially_refunded', 'transaction_amount' => 24.95,
	'currency_id' => 'BRL', 'external_reference' => 'coc-x', 'payment_method_id' => 'pix', 'transaction_amount_refunded' => 10.00);
$n = ChaosPayMercadoPago::normalize($approved);
check($n['status'] === 'refunded' && $n['refunded_cents'] === 1000 && $n['amount_cents'] === 2495, 'partial refund is a refund of 10.00');
$approved['transaction_amount_refunded'] = 0;
$approved['status_detail'] = 'accredited';
check(ChaosPayMercadoPago::normalize($approved)['status'] === 'approved', 'no refund: still approved');

$now = 1800000000;
$clock = static function () use (&$now) { return $now; };
$answers = array();
$http = static function (string $method, string $url, array $headers, ?string $body) use (&$answers): array {
	foreach ($answers as $part => $answer) {
		if (strpos($method . ' ' . $url, $part) !== false) {
			return array(200, json_encode($answer));
		}
	}
	return array(500, '{}');
};
$db = chaos_pay_test_db();
$mp = new ChaosPayMercadoPago('TEST-TOKEN', 'whsecret', '', 0, $http, $clock);
$svc = new ChaosPayService($db, array('pix' => $mp), chaos_pay_packs(), chaos_pay_config(), array('site_url' => 'https://www.example.org'),
	$clock, static function (string $l): void {});
$sign = static function (string $id): array {
	return array('x-signature' => 'ts=1800000000,v1=' . hash_hmac('sha256', "id:$id;request-id:r;ts:1800000000;", 'whsecret'), 'x-request-id' => 'r');
};

// credited, then refunded in part
$id = $svc->createOrder(77, 'coins250', 'pix')['order_id'];
$answers = array('POST https://api.mercadopago.com/v1/payments' => array('id' => 555, 'status' => 'pending',
	'point_of_interaction' => array('transaction_data' => array('qr_code' => 'PIX'))));
check($svc->makeCharge($id), 'charge made');
$token = $db->rows('SELECT token FROM chaos_coin_payments WHERE order_id = ?', array($id))[0]['token'];
$db->exec("UPDATE chaos_coin_orders SET status = 'credited' WHERE id = ?", array($id));
$answers = array('GET https://api.mercadopago.com/v1/payments/555' => array('id' => 555, 'status' => 'approved',
	'status_detail' => 'partially_refunded', 'transaction_amount' => 24.95, 'currency_id' => 'BRL', 'external_reference' => $token,
	'payment_method_id' => 'pix', 'transaction_amount_refunded' => 10.00));
$res = $svc->webhook('mercadopago', $sign('555'), '{}', 'data.id=555&type=payment');
$p = $db->rows('SELECT reversal, reversal_cents FROM chaos_coin_payments WHERE order_id = ?', array($id))[0];
check($res[1] === 'reversal' && $p['reversal'] === 'refunded' && (int)$p['reversal_cents'] === 1000, 'partial refund after crediting flagged with its amount');

// paid but not yet credited, then refunded in part: not credited
$now += 7200;
$id2 = $svc->createOrder(77, 'coins250', 'pix')['order_id'];
$answers = array('POST https://api.mercadopago.com/v1/payments' => array('id' => 556, 'status' => 'pending',
	'point_of_interaction' => array('transaction_data' => array('qr_code' => 'PIX'))));
$svc->makeCharge($id2);
$token2 = $db->rows('SELECT token FROM chaos_coin_payments WHERE order_id = ?', array($id2))[0]['token'];
$answers = array('GET https://api.mercadopago.com/v1/payments/556' => array('id' => 556, 'status' => 'approved', 'transaction_amount' => 24.95,
	'currency_id' => 'BRL', 'external_reference' => $token2, 'payment_method_id' => 'pix', 'transaction_amount_refunded' => 5.00));
$svc->webhook('mercadopago', $sign('556'), '{}', 'data.id=556&type=payment');
check($db->rows('SELECT status FROM chaos_coin_orders WHERE id = ?', array($id2))[0]['status'] === 'refunded', 'partial refund before crediting: not credited');

// ------------------------------------------------------------------ a second, larger refund after crediting
// order $id: refunded 10.00 of 24.95 and flagged above; the game server handled it, then the rest is refunded
$db->exec('UPDATE chaos_coin_payments SET reversal_done = 1, reversal_coins = 100 WHERE order_id = ?', array($id));
$answers = array('GET https://api.mercadopago.com/v1/payments/555' => array('id' => 555, 'status' => 'refunded', 'transaction_amount' => 24.95,
	'currency_id' => 'BRL', 'external_reference' => $token, 'payment_method_id' => 'pix', 'transaction_amount_refunded' => 24.95));
$res = $svc->webhook('mercadopago', $sign('555'), '{}', 'data.id=555&type=payment');
$p = $db->rows('SELECT reversal, reversal_cents, reversal_done, reversal_coins FROM chaos_coin_payments WHERE order_id = ?', array($id))[0];
check($res[1] === 'reversal' && (int)$p['reversal_cents'] === 2495 && (int)$p['reversal_done'] === 0 && (int)$p['reversal_coins'] === 100,
	'a larger refund raises reversal_cents and asks the game server again (it keeps what it took)');
check($svc->webhook('mercadopago', $sign('555'), '{}', 'data.id=555&type=payment')[1] === 'already', 'the same refund again: nothing');
// a chargeback after a partial refund: the whole donation
$now += 7200;
$id4 = $svc->createOrder(77, 'coins250', 'pix')['order_id'];
$answers = array('POST https://api.mercadopago.com/v1/payments' => array('id' => 557, 'status' => 'pending',
	'point_of_interaction' => array('transaction_data' => array('qr_code' => 'PIX'))));
$svc->makeCharge($id4);
$token4 = $db->rows('SELECT token FROM chaos_coin_payments WHERE order_id = ?', array($id4))[0]['token'];
$db->exec("UPDATE chaos_coin_orders SET status = 'credited' WHERE id = ?", array($id4));
$db->exec("UPDATE chaos_coin_payments SET reversal = 'refunded', reversal_cents = 500, reversal_done = 1, reversal_coins = 50, paid_at = ? WHERE order_id = ?", array($now, $id4));
$answers = array('GET https://api.mercadopago.com/v1/payments/557' => array('id' => 557, 'status' => 'charged_back', 'transaction_amount' => 24.95,
	'currency_id' => 'BRL', 'external_reference' => $token4, 'payment_method_id' => 'pix', 'transaction_amount_refunded' => 5.00));
$res = $svc->webhook('mercadopago', $sign('557'), '{}', 'data.id=557&type=payment');
$p = $db->rows('SELECT reversal, reversal_cents, reversal_done FROM chaos_coin_payments WHERE order_id = ?', array($id4))[0];
check($res[1] === 'reversal' && $p['reversal'] === 'charged_back' && (int)$p['reversal_cents'] === 0 && (int)$p['reversal_done'] === 0,
	'a chargeback after a partial refund flags the whole donation');

// ------------------------------------------------------------------ credited orders are asked again once a day
$now += 7200;
$id5 = $svc->createOrder(77, 'coins250', 'pix')['order_id'];
$answers = array('POST https://api.mercadopago.com/v1/payments' => array('id' => 558, 'status' => 'pending',
	'point_of_interaction' => array('transaction_data' => array('qr_code' => 'PIX'))));
$svc->makeCharge($id5);
$token5 = $db->rows('SELECT token FROM chaos_coin_payments WHERE order_id = ?', array($id5))[0]['token'];
$db->exec("UPDATE chaos_coin_orders SET status = 'credited' WHERE id = ?", array($id5));
$db->exec('UPDATE chaos_coin_payments SET paid_at = ?, checked = ? WHERE order_id = ?', array($now, $now, $id5));
$answers = array('GET https://api.mercadopago.com/v1/payments/558' => array('id' => 558, 'status' => 'charged_back', 'transaction_amount' => 24.95,
	'currency_id' => 'BRL', 'external_reference' => $token5, 'payment_method_id' => 'pix', 'transaction_amount_refunded' => 0));
$svc->runOnce();
check($db->rows('SELECT reversal FROM chaos_coin_payments WHERE order_id = ?', array($id5))[0]['reversal'] === '', 'not again within a day');
$now += 86401;
$st = $svc->runOnce();
check(($st['rechecked'] ?? 0) >= 1 && $db->rows('SELECT reversal FROM chaos_coin_payments WHERE order_id = ?', array($id5))[0]['reversal'] === 'charged_back',
	'a day later: a chargeback whose webhook was lost is flagged');
$db->exec("UPDATE chaos_coin_payments SET reversal = '', checked = 0, paid_at = ? WHERE order_id = ?", array($now - 86400 * 181, $id5));
$svc->runOnce();
check($db->rows('SELECT reversal FROM chaos_coin_payments WHERE order_id = ?', array($id5))[0]['reversal'] === '', 'not after 180 days');

// ------------------------------------------------------------------ PayPal webhook: checks before any call, token kept
$ppCalls = array();
$ppHttp = static function (string $method, string $url, array $headers, ?string $body) use (&$ppCalls): array {
	$ppCalls[] = $method . ' ' . $url;
	if (strpos($url, '/v1/oauth2/token') !== false) {
		return array(200, '{"access_token":"TOK","expires_in":32000}');
	}
	return array(200, '{"verification_status":"SUCCESS"}');
};
$ppNow = 1800000000;
$ppClock = static function () use (&$ppNow) { return $ppNow; };
$cache = sys_get_temp_dir() . '/chaos_qa_pp_' . getmypid() . '.json';
@unlink($cache);
$pp = new ChaosPayPayPal('CID', 'SEC', 'WH', 'sandbox', 'DONATION', '', $ppHttp, $ppClock, $cache);
$h = array('paypal-auth-algo' => 'SHA256withRSA', 'paypal-cert-url' => 'https://api.sandbox.paypal.com/v1/notifications/certs/CERT-1',
	'paypal-transmission-id' => 'T', 'paypal-transmission-sig' => 'S', 'paypal-transmission-time' => gmdate('Y-m-d\TH:i:s\Z', $ppNow));
$ev = '{"event_type":"CHECKOUT.ORDER.APPROVED","resource":{"id":"5O190127TN364715T"}}';
check($pp->webhook(array('paypal-cert-url' => 'https://evil.example.org/cert.pem') + $h, $ev, '')['code'] === 401 && !$ppCalls, 'a certificate off paypal.com: refused, no PayPal call');
check($pp->webhook(array('paypal-cert-url' => 'https://evilpaypal.com/c') + $h, $ev, '')['code'] === 401 && !$ppCalls, 'a look-alike host: refused');
check($pp->webhook(array('paypal-cert-url' => 'http://api.paypal.com/c') + $h, $ev, '')['code'] === 401 && !$ppCalls, 'plain http: refused');
check($pp->webhook(array('paypal-transmission-time' => gmdate('Y-m-d\TH:i:s\Z', $ppNow - 86400)) + $h, $ev, '')['code'] === 401 && !$ppCalls, 'an old transmission: refused, no PayPal call');
check(!empty($pp->webhook($h, $ev, '')['ok']), 'a good call is verified');
$pp2 = new ChaosPayPayPal('CID', 'SEC', 'WH', 'sandbox', 'DONATION', '', $ppHttp, $ppClock, $cache);
check(!empty($pp2->webhook($h, $ev, '')['ok']), 'the next request too');
$tokens = count(array_filter($ppCalls, static function ($c) { return strpos($c, 'oauth2/token') !== false; }));
check($tokens === 1, 'one access token for both requests (kept in the cache file)');
check(is_file($cache) && (fileperms($cache) & 0077) === 0, 'the token file is private (600)');
@unlink($cache);
check(ChaosPayPayPal::tokenCachePath('a', 'b', 'live') !== ChaosPayPayPal::tokenCachePath('a', 'c', 'live'), 'one token file per credentials');

// ------------------------------------------------------------------ the site address is required; the mock never opens without it
$installer = (string)file_get_contents(__DIR__ . '/../install_site.sh');
check(strpos($installer, ': "${CHAOS_SITE_URL:?') !== false, 'install_site.sh refuses to run without CHAOS_SITE_URL');
$cmd = 'env -i PATH=' . escapeshellarg((string)getenv('PATH')) . ' CHAOS_DB_USER=u CHAOS_DB_NAME=n CHAOS_DB_HOST=127.0.0.1 CHAOS_DB_PORT=1 CHAOS_START_TOWNS=1 '
	. escapeshellarg(PHP_BINARY) . ' ' . escapeshellarg(__DIR__ . '/../setup/write_config.php') . ' 2>/dev/null';
$written = (string)shell_exec($cmd);
$config = array();
eval('?>' . $written);
check(array_key_exists('site_url', $config) && $config['site_url'] === '', 'no CHAOS_SITE_URL: no localhost default');
$mockOn = array_fill_keys(CHAOS_PAY_KEYS, '');
$mockOn['CHAOS_PAY_PIX_PROVIDER'] = 'mock';
$mockOn['CHAOS_PAY_PAYPAL_PROVIDER'] = 'mock';
$oldLog = ini_set('error_log', '/dev/null'); // the refusal is logged
check(chaos_pay_providers($mockOn, null, null, chaos_pay_site_url($mockOn, $config)) === array(), 'the mock stays off without a site address');
ini_set('error_log', (string)$oldLog);
$GLOBALS['config'] = array('chaos' => array('server_data' => __DIR__ . '/../../server/data'));

// ------------------------------------------------------------------ sessions end when the password changes
require __DIR__ . '/../overlay/plugins/chaos/session_guard.php';
$session = array();
check(chaos_session_password_ok($session, 7, 'pbkdf2-sha256$1$aaa$bbb'), 'first request: the mark is taken');
check(strpos((string)$session['chaos_pw'], 'pbkdf2') === false, 'the hash itself is not kept in the session');
check(chaos_session_password_ok($session, 7, 'pbkdf2-sha256$1$aaa$bbb'), 'same password: stays');
check(!chaos_session_password_ok($session, 7, 'pbkdf2-sha256$1$ccc$ddd'), 'password changed elsewhere: logged out');
$other = array('chaos_pw' => chaos_session_password_mark(8, 'x'));
check(chaos_session_password_ok($other, 7, 'y') && strpos($other['chaos_pw'], '7:') === 0, 'a mark of another account is replaced');
$plugin = (string)file_get_contents(__DIR__ . '/../overlay/plugins/chaos/plugin.php');
check(strpos($plugin, "require_once __DIR__ . '/session_guard.php';") !== false
	&& strpos($plugin, "session_guard.php") < strpos($plugin, 'chaos_legal_gate_target('), 'plugin.php runs the session guard before the pages');

// ------------------------------------------------------------------ the login guard counts IPv6 by /64
$ipPatch = (string)@file_get_contents(__DIR__ . '/../patches/znotex-chaos-ratelimit-ipv6.patch');
$fn = '';
if (preg_match('/^\+function chaos_login_guard_ip_key.*?^\+\}$/ms', $ipPatch, $m)) {
	$fn = preg_replace('/^\+/m', '', $m[0]);
}
check($fn !== '', 'the patch defines chaos_login_guard_ip_key');
if ($fn !== '') {
	eval($fn);
	check(chaos_login_guard_ip_key('2001:db8:1:2:aaaa:bbbb:cccc:dddd') === chaos_login_guard_ip_key('2001:db8:1:2::9') &&
		chaos_login_guard_ip_key('2001:db8:1:2::9') === '2001:db8:1:2::/64', 'two addresses of one /64 count together');
	check(chaos_login_guard_ip_key('2001:db8:1:3::9') !== chaos_login_guard_ip_key('2001:db8:1:2::9'), 'another /64 counts apart');
	check(chaos_login_guard_ip_key('203.0.113.7') === '203.0.113.7', 'IPv4 as it is');
}
check(substr_count($ipPatch, "+\t\$ip = chaos_login_guard_ip_key(\$ip);") === 2, 'record and lockout both use the /64 key');

if ($failed > 0) {
	echo "chaos_qa_security_test: $failed check(s) failed\n";
	exit(1);
}
echo "chaos_qa_security_test: OK\n";
