<?php
/**
 * PayPal (USD) through the Orders v2 REST API (checked against PayPal's published OpenAPI specifications in October 2026):
 *  - token: POST /v1/oauth2/token (client credentials, the app's client id and secret).
 *  - create: POST /v2/checkout/orders, intent CAPTURE, one purchase unit with custom_id / invoice_id = our order token,
 *    one item with category "DONATION" (CHAOS_PAYPAL_CATEGORY; PayPal may only accept the donation category from a
 *    registered charity or nonprofit in some countries: set DIGITAL_GOODS then, the item stays labelled as a voluntary
 *    donation), payment_source.paypal.experience_context (return_url, cancel_url, NO_SHIPPING, PAY_NOW), header
 *    PayPal-Request-Id = token. The payer approves on the link of rel "payer-action" (or "approve").
 *  - capture: POST /v2/checkout/orders/{id}/capture (PayPal-Request-Id = token + "-capture") once the order is APPROVED.
 *  - fetch: GET /v2/checkout/orders/{id}: CREATED / SAVED / PAYER_ACTION_REQUIRED pending, APPROVED authorized,
 *    VOIDED cancelled, COMPLETED with the capture's status (COMPLETED, PENDING, DECLINED, FAILED, REFUNDED,
 *    PARTIALLY_REFUNDED). A dispute: GET /v1/customer/disputes/{id}, checked against our capture id.
 *  - webhook: POST /v1/notifications/verify-webhook-signature with the PAYPAL-* transmission headers, the webhook id
 *    and the event exactly as received; only a SUCCESS answer is accepted, then the order is fetched again.
 *    Events: CHECKOUT.ORDER.APPROVED, PAYMENT.CAPTURE.COMPLETED / DENIED / PENDING / REFUNDED / REVERSED,
 *    CUSTOMER.DISPUTE.CREATED.
 */

require_once __DIR__ . '/Provider.php';

final class ChaosPayPayPal implements ChaosPayProvider {
	private string $base;
	private string $clientId;
	private string $secret;
	private string $webhookId;
	private string $category;
	private string $brand;
	/** @var callable */
	private $http;
	/** @var callable */
	private $now;
	private string $access = '';
	private int $accessUntil = 0;

	public function __construct(string $clientId, string $secret, string $webhookId, string $env = 'sandbox',
			string $category = 'DONATION', string $brand = '', ?callable $http = null, ?callable $now = null) {
		$this->base = $env === 'live' ? 'https://api-m.paypal.com' : 'https://api-m.sandbox.paypal.com';
		$this->clientId = $clientId;
		$this->secret = $secret;
		$this->webhookId = $webhookId;
		$this->category = in_array($category, array('DONATION', 'DIGITAL_GOODS'), true) ? $category : 'DONATION';
		$this->brand = $brand;
		$this->http = $http ?? array(ChaosPayHttp::class, 'request');
		$this->now = $now ?? 'time';
	}

	public function name(): string { return 'paypal'; }
	public function method(): string { return 'paypal'; }

	private function accessToken(): string {
		if ($this->access !== '' && ($this->now)() < $this->accessUntil) {
			return $this->access;
		}
		if ($this->clientId === '' || $this->secret === '') {
			throw new ChaosPayError('PayPal client id / secret missing (CHAOS_PAYPAL_CLIENT_ID, CHAOS_PAYPAL_CLIENT_SECRET)');
		}
		[$code, $out] = ($this->http)('POST', $this->base . '/v1/oauth2/token', array(
			'Authorization: Basic ' . base64_encode($this->clientId . ':' . $this->secret),
			'Content-Type: application/x-www-form-urlencoded', 'Accept: application/json'), 'grant_type=client_credentials');
		$d = ChaosPayUtil::json($out);
		if ($code !== 200 || empty($d['access_token'])) {
			throw new ChaosPayError('PayPal token: HTTP ' . $code);
		}
		$this->access = (string)$d['access_token'];
		$this->accessUntil = ($this->now)() + max(60, (int)($d['expires_in'] ?? 300) - 60);
		return $this->access;
	}

	/** $rawJson: a body sent exactly as given (the webhook event inside the verification request). */
	private function call(string $method, string $path, ?array $body = null, array $extra = array(), ?string $rawJson = null): array {
		$headers = array_merge(array('Authorization: Bearer ' . $this->accessToken(), 'Accept: application/json'), $extra);
		$json = $rawJson;
		if ($json === null && $body !== null) {
			$json = json_encode($body, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);
		}
		if ($json !== null) {
			$headers[] = 'Content-Type: application/json';
		}
		[$code, $out] = ($this->http)($method, $this->base . $path, $headers, $json);
		$data = ChaosPayUtil::json($out);
		if ($code < 200 || $code >= 300) {
			throw new ChaosPayError('PayPal ' . $method . ' ' . preg_replace('#/[A-Z0-9-]{8,}#', '/#', $path) . ': HTTP ' . $code .
				(isset($data['name']) ? ' ' . substr((string)$data['name'], 0, 60) : ''));
		}
		return $data;
	}

