<?php
// php website/tests/chaos_fairplay_page_test.php : the fair-play page (plugins/chaos/fairplay_lib.php,
// pages/fairplay.php, fairplay/fairplay_data.json): the data in both languages, every `verify` rule against
// docs/PRICES.md and the server configs, the weekly limits quoted against shop_config.lua, the page in English and
// Portuguese, and its links (Donate page, site menu, sitemap). php-cli only, no ZnoteX, no database.
require __DIR__ . '/chaos_pages_helper.php';
$plugin = CHAOS_TEST_REPO . '/website/overlay/plugins/chaos';
require $plugin . '/lib.php';
require $plugin . '/i18n_lib.php';
require $plugin . '/fairplay_lib.php';

$failed = 0;
$checks = 0;
function check(bool $ok, string $what): void {
	global $failed, $checks;
	$checks++;
	if (!$ok) { $failed++; echo "FAIL: $what\n"; }
}

$d = chaos_fairplay_data();
$ids = static function (array $list): array { return array_map(static function ($e) { return $e['id']; }, $list); };
foreach (array('gear', 'orbs', 'random', 'stats', 'classes', 'combat') as $want) {
	check(in_array($want, $ids($d['never']), true), "never list: $want");
}
foreach (array('cosmetics', 'convenience', 'timesavers', 'supplies', 'services', 'subscriptions') as $want) {
	check(in_array($want, $ids($d['sold']), true), "sold list: $want");
}
// the gray areas are listed, not hidden
foreach (array('pact', 'premium', 'doublexp', 'worldbuffs', 'exercise', 'crafting') as $want) {
	check(in_array($want, $ids($d['timesavers']), true), "time savers: $want");
}
$all = array();
foreach (array('never', 'sold', 'timesavers') as $list) {
	foreach ($d[$list] as $e) {
		foreach (array('title', 'text', 'what', 'limit') as $f) {
			if (!isset($e[$f])) { continue; }
			foreach (array('pt-BR', 'en') as $l) {
				check(is_string($e[$f][$l] ?? null) && $e[$f][$l] !== '', "{$e['id']}.$f has $l");
				check(chaos_no_dashes((string)($e[$f][$l] ?? '')), "{$e['id']}.$f $l has no em or en dash");
			}
			if ($f !== 'title') { check(($e[$f]['pt-BR'] ?? '') !== ($e[$f]['en'] ?? ''), "{$e['id']}.$f differs between languages"); }
		}
		check(!empty($e['verify']), "{$e['id']} has verify rules");
		check(chaos_verify_rules((array)($e['verify'] ?? array())) === array(), "{$e['id']} verify: " . implode('; ', chaos_verify_rules((array)($e['verify'] ?? array()))));
	}
}
check(chaos_bi($d['never'][0]['title'], 'en') === 'Gear' && chaos_bi($d['never'][0]['title'], 'pt-BR') === 'Equipamento', 'chaos_bi picks the language');
check(chaos_bi(array('en' => 'x'), 'pt-BR') === 'x', 'chaos_bi falls back');

// Double Experience: 4 singles + 2 packs of 5 = 14 hours a week, as the page says
$shop = (string)file_get_contents(CHAOS_TEST_REPO . '/server/data/scripts/chaos/shop_config.lua');
preg_match('/count = 1, cost = 50, weeklyLimit = (\d+)[^\n]*Double Experience Potion/', $shop, $a);
preg_match('/count = 5, cost = 225, weeklyLimit = (\d+)/', $shop, $b);
check(isset($a[1], $b[1]) && (int)$a[1] + 5 * (int)$b[1] === 14, 'Double Experience Potion: 4 + 2 x 5 = 14 hours a week');
$dx = '';
foreach ($d['timesavers'] as $e) { if ($e['id'] === 'doublexp') { $dx = $e['limit']['en'] . $e['limit']['pt-BR']; } }
check(strpos($dx, '14') !== false, 'the page quotes 14 hours');

// the page
foreach (array('en' => array('What the store never sells', 'Never sold', 'What time savers exist and their limits', 'Double Experience Potion'),
	'pt-BR' => array('O que a loja nunca vende', 'Nunca vendido', 'Quais aceleradores de tempo existem e seus limites', 'Poção de Experiência Dobrada')) as $lang => $wants) {
	$html = chaos_render_page('fairplay', $lang);
	foreach ($wants as $w) { check(strpos($html, $w) !== false, "page $lang says: $w"); }
	check(strpos($html, 'id="never-classes"') !== false && strpos($html, 'id="timesaver-pact"') !== false, "page $lang: anchors");
	check(strpos($html, 'Warning') === false && strpos($html, 'Fatal') === false && strpos($html, 'Notice') === false, "page $lang: no PHP error");
	check(strpos($html, "\u{2014}") === false, "page $lang: no em dash");
}

// links
check(strpos((string)file_get_contents($plugin . '/pages/coins.php'), 'p=fairplay') !== false, 'the Donate page links the pledge');
check(strpos((string)file_get_contents(CHAOS_TEST_REPO . '/website/setup/chaos_setup.php'), "p=fairplay'") !== false, 'the site menu links the pledge');
check(strpos((string)file_get_contents(CHAOS_TEST_REPO . '/website/setup/write_seo_files.php'), "'fairplay'") !== false, 'the sitemap lists the pledge');
check(strpos((string)file_get_contents($plugin . '/seo_lib.php'), 'page_chaos_fairplay') !== false, 'the page has a description');

echo $failed ? "chaos_fairplay_page_test: $failed of $checks checks failed\n" : "chaos_fairplay_page_test: $checks checks OK\n";
exit($failed ? 1 : 0);
