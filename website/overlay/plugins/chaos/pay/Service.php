<?php
/**
 * The donation flow between our tables and a payment provider (Provider.php). Used by the worker (worker.php: makes
 * the charges of new orders, checks open ones, expires and cancels), the webhook (chaos_pay_webhook.php) and the
 * website's donation page (pages/coins.php).
 *
 * Tables: chaos_coin_orders (one row per order; the game server credits 'paid' rows and marks them 'credited') and
 * chaos_coin_payments (the charge of an order). Order statuses: pending (no charge yet) -> open (charge made, QR /
 * link stored) -> paid (confirmed by the provider) -> credited (game server). Side exits: expired, cancelled,
 * failed, refunded (before crediting). A refund or chargeback after crediting sets chaos_coin_payments.reversal; the
 * game server takes back the unspent coins and staff see it in the admin panel.
 *
 * Every confirmation is fetched again from the provider and checked against the row (provider id, our token, amount
 * in integer cents, currency) before the order changes; every change is one conditional UPDATE, so a repeated
 * webhook or two workers change nothing twice. Logs carry order ids and amounts only (no e-mail, no names).
 */

require_once __DIR__ . '/Provider.php';
require_once __DIR__ . '/Db.php';

final class ChaosPayService {
	public const NOTICE_EN = 'Voluntary donation: it helps keep the server running. Nobody is required to donate; the game is fully playable for free.';
	public const NOTICE_PT = 'Doação voluntária: ajuda a manter o servidor. Ninguém é obrigado a doar; o jogo é totalmente jogável de graça.';
	public const OPEN = array('pending', 'open');
	public const METHODS = array('pix', 'paypal');
	/** Days after payment during which a credited order is checked again once a day (refunds, chargebacks). */
	public const RECHECK_DAYS = 180;

	private ChaosPayDb $db;
	/** @var array<string, ChaosPayProvider> method => provider */
	private array $providers;
	private array $packs;
	private array $pay;
	private array $opt;
	/** @var callable */
	private $now;
	/** @var callable */
	private $log;

	/**
	 * $packs: key => pack (key, name, coins, bonus_pct, bonus_coins, usd_cents, once, starter) from shop_coins_config.lua
	 * $pay: the `payments` block (brl_per_usd, expire_minutes, max_open, max_per_hour, methods => [key => enabled, currency, label])
	 * $opt: site_url, payer_email (pattern with {account}), reconcile_seconds, payer_salt (CHAOS_PAY_PAYER_SALT: mixed
	 *       into the payer hashes of chaos_pay_payers)
	 */
	public function __construct(ChaosPayDb $db, array $providers, array $packs, array $pay, array $opt = array(),
			?callable $now = null, ?callable $log = null) {
		$this->db = $db;
		$this->providers = $providers;
		$this->packs = $packs;
		$this->pay = $pay;
		$this->opt = $opt + array('site_url' => '', 'payer_email' => '', 'reconcile_seconds' => 60, 'payer_salt' => '');
		$this->now = $now ?? 'time';
		$this->log = $log ?? static function (string $line): void { error_log('[chaos pay] ' . $line); };
	}

	private function now(): int { return (int)($this->now)(); }
	private function log(string $s): void { ($this->log)($s); }

	public static function thanks(int $coins): array {
		return array(
			sprintf('Thank you for your voluntary donation! You received %d Chaos Coins as a thank-you.', $coins),
			sprintf('Obrigado pela sua doação voluntária! Você recebeu %d Chaos Coins como agradecimento.', $coins),
		);
	}

	/** Price of a pack in integer cents of the method's currency: usdCents, x brlPerUsd for Pix. Null when not sold. */
	public static function priceCents(array $pack, string $method, array $pay): ?int {
		$m = $pay['methods'][$method] ?? null;
		$usd = $pack['usd_cents'] ?? null;
		if (!$m || empty($m['enabled']) || !is_int($usd) || $usd <= 0) {
			return null;
		}
		if ($method === 'pix') {
			$rate = $pay['brl_per_usd'] ?? null;
			return (is_int($rate) && $rate > 0) ? $usd * $rate : null;
		}
		return $usd;
	}

