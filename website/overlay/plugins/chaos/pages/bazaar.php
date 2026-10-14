<?php
/**
 * Character Bazaar (page.php?plugin=chaos&p=bazaar; bazaar_lib.php, website/README.md "Character Bazaar").
 *
 *  - GET: the open auctions (character, level, class, current bid, ends); &id=N one auction with its bids (amounts and
 *    times only, never the bidders) and, logged in, the bid form; &mine=1 the account's characters (which can be
 *    listed and why not) and its listings.
 *  - POST (CSRF token): do=list (player, min, buyout, days), do=bid (id, amount), do=cancel (id; the seller before a
 *    bid, an administrator with a reason at any time).
 *  - Administrators (admin panel account with a group 5+ character): &admin=1, the latest listings with a Cancel.
 * Every view first ends the auctions whose time ran out (the worker does it too, bazaar_worker.php).
 */
if (!isset($config)) { http_response_code(403); die('Direct access denied.'); }
require_once __DIR__ . '/../bazaar_lib.php';
$GLOBALS['page_title'] = 'Character Bazaar';

$self = 'page.php?plugin=chaos&p=bazaar';
$accountId = function_exists('getSession') ? (int)getSession('user_id') : 0;
try {
	$bz = chaos_bazaar($config);
	$bz->settleDue();
} catch (Throwable $e) {
	error_log('[chaos bazaar] page: ' . $e->getMessage());
	echo '<div class="chaos-page"><div class="chaos-box"><h1 class="chaos-heading">Character Bazaar</h1><p class="chaos-muted">The bazaar is not available right now.</p></div></div>';
	return;
}
$cfg = $bz->config();
$isAdmin = $accountId > 0 && chaos_bazaar_is_admin($config, $accountId);
if (session_status() === PHP_SESSION_ACTIVE && empty($_SESSION['chaos_bazaar_csrf'])) {
	$_SESSION['chaos_bazaar_csrf'] = bin2hex(random_bytes(16));
}
$csrf = (string)($_SESSION['chaos_bazaar_csrf'] ?? '');
$ip = (string)($_SERVER['REMOTE_ADDR'] ?? '');

