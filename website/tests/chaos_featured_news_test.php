<?php
// php website/tests/chaos_featured_news_test.php : featured news (O688; plugins/chaos/news_lib.php, news/news_data.json written by
// website/tools/gen_changelog.py): the freshness window and its edges, the order and the cap of the banner, the gate of an entry
// that is not live yet (flag, flag since a day, date, unknown form), the NEW badge on the news page, the front page block and the
// menu item, the "Novo" tag on the guide card and the server info section, the banner on the front page in both languages with
// the clock and the flags set by the test, escaping, the texts in pt-BR and no dash. php-cli only.
require __DIR__ . '/chaos_pages_helper.php';
$root = CHAOS_TEST_REPO . '/website';
$plugin = $root . '/overlay/plugins/chaos';
require $plugin . '/lib.php';
require $plugin . '/i18n_lib.php';
require $plugin . '/media_lib.php';
require $plugin . '/news_lib.php';
require $plugin . '/guide_lib.php';

$failed = 0;
$checks = 0;
function check(bool $ok, string $what): void {
	global $failed, $checks;
	$checks++;
	if (!$ok) { $failed++; echo "FAIL: $what\n"; }
}

$entry = static function (string $id, string $date, array $over = array()): array {
	return array_merge(array('id' => $id, 'kind' => 'new', 'date' => $date, 'patch' => null,
		'title' => array('en' => 'Title ' . $id, 'pt-BR' => 'Titulo ' . $id), 'text' => array('en' => 'Text of ' . $id, 'pt-BR' => 'Texto de ' . $id),
		'points' => array('en' => array(), 'pt-BR' => array())), $over);
};
$feat = static function (string $id, string $date, int $rank = 50, array $feature = array()): array {
	global $entry;
	return $entry($id, $date, array('featured' => true, 'feature' => array_merge(array('rank' => $rank,
		'headline' => array('en' => 'Head ' . $id, 'pt-BR' => 'Titulo ' . $id), 'pitch' => array('en' => 'Pitch ' . $id, 'pt-BR' => 'Linha ' . $id)), $feature)));
};
$data = static function (array $entries, int $days = 30, int $max = 3): array {
	$weeks = array();
	foreach ($entries as $e) {
		$start = chaos_news_monday($e['date']);
		if (!$weeks || $weeks[count($weeks) - 1]['start'] !== $start) {
			$weeks[] = array('start' => $start, 'entries' => array());
		}
		$weeks[count($weeks) - 1]['entries'][] = $e;
	}
	return array('recent' => 8, 'latest' => $entries ? $entries[0]['date'] : '', 'featured_days' => $days, 'featured_max' => $max, 'weeks' => $weeks);
};
$ids = static function (array $list): array { return array_map(static function (array $e): string { return $e['id']; }, $list); };

// ---------------------------------------------------------------- freshness: younger than the window, never in the future
$TODAY = '2026-11-20';
$d = $data(array($feat('a', '2026-11-20'), $feat('b', '2026-10-22'), $feat('c', '2026-10-21'), $feat('d', '2026-11-21'), $entry('plain', '2026-11-20')));
check($ids(chaos_news_featured($d, $TODAY)) === array('a', 'b'), 'fresh: today and 29 days ago; not 30 days, not tomorrow, not a plain entry');
check(chaos_news_age('2026-10-21', $TODAY) === 30 && chaos_news_age('2026-11-21', $TODAY) === -1 && chaos_news_age($TODAY, $TODAY) === 0, 'age in days');
$d14 = $data(array($feat('a', '2026-11-20'), $feat('b', '2026-11-06'), $feat('c', '2026-11-07')), 14);
check($ids(chaos_news_featured($d14, $TODAY)) === array('a', 'c'), 'featured_days 14: 13 days is fresh, 14 is not');
check($ids(chaos_news_featured($d, '2027-01-20')) === array(), 'two months later nothing is fresh');
check(chaos_news_banner_html($d, 'en', '2027-01-20', array()) === '', 'nothing fresh: no banner');
check(chaos_news_banner_html($data(array()), 'en', $TODAY, array()) === '' && chaos_news_banner_html($data(array($entry('p', $TODAY))), 'en', $TODAY, array()) === '', 'no featured entry: no banner');
$notBool = $entry('x', $TODAY, array('featured' => 'yes'));
check(chaos_news_feature($notBool) === null && chaos_news_feature($entry('y', $TODAY)) === null, 'only featured: true counts');