	public function create(array $order): array {
		if (($order['currency'] ?? '') !== 'USD') {
			throw new ChaosPayError('PayPal donations are in USD');
		}
		$value = ChaosPayUtil::decimal((int)$order['amount_cents']);
		$money = array('currency_code' => 'USD', 'value' => $value);
		$context = array('user_action' => 'PAY_NOW', 'shipping_preference' => 'NO_SHIPPING', 'landing_page' => 'LOGIN',
			'return_url' => (string)$order['return_url'], 'cancel_url' => (string)$order['cancel_url']);
		if ($this->brand !== '') {
			$context['brand_name'] = substr($this->brand, 0, 127);
		}
		$body = array(
			'intent' => 'CAPTURE',
			'purchase_units' => array(array(
				'reference_id' => 'order-' . (int)$order['order_id'],
				'custom_id' => (string)$order['token'],
				'invoice_id' => (string)$order['token'],
				'description' => substr((string)$order['description'], 0, 127),
				'amount' => $money + array('breakdown' => array('item_total' => $money)),
				'items' => array(array(
					'name' => substr((string)$order['title'], 0, 127),
					'description' => substr((string)$order['description'], 0, 127),
					'quantity' => '1',
					'unit_amount' => $money,
					'category' => $this->category,
				)),
			)),
			'payment_source' => array('paypal' => array('experience_context' => $context)),
		);
		$o = $this->call('POST', '/v2/checkout/orders', $body,
			array('PayPal-Request-Id: ' . $order['token'], 'Prefer: return=representation'));
		$url = '';
		foreach ((array)($o['links'] ?? array()) as $l) {
			if (in_array($l['rel'] ?? '', array('payer-action', 'approve'), true)) {
				$url = (string)$l['href'];
			}
		}
		if (empty($o['id']) || $url === '') {
			throw new ChaosPayError('PayPal answered without an approval link');
		}
		return array('psp_id' => (string)$o['id'], 'psp_ref' => '', 'qr_code' => '', 'qr_image' => '', 'pay_url' => $url,
			'expires' => (int)$order['expires'], 'psp_status' => (string)($o['status'] ?? ''));
	}

	public static function normalize(array $o): array {
		$pu = $o['purchase_units'][0] ?? array();
		$capture = $pu['payments']['captures'][0] ?? array();
		$refunded = 0;
		foreach ((array)($pu['payments']['refunds'] ?? array()) as $r) {
			if (($r['status'] ?? '') === 'COMPLETED') {
				$refunded += max(0, ChaosPayUtil::cents((string)($r['amount']['value'] ?? '0')));
			}
		}
		$raw = (string)($o['status'] ?? '');
		switch ($raw) {
			case 'APPROVED': $status = 'authorized'; break;
			case 'VOIDED': $status = 'cancelled'; break;
			case 'COMPLETED':
				$cs = (string)($capture['status'] ?? '');
				$raw .= '/' . $cs;
				$status = array('COMPLETED' => 'approved', 'PENDING' => 'pending', 'DECLINED' => 'failed', 'FAILED' => 'failed',
					'REFUNDED' => 'refunded', 'PARTIALLY_REFUNDED' => 'refunded')[$cs] ?? 'pending';
				break;
			default: $status = 'pending';
		}
		$amount = $capture['amount'] ?? ($pu['amount'] ?? array());
		return array(
			'status' => $status,
			'raw' => $raw,
			'psp_id' => (string)($o['id'] ?? ''),
			'psp_ref' => (string)($capture['id'] ?? ''),
			'amount_cents' => ChaosPayUtil::cents((string)($amount['value'] ?? '-1')),
			'currency' => strtoupper((string)($amount['currency_code'] ?? '')),
			'reference' => (string)($capture['custom_id'] ?? ($pu['custom_id'] ?? '')),
			'refunded_cents' => $refunded,
		);
	}

	private static function checkId(string $id): string {
		if (!preg_match('/^[A-Z0-9-]{5,64}$/', $id)) {
			throw new ChaosPayError('not a PayPal id');
		}
		return $id;
	}

