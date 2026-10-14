<?php
/**
 * Fake provider for tests and the in-game demo (CHAOS_PAY_PIX_PROVIDER=mock / CHAOS_PAY_PAYPAL_PROVIDER=mock; named
 * mock-pix / mock-paypal, webhook ?psp=mock-pix). No
 * network, no money. A charge is "paid" by itself `approveAfter` seconds after it was made (Pix: approved; PayPal:
 * approved by the payer, then captured like the real one). State in a small JSON file so the website and the worker
 * see the same charges. `worker.php --mock-refund <order id>` / `--mock-dispute <order id>` simulate a refund or a
 * chargeback after crediting. Webhook: header x-mock-signature = HMAC-SHA256 of the body with CHAOS_PAY_MOCK_SECRET.
 * Never enable it on a live server: anybody waiting `approveAfter` seconds gets coins.
 */

require_once __DIR__ . '/Provider.php';

final class ChaosPayMock implements ChaosPayProvider {
	private string $method;
	private int $approveAfter;
	private string $stateFile;
	private string $secret;
	private string $url;
	/** @var callable */
	private $now;

	public function __construct(string $method, int $approveAfter, string $stateFile, string $secret = '',
			string $url = 'https://www.example.invalid/mock-donation/', ?callable $now = null) {
		$this->method = $method;
		$this->approveAfter = max(0, $approveAfter);
		$this->stateFile = $stateFile;
		$this->secret = $secret;
		$this->url = $url;
		$this->now = $now ?? 'time';
	}

	public function name(): string { return 'mock-' . $this->method; }
	public function method(): string { return $this->method; }

	/** Reads, changes and writes the state under a lock. */
	private function state(?callable $change = null): array {
		$fh = fopen($this->stateFile, 'c+');
		if (!$fh) {
			throw new ChaosPayError('mock state file not writable');
		}
		flock($fh, LOCK_EX);
		$data = json_decode((string)stream_get_contents($fh), true);
		$data = is_array($data) ? $data : array();
		if ($change) {
			$data = $change($data);
			ftruncate($fh, 0);
			rewind($fh);
			fwrite($fh, json_encode($data));
		}
		flock($fh, LOCK_UN);
		fclose($fh);
		return $data;
	}

	/** A Pix "copia e cola" payload in the EMV BR Code layout (fake key and merchant), with its CRC. */
	public static function pixPayload(string $token, int $cents): string {
		$f = static function (string $id, string $v): string {
			return $id . str_pad((string)strlen($v), 2, '0', STR_PAD_LEFT) . $v;
		};
		$account = $f('00', 'br.gov.bcb.pix') . $f('01', 'mock-donation@example.invalid');
		$p = $f('00', '01') . $f('26', $account) . $f('52', '0000') . $f('53', '986') . $f('54', ChaosPayUtil::decimal($cents)) .
			$f('58', 'BR') . $f('59', 'CINDERS OF CHAOS') . $f('60', 'SAO PAULO') .
			$f('62', $f('05', substr(preg_replace('/[^A-Za-z0-9]/', '', $token), -25))) . '6304';
		return $p . ChaosPayUtil::crc16($p);
	}

	public function create(array $order): array {
		$cur = $this->method === 'pix' ? 'BRL' : 'USD';
		if (($order['currency'] ?? '') !== $cur) {
			throw new ChaosPayError('mock ' . $this->method . ' charges are in ' . $cur);
		}
		$id = 'MOCK-' . strtoupper($this->method) . '-' . (int)$order['order_id'] . '-' . substr(hash('sha256', (string)$order['token']), 0, 8);
		$now = ($this->now)();
		$this->state(function (array $d) use ($id, $order, $now): array {
			if (!isset($d[$id])) { // idempotent like the real ones
				$d[$id] = array('created' => $now, 'amount' => (int)$order['amount_cents'], 'currency' => $order['currency'],
					'token' => (string)$order['token'], 'status' => 'pending', 'refunded' => 0, 'capture' => '');
			}
			return $d;
		});
		return array('psp_id' => $id, 'psp_ref' => '',
			'qr_code' => $this->method === 'pix' ? self::pixPayload((string)$order['token'], (int)$order['amount_cents']) : '',
			'qr_image' => '', 'pay_url' => $this->method === 'pix' ? '' : $this->url . rawurlencode($id),
			'expires' => (int)$order['expires'], 'psp_status' => 'pending');
	}

	private function view(string $id, array $c): array {
		return array('status' => $c['status'], 'raw' => 'mock ' . $c['status'], 'psp_id' => $id, 'psp_ref' => (string)$c['capture'],
			'amount_cents' => (int)$c['amount'], 'currency' => (string)$c['currency'], 'reference' => (string)$c['token'],
			'refunded_cents' => (int)$c['refunded'], 'payer' => (string)($c['payer'] ?? ''));
	}

	public function fetch(array $row, array $hint = array()): array {
		$id = (string)$row['psp_id'];
		$now = ($this->now)();
		$after = $this->approveAfter;
		$method = $this->method;
		$d = $this->state(function (array $d) use ($id, $now, $after, $method): array {
			if (isset($d[$id]) && $d[$id]['status'] === 'pending' && $now >= $d[$id]['created'] + $after) {
				$d[$id]['status'] = $method === 'pix' ? 'approved' : 'authorized';
			}
			return $d;
		});
		if (!isset($d[$id])) {
			throw new ChaosPayError('mock: unknown charge');
		}
		return $this->view($id, $d[$id]);
	}

	public function capture(array $row): array {
		$id = (string)$row['psp_id'];
		$d = $this->state(function (array $d) use ($id): array {
			if (isset($d[$id]) && $d[$id]['status'] === 'authorized') {
				$d[$id]['status'] = 'approved';
				$d[$id]['capture'] = 'CAP' . substr(hash('sha256', $id), 0, 10);
			}
			return $d;
		});
		if (!isset($d[$id])) {
			throw new ChaosPayError('mock: unknown charge');
		}
		return $this->view($id, $d[$id]);
	}

	public function cancel(array $row): bool {
		$id = (string)$row['psp_id'];
		$this->state(function (array $d) use ($id): array {
			if (isset($d[$id]) && in_array($d[$id]['status'], array('pending', 'authorized'), true)) {
				$d[$id]['status'] = 'cancelled';
			}
			return $d;
		});
		return true;
	}

	/** Test / demo helper: refund (status refunded) or chargeback (status charged_back) a paid charge. */
	public function reverse(string $id, string $status, int $cents = 0): bool {
		$ok = false;
		$this->state(function (array $d) use ($id, $status, $cents, &$ok): array {
			if (isset($d[$id]) && $d[$id]['status'] === 'approved') {
				$d[$id]['status'] = $status;
				$d[$id]['refunded'] = $cents > 0 ? $cents : $d[$id]['amount'];
				$ok = true;
			}
			return $d;
		});
		return $ok;
	}

	public function webhook(array $headers, string $body, string $query): array {
		if ($this->secret === '') {
			return array('ok' => false, 'code' => 503, 'hints' => array());
		}
		$sig = ChaosPayUtil::header($headers, 'x-mock-signature');
		if ($sig === '' || !hash_equals(hash_hmac('sha256', $body, $this->secret), strtolower($sig))) {
			return array('ok' => false, 'code' => 401, 'hints' => array());
		}
		$id = (string)(ChaosPayUtil::json($body)['id'] ?? '');
		return array('ok' => true, 'hints' => $id !== '' ? array(array('by' => 'psp_id', 'id' => $id)) : array());
	}
}