// ---------------------------------------------------------------- order and cap
$many = $data(array($feat('d1', '2026-11-20', 30), $feat('d2', '2026-11-20', 10), $feat('d3', '2026-11-20', 10), $feat('old', '2026-11-18', 1), $feat('d4', '2026-11-20', 5)));
check($ids(chaos_news_featured($many, $TODAY)) === array('d4', 'd2', 'd3', 'd1', 'old'), 'newest day first, then the lower rank, then the file order');
$html = chaos_news_banner_html($many, 'en', $TODAY, array());
check(substr_count($html, 'chaos-novelty__card') === 3 && strpos($html, 'chaos-novelty__grid--3') !== false, 'at most featured_max cards (3)');
check(strpos($html, 'Head d4') < strpos($html, 'Head d2') && strpos($html, 'Head d2') < strpos($html, 'Head d3') && strpos($html, 'Head d1') === false, 'the banner follows that order and cuts after three');
$one = chaos_news_banner_html($data(array($feat('only', '2026-11-20')), 30, 1), 'en', $TODAY, array());
check(substr_count($one, 'chaos-novelty__card') === 1 && strpos($one, 'chaos-novelty__grid--1') !== false, 'one card');
check(count(chaos_news_fresh_ids($many, $TODAY)) === 5, 'every fresh featured entry gets the badge, not only the three of the banner');

// ---------------------------------------------------------------- the banner card: texts, links, pictures, escaping
$files = array('clip-pinnacle.jpg' => 1, 'shot-rift.jpg' => 1);
$card = $data(array($feat('p', '2026-11-20', 5, array('clip' => 'pinnacle', 'target' => 'guide:bosses')), $feat('r', '2026-11-20', 6, array('clip' => 'rift', 'target' => 'serverinfo:endgame')),
	$feat('n', '2026-11-20', 7, array('headline' => array('en' => 'A <b>"bold"</b> & more', 'pt-BR' => 'Em <i>negrito</i>')))));
$en = chaos_news_banner_html($card, 'en', $TODAY, $files);
$pt = chaos_news_banner_html($card, 'pt-BR', $TODAY, $files);
check(strpos($en, 'id="novidade"') !== false && strpos($en, 'New in the game') !== false && strpos($en, '>NEW<') !== false, 'en: heading and badge');
check(strpos($pt, 'Novidade no jogo') !== false && strpos($pt, '>NOVO<') !== false && strpos($pt, 'Linha p') !== false && strpos($pt, 'Leia mais') !== false, 'pt-BR: heading, badge, pitch, link');
check(strpos($en, 'plugins/chaos/assets/media/clip-pinnacle.jpg') !== false, 'a recorded clip poster is the picture');
check(strpos($en, 'plugins/chaos/assets/media/shot-rift.jpg') !== false, 'a clip not recorded shows the still of its slot');
check(substr_count($en, '<img ') === 2 && substr_count($en, 'loading="lazy"') === 2 && substr_count($en, 'alt=""') === 2, 'a card with no picture has no image; pictures lazy, decorative');
check(strpos($en, 'p=guide#card-bosses') !== false && strpos($en, 'serverinfo#endgame') !== false && strpos($en, 'In the guide') !== false && strpos($en, 'On the server info page') !== false, 'links to the guide card and the server info section');
check(strpos($pt, 'No guia') !== false && strpos($pt, 'Na página de informações do servidor') !== false, 'pt-BR link labels');
check(strpos($en, 'p=news#news-p') !== false, 'a link to the news entry');
check(strpos($en, '<b>') === false && strpos($en, '&lt;b&gt;&quot;bold&quot;&lt;/b&gt; &amp; more') !== false, 'texts are escaped');
check(strpos($en, 'http') === false && strpos($en, '//') === false, 'no external address');
$bad = $data(array($feat('bad', '2026-11-20', 5, array('clip' => '../x', 'target' => 'guide:"><script>'))));
$badHtml = chaos_news_banner_html($bad, 'en', $TODAY, array());
check(strpos($badHtml, '<script>') === false && strpos($badHtml, 'p=guide#card') === false && strpos($badHtml, '<img') === false, 'a bad clip or target is dropped');
$noText = $data(array($entry('nofeature', '2026-11-20', array('featured' => true))));
check(strpos(chaos_news_banner_html($noText, 'en', $TODAY, array()), 'Title nofeature') !== false && strpos(chaos_news_banner_html($noText, 'en', $TODAY, array()), 'Text of nofeature') !== false, 'a featured entry without a feature block shows its title and text');

