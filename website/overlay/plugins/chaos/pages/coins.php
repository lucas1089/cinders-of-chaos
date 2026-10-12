<?php
/**
 * Donations for Chaos Coins (page.php?plugin=chaos&p=coins). Chaos Coins are a thank-you for a voluntary donation;
 * nobody is required to donate and the game is fully playable for free. The packs, prices (one USD table, Pix =
 * USD x 5) and bonuses come from the game server's shop_coins_config.lua; the game server credits every paid order.
 *
 *  - GET: the notice (voluntary; no refund except where the law requires; not a purchase; the Donation Terms of
 *    legal_lib.php), the packs with a Donate button per method (Pix in BRL, PayPal in USD) for a logged-in account,
 *    the account's last donations.
 *  - POST pack + method (+ CSRF token): writes the order and makes the charge (pay/Service.php); PayPal goes to its
 *    approval page, Pix shows the QR code and the copy-and-paste code.
 *  - GET order=<id>: the order of this account (refreshes itself until it is paid and credited; once paid it says
 *    again that it was a voluntary donation, not a purchase); &cancel=1 (the
 *    page's link and PayPal's cancel_url) only asks "Cancel this donation?"; the POST of that form (chaos_pay_cancel
 *    + CSRF token) cancels it, so a link alone can never cancel a donation.
 */
if (!isset($config)) { http_response_code(403); die('Direct access denied.'); }
require_once __DIR__ . '/../pay/bootstrap.php';
require_once __DIR__ . '/../legal_lib.php';
$GLOBALS['page_title'] = 'Donate - Chaos Coins';

$packs = chaos_coin_packs();
$settings = chaos_coin_settings();
$payCfg = chaos_pay_config();
$accountId = function_exists('getSession') ? (int)getSession('user_id') : 0;
$state = chaos_coin_account_state($accountId);
$service = $GLOBALS['chaos_pay_service'] ?? null;
if (!$service) {
	try {
		$service = chaos_pay_service($config);
	} catch (Throwable $e) {
		error_log('[chaos pay] page: ' . $e->getMessage());
		$service = null;
	}
}
$methods = $service ? $service->methods() : array();
$self = 'page.php?plugin=chaos&p=coins';

if (session_status() === PHP_SESSION_ACTIVE && empty($_SESSION['chaos_pay_csrf'])) {
	$_SESSION['chaos_pay_csrf'] = bin2hex(random_bytes(16));
}
$csrf = (string)($_SESSION['chaos_pay_csrf'] ?? '');

$error = '';
$order = null;
$confirmCancel = false;
$redirect = '';
if ($accountId > 0 && $service && ($_SERVER['REQUEST_METHOD'] ?? 'GET') === 'POST' && isset($_POST['chaos_pay_pack'])) {
	if ($csrf === '' || !hash_equals($csrf, (string)($_POST['chaos_pay_csrf'] ?? ''))) {
		$error = 'The form expired. Please try again.';
	} else {
		$res = $service->createOrder($accountId, (string)$_POST['chaos_pay_pack'], (string)($_POST['chaos_pay_method'] ?? ''), 'site');
		if (!$res['ok']) {
			$error = $res['error'];
		}
		$oid = (int)($res['order_id'] ?? 0);
		if ($oid > 0) {
			$service->makeCharge($oid); // the worker retries if the provider is slow
			$order = $service->order($accountId, $oid);
			if ($order && $order['method'] === 'paypal' && $order['status'] === 'open' && $order['pay_url'] !== '') {
				$redirect = $order['pay_url'];
			}
		}
	}
} elseif ($accountId > 0 && $service && ($_SERVER['REQUEST_METHOD'] ?? 'GET') === 'POST' && isset($_POST['chaos_pay_cancel'])) {
	$oid = (int)$_POST['chaos_pay_cancel'];
	if ($csrf === '' || !hash_equals($csrf, (string)($_POST['chaos_pay_csrf'] ?? ''))) {
		$error = 'The form expired. Please try again.';
	} else {
		$service->cancelOrder($accountId, $oid);
	}
	$order = $service->order($accountId, $oid);
} elseif ($accountId > 0 && $service && isset($_GET['order'])) {
	$oid = (int)$_GET['order'];
	$order = $service->order($accountId, $oid);
	$confirmCancel = !empty($_GET['cancel']) && $order && in_array($order['status'], array('pending', 'open'), true);
	if ($order && $order['status'] === 'open' && !empty($_GET['done'])) {
		$service->sync($oid); // back from PayPal: capture at once instead of waiting for the webhook
		$order = $service->order($accountId, $oid);
	}
}