$message = '';
$messageOk = true;
if ($accountId > 0 && ($_SERVER['REQUEST_METHOD'] ?? 'GET') === 'POST' && isset($_POST['do'])) {
	if ($csrf === '' || !hash_equals($csrf, (string)($_POST['csrf'] ?? ''))) {
		[$messageOk, $message] = array(false, 'The form expired. Please try again.');
	} elseif ($_POST['do'] === 'list') {
		[$messageOk, $message] = $bz->listCharacter($accountId, (int)($_POST['player'] ?? 0), (int)($_POST['min'] ?? 0),
			(int)($_POST['buyout'] ?? 0), (int)($_POST['days'] ?? 0));
	} elseif ($_POST['do'] === 'bid') {
		[$messageOk, $message] = $bz->bid($accountId, (int)($_POST['id'] ?? 0), (int)($_POST['amount'] ?? 0), $ip);
	} elseif ($_POST['do'] === 'cancel') {
		[$messageOk, $message] = $bz->cancel((int)($_POST['id'] ?? 0), $accountId, $isAdmin && !empty($_POST['admin']),
			trim(substr((string)($_POST['reason'] ?? ''), 0, 48)));
	}
}
$time = static function (int $t): string { return $t > 0 ? gmdate('Y-m-d H:i', $t) : '-'; };
$left = static function (int $t): string {
	$s = max(0, $t - time());
	return $s >= 86400 ? sprintf('%dd %dh', intdiv($s, 86400), intdiv($s % 86400, 3600)) : sprintf('%dh %02dm', intdiv($s, 3600), intdiv($s % 3600, 60));
};
$class = static function (int $voc): string { return function_exists('chaos_class_name') ? chaos_class_name($voc) : (string)$voc; };
$view = isset($_GET['id']) ? $bz->listing((int)$_GET['id']) : null;
?>
<div class="chaos-page" id="chaos-bazaar">
	<div class="chaos-box">
		<h1 class="chaos-heading">Character Bazaar</h1>
		<p class="chaos-lead">Players sell characters to players for Chaos Coins. Bids are held from your balance and come back at once if you are outbid. The house keeps <?= (int)$cfg['feePct'] ?>% of the final price. A listed character cannot log in until its auction ends. Season, Hardcore and Self-Found characters, guild leaders and characters with an open report cannot be listed. Rules: the wiki's Character Bazaar page and the Donation Terms.</p>
		<nav class="chaos-tabs" aria-label="Views">
			<a class="chaos-tab<?= !$view && empty($_GET['mine']) && empty($_GET['admin']) ? ' is-active' : '' ?>" href="<?= chaos_h($self) ?>">Open auctions</a>
			<?php if ($accountId > 0): ?><a class="chaos-tab<?= !empty($_GET['mine']) ? ' is-active' : '' ?>" href="<?= chaos_h($self . '&mine=1') ?>">Sell a character</a><?php endif; ?>
			<?php if ($isAdmin): ?><a class="chaos-tab<?= !empty($_GET['admin']) ? ' is-active' : '' ?>" href="<?= chaos_h($self . '&admin=1') ?>">Administration</a><?php endif; ?>
		</nav>
		<?php if ($message !== ''): ?>
			<p class="<?= $messageOk ? 'chaos-gold' : 'chaos-error' ?>" id="chaos-bazaar-message"><?= chaos_h($message) ?></p>
		<?php endif; ?>
		<?php if (empty($cfg['enabled'])): ?>
			<p class="chaos-muted">The Character Bazaar is closed.</p>
		<?php elseif ($view): ?>
			<?php $bids = $bz->bidsOf((int)$view['id']); ?>
			<h2><?= chaos_h($view['player_name']) ?></h2>
			<p>Level <?= (int)$view['level'] ?> <?= chaos_h($class((int)$view['vocation'])) ?>. Status: <?= chaos_h($view['status']) ?>.
				<?php if ($view['status'] === 'active'): ?>Ends <?= chaos_h($time((int)$view['ends_at'])) ?> UTC (in <?= chaos_h($left((int)$view['ends_at'])) ?>).<?php endif; ?></p>
			<p>Current bid: <strong><?= (int)$view['current_bid'] > 0 ? (int)$view['current_bid'] . ' Chaos Coins' : 'none (minimum ' . (int)$view['min_price'] . ')' ?></strong><?= (int)$view['buyout'] > 0 ? '. Buyout: ' . (int)$view['buyout'] . ' Chaos Coins' : '' ?>.</p>
			<?php if ($view['status'] === 'active' && $accountId > 0 && (int)$view['seller_account_id'] !== $accountId): ?>
				<form method="post" action="<?= chaos_h($self . '&id=' . (int)$view['id']) ?>" id="chaos-bazaar-bid">
					<input type="hidden" name="csrf" value="<?= chaos_h($csrf) ?>"><input type="hidden" name="id" value="<?= (int)$view['id'] ?>">
					<label>Your bid <input type="number" name="amount" min="<?= $bz->minNextBid($view) ?>" value="<?= $bz->minNextBid($view) ?>"></label>
					<button type="submit" name="do" value="bid" class="chaos-button">Bid</button>
					<span class="chaos-muted">Your balance: <?= $bz->coins($accountId) ?> Chaos Coins.</span>
				</form>
			<?php elseif ($view['status'] === 'active' && (int)$view['seller_account_id'] === $accountId && (int)$view['current_bid_id'] === 0): ?>
				<form method="post" action="<?= chaos_h($self . '&id=' . (int)$view['id']) ?>">
					<input type="hidden" name="csrf" value="<?= chaos_h($csrf) ?>"><input type="hidden" name="id" value="<?= (int)$view['id'] ?>">
					<button type="submit" name="do" value="cancel" class="chaos-button">Cancel this auction</button>
				</form>
			<?php endif; ?>
			<table class="chaos-table"><thead><tr><th>Time (UTC)</th><th class="num">Bid</th><th>State</th></tr></thead><tbody>
				<?php if (!$bids): ?><tr><td colspan="3" class="chaos-muted">No bids yet.</td></tr><?php endif; ?>
				<?php foreach ($bids as $b): ?>
					<tr><td><?= chaos_h($time((int)$b['created_at'])) ?></td><td class="num"><?= (int)$b['amount'] ?><?= (int)$b['buyout'] === 1 ? ' (buyout)' : '' ?></td><td><?= chaos_h($b['state']) ?></td></tr>
				<?php endforeach; ?>
			</tbody></table>
		<?php elseif (!empty($_GET['mine']) && $accountId > 0): ?>
			<h2>Your characters</h2>
			<table class="chaos-table" id="chaos-bazaar-candidates"><thead><tr><th>Character</th><th class="num">Level</th><th>Can be listed?</th></tr></thead><tbody>
				<?php foreach ($bz->candidates($accountId) as $c): ?>
					<tr><td><?= chaos_h($c['name']) ?></td><td class="num"><?= (int)$c['level'] ?></td>
						<td><?php if (!$c['why']): ?>
							<form method="post" action="<?= chaos_h($self . '&mine=1') ?>">
								<input type="hidden" name="csrf" value="<?= chaos_h($csrf) ?>"><input type="hidden" name="player" value="<?= (int)$c['id'] ?>">
								<label>Minimum <input type="number" name="min" min="<?= (int)$cfg['minPrice'] ?>" value="<?= (int)$cfg['minPrice'] ?>" style="width:7em;"></label>
								<label>Buyout <input type="number" name="buyout" min="0" value="0" style="width:7em;"></label>
								<label>Days <select name="days"><?php for ($d = (int)$cfg['minDays']; $d <= (int)$cfg['maxDays']; $d++): ?><option value="<?= $d ?>"<?= $d === 3 ? ' selected' : '' ?>><?= $d ?></option><?php endfor; ?></select></label>
								<button type="submit" name="do" value="list" class="chaos-button">List</button>
							</form>
						<?php else: ?><span class="chaos-muted"><?= chaos_h(implode(' ', $c['why'])) ?></span><?php endif; ?></td></tr>
				<?php endforeach; ?>
			</tbody></table>
			<h2>Your listings</h2>
			<table class="chaos-table"><thead><tr><th>Character</th><th>Status</th><th class="num">Price</th><th class="num">Fee</th><th>Ends (UTC)</th></tr></thead><tbody>
				<?php foreach ($bz->ofSeller($accountId) as $l): ?>
					<tr><td><a href="<?= chaos_h($self . '&id=' . (int)$l['id']) ?>"><?= chaos_h($l['player_name']) ?></a></td><td><?= chaos_h($l['status'] . ($l['reason'] !== '' ? ' (' . $l['reason'] . ')' : '')) ?></td>
						<td class="num"><?= (int)$l['current_bid'] ?></td><td class="num"><?= (int)$l['fee'] ?></td><td><?= chaos_h($time((int)$l['ends_at'])) ?></td></tr>
				<?php endforeach; ?>
			</tbody></table>
		<?php elseif (!empty($_GET['admin']) && $isAdmin): ?>
			<h2>Latest listings</h2>
			<table class="chaos-table" id="chaos-bazaar-admin"><thead><tr><th>#</th><th>Character</th><th>Status</th><th class="num">Bid</th><th class="num">Bids</th><th>Ends</th><th></th></tr></thead><tbody>
				<?php foreach ($bz->adminRecent() as $l): ?>
					<tr><td><?= (int)$l['id'] ?></td><td><a href="<?= chaos_h($self . '&id=' . (int)$l['id']) ?>"><?= chaos_h($l['player_name']) ?></a></td>
						<td><?= chaos_h($l['status'] . ($l['reason'] !== '' ? ' (' . $l['reason'] . ')' : '')) ?></td><td class="num"><?= (int)$l['current_bid'] ?></td><td class="num"><?= (int)$l['bids'] ?></td>
						<td><?= chaos_h($time((int)$l['ends_at'])) ?></td>
						<td><?php if (in_array($l['status'], array('active', 'settling'), true)): ?>
							<form method="post" action="<?= chaos_h($self . '&admin=1') ?>">
								<input type="hidden" name="csrf" value="<?= chaos_h($csrf) ?>"><input type="hidden" name="id" value="<?= (int)$l['id'] ?>"><input type="hidden" name="admin" value="1">
								<input type="text" name="reason" maxlength="48" placeholder="reason" required>
								<button type="submit" name="do" value="cancel" class="chaos-button">Cancel</button>
							</form>
						<?php endif; ?></td></tr>
				<?php endforeach; ?>
			</tbody></table>
		<?php else: ?>
			<?php $open = $bz->open(); ?>
			<table class="chaos-table" id="chaos-bazaar-open"><thead><tr><th>Character</th><th class="num">Level</th><th>Class</th><th class="num">Bid</th><th class="num">Buyout</th><th>Ends in</th></tr></thead><tbody>
				<?php if (!$open): ?><tr><td colspan="6" class="chaos-muted">No auctions right now.</td></tr><?php endif; ?>
				<?php foreach ($open as $l): ?>
					<tr><td><a href="<?= chaos_h($self . '&id=' . (int)$l['id']) ?>"><?= chaos_h($l['player_name']) ?></a></td><td class="num"><?= (int)$l['level'] ?></td><td><?= chaos_h($class((int)$l['vocation'])) ?></td>
						<td class="num"><?= (int)$l['current_bid'] > 0 ? (int)$l['current_bid'] : (int)$l['min_price'] . ' min' ?></td><td class="num"><?= (int)$l['buyout'] > 0 ? (int)$l['buyout'] : '-' ?></td>
						<td><?= chaos_h($left((int)$l['ends_at'])) ?></td></tr>
				<?php endforeach; ?>
			</tbody></table>
		<?php endif; ?>
	</div>
</div>
