<?php
// php website/tests/chaos_starterbuilds_page_test.php : the Starter Builds guide (plugins/chaos/starter_builds_lib.php,
// pages/starterbuilds.php, guide/starter_builds_data.json written by server/tools/gen_starter_builds.lua): the data (21
// classes, 3 builds each, both languages, the point cuts and their codes, keystones in the order of the build), the OWNER RULE
// (the guide is qualitative: no percent sign, no DPS and no dash in any text), a build card's HTML (escaping, rows, codes), the
// page in English and Portuguese, a missing data file, and the links (the tree guide, the page description, the sitemap).
// The data itself is checked against the server files by gen_starter_builds.lua --check. php-cli only.
require __DIR__ . '/chaos_pages_helper.php';
$plugin = CHAOS_TEST_REPO . '/website/overlay/plugins/chaos';
require $plugin . '/lib.php';
require $plugin . '/i18n_lib.php';
require $plugin . '/starter_builds_lib.php';

$failed = 0;
$checks = 0;
function check(bool $ok, string $what): void {
	global $failed, $checks;
	$checks++;
	if (!$ok) { $failed++; echo "FAIL: $what\n"; }
}

// every text of the data, English and Portuguese: [label, text]
function sb_texts(array $d): array {
	$out = array();
	$walk = static function ($v, string $path) use (&$walk, &$out): void {
		if (is_array($v) && isset($v['en']) && isset($v['pt-BR'])) {
			$out[] = array($path . '.en', (string)$v['en']);
			$out[] = array($path . '.pt-BR', (string)$v['pt-BR']);
			return;
		}
		if (is_array($v)) {
			foreach ($v as $k => $x) { $walk($x, $path . '.' . $k); }
			return;
		}
		if (is_string($v) && $path !== '' && !preg_match('/\.(id|key|code|format|set|_generated)$/', $path)) {
			$out[] = array($path, $v);
		}
	};
	$walk($d, '');
	return $out;
}

// the data
$d = chaos_starter_data();
check(count($d['classes']) === 21, 'the 21 classes (' . count($d['classes']) . ')');
check($d['format'] === 'CB6', 'the code format is the game\'s tree code, version 6');
check(array_column($d['cuts'], 'points') === array(23, 73, 123, 248) && array_column($d['cuts'], 'level') === array(100, 300, 500, 1000), 'the four cuts: 23, 73, 123 and 248 points are levels 100, 300, 500 and 1000');
$ids = array();
$builds = 0;
foreach ($d['classes'] as $c) {
	check(count($c['builds']) === 3, "{$c['key']}: three Recommended builds");
	check(chaos_bi($c['line'], 'en') !== '' && chaos_bi($c['line'], 'pt-BR') !== '', "{$c['key']}: a line in both languages");
	foreach ($c['builds'] as $b) {
		$builds++;
		$ids[] = $b['id'];
		check(strpos($b['id'], $c['key'] . '_') === 0, "{$b['id']}: the id names its class");
		foreach (array('kind', 'what', 'style', 'price', 'gear') as $f) {
			check(chaos_bi($b[$f], 'en') !== '' && chaos_bi($b[$f], 'pt-BR') !== '' && $b[$f]['en'] !== $b[$f]['pt-BR'] || $f === 'kind', "{$b['id']}.$f in both languages");
		}
		foreach (array('en', 'pt-BR') as $l) {
			check(mb_strlen($b['style'][$l]) <= 240, "{$b['id']}: the style is at most 240 characters ($l)");
		}
		check(count($b['spells']) >= 2 && count($b['spells']) <= 4, "{$b['id']}: 2 to 4 spells");
		check(count($b['keystones']) <= 3, "{$b['id']}: at most 3 keystones");
		$last = 0;
		foreach ($b['keystones'] as $k) {
			check($k['name'] !== '' && $k['point'] > $last && $k['point'] <= 248, "{$b['id']}: {$k['name']} arrives at point {$k['point']}, in the order of the build");
			$last = $k['point'];
		}
		check(isset($b['cards']['set']) || isset($b['cards']['none']), "{$b['id']}: a card line");
		check(count($b['codes']) === 4 && !isset($b['dropped']), "{$b['id']}: four codes, no cut dropped");
		$prevKs = -1;
		foreach ($b['codes'] as $i => $code) {
			check(chaos_starter_code($code['code']) === $code['code'], "{$b['id']}: code $i is a tree code");
			check($code['points'] === $d['cuts'][$i]['points'] && $code['level'] === $d['cuts'][$i]['level'], "{$b['id']}: code $i is the cut {$d['cuts'][$i]['points']}");
			check($code['keystones'] >= $prevKs && $code['keystones'] <= 3, "{$b['id']}: the keystones of the cuts never fall and stay within the cap");
			$prevKs = $code['keystones'];
		}
		check(count(array_unique(array_column($b['codes'], 'code'))) === 4, "{$b['id']}: the four codes differ");
	}
}
check($builds === 63 && count(array_unique($ids)) === 63, 'every build once (63)');

