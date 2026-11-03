<?php
// php website/tests/chaos_guide_page_test.php : the beginner guide (plugins/chaos/guide_lib.php, pages/guide.php,
// guide/guide_data.json written by server/tools/gen_guide_data.lua from the How it works cards): the data (every card
// placed once, the first steps in order, levels rising, both languages, no dash), the view, a card's HTML (level, menu
// path, tip, rows, escaping), the page in English and Portuguese, a missing data file, and the links (site menu, home
// page, sitemap, page description). The data itself is checked against the server files by gen_guide_data.lua --check.
// php-cli only.
require __DIR__ . '/chaos_pages_helper.php';
$plugin = CHAOS_TEST_REPO . '/website/overlay/plugins/chaos';
require $plugin . '/lib.php';
require $plugin . '/i18n_lib.php';
require $plugin . '/guide_lib.php';

$failed = 0;
$checks = 0;
function check(bool $ok, string $what): void {
	global $failed, $checks;
	$checks++;
	if (!$ok) { $failed++; echo "FAIL: $what\n"; }
}

// the data
$d = chaos_guide_data();
check(count($d['cards']) >= 40, 'the cards are there (' . count($d['cards']) . ')');
check(count($d['steps']) >= 5, 'first steps');
check($d['steps'][0]['card'] === 'goals', 'the first step is Next Goals');
$placed = array();
foreach ($d['steps'] as $s) { $placed[] = $s['card']; }
$last = 0;
foreach ($d['levels'] as $l) {
	check($l['level'] > $last, "levels rise ({$l['level']})");
	$last = $l['level'];
	foreach ($l['cards'] as $k) {
		$placed[] = $k;
		check((int)$d['cards'][$k]['level'] === (int)$l['level'], "$k is listed at its own level");
	}
}
foreach ($d['anytime'] as $k) { $placed[] = $k; check($d['cards'][$k]['level'] === null, "$k has no level"); }
check(count($placed) === count(array_unique($placed)), 'every card is placed once');
check(count($placed) === count($d['cards']), 'every card is placed');
foreach ($d['cards'] as $k => $c) {
	check(chaos_bi($c['title'], 'en') !== '' && chaos_bi($c['title'], 'pt-BR') !== '', "$k: title in both languages");
	foreach ($c['rows'] as $r) {
		check(isset($d['headings']['rows'][$r['id']]), "$k: a heading for the row {$r['id']}");
		check(($r['text']['en'] ?? '') !== '' && ($r['text']['pt-BR'] ?? '') !== '', "$k.{$r['id']} in both languages");
	}
}
foreach ($d['steps'] as $s) { check(($s['tip']['en'] ?? '') !== '' && ($s['tip']['pt-BR'] ?? '') !== '', "the tip of {$s['card']} in both languages"); }
check($d['cards']['rift']['level'] === 100 && $d['cards']['rift']['menu'] === 'Adventure > Rifts', 'rifts: level 100, Adventure > Rifts');
check(chaos_no_dashes((string)file_get_contents($plugin . '/guide/guide_data.json')), 'no em or en dash in the data');

// the view
$v = chaos_guide_view($d);
check(array_column($v, 'id') === array('steps', 'levels', 'anytime'), 'three sections in order');
check(count($v[0]['groups'][0]['cards']) === count($d['steps']), 'the steps section holds every step');
check($v[1]['groups'][0]['id'] === 'level-' . $d['levels'][0]['level'], 'level anchors');
$broken = $d;
$broken['steps'][] = array('card' => 'no-such-card', 'tip' => array('en' => 'x'));
check(count(chaos_guide_view($broken)[0]['groups'][0]['cards']) === count($d['steps']), 'an unknown card is left out');

// one card
$card = array('title' => array('en' => 'A <b>', 'pt-BR' => 'Um <b>'), 'level' => 20, 'menu' => 'Economy > Crafting Bench',
	'rows' => array(array('id' => 'what', 'text' => array('en' => 'Fire & "ice"', 'pt-BR' => 'Fogo'))));
