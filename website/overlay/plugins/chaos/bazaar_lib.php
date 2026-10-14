<?php
/**
 * Character Bazaar: player-to-player character auctions for Chaos Coins (pages/bazaar.php, bazaar_worker.php;
 * website/README.md "Character Bazaar"; the game server's login lock: server/data/scripts/chaos/bazaar.lua).
 *
 *  - List: a seller lists one of its characters with a minimum bid, an optional buyout and a duration of 1-7 days.
 *    Only an offline character of level minLevel+, not a guild leader or vice-leader, not a season, Hardcore or
 *    Self-Found character, no staff character, no open player report against it, on an account without an active ban
 *    or a chargeback in chargebackDays. The character cannot log in while listed (the game server's lock).
 *  - Bid: Chaos Coins are taken from the bidder's balance at once and held (escrow); an outbid bidder gets them back at
 *    once. A bid in the last snipeMinutes moves the end. A bid at or over the buyout ends the auction at once. The
 *    seller's own account, a banned account, an account with a recent chargeback or without a free character slot
 *    cannot bid.
 *  - End: no bid -> expired. Else the character moves to the winner's account (players.account_id, while it is offline
 *    and locked; it leaves its guild), the seller gets the price less the house fee (feePct, the coins leave the
 *    economy), the listing is sold. If the character can no longer move (it is online, changed owner, the winner has no
 *    slot, ...) the listing fails and the escrow goes back.
 *  - Cancel: the seller before the first bid; an administrator (admin panel account with a group adminGroup+ character)
 *    at any time, with a reason. Every escrow goes back.
 *  - The seller's account e-mail (its security e-mail) is told when its character is listed, sold, expired, failed or
 *    cancelled; the winner and an outbid bidder are told too. Mail is off without SMTP settings (mail_lib.php).
 *
 * The rules here are a class over ChaosPayDb (pay/Db.php: prepared statements with affected-row counts, mysqli on the
 * site, PDO / SQLite in the tests). Every coin move is one conditional UPDATE inside a transaction: a balance only
 * drops when it holds the amount, a listing only takes a bid when its current bid is still the one the bidder saw.
 * Numbers: the game server's bazaar_config.lua (CHAOS_SERVER_DATA), defaults without it.
 */

