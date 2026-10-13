<?php
// php website/tests/chaos_pay_test.php : the donation flow (Pix through Mercado Pago, PayPal, the mock provider)
// against an in-memory SQLite database and a fake HTTP transport; no network, no credentials. Exit status 0 when every
// check passes. Covers: prices from one USD table (Pix = USD x 5, integer cents), the order rules, the charge requests
// (fields, idempotency keys, donation wording), webhook signatures (good, bad, missing, unknown id), the re-fetch
// before crediting with amount / currency / reference checks, idempotency, expiry, cancel, refunds and chargebacks
// before and after crediting, PayPal capture, the mock provider, the settings loader.
$GLOBALS['config'] = array('chaos' => array('server_data' => __DIR__ . '/../../server/data'));
require __DIR__ . '/../overlay/plugins/chaos/lib.php';
require __DIR__ . '/../overlay/plugins/chaos/pay/bootstrap.php';

$failed = 0;
function check(bool $ok, string $what): void {
	global $failed;
	if (!$ok) {
		$failed++;
		echo "FAIL: $what\n";
	}
}

require __DIR__ . '/chaos_pay_test_db.php';
function fresh_db(): ChaosPayPdo {
	return chaos_pay_test_db();
}
function order_row(ChaosPayDb $db, int $id): array {
	return $db->rows('SELECT o.*, p.* FROM chaos_coin_orders o JOIN chaos_coin_payments p ON p.order_id = o.id WHERE o.id = ?', array($id))[0] ?? array();
}

// ------------------------------------------------------------------ fake HTTP: queued answers, recorded requests
final class FakeHttp {
	public array $requests = array();
	public array $answers = array();
	public function __invoke(string $method, string $url, array $headers, ?string $body): array {
		$this->requests[] = array('method' => $method, 'url' => $url, 'headers' => $headers, 'body' => $body);
		foreach ($this->answers as $i => $a) {
			if ($a[0] === $method && strpos($url, $a[1]) !== false) {
				if (empty($a[3])) {
					unset($this->answers[$i]);
				}
				return array($a[2][0], is_string($a[2][1]) ? $a[2][1] : json_encode($a[2][1]));
			}
		}
		return array(500, '{"message":"no fake answer"}');
	}
	public function on(string $method, string $urlPart, int $code, $body, bool $keep = false): void {
		$this->answers[] = array($method, $urlPart, array($code, $body), $keep);
	}
	public function last(): array { return end($this->requests) ?: array(); }
	public function header(array $req, string $name): string {
		foreach ($req['headers'] as $h) {
			if (stripos($h, $name . ':') === 0) { return trim(substr($h, strlen($name) + 1)); }
		}
		return '';
	}
}

$now = 1800000000;
$clock = static function () use (&$now) { return $now; };
$logs = array();
$logger = static function (string $l) use (&$logs) { $logs[] = $l; };
$packs = chaos_pay_packs();
$pay = chaos_pay_config();

// ------------------------------------------------------------------ prices and texts
check($pay['brl_per_usd'] === 5, 'BRL per USD from the server config');
foreach ($packs as $k => $p) {
	check(is_int($p['usd_cents']) && $p['usd_cents'] > 0, "$k usd_cents");
	check(ChaosPayService::priceCents($p, 'pix', $pay) === $p['usd_cents'] * 5, "$k Pix = USD x 5");
	check(ChaosPayService::priceCents($p, 'paypal', $pay) === $p['usd_cents'], "$k PayPal = USD");
}
check(ChaosPayService::priceCents(array('usd_cents' => 1000), 'pix', $pay) === 5000, '10.00 USD = R$ 50,00');
check(ChaosPayService::priceCents($packs['coins250'], 'card', $pay) === null, 'no third method');
check(ChaosPayService::money(7495, 'BRL') === 'R$ 74,95' && ChaosPayService::money(123456, 'BRL') === 'R$ 1.234,56', 'BRL text');
check(ChaosPayService::money(1499, 'USD') === 'US$ 14.99' && ChaosPayService::money(100000, 'USD') === 'US$ 1,000.00', 'USD text');
check(ChaosPayUtil::cents('24.95') === 2495 && ChaosPayUtil::cents(74.95) === 7495 && ChaosPayUtil::cents('5') === 500 && ChaosPayUtil::cents('0.1') === 10, 'cents parsing');
check(ChaosPayUtil::decimal(7495) === '74.95' && ChaosPayUtil::decimal(5) === '0.05', 'decimal');
check(ChaosPayUtil::crc16('123456789') === '29B1', 'CRC16-CCITT check value');
[$en, $pt] = ChaosPayService::thanks(975);
check($en === 'Thank you for your voluntary donation! You received 975 Chaos Coins as a thank-you.', 'thanks en');
check($pt === 'Obrigado pela sua doação voluntária! Você recebeu 975 Chaos Coins como agradecimento.', 'thanks pt');
check(strpos(ChaosPayService::NOTICE_PT, 'Ninguém é obrigado a doar') !== false && strpos(ChaosPayService::NOTICE_EN, 'fully playable for free') !== false, 'notices');
$lua = (string)file_get_contents(__DIR__ . '/../../server/data/scripts/chaos/shop_payments_core.lua');
check(strpos($lua, ChaosPayService::NOTICE_EN) !== false && strpos($lua, ChaosPayService::NOTICE_PT) !== false, 'same notices as the game server');

