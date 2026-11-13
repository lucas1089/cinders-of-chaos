<?php
// php website/tests/chaos_launcher_feed_test.php : the launcher feed (plugins/chaos/launcher_feed_lib.php,
// chaos_launcher_feed.php). News rows and the real patch notes of server/data/patchnotes in both languages, plain text
// (BBCode and HTML out), links, limits, the size limit, the cache file, no account data. Any PHP notice fails. php-cli.
$repo = realpath(__DIR__ . '/../..');
$config = array('chaos' => array('server_data' => $repo . '/server/data'), 'site_url' => 'https://www.example.org/');
$GLOBALS['config'] = $config;
$checks = 0;
$failures = array();
function check(bool $ok, string $what): void {
	global $checks, $failures;
	$checks++;
	if (!$ok) {
		$failures[] = "FAIL: $what";
	}
}
$notices = array();
set_error_handler(static function (int $no, string $msg, string $file, int $line) use (&$notices): bool {
	$notices[] = "$msg ($file:$line)";
	return true;
});
require __DIR__ . '/../overlay/plugins/chaos/lib.php';
require __DIR__ . '/../overlay/plugins/chaos/launcher_feed_lib.php';
$lim = chaos_launcher_feed_limits();

// ---------------------------------------------------------------- plain text
check(chaos_lf_plain('[b]Hello[/b] [url=https://x.test/a]world[/url] [img]a.png[/img]', 99) === 'Hello world a.png', 'bbcode out');
check(chaos_lf_plain('<script>alert(1)</script><b>Hi</b> &amp; &lt;i&gt; there', 99) === 'Hi & <i> there', 'html out, entities decoded to text');
check(chaos_lf_plain("a\x00b\x07c\r\n\t d\u{202E}e", 99) === 'a b c d e', 'control and bidi characters out: ' . chaos_lf_plain("a\x00b\x07c\r\n\t d\u{202E}e", 99));
check(chaos_lf_plain(str_repeat('ação ', 100), 20) === 'ação ação ação a...' || mb_strlen(chaos_lf_plain(str_repeat('ação ', 100), 20)) <= 20, 'cut by characters, never in half');
check(preg_match('//u', chaos_lf_plain(str_repeat('é', 500), 33)) === 1, 'cut text is valid UTF-8');
check(chaos_lf_url('https://www.example.org/?view=3') !== '' && chaos_lf_url('http://x.test/') === '' && chaos_lf_url('javascript:alert(1)') === ''
	&& chaos_lf_url("https://x.test/a b") === '' && chaos_lf_url('file:///etc/passwd') === '', 'only https links');

// ---------------------------------------------------------------- news
$rows = array(
	array('id' => 1, 'title' => 'Old', 'text' => 'old text', 'date' => 1000000000),
	array('id' => 3, 'title' => '[b]Season [i]two[/i][/b]', 'text' => "[quote]Join <b>now</b>[/quote]\nSecond line &amp; more", 'date' => 1790000000),
	array('id' => 2, 'title' => '', 'text' => 'no title', 'date' => 1780000000),
	array('id' => 4, 'title' => 'Maintenance', 'text' => str_repeat('long ', 200), 'date' => 1785000000, 'pid' => 7, 'name' => 'Secret GM'),
);
$news = chaos_lf_news($rows, 'https://www.example.org');
check(count($news) === 3, 'news: an item without a title is dropped');
check($news[0]['id'] === 3 && $news[1]['id'] === 4 && $news[2]['id'] === 1, 'news: newest first');
check($news[0]['title'] === 'Season two' && $news[0]['text'] === 'Join now Second line & more', 'news: plain text: ' . json_encode($news[0]));
check($news[0]['url'] === 'https://www.example.org/?view=3', 'news: link');
check(strlen($news[1]['text']) <= $lim['news_text'] + 2 && substr($news[1]['text'], -3) === '...', 'news: text cut');
check(!array_key_exists('pid', $news[1]) && !array_key_exists('name', $news[1]) && strpos(json_encode($news), 'Secret GM') === false, 'news: no author');
check(date('Y-m-d', 1790000000) === $news[0]['date'], 'news: date');
$many = array();
for ($i = 1; $i <= 30; $i++) {
	$many[] = array('id' => $i, 'title' => "N$i", 'text' => 't', 'date' => 1700000000 + $i);
}
check(count(chaos_lf_news($many, '')) === $lim['news'], 'news: limited');
check(chaos_lf_news($many, '')[0]['url'] === '', 'news: no site url, no link');