	public static function money(int $cents, string $currency): string {
		$whole = intdiv($cents, 100);
		$frac = str_pad((string)($cents % 100), 2, '0', STR_PAD_LEFT);
		if ($currency === 'BRL') {
			return 'R$ ' . number_format($whole, 0, ',', '.') . ',' . $frac;
		}
		if ($currency === 'USD') {
			return 'US$ ' . number_format($whole, 0, '.', ',') . '.' . $frac;
		}
		return number_format($whole) . '.' . $frac . ' ' . $currency;
	}

	public function provider(string $method): ?ChaosPayProvider {
		return $this->providers[$method] ?? null;
	}

	public function providerByName(string $name): ?ChaosPayProvider {
		foreach ($this->providers as $p) {
			if ($p->name() === $name) {
				return $p;
			}
		}
		return null;
	}

	/** Methods with a provider and switched on in the server config. */
	public function methods(): array {
		$out = array();
		foreach (self::METHODS as $m) {
			if (isset($this->providers[$m]) && !empty($this->pay['methods'][$m]['enabled'])) {
				$out[$m] = $this->pay['methods'][$m];
			}
		}
		return $out;
	}

	// ------------------------------------------------------------------ orders from the website
	private function credited(int $accountId, bool $starter): int {
		$keys = array();
		foreach ($this->packs as $p) {
			if (!empty($p['starter']) === $starter) {
				$keys[] = $p['key'];
			}
		}
		if (!$keys) {
			return 0;
		}
		$in = implode(',', array_fill(0, count($keys), '?'));
		$r = $this->db->rows("SELECT COUNT(*) AS n FROM chaos_coin_orders WHERE account_id = ? AND status IN ('paid', 'credited') AND pack_key IN ($in)",
			array_merge(array($accountId), $keys));
		return (int)($r[0]['n'] ?? 0);
	}

	public function recentOrders(int $accountId, int $limit = 50): array {
		return $this->db->rows('SELECT o.id, o.status, o.pack_key, o.created, o.coins, o.bonus, o.first_bonus, p.method, p.amount_cents, ' .
			'p.currency, p.qr_code, p.qr_image, p.pay_url, p.expires, p.token FROM chaos_coin_orders o JOIN chaos_coin_payments p ' .
			'ON p.order_id = o.id WHERE o.account_id = ? ORDER BY o.id DESC LIMIT ' . max(1, min(200, $limit)), array($accountId));
	}

	public function order(int $accountId, int $orderId): ?array {
		$r = $this->db->rows('SELECT o.id, o.status, o.pack_key, o.created, o.coins, o.bonus, o.first_bonus, p.method, p.amount_cents, ' .
			'p.currency, p.qr_code, p.qr_image, p.pay_url, p.expires, p.token FROM chaos_coin_orders o JOIN chaos_coin_payments p ' .
			'ON p.order_id = o.id WHERE o.account_id = ? AND o.id = ?', array($accountId, $orderId));
		return $r[0] ?? null;
	}

	public static function isOpen(array $o, int $now): bool {
		if ($o['status'] === 'pending') {
			return true;
		}
		return $o['status'] === 'open' && ((int)$o['expires'] === 0 || (int)$o['expires'] > $now);
	}