// ---------------------------------------------------------------- the gate
$gated = static function (string $id, string $when, string $date = '2026-11-20') use ($feat): array {
	return array_merge($feat($id, $date, 5), array('live_when' => $when));
};
$g = $data(array($gated('s', 'flag:spell_upgrades'), $feat('open', '2026-11-19')));
check($ids(chaos_news_featured(chaos_news_live($g, $TODAY, array()), $TODAY)) === array('open'), 'a flag that is off hides the entry');
check($ids(chaos_news_featured(chaos_news_live($g, $TODAY, array('spell_upgrades' => false)), $TODAY)) === array('open'), 'a flag set to false hides it');
check($ids(chaos_news_featured(chaos_news_live($g, $TODAY, array('other' => true)), $TODAY)) === array('open'), 'another flag does not open it');
$on = chaos_news_live($g, $TODAY, array('spell_upgrades' => true));
check($ids(chaos_news_featured($on, $TODAY)) === array('s', 'open'), 'a flag that is on shows it, newest first');
check(chaos_news_live($g, $TODAY, array())['latest'] === '2026-11-19' && $on['latest'] === '2026-11-20', 'latest follows the live entries');
$since = chaos_news_live($g, '2026-12-03', array('spell_upgrades' => '2026-12-01'));
check($since['weeks'][0]['start'] === '2026-11-30' && $since['weeks'][0]['entries'][0]['id'] === 's' && $since['weeks'][0]['entries'][0]['date'] === '2026-12-01', 'a flag set to a day dates the entry from that day, in that week');
check($ids(chaos_news_featured($since, '2026-12-03')) === array('s', 'open'), 'fresh from the day it went on, newest first');
check(chaos_news_live($g, '2026-11-25', array('spell_upgrades' => '2026-12-01'))['weeks'][0]['entries'][0]['id'] === 'open', 'a flag set to a day in the future is not live yet');
$dg = $data(array($gated('dated', 'date:2026-12-01', '2026-12-01'), $feat('open', '2026-11-19')));
check($ids(chaos_news_featured(chaos_news_live($dg, '2026-11-30', array()), '2026-11-30')) === array('open') && $ids(chaos_news_featured(chaos_news_live($dg, '2026-12-01', array()), '2026-12-01')) === array('dated', 'open'), 'a date gate opens on its day');
foreach (array('flag:', 'flag:Bad', 'date:2026-12-1', 'soon', 'flag:a b', '') as $when) {
	$weird = $data(array($gated('w', $when)));
	check(chaos_news_live($weird, $TODAY, array('a b' => true, 'Bad' => true))['weeks'] === array(), "an unknown gate '$when' reads as off");
}
check(chaos_news_live($data(array($gated('w', 'flag:xy'))), $TODAY, array('xy' => true))['weeks'][0]['entries'][0]['id'] === 'w', 'a plain flag name works');
$regroup = chaos_news_live($data(array($entry('e1', '2026-11-20'), $entry('e2', '2026-11-19'), $entry('e3', '2026-11-12'))), $TODAY, array());
check(count($regroup['weeks']) === 2 && $ids($regroup['weeks'][0]['entries']) === array('e1', 'e2') && $regroup['weeks'][1]['start'] === '2026-11-09', 'the weeks are rebuilt in the same order');
check(chaos_news_monday('2026-11-22') === '2026-11-16' && chaos_news_monday('2026-11-16') === '2026-11-16' && chaos_news_monday('2026-11-23') === '2026-11-23', 'the Monday of a week');
check(chaos_news_flags(array('a' => true)) === array('a' => true) && is_array(chaos_news_flags()), 'flags: an override, and the real source gives an array');