$packName = static function (string $key) use ($packs): string {
	foreach ($packs as $p) {
		if ($p['key'] === $key) { return $p['name']; }
	}
	return $key;
};
$statusText = array(
	'pending' => 'Preparing your donation...',
	'open' => 'Waiting for your donation.',
	'paid' => 'Donation received. Your Chaos Coins arrive in a few seconds.',
	'expired' => 'This donation expired before it was paid. Nothing was charged.',
	'cancelled' => 'This donation was cancelled. Nothing was charged.',
	'failed' => 'The payment service is not available right now. Nothing was charged; try again later.',
	'refunded' => 'This donation was refunded.',
	'rejected' => 'This order could not be credited. Please contact staff.',
);
$waiting = $order && in_array($order['status'], array('pending', 'open', 'paid'), true) && !$confirmCancel;
?>
<div class="chaos-page">
	<div class="chaos-box">
		<h1 class="chaos-heading">Donate - Chaos Coins</h1>
		<div class="chaos-notice" id="chaos-donation-notice" style="border:1px solid #c89a3c;padding:10px 14px;margin:0 0 14px 0;">
			<p class="chaos-gold" style="margin:0 0 4px 0;"><strong><?= chaos_h(ChaosPayService::NOTICE_EN) ?></strong></p>
			<p style="margin:0;" lang="pt-BR"><?= chaos_h(ChaosPayService::NOTICE_PT) ?></p>
			<p class="chaos-terms-note" id="chaos-donation-terms"><?= chaos_h(CHAOS_LEGAL_DONATION_BEFORE_EN) ?>
				<a href="<?= chaos_h(chaos_legal_url('donations', 'en')) ?>">Donation Terms</a></p>
			<p class="chaos-terms-note" lang="pt-BR"><?= chaos_h(CHAOS_LEGAL_DONATION_BEFORE_PT) ?>
				<a href="<?= chaos_h(chaos_legal_url('donations')) ?>">Termos de Doação</a></p>
		</div>
		<p class="chaos-lead">Chaos Coins are our thank-you for your donation. They buy cosmetics, convenience and services in the in-game Store (Economy &gt; Store) and belong to your account, so every character can spend them.</p>

		<?php if ($redirect !== ''): ?>
			<meta http-equiv="refresh" content="0;url=<?= chaos_h($redirect) ?>">
			<p>Opening PayPal... <a href="<?= chaos_h($redirect) ?>">Continue to PayPal</a> if nothing happens.</p>
			<script>location.href = <?= json_encode($redirect) ?>;</script>
		<?php endif; ?>

		<?php if ($error !== ''): ?>
			<p class="chaos-error" style="color:#e07060;"><?= chaos_h($error) ?></p>
		<?php endif; ?>

		<?php if ($order): ?>
			<div class="chaos-box" id="chaos-donation-order" style="margin:10px 0;">
				<h2 class="chaos-heading">Your donation: <?= chaos_h($packName($order['pack_key'])) ?></h2>
				<p><?= chaos_h($order['method'] === 'pix' ? 'Pix' : 'PayPal') ?>: <strong><?= chaos_h(ChaosPayService::money((int)$order['amount_cents'], $order['currency'])) ?></strong>
					&middot; <?= (int)$order['coins'] + (int)$order['bonus'] + (int)$order['first_bonus'] ?> Chaos Coins as a thank-you</p>
				<?php if ($order['status'] === 'credited'): ?>
					<?php [$thanksEn, $thanksPt] = ChaosPayService::thanks((int)$order['coins'] + (int)$order['bonus'] + (int)$order['first_bonus']); ?>
					<p class="chaos-gold"><strong><?= chaos_h($thanksEn) ?></strong></p>
					<p lang="pt-BR"><?= chaos_h($thanksPt) ?></p>
				<?php else: ?>
					<p><?= chaos_h($statusText[$order['status']] ?? $order['status']) ?></p>
				<?php endif; ?>
				<?php if (in_array($order['status'], array('paid', 'credited'), true)): ?>
					<p class="chaos-terms-note" id="chaos-donation-receipt-terms"><?= chaos_h(CHAOS_LEGAL_DONATION_AFTER_EN) ?>
						<a href="<?= chaos_h(chaos_legal_url('donations', 'en')) ?>">Donation Terms</a></p>
					<p class="chaos-terms-note" lang="pt-BR"><?= chaos_h(CHAOS_LEGAL_DONATION_AFTER_PT) ?>
						<a href="<?= chaos_h(chaos_legal_url('donations')) ?>">Termos de Doação</a></p>
				<?php endif; ?>
				<?php if ($order['status'] === 'open' && $order['method'] === 'pix'): ?>
					<?php if (!empty($order['qr_image'])): ?>
						<p><img alt="Pix QR code" width="240" height="240" src="data:image/png;base64,<?= chaos_h($order['qr_image']) ?>"></p>
						<p>Scan the QR code with your bank app, or use Pix copy and paste:</p>
					<?php else: ?>
						<p>Use Pix copy and paste in your bank app:</p>
					<?php endif; ?>
					<textarea readonly rows="3" style="width:100%;" onclick="this.select()"><?= chaos_h($order['qr_code']) ?></textarea>
					<p class="chaos-muted">Expires at <?= chaos_h(gmdate('H:i', (int)$order['expires'])) ?> UTC. This page updates by itself.</p>
				<?php elseif ($order['status'] === 'open' && $order['method'] === 'paypal' && $order['pay_url'] !== ''): ?>
					<p><a class="chaos-button" href="<?= chaos_h($order['pay_url']) ?>">Continue to PayPal</a></p>
				<?php endif; ?>
				<?php if ($confirmCancel): ?>
					<form method="post" action="<?= chaos_h($self) ?>" id="chaos-donation-cancel">
						<p><strong>Cancel this donation?</strong> Nothing has been charged for it.</p>
						<input type="hidden" name="chaos_pay_csrf" value="<?= chaos_h($csrf) ?>">
						<input type="hidden" name="chaos_pay_cancel" value="<?= (int)$order['id'] ?>">
						<button type="submit" class="chaos-button">Yes, cancel it</button>
						<a href="<?= chaos_h($self . '&order=' . (int)$order['id']) ?>">No, keep it</a>
					</form>
				<?php elseif (in_array($order['status'], array('pending', 'open'), true)): ?>
					<p><a href="<?= chaos_h($self . '&order=' . (int)$order['id'] . '&cancel=1') ?>">Cancel this donation</a></p>
				<?php endif; ?>
				<?php if ($waiting): ?>
					<script>setTimeout(function () { location.href = <?= json_encode($self . '&order=' . (int)$order['id']) ?>; }, 5000);</script>
				<?php endif; ?>
			</div>
		<?php endif; ?>

		<?php if ($settings['first_bonus_pct'] > 0): ?>
			<p>Your first donation brings <span class="chaos-gold">+<?= (int)$settings['first_bonus_pct'] ?>% extra Chaos Coins</span> as an extra thank-you<?php if ($accountId > 0 && !$state['first']): ?> <span class="chaos-muted">(already used on your account)</span><?php endif; ?>.</p>
		<?php endif; ?>
		<?php if (!$packs): ?>
			<p class="chaos-empty">No coin packs are set up yet.</p>
		<?php else: ?>
			<table class="chaos-table" id="chaos-donation-packs">
				<thead><tr><th>Pack</th><th class="num">Chaos Coins</th><th class="num">Bonus</th><th class="num">Thank-you</th>
					<?php foreach (array('pix', 'paypal') as $m): ?><th class="num"><?= chaos_h($payCfg['methods'][$m]['label'] ?? $m) ?></th><?php endforeach; ?></tr></thead>
				<tbody>
				<?php foreach ($packs as $p): ?>
					<tr>
						<td><?= chaos_h($p['name']) ?><?php if ($p['once']): ?> <span class="chaos-muted">(once per account<?= ($accountId > 0 && $p['starter'] && !$state['starter']) ? ', already received' : '' ?>)</span><?php endif; ?></td>
						<td class="num"><?= (int)$p['coins'] ?></td>
						<td class="num"><?= $p['bonus_pct'] > 0 ? '+' . (int)$p['bonus_pct'] . '%' : '' ?><?= $p['bonus_coins'] > 0 ? '+' . (int)$p['bonus_coins'] : '' ?></td>
						<td class="num chaos-gold"><?= (int)$p['total'] ?></td>
						<?php foreach (array('pix', 'paypal') as $m): ?>
							<?php $cents = ChaosPayService::priceCents($p, $m, $payCfg); $money = $cents !== null ? ChaosPayService::money($cents, $payCfg['methods'][$m]['currency']) : ''; ?>
							<td class="num">
								<?php if ($cents === null): ?>
									-
								<?php elseif ($accountId > 0 && isset($methods[$m]) && !($p['starter'] && !$state['starter'])): ?>
									<form method="post" action="<?= chaos_h($self) ?>" style="display:inline;">
										<input type="hidden" name="chaos_pay_csrf" value="<?= chaos_h($csrf) ?>">
										<input type="hidden" name="chaos_pay_pack" value="<?= chaos_h($p['key']) ?>">
										<input type="hidden" name="chaos_pay_method" value="<?= chaos_h($m) ?>">
										<button type="submit" class="chaos-button">Donate <?= chaos_h($money) ?></button>
									</form>
								<?php else: ?>
									<?= chaos_h($money) ?>
								<?php endif; ?>
							</td>
						<?php endforeach; ?>
					</tr>
				<?php endforeach; ?>
				</tbody>
			</table>
		<?php endif; ?>
		<?php if ($accountId <= 0): ?>
			<p class="chaos-muted">Log in to donate. You can also donate in the game: Store &gt; Donate.</p>
		<?php elseif (!$methods): ?>
			<p class="chaos-muted">Donations are not open right now.</p>
		<?php else: ?>
			<p class="chaos-muted">Pix is charged in Brazilian reais (BRL), PayPal in US dollars (USD). Coins reach your account within seconds of the confirmation, also while you play.</p>
		<?php endif; ?>

		<?php if ($accountId > 0 && $service): ?>
			<?php $history = array_slice($service->recentOrders($accountId, 10), 0, 10); ?>
			<?php if ($history): ?>
				<h2 class="chaos-heading">Your donations</h2>
				<table class="chaos-table" id="chaos-donation-history">
					<thead><tr><th>Date (UTC)</th><th>Donation</th><th class="num">Amount</th><th class="num">Thank-you</th><th>Status</th></tr></thead>
					<tbody>
					<?php foreach ($history as $h): ?>
						<tr>
							<td><?= chaos_h(gmdate('Y-m-d H:i', (int)$h['created'])) ?></td>
							<td><a href="<?= chaos_h($self . '&order=' . (int)$h['id']) ?>">Donation #<?= (int)$h['id'] ?></a>: <?= chaos_h($packName($h['pack_key'])) ?></td>
							<td class="num"><?= chaos_h(ChaosPayService::money((int)$h['amount_cents'], $h['currency'])) ?></td>
							<td class="num"><?= (int)$h['coins'] + (int)$h['bonus'] + (int)$h['first_bonus'] ?> Chaos Coins</td>
							<td><?= chaos_h($h['status'] === 'credited' ? 'thank you, coins received' : $h['status']) ?></td>
						</tr>
					<?php endforeach; ?>
					</tbody>
				</table>
			<?php endif; ?>
		<?php endif; ?>
	</div>
</div>