if (!class_exists('ChaosBazaar')) {

require_once __DIR__ . '/pay/Db.php';

/** bazaar_config.lua's plain numbers (comments stripped; the defaults below when the file is not readable). */
function chaos_bazaar_config(): array {
	$defaults = array('enabled' => true, 'feePct' => 8, 'minDays' => 1, 'maxDays' => 7, 'minPrice' => 100, 'maxPrice' => 1000000,
		'minStepPct' => 5, 'minStep' => 10, 'minLevel' => 50, 'maxActivePerAccount' => 2, 'maxBidsPerAccountHour' => 20,
		'snipeMinutes' => 5, 'chargebackDays' => 180, 'adminGroup' => 5);
	if (!function_exists('chaos_read_server_file')) {
		return $defaults;
	}
	$text = preg_replace('/--[^\n]*/', '', chaos_read_server_file('scripts/chaos/bazaar_config.lua'));
	$out = $defaults;
	foreach ($defaults as $key => $default) {
		if (is_bool($default)) {
			if (preg_match('/\b' . preg_quote($key, '/') . '\s*=\s*(true|false)\b/', (string)$text, $m)) {
				$out[$key] = $m[1] === 'true';
			}
		} elseif (preg_match('/\b' . preg_quote($key, '/') . '\s*=\s*(-?\d+)\b/', (string)$text, $m)) {
			$out[$key] = (int)$m[1];
		}
	}
	$out['feePct'] = max(5, min(10, $out['feePct'])); // the owner's range (docs/OWNER_TODO.md)
	return $out;
}

final class ChaosBazaar {
	private ChaosPayDb $db;
	private array $cfg;
	/** @var callable(): int */
	private $clock;
	/** @var callable(string $to, string $subject, string $text): bool */
	private $mailer;
	/** @var callable(int $accountId): bool  true when the account may own one more character */
	private $slotFree;
	private array $tables = array();

	public function __construct(ChaosPayDb $db, array $cfg, ?callable $clock = null, ?callable $mailer = null, ?callable $slotFree = null) {
		$this->db = $db;
		$this->cfg = $cfg;
		$this->clock = $clock ?? static function (): int { return time(); };
		$this->mailer = $mailer ?? static function (string $to, string $subject, string $text): bool {
			return function_exists('chaos_mail_send') && chaos_mail_send($to, '', $subject, $text);
		};
		// the same limit as character creation and the game's login (lib.php chaos_character_limit_of: free slots of
		// pact_config.lua plus Character Slots bought), read through this class's own connection (the worker has no db())
		$this->slotFree = $slotFree ?? function (int $accountId): bool {
			if (!function_exists('chaos_character_slot_config') || !function_exists('chaos_character_limit_of')) {
				return true;
			}
			$bought = 0;
			$legacy = 0;
			if ($this->has('chaos_account_extras')) {
				foreach ($this->db->rows("SELECT `extra_key`, `amount` FROM `chaos_account_extras` WHERE `account_id` = ? AND `extra_key` IN ('charSlots', 'charSlotsLegacy');", [$accountId]) as $r) {
					if ($r['extra_key'] === 'charSlots') {
						$bought = (int)$r['amount'];
					} else {
						$legacy = (int)$r['amount'];
					}
				}
			}
			$n = $this->db->rows('SELECT COUNT(*) AS `n` FROM `players` WHERE `account_id` = ?;', [$accountId]);
			return (int)($n[0]['n'] ?? 0) < chaos_character_limit_of(chaos_character_slot_config(), $bought, $legacy);
		};
	}

	public function config(): array { return $this->cfg; }
	private function now(): int { return (int)($this->clock)(); }

	private function has(string $table): bool {
		if (!array_key_exists($table, $this->tables)) {
			try {
				$this->db->rows('SELECT 1 FROM `' . $table . '` LIMIT 1;');
				$this->tables[$table] = true;
			} catch (Throwable $e) {
				$this->tables[$table] = false;
			}
		}
		return $this->tables[$table];
	}

	private function one(string $sql, array $p = array()): ?array {
		$r = $this->db->rows($sql, $p);
		return $r ? $r[0] : null;
	}

	private function log(int $listingId, int $accountId, int $playerId, string $action, string $detail = ''): void {
		$this->db->exec('INSERT INTO `chaos_bazaar_log` (`at`, `listing_id`, `account_id`, `player_id`, `action`, `detail`) VALUES (?, ?, ?, ?, ?, ?);',
			[$this->now(), $listingId, $accountId, $playerId, substr($action, 0, 16), substr($detail, 0, 255)]);
	}

	// ------------------------------------------------------------------ money (Chaos Coins, the game's chaos_shop_coins)
	public function coins(int $accountId): int {
		$r = $this->one('SELECT `coins` FROM `chaos_shop_coins` WHERE `account_id` = ?;', [$accountId]);
		return (int)($r['coins'] ?? 0);
	}

	/** Takes `amount` only when the balance holds it; true when taken. */
	private function take(int $accountId, int $amount): bool {
		return $this->db->exec('UPDATE `chaos_shop_coins` SET `coins` = `coins` - ? WHERE `account_id` = ? AND `coins` >= ?;',
			[$amount, $accountId, $amount]) === 1;
	}

	private function give(int $accountId, int $amount): void {
		if ($amount <= 0) {
			return;
		}
		if ($this->db->exec('UPDATE `chaos_shop_coins` SET `coins` = `coins` + ? WHERE `account_id` = ?;', [$amount, $accountId]) === 0) {
			$this->db->exec('INSERT INTO `chaos_shop_coins` (`account_id`, `coins`) VALUES (?, ?);', [$accountId, $amount]);
		}
	}

	// ------------------------------------------------------------------ numbers
	public function fee(int $price): int {
		return $price <= 0 ? 0 : max(1, intdiv($price * (int)$this->cfg['feePct'], 100));
	}

	public function minNextBid(array $listing): int {
		$cur = (int)$listing['current_bid'];
		if ($cur <= 0) {
			return max((int)$this->cfg['minPrice'], (int)$listing['min_price']);
		}
		return $cur + max((int)$this->cfg['minStep'], intdiv($cur * (int)$this->cfg['minStepPct'], 100));
	}

	// ------------------------------------------------------------------ facts
	public function accountBanned(int $accountId): bool {
		if (!$this->has('account_bans')) {
			return false;
		}
		return (bool)$this->db->rows('SELECT `account_id` FROM `account_bans` WHERE `account_id` = ? AND (`expires_at` <= 0 OR `expires_at` > ?);',
			[$accountId, $this->now()]);
	}

	/** A chargeback or dispute on a donation of the account in chargebackDays. */
	public function accountChargeback(int $accountId): bool {
		if (!$this->has('chaos_coin_payments') || !$this->has('chaos_coin_orders')) {
			return false;
		}
		$since = $this->now() - (int)$this->cfg['chargebackDays'] * 86400;
		return (bool)$this->db->rows("SELECT `p`.`order_id` FROM `chaos_coin_payments` `p` JOIN `chaos_coin_orders` `o` ON `o`.`id` = `p`.`order_id`
			WHERE `o`.`account_id` = ? AND `p`.`reversal` IN ('charged_back', 'disputed') AND (`p`.`reversal_at` = 0 OR `p`.`reversal_at` >= ?);",
			[$accountId, $since]);
	}

	private function online(int $playerId): bool {
		return $this->has('players_online') && (bool)$this->db->rows('SELECT `player_id` FROM `players_online` WHERE `player_id` = ?;', [$playerId]);
	}

	private function guildLeader(int $playerId): bool {
		if ($this->has('guilds') && $this->db->rows('SELECT `id` FROM `guilds` WHERE `ownerid` = ?;', [$playerId])) {
			return true;
		}
		if ($this->has('guild_membership') && $this->has('guild_ranks')) {
			return (bool)$this->db->rows('SELECT `m`.`player_id` FROM `guild_membership` `m` JOIN `guild_ranks` `r` ON `r`.`id` = `m`.`rank_id`
				WHERE `m`.`player_id` = ? AND `r`.`level` >= 2;', [$playerId]);
		}
		return false;
	}

	private function email(int $accountId): string {
		$r = $this->one('SELECT `email` FROM `accounts` WHERE `id` = ?;', [$accountId]);
		return (string)($r['email'] ?? '');
	}

	private function notify(int $accountId, string $subject, string $text): void {
		$to = $this->email($accountId);
		if ($to === '') {
			return;
		}
		try {
			($this->mailer)($to, 'Cinders of Chaos - ' . $subject, $text . "\n\nIf this was not you, change your password at once and contact the staff.");
		} catch (Throwable $e) {
			error_log('[chaos bazaar] mail: ' . $e->getMessage());
		}
	}

	/**
	 * Why `playerId` cannot be listed by `sellerAccount` now: a list of reasons (empty = it can). Also used again right
	 * before the transfer (with $forTransfer: the listing's own lock is expected then).
	 */
	public function blockers(int $playerId, int $sellerAccount, bool $forTransfer = false): array {
		$why = array();
		$p = $this->one('SELECT `id`, `name`, `account_id`, `level`, `group_id`, `deletion` FROM `players` WHERE `id` = ?;', [$playerId]);
		if (!$p || (int)$p['deletion'] !== 0) {
			return array('That character does not exist.');
		}
		if ((int)$p['account_id'] !== $sellerAccount) {
			return array('That character is not on your account.');
		}
		if ((int)$p['group_id'] > 1) {
			$why[] = 'Staff characters cannot be sold.';
		}
		if (!$forTransfer && (int)$p['level'] < (int)$this->cfg['minLevel']) {
			$why[] = sprintf('The character must be level %d or higher.', (int)$this->cfg['minLevel']);
		}
		if ($this->online($playerId)) {
			$why[] = 'Log the character out first.';
		}
		if ($this->guildLeader($playerId)) {
			$why[] = 'A guild leader or vice-leader cannot be sold: pass the rank on first.';
		}
		if ($this->has('chaos_season_players') && $this->db->rows('SELECT `player_id` FROM `chaos_season_players` WHERE `player_id` = ? AND `migrated_at` = 0;', [$playerId])) {
			$why[] = 'Season characters cannot be sold while their season runs.';
		}
		if ($this->has('chaos_season_modes') && $this->db->rows('SELECT `player_id` FROM `chaos_season_modes` WHERE `player_id` = ? AND `reset_at` = 0 AND (`hc` = 1 OR `ssf` = 1);', [$playerId])) {
			$why[] = 'Hardcore and Self-Found characters cannot be sold.';
		}
		if ($this->has('chaos_reports') && $this->db->rows("SELECT `id` FROM `chaos_reports` WHERE `target_name` = ? AND `status` = 'open' AND `reason` <> 'bug';", [(string)$p['name']])) {
			$why[] = 'The character has an open player report: wait for the staff to close it.';
		}
		if ($this->accountBanned($sellerAccount)) {
			$why[] = 'Your account is banned.';
		}
		if ($this->accountChargeback($sellerAccount)) {
			$why[] = 'Your account has a donation chargeback: the bazaar is closed to it.';
		}
		if (!$forTransfer && $this->db->rows("SELECT `id` FROM `chaos_bazaar_listings` WHERE `player_id` = ? AND `status` IN ('active', 'settling');", [$playerId])) {
			$why[] = 'The character is already listed.';
		}
		return $why;
	}

	// ------------------------------------------------------------------ list
	/** Returns [ok, message, listing id]. */
	public function listCharacter(int $sellerAccount, int $playerId, int $minPrice, int $buyout, int $days): array {
		$c = $this->cfg;
		if (empty($c['enabled'])) {
			return array(false, 'The Character Bazaar is closed.', 0);
		}
		if ($days < (int)$c['minDays'] || $days > (int)$c['maxDays']) {
			return array(false, sprintf('An auction runs %d to %d days.', (int)$c['minDays'], (int)$c['maxDays']), 0);
		}
		if ($minPrice < (int)$c['minPrice'] || $minPrice > (int)$c['maxPrice']) {
			return array(false, sprintf('The minimum bid is %d to %d Chaos Coins.', (int)$c['minPrice'], (int)$c['maxPrice']), 0);
		}
		if ($buyout !== 0 && ($buyout <= $minPrice || $buyout > (int)$c['maxPrice'])) {
			return array(false, 'The buyout must be above the minimum bid (or 0 for none).', 0);
		}
		$active = $this->one("SELECT COUNT(*) AS `n` FROM `chaos_bazaar_listings` WHERE `seller_account_id` = ? AND `status` IN ('active', 'settling');", [$sellerAccount]);
		if ((int)($active['n'] ?? 0) >= (int)$c['maxActivePerAccount']) {
			return array(false, sprintf('You can run %d auctions at once.', (int)$c['maxActivePerAccount']), 0);
		}
		$why = $this->blockers($playerId, $sellerAccount);
		if ($why) {
			$this->log(0, $sellerAccount, $playerId, 'list_refused', implode(' ', $why));
			return array(false, implode(' ', $why), 0);
		}
		$p = $this->one('SELECT `name`, `level`, `vocation` FROM `players` WHERE `id` = ?;', [$playerId]);
		$now = $this->now();
		$this->db->exec('INSERT INTO `chaos_bazaar_listings` (`player_id`, `seller_account_id`, `min_price`, `buyout`, `fee_pct`, `status`, `created_at`, `ends_at`,
			`player_name`, `level`, `vocation`) VALUES (?, ?, ?, ?, ?, \'active\', ?, ?, ?, ?, ?);',
			[$playerId, $sellerAccount, $minPrice, $buyout, (int)$c['feePct'], $now, $now + $days * 86400, (string)$p['name'], (int)$p['level'], (int)$p['vocation']]);
		$row = $this->one("SELECT `id` FROM `chaos_bazaar_listings` WHERE `player_id` = ? AND `status` = 'active' ORDER BY `id` DESC LIMIT 1;", [$playerId]);
		$id = (int)($row['id'] ?? 0);
		$this->log($id, $sellerAccount, $playerId, 'list', sprintf('min %d, buyout %d, %d days', $minPrice, $buyout, $days));
		$this->notify($sellerAccount, 'character listed', sprintf("Your character %s was listed on the Character Bazaar (minimum bid %d Chaos Coins%s, ends %s UTC).\nIt cannot log in until the auction ends.",
			$p['name'], $minPrice, $buyout > 0 ? ', buyout ' . $buyout : '', gmdate('Y-m-d H:i', $now + $days * 86400)));
		return array(true, sprintf('%s is listed. It cannot log in until the auction ends.', $p['name']), $id);
	}

	public function listing(int $id): ?array {
		return $this->one('SELECT * FROM `chaos_bazaar_listings` WHERE `id` = ?;', [$id]);
	}

	// ------------------------------------------------------------------ bid
	/** Returns [ok, message]. A bid at or over the buyout buys the character at the buyout price. */
	public function bid(int $accountId, int $listingId, int $amount, string $ip = ''): array {
		$c = $this->cfg;
		$l = $this->listing($listingId);
		$now = $this->now();
		if (!$l || $l['status'] !== 'active' || (int)$l['ends_at'] <= $now) {
			return array(false, 'This auction is not open.');
		}
		if ((int)$l['seller_account_id'] === $accountId) {
			return array(false, 'You cannot bid on your own character.');
		}
		if ($this->accountBanned($accountId) || $this->accountChargeback($accountId)) {
			$this->log($listingId, $accountId, 0, 'bid_refused', 'banned or chargeback');
			return array(false, 'Your account cannot bid on the bazaar.');
		}
		if (!($this->slotFree)($accountId)) {
			return array(false, 'Your account has no free character slot for this character.');
		}
		$recent = $this->one('SELECT COUNT(*) AS `n` FROM `chaos_bazaar_bids` WHERE `account_id` = ? AND `created_at` > ?;', [$accountId, $now - 3600]);
		if ((int)($recent['n'] ?? 0) >= (int)$c['maxBidsPerAccountHour']) {
			return array(false, 'Too many bids this hour. Try again later.');
		}
		$buyout = (int)$l['buyout'] > 0 && $amount >= (int)$l['buyout'];
		if ($buyout) {
			$amount = (int)$l['buyout'];
		} elseif ($amount < $this->minNextBid($l)) {
			return array(false, sprintf('The lowest bid now is %d Chaos Coins.', $this->minNextBid($l)));
		}
		if ($amount > (int)$c['maxPrice']) {
			return array(false, 'That bid is too high.');
		}
		$prevBidId = (int)$l['current_bid_id'];
		$this->db->begin();
		try {
			if (!$this->take($accountId, $amount)) {
				$this->db->rollback();
				return array(false, sprintf('You need %d Chaos Coins (they are held until you are outbid or the auction ends).', $amount));
			}
			$this->db->exec('INSERT INTO `chaos_bazaar_bids` (`listing_id`, `account_id`, `amount`, `escrow`, `buyout`, `state`, `created_at`, `ip`) VALUES (?, ?, ?, ?, ?, \'leading\', ?, ?);',
				[$listingId, $accountId, $amount, $amount, $buyout ? 1 : 0, $now, substr($ip, 0, 64)]);
			$bidRow = $this->one('SELECT `id` FROM `chaos_bazaar_bids` WHERE `listing_id` = ? AND `account_id` = ? ORDER BY `id` DESC LIMIT 1;', [$listingId, $accountId]);
			$bidId = (int)($bidRow['id'] ?? 0);
			$snipe = $now + (int)$c['snipeMinutes'] * 60;
			$ends = $buyout ? $now : max((int)$l['ends_at'], $snipe);
			// the listing takes the bid only if nobody bid since the bidder read it (current_bid_id unchanged)
			$ok = $this->db->exec('UPDATE `chaos_bazaar_listings` SET `current_bid` = ?, `current_bid_id` = ?, `bidder_account_id` = ?, `bids` = `bids` + 1, `ends_at` = ?
				WHERE `id` = ? AND `status` = \'active\' AND `current_bid_id` = ?;', [$amount, $bidId, $accountId, $ends, $listingId, $prevBidId]);
			if ($ok !== 1) {
				$this->db->rollback();
				return array(false, 'Someone bid first: look at the new price.');
			}
			$prev = null;
			if ($prevBidId > 0) {
				$prev = $this->one('SELECT `id`, `account_id`, `escrow` FROM `chaos_bazaar_bids` WHERE `id` = ?;', [$prevBidId]);
				if ($prev && $this->db->exec('UPDATE `chaos_bazaar_bids` SET `state` = \'outbid\', `escrow` = 0 WHERE `id` = ? AND `escrow` > 0;', [$prevBidId]) === 1) {
					$this->give((int)$prev['account_id'], (int)$prev['escrow']);
				}
			}
			$this->db->commit();
		} catch (Throwable $e) {
			$this->db->rollback();
			throw $e;
		}
		$this->log($listingId, $accountId, (int)$l['player_id'], $buyout ? 'buyout' : 'bid', (string)$amount);
		if ($prev && (int)$prev['account_id'] !== $accountId) {
			$this->log($listingId, (int)$prev['account_id'], (int)$l['player_id'], 'refund', 'outbid: ' . (int)$prev['escrow']);
			$this->notify((int)$prev['account_id'], 'outbid', sprintf('You were outbid on %s (%d Chaos Coins). Your %d Chaos Coins are back on your account.',
				$l['player_name'], $amount, (int)$prev['escrow']));
		}
		if ($buyout) {
			$this->settle($listingId);
			return array(true, sprintf('You bought %s for %d Chaos Coins.', $l['player_name'], $amount));
		}
		return array(true, sprintf('You lead with %d Chaos Coins. They are held until you are outbid (then they come back) or you win.', $amount));
	}

	// ------------------------------------------------------------------ end of an auction
	/** Every active listing whose end has passed: expire or sell. Returns the number settled. */
	public function settleDue(): int {
		$n = 0;
		foreach ($this->db->rows("SELECT `id` FROM `chaos_bazaar_listings` WHERE (`status` = 'active' AND `ends_at` <= ?) OR `status` = 'settling' ORDER BY `id` LIMIT 50;", [$this->now()]) as $r) {
			$n += $this->settle((int)$r['id']) ? 1 : 0;
		}
		return $n;
	}

	/** Ends one listing (ended, or bought out). True when it ended now. */
	public function settle(int $listingId): bool {
		$l = $this->listing($listingId);
		if (!$l || ($l['status'] === 'active' && (int)$l['ends_at'] > $this->now())) {
			return false;
		}
		$now = $this->now();
		if ($l['status'] === 'active' && (int)$l['current_bid_id'] === 0) {
			if ($this->db->exec("UPDATE `chaos_bazaar_listings` SET `status` = 'expired', `settled_at` = ? WHERE `id` = ? AND `status` = 'active' AND `current_bid_id` = 0;", [$now, $listingId]) === 1) {
				$this->log($listingId, (int)$l['seller_account_id'], (int)$l['player_id'], 'expired');
				$this->notify((int)$l['seller_account_id'], 'auction ended', sprintf('The auction of %s ended without a bid. The character can log in again.', $l['player_name']));
				return true;
			}
			return false;
		}
		if ($l['status'] === 'active') {
			if ($this->db->exec("UPDATE `chaos_bazaar_listings` SET `status` = 'settling' WHERE `id` = ? AND `status` = 'active';", [$listingId]) !== 1) {
				return false;
			}
			$l['status'] = 'settling';
		}
		if ($l['status'] !== 'settling') {
			return false;
		}
		return $this->transfer($l);
	}

	private function transfer(array $l): bool {
		$listingId = (int)$l['id'];
		$playerId = (int)$l['player_id'];
		$seller = (int)$l['seller_account_id'];
		$buyer = (int)$l['bidder_account_id'];
		$price = (int)$l['current_bid'];
		$why = $this->blockers($playerId, $seller, true);
		if (!($this->slotFree)($buyer)) {
			$why[] = 'The winner has no free character slot.';
		}
		if ($this->accountBanned($buyer)) {
			$why[] = 'The winner is banned.';
		}
		if ($why) {
			$this->fail($l, implode(' ', $why));
			return true;
		}
		$fee = $this->fee($price);
		$now = $this->now();
		$this->db->begin();
		try {
			$bid = $this->one('SELECT `id`, `escrow` FROM `chaos_bazaar_bids` WHERE `id` = ?;', [(int)$l['current_bid_id']]);
			if (!$bid || (int)$bid['escrow'] !== $price
					|| $this->db->exec('UPDATE `chaos_bazaar_bids` SET `state` = \'won\', `escrow` = 0 WHERE `id` = ? AND `escrow` = ?;', [(int)$bid['id'], $price]) !== 1) {
				$this->db->rollback();
				$this->log($listingId, $buyer, $playerId, 'transfer_error', 'escrow does not match the price');
				return false;
			}
			if ($this->db->exec('UPDATE `players` SET `account_id` = ? WHERE `id` = ? AND `account_id` = ?;', [$buyer, $playerId, $seller]) !== 1) {
				$this->db->rollback();
				$this->fail($l, 'The character could not be moved.');
				return true;
			}
			if ($this->has('guild_membership')) {
				$this->db->exec('DELETE FROM `guild_membership` WHERE `player_id` = ?;', [$playerId]);
			}
			$this->give($seller, $price - $fee);
			$this->db->exec("UPDATE `chaos_bazaar_listings` SET `status` = 'sold', `fee` = ?, `settled_at` = ? WHERE `id` = ? AND `status` = 'settling';", [$fee, $now, $listingId]);
			$this->db->commit();
		} catch (Throwable $e) {
			$this->db->rollback();
			throw $e;
		}
		$this->log($listingId, $buyer, $playerId, 'sold', sprintf('%d coins, fee %d, seller %d gets %d', $price, $fee, $seller, $price - $fee));
		$this->notify($seller, 'character sold', sprintf("Your character %s was sold on the Character Bazaar for %d Chaos Coins. The house fee is %d; %d Chaos Coins are on your account.\nThe character now belongs to another account.",
			$l['player_name'], $price, $fee, $price - $fee));
		$this->notify($buyer, 'character won', sprintf('You won %s for %d Chaos Coins. It is on your account now: log in with it from your character list.', $l['player_name'], $price));
		return true;
	}

	/** The listing fails: escrow back to the leader, the character unlocked. */
	private function fail(array $l, string $reason): void {
		$this->refundAll((int)$l['id']);
		$this->db->exec("UPDATE `chaos_bazaar_listings` SET `status` = 'failed', `reason` = ?, `settled_at` = ? WHERE `id` = ?;", [substr($reason, 0, 64), $this->now(), (int)$l['id']]);
		$this->log((int)$l['id'], (int)$l['seller_account_id'], (int)$l['player_id'], 'failed', $reason);
		$this->notify((int)$l['seller_account_id'], 'auction failed', sprintf('The sale of %s could not be completed: %s The character stays yours and can log in again.', $l['player_name'], $reason));
		if ((int)$l['bidder_account_id'] > 0) {
			$this->notify((int)$l['bidder_account_id'], 'auction failed', sprintf('The sale of %s could not be completed: %s Your Chaos Coins are back on your account.', $l['player_name'], $reason));
		}
	}

	private function refundAll(int $listingId): int {
		$n = 0;
		foreach ($this->db->rows('SELECT `id`, `account_id`, `escrow` FROM `chaos_bazaar_bids` WHERE `listing_id` = ? AND `escrow` > 0;', [$listingId]) as $b) {
			if ($this->db->exec('UPDATE `chaos_bazaar_bids` SET `state` = \'refunded\', `escrow` = 0 WHERE `id` = ? AND `escrow` = ?;', [(int)$b['id'], (int)$b['escrow']]) === 1) {
				$this->give((int)$b['account_id'], (int)$b['escrow']);
				$this->log($listingId, (int)$b['account_id'], 0, 'refund', (string)(int)$b['escrow']);
				$n++;
			}
		}
		return $n;
	}

	// ------------------------------------------------------------------ cancel
	/** The seller before any bid, or an administrator at any time. Returns [ok, message]. */
	public function cancel(int $listingId, int $byAccount, bool $admin, string $reason = ''): array {
		$l = $this->listing($listingId);
		if (!$l || !in_array($l['status'], array('active', 'settling'), true)) {
			return array(false, 'This auction cannot be cancelled.');
		}
		if (!$admin && ((int)$l['seller_account_id'] !== $byAccount || (int)$l['current_bid_id'] !== 0 || $l['status'] !== 'active')) {
			return array(false, 'Only an auction without bids can be cancelled by its seller.');
		}
		if ($this->db->exec("UPDATE `chaos_bazaar_listings` SET `status` = 'cancelled', `reason` = ?, `settled_at` = ? WHERE `id` = ? AND `status` = ?;",
				[substr($admin ? 'staff: ' . $reason : 'seller', 0, 64), $this->now(), $listingId, $l['status']]) !== 1) {
			return array(false, 'This auction changed meanwhile: reload the page.');
		}
		$refunds = $this->refundAll($listingId);
		$this->log($listingId, $byAccount, (int)$l['player_id'], 'cancel', ($admin ? 'staff: ' : 'seller') . $reason);
		$this->notify((int)$l['seller_account_id'], 'auction cancelled', sprintf('The auction of %s was cancelled%s. The character can log in again.',
			$l['player_name'], $admin ? ' by the staff' . ($reason !== '' ? ' (' . $reason . ')' : '') : ''));
		if ((int)$l['bidder_account_id'] > 0) {
			$this->notify((int)$l['bidder_account_id'], 'auction cancelled', sprintf('The auction of %s was cancelled. Your Chaos Coins are back on your account.', $l['player_name']));
		}
		return array(true, sprintf('Cancelled; %d bid(s) refunded.', $refunds));
	}

	// ------------------------------------------------------------------ views
	public function open(int $limit = 50): array {
		return $this->db->rows("SELECT * FROM `chaos_bazaar_listings` WHERE `status` = 'active' AND `ends_at` > ? ORDER BY `ends_at` LIMIT ?;", [$this->now(), $limit]);
	}

	public function ofSeller(int $accountId): array {
		return $this->db->rows('SELECT * FROM `chaos_bazaar_listings` WHERE `seller_account_id` = ? ORDER BY `id` DESC LIMIT 20;', [$accountId]);
	}

	public function bidsOf(int $listingId): array {
		return $this->db->rows('SELECT `amount`, `state`, `buyout`, `created_at` FROM `chaos_bazaar_bids` WHERE `listing_id` = ? ORDER BY `id` DESC LIMIT 30;', [$listingId]);
	}

	/** The seller's characters that could be listed: {id, name, level, why = [reasons]}. */
	public function candidates(int $accountId): array {
		$out = array();
		foreach ($this->db->rows('SELECT `id`, `name`, `level` FROM `players` WHERE `account_id` = ? AND `deletion` = 0 ORDER BY `level` DESC;', [$accountId]) as $p) {
			$p['why'] = $this->blockers((int)$p['id'], $accountId);
			$out[] = $p;
		}
		return $out;
	}

	public function adminRecent(int $limit = 50): array {
		return $this->db->rows('SELECT * FROM `chaos_bazaar_listings` ORDER BY `id` DESC LIMIT ?;', [$limit]);
	}
}

/** The bazaar of this site (mysqli with ZnoteX's credentials). */
function chaos_bazaar(array $config): ChaosBazaar {
	static $bz = null;
	if ($bz === null) {
		$bz = $GLOBALS['chaos_bazaar'] ?? new ChaosBazaar(ChaosPayMysqli::fromConfig($config), chaos_bazaar_config());
	}
	return $bz;
}

/** An admin panel account with a character of group adminGroup (5) or higher. */
function chaos_bazaar_is_admin(array $config, int $accountId): bool {
	require_once __DIR__ . '/reports_lib.php';
	if (!chaos_reports_is_admin($config, $accountId)) {
		return false;
	}
	$row = db()->fetchOne('SELECT MAX(`group_id`) AS `g` FROM `players` WHERE `account_id` = ?;', [$accountId]);
	return is_array($row) && (int)($row['g'] ?? 0) >= (int)chaos_bazaar_config()['adminGroup'];
}

} // class_exists guard
