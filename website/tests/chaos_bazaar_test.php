<?php
// php website/tests/chaos_bazaar_test.php : the Character Bazaar (plugins/chaos/bazaar_lib.php) over an in-memory
// SQLite database with the game's tables: listing rules and every blocked case (offline, guild leader / vice-leader,
// season, Hardcore, Self-Found, open report, ban, chargeback, staff, level, already listed), bids with the escrow
// (balance held, outbid refunds, the step, the snipe extension, own / banned / poor bidders), the fee and the transfer
// at the end (account moved, seller paid less the fee, guild left, mails), expiry, buyout, cancel (seller, staff),
// a failed transfer, two list requests at once (the unique open-listing key), two characters of one seller listed at
// once (the per-seller slot key), the install steps for duplicates and seller slots, and
// the coins kept whole. No ZnoteX, no network. Exit status 0 when every check passes.
$config = array('chaos' => array('server_data' => __DIR__ . '/../../server/data'));
$GLOBALS['config'] = $config;
require __DIR__ . '/../overlay/plugins/chaos/lib.php';
require __DIR__ . '/../overlay/plugins/chaos/bazaar_lib.php';

$failed = 0;
$checks = 0;
function check(bool $ok, string $what): void {
	global $failed, $checks;
	$checks++;
	if (!$ok) { $failed++; echo "FAIL: $what\n"; }
}

