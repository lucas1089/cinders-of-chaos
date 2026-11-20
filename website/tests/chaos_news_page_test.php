<?php
// php website/tests/chaos_news_page_test.php : the news page "Novidades" / "News" (O687; plugins/chaos/news_lib.php, pages/news.php,
// news/news_data.json written by website/tools/gen_changelog.py): the data file, the week labels in both languages, the split
// into recent weeks and the archive, an entry's HTML and its escaping, the front page block, the page in English and Portuguese,
// the menu, sitemap and description wiring, the texts in pt-BR and no dash. The data file against its sources is checked by
// gen_changelog.py --check. php-cli only.
require __DIR__ . '/chaos_pages_helper.php';
$root = CHAOS_TEST_REPO . '/website';
$plugin = $root . '/overlay/plugins/chaos';
require $plugin . '/lib.php';
require $plugin . '/i18n_lib.php';
require $plugin . '/news_lib.php';

$failed = 0;
$checks = 0;
function check(bool $ok, string $what): void {
	global $failed, $checks;
	$checks++;
	if (!$ok) { $failed++; echo "FAIL: $what\n"; }
}

// ---------------------------------------------------------------- the shipped data
$d = chaos_news_data();
check(count($d['weeks']) >= 5 && $d['recent'] === 8 && preg_match('/^\d{4}-\d{2}-\d{2}$/', $d['latest']) === 1, 'the shipped data: weeks, recent weeks, latest date');
$ids = array();
$prev = '9999-99-99';
foreach ($d['weeks'] as $week) {
	check($week['start'] < $prev, 'weeks newest first: ' . $week['start']);
	$prev = $week['start'];
	check((int)(new DateTimeImmutable($week['start']))->format('N') === 1, 'a week starts on a Monday: ' . $week['start']);
	foreach ($week['entries'] as $e) {
		$ids[] = $e['id'];
		check(chaos_news_pick($e['title'], 'en') !== '' && chaos_news_pick($e['title'], 'pt-BR') !== '' && chaos_news_pick($e['title'], 'pt-BR') !== chaos_news_pick($e['title'], 'en') || $e['kind'] === 'patch', 'both languages: ' . $e['id']);
		check($e['date'] >= $week['start'] && $e['date'] <= (new DateTimeImmutable($week['start']))->modify('+6 days')->format('Y-m-d'), 'an entry sits in its week: ' . $e['id']);
	}
}
check(count($ids) === count(array_unique($ids)) && count($ids) >= 20, 'distinct entries, at least twenty');
check($d['weeks'][0]['entries'][0]['date'] === $d['latest'], 'the first entry is the latest');
$newest = chaos_news_latest($d, 3);
check(count($newest) === 3 && $newest[0]['date'] >= $newest[2]['date'], 'the newest three');

// ---------------------------------------------------------------- bad or missing data
check(chaos_news_data('/nonexistent/x.json')['weeks'] === array(), 'no file: no weeks');
$tmp = sys_get_temp_dir() . '/chaos_news_test_' . getmypid() . '.json';
file_put_contents($tmp, '{"format":2,"weeks":[]}');
check(chaos_news_data($tmp)['weeks'] === array(), 'another format: no weeks');
file_put_contents($tmp, 'not json');
check(chaos_news_data($tmp)['weeks'] === array(), 'broken json: no weeks');
$entry = static function (string $id, string $kind, string $date, array $over = array()): array {
	return array_merge(array('id' => $id, 'kind' => $kind, 'date' => $date, 'patch' => null,
		'title' => array('en' => 'T <b>one</b> & "two"', 'pt-BR' => 'Título <i>um</i>'), 'text' => array('en' => 'Text <script>alert(1)</script>', 'pt-BR' => 'Texto'),
		'points' => array('en' => array('Point <x>'), 'pt-BR' => array('Ponto'))), $over);
};
$weeks = array();
foreach (array('2026-11-16', '2026-11-09', '2026-11-02', '2026-10-26') as $i => $start) {
	$weeks[] = array('start' => $start, 'entries' => array($entry('e' . $i, 'new', $start)));
}
$weeks[] = array('start' => 'bad', 'entries' => array($entry('bad1', 'new', '2026-01-01')));
$weeks[] = array('start' => '2026-10-19', 'entries' => array($entry('Bad Id', 'new', '2026-10-19'), $entry('nokind', 'oops', '2026-10-19')));
file_put_contents($tmp, json_encode(array('format' => 1, 'recent_weeks' => 2, 'latest' => '2026-11-16', 'weeks' => $weeks)));
$fake = chaos_news_data($tmp);
check(count($fake['weeks']) === 4 && $fake['recent'] === 2, 'a bad week, a bad id and a bad kind are dropped');
$split = chaos_news_split($fake);
check(count($split['recent']) === 2 && count($split['archive']) === 2 && $split['archive'][0]['start'] === '2026-11-02', 'the archive holds the weeks after the recent ones');