// ---------------------------------------------------------------- the real patch notes: all "Kind: news", so the launcher News
$notes = chaos_lf_notes($repo . '/server/data/patchnotes');
check(count($notes) >= 3 && count($notes) <= $lim['notes'], 'notes found (' . count($notes) . ')');
$ids = array_column($notes, 'id');
$sorted = $ids;
rsort($sorted);
check($ids === $sorted, 'notes: newest first');
$bad = array_filter($ids, static function ($i) { return stripos($i, 'pt-br') !== false; });
check(!$bad, 'notes: the pt-BR twins are not entries of their own');
check(!array_filter($notes, static function (array $n): bool { return ($n['en']['kind'] ?? '') !== 'news'; }), 'notes: every real note is marked Kind: news (owner 2026-11-02)');
$feed = chaos_launcher_feed_build($rows, $notes, 'https://www.example.org/', 1790000100);
check($feed['format'] === 1 && $feed['generated'] === 1790000100, 'feed: format and time');
foreach (array('en', 'pt-BR') as $lang) {
	check(isset($feed[$lang]['news'], $feed[$lang]['changelog']) && $feed[$lang]['changelog'] === array() && count($feed[$lang]['news']) === $lim['news'], "feed $lang: news notes go to News, the changelog is empty");
	$dates = array_column($feed[$lang]['news'], 'date');
	$ds = $dates;
	rsort($ds);
	check($dates === $ds, "feed $lang: news newest first, site rows and notes merged");
	foreach ($feed[$lang]['news'] as $e) {
		if (!is_string($e['id'])) {
			continue;   // a site news row
		}
		check($e['title'] !== '' && $e['text'] !== '' && preg_match('/^\d{4}-\d{2}-\d{2}$/', $e['date']) === 1 && !isset($e['lines']), "feed $lang: note {$e['id']} has title, date and text");
		check($e['text'] === chaos_lf_plain($e['text'], $lim['news_text']) && preg_match('/\*\*|__|`/', $e['text']) === 0, "feed $lang: note {$e['id']} text is plain");
		check(strpos($e['url'], 'https://www.example.org/page?plugin=chaos&p=patchnotes&id=') === 0, "feed $lang: note {$e['id']} link");
	}
}
$e0en = $feed['en']['news'][0];
$e0pt = $feed['pt-BR']['news'][0];
check(is_string($e0en['id']) && $e0en['id'] === $e0pt['id'] && $e0en['text'] !== $e0pt['text'], 'feed: the pt-BR block has the twin text');
check(is_file($repo . '/server/data/patchnotes/' . $e0en['id'] . '.pt-br.md'), 'feed: newest note has a twin to compare with');
// a note without a twin falls back to English
$dir = sys_get_temp_dir() . '/chaos_lf_test_' . getmypid();
@mkdir($dir);
file_put_contents($dir . '/2026-01-02.md', "# Only English\nDate: 2026-01-02\n\n## New\n\n- **Lead.** The line.\n  - a sub bullet\n- Second.\n");
file_put_contents($dir . '/2026-01-01.md', "# First\nDate: 2026-01-01\n\n## Fixes\n\n- Fixed it.\n");
file_put_contents($dir . '/2026-01-01.pt-br.md', "# Primeiro\nDate: 2026-01-01\n\n## Correções\n\n- Corrigido.\n");
file_put_contents($dir . '/README.md', "# not a note\n");
file_put_contents($dir . '/2026-01-03.md', "# Big news\nDate: 2026-01-03\nKind: news\n\nThe intro **line**.\nMore intro.\n\n## New\n\n- A bullet.\n");
file_put_contents($dir . '/_draft.md', "# draft\n");
$n2 = chaos_lf_notes($dir);
$f2 = chaos_launcher_feed_build(array(), $n2, '', 5);
check(count($n2) === 3 && count($f2['en']['changelog']) === 2 && $f2['en']['changelog'][0]['id'] === '2026-01-02', 'folder: README and drafts skipped, a plain note stays in the changelog, newest first');
check($f2['en']['news'] === array(array('id' => '2026-01-03', 'date' => '2026-01-03', 'title' => 'Big news', 'text' => 'The intro line. More intro.', 'url' => '')), 'folder: a Kind: news note goes to News with its intro: ' . json_encode($f2['en']['news']));
check($f2['pt-BR']['news'][0]['title'] === 'Big news', 'folder: a news note without a twin is English in pt-BR');
$f3 = chaos_launcher_feed_build(array(array('id' => 9, 'title' => 'Site', 'text' => 's', 'date' => strtotime('2026-01-04 12:00 UTC'))), $n2, '', 5);
check(array_column($f3['en']['news'], 'title') === array('Site', 'Big news'), 'folder: site news and news notes merged by date');
check($f2['pt-BR']['changelog'][0]['title'] === 'Only English' && $f2['pt-BR']['changelog'][0]['lines'] === array('Lead. The line.', 'Second.'), 'folder: no twin gives the English note, sub-bullets left out');
check($f2['pt-BR']['changelog'][1]['title'] === 'Primeiro' && $f2['pt-BR']['changelog'][1]['lines'] === array('Corrigido.'), 'folder: the twin is used');
check($f2['en']['changelog'][1]['title'] === 'First' && $f2['en']['changelog'][0]['url'] === '', 'folder: English block, no site url, no link');
check(chaos_lf_notes($dir . '/missing') === array() && chaos_lf_notes('') === array(), 'folder: missing gives an empty list');