// ------------------------------------------------------------------ Mercado Pago: order, charge, webhook
$db = fresh_db();
$mpHttp = new FakeHttp();
$mp = new ChaosPayMercadoPago('TEST-TOKEN', 'whsecret', '', 0, $mpHttp, $clock);
$svc = new ChaosPayService($db, array('pix' => $mp), $packs, $pay, array('site_url' => 'https://site.example.invalid', 'reconcile_seconds' => 60), $clock, $logger);
$r = $svc->createOrder(77, 'coins750', 'pix');
check($r['ok'] && !$r['reused'], 'order created');
$id = $r['order_id'];
$o = order_row($db, $id);
check($o['status'] === 'pending' && (int)$o['amount_cents'] === 7495 && $o['currency'] === 'BRL', 'pending row with the server price');
check((int)$o['coins'] + (int)$o['bonus'] + (int)$o['first_bonus'] === 1575, 'credit preview with the first donation bonus (double)');
check($svc->createOrder(77, 'coins750', 'pix')['order_id'] === $id && $svc->createOrder(77, 'coins750', 'pix')['reused'], 'same pack: the open order');
$x = $svc->createOrder(77, 'coins4000', 'pix');
check(!$x['ok'] && $x['order_id'] === $id, 'one open order at a time');
check(!$svc->createOrder(77, 'coins750', 'paypal')['ok'], 'no provider for PayPal here');
check(!$svc->createOrder(77, 'nope', 'pix')['ok'], 'unknown pack');

$mpHttp->on('POST', '/v1/payments', 201, array('id' => 123456789, 'status' => 'pending', 'date_of_expiration' => '2027-01-15T08:30:00.000-03:00',
	'point_of_interaction' => array('transaction_data' => array('qr_code' => '00020126580014br.gov.bcb.pix', 'qr_code_base64' => 'iVBORw0KGgo=', 'ticket_url' => 'https://www.mercadopago.com.br/payments/123456789/ticket'))));
check($svc->makeCharge($id), 'charge made');
$req = $mpHttp->last();
$body = json_decode($req['body'], true);
check($req['url'] === 'https://api.mercadopago.com/v1/payments' && $req['method'] === 'POST', 'POST /v1/payments');
check($mpHttp->header($req, 'Authorization') === 'Bearer TEST-TOKEN', 'bearer token');
check($mpHttp->header($req, 'X-Idempotency-Key') === $o['token'], 'idempotency key = order token');
check($body['payment_method_id'] === 'pix' && $body['transaction_amount'] === 74.95 && $body['external_reference'] === $o['token'], 'Pix body');
check($body['payer']['email'] === 'player@example.invalid', 'payer e-mail passed through');
check($body['date_of_expiration'] === gmdate('Y-m-d\TH:i:s', $now + 1800) . '.000+00:00', 'expiry 30 minutes, ISO 8601');
check(strpos($body['description'], 'Voluntary donation') !== false && strpos($body['description'], 'fully playable for free') !== false, 'donation wording in the description');
$o = order_row($db, $id);
check($o['status'] === 'open' && $o['qr_code'] === '00020126580014br.gov.bcb.pix' && $o['psp_id'] === '123456789' && $o['psp'] === 'mercadopago', 'open with the Pix code');
check((int)$o['expires'] === strtotime('2027-01-15T08:30:00.000-03:00'), 'expiry from the answer');
check(!in_array('player@example.invalid', array_map('strval', $o), true), 'e-mail not stored');
check(strpos(implode("\n", $logs), 'player@example.invalid') === false, 'e-mail not logged');