// ---------------------------------------------------------------- labels
check(chaos_news_week_label('2026-11-16', 'pt-BR') === '16 a 22 de novembro de 2026', 'pt-BR week label');
check(chaos_news_week_label('2026-11-16', 'en') === '16 to 22 November 2026', 'en week label');
check(chaos_news_week_label('2026-10-26', 'pt-BR') === '26 de outubro a 1 de novembro de 2026', 'pt-BR week over a month end');
check(chaos_news_week_label('2026-10-26', 'en') === '26 October to 1 November 2026', 'en week over a month end');
check(chaos_news_week_label('2026-12-28', 'en') === '28 December 2026 to 3 January 2027', 'en week over a year end');
check(chaos_news_date('2026-11-05', 'pt-BR') === '05/11/2026' && chaos_news_date('2026-11-05', 'en') === '5 Nov 2026', 'dates');
check(chaos_news_clip('Short.', 50) === 'Short.' && strlen(chaos_news_clip(str_repeat('word ', 80), 60)) <= 63 && substr(chaos_news_clip(str_repeat('word ', 80), 60), -3) === '...', 'clip');

// ---------------------------------------------------------------- html and escaping
$html = chaos_news_entry_html($fake['weeks'][0]['entries'][0], 'en');
check(strpos($html, '<script>') === false && strpos($html, '&lt;script&gt;') !== false && strpos($html, '<b>') === false && strpos($html, '&amp; &quot;two&quot;') !== false, 'every text is escaped');
check(strpos($html, 'id="news-e0"') !== false && strpos($html, 'datetime="2026-11-16"') !== false && strpos($html, '16 Nov 2026') !== false, 'id, date');
check(strpos(chaos_news_entry_html($fake['weeks'][0]['entries'][0], 'pt-BR'), 'Título &lt;i&gt;um') !== false, 'the Portuguese text');
$patchEntry = $entry('patch-2026-11-13', 'patch', '2026-11-13', array('patch' => '2026-11-13'));
check(strpos(chaos_news_entry_html($patchEntry, 'en'), 'p=patchnotes&amp;id=2026-11-13') !== false, 'a patch note entry links to its notes');
$evil = $entry('evil', 'patch', '2026-11-13', array('patch' => '"><script>'));
check(strpos(chaos_news_entry_html($evil, 'en'), 'patchnotes') === false, 'a bad patch id gives no link');
check(strpos(chaos_news_entry_html($entry('e', 'fix', '2026-11-13'), 'en', false), '<p class="chaos-newsitem__text">') === false, 'the compact form has no text');
check(strpos(chaos_news_week_html($fake['weeks'][0], 'pt-BR'), 'Semana de 16 a 22 de novembro de 2026') !== false, 'a week heading');
check(chaos_news_home_html(array('recent' => 8, 'latest' => '', 'weeks' => array()), 'en') === '', 'no data: no front page block');
$home = chaos_news_home_html($fake, 'pt-BR', 2);
check(substr_count($home, 'chaos-newshome__item') === 2 && strpos($home, 'Novidades') !== false && strpos($home, 'Todas as novidades') !== false && strpos($home, 'p=news#news-e0') !== false, 'the front page block: two items, a link to the page');