// ---------------------------------------------------------------- flags from the config and the server file
$srv = sys_get_temp_dir() . '/chaos_feat_' . getmypid();
mkdir($srv . '/scripts/chaos', 0777, true);
file_put_contents($srv . '/scripts/chaos/live_flags.lua', "-- flags\nreturn {\n  spell_upgrades = true, -- on\n  combo_x = \"2026-12-05\",\n  off_one = false,\n}\n");
$GLOBALS['config'] = array('chaos' => array('server_data' => $srv, 'live' => array('from_config' => true, 'combo_x' => false, 'late' => '2026-12-09', 'Bad Name' => true)));
$flags = chaos_news_flags();
check(($flags['spell_upgrades'] ?? null) === true && ($flags['from_config'] ?? null) === true && ($flags['late'] ?? null) === '2026-12-09', 'flags come from the server file and the config');
check(!array_key_exists('combo_x', $flags) && !array_key_exists('off_one', $flags) && !array_key_exists('Bad Name', $flags), 'the config wins (false removes), false and bad names are not flags');
unlink($srv . '/scripts/chaos/live_flags.lua');
rmdir($srv . '/scripts/chaos');
rmdir($srv . '/scripts');
rmdir($srv);
$GLOBALS['config'] = array('chaos' => array());

// ---------------------------------------------------------------- the NEW badge
$newIds = array('e1' => true);
$weekHtml = chaos_news_week_html($regroup['weeks'][0], 'en', $newIds);
check(substr_count($weekHtml, 'chaos-newbadge') === 1 && strpos($weekHtml, 'chaos-newsitem--new') !== false, 'the news page: the badge on the entry in the set, not on the other');
check(strpos(chaos_news_week_html($regroup['weeks'][0], 'en'), 'chaos-newbadge') === false, 'no set: no badge');
check(strpos(chaos_news_entry_html($regroup['weeks'][0]['entries'][0], 'pt-BR', true, true), '>NOVO<') !== false, 'pt-BR badge');
$home = chaos_news_home_html($regroup, 'en', 3, $newIds);
check(substr_count($home, 'chaos-newbadge') === 1 && strpos($home, 'chaos-newshome__item') !== false, 'the front page block: the badge on the fresh entry');
check(strpos(chaos_news_home_html($regroup, 'en', 3), 'chaos-newbadge') === false, 'the block: no set, no badge');

// ---------------------------------------------------------------- the menu item
$nav = '<ul class="sh-nav-list"><li><a href="page?plugin=chaos&amp;p=news"><i class="fa fa-newspaper-o"></i> What is New</a></li>'
	. '<li><a href="/page.php?plugin=chaos&p=news&l=pt-BR">Novidades</a></li><li><a href="page?plugin=chaos&amp;p=patchnotes">Patch Notes</a></li></ul>'
	. '<a class="chaos-btn chaos-btn--ghost" href="page?plugin=chaos&amp;p=news">All the news</a>'
	. '<h3><a href="page?plugin=chaos&amp;p=news#news-x">Entry</a></h3><a href="page?plugin=chaos&amp;p=newsletter">other</a>';
$freshLive = $data(array($feat('a', '2026-11-20')));
$out = chaos_news_menu_badge($nav, 'en', $freshLive, $TODAY);
check(substr_count($out, '<span class="chaos-newbadge') === 2 && strpos($out, 'What is New <span class="chaos-newbadge chaos-newbadge--menu">NEW</span></a>') !== false, 'the menu items that lead to the news page get the badge');
check(strpos($out, 'All the news</a>') !== false && strpos($out, 'Entry</a>') !== false && strpos($out, 'other</a>') !== false && strpos($out, 'Patch Notes</a>') !== false, 'our buttons, the entry link and other pages stay as they were');
check(chaos_news_menu_badge($out, 'en', $freshLive, $TODAY) === $out, 'no second badge');
check(strpos(chaos_news_menu_badge($nav, 'pt-BR', $freshLive, $TODAY), '>NOVO<') !== false, 'pt-BR menu badge');
check(chaos_news_menu_badge($nav, 'en', $data(array($feat('a', '2026-09-01'))), $TODAY) === $nav, 'nothing fresh: the page is untouched');
check(chaos_news_menu_badge($nav, 'en', chaos_news_live($data(array($gated('g', 'flag:nope'))), $TODAY, array()), $TODAY) === $nav, 'a gated entry gives no badge');
check(chaos_news_menu_badge('<html>no link</html>', 'en', $freshLive, $TODAY) === '<html>no link</html>', 'a page with no link is untouched');