	public function fetch(array $row, array $hint = array()): array {
		$s = self::normalize($this->call('GET', '/v2/checkout/orders/' . self::checkId((string)$row['psp_id'])));
		if (!empty($hint['dispute']) && $s['psp_ref'] !== '') {
			$d = $this->call('GET', '/v1/customer/disputes/' . self::checkId((string)$hint['dispute']));
			foreach ((array)($d['disputed_transactions'] ?? array()) as $t) {
				if (($t['seller_transaction_id'] ?? '') === $s['psp_ref']) {
					$s['status'] = 'disputed';
					$s['raw'] .= ' dispute ' . (string)($d['status'] ?? '');
				}
			}
		}
		return $s;
	}

	public function capture(array $row): array {
		$id = self::checkId((string)$row['psp_id']);
		$o = $this->call('POST', '/v2/checkout/orders/' . $id . '/capture', null,
			array('PayPal-Request-Id: ' . $row['token'] . '-capture', 'Prefer: return=representation'), '{}');
		return self::normalize($o);
	}

	public function cancel(array $row): bool {
		// an order that was never captured moves no money; PayPal lets it expire. Nothing to call.
		return true;
	}

	public function webhook(array $headers, string $body, string $query): array {
		if ($this->webhookId === '') {
			return array('ok' => false, 'code' => 503, 'hints' => array());
		}
		$need = array('paypal-auth-algo', 'paypal-cert-url', 'paypal-transmission-id', 'paypal-transmission-sig', 'paypal-transmission-time');
		foreach ($need as $h) {
			if (ChaosPayUtil::header($headers, $h) === '') {
				return array('ok' => false, 'code' => 401, 'hints' => array());
			}
		}
		$event = ChaosPayUtil::json($body);
		if (!$event) {
			return array('ok' => false, 'code' => 400, 'hints' => array());
		}
		$verify = '{"auth_algo":' . json_encode(ChaosPayUtil::header($headers, 'paypal-auth-algo')) .
			',"cert_url":' . json_encode(ChaosPayUtil::header($headers, 'paypal-cert-url'), JSON_UNESCAPED_SLASHES) .
			',"transmission_id":' . json_encode(ChaosPayUtil::header($headers, 'paypal-transmission-id')) .
			',"transmission_sig":' . json_encode(ChaosPayUtil::header($headers, 'paypal-transmission-sig')) .
			',"transmission_time":' . json_encode(ChaosPayUtil::header($headers, 'paypal-transmission-time')) .
			',"webhook_id":' . json_encode($this->webhookId) . ',"webhook_event":' . $body . '}';
		try {
			$r = $this->call('POST', '/v1/notifications/verify-webhook-signature', null, array(), $verify);
		} catch (ChaosPayError $e) {
			return array('ok' => false, 'code' => 503, 'hints' => array());
		}
		if (($r['verification_status'] ?? '') !== 'SUCCESS') {
			return array('ok' => false, 'code' => 401, 'hints' => array());
		}
		return array('ok' => true, 'hints' => self::hints($event));
	}

	/** Which of our charges an event is about. */
	public static function hints(array $event): array {
		$type = (string)($event['event_type'] ?? '');
		$res = (array)($event['resource'] ?? array());
		if (in_array($type, array('CHECKOUT.ORDER.APPROVED', 'CHECKOUT.ORDER.COMPLETED'), true) && !empty($res['id'])) {
			return array(array('by' => 'psp_id', 'id' => (string)$res['id']));
		}
		if (strpos($type, 'PAYMENT.CAPTURE.') === 0) {
			$orderId = (string)($res['supplementary_data']['related_ids']['order_id'] ?? '');
			if ($orderId !== '') {
				return array(array('by' => 'psp_id', 'id' => $orderId));
			}
			// a refund resource points at its capture with the link "up"
			foreach ((array)($res['links'] ?? array()) as $l) {
				if (($l['rel'] ?? '') === 'up' && preg_match('#/captures/([A-Z0-9-]+)#', (string)($l['href'] ?? ''), $m)) {
					return array(array('by' => 'psp_ref', 'id' => $m[1]));
				}
			}
			if ($type !== 'PAYMENT.CAPTURE.REFUNDED' && !empty($res['id'])) {
				return array(array('by' => 'psp_ref', 'id' => (string)$res['id']));
			}
			return array();
		}
		if ($type === 'CUSTOMER.DISPUTE.CREATED') {
			$out = array();
			foreach ((array)($res['disputed_transactions'] ?? array()) as $t) {
				if (!empty($t['seller_transaction_id'])) {
					$out[] = array('by' => 'psp_ref', 'id' => (string)$t['seller_transaction_id'], 'dispute' => (string)($res['dispute_id'] ?? ''));
				}
			}
			return $out;
		}
		return array();
	}
}
