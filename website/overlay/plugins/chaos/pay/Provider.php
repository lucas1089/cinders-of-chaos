<?php
/**
 * The payment provider adapter. One class per provider (MercadoPago.php for Pix, PayPal.php, Mock.php); the service
 * (Service.php) only talks to this interface, so another provider (another Pix PSP, for example) is one more class.
 *
 * A provider never decides an amount: it gets the order row the game server (or the site) wrote from the server's
 * config, and the service checks every answer against that row.
 *
 * Normalised payment state returned by fetch() / capture():
 *   status       approved | authorized (approved by the payer, still to capture) | pending | cancelled | expired |
 *                failed | refunded | charged_back | disputed
 *   psp_id       the provider's id of the charge (Mercado Pago payment id, PayPal order id)
 *   psp_ref      a second id (PayPal capture id), '' when none
 *   amount_cents integer, currency (upper case), reference (our order token, as sent at creation)
 *   refunded_cents integer (0 when nothing was refunded), raw (the provider's own status word, for the log)
 */

final class ChaosPayError extends RuntimeException {
}

interface ChaosPayProvider {
	/** 'mercadopago', 'paypal', 'mock' (stored in chaos_coin_payments.psp). */
	public function name(): string;

	/** 'pix' or 'paypal' (the donation method of shop_coins_config.lua it serves). */
	public function method(): string;

	/**
	 * Creates the charge. $order: order_id, token, amount_cents, currency, title, description, payer_email, expires
	 * (unix time), return_url, cancel_url. Returns psp_id, psp_ref, qr_code, pay_url, qr_image, expires, psp_status.
	 * Throws ChaosPayError. Must be safe to repeat with the same token (idempotency key).
	 */
	public function create(array $order): array;

	/** The current state of a charge (see above). $row: psp_id, psp_ref, token. $hint: what the webhook said. */
	public function fetch(array $row, array $hint = array()): array;

	/** Captures an 'authorized' charge and returns the new state (providers without a capture step return fetch()). */
	public function capture(array $row): array;

	/** Cancels an unpaid charge, best effort. */
	public function cancel(array $row): bool;

	/**
	 * Checks a webhook call. $headers: lower-case names. $query: the raw query string. Returns
	 * ['ok' => bool, 'code' => http status when not ok, 'hints' => [['by' => 'psp_id'|'psp_ref', 'id' => ..., ...]]].
	 * Nothing from the body is trusted beyond the ids in the hints: the service re-fetches the charge.
	 */
	public function webhook(array $headers, string $body, string $query): array;
}

/** HTTPS calls (curl). Tests pass their own callable instead. */
final class ChaosPayHttp {
	/** @return array{0:int,1:string} status code and body */
	public static function request(string $method, string $url, array $headers, ?string $body, int $timeout = 20): array {
		$ch = curl_init($url);
		$opts = array(
			CURLOPT_CUSTOMREQUEST => $method,
			CURLOPT_RETURNTRANSFER => true,
			CURLOPT_HTTPHEADER => $headers,
			CURLOPT_TIMEOUT => $timeout,
			CURLOPT_CONNECTTIMEOUT => 10,
			CURLOPT_SSL_VERIFYPEER => true,
			CURLOPT_SSL_VERIFYHOST => 2,
		);
		if ($body !== null) {
			$opts[CURLOPT_POSTFIELDS] = $body;
		}
		curl_setopt_array($ch, $opts);
		$out = curl_exec($ch);
		if ($out === false) {
			$err = curl_error($ch);
			curl_close($ch);
			throw new ChaosPayError('network error: ' . $err);
		}
		$code = (int)curl_getinfo($ch, CURLINFO_RESPONSE_CODE);
		curl_close($ch);
		return array($code, (string)$out);
	}
}

/** Small helpers shared by the providers. */
final class ChaosPayUtil {
	/** "24.95" from 2495 (what the providers' JSON wants). */
	public static function decimal(int $cents): string {
		return intdiv($cents, 100) . '.' . str_pad((string)($cents % 100), 2, '0', STR_PAD_LEFT);
	}

	/** 2495 from 24.95 / "24.95" without float rounding surprises. */
	public static function cents($value): int {
		$s = is_string($value) ? trim($value) : sprintf('%.4F', (float)$value);
		if (!preg_match('/^(-?)(\d+)(?:\.(\d+))?$/', $s, $m)) {
			return -1;
		}
		$frac = substr(str_pad($m[3] ?? '', 4, '0'), 0, 4);
		$v = (int)$m[2] * 100 + intdiv((int)$frac + 50, 100);
		return $m[1] === '-' ? -$v : $v;
	}

	/** CRC16-CCITT (0x1021, start 0xFFFF): the checksum field 63 of a Pix (EMV BR Code) payload. */
	public static function crc16(string $data): string {
		$crc = 0xFFFF;
		$len = strlen($data);
		for ($i = 0; $i < $len; $i++) {
			$crc ^= ord($data[$i]) << 8;
			for ($b = 0; $b < 8; $b++) {
				$crc = ($crc & 0x8000) ? (($crc << 1) ^ 0x1021) : ($crc << 1);
				$crc &= 0xFFFF;
			}
		}
		return strtoupper(str_pad(dechex($crc), 4, '0', STR_PAD_LEFT));
	}

	public static function json(string $body): array {
		$d = json_decode($body, true);
		return is_array($d) ? $d : array();
	}

	public static function header(array $headers, string $name): string {
		$name = strtolower($name);
		return isset($headers[$name]) ? trim((string)$headers[$name]) : '';
	}
}