	/**
	 * The same rules as the game server (shop_payments_core.lua ChaosPayCore.decide): pack and method on sale, the
	 * starter once, an open order of the same pack and method is shown again, one open order at a time, a few an hour.
	 * Returns ['ok' => true, 'order_id' => id, 'reused' => bool] or ['ok' => false, 'error' => text, 'order_id' => open id?].
	 */
	public function createOrder(int $accountId, string $packKey, string $method, string $source = 'site'): array {
		$pack = $this->packs[$packKey] ?? null;
		if ($accountId <= 0 || !$pack) {
			return array('ok' => false, 'error' => 'Unknown pack.');
		}
		$cents = self::priceCents($pack, $method, $this->pay);
		if ($cents === null || !isset($this->providers[$method])) {
			return array('ok' => false, 'error' => 'This donation method is not available.');
		}
		if (!empty($pack['once']) && $this->credited($accountId, true) > 0) {
			return array('ok' => false, 'error' => $pack['name'] . ' is once per account and was already received.');
		}
		$now = $this->now();
		$open = array();
		$lastHour = 0;
		foreach ($this->recentOrders($accountId) as $o) {
			if (self::isOpen($o, $now)) {
				$open[] = $o;
			}
			if ((int)$o['created'] > $now - 3600) {
				$lastHour++;
			}
		}
		foreach ($open as $o) {
			if ($o['pack_key'] === $packKey && $o['method'] === $method) {
				return array('ok' => true, 'order_id' => (int)$o['id'], 'reused' => true);
			}
		}
		if (count($open) >= (int)($this->pay['max_open'] ?? 1)) {
			return array('ok' => false, 'error' => 'You already have an open donation. Finish or cancel it first.', 'order_id' => (int)$open[0]['id']);
		}
		if ($lastHour >= (int)($this->pay['max_per_hour'] ?? 6)) {
			return array('ok' => false, 'error' => 'Too many donations started in the last hour. Please wait a little.');
		}
		$coins = (int)$pack['coins'];
		$bonus = intdiv($coins * (int)$pack['bonus_pct'], 100) + (int)$pack['bonus_coins'];
		$first = (empty($pack['starter']) && $this->credited($accountId, false) === 0) ? intdiv($coins * (int)($this->pay['first_bonus_pct'] ?? 0), 100) : 0;
		if ((int)($this->pay['first_bonus_max'] ?? 0) > 0) {
			$first = min($first, (int)$this->pay['first_bonus_max']); // "Limite a 1000" (ChaosShopCore.packCredit)
		}
		$token = sprintf('coc-%d-%d-%s', $accountId, $now, bin2hex(random_bytes(6)));
		$currency = (string)$this->pay['methods'][$method]['currency'];
		$this->db->begin();
		try {
			$this->db->exec("INSERT INTO chaos_coin_orders (account_id, pack_key, provider, provider_ref, status, coins, bonus, first_bonus, note, created) " .
				"VALUES (?, ?, ?, ?, 'pending', ?, ?, ?, 'donation', ?)", array($accountId, $packKey, $method, $token, $coins, $bonus, $first, $now));
			$id = (int)($this->db->rows('SELECT id FROM chaos_coin_orders WHERE provider = ? AND provider_ref = ?', array($method, $token))[0]['id'] ?? 0);
			$this->db->exec('INSERT INTO chaos_coin_payments (order_id, method, token, amount_cents, currency, source, updated) VALUES (?, ?, ?, ?, ?, ?, ?)',
				array($id, $method, $token, $cents, $currency, $source, $now));
			$this->db->commit();
		} catch (Throwable $e) {
			$this->db->rollback();
			$this->log('order not written: ' . $e->getMessage());
			return array('ok' => false, 'error' => 'Could not start the donation. Please try again.');
		}
		$this->log(sprintf('order %d: %s %s %d cents %s (%s)', $id, $packKey, $method, $cents, $currency, $source));
		return array('ok' => true, 'order_id' => $id, 'reused' => false);
	}

	public function cancelOrder(int $accountId, int $orderId): bool {
		return $this->db->exec("UPDATE chaos_coin_orders SET status = 'cancelled', note = 'cancelled by the player' WHERE id = ? AND account_id = ? AND status IN ('pending', 'open')",
			array($orderId, $accountId)) > 0;
	}

	// ------------------------------------------------------------------ charges
	private function row(int $orderId): ?array {
		$r = $this->db->rows('SELECT o.id, o.account_id, o.pack_key, o.status, o.created, o.coins, o.bonus, o.first_bonus, p.method, p.token, ' .
			'p.amount_cents, p.currency, p.psp, p.psp_id, p.psp_ref, p.expires, p.attempts, p.cancel_sent, p.reversal ' .
			'FROM chaos_coin_orders o JOIN chaos_coin_payments p ON p.order_id = o.id WHERE o.id = ?', array($orderId));
		return $r[0] ?? null;
	}

	private function note(int $orderId, string $note): void {
		$this->db->exec('UPDATE chaos_coin_payments SET note = ?, updated = ? WHERE order_id = ?', array(substr($note, 0, 255), $this->now(), $orderId));
	}