// ---------------------------------------------------------------- targets
$targets = chaos_news_fresh_targets($data(array($feat('a', '2026-11-20', 5, array('target' => 'guide:bosses')), $feat('b', '2026-09-01', 5, array('target' => 'guide:rift')), $feat('c', '2026-11-20', 5, array('target' => 'serverinfo:endgame')))), $TODAY);
check($targets === array('guide:bosses' => true, 'serverinfo:endgame' => true), 'the targets of the fresh entries only');
$cardHtml = chaos_guide_card_html('bosses', array('title' => array('en' => 'Bosses'), 'rows' => array()), null, array('rows' => array()), 'en', true);
check(strpos($cardHtml, 'chaos-guide-card--new') !== false && strpos($cardHtml, '>NEW<') !== false && strpos(chaos_guide_card_html('bosses', array('title' => array('en' => 'Bosses'), 'rows' => array()), null, array('rows' => array()), 'en'), 'chaos-newbadge') === false, 'a guide card: the tag only when asked');

// ---------------------------------------------------------------- the pages, with the clock and the flags set
function render(string $kind, string $lang, string $today, array $live = array()): string {
	$cfg = 'array("chaos" => array("server_data" => ' . var_export(CHAOS_TEST_REPO . '/server/data', true) . ', "live" => ' . var_export($live, true) . '))';
	$base = '$config = ' . $cfg . '; $GLOBALS["config"] = $config; $GLOBALS["chaos_news_today"] = ' . var_export($today, true) . ';';
	$p = CHAOS_TEST_REPO . '/website/overlay';
	if ($kind === 'home') {
		$code = $base . '$_GET = array("l" => ' . var_export($lang, true) . '); $news = array(); $view = ""; $page = 0; ob_start(); error_reporting(E_ALL & ~E_WARNING);'
			. 'require ' . var_export($p . '/plugins/chaos/lib.php', true) . ';'
			. 'function znote_plugin_asset(string $p, string $a): string { return "plugins/" . $p . "/assets/" . $a; }'
			. 'include ' . var_export($p . '/layouts/chaos/views/index.php', true) . '; echo ob_get_clean();';
	} elseif ($kind === 'serverinfo') {
		$code = $base . '$_GET = array("l" => ' . var_export($lang, true) . '); ob_start(); error_reporting(E_ALL & ~E_WARNING); require ' . var_export($p . '/plugins/chaos/lib.php', true) . ';'
			. 'include ' . var_export($p . '/layouts/chaos/views/serverinfo.php', true) . '; echo ob_get_clean();';
	} else {
		$code = $base . '$_GET = array("plugin" => "chaos", "p" => ' . var_export($kind, true) . ', "l" => ' . var_export($lang, true) . '); ob_start(); error_reporting(E_ALL & ~E_WARNING);'
			. 'require ' . var_export($p . '/plugins/chaos/lib.php', true) . '; include ' . var_export($p . '/plugins/chaos/pages/' . $kind . '.php', true) . '; echo ob_get_clean();';
	}
	$out = array();
	exec(escapeshellarg(PHP_BINARY) . ' -r ' . escapeshellarg($code) . ' 2>&1', $out);
	return implode("\n", $out);
}
$T = '2026-11-20';
$home = render('home', 'en', $T);
$homePt = render('home', 'pt-BR', $T);
check(strpos($home, 'id="novidade"') !== false && substr_count($home, 'chaos-novelty__card') === 3, 'the front page shows the banner with three cards today');
check(strpos($home, 'Loot bursts out of every kill') < strpos($home, 'Four Ascended pinnacle bosses') && strpos($home, 'Four Ascended pinnacle bosses') < strpos($home, 'The Greater Rift has no end') && strpos($home, 'Waystone tiers XVI to XXV') === false, 'shipped data: loot explosion, pinnacle bosses, Greater Rift (the ranks), the fourth waits');
check(strpos($home, 'chaos-hero') < strpos($home, 'id="novidade"') && strpos($home, 'id="novidade"') < strpos($home, 'id="trailer"') && strpos($home, 'id="novidade"') < strpos($home, 'id="novidades"'), 'order: hero, banner, trailer, the news block');
check(strpos($homePt, 'Novidade no jogo') !== false && strpos($homePt, 'O loot explode de cada abate') !== false && strpos($homePt, '>NOVO<') !== false, 'pt-BR front page');
check(strpos($home, 'Spells now have ranks') === false && strpos($home, 'Spell combos') === false && strpos($home, 'Combos de magia') === false, 'the spell entries are not shown while the system is off');
check(strpos($home, 'Warning') === false && strpos($home, 'Fatal') === false && strpos($home, 'Notice') === false, 'no PHP message on the front page');
check(strpos(render('home', 'en', '2026-12-25'), 'id="novidade"') === false, 'a month on the banner is gone');
$on = render('home', 'en', $T, array('spell_upgrades' => true));
check(strpos($on, 'Spell ranks: your spells grow') !== false && strpos($on, 'Spell combos: ice then fire, and more') !== false && strpos($on, 'Spell ranks: your spells grow') < strpos($on, 'Spell combos: ice then fire, and more') && strpos($on, 'Spell combos: ice then fire, and more') < strpos($on, 'Loot bursts out of every kill'), 'the flag on: the spell entries lead the banner');
check(strpos($on, 'Four Ascended pinnacle bosses') === false && substr_count($on, 'chaos-novelty__card') === 3, 'still three cards');
check(strpos($on, 'Spells now have ranks') !== false, 'and the news block of the front page lists the entry');