$pdo = new PDO('sqlite::memory:');
$db = new ChaosPayPdo($pdo);
$schema = array(
	"CREATE TABLE accounts (id INTEGER PRIMARY KEY, email TEXT NOT NULL DEFAULT '')",
	"CREATE TABLE players (id INTEGER PRIMARY KEY, name TEXT, account_id INT, level INT, vocation INT DEFAULT 4, group_id INT DEFAULT 1, deletion INT DEFAULT 0)",
	"CREATE TABLE players_online (player_id INT PRIMARY KEY)",
	"CREATE TABLE guilds (id INTEGER PRIMARY KEY, name TEXT, ownerid INT)",
	"CREATE TABLE guild_ranks (id INTEGER PRIMARY KEY, guild_id INT, name TEXT, level INT)",
	"CREATE TABLE guild_membership (player_id INT PRIMARY KEY, guild_id INT, rank_id INT, nick TEXT DEFAULT '')",
	"CREATE TABLE account_bans (account_id INT PRIMARY KEY, expires_at INT)",
	"CREATE TABLE chaos_shop_coins (account_id INT PRIMARY KEY, coins INT NOT NULL DEFAULT 0)",
	"CREATE TABLE chaos_season_players (player_id INT PRIMARY KEY, account_id INT, season INT, joined_at INT, migrated_at INT DEFAULT 0)",
	"CREATE TABLE chaos_season_modes (player_id INT PRIMARY KEY, season INT, ssf INT DEFAULT 0, hc INT DEFAULT 0, chosen_at INT, reset_at INT DEFAULT 0)",
	"CREATE TABLE chaos_reports (id INTEGER PRIMARY KEY, target_name TEXT, reason TEXT, status TEXT)",
	"CREATE TABLE chaos_coin_orders (id INTEGER PRIMARY KEY, account_id INT, status TEXT)",
	"CREATE TABLE chaos_coin_payments (order_id INT PRIMARY KEY, reversal TEXT DEFAULT '', reversal_at INT DEFAULT 0)",
	"CREATE TABLE chaos_bazaar_listings (id INTEGER PRIMARY KEY AUTOINCREMENT, player_id INT, seller_account_id INT, min_price INT, buyout INT DEFAULT 0,
		current_bid INT DEFAULT 0, current_bid_id INT DEFAULT 0, bidder_account_id INT DEFAULT 0, bids INT DEFAULT 0, fee_pct INT DEFAULT 0, fee INT DEFAULT 0,
		status TEXT DEFAULT 'active', reason TEXT DEFAULT '', created_at INT, ends_at INT, settled_at INT DEFAULT 0, player_name TEXT DEFAULT '',
		level INT DEFAULT 0, vocation INT DEFAULT 0,
		active_player_id INT GENERATED ALWAYS AS (CASE WHEN status IN ('active', 'settling') THEN player_id ELSE NULL END) STORED,
		seller_slot INT DEFAULT NULL,
		active_seller_id INT GENERATED ALWAYS AS (CASE WHEN status IN ('active', 'settling') THEN seller_account_id ELSE NULL END) STORED)",
	"CREATE UNIQUE INDEX chaos_bazaar_listings_active ON chaos_bazaar_listings (active_player_id)",
	"CREATE UNIQUE INDEX chaos_bazaar_listings_seller_slot ON chaos_bazaar_listings (active_seller_id, seller_slot)",
	"CREATE TABLE chaos_bazaar_bids (id INTEGER PRIMARY KEY AUTOINCREMENT, listing_id INT, account_id INT, amount INT, escrow INT DEFAULT 0,
		buyout INT DEFAULT 0, state TEXT DEFAULT 'leading', created_at INT, ip TEXT DEFAULT '')",
	"CREATE TABLE chaos_bazaar_log (id INTEGER PRIMARY KEY AUTOINCREMENT, at INT, listing_id INT, account_id INT, player_id INT, action TEXT, detail TEXT)",
);
foreach ($schema as $sql) {
	$pdo->exec($sql);
}
// invented accounts and characters only
$pdo->exec("INSERT INTO accounts (id, email) VALUES (1, 'seller@example.invalid'), (2, 'bidder@example.invalid'), (3, 'rival@example.invalid'),
	(4, 'banned@example.invalid'), (5, 'cb@example.invalid'), (6, 'full@example.invalid')");
$pdo->exec("INSERT INTO players (id, name, account_id, level, group_id) VALUES
	(10, 'Ashen Vale', 1, 200, 1), (11, 'Online Oren', 1, 150, 1), (12, 'Leader Lysa', 1, 150, 1), (13, 'Vice Varn', 1, 150, 1),
	(14, 'Season Sera', 1, 150, 1), (15, 'Hardcore Hal', 1, 150, 1), (16, 'Selffound Sil', 1, 150, 1), (17, 'Reported Rik', 1, 150, 1),
	(18, 'Lowly Lem', 1, 10, 1), (19, 'Gamemaster Gil', 1, 150, 3), (20, 'Bidder Bo', 2, 100, 1), (30, 'Rival Ru', 3, 100, 1),
	(40, 'Banned Ben', 4, 200, 1), (50, 'Charged Cy', 5, 200, 1), (21, 'Second Sale', 1, 120, 1), (22, 'Third Sale', 1, 120, 1)");
$pdo->exec("INSERT INTO players_online VALUES (11)");
$pdo->exec("INSERT INTO guilds (id, name, ownerid) VALUES (1, 'Embers', 12)");
$pdo->exec("INSERT INTO guild_ranks (id, guild_id, name, level) VALUES (1, 1, 'Leader', 3), (2, 1, 'Vice', 2), (3, 1, 'Member', 1)");
$pdo->exec("INSERT INTO guild_membership (player_id, guild_id, rank_id) VALUES (12, 1, 1), (13, 1, 2), (10, 1, 3)");
$pdo->exec("INSERT INTO chaos_season_players VALUES (14, 1, 1, 100, 0)");
$pdo->exec("INSERT INTO chaos_season_modes (player_id, season, ssf, hc, chosen_at, reset_at) VALUES (15, 1, 0, 1, 100, 0), (16, 1, 1, 0, 100, 0)");
$pdo->exec("INSERT INTO chaos_reports (target_name, reason, status) VALUES ('Reported Rik', 'botting', 'open'), ('Ashen Vale', 'bug', 'open')");
$pdo->exec("INSERT INTO account_bans VALUES (4, 0)");
$pdo->exec("INSERT INTO chaos_coin_orders VALUES (1, 5, 'credited')");
$pdo->exec("INSERT INTO chaos_coin_payments (order_id, reversal, reversal_at) VALUES (1, 'charged_back', 0)");
$pdo->exec("INSERT INTO chaos_shop_coins VALUES (1, 0), (2, 5000), (3, 5000), (4, 5000), (5, 5000)");

$now = 1800000000;
$mails = array();
$cfg = chaos_bazaar_config();
$bz = new ChaosBazaar($db, $cfg, function () use (&$now) { return $now; },
	function (string $to, string $subject, string $text) use (&$mails) { $mails[] = array($to, $subject, $text); return true; });
$coins = function (int $acc) use ($bz) { return $bz->coins($acc); };
$total = function () use ($pdo) { return (int)$pdo->query('SELECT SUM(coins) FROM chaos_shop_coins')->fetchColumn()
	+ (int)$pdo->query('SELECT COALESCE(SUM(escrow), 0) FROM chaos_bazaar_bids')->fetchColumn(); };
$start = $total();

// ---------------------------------------------------------------- the config the site reads (server bazaar_config.lua)
check($cfg['feePct'] >= 5 && $cfg['feePct'] <= 10, 'fee 5-10 % from bazaar_config.lua: ' . $cfg['feePct']);
check($cfg['minDays'] === 1 && $cfg['maxDays'] === 7, 'auctions 1-7 days');
$lua = file_get_contents(__DIR__ . '/../../server/data/scripts/chaos/bazaar_config.lua');
check(preg_match('/\bfeePct = (\d+)/', $lua, $m) && (int)$m[1] === $cfg['feePct'], 'fee read from the Lua file');
check($bz->fee(1000) === intdiv(1000 * $cfg['feePct'], 100), 'fee of 1000');
check($bz->fee(3) === 1, 'at least one coin');

// ---------------------------------------------------------------- listing: blocked cases
$blocked = array(
	11 => 'Log the character out', 12 => 'guild leader', 13 => 'guild leader', 14 => 'Season characters', 15 => 'Hardcore and Self-Found',
	16 => 'Hardcore and Self-Found', 17 => 'open player report', 18 => 'level', 19 => 'Staff characters', 20 => 'not on your account',
);
foreach ($blocked as $pid => $needle) {
	[$ok, $msg] = $bz->listCharacter(1, $pid, 500, 0, 3);
	check(!$ok && stripos($msg, $needle) !== false, "player $pid blocked ($needle): $msg");
}
[$ok, $msg] = $bz->listCharacter(4, 40, 500, 0, 3);
check(!$ok && strpos($msg, 'banned') !== false, 'banned seller blocked');
[$ok, $msg] = $bz->listCharacter(5, 50, 500, 0, 3);
check(!$ok && strpos($msg, 'chargeback') !== false, 'seller with a chargeback blocked');
[$ok, $msg] = $bz->listCharacter(1, 10, 500, 0, 8);
check(!$ok && strpos($msg, '1 to 7 days') !== false, '8 days refused');
[$ok, $msg] = $bz->listCharacter(1, 10, 500, 0, 0);
check(!$ok, '0 days refused');
[$ok, $msg] = $bz->listCharacter(1, 10, 5, 0, 3);
check(!$ok && strpos($msg, 'minimum bid') !== false, 'price under the bazaar minimum refused');
[$ok, $msg] = $bz->listCharacter(1, 10, 500, 400, 3);
check(!$ok && strpos($msg, 'buyout') !== false, 'buyout under the minimum refused');
check(count($mails) === 0, 'no mail for a refusal');

// a listing that works (a bug report against it does not block it)
[$ok, $msg, $lid] = $bz->listCharacter(1, 10, 500, 3000, 3);
check($ok && $lid > 0, 'Ashen Vale listed: ' . $msg);
check(count($mails) === 1 && $mails[0][0] === 'seller@example.invalid' && strpos($mails[0][2], 'Ashen Vale') !== false, 'the seller\'s security e-mail is told');
[$ok, $msg] = $bz->listCharacter(1, 10, 500, 0, 3);
check(!$ok && strpos($msg, 'already listed') !== false, 'listed twice refused');
[$ok] = $bz->listCharacter(1, 21, 500, 0, 3);
check($ok, 'second auction');
[$ok, $msg] = $bz->listCharacter(1, 22, 500, 0, 3);
check(!$ok && strpos($msg, 'auctions at once') !== false, 'max active auctions per seller');

// ---------------------------------------------------------------- bids and escrow
[$ok, $msg] = $bz->bid(1, $lid, 600, '1.1.1.1');
check(!$ok && strpos($msg, 'own character') !== false, 'seller cannot bid');
[$ok, $msg] = $bz->bid(2, $lid, 499, '2.2.2.2');
check(!$ok && strpos($msg, '500') !== false, 'under the minimum refused');
[$ok, $msg] = $bz->bid(4, $lid, 600, '4.4.4.4');
check(!$ok && strpos($msg, 'cannot bid') !== false, 'banned bidder refused');
[$ok, $msg] = $bz->bid(5, $lid, 600, '5.5.5.5');
check(!$ok, 'bidder with a chargeback refused');
[$ok, $msg] = $bz->bid(6, $lid, 600, '6.6.6.6');
check(!$ok && strpos($msg, 'need 600') !== false, 'a bidder without the coins refused');
[$ok, $msg] = $bz->bid(2, $lid, 600, '2.2.2.2');
check($ok, 'first bid: ' . $msg);
check($coins(2) === 4400, 'escrow: 600 held from the bidder');
$l = $bz->listing($lid);
check((int)$l['current_bid'] === 600 && (int)$l['bidder_account_id'] === 2 && (int)$l['bids'] === 1, 'listing leads with 600');
$next = $bz->minNextBid($l);
check($next === 600 + max($cfg['minStep'], intdiv(600 * $cfg['minStepPct'], 100)), 'the next step');
[$ok, $msg] = $bz->bid(3, $lid, $next - 1, '3.3.3.3');
check(!$ok, 'under the step refused');
$mailsBefore = count($mails);
[$ok, $msg] = $bz->bid(3, $lid, 800, '3.3.3.3');
check($ok, 'outbid with 800');
check($coins(2) === 5000, 'the outbid bidder got the 600 back at once');
check($coins(3) === 4200, '800 held from the new leader');
check(count($mails) === $mailsBefore + 1 && $mails[count($mails) - 1][0] === 'bidder@example.invalid', 'the outbid bidder is told');
check($total() === $start, 'coins kept whole (balances + escrow)');
// a bid in the last minutes moves the end
$now = (int)$bz->listing($lid)['ends_at'] - 60;
[$ok] = $bz->bid(2, $lid, 1000, '2.2.2.2');
check($ok && (int)$bz->listing($lid)['ends_at'] === $now + $cfg['snipeMinutes'] * 60, 'snipe: the end moved');
check($coins(3) === 5000 && $coins(2) === 4000, 'refund and hold after the snipe bid');

// ---------------------------------------------------------------- the end: transfer, fee, seller paid
$now += $cfg['snipeMinutes'] * 60 + 1;
[$ok, $msg] = $bz->bid(3, $lid, 2000, '3.3.3.3');
check(!$ok, 'no bid after the end');
$mailsBefore = count($mails);
check($bz->settleDue() >= 1, 'settled');
$l = $bz->listing($lid);
$fee = $bz->fee(1000);
check($l['status'] === 'sold' && (int)$l['fee'] === $fee, 'sold with the fee ' . $fee);
check((int)$pdo->query('SELECT account_id FROM players WHERE id = 10')->fetchColumn() === 2, 'the character moved to the winner');
check($coins(1) === 1000 - $fee, 'the seller got the price less the fee');
check($coins(2) === 4000, 'the winner\'s escrow was spent');
check((int)$pdo->query("SELECT escrow FROM chaos_bazaar_bids WHERE listing_id = $lid AND state = 'won'")->fetchColumn() === 0, 'winning bid: no escrow left');
check((int)$pdo->query('SELECT COUNT(*) FROM guild_membership WHERE player_id = 10')->fetchColumn() === 0, 'the character left its guild');
check($total() === $start - $fee, 'only the fee left the economy');
$to = array_map(function ($m) { return $m[0]; }, array_slice($mails, $mailsBefore));
check(in_array('seller@example.invalid', $to, true) && in_array('bidder@example.invalid', $to, true), 'seller and winner are told');
check($bz->settle($lid) === false, 'a sold listing does not settle twice');

// ---------------------------------------------------------------- expiry without a bid
$l2 = (int)$pdo->query("SELECT id FROM chaos_bazaar_listings WHERE player_id = 21")->fetchColumn();
$now += 3 * 86400 + 10;
$bz->settleDue();
check($bz->listing($l2)['status'] === 'expired', 'no bid: expired');
check((int)$pdo->query('SELECT account_id FROM players WHERE id = 21')->fetchColumn() === 1, 'an expired character stays');

// ---------------------------------------------------------------- buyout
[$ok, $msg, $l3] = $bz->listCharacter(1, 22, 500, 1500, 2);
check($ok, 'listed with a buyout');
[$ok, $msg] = $bz->bid(3, $l3, 99999, '3.3.3.3');
check($ok && strpos($msg, 'bought') !== false, 'a bid over the buyout buys at the buyout: ' . $msg);
check($bz->listing($l3)['status'] === 'sold' && (int)$bz->listing($l3)['current_bid'] === 1500, 'sold at once, at the buyout price');
check($coins(3) === 3500, 'the buyer paid the buyout, not the bid typed');
check((int)$pdo->query('SELECT account_id FROM players WHERE id = 22')->fetchColumn() === 3, 'moved to the buyer');

// ---------------------------------------------------------------- cancel
$pdo->exec("INSERT INTO players (id, name, account_id, level) VALUES (23, 'Cancel Cal', 1, 120), (24, 'Staff Cancel', 1, 120), (25, 'Fail Fay', 1, 120)");
[$ok, , $l4] = $bz->listCharacter(1, 23, 500, 0, 3);
[$ok, $msg] = $bz->cancel($l4, 2, false);
check(!$ok, 'someone else cannot cancel');
[$ok, $msg] = $bz->cancel($l4, 1, false);
check($ok && $bz->listing($l4)['status'] === 'cancelled', 'the seller cancels before a bid');
[$ok, , $l5] = $bz->listCharacter(1, 24, 500, 0, 3);
$bz->bid(2, $l5, 700, '2.2.2.2');
[$ok, $msg] = $bz->cancel($l5, 1, false);
check(!$ok, 'the seller cannot cancel after a bid');
$before = $coins(2);
[$ok, $msg] = $bz->cancel($l5, 99, true, 'real-money trade report');
check($ok && $bz->listing($l5)['status'] === 'cancelled', 'staff cancel with a bid');
check($coins(2) === $before + 700, 'staff cancel refunds the escrow');
check(strpos($bz->listing($l5)['reason'], 'real-money') !== false, 'the reason is kept');

// ---------------------------------------------------------------- a failed transfer (the character logged in somehow)
[$ok, , $l6] = $bz->listCharacter(1, 25, 500, 0, 1);
$bz->bid(2, $l6, 900, '2.2.2.2');
$pdo->exec('INSERT INTO players_online VALUES (25)');
$before = $coins(2);
$now += 86400 + 10;
$bz->settleDue();
check($bz->listing($l6)['status'] === 'failed', 'online at the end: failed');
check($coins(2) === $before + 900, 'the winner got the escrow back');
check((int)$pdo->query('SELECT account_id FROM players WHERE id = 25')->fetchColumn() === 1, 'the character stays with the seller');

// ---------------------------------------------------------------- no free slot for the winner
$full = new ChaosBazaar($db, $cfg, function () use (&$now) { return $now; }, function () { return true; }, function (int $a) { return $a !== 3; });
$pdo->exec("DELETE FROM players_online");
$pdo->exec("INSERT INTO players (id, name, account_id, level) VALUES (26, 'Slot Sam', 1, 120)");
[$ok, , $l7] = $full->listCharacter(1, 26, 500, 0, 1);
[$ok, $msg] = $full->bid(3, $l7, 600, '3.3.3.3');
check(!$ok && strpos($msg, 'slot') !== false, 'no free character slot: no bid');

// ---------------------------------------------------------------- races (another request between a read and a write)
// the seller's cancel read the listing without a bid; a bid lands before the cancel's UPDATE: the cancel must fail
$pdo->exec("INSERT INTO players (id, name, account_id, level) VALUES (27, 'Race Ria', 1, 120), (28, 'Twice Tor', 1, 120)");
$hook = null;
$raceClock = function () use (&$now, &$hook) { if ($hook) { $h = $hook; $hook = null; $h(); } return $now; };
$race = new ChaosBazaar($db, $cfg, $raceClock, function () { return true; });
[$ok, , $l8] = $race->listCharacter(1, 27, 500, 0, 2);
$hook = function () use ($bz, $l8) { $bz->bid(2, $l8, 600, '2.2.2.2'); };
[$ok, $msg] = $race->cancel($l8, 1, false);
check(!$ok && $race->listing($l8)['status'] === 'active', 'a bid that lands during the seller cancel keeps the auction: ' . $msg);
check((int)$race->listing($l8)['current_bid'] === 600, 'the bid stands');
[$ok] = $bz->cancel($l8, 99, true, 'test cleanup');
// two settles of one listing (the page and the worker): the second sees a blocker only after the first sold it; the
// sold listing must stay sold (it was turned into "failed" with mails saying the sale did not happen)
$inner = false;
$slotHook = null;
$twice = new ChaosBazaar($db, $cfg, function () use (&$now) { return $now; }, function () { return true; },
	function (int $a) use (&$slotHook) { if ($slotHook) { $h = $slotHook; $slotHook = null; $h(); return false; } return true; });
[$ok, , $l9] = $twice->listCharacter(1, 28, 500, 0, 1);
$twice->bid(2, $l9, 800, '2.2.2.2');
$now += 86400 + 10;
$pdo->exec("UPDATE chaos_bazaar_listings SET status = 'settling' WHERE id = $l9");
$sellerBefore = $coins(1);
$bidderBefore = $coins(2);
$slotHook = function () use ($bz, $l9) { $bz->settle($l9); }; // the other request completes the sale meanwhile
$twice->settle($l9);
check($twice->listing($l9)['status'] === 'sold', 'a sold listing stays sold after a late second settle: ' . $twice->listing($l9)['status']);
check((int)$pdo->query('SELECT account_id FROM players WHERE id = 28')->fetchColumn() === 2, 'the character went to the winner once');
check($coins(1) === $sellerBefore + 800 - $bz->fee(800) && $coins(2) === $bidderBefore, 'paid once, nothing refunded twice');

// two list requests for one character at once: both pass the "already listed" check before either INSERT. The
// database's unique key (active_player_id) lets one in; the other gets a clear refusal, no second listing.
final class RaceDb implements ChaosPayDb {
	public $hook = null;
	public function __construct(private ChaosPayDb $db) {}
	public function rows(string $sql, array $p = array()): array { return $this->db->rows($sql, $p); }
	public function exec(string $sql, array $p = array()): int {
		if ($this->hook && stripos($sql, 'INSERT INTO `chaos_bazaar_listings`') === 0) { $h = $this->hook; $this->hook = null; $h(); }
		return $this->db->exec($sql, $p);
	}
	public function begin(): void { $this->db->begin(); }
	public function commit(): void { $this->db->commit(); }
	public function rollback(): void { $this->db->rollback(); }
}
$pdo->exec("INSERT INTO players (id, name, account_id, level) VALUES (29, 'Double Dax', 1, 120)");
$rdb = new RaceDb($db);
$raceList = new ChaosBazaar($rdb, $cfg, function () use (&$now) { return $now; }, function () { return true; });
$other = null;
$rdb->hook = function () use ($bz, &$other) { $other = $bz->listCharacter(1, 29, 500, 0, 2); };
$mine = $raceList->listCharacter(1, 29, 600, 0, 2);
check(is_array($other) && $other[0] === true, 'the other request listed the character first');
check($mine[0] === false && strpos($mine[1], 'already listed') !== false && $mine[2] === 0, 'the concurrent list is refused: ' . $mine[1]);
check((int)$pdo->query("SELECT COUNT(*) FROM chaos_bazaar_listings WHERE player_id = 29 AND status IN ('active', 'settling')")->fetchColumn() === 1, 'one open listing for the character');
$threw = false;
try {
	$pdo->exec("INSERT INTO chaos_bazaar_listings (player_id, seller_account_id, min_price, status, created_at, ends_at) VALUES (29, 1, 500, 'settling', 1, 2)");
} catch (PDOException $e) {
	$threw = true;
}
check($threw, 'the database itself refuses a second open listing (unique key)');
// the flows still free the key: cancel, then relist; sold, expired and failed rows do not block a new listing
[$ok] = $bz->cancel((int)$other[2], 1, false);
check($ok, 'the seller cancels the race winner');
[$ok, $msg, $l10] = $bz->listCharacter(1, 29, 500, 0, 1);
check($ok, 'relisted after the cancel: ' . $msg);
$bz->bid(2, $l10, 700, '2.2.2.2');
$pdo->exec('INSERT INTO players_online VALUES (29)');
$now += 86400 + 10;
$bz->settleDue();
check($bz->listing($l10)['status'] === 'failed', 'the relisted auction failed (online at the end)');
$pdo->exec('DELETE FROM players_online WHERE player_id = 29');
[$ok, $msg, $l11] = $bz->listCharacter(1, 29, 500, 0, 1);
check($ok, 'relisted after a failed transfer: ' . $msg);
$now += 86400 + 10;
$bz->settleDue();
check($bz->listing($l11)['status'] === 'expired', 'expired');
[$ok, $msg, $l12] = $bz->listCharacter(1, 29, 500, 0, 1);
check($ok, 'relisted after expiry: ' . $msg);
$bz->bid(3, $l12, 600, '3.3.3.3');
$now += 86400 + 10;
$bz->settleDue();
check($bz->listing($l12)['status'] === 'sold', 'the relisted character sold');
// two characters of one seller listed at once: both requests pass the maxActivePerAccount count before either INSERT.
// The unique key on (active_seller_id, seller_slot) lets the first into the last free slot; the other reads the slots
// again, finds none and gets the per-seller refusal. The seller never runs more than maxActivePerAccount auctions.
check($cfg['maxActivePerAccount'] === 2, 'two auctions per seller (the race below fills the second slot)');
$pdo->exec("INSERT INTO accounts (id, email) VALUES (7, 'twin@example.invalid')");
$pdo->exec("INSERT INTO players (id, name, account_id, level) VALUES (60, 'Twin Ama', 7, 120), (61, 'Twin Bex', 7, 120), (62, 'Twin Cal', 7, 120)");
[$ok, , $t1] = $bz->listCharacter(7, 60, 500, 0, 2);
check($ok, 'the seller\'s first auction');
$other = null;
$rdb->hook = function () use ($bz, &$other) { $other = $bz->listCharacter(7, 61, 500, 0, 2); };
$mine = $raceList->listCharacter(7, 62, 500, 0, 2);
check(is_array($other) && $other[0] === true, 'the other request listed a second character of the seller first');
check($mine[0] === false && strpos($mine[1], 'auctions at once') !== false && $mine[2] === 0, 'the concurrent third listing is refused: ' . $mine[1]);
$openOf7 = function () use ($pdo) { return (int)$pdo->query("SELECT COUNT(*) FROM chaos_bazaar_listings WHERE seller_account_id = 7 AND status IN ('active', 'settling')")->fetchColumn(); };
check($openOf7() === 2, 'the seller runs two auctions, not three');
check((int)$pdo->query("SELECT COUNT(*) FROM chaos_bazaar_log WHERE account_id = 7 AND action = 'list_refused' AND detail LIKE 'auction limit%'")->fetchColumn() === 1, 'the refusal is logged');
$threw = false;
try {
	$pdo->exec("INSERT INTO chaos_bazaar_listings (player_id, seller_account_id, seller_slot, min_price, status, created_at, ends_at) VALUES (62, 7, 1, 500, 'active', 1, 2)");
} catch (PDOException $e) {
	$threw = true;
}
check($threw, 'the database itself refuses a second open listing in one seller slot (unique key)');
[$ok] = $bz->cancel($t1, 7, false);
check($ok, 'the seller cancels the first auction');
[$ok, $msg, $t3] = $bz->listCharacter(7, 62, 500, 0, 2);
check($ok && (int)$bz->listing($t3)['seller_slot'] === 1, 'the freed slot is listed again: ' . $msg);
foreach (array((int)$other[2], $t3) as $id) {
	$bz->cancel($id, 99, true, 'test cleanup');
}
check($openOf7() === 0, 'cleanup');
// the install step for open listings made before seller_slot: each gets its seller's lowest free slot, once
$pdo->exec("INSERT INTO chaos_bazaar_listings (player_id, seller_account_id, min_price, status, created_at, ends_at) VALUES
	(60, 7, 500, 'active', 1, 2), (61, 7, 500, 'settling', 1, 2), (62, 7, 500, 'sold', 1, 2)");
check($bz->assignSellerSlots() === 2, 'the install step gives a slot to the two open legacy rows');
check(array_map('intval', $pdo->query("SELECT seller_slot FROM chaos_bazaar_listings WHERE seller_account_id = 7 AND status IN ('active', 'settling') ORDER BY id")->fetchAll(PDO::FETCH_COLUMN)) === array(1, 2), 'slots 1 and 2');
check($bz->assignSellerSlots() === 0, 'the slot step runs twice harmlessly');
[$ok, $msg] = $bz->listCharacter(7, 62, 500, 0, 2);
check(!$ok && strpos($msg, 'auctions at once') !== false, 'legacy rows count against the limit');
$pdo->exec("UPDATE chaos_bazaar_listings SET status = 'cancelled' WHERE seller_account_id = 7 AND status IN ('active', 'settling')");
// the install step for a table made before the key: duplicates from the old race keep the oldest, the rest are
// cancelled with their escrow refunded
$pdo->exec("INSERT INTO players (id, name, account_id, level) VALUES (31, 'Legacy Lou', 1, 120)");
$pdo->exec('DROP INDEX chaos_bazaar_listings_active');
$pdo->exec("INSERT INTO chaos_bazaar_listings (player_id, seller_account_id, min_price, status, created_at, ends_at, player_name) VALUES
	(31, 1, 500, 'active', $now, " . ($now + 86400) . ", 'Legacy Lou'), (31, 1, 500, 'active', $now, " . ($now + 86400) . ", 'Legacy Lou')");
$dupIds = array_map('intval', $pdo->query('SELECT id FROM chaos_bazaar_listings WHERE player_id = 31 ORDER BY id')->fetchAll(PDO::FETCH_COLUMN));
$before = $coins(2);
$bz->bid(2, $dupIds[1], 650, '2.2.2.2');
$cancelled = $bz->cancelDuplicateListings();
check($cancelled === array($dupIds[1]), 'the install step cancels the newer duplicate only');
check($bz->listing($dupIds[0])['status'] === 'active' && $bz->listing($dupIds[1])['status'] === 'cancelled', 'the oldest listing stays open');
check($coins(2) === $before, 'the duplicate\'s escrow was refunded');
check($bz->cancelDuplicateListings() === array(), 'the install step runs twice harmlessly');
$pdo->exec('CREATE UNIQUE INDEX chaos_bazaar_listings_active ON chaos_bazaar_listings (active_player_id)');
[$ok] = $bz->cancel($dupIds[0], 99, true, 'test cleanup');
foreach (array(__DIR__ . '/../overlay/plugins/chaos/install.sql', __DIR__ . '/../../server/sql/chaos_bazaar.sql') as $f) {
	$sql = (string)file_get_contents($f);
	check(strpos($sql, "`active_player_id` int(11) GENERATED ALWAYS AS (CASE WHEN `status` IN ('active', 'settling') THEN `player_id` ELSE NULL END) STORED") !== false
		&& strpos($sql, 'UNIQUE KEY `chaos_bazaar_listings_active` (`active_player_id`)') !== false, basename($f) . ': the unique open-listing key');
	check(strpos($sql, "`active_seller_id` int(11) GENERATED ALWAYS AS (CASE WHEN `status` IN ('active', 'settling') THEN `seller_account_id` ELSE NULL END) STORED") !== false
		&& strpos($sql, 'UNIQUE KEY `chaos_bazaar_listings_seller_slot` (`active_seller_id`, `seller_slot`)') !== false, basename($f) . ': the per-seller slot key');
}
$setup = (string)file_get_contents(__DIR__ . '/../setup/chaos_setup.php');
check(strpos($setup, "SHOW COLUMNS FROM `chaos_bazaar_listings` LIKE 'active_player_id'") !== false && strpos($setup, 'cancelDuplicateListings()') !== false
	&& strpos($setup, 'ADD UNIQUE KEY `chaos_bazaar_listings_active`') !== false, 'setup adds the key to an existing table once');
check(strpos($setup, "WHERE `Key_name` = 'chaos_bazaar_listings_seller_slot'") !== false && strpos($setup, 'assignSellerSlots()') !== false
	&& strpos($setup, 'ADD UNIQUE KEY `chaos_bazaar_listings_seller_slot` (`active_seller_id`, `seller_slot`)') !== false, 'setup adds the seller slot key to an existing table once');

check($total() === $start - $bz->fee(1000) - $bz->fee(1500) - $bz->fee(800) - $bz->fee(600), 'coins whole after everything (only the fees left)');
check((int)$pdo->query("SELECT COUNT(*) FROM chaos_bazaar_log WHERE action = 'list_refused'")->fetchColumn() > 0, 'refusals logged');

// ---------------------------------------------------------------- the files
foreach (array('bazaar_lib.php', 'bazaar_worker.php', 'pages/bazaar.php') as $f) {
	$out = array();
	exec('php -l ' . escapeshellarg(__DIR__ . '/../overlay/plugins/chaos/' . $f) . ' 2>&1', $out, $rc);
	check($rc === 0, "php -l $f");
}
$page = file_get_contents(__DIR__ . '/../overlay/plugins/chaos/pages/bazaar.php');
check(strpos($page, 'hash_equals($csrf') !== false, 'the page checks its CSRF token');
check(!preg_match('/<\?= \$(?!bz->|cfg\[|d\b|d ===)[a-z]+\[\'(player_name|name|reason|status)\'\]/', $page), 'names and reasons printed through chaos_h');
$install = file_get_contents(__DIR__ . '/../overlay/plugins/chaos/install.sql');
foreach (array('chaos_bazaar_listings', 'chaos_bazaar_bids', 'chaos_bazaar_log') as $t) {
	check(strpos($install, "CREATE TABLE IF NOT EXISTS `$t`") !== false, "install.sql creates $t");
}

echo $failed === 0 ? "chaos_bazaar_test: $checks checks OK\n" : "chaos_bazaar_test: $failed of $checks checks FAILED\n";
exit($failed === 0 ? 0 : 1);