	private function payerEmail(int $accountId): string {
		$r = $this->db->rows('SELECT email FROM accounts WHERE id = ?', array($accountId));
		$email = trim((string)($r[0]['email'] ?? ''));
		if (filter_var($email, FILTER_VALIDATE_EMAIL)) {
			return $email;
		}
		$pattern = (string)$this->opt['payer_email'];
		return $pattern !== '' ? str_replace('{account}', (string)$accountId, $pattern) : '';
	}

	/** Makes the charge of a pending order. True when the order is open (or was already). */
	public function makeCharge(int $orderId): bool {
		$r = $this->row($orderId);
		if (!$r || $r['status'] !== 'pending' || $r['psp_id'] !== '') {
			return $r !== null && $r['status'] === 'open';
		}
		$now = $this->now();
		// claim it: one worker (or the page) at a time, retried after 30 s
		if ($this->db->exec("UPDATE chaos_coin_payments SET claimed = ?, attempts = attempts + 1 WHERE order_id = ? AND psp_id = '' AND claimed < ?",
				array($now, $orderId, $now - 30)) === 0) {
			return false;
		}
		$provider = $this->providers[$r['method']] ?? null;
		$pack = $this->packs[$r['pack_key']] ?? null;
		$expected = $pack ? self::priceCents($pack, $r['method'], $this->pay) : null;
		$fail = null;
		if (!$provider) {
			$fail = 'no provider for ' . $r['method'];
		} elseif ($expected === null || $expected !== (int)$r['amount_cents'] || $r['currency'] !== ($this->pay['methods'][$r['method']]['currency'] ?? '')) {
			$fail = 'amount differs from the server config';
		}
		$email = '';
		if (!$fail && $r['method'] === 'pix') {
			$email = $this->payerEmail((int)$r['account_id']);
			if ($email === '') {
				$fail = 'no payer e-mail (account e-mail empty, CHAOS_PAY_PAYER_EMAIL unset)';
			}
		}
		if ($fail) {
			$this->db->exec("UPDATE chaos_coin_orders SET status = 'failed', note = ? WHERE id = ? AND status = 'pending'", array($fail, $orderId));
			$this->note($orderId, $fail);
			$this->log("order $orderId failed: $fail");
			return false;
		}
		$coins = (int)$r['coins'] + (int)$r['bonus'] + (int)$r['first_bonus'];
		$expires = $now + 60 * max(30, (int)($this->pay['expire_minutes'] ?? 30));
		$site = rtrim((string)$this->opt['site_url'], '/');
		$back = $site . '/page.php?plugin=chaos&p=coins&order=' . $orderId;
		try {
			$c = $provider->create(array(
				'order_id' => $orderId, 'token' => $r['token'], 'amount_cents' => (int)$r['amount_cents'], 'currency' => $r['currency'],
				'title' => ($pack['name'] ?? $r['pack_key']) . ' - voluntary donation',
				'description' => sprintf('Voluntary donation to Cinders of Chaos (%d Chaos Coins as a thank-you). Nobody is required to donate; the game is fully playable for free.', $coins),
				'payer_email' => $email, 'expires' => $expires, 'return_url' => $back . '&done=1', 'cancel_url' => $back . '&cancel=1',
			));
		} catch (Throwable $e) {
			$msg = substr($e->getMessage(), 0, 200);
			$this->note($orderId, 'create: ' . $msg);
			$this->log("order $orderId: charge not made ($msg)");
			if ((int)$r['attempts'] + 1 >= 3) {
				$this->db->exec("UPDATE chaos_coin_orders SET status = 'failed', note = 'the payment service refused the charge' WHERE id = ? AND status = 'pending'", array($orderId));
			}
			return false;
		}
		$this->db->exec('UPDATE chaos_coin_payments SET psp = ?, psp_id = ?, psp_ref = ?, qr_code = ?, qr_image = ?, pay_url = ?, expires = ?, ' .
			'psp_status = ?, checked = ?, updated = ? WHERE order_id = ?', array($provider->name(), $c['psp_id'], $c['psp_ref'],
			substr($c['qr_code'], 0, 1024), $c['qr_image'] !== '' ? $c['qr_image'] : null, substr($c['pay_url'], 0, 1024),
			(int)$c['expires'], substr($c['psp_status'], 0, 32), $now, $now, $orderId));
		if ($this->db->exec("UPDATE chaos_coin_orders SET status = 'open' WHERE id = ? AND status = 'pending'", array($orderId)) === 0) {
			// cancelled or timed out meanwhile: take the charge back
			$provider->cancel(array('psp_id' => $c['psp_id'], 'psp_ref' => $c['psp_ref'], 'token' => $r['token']));
			$this->db->exec('UPDATE chaos_coin_payments SET cancel_sent = 1 WHERE order_id = ?', array($orderId));
			$this->log("order $orderId: charge made after the order closed, cancelled at " . $provider->name());
			return false;
		}
		$this->log(sprintf('order %d: %s charge %s, expires %s', $orderId, $provider->name(), $c['psp_id'], gmdate('H:i', (int)$c['expires'])));
		return true;
	}