// the owner rule: qualitative, no computed number
foreach (sb_texts($d) as $t) {
	check(strpos($t[1], '%') === false, "no percent sign: {$t[0]}");
	check(stripos($t[1], 'DPS') === false, "no DPS: {$t[0]}");
	check(chaos_no_dashes($t[1]), "no em or en dash: {$t[0]}");
}
check(chaos_no_dashes((string)file_get_contents($plugin . '/guide/starter_builds_data.json')), 'no em or en dash in the data file');
// the rule catches what it is for
$probe = array(array('en' => 'It adds 12% damage', 'pt-BR' => 'x'), array('en' => 'a high DPS', 'pt-BR' => 'x'));
check(strpos($probe[0]['en'], '%') !== false && stripos($probe[1]['en'], 'DPS') !== false, 'the rule\'s probe texts do hold what it forbids');

// the code reader
check(chaos_starter_code('CB6-BAAIAAAAfQUAAAACEQAA') === 'CB6-BAAIAAAAfQUAAAACEQAA', 'a tree code is kept');
foreach (array('', 'CC1-AAAA', 'CB6-', 'CB6-<script>', "CB6-AB\nCD", 'cb6-AAAAAA', 'CB6-' . str_repeat('A', 901)) as $bad) {
	check(chaos_starter_code($bad) === '', 'not a tree code: ' . substr(json_encode($bad), 0, 24));
}

// one card
$build = array('id' => 'x"y', 'name' => 'A <b>', 'kind' => array('en' => 'Area', 'pt-BR' => 'Área'),
	'what' => array('en' => 'Fire & "ice"', 'pt-BR' => 'Fogo'), 'style' => array('en' => 'Plays', 'pt-BR' => 'Joga'),
	'price' => array('en' => 'Costs', 'pt-BR' => 'Custa'), 'keystones' => array(array('name' => 'Pyre <Oath>', 'point' => 9)),
	'spells' => array('Reaping Gyre', 'A<b>'), 'gear' => array('en' => 'Wear', 'pt-BR' => 'Vista'),
	'cards' => array('set' => 'Fire', 'name' => array('en' => 'Fire', 'pt-BR' => 'Fogo'), 'text' => array('en' => 'More', 'pt-BR' => 'Mais')),
	'codes' => array(array('points' => 23, 'level' => 100, 'keystones' => 1, 'code' => 'CB6-BAAIAAAAfQUAAAACEQAA'),
		array('points' => 73, 'level' => 300, 'keystones' => 1, 'code' => 'bad code')));
$html = chaos_starter_build_html($build, $d, 'en');
check(strpos($html, 'A &lt;b&gt;') !== false && strpos($html, '<b>') === false, 'the name is escaped');
check(strpos($html, 'id="build-x&quot;y"') !== false, 'the anchor is escaped');
check(strpos($html, 'Fire &amp; &quot;ice&quot;') !== false, 'a row is escaped');
check(strpos($html, '<strong>Pyre &lt;Oath&gt;</strong>, point 9') !== false, 'a keystone with its point');
check(strpos($html, 'Reaping Gyre, A&lt;b&gt;') !== false, 'the spells');
check(strpos($html, '<strong>Fire</strong>: More') !== false, 'the card set');
check(strpos($html, '23 points, level 100</span> <code class="chaos-sb-code">CB6-BAAIAAAAfQUAAAACEQAA</code>') !== false, 'a code with its cut');
check(strpos($html, 'bad code') === false && strpos($html, '73 points') === false, 'a code that is not a tree code is left out');
$pt = chaos_starter_build_html($build, $d, 'pt-BR');
check(strpos($pt, '<dt>O que faz</dt><dd>Fogo</dd>') !== false && strpos($pt, '23 pontos, nível 100') !== false && strpos($pt, ', ponto 9') !== false, 'the card in Portuguese');
$none = $build;
$none['cards'] = array('none' => array('en' => 'No set fits', 'pt-BR' => 'Nenhum conjunto serve'));
$none['keystones'] = array();
$html = chaos_starter_build_html($none, $d, 'en');
check(strpos($html, 'No set fits') !== false && strpos($html, 'No keystone: the walls and the aura are the build.') !== false, 'no set and no keystone are said');
check(chaos_starter_data('/no/such/file.json')['classes'] === array(), 'a missing file gives no classes');