// signatures
$sign = static function (string $dataId, string $reqId, string $ts, string $secret = 'whsecret'): array {
	$v1 = hash_hmac('sha256', "id:$dataId;request-id:$reqId;ts:$ts;", $secret);
	return array('x-signature' => "ts=$ts,v1=$v1", 'x-request-id' => $reqId);
};
$payment = static function (string $status, $amount = 74.95, string $currency = 'BRL', string $ref = null, array $extra = array()) use ($o): array {
	return array_merge(array('id' => 123456789, 'status' => $status, 'status_detail' => '', 'transaction_amount' => $amount, 'currency_id' => $currency,
		'external_reference' => $ref ?? $o['token'], 'payment_method_id' => 'pix', 'transaction_amount_refunded' => 0), $extra);
};
$q = 'psp=mercadopago&data.id=123456789&type=payment';
$res = $svc->webhook('mercadopago', array('x-signature' => 'ts=1,v1=abc', 'x-request-id' => 'r1'), '{}', $q);
check($res[0] === 401, 'bad signature refused');
$res = $svc->webhook('mercadopago', array(), '{}', $q);
check($res[0] === 401, 'missing signature refused');
$res = $svc->webhook('mercadopago', $sign('123456789', 'r1', '1800000000', 'other'), '{}', $q);
check($res[0] === 401, 'signature with another secret refused');
check(order_row($db, $id)['status'] === 'open', 'nothing changed by refused calls');
$res = $svc->webhook('mercadopago', $sign('999', 'r2', '1800000000'), '{}', 'psp=mercadopago&data.id=999&type=payment');
check($res[0] === 404, 'unknown payment id refused');
$res = $svc->webhook('nobody', array(), '{}', '');
check($res[0] === 404, 'unknown provider');

// amount / currency / reference checks on the re-fetched payment
$mpHttp->on('GET', '/v1/payments/123456789', 200, $payment('approved', 7.49));
$res = $svc->webhook('mercadopago', $sign('123456789', 'r3', '1800000000'), '{"type":"payment"}', $q);
check($res[0] === 200 && order_row($db, $id)['status'] === 'open', 'wrong amount: not paid');
check(strpos(order_row($db, $id)['note'], 'mismatch') === 0, 'mismatch noted');
$mpHttp->on('GET', '/v1/payments/123456789', 200, $payment('approved', 74.95, 'USD'));
$svc->webhook('mercadopago', $sign('123456789', 'r4', '1800000000'), '{}', $q);
check(order_row($db, $id)['status'] === 'open', 'wrong currency: not paid');
$mpHttp->on('GET', '/v1/payments/123456789', 200, $payment('approved', 74.95, 'BRL', 'coc-1-2-other'));
$svc->webhook('mercadopago', $sign('123456789', 'r5', '1800000000'), '{}', $q);
check(order_row($db, $id)['status'] === 'open', 'wrong reference: not paid');
$mpHttp->on('GET', '/v1/payments/123456789', 200, $payment('approved', 74.95, 'BRL', null, array('payment_method_id' => 'visa')));
$svc->webhook('mercadopago', $sign('123456789', 'r5b', '1800000000'), '{}', $q);
check(order_row($db, $id)['status'] === 'open', 'not a Pix payment: not paid');
$mpHttp->on('GET', '/v1/payments/123456789', 200, $payment('pending'));
$svc->webhook('mercadopago', $sign('123456789', 'r6', '1800000000'), '{}', $q);
check(order_row($db, $id)['status'] === 'open', 'pending stays open');
$mpHttp->on('GET', '/v1/payments/123456789', 200, $payment('approved', 74.95, 'BRL', null,
	array('payer' => array('id' => '555', 'email' => 'Payer@Example.com', 'identification' => array('type' => 'CPF', 'number' => '123.456.789-09')))), true);