$html = chaos_guide_card_html('x"y', $card, array('en' => 'Tip', 'pt-BR' => 'Dica'), $d['headings'], 'en');
check(strpos($html, 'A &lt;b&gt;') !== false && strpos($html, '<b>') === false, 'the title is escaped');
check(strpos($html, 'id="card-x&quot;y"') !== false, 'the anchor is escaped');
check(strpos($html, 'Level 20+') !== false && strpos($html, 'In game: Economy &gt; Crafting Bench') !== false, 'level and menu path');
check(strpos($html, '>Tip<') !== false, 'the tip');
check(strpos($html, '<dt>What it is</dt><dd>Fire &amp; &quot;ice&quot;</dd>') !== false, 'the row under its heading');
$pt = chaos_guide_card_html('x', $card, null, $d['headings'], 'pt-BR');
check(strpos($pt, 'Nível 20+') !== false && strpos($pt, 'No jogo: Economy') !== false && strpos($pt, '<dt>O que é</dt><dd>Fogo</dd>') !== false, 'the card in Portuguese');
check(strpos($pt, 'chaos-guide-card__tip') === false, 'no tip line without a tip');
check(chaos_guide_data('/no/such/file.json')['cards'] === array(), 'a missing file gives no cards');

// the page
$en = chaos_render_page('guide', 'en');
$ptp = chaos_render_page('guide', 'pt-BR');
foreach (array('Start here', 'Beginner guide', 'First steps', 'As you level up', 'Any level', 'Opens at level 100', 'Next Goals',
	'In game: Adventure &gt; Next Goals', 'Help Search (Alt+F)', 'Infinity Tower', 'What drops', 'Read more') as $w) {
	check(strpos($en, $w) !== false, "page en says: $w");
}
foreach (array('Comece aqui', 'Guia do iniciante', 'Primeiros passos', 'Conforme você sobe de nível', 'Qualquer nível', 'Abre no nível 100',
	'Masmorras', 'O que cai', 'Se você morrer', 'Leia mais', 'Português') as $w) {
	if ($w === 'Português') { check(strpos($en, $w) !== false, 'the en page links to Portuguese'); continue; }
	check(strpos($ptp, $w) !== false, "page pt-BR says: $w");
}
foreach (array($en, $ptp) as $html) {
	check(strpos($html, 'id="steps"') !== false && strpos($html, 'id="levels"') !== false && strpos($html, 'id="anytime"') !== false, 'section anchors');
	check(strpos($html, 'id="card-goals"') !== false && strpos($html, 'id="card-raid"') !== false, 'card anchors');
	check(strpos($html, 'Fatal') === false && strpos($html, 'Notice') === false && strpos($html, 'Warning') === false, 'no PHP error');
	check(strpos($html, '<script') === false && strpos($html, 'style="') === false, 'no inline script or style');
	check(chaos_no_dashes($html), 'no em or en dash on the page');
}
check(strpos($en, 't=guide%3Astart&amp;l=en') !== false, 'the wiki link keeps English');
check(strpos($ptp, 't=guide%3Astart"') !== false, 'the wiki link in Portuguese');
$stepsAt = strpos($en, 'id="steps"');
check($stepsAt !== false && $stepsAt < strpos($en, 'id="levels"') && strpos($en, 'id="levels"') < strpos($en, 'id="anytime"'), 'steps, then levels, then any level');

// links
$setup = (string)file_get_contents(CHAOS_TEST_REPO . '/website/setup/chaos_setup.php');
check(strpos($setup, "'Start Here', 'page?plugin=chaos&p=guide'") !== false, 'the site menu links the guide');
check(strpos((string)file_get_contents(CHAOS_TEST_REPO . '/website/overlay/layouts/chaos/views/index.php'), 'p=guide') !== false, 'the home page links the guide');
check(strpos((string)file_get_contents(CHAOS_TEST_REPO . '/website/setup/write_seo_files.php'), "'guide'") !== false, 'the sitemap lists the guide');
$seo = (string)file_get_contents($plugin . '/seo_lib.php');
check(strpos($seo, "'page_chaos_guide' =>") !== false && substr_count($seo, 'page_chaos_guide') >= 2, 'the page has a description and is bilingual');

echo $failed ? "chaos_guide_page_test: $failed of $checks checks failed\n" : "chaos_guide_page_test: $checks checks OK\n";
exit($failed ? 1 : 0);
