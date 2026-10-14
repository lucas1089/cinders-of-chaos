<?php
// php website/tests/chaos_coins_test.php : the site reads the coin packs of server/data/scripts/chaos/shop_coins_config.lua
// the way the game server credits them (ChaosShopCore.packCredit; server/tests/shop_test.lua checks the same totals).
// php-cli only, no ZnoteX, no database. Exit status 0 when every check passes.
$GLOBALS['config'] = array('chaos' => array('server_data' => __DIR__ . '/../../server/data'));
require __DIR__ . '/../overlay/plugins/chaos/lib.php';

$failed = 0;
function check(bool $ok, string $what): void {
	global $failed;
	if (!$ok) {
		$failed++;
		echo "FAIL: $what\n";
	}
}

$packs = array();
foreach (chaos_coin_packs() as $p) {
	$packs[$p['key']] = $p;
}
$s = chaos_coin_settings();
check(count($packs) >= 5, 'five packs');
check($s['first_bonus_pct'] === 100 && $s['currency'] === 'USD', 'settings');
check($packs['coins750']['usd_cents'] === 1499 && $packs['starter']['usd_cents'] === 299, 'USD prices in integer cents');
check($packs['coins250']['total'] === 250, '250');
check($packs['coins750']['total'] === 825, '750 +10%');
check($packs['coins1500']['total'] === 1725, '1500 +15%');
check($packs['coins4000']['total'] === 5000, '4000 +25%');
check(chaos_coin_pack_total($packs['coins750'], true, $s['first_bonus_pct'], $s['first_bonus_max']) === 1575, 'first purchase bonus: double');
check($s['first_bonus_max'] === 1000, 'the first bonus cap read from the server config');
check(chaos_coin_pack_total($packs['coins1500'], true, $s['first_bonus_pct'], $s['first_bonus_max']) === 1725 + 1000, '1500 pack: +1000 flat, not +1500');
check(chaos_coin_pack_total($packs['coins10000'], true, $s['first_bonus_pct'], $s['first_bonus_max']) === 13000 + 1000, 'Vault: +1000 flat');
check(chaos_coin_first_bonus(1000, 100, 1000) === 1000 && chaos_coin_first_bonus(999, 100, 1000) === 999, 'up to 1000 the bonus doubles');
check(chaos_coin_first_text(100, 1000) === 'double Chaos Coins (+100%, up to 1000 extra)', 'page text');
check($packs['coins80']['total'] === 80 && $packs['coins10000']['total'] === 13000, 'entry pack and the Vault anchor (+30%)');
check($packs['starter']['once'] && $packs['starter']['starter'] && $packs['starter']['total'] === 500, 'starter pack');
check(chaos_coin_pack_total($packs['starter'], true, $s['first_bonus_pct']) === 500, 'no first bonus on the starter');
check(!$packs['coins250']['once'], 'packs are not once');
echo $failed === 0 ? "chaos_coins_test: OK\n" : "chaos_coins_test: $failed failed\n";
exit($failed === 0 ? 0 : 1);