$res = $svc->webhook('mercadopago', $sign('123456789', 'r7', '1800000000'), '{}', $q);
check($res[0] === 200 && $res[1] === 'paid' && order_row($db, $id)['status'] === 'paid', 'approved: paid');
// the payer of a confirmed donation as a SHA-256 (creator codes and referrals: same payer checks)
$payers = $db->rows('SELECT order_id, account_id, payer_hash FROM chaos_pay_payers', array());
check(count($payers) === 1 && (int)$payers[0]['order_id'] === $id && (int)$payers[0]['account_id'] === (int)order_row($db, $id)['account_id'], 'payer recorded for the order and account');
check($payers[0]['payer_hash'] === ChaosPayService::payerHash('mercadopago', 'doc:cpf:12345678909'), 'hash of the payer document (Pix: CPF)');
check(strlen($payers[0]['payer_hash']) === 64 && strpos($payers[0]['payer_hash'], '12345678909') === false, 'never the raw document');
check(ChaosPayService::payerHash('mercadopago', 'doc:cpf:1', 'salt') !== ChaosPayService::payerHash('mercadopago', 'doc:cpf:1'), 'the salt changes the hash');
$res = $svc->webhook('mercadopago', $sign('123456789', 'r8', '1800000001'), '{}', $q);
check($res[1] === 'already' && order_row($db, $id)['status'] === 'paid', 'repeated webhook changes nothing');
check(count($db->rows('SELECT order_id FROM chaos_pay_payers', array())) === 1, 'one payer row per order');
check(ChaosPayMercadoPago::payerOf(array('payer' => array('id' => 9))) === 'id:9' && ChaosPayMercadoPago::payerOf(array()) === '', 'MP payer id fallback');
$ppState = ChaosPayPayPal::normalize(array('status' => 'COMPLETED', 'payer' => array('payer_id' => 'PAYERX', 'email_address' => 'a@b.c')));
check($ppState['payer'] === 'id:PAYERX', 'PayPal payer id');
// the signature manifest without x-request-id, and an alphanumeric id in lower case
check(ChaosPayMercadoPago::manifest('ABC12', '', '9') === 'id:abc12;ts:9;', 'manifest rules');
check(ChaosPayMercadoPago::queryValue('a=1&data.id=55&type=payment', 'data.id') === '55', 'data.id from the raw query');
// tolerance on the timestamp (optional)
$mpT = new ChaosPayMercadoPago('T', 'whsecret', '', 300, $mpHttp, $clock);
check(!$mpT->webhook($sign('123456789', 'r', '1700000000'), '{}', $q)['ok'], 'old timestamp refused when a tolerance is set');
check($mpT->webhook($sign('123456789', 'r', (string)($now * 1000)), '{}', $q)['ok'], 'millisecond timestamp accepted');

// refund before the game server credited it
$mpHttp->answers = array();
$mpHttp->on('GET', '/v1/payments/123456789', 200, $payment('refunded', 74.95, 'BRL', null, array('transaction_amount_refunded' => 74.95)));
$svc->webhook('mercadopago', $sign('123456789', 'r9', '1800000000'), '{}', $q);
check(order_row($db, $id)['status'] === 'refunded', 'refunded before crediting');

// a second order: credited, then charged back -> flagged once for the game server and staff
$now += 4000;
$r2 = $svc->createOrder(77, 'coins250', 'pix');
$id2 = $r2['order_id'];
$mpHttp->on('POST', '/v1/payments', 201, array('id' => 222, 'status' => 'pending', 'point_of_interaction' => array('transaction_data' => array('qr_code' => 'PIX2'))));
$svc->makeCharge($id2);
$o2 = order_row($db, $id2);
check((int)$o2['amount_cents'] === 2495, 'R$ 24,95 for the 4.99 USD pack');
$db->exec("UPDATE chaos_coin_orders SET status = 'credited' WHERE id = ?", array($id2));
$mpHttp->on('GET', '/v1/payments/222', 200, array('id' => 222, 'status' => 'charged_back', 'transaction_amount' => 24.95, 'currency_id' => 'BRL',
	'external_reference' => $o2['token'], 'payment_method_id' => 'pix'), true);
$res = $svc->webhook('mercadopago', $sign('222', 'r10', '1800000000'), '{}', 'data.id=222&type=payment');
$o2 = order_row($db, $id2);
check($res[1] === 'reversal' && $o2['status'] === 'credited' && $o2['reversal'] === 'charged_back' && (int)$o2['reversal_done'] === 0, 'chargeback after crediting flagged');
check($svc->webhook('mercadopago', $sign('222', 'r11', '1800000000'), '{}', 'data.id=222&type=payment')[1] === 'already', 'flagged once');

// expiry: an open order past its time is checked once more, then expired and cancelled at the provider
$now += 4000;
$id3 = $svc->createOrder(77, 'coins250', 'pix')['order_id'];
$mpHttp->on('POST', '/v1/payments', 201, array('id' => 333, 'status' => 'pending', 'point_of_interaction' => array('transaction_data' => array('qr_code' => 'PIX3'))));
$svc->makeCharge($id3);
$t3 = order_row($db, $id3)['token'];
$mpHttp->on('GET', '/v1/payments/333', 200, array('id' => 333, 'status' => 'pending', 'transaction_amount' => 24.95, 'currency_id' => 'BRL', 'external_reference' => $t3, 'payment_method_id' => 'pix'), true);
$now += 1800 + 61;
$mpHttp->on('PUT', '/v1/payments/333', 200, array('id' => 333, 'status' => 'cancelled'));
$st = $svc->runOnce();
check(order_row($db, $id3)['status'] === 'expired' && $st['expired'] === 1, 'expired');
$svc->runOnce();
check((int)order_row($db, $id3)['cancel_sent'] === 1, 'cancel sent once');
$puts = array_filter($mpHttp->requests, static function ($q) { return $q['method'] === 'PUT'; });
check(count($puts) === 1 && json_decode(end($puts)['body'], true)['status'] === 'cancelled', 'PUT status cancelled');
// a Pix paid at the last second still counts
$mpHttp->answers = array();
$mpHttp->on('GET', '/v1/payments/333', 200, array('id' => 333, 'status' => 'approved', 'transaction_amount' => 24.95, 'currency_id' => 'BRL', 'external_reference' => $t3, 'payment_method_id' => 'pix'));
$svc->webhook('mercadopago', $sign('333', 'r12', '1800000000'), '{}', 'data.id=333&type=payment');
check(order_row($db, $id3)['status'] === 'paid', 'late approval after expiry is still paid');

