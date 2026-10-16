<?php
/**
 * The Capital Memorial on the website (read only), with the archive of past seasons. The game server writes the table
 * (server/data/scripts/chaos/memorial.lua, server/sql/chaos_memorial.sql); this file only reads it:
 *   chaos_memorial_entries  per season key ("s<id>", or the quarter "q<year><q>"): realm firsts (one row per member),
 *                           records (the season's best of each board) and Hardcore falls, each with `shown`
 * Privacy: only rows with shown = 1 give a name (the character's choice: records and firsts unless turned off, a fall
 * only after a yes; turning it off hides every season's rows at once). A first counts its hidden members without
 * naming them; a record whose holder keeps the name stays, without it; a hidden fall is not listed at all.
 * Used by page?plugin=chaos&p=memorial (&s=<season key> for the archive). Prepared statements; chaos_h() on output.
 */

if (!function_exists('chaos_memorial_seasons')) {

/** The season keys with something to show, newest first: [[key, name]]. */
function chaos_memorial_seasons(): array {
	if (!chaos_table_exists('chaos_memorial_entries')) {
		return array();
	}
	$out = array();
	foreach (chaos_rows('SELECT `season`, MAX(`season_name`) AS `name`, MAX(`at`) AS `last` FROM `chaos_memorial_entries` '
		. 'GROUP BY `season` ORDER BY `last` DESC LIMIT 40;') as $r) {
		$key = (string)$r['season'];
		if (!preg_match('/^[sq][0-9]{1,8}$/', $key)) {
			continue;
		}
		$out[] = array('key' => $key, 'name' => (string)$r['name'] !== '' ? (string)$r['name'] : $key);
	}
	return $out;
}

/**
 * One season: ['key', 'name', 'firsts' => [[title, names => [..], hidden, at]], 'records' => [[title, detail, name,
 * class, at]] (name '' when hidden), 'fallen' => [[name, level, class, cause, at]]]
 */
function chaos_memorial_season(string $key): array {
	$out = array('key' => $key, 'name' => $key, 'firsts' => array(), 'records' => array(), 'fallen' => array());
	if (!chaos_table_exists('chaos_memorial_entries') || !preg_match('/^[sq][0-9]{1,8}$/', $key)) {
		return $out;
	}
	$rows = chaos_rows('SELECT `kind`, `entry_key`, `name`, `title`, `detail`, `level`, `class`, `at`, `ord`, `shown`, `season_name` '
		. 'FROM `chaos_memorial_entries` WHERE `season` = ? ORDER BY `kind` ASC, `ord` ASC, `entry_key` ASC, `player_id` ASC;', array($key));
	$firsts = array();
	foreach ($rows as $r) {
		if ((string)$r['season_name'] !== '') {
			$out['name'] = (string)$r['season_name'];
		}
		$shown = (int)$r['shown'] === 1;
		$kind = (string)$r['kind'];
		if ($kind === 'first') {
			$k = (string)$r['entry_key'];
			if (!isset($firsts[$k])) {
				$firsts[$k] = array('title' => (string)$r['title'], 'names' => array(), 'hidden' => 0, 'at' => (int)$r['at'], 'ord' => (int)$r['ord']);
			}
			if ($shown) {
				$firsts[$k]['names'][] = (string)$r['name'];
			} else {
				$firsts[$k]['hidden']++;
			}
		} elseif ($kind === 'record') {
			$out['records'][] = array('title' => (string)$r['title'], 'detail' => (string)$r['detail'], 'name' => $shown ? (string)$r['name'] : '',
				'class' => $shown ? (string)$r['class'] : '', 'at' => (int)$r['at']);
		} elseif ($kind === 'fallen' && $shown) {
			$out['fallen'][] = array('name' => (string)$r['name'], 'level' => (int)$r['level'], 'class' => (string)$r['class'],
				'cause' => (string)$r['detail'], 'at' => (int)$r['at']);
		}
	}
	usort($firsts, static function ($a, $b) { return $a['ord'] <=> $b['ord']; });
	$out['firsts'] = array_values($firsts);
	return $out;
}

/** "Vexa, Mira and 2 others" (hidden members counted, never named). */
function chaos_memorial_names(array $names, int $hidden): string {
	$list = array_slice($names, 0, 4);
	$others = $hidden + max(0, count($names) - 4);
	if ($others > 0) {
		$list[] = $others === 1 ? '1 other' : $others . ' others';
	}
	if (!$list) {
		return 'heroes who keep their names';
	}
	if (count($list) === 1) {
		return $list[0];
	}
	$last = array_pop($list);
	return implode(', ', $list) . ' and ' . $last;
}

function chaos_memorial_season_html(array $s): string {
	$h = '<div class="chaos-memorial">';
	$h .= '<h3 class="chaos-subheading">Realm firsts</h3>';
	if (!$s['firsts']) {
		$h .= '<p class="chaos-muted">No realm first is remembered.</p>';
	} else {
		$h .= '<table class="chaos-table"><thead><tr><th>First</th><th>Slain by</th><th>Date</th></tr></thead><tbody>';
		foreach ($s['firsts'] as $f) {
			$h .= '<tr><td class="chaos-gold">' . chaos_h($f['title']) . '</td><td>' . chaos_h(chaos_memorial_names($f['names'], $f['hidden']))
				. '</td><td>' . chaos_h(date('j M Y', $f['at'])) . '</td></tr>';
		}
		$h .= '</tbody></table>';
	}
	$h .= '<h3 class="chaos-subheading">Records</h3>';
	if (!$s['records']) {
		$h .= '<p class="chaos-muted">No record is remembered.</p>';
	} else {
		$h .= '<table class="chaos-table"><thead><tr><th>Record</th><th class="num">Result</th><th>Held by</th><th>Date</th></tr></thead><tbody>';
		foreach ($s['records'] as $r) {
			$who = $r['name'] === '' ? '<span class="chaos-muted">a hero who keeps their name</span>'
				: chaos_h($r['name'] . ($r['class'] !== '' ? ', ' . $r['class'] : ''));
			$h .= '<tr><td>' . chaos_h($r['title']) . '</td><td class="num chaos-gold">' . chaos_h($r['detail']) . '</td><td>' . $who
				. '</td><td>' . chaos_h(date('j M Y', $r['at'])) . '</td></tr>';
		}
		$h .= '</tbody></table>';
	}
	$h .= '<h3 class="chaos-subheading">The fallen</h3>';
	if (!$s['fallen']) {
		$h .= '<p class="chaos-muted">Nobody is remembered here.</p>';
	} else {
		$h .= '<table class="chaos-table"><thead><tr><th>Name</th><th class="num">Level</th><th>Class</th><th>What killed them</th><th>Date</th></tr></thead><tbody>';
		foreach ($s['fallen'] as $f) {
			$h .= '<tr><td>' . chaos_h($f['name']) . '</td><td class="num">' . (int)$f['level'] . '</td><td>' . chaos_h($f['class'])
				. '</td><td>' . chaos_h($f['cause']) . '</td><td>' . chaos_h(date('j M Y', $f['at'])) . '</td></tr>';
		}
		$h .= '</tbody></table>';
	}
	return $h . '</div>';
}

}