	// ------------------------------------------------------------------ confirmation
	/** Fetches the charge of an order and applies it. Returns what happened (for logs and tests). */
	public function sync(int $orderId, array $hint = array()): string {
		$r = $this->row($orderId);
		if (!$r || $r['psp_id'] === '') {
			return 'no charge';
		}
		$provider = $this->providerByName($r['psp']);
		if (!$provider) {
			return 'no provider';
		}
		$this->db->exec('UPDATE chaos_coin_payments SET checked = ? WHERE order_id = ?', array($this->now(), $orderId));
		try {
			$state = $provider->fetch($r, $hint);
			if ($state['status'] === 'authorized') {
				if (!in_array($r['status'], self::OPEN, true)) {
					// approved by the payer after the order closed: not captured, no money moves
					$this->note($orderId, 'approved after the order closed; not captured');
					return 'not captured';
				}
				$state = $provider->capture($r);
			}
		} catch (Throwable $e) {
			$this->note($orderId, 'fetch: ' . substr($e->getMessage(), 0, 200));
			return 'error';
		}
		return $this->apply($r, $state);
	}

	public function apply(array $r, array $s): string {
		$id = (int)$r['id'];
		$now = $this->now();
		$this->db->exec('UPDATE chaos_coin_payments SET psp_status = ?, psp_ref = CASE WHEN ? <> \'\' THEN ? ELSE psp_ref END, updated = ? WHERE order_id = ?',
			array(substr((string)$s['raw'], 0, 32), (string)$s['psp_ref'], (string)$s['psp_ref'], $now, $id));
		// the charge must be ours: provider id and our token
		if ((string)$s['psp_id'] !== (string)$r['psp_id'] || (string)$s['reference'] !== (string)$r['token']) {
			$this->note($id, 'mismatch: provider id or reference');
			$this->log("order $id: answer does not match the order (id/reference), ignored");
			return 'mismatch';
		}
		$status = (string)$s['status'];
		if ($status === 'mismatch') {
			$this->note($id, 'mismatch: ' . $s['raw']);
			$this->log("order $id: answer does not match the order ({$s['raw']}), ignored");
			return 'mismatch';
		}
		if (in_array($status, array('approved', 'refunded', 'charged_back', 'disputed'), true)
				&& ((int)$s['amount_cents'] !== (int)$r['amount_cents'] || strtoupper((string)$s['currency']) !== $r['currency'])) {
			$this->note($id, sprintf('mismatch: %d %s paid, %d %s ordered', (int)$s['amount_cents'], $s['currency'], (int)$r['amount_cents'], $r['currency']));
			$this->log("order $id: amount or currency does not match, not credited");
			return 'mismatch';
		}
		switch ($status) {
			case 'approved':
				$n = $this->db->exec("UPDATE chaos_coin_orders SET status = 'paid', note = 'donation' WHERE id = ? AND status IN ('pending', 'open', 'expired', 'cancelled', 'failed')", array($id));
				if ($n > 0) {
					$this->db->exec('UPDATE chaos_coin_payments SET paid_at = ? WHERE order_id = ?', array($now, $id));
					$this->recordPayer($r, $s);
					$this->log(sprintf('order %d: paid (%s %s)', $id, self::money((int)$r['amount_cents'], $r['currency']), $r['psp']));
					return 'paid';
				}
				return 'already';
			case 'refunded':
			case 'charged_back':
			case 'disputed':
				$n = $this->db->exec("UPDATE chaos_coin_orders SET status = 'refunded', note = ? WHERE id = ? AND status IN ('pending', 'open', 'paid', 'expired', 'cancelled', 'failed')",
					array($status, $id));
				if ($n > 0) {
					$this->log("order $id: $status before crediting");
					return 'refunded';
				}
				$cur = $this->db->rows('SELECT status FROM chaos_coin_orders WHERE id = ?', array($id));
				if (($cur[0]['status'] ?? '') === 'credited') {
					$refunded = $status === 'refunded' ? (int)$s['refunded_cents'] : 0;
					$m = $this->db->exec("UPDATE chaos_coin_payments SET reversal = ?, reversal_cents = ?, reversal_at = ? WHERE order_id = ? AND reversal = ''",
						array($status, $refunded, $now, $id));
					if ($m > 0) {
						$this->log("order $id: $status after crediting, flagged for the game server and staff");
						return 'reversal';
					}
					// a second, larger refund of an order refunded in part: the game server takes back the difference
					if ($refunded > 0 && $this->db->exec("UPDATE chaos_coin_payments SET reversal_cents = ?, reversal_done = 0, reversal_at = ? " .
							"WHERE order_id = ? AND reversal = 'refunded' AND reversal_cents > 0 AND reversal_cents < ?",
							array($refunded, $now, $id, $refunded)) > 0) {
						$this->log("order $id: refunded further after crediting ($refunded cents in all), flagged again");
						return 'reversal';
					}
					// a chargeback or dispute after a partial refund: the whole donation is reversed now
					if ($status !== 'refunded' && $this->db->exec("UPDATE chaos_coin_payments SET reversal = ?, reversal_cents = 0, reversal_done = 0, " .
							"reversal_at = ? WHERE order_id = ? AND reversal = 'refunded' AND reversal_cents > 0", array($status, $now, $id)) > 0) {
						$this->log("order $id: $status after a partial refund, flagged again");
						return 'reversal';
					}
				}
				return 'already';
			case 'expired':
			case 'cancelled':
			case 'failed':
				$n = $this->db->exec("UPDATE chaos_coin_orders SET status = ?, note = ? WHERE id = ? AND status IN ('pending', 'open')",
					array($status, 'provider: ' . $s['raw'], $id));
				return $n > 0 ? $status : 'already';
			default:
				return 'waiting';
		}
	}

