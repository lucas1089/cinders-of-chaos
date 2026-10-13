<?php
/**
 * Pix through the Mercado Pago Payments API (checked against the developer docs in October 2026):
 *  - create: POST https://api.mercadopago.com/v1/payments with payment_method_id "pix", transaction_amount (BRL),
 *    payer.email (required by Mercado Pago; the account's e-mail, passed through and not stored here),
 *    external_reference (our order token), date_of_expiration (30 minutes to 30 days ahead), header X-Idempotency-Key.
 *    The answer carries point_of_interaction.transaction_data.qr_code (the copy-and-paste code), qr_code_base64 (a PNG)
 *    and ticket_url (Mercado Pago's own payment page).
 *  - fetch: GET /v1/payments/{id}; status pending / in_process / approved / rejected / cancelled (status_detail
 *    "expired" when the Pix code ran out) / refunded / charged_back / in_mediation.
 *  - webhook: header x-signature "ts=...,v1=..." = HMAC-SHA256 with the webhook secret over
 *    "id:<data.id of the query string, lower case>;request-id:<x-request-id>;ts:<ts>;" (a missing part is left out).
 *    Only the payment id is taken from the call; the payment is fetched again before anything changes.
 */

require_once __DIR__ . '/Provider.php';

final class ChaosPayMercadoPago implements ChaosPayProvider {
	private const API = 'https://api.mercadopago.com';

	private string $token;
	private string $secret;
	private string $notificationUrl;
	private int $tolerance;
	/** @var callable(string,string,array,?string):array */
	private $http;
	/** @var callable():int */
	private $now;

	public function __construct(string $accessToken, string $webhookSecret, string $notificationUrl = '', int $tolerance = 600,
			?callable $http = null, ?callable $now = null) {
		$this->token = $accessToken;
		$this->secret = $webhookSecret;
		$this->notificationUrl = $notificationUrl;
		$this->tolerance = $tolerance;
		$this->http = $http ?? array(ChaosPayHttp::class, 'request');
		$this->now = $now ?? 'time';
	}

	public function name(): string { return 'mercadopago'; }
	public function method(): string { return 'pix'; }

	private function call(string $method, string $path, ?array $body = null, array $extra = array()): array {
		if ($this->token === '') {
			throw new ChaosPayError('Mercado Pago access token missing (CHAOS_MP_ACCESS_TOKEN)');
		}
		$headers = array_merge(array('Authorization: Bearer ' . $this->token, 'Accept: application/json'), $extra);
		$json = null;
		if ($body !== null) {
			$headers[] = 'Content-Type: application/json';
			$json = json_encode($body, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);
		}
		[$code, $out] = ($this->http)($method, self::API . $path, $headers, $json);
		$data = ChaosPayUtil::json($out);
		if ($code < 200 || $code >= 300) {
			throw new ChaosPayError('Mercado Pago ' . $method . ' ' . preg_replace('/\d{6,}/', '#', $path) . ': HTTP ' . $code .
				(isset($data['message']) ? ' ' . substr((string)$data['message'], 0, 120) : ''));
		}
		return $data;
	}

	public static function isoDate(int $time): string {
		return gmdate('Y-m-d\TH:i:s', $time) . '.000+00:00';
	}

	public function create(array $order): array {
		if (($order['currency'] ?? '') !== 'BRL') {
			throw new ChaosPayError('Pix charges are in BRL');
		}
		$body = array(
			'transaction_amount' => (float)ChaosPayUtil::decimal((int)$order['amount_cents']),
			'description' => substr((string)$order['description'], 0, 250),
			'payment_method_id' => 'pix',
			'external_reference' => (string)$order['token'],
			'date_of_expiration' => self::isoDate((int)$order['expires']),
			'payer' => array('email' => (string)$order['payer_email']),
			'metadata' => array('order_id' => (int)$order['order_id']),
		);
		if ($this->notificationUrl !== '') {
			$body['notification_url'] = $this->notificationUrl;
		}
		$p = $this->call('POST', '/v1/payments', $body, array('X-Idempotency-Key: ' . $order['token']));
		$td = $p['point_of_interaction']['transaction_data'] ?? array();
		if (empty($p['id']) || empty($td['qr_code'])) {
			throw new ChaosPayError('Mercado Pago answered without a Pix code');
		}
		$expires = isset($p['date_of_expiration']) ? strtotime((string)$p['date_of_expiration']) : false;
		return array(
			'psp_id' => (string)$p['id'],
			'psp_ref' => '',
			'qr_code' => (string)$td['qr_code'],
			'qr_image' => (string)($td['qr_code_base64'] ?? ''),
			'pay_url' => (string)($td['ticket_url'] ?? ''),
			'expires' => $expires ? (int)$expires : (int)$order['expires'],
			'psp_status' => (string)($p['status'] ?? ''),
		);
	}