// rate limit: six orders an hour
$now += 4000;
$db2 = fresh_db();
$svc2 = new ChaosPayService($db2, array('pix' => $mp), $packs, $pay, array(), $clock, $logger);
for ($i = 0; $i < 6; $i++) {
	$k = $svc2->createOrder(77, 'coins250', 'pix');
	$svc2->cancelOrder(77, $k['order_id']);
}
$k = $svc2->createOrder(77, 'coins250', 'pix');
check(!$k['ok'] && strpos($k['error'], 'last hour') !== false, 'hourly limit');
check(!$svc2->cancelOrder(78, 1), 'another account cannot cancel');
// payer e-mail: account without one and no pattern -> the order fails without a call
$k = (new ChaosPayService($db2, array('pix' => $mp), $packs, $pay, array(), static function () use ($now) { return $now + 9000; }, $logger))->createOrder(78, 'coins250', 'pix');
$before = count($mpHttp->requests);
$svc2->makeCharge($k['order_id']);
check(order_row($db2, $k['order_id'])['status'] === 'failed' && count($mpHttp->requests) === $before, 'no payer e-mail: failed, no call');
// amount changed in the config after the order: refused before any call
$db2->exec("UPDATE chaos_coin_payments SET amount_cents = 1 WHERE order_id = 1");
$db2->exec("UPDATE chaos_coin_orders SET status = 'pending' WHERE id = 1");
$svc2->makeCharge(1);
check(order_row($db2, 1)['status'] === 'failed' && strpos(order_row($db2, 1)['note'], 'amount') !== false, 'row amount must match the config');

// ------------------------------------------------------------------ PayPal
$now += 9000;
$db3 = fresh_db();
$ppHttp = new FakeHttp();
$pp = new ChaosPayPayPal('CID', 'CSECRET', 'WH-1', 'sandbox', 'DONATION', 'Cinders of Chaos', $ppHttp, $clock);
$svc3 = new ChaosPayService($db3, array('paypal' => $pp), $packs, $pay, array('site_url' => 'https://site.example.invalid/'), $clock, $logger);
$ppHttp->on('POST', '/v1/oauth2/token', 200, array('access_token' => 'A21', 'expires_in' => 32000), true);
$pid = $svc3->createOrder(77, 'coins1500', 'paypal')['order_id'];
$ppHttp->on('POST', '/v2/checkout/orders', 201, array('id' => '5O190127TN364715T', 'status' => 'PAYER_ACTION_REQUIRED',
	'links' => array(array('rel' => 'self', 'href' => 'x'), array('rel' => 'payer-action', 'href' => 'https://www.sandbox.paypal.com/checkoutnow?token=5O190127TN364715T'))));