// ---------------------------------------------------------------- JSON, size
$json = chaos_launcher_feed_json($feed);
$back = json_decode($json, true);
check(is_array($back) && $back['en']['news'][0]['id'] === $e0en['id'] && strlen($json) < $lim['bytes'], 'json: round trip, ' . strlen($json) . ' bytes');
$keys = array();
foreach (array('en', 'pt-BR') as $lang) {
	foreach (array('news', 'changelog') as $k) {
		foreach ($back[$lang][$k] as $item) {
			$keys = array_merge($keys, array_keys($item));
		}
	}
}
check(!array_diff($keys, array('id', 'date', 'title', 'text', 'lines', 'url')), 'json: only the public fields, no account data');
$huge = array('format' => 1, 'generated' => 1);
foreach (array('en', 'pt-BR') as $lang) {
	$huge[$lang] = array('news' => array(), 'changelog' => array());
	for ($i = 0; $i < 6; $i++) {
		$huge[$lang]['news'][] = array('id' => $i, 'title' => 't', 'text' => str_repeat('x', 6000), 'date' => 'd', 'url' => '');
		$huge[$lang]['changelog'][] = array('id' => "i$i", 'title' => 't', 'lines' => array(str_repeat('y', 6000)), 'date' => 'd', 'url' => '');
	}
}
$hj = chaos_launcher_feed_json($huge);
check(strlen($hj) <= $lim['bytes'] && json_decode($hj, true) !== null && count(json_decode($hj, true)['en']['news']) < 6, 'json: over the size limit, the oldest items go: ' . strlen($hj));

// ---------------------------------------------------------------- cache file
$cache = $dir . '/cache.json';
$calls = 0;
$build = static function () use (&$calls) { $calls++; return '{"n":' . $calls . '}'; };
check(chaos_launcher_feed_cached($build, $cache, 300, 1000) === '{"n":1}' && $calls === 1, 'cache: first call builds');
touch($cache, 1000);
check(chaos_launcher_feed_cached($build, $cache, 300, 1100) === '{"n":1}' && $calls === 1, 'cache: young copy is served');
check(chaos_launcher_feed_cached($build, $cache, 300, 1400) === '{"n":2}' && $calls === 2, 'cache: old copy is rebuilt');
file_put_contents($cache, str_repeat('z', $lim['bytes'] + 1));
touch($cache, 2000);
check(chaos_launcher_feed_cached($build, $cache, 300, 2001) === '{"n":3}', 'cache: an oversize file is not served');
check(chaos_launcher_feed_cached($build, '/nonexistent-folder/x.json', 300, 3000) === '{"n":4}', 'cache: an unwritable place still answers');
check(count(glob($dir . '/cache.json.*.tmp') ?: array()) === 0, 'cache: no temporary file left');