	/**
	 * The payer of a confirmed donation as a SHA-256 in chaos_pay_payers (order, account, hash): the creator codes and the
	 * referral program void a share or a reward when the same payer stands behind both accounts. The provider's payer
	 * (document, payer id or e-mail; MercadoPago/PayPal normalize 'payer'), else the e-mail the charge was made with.
	 * The raw value is never stored. Skipped when the table is missing (creator codes not installed).
	 */
	public static function payerHash(string $psp, string $identity, string $salt = ''): string {
		return hash('sha256', $salt . '|' . strtolower($psp) . '|' . strtolower(trim($identity)));
	}

	private function recordPayer(array $r, array $s): void {
		$who = trim((string)($s['payer'] ?? ''));
		if ($who === '') {
			$email = $this->payerEmail((int)$r['account_id']);
			$who = $email !== '' ? 'mail:' . strtolower($email) : '';
		}
		if ($who === '') {
			return;
		}
		$hash = self::payerHash((string)$r['psp'], $who, (string)$this->opt['payer_salt']);
		try {
			if (!$this->db->rows('SELECT order_id FROM chaos_pay_payers WHERE order_id = ?', array((int)$r['id']))) {
				$this->db->exec('INSERT INTO chaos_pay_payers (order_id, account_id, payer_hash, created_at) VALUES (?, ?, ?, ?)',
					array((int)$r['id'], (int)$r['account_id'], $hash, $this->now()));
			}
		} catch (Throwable $e) {
			$this->log('order ' . (int)$r['id'] . ': payer not recorded (' . substr($e->getMessage(), 0, 120) . ')');
		}
	}