// ---------------------------------------------------------------- the pages
function render_news(string $lang, ?string $file): string {
	$code = '$config = array("chaos" => array()); $GLOBALS["config"] = $config; $_GET = array("plugin" => "chaos", "p" => "news", "l" => ' . var_export($lang, true) . ');'
		. ($file !== null ? '$GLOBALS["chaos_news_file"] = ' . var_export($file, true) . ';' : '')
		. 'ob_start(); error_reporting(E_ALL & ~E_WARNING); require ' . var_export(CHAOS_TEST_REPO . '/website/overlay/plugins/chaos/lib.php', true) . ';'
		. 'include ' . var_export(CHAOS_TEST_REPO . '/website/overlay/plugins/chaos/pages/news.php', true) . '; echo ob_get_clean();';
	$out = array();
	exec(escapeshellarg(PHP_BINARY) . ' -r ' . escapeshellarg($code) . ' 2>&1', $out);
	return implode("\n", $out);
}
$en = render_news('en', null);
$pt = render_news('pt-BR', null);
check(strpos($en, '<h1 class="chaos-heading">What is new</h1>') !== false && strpos($pt, '<h1 class="chaos-heading">Novidades</h1>') !== false, 'the heading in both languages');
$dLive = chaos_news_live($d, '2026-11-20', array()); // the gated entries (O688) are not on the page while their flags are off
check(substr_count($en, '<section class="chaos-newsweek"') === count($dLive['weeks']), 'every week is on the page');
check(substr_count($en, '<article ') === array_sum(array_map(static function (array $w): int { return count($w['entries']); }, $dLive['weeks'])), 'every live entry is on the page once');
check((strpos($en, 'chaos-newsarchive') !== false) === (count($dLive['weeks']) > $dLive['recent']), 'the archive only when there are more weeks than the recent ones');
check(strpos($pt, 'Semana de ') !== false && strpos($pt, 'Week of') === false && strpos($en, 'Week of ') !== false, 'week headings follow the language');
check(strpos($en, 'Warning') === false && strpos($en, 'Notice') === false && strpos($en, 'Fatal') === false && strpos($pt, 'Fatal') === false, 'no PHP message');
$small = render_news('en', $tmp);
check(strpos($small, 'id="chaos-news-archive"') !== false && strpos($small, '<summary>Archive') !== false && substr_count($small, '<article ') === 4, 'a small data file: two recent weeks and a two week archive');
check(strpos($small, '&lt;script&gt;') !== false && strpos($small, '<script>') === false, 'the page escapes the data');
check(strpos(render_news('en', '/nonexistent/x.json'), 'No news yet.') !== false, 'no data: the empty note');
unlink($tmp);

// ---------------------------------------------------------------- wiring and texts
$setup = (string)file_get_contents($root . '/setup/chaos_setup.php');
check(strpos($setup, "page?plugin=chaos&p=news") !== false, 'the menu entry in the setup');
$seo = (string)file_get_contents($plugin . '/seo_lib.php');
check(strpos($seo, "'page_chaos_news' => ") !== false && strpos($seo, "'page_chaos_news');") !== false, 'the description and the bilingual page list');
check(strpos((string)file_get_contents($root . '/setup/write_seo_files.php'), "'news' => '0.8'") !== false, 'the sitemap');
check(strpos((string)file_get_contents($plugin . '/plugin.php'), "news_lib.php") !== false, 'the plugin loads the news library');
$index = (string)file_get_contents($root . '/overlay/layouts/chaos/views/index.php');
check(strpos($index, 'chaos_news_home_html') !== false && strpos($index, '$newsHome') !== false, 'the front page shows the block');
$table = require $plugin . '/i18n/pt-BR.php';
foreach (array('What is new', 'All the news', 'Archive', 'Week of %s', 'New', 'Change', 'Balance', 'Fix', 'Patch Notes', 'Read the full notes', 'No news yet.',
	'What changed in the game, week by week, newest first. The full weekly notes are on the Patch Notes page and in the game (Social > Patch Notes).',
	'What is new in %s: the changes of the game week by week, newest first.') as $k) {
	check(isset($table[$k]) && $table[$k] !== '' && chaos_no_dashes($k) && chaos_no_dashes($table[$k]), "pt-BR text for '$k'");
}
$json = (string)file_get_contents($plugin . '/news/news_data.json');
check(chaos_no_dashes($json) && chaos_no_dashes((string)file_get_contents($plugin . '/news_lib.php')) && chaos_no_dashes((string)file_get_contents($plugin . '/pages/news.php')), 'no em or en dash in the data and the page');

echo $failed ? "chaos_news_page_test: $failed of $checks checks failed\n" : "chaos_news_page_test: $checks checks OK\n";
exit($failed ? 1 : 0);