// ---------------------------------------------------------------- card fields of the carousel (O552): Tag, Build, Image
$note = chaos_pn_parse("# Patch\nDate: 2026-11-13\nTag: Event\nBuild: 47\nImage: raid.jpg\n\nIntro.\n\n## New\n\n- **Lead.** Text.\n", '2026-11-13');
check(($note['tag'] ?? '') === 'Event' && ($note['build'] ?? '') === '47' && ($note['image'] ?? '') === 'raid.jpg', 'the header lines Tag, Build and Image are read');
$cf = chaos_lf_card_fields($note, 'https://www.example.org');
check($cf === array('tag' => 'event', 'build' => '47', 'image' => 'https://www.example.org/plugins/chaos/assets/launcher/raid.jpg'), 'card fields: ' . json_encode($cf));
$e = chaos_lf_entry($note, '2026-11-13', 'https://www.example.org');
check(($e['tag'] ?? '') === 'event' && ($e['build'] ?? '') === '47' && isset($e['image']) && $e['lines'] !== array(), 'a changelog entry carries them');
check(chaos_lf_card_fields(array('tag' => 'weird', 'build' => '4x', 'image' => '../etc/passwd'), 'https://www.example.org') === array(), 'a bad tag, build or image path is left out');
check(chaos_lf_card_fields(array('image' => 'a.gif'), 'https://www.example.org') === array() && chaos_lf_card_fields(array('image' => 'a.png'), '') === array(), 'only jpg and png, and only with a site address');
check(chaos_lf_card_fields(array('image' => 'a..b.png'), 'https://www.example.org') === array(), 'no double dots in the file name');
$plain = chaos_lf_entry(chaos_pn_parse("# Plain\nDate: 2026-11-12\n\n## New\n\n- One.\n", 'p'), 'p', 'https://www.example.org');
check(!isset($plain['tag']) && !isset($plain['build']) && !isset($plain['image']), 'a note without the lines has none of the keys');

// ---------------------------------------------------------------- live builder: a failing database keeps the news notes
function db() {
	return new class {
		public function fetchAll(string $sql, array $p = array()) { throw new RuntimeException('database down'); }
	};
}
$log = ini_set('error_log', $dir . '/php.log');
$live = json_decode(chaos_launcher_feed_live(1790000200), true);
check(is_array($live) && count($live['en']['news']) >= 3 && !array_filter($live['en']['news'], static function (array $n): bool { return !is_string($n['id']); }), 'live: database down gives no site news, the news notes stay');
ini_set('error_log', (string)$log);

// ---------------------------------------------------------------- the entry point and the wiring
$entry = (string)file_get_contents($repo . '/website/overlay/chaos_launcher_feed.php');
check(strpos($entry, "'GET', 'HEAD'") !== false && strpos($entry, 'public, max-age=') !== false && strpos($entry, 'Set-Cookie') !== false, 'entry: GET/HEAD only, public cache, no cookie');
foreach (array('overlay/.htaccess', 'setup/router.php', 'overlay/plugins/chaos/lib.php', 'overlay/plugins/chaos/seo_lib.php', 'setup/write_seo_files.php', 'README.md') as $f) {
	check(strpos((string)file_get_contents($repo . '/website/' . $f), 'chaos_launcher_feed') !== false, "wiring: $f names the endpoint");
}
check(chaos_clean_url('chaos_launcher_feed.php') === 'chaos_launcher_feed.php', 'the endpoint address is not turned into a clean address');
$pnIds = array_map(static function (array $n): string { return (string)$n['id']; }, chaos_patchnotes());
check($pnIds !== array() && !preg_grep('~\.pt-br$~i', $pnIds), 'the Patch Notes page does not list a pt-BR twin as a note: ' . implode(', ', $pnIds));
check(!$notices, 'no PHP notice: ' . implode(' | ', $notices));
foreach (glob($dir . '/*') as $f) {
	@unlink($f);
}
@rmdir($dir);
if ($failures) {
	echo implode("\n", $failures) . "\n";
	exit(1);
}
echo "chaos_launcher_feed_test: $checks checks passed\n";