	public static function normalize(array $p): array {
		$raw = (string)($p['status'] ?? '');
		$detail = (string)($p['status_detail'] ?? '');
		$refunded = max(0, ChaosPayUtil::cents($p['transaction_amount_refunded'] ?? 0));
		switch ($raw) {
			// a partial refund leaves the payment "approved" (status_detail partially_refunded): treated as a refund of
			// that share, so the game server takes those coins back (or nothing is credited before crediting)
			case 'approved': $status = $refunded > 0 ? 'refunded' : 'approved'; break;
			case 'pending': case 'in_process': case 'authorized': $status = 'pending'; break;
			case 'rejected': $status = 'failed'; break;
			case 'cancelled': $status = $detail === 'expired' ? 'expired' : 'cancelled'; break;
			case 'refunded': $status = 'refunded'; break;
			case 'charged_back': $status = 'charged_back'; break;
			case 'in_mediation': $status = 'disputed'; break;
			default: $status = 'pending';
		}
		return array(
			'status' => $status,
			'raw' => $raw . ($detail !== '' ? '/' . $detail : ''),
			'psp_id' => (string)($p['id'] ?? ''),
			'psp_ref' => '',
			'amount_cents' => ChaosPayUtil::cents($p['transaction_amount'] ?? -1),
			'currency' => strtoupper((string)($p['currency_id'] ?? '')),
			'reference' => (string)($p['external_reference'] ?? ''),
			'refunded_cents' => $refunded,
			'method' => (string)($p['payment_method_id'] ?? ''),
			// who paid (hashed by the service into chaos_pay_payers, never stored as is): the payer's document, else
			// Mercado Pago's payer id, else the e-mail
			'payer' => self::payerOf($p),
		);
	}

	public static function payerOf(array $p): string {
		$payer = (array)($p['payer'] ?? array());
		$doc = (array)($payer['identification'] ?? array());
		if (($doc['number'] ?? '') !== '') {
			return 'doc:' . strtolower((string)($doc['type'] ?? '')) . ':' . preg_replace('/\D+/', '', (string)$doc['number']);
		}
		if (($payer['id'] ?? '') !== '') {
			return 'id:' . (string)$payer['id'];
		}
		return ($payer['email'] ?? '') !== '' ? 'mail:' . strtolower(trim((string)$payer['email'])) : '';
	}

	public function fetch(array $row, array $hint = array()): array {
		if (!preg_match('/^\d{1,30}$/', (string)$row['psp_id'])) {
			throw new ChaosPayError('not a Mercado Pago payment id');
		}
		$s = self::normalize($this->call('GET', '/v1/payments/' . $row['psp_id']));
		if ($s['method'] !== 'pix') {
			$s['status'] = 'mismatch'; // our reference on another payment method: never credited, staff look at it
			$s['raw'] .= ' (not pix)';
		}
		return $s;
	}

	public function capture(array $row): array {
		return $this->fetch($row);
	}

	public function cancel(array $row): bool {
		try {
			$this->call('PUT', '/v1/payments/' . (string)$row['psp_id'], array('status' => 'cancelled'));
			return true;
		} catch (ChaosPayError $e) {
			return false;
		}
	}

	/** The query value of `data.id` (PHP's $_GET turns the dot into "_", so the raw query string is read). */
	public static function queryValue(string $query, string $name): string {
		foreach (explode('&', $query) as $pair) {
			$kv = explode('=', $pair, 2);
			if (urldecode($kv[0]) === $name) {
				return urldecode($kv[1] ?? '');
			}
		}
		return '';
	}

	public static function manifest(string $dataId, string $requestId, string $ts): string {
		$m = '';
		if ($dataId !== '') {
			$m .= 'id:' . (ctype_alnum($dataId) ? strtolower($dataId) : $dataId) . ';';
		}
		if ($requestId !== '') {
			$m .= 'request-id:' . $requestId . ';';
		}
		return $m . 'ts:' . $ts . ';';
	}

	public function webhook(array $headers, string $body, string $query): array {
		if ($this->secret === '') {
			return array('ok' => false, 'code' => 503, 'hints' => array());
		}
		$sig = ChaosPayUtil::header($headers, 'x-signature');
		$ts = $v1 = '';
		foreach (explode(',', $sig) as $part) {
			$kv = explode('=', trim($part), 2);
			if (count($kv) === 2 && $kv[0] === 'ts') { $ts = $kv[1]; }
			if (count($kv) === 2 && $kv[0] === 'v1') { $v1 = strtolower($kv[1]); }
		}
		$dataId = self::queryValue($query, 'data.id');
		$requestId = ChaosPayUtil::header($headers, 'x-request-id');
		if ($ts === '' || $v1 === '' || !ctype_digit($ts)) {
			return array('ok' => false, 'code' => 401, 'hints' => array());
		}
		$expected = hash_hmac('sha256', self::manifest($dataId, $requestId, $ts), $this->secret);
		if (!hash_equals($expected, $v1)) {
			return array('ok' => false, 'code' => 401, 'hints' => array());
		}
		if ($this->tolerance > 0) {
			$sec = strlen($ts) > 11 ? intdiv((int)$ts, 1000) : (int)$ts; // the docs say ms; examples show seconds
			if (abs(($this->now)() - $sec) > $this->tolerance) {
				return array('ok' => false, 'code' => 401, 'hints' => array());
			}
		}
		$type = self::queryValue($query, 'type');
		if ($type === '') {
			$type = (string)(ChaosPayUtil::json($body)['type'] ?? '');
		}
		if ($type !== 'payment' || !preg_match('/^\d{1,30}$/', $dataId)) {
			return array('ok' => true, 'hints' => array()); // another topic: acknowledged, nothing to do
		}
		return array('ok' => true, 'hints' => array(array('by' => 'psp_id', 'id' => $dataId)));
	}
}
