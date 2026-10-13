<?php
// php website/tests/chaos_qa_security_test.php : regressions found by the security QA of the site and the donation flow
// (php-cli with pdo_sqlite, a fake HTTP transport, no network). Exit status 0 when every check passes.
//  - Mercado Pago: a partial refund leaves the payment "approved" (status_detail partially_refunded). It must count
//    as a refund: before crediting nothing is credited, after crediting the refunded share is flagged for the game
//    server (which takes those coins back).
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

if ($failed > 0) {
	echo "chaos_qa_security_test: $failed check(s) failed\n";
	exit(1);
}
echo "chaos_qa_security_test: OK\n";