$news = render('news', 'en', $T);
check(strpos($news, 'chaos-newsitem--new') !== false && substr_count($news, 'chaos-newbadge') === 4 && strpos($news, 'Spells now have ranks') === false, 'the news page: the badge on the four fresh featured entries, the gated ones left out');
$newsOn = render('news', 'pt-BR', $T, array('spell_upgrades' => true));
check(strpos($newsOn, 'As magias agora têm ranks') !== false && strpos($newsOn, 'Magias despertas') !== false && strpos($newsOn, 'Combos de magia') !== false && strpos($newsOn, 'As magias agora têm ranks') < strpos($newsOn, 'Explosão de loot'), 'the flag on: the four spell entries are on the page, newest first');
check(substr_count($newsOn, 'chaos-newbadge') === 6, 'the badge on the two featured spell entries as well');
check(strpos(render('news', 'en', '2026-12-25'), 'chaos-newbadge') === false, 'a month on no badge');

$guide = render('guide', 'en', $T);
check(strpos($guide, 'id="card-bosses"') !== false && preg_match('/id="card-bosses">\s*<h3[^>]*>[^<]*<span class="chaos-newbadge chaos-newbadge--tag">NEW<\/span>/', $guide) === 1 && substr_count($guide, '<span class="chaos-newbadge') === 3, 'the guide: a NEW tag on the cards the fresh entries point at (autoloot, bosses, rift)');
check(strpos(render('guide', 'pt-BR', $T), '>NOVO<') !== false && strpos(render('guide', 'en', '2026-12-25'), 'chaos-newbadge') === false, 'the guide: NOVO in Portuguese, no tag a month on');
check(preg_match('/id="card-spellbook">\s*<h3[^>]*>[^<]*<span class="chaos-newbadge/', render('guide', 'en', $T, array('spell_upgrades' => true))) === 1, 'the spellbook card is tagged once the spell entries are live');
check(preg_match('/id="card-spellbook">\s*<h3[^>]*>[^<]*<span class="chaos-newbadge/', $guide) === 0, 'and not before');
$info = render('serverinfo', 'en', $T);
check(preg_match('/id="endgame">\s*<h2[^>]*>Endgame <span class="chaos-newbadge chaos-newbadge--tag">NEW<\/span>/', $info) === 1 && substr_count($info, '<span class="chaos-newbadge') === 1, 'the server info page: a tag on the Endgame section');
check(strpos(render('serverinfo', 'en', '2026-12-25'), 'chaos-newbadge') === false, 'the server info page: no tag a month on');

// ---------------------------------------------------------------- the shipped data
$shipped = chaos_news_data();
$all = array();
foreach ($shipped['weeks'] as $w) {
	foreach ($w['entries'] as $e) { $all[$e['id']] = $e; }
}
check($shipped['featured_days'] === 30 && $shipped['featured_max'] === 3, 'the shipped window is 30 days and 3 cards');
foreach (array('loot-explosion', 'pinnacle', 'greater-rift', 'waystone-endgame') as $id) {
	check(isset($all[$id]) && chaos_news_feature($all[$id]) !== null && !isset($all[$id]['live_when']), "$id is featured and live");
}
foreach (array('spell-ranks', 'spell-forms', 'spell-awakening', 'spell-combos') as $id) {
	check(isset($all[$id]) && ($all[$id]['live_when'] ?? '') === 'flag:spell_upgrades', "$id is gated by flag:spell_upgrades");
	check(chaos_news_pick($all[$id]['title'], 'en') !== '' && chaos_news_pick($all[$id]['title'], 'pt-BR') !== chaos_news_pick($all[$id]['title'], 'en'), "$id has both languages");
}
check(strpos(chaos_news_pick($all['spell-combos']['text'], 'en'), 'Steam Burst') !== false && strpos(chaos_news_pick($all['spell-combos']['text'], 'en'), '10% to 20%') !== false, 'the combo entry names Steam Burst and the 10% to 20%');
check(strpos(chaos_news_pick($all['spell-ranks']['text'], 'en'), '0 to 20') !== false && strpos(chaos_news_pick($all['spell-ranks']['text'], 'en'), '25%') !== false, 'the rank entry: ranks 0 to 20, about 25%');

