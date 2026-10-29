<?php
/**
 * The launcher feed (website/README.md "Launcher feed"): one small public JSON file for the game launcher (launcher/,
 * ROADMAP O314), which shows News and a Changelog next to the Play button. Entry point: chaos_launcher_feed.php
 * (site root, GET). Nothing new is written by hand: the news are ZnoteX's own (table znote_news, the front page's
 * news) and the changelog is the weekly patch notes (server/data/patchnotes/*.md and their pt-BR twins <id>.pt-br.md,
 * the same files as the Patch Notes page and the in-game window).
 *
 * Shape (format 1), one block per language, "en" and "pt-BR":
 *   {"format":1,"generated":<unix>,"en":{"news":[{id,date,title,text,url}],"changelog":[{id,date,title,lines,url}]},
 *    "pt-BR":{...}}
 * Plain text only (BBCode, HTML and control characters are removed here and again in the launcher). No account data:
 * a news item has no author. The news are written in one language by the staff, so both blocks hold the same news.
 * Limits: 6 news and 6 changelog entries, 8 lines each, short texts, the whole file at most 64 KiB.
 * Cache: a copy in the system temp folder for 5 minutes (one database query and a few files per 5 minutes however
 * many players start the launcher) and `Cache-Control: public, max-age=300`.
 */