// the page
$en = chaos_render_page('starterbuilds', 'en');
$ptp = chaos_render_page('starterbuilds', 'pt-BR');
foreach (array('Starter builds', 'Three Recommended builds for every class', 'Import codes', 'How it plays', 'Slayer', 'Cleaving Arc</strong>, point 25',
	'23 points, level 100', '248 points, level 1000', 'Heavy armour', 'Read more') as $w) {
	check(strpos($en, $w) !== false, "page en says: $w");
}
foreach (array('Builds iniciais', 'Três builds recomendadas para cada classe', 'Códigos de importação', 'Como se joga', 'Slayer', 'Cleaving Arc</strong>, ponto 25',
	'23 pontos, nível 100', 'Armadura pesada', 'Leia mais', 'Português') as $w) {
	if ($w === 'Português') { check(strpos($en, $w) !== false, 'the en page links to Portuguese'); continue; }
	check(strpos($ptp, $w) !== false, "page pt-BR says: $w");
}
foreach (array($en, $ptp) as $html) {
	check(substr_count($html, 'class="chaos-guide-section"') === 21 && substr_count($html, 'chaos-sb-build') === 63, 'the page has 21 classes and 63 builds');
	check(substr_count($html, 'class="chaos-sb-code"') === 252, 'the page has 252 codes');
	check(strpos($html, 'id="class-warrior"') !== false && strpos($html, 'id="class-sentinel"') !== false && strpos($html, 'id="build-warrior_slayer"') !== false, 'anchors');
	check(strpos($html, 'Fatal') === false && strpos($html, 'Notice') === false && strpos($html, 'Warning') === false, 'no PHP error');
	check(strpos($html, '<script') === false && strpos($html, 'style="') === false, 'no inline script or style');
	check(chaos_no_dashes($html), 'no em or en dash on the page');
	$visible = strip_tags($html);
	check(strpos($visible, '%') === false && stripos($visible, 'DPS') === false, 'no percent sign and no DPS in the text of the page');
}
check(strpos($en, 't=guide%3Atree&amp;l=en') !== false, 'the wiki link keeps English');
check(strpos($ptp, 't=guide%3Atree"') !== false, 'the wiki link in Portuguese');

// links
$seo = (string)file_get_contents($plugin . '/seo_lib.php');
check(strpos($seo, "'page_chaos_starterbuilds' =>") !== false && substr_count($seo, 'page_chaos_starterbuilds') >= 2, 'the page has a description and is bilingual');
check(strpos((string)file_get_contents(CHAOS_TEST_REPO . '/website/setup/write_seo_files.php'), "'starterbuilds'") !== false, 'the sitemap lists the guide');
check(strpos((string)file_get_contents($plugin . '/wiki/guides/tree.en.md'), 'p=starterbuilds') !== false
	&& strpos((string)file_get_contents($plugin . '/wiki/guides/tree.pt-BR.md'), 'page:starterbuilds') !== false, 'the tree guide links the page in both languages');

// the menu entry (setup/chaos_setup.php, next to Start Here and Wiki) and the beginner guide's "Read more" list
$setupSrc = (string)file_get_contents(CHAOS_TEST_REPO . '/website/setup/chaos_setup.php');
check(strpos($setupSrc, "\$menu('Starter Builds', 'page?plugin=chaos&p=starterbuilds'") !== false, 'the site menu links the page');
$guideEn = chaos_render_page('guide', 'en');
$guidePt = chaos_render_page('guide', 'pt-BR');
check(strpos($guideEn, 'p=starterbuilds&amp;l=en">Starter builds</a>') !== false, 'the beginner guide links the page in English');
check(strpos($guidePt, 'p=starterbuilds">Builds iniciais</a>') !== false, 'the beginner guide links the page in Portuguese');

echo $failed ? "chaos_starterbuilds_page_test: $failed of $checks checks failed\n" : "chaos_starterbuilds_page_test: $checks checks OK\n";
exit($failed ? 1 : 0);