// ---------------------------------------------------------------- CHAOS_LIVE_FLAGS in the written config
function run_config(string $live): array {
	$env = array('CHAOS_DB_USER' => 'u', 'CHAOS_DB_NAME' => 'n', 'CHAOS_DB_HOST' => '127.0.0.1', 'CHAOS_DB_PORT' => '1', 'CHAOS_START_TOWNS' => '1',
		'CHAOS_SITE_URL' => 'https://www.example.org', 'CHAOS_LIVE_FLAGS' => $live);
	$cmd = 'env -i PATH=' . escapeshellarg((string)getenv('PATH'));
	foreach ($env as $k => $v) {
		$cmd .= ' ' . $k . '=' . escapeshellarg($v);
	}
	$out = array();
	exec($cmd . ' ' . escapeshellarg(PHP_BINARY) . ' ' . escapeshellarg(CHAOS_TEST_REPO . '/website/setup/write_config.php') . ' 2>/dev/null', $out);
	$config = array();
	eval('?>' . implode("\n", $out));
	return $config['chaos']['live'] ?? array('missing');
}
check(run_config('') === array(), 'CHAOS_LIVE_FLAGS empty: no flag on');
check(run_config('spell_upgrades, other=2026-12-05') === array('spell_upgrades' => true, 'other' => '2026-12-05'), 'CHAOS_LIVE_FLAGS: a name is on, name=day is on since that day');
check(run_config('Bad Name,x,a=2026-1-1,ok_one') === array('ok_one' => true), 'CHAOS_LIVE_FLAGS: bad names and days are dropped');
check(strpos((string)file_get_contents($root . '/site.env.example'), 'CHAOS_LIVE_FLAGS=') !== false, 'site.env.example lists it');

// ---------------------------------------------------------------- wiring and texts
$index = (string)file_get_contents($root . '/overlay/layouts/chaos/views/index.php');
check(strpos($index, 'chaos_news_banner_html') !== false && strpos($index, '<?= $novelty ?>') !== false, 'the front page calls the banner');
check(strpos((string)file_get_contents($plugin . '/seo_lib.php'), 'chaos_news_menu_badge') !== false, 'the output callback badges the menu');
$css = (string)file_get_contents($root . '/overlay/layouts/chaos/assets/css/chaos.css');
foreach (array('.chaos-newbadge', '.chaos-novelty', '.chaos-novelty__grid', '.chaos-newsitem--new', '.chaos-guide-card--new') as $sel) {
	check(strpos($css, $sel) !== false, "css rule $sel");
}
check(preg_match('/@media \(max-width: 900px\) \{ \.chaos-novelty__grid/', $css) === 1, 'the banner is one column on a phone');
check(preg_match('/prefers-reduced-motion: reduce\) \{\s*\.chaos-newbadge \{ animation: none/', $css) === 1 && preg_match('/prefers-reduced-motion: no-preference\) \{\s*\.chaos-newbadge \{ animation/', $css) === 1, 'the pulse only without reduced motion');
$new = substr($css, strpos($css, 'featured news (O688'));
check(strpos($new, 'http') === false && strpos($new, '@import') === false, 'the new css loads nothing external');
$table = require $plugin . '/i18n/pt-BR.php';
foreach (array('NEW', 'New in the game', 'In the guide', 'On the server info page', 'Read more') as $k) {
	check(isset($table[$k]) && $table[$k] !== '' && chaos_no_dashes($table[$k]), "pt-BR text for '$k'");
}
check(chaos_no_dashes((string)file_get_contents($plugin . '/news_lib.php')) && chaos_no_dashes((string)file_get_contents($plugin . '/news/news_data.json')), 'no em or en dash in the library and the data');

echo $failed ? "chaos_featured_news_test: $failed of $checks checks failed\n" : "chaos_featured_news_test: $checks checks OK\n";
exit($failed ? 1 : 0);