check($svc3->makeCharge($pid), 'PayPal order made');
$req = end($ppHttp->requests);
$b = json_decode($req['body'], true);
$po = order_row($db3, $pid);
check($req['url'] === 'https://api-m.sandbox.paypal.com/v2/checkout/orders' && $ppHttp->header($req, 'PayPal-Request-Id') === $po['token'], 'create request and its request id');
check($ppHttp->header($req, 'Authorization') === 'Bearer A21', 'OAuth token used');
check($ppHttp->header($ppHttp->requests[0], 'Authorization') === 'Basic ' . base64_encode('CID:CSECRET'), 'client credentials');
$u = $b['purchase_units'][0];
check($b['intent'] === 'CAPTURE' && $u['amount']['value'] === '29.99' && $u['amount']['currency_code'] === 'USD', 'USD amount from the table');
check($u['custom_id'] === $po['token'] && $u['items'][0]['category'] === 'DONATION' && $u['items'][0]['quantity'] === '1', 'donation item');
check(strpos($u['items'][0]['name'], 'voluntary donation') !== false && strpos($u['description'], 'Voluntary donation') !== false, 'donation wording at PayPal');
check($b['payment_source']['paypal']['experience_context']['return_url'] === 'https://site.example.invalid/page.php?plugin=chaos&p=coins&order=' . $pid . '&done=1', 'return url');
check($b['payment_source']['paypal']['experience_context']['shipping_preference'] === 'NO_SHIPPING', 'no shipping');
$po = order_row($db3, $pid);
check($po['status'] === 'open' && strpos($po['pay_url'], 'checkoutnow') !== false && $po['qr_code'] === '', 'approval link stored');
$ppOrder = static function (string $status, string $capStatus = '', string $value = '29.99', array $refunds = array()) use ($po): array {
	$o = array('id' => '5O190127TN364715T', 'status' => $status, 'purchase_units' => array(array('custom_id' => $po['token'],
		'amount' => array('currency_code' => 'USD', 'value' => $value))));
	if ($capStatus !== '') {
		$o['purchase_units'][0]['payments'] = array('captures' => array(array('id' => '3C679366HH908993F', 'status' => $capStatus, 'custom_id' => $po['token'],
			'amount' => array('currency_code' => 'USD', 'value' => $value))), 'refunds' => $refunds);
	}
	return $o;
};
$ppHeaders = array('paypal-auth-algo' => 'SHA256withRSA', 'paypal-cert-url' => 'https://api.paypal.com/cert.pem', 'paypal-transmission-id' => 'T1',
	'paypal-transmission-sig' => 'SIG', 'paypal-transmission-time' => gmdate('Y-m-d\TH:i:s\Z', $now));
$event = '{"id":"WH-EV-1","event_type":"CHECKOUT.ORDER.APPROVED","resource":{"id":"5O190127TN364715T"}}';
$res = $svc3->webhook('paypal', array(), $event, 'psp=paypal');
check($res[0] === 401, 'PayPal call without transmission headers refused');
$ppHttp->on('POST', '/v1/notifications/verify-webhook-signature', 200, array('verification_status' => 'FAILURE'));
$res = $svc3->webhook('paypal', $ppHeaders, $event, 'psp=paypal');
check($res[0] === 401 && order_row($db3, $pid)['status'] === 'open', 'FAILURE verification refused');
$verifyReq = end($ppHttp->requests);
check(strpos($verifyReq['body'], '"webhook_event":' . $event) !== false && strpos($verifyReq['body'], '"webhook_id":"WH-1"') !== false, 'event verified exactly as received');
$ppHttp->on('POST', '/v1/notifications/verify-webhook-signature', 200, array('verification_status' => 'SUCCESS'), true);
$ppHttp->on('GET', '/v2/checkout/orders/5O190127TN364715T', 200, $ppOrder('APPROVED'));
$ppHttp->on('POST', '/v2/checkout/orders/5O190127TN364715T/capture', 201, $ppOrder('COMPLETED', 'COMPLETED'));
$res = $svc3->webhook('paypal', $ppHeaders, $event, 'psp=paypal');
$capReq = end($ppHttp->requests);
check($res[1] === 'paid' && order_row($db3, $pid)['status'] === 'paid', 'approved, captured, paid');
check($ppHttp->header($capReq, 'PayPal-Request-Id') === $po['token'] . '-capture', 'capture request id');
check(order_row($db3, $pid)['psp_ref'] === '3C679366HH908993F', 'capture id stored');
$res = $svc3->webhook('paypal', $ppHeaders, '{"event_type":"CHECKOUT.ORDER.APPROVED","resource":{"id":"9XX0000000000000"}}', 'psp=paypal');
check($res[0] === 404, 'unknown PayPal order refused');
// refund after crediting: the refund resource points at the capture
$db3->exec("UPDATE chaos_coin_orders SET status = 'credited' WHERE id = ?", array($pid));
$ppHttp->on('GET', '/v2/checkout/orders/5O190127TN364715T', 200, $ppOrder('COMPLETED', 'PARTIALLY_REFUNDED', '29.99',
	array(array('status' => 'COMPLETED', 'amount' => array('value' => '10.00', 'currency_code' => 'USD')))));