if (!function_exists('chaos_launcher_feed_limits')) {

function chaos_launcher_feed_limits(): array {
	return array('news' => 6, 'changelog' => 6, 'lines' => 8, 'title' => 80, 'news_text' => 280, 'line' => 200,
		'bytes' => 65536, 'ttl' => 300);
}

/** Text safe to show as plain text: BBCode and HTML out, entities decoded, control characters out, cut to $n characters. */
function chaos_lf_plain($s, int $n): string {
	$s = (string)$s;
	$s = preg_replace('/\[(?:\/?[a-z*]+(?:=[^\]\[]*)?)\]/i', ' ', $s);      // [b] [/url] [url=...] [img] [*]
	$s = preg_replace('/<(?:script|style)\b.*?<\/(?:script|style)\s*>/is', ' ', $s);
	$s = preg_replace('/<[^>]*>/', ' ', $s);
	$s = html_entity_decode($s, ENT_QUOTES | ENT_HTML5, 'UTF-8');
	$s = preg_replace('/[\x00-\x1F\x7F]+|\p{Cf}+|\p{Zl}|\p{Zp}/u', ' ', $s) ?? '';
	$s = trim(preg_replace('/\s+/u', ' ', $s) ?? '');
	if (preg_match_all('/./su', $s) > $n) {
		preg_match('/^.{0,' . max(0, $n - 3) . '}/su', $s, $m);
		$s = rtrim($m[0] ?? '') . '...';
	}
	return $s;
}

/** An absolute https:// link without spaces or control characters, else ''. */
function chaos_lf_url(string $url): string {
	return (strlen($url) <= 300 && preg_match('~^https://[A-Za-z0-9.-]+(:\d+)?(/[^\s\x00-\x1F"<>\\\\]*)?$~', $url)) ? $url : '';
}

/** News rows (id, title, text, date) -> feed items, newest first. */
function chaos_lf_news(array $rows, string $site): array {
	$lim = chaos_launcher_feed_limits();
	usort($rows, static function (array $a, array $b): int {
		return ((int)($b['date'] ?? 0) <=> (int)($a['date'] ?? 0)) ?: ((int)($b['id'] ?? 0) <=> (int)($a['id'] ?? 0));
	});
	$out = array();
	foreach ($rows as $r) {
		$title = chaos_lf_plain($r['title'] ?? '', $lim['title']);
		$id = (int)($r['id'] ?? 0);
		if ($title === '' || $id <= 0) {
			continue;
		}
		$out[] = array(
			'id'    => $id,
			'date'  => date('Y-m-d', (int)($r['date'] ?? 0)),
			'title' => $title,
			'text'  => chaos_lf_plain($r['text'] ?? '', $lim['news_text']),
			'url'   => $site === '' ? '' : chaos_lf_url($site . '/?view=' . $id),
		);
		if (count($out) >= $lim['news']) {
			break;
		}
	}
	return $out;
}

/** The notes of the patch notes folder: list of ['id', 'date', 'en' => parsed, 'pt-BR' => parsed or null], newest first. */
function chaos_lf_notes(string $dir): array {
	if ($dir === '' || !is_dir($dir)) {
		return array();
	}
	$lim = chaos_launcher_feed_limits();
	$notes = array();
	foreach ((array)scandir($dir) as $name) {
		$name = (string)$name;
		$lower = strtolower($name);
		if (substr($lower, -3) !== '.md' || $lower === 'readme.md' || $name[0] === '_') {
			continue;
		}
		if (substr($lower, -9) === '.pt-br.md') {
			continue;   // a twin: read with its English file below
		}
		$id = substr($name, 0, -3);
		if (!chaos_pn_valid_id($id) || !is_file($dir . '/' . $name)) {
			continue;
		}
		$en = chaos_pn_parse((string)file_get_contents($dir . '/' . $name), $id);
		$twin = $dir . '/' . $id . '.pt-br.md';
		$pt = is_file($twin) ? chaos_pn_parse((string)file_get_contents($twin), $id) : null;
		$notes[] = array('id' => $id, 'date' => $en['date'] ?? '', 'en' => $en, 'pt-BR' => $pt);
	}
	usort($notes, static function (array $a, array $b): int {
		return strcmp(($b['date'] ?: '0000-00-00') . '|' . $b['id'], ($a['date'] ?: '0000-00-00') . '|' . $a['id']);
	});
	return array_slice($notes, 0, $lim['changelog']);
}

/** One parsed note -> a changelog entry: title, date and the first lines (bullets, "Lead. text"), in plain text. */
function chaos_lf_entry(array $note, string $id, string $site): array {
	$lim = chaos_launcher_feed_limits();
	$lines = array();
	foreach ($note['sections'] as $section) {
		foreach ($section['items'] as $it) {
			if ($it['level'] === 2) {
				continue;   // sub-bullets stay on the full page
			}
			$line = chaos_lf_plain(trim(($it['lead'] !== '' ? $it['lead'] . ' ' : '') . $it['text']), $lim['line']);
			if ($line !== '') {
				$lines[] = $line;
			}
			if (count($lines) >= $lim['lines']) {
				break 2;
			}
		}
	}
	return array(
		'id'    => $id,
		'date'  => (string)($note['date'] ?? ''),
		'title' => chaos_lf_plain($note['title'] ?? $id, $lim['title']),
		'lines' => $lines,
		'url'   => $site === '' ? '' : chaos_lf_url($site . '/page?plugin=chaos&p=patchnotes&id=' . rawurlencode($id)),
	);
}

/** The feed array. $newsRows: znote_news rows; $notes: chaos_lf_notes(). */
function chaos_launcher_feed_build(array $newsRows, array $notes, string $site, int $now): array {
	$site = rtrim($site, '/');
	$news = chaos_lf_news($newsRows, $site);
	$feed = array('format' => 1, 'generated' => $now);
	foreach (array('en', 'pt-BR') as $lang) {
		$log = array();
		foreach ($notes as $n) {
			$log[] = chaos_lf_entry($n[$lang] ?? $n['en'], (string)$n['id'], $site);   // no twin: the English note
		}
		$feed[$lang] = array('news' => $news, 'changelog' => $log);
	}
	return $feed;
}

/** JSON of the feed, within the size limit (the oldest items go first). */
function chaos_launcher_feed_json(array $feed): string {
	$max = chaos_launcher_feed_limits()['bytes'];
	$flags = JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE | JSON_INVALID_UTF8_SUBSTITUTE;
	for ($i = 0; $i < 40; $i++) {
		$json = (string)json_encode($feed, $flags);
		if (strlen($json) <= $max) {
			return $json;
		}
		foreach (array('en', 'pt-BR') as $lang) {
			foreach (array('news', 'changelog') as $k) {
				if (!empty($feed[$lang][$k])) {
					array_pop($feed[$lang][$k]);
				}
			}
		}
	}
	return (string)json_encode(array('format' => 1, 'generated' => (int)($feed['generated'] ?? 0)), $flags);
}

/** The JSON text from the cache file when it is younger than $ttl seconds, else $build() written to it (atomic). */
function chaos_launcher_feed_cached(callable $build, string $file, int $ttl, int $now): string {
	$age = is_file($file) ? $now - (int)@filemtime($file) : PHP_INT_MAX;
	if ($age >= 0 && $age < $ttl) {
		$text = @file_get_contents($file);
		if (is_string($text) && $text !== '' && strlen($text) <= chaos_launcher_feed_limits()['bytes']) {
			return $text;
		}
	}
	$json = (string)$build();
	$tmp = $file . '.' . getmypid() . '.tmp';
	if (is_dir(dirname($file)) && is_writable(dirname($file)) && @file_put_contents($tmp, $json) !== false) {
		@chmod($tmp, 0640);
		if (!@rename($tmp, $file)) {
			@unlink($tmp);
		}
	}
	return $json;
}

/** The whole feed from the live site (database and patch notes folder). A news query that fails gives an empty news list. */
function chaos_launcher_feed_live(int $now): string {
	$rows = array();
	try {
		$rows = (array)db()->fetchAll('SELECT `id`, `title`, `text`, `date` FROM `znote_news` ORDER BY `date` DESC, `id` DESC LIMIT 12;');
	} catch (Throwable $e) {
		error_log('[chaos launcher feed] news: ' . $e->getMessage());
	}
	$site = (string)($GLOBALS['config']['site_url'] ?? '');
	return chaos_launcher_feed_json(chaos_launcher_feed_build($rows, chaos_lf_notes(chaos_data_path('patchnotes')), trim($site), $now));
}

}