	// ------------------------------------------------------------------ webhook
	/** Returns [http status, text]. */
	public function webhook(string $pspName, array $headers, string $body, string $query): array {
		$provider = $this->providerByName($pspName);
		if (!$provider) {
			return array(404, 'unknown provider');
		}
		$v = $provider->webhook($headers, $body, $query);
		if (empty($v['ok'])) {
			$this->log("webhook $pspName refused (" . (int)($v['code'] ?? 401) . ')');
			return array((int)($v['code'] ?? 401), 'refused');
		}
		$done = array();
		foreach ($v['hints'] as $h) {
			$col = $h['by'] === 'psp_ref' ? 'psp_ref' : 'psp_id';
			$rows = $this->db->rows("SELECT order_id FROM chaos_coin_payments WHERE psp = ? AND $col = ? AND $col <> ''", array($pspName, (string)$h['id']));
			if (!$rows) {
				$this->log("webhook $pspName: unknown charge, ignored");
				return array(404, 'unknown id');
			}
			$done[] = $this->sync((int)$rows[0]['order_id'], $h);
		}
		return array(200, $done ? implode(',', $done) : 'ok');
	}

	// ------------------------------------------------------------------ the worker's round
	public function runOnce(): array {
		$now = $this->now();
		$stats = array('charged' => 0, 'synced' => 0, 'expired' => 0, 'cancelled' => 0, 'rechecked' => 0);
		foreach ($this->db->rows("SELECT o.id FROM chaos_coin_orders o JOIN chaos_coin_payments p ON p.order_id = o.id WHERE o.status = 'pending' AND p.psp_id = '' ORDER BY o.id LIMIT 20") as $o) {
			$stats['charged'] += $this->makeCharge((int)$o['id']) ? 1 : 0;
		}
		// open orders: checked again every reconcile_seconds (the webhook is the fast path; this catches a lost one)
		$every = max(1, (int)$this->opt['reconcile_seconds']);
		foreach ($this->db->rows("SELECT o.id FROM chaos_coin_orders o JOIN chaos_coin_payments p ON p.order_id = o.id WHERE o.status = 'open' AND p.checked < ? ORDER BY p.checked LIMIT 50",
				array($now - $every)) as $o) {
			$this->sync((int)$o['id']);
			$stats['synced']++;
		}
		// past the expiry (with a minute of grace for a payment on the last second): checked once more, then expired
		foreach ($this->db->rows("SELECT o.id FROM chaos_coin_orders o JOIN chaos_coin_payments p ON p.order_id = o.id WHERE o.status = 'open' AND p.expires > 0 AND p.expires < ? LIMIT 50",
				array($now - 60)) as $o) {
			$res = $this->sync((int)$o['id']);
			if ($res !== 'paid' && $this->db->exec("UPDATE chaos_coin_orders SET status = 'expired', note = 'not paid in time' WHERE id = ? AND status = 'open'", array((int)$o['id'])) > 0) {
				$stats['expired']++;
			}
		}
		// closed orders with a charge: cancel it at the provider once, then one last look (a Pix paid at the last moment)
		foreach ($this->db->rows("SELECT o.id FROM chaos_coin_orders o JOIN chaos_coin_payments p ON p.order_id = o.id WHERE o.status IN ('cancelled', 'expired', 'failed') AND p.psp_id <> '' AND p.cancel_sent = 0 LIMIT 20") as $o) {
			$r = $this->row((int)$o['id']);
			$provider = $r ? $this->providerByName($r['psp']) : null;
			if ($provider) {
				$provider->cancel($r);
			}
			$this->db->exec('UPDATE chaos_coin_payments SET cancel_sent = 1 WHERE order_id = ?', array((int)$o['id']));
			$this->sync((int)$o['id']);
			$stats['cancelled']++;
		}
		// credited orders: asked again once a day for RECHECK_DAYS after payment, so a refund or chargeback whose webhook
		// was lost (or refused after a secret change) is still flagged for the game server
		foreach ($this->db->rows("SELECT o.id FROM chaos_coin_orders o JOIN chaos_coin_payments p ON p.order_id = o.id WHERE o.status = 'credited' " .
				"AND p.psp_id <> '' AND p.paid_at > ? AND p.checked < ? AND p.reversal IN ('', 'refunded') ORDER BY p.checked LIMIT 20",
				array($now - 86400 * self::RECHECK_DAYS, $now - 86400)) as $o) {
			$this->sync((int)$o['id']);
			$stats['rechecked']++;
		}
		return $stats;
	}
}