$refundEvent = '{"event_type":"PAYMENT.CAPTURE.REFUNDED","resource":{"id":"1JU08902781691411","links":[{"rel":"up","href":"https://api.paypal.com/v2/payments/captures/3C679366HH908993F"}]}}';
$res = $svc3->webhook('paypal', $ppHeaders, $refundEvent, 'psp=paypal');
$po = order_row($db3, $pid);
check($res[1] === 'reversal' && $po['reversal'] === 'refunded' && (int)$po['reversal_cents'] === 1000, 'partial refund after crediting flagged with its amount');
check(ChaosPayPayPal::hints(json_decode('{"event_type":"CUSTOMER.DISPUTE.CREATED","resource":{"dispute_id":"PP-D-1","disputed_transactions":[{"seller_transaction_id":"3C679366HH908993F"}]}}', true))
	=== array(array('by' => 'psp_ref', 'id' => '3C679366HH908993F', 'dispute' => 'PP-D-1')), 'dispute event names the capture');
check(ChaosPayPayPal::hints(array('event_type' => 'PAYMENT.CAPTURE.COMPLETED', 'resource' => array('id' => 'C1', 'supplementary_data' => array('related_ids' => array('order_id' => 'O1')))))
	=== array(array('by' => 'psp_id', 'id' => 'O1')), 'capture event names the order');
// an order approved after the player cancelled it is not captured
$now += 4000;
$pid2 = $svc3->createOrder(77, 'coins250', 'paypal')['order_id'];
$ppHttp->on('POST', '/v2/checkout/orders', 201, array('id' => '7AB00000000000000', 'status' => 'PAYER_ACTION_REQUIRED', 'links' => array(array('rel' => 'payer-action', 'href' => 'https://x/y'))));
$svc3->makeCharge($pid2);
$svc3->cancelOrder(77, $pid2);
$ppHttp->on('GET', '/v2/checkout/orders/7AB00000000000000', 200, array('id' => '7AB00000000000000', 'status' => 'APPROVED',
	'purchase_units' => array(array('custom_id' => order_row($db3, $pid2)['token'], 'amount' => array('currency_code' => 'USD', 'value' => '4.99')))));
$before = count(array_filter($ppHttp->requests, static function ($q) { return strpos($q['url'], '/capture') !== false; }));
check($svc3->sync($pid2) === 'not captured' && order_row($db3, $pid2)['status'] === 'cancelled', 'cancelled order not captured');
check(count(array_filter($ppHttp->requests, static function ($q) { return strpos($q['url'], '/capture') !== false; })) === $before, 'no capture call');

// ------------------------------------------------------------------ mock provider
$now += 9000;
$state = tempnam(sys_get_temp_dir(), 'chaos_pay_mock_test');
$db4 = fresh_db();
$mockPix = new ChaosPayMock('pix', 20, $state, 'mocksecret', 'https://m.example.invalid/', $clock);
$mockPp = new ChaosPayMock('paypal', 20, $state, 'mocksecret', 'https://m.example.invalid/', $clock);
$svc4 = new ChaosPayService($db4, array('pix' => $mockPix, 'paypal' => $mockPp), $packs, $pay, array('reconcile_seconds' => 2), $clock, $logger);
$m1 = $svc4->createOrder(77, 'starter', 'pix')['order_id'];
$svc4->runOnce();
$mo = order_row($db4, $m1);
check($mo['status'] === 'open' && strpos($mo['qr_code'], '0014br.gov.bcb.pix') !== false, 'mock Pix code');
check(substr($mo['qr_code'], -4) === ChaosPayUtil::crc16(substr($mo['qr_code'], 0, -4)), 'mock Pix code has a valid CRC');
check(strpos($mo['qr_code'], '5405' . '14.95') !== false, 'mock Pix amount R$ 14,95 (2.99 USD x 5)');
$now += 10;
$svc4->runOnce();
check(order_row($db4, $m1)['status'] === 'open', 'not before approveAfter');
$now += 15;
$svc4->runOnce();
check(order_row($db4, $m1)['status'] === 'paid', 'mock Pix approved by itself');
$db4->exec("UPDATE chaos_coin_orders SET status = 'credited' WHERE id = ?", array($m1));
check(!$svc4->createOrder(77, 'starter', 'paypal')['ok'], 'starter once per account');
$m2 = $svc4->createOrder(77, 'coins250', 'paypal')['order_id'];
$svc4->runOnce();
check(strpos(order_row($db4, $m2)['pay_url'], 'https://m.example.invalid/MOCK-PAYPAL-') === 0, 'mock PayPal link');
$now += 30;
$svc4->runOnce();
check(order_row($db4, $m2)['status'] === 'paid' && order_row($db4, $m2)['psp_ref'] !== '', 'mock PayPal approved and captured');
$db4->exec("UPDATE chaos_coin_orders SET status = 'credited' WHERE id = ?", array($m2));
check($mockPp->reverse(order_row($db4, $m2)['psp_id'], 'refunded') && $svc4->sync($m2) === 'reversal', 'mock refund after crediting flagged');
$mb = '{"id":"' . order_row($db4, $m1)['psp_id'] . '"}';
check($svc4->webhook('mock-pix', array('x-mock-signature' => hash_hmac('sha256', $mb, 'mocksecret')), $mb, '')[0] === 200, 'mock webhook signed');
check($svc4->webhook('mock-pix', array('x-mock-signature' => '00'), $mb, '')[0] === 401, 'mock webhook bad signature');
@unlink($state);

// ------------------------------------------------------------------ settings: environment over the file, no secrets in the repo
$f = tempnam(sys_get_temp_dir(), 'chaos_pay_env');
file_put_contents($f, "# comment\nCHAOS_PAY_PIX_PROVIDER=mock\nCHAOS_MP_ACCESS_TOKEN=\"from-file\"\nCHAOS_PAYPAL_ENV=live # note\n");
putenv('CHAOS_MP_ACCESS_TOKEN=from-env');
$s = chaos_pay_settings($f);
putenv('CHAOS_MP_ACCESS_TOKEN');
check($s['CHAOS_PAY_PIX_PROVIDER'] === 'mock' && $s['CHAOS_MP_ACCESS_TOKEN'] === 'from-env' && $s['CHAOS_PAYPAL_ENV'] === 'live', 'settings file and environment');
check(array_keys(chaos_pay_providers($s, null, null, 'http://127.0.0.1:8095')) === array('pix'), 'providers from the settings');
// the mock never runs on a public site: only localhost / 127.0.0.1 / ::1, or with CHAOS_PAY_ALLOW_MOCK=1
$sm = $s + array();
$sm['CHAOS_PAY_PAYPAL_PROVIDER'] = 'mock';
$errorLog = ini_set('error_log', DIRECTORY_SEPARATOR === '/' ? '/dev/null' : 'NUL'); // the refusals are logged
check(chaos_pay_providers($sm, null, null, 'https://www.example.org') === array(), 'mock refused on a public site');
check(chaos_pay_providers($sm, null, null, '') === array(), 'mock refused without a site address');
check(chaos_pay_providers($sm, null, null, 'http://evil.localhost.example.org') === array(), 'mock refused on a look-alike host');
check(array_keys(chaos_pay_providers($sm, null, null, 'http://localhost')) === array('pix', 'paypal'), 'mock on localhost');
check(array_keys(chaos_pay_providers($sm, null, null, 'http://[::1]:8080/')) === array('pix', 'paypal'), 'mock on ::1');
$sm['CHAOS_PAY_ALLOW_MOCK'] = '1';
check(array_keys(chaos_pay_providers($sm, null, null, 'https://demo.example.org')) === array('pix', 'paypal'), 'mock with CHAOS_PAY_ALLOW_MOCK=1');
$sm['CHAOS_PAY_ALLOW_MOCK'] = '';
$sm['CHAOS_PAY_SITE_URL'] = 'https://www.example.org';
check(chaos_pay_providers($sm) === array(), 'mock refused: site address from the settings');
ini_set('error_log', (string)$errorLog);
// Mercado Pago: a signature older than 600 s is refused unless the setting says otherwise
$smp = $s + array();
$smp['CHAOS_PAY_PIX_PROVIDER'] = 'mercadopago';
$smp['CHAOS_MP_SIGNATURE_TOLERANCE'] = '';
$tol = (new ReflectionProperty(ChaosPayMercadoPago::class, 'tolerance'));
$tol->setAccessible(true);
check($tol->getValue(chaos_pay_providers($smp)['pix']) === 600, 'Mercado Pago signature tolerance 600 s by default');
$smp['CHAOS_MP_SIGNATURE_TOLERANCE'] = '0';
check($tol->getValue(chaos_pay_providers($smp)['pix']) === 0, 'tolerance 0 = off when set');
@unlink($f);
$example = (string)file_get_contents(__DIR__ . '/../payments.env.example');
foreach (CHAOS_PAY_KEYS as $k) {
	check(strpos($example, $k . '=') !== false, "payments.env.example lists $k");
}
check(!preg_match('/(APP_USR-|ACCESS_TOKEN=\S|SECRET=\S|CLIENT_ID=\S)/', $example), 'no credential in the example');
check(strpos((string)file_get_contents(__DIR__ . '/../../.gitignore'), 'payments.env') !== false, 'payments.env is git-ignored');

echo $failed === 0 ? "chaos_pay_test: OK\n" : "chaos_pay_test: $failed failed\n";
exit($failed === 0 ? 0 : 1);
