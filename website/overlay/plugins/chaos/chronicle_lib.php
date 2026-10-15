<?php
/**
 * The Ashen Chronicle on the website (read only). The game server writes the tables
 * (server/data/scripts/chaos/chronicle.lua, server/sql/chaos_chronicle.sql); this file only reads them:
 *   chaos_chronicle_state     one row per season with a Chronicle (arc, open chapter, chapters written, finished)
 *   chaos_chronicle_chapters  each chapter's title (en, pt), what it changed once written (en, pt), when
 *   chaos_chronicle_progress  each goal: label, progress, target
 *   chaos_chronicle_contrib   each character's points per chapter (the running season)
 *   chaos_chronicle_record    the top contributors per chapter, written at the season's end
 * Privacy: a name is shown unless the character turned off "Show my records and realm firsts" (the Memorial's choice,
 * chaos_memorial_optin.records = 0); such a row reads "A hero who keeps their name".
 * Used by page.php?plugin=chaos&p=chronicle. Every query is a prepared statement; every value printed goes through chaos_h().
 */

if (!function_exists('chaos_chronicle_state')) {

define('CHAOS_CHRONICLE_HIDDEN', 'A hero who keeps their name');

/** Percent of a goal, 0..100 with one decimal. */
function chaos_chronicle_pct(int $progress, int $target): float {
	if ($target <= 0) {
		return 0.0;
	}
	return min(100.0, floor($progress * 1000 / $target) / 10);
}

/** The SQL that hides a name (needs the contributor table as alias `c`). */
function chaos_chronicle_name_sql(): string {
	if (!chaos_table_exists('chaos_memorial_optin')) {
		return 'c.`name` AS `shown_name`';
	}
	return 'CASE WHEN o.`records` = 0 THEN \'\' ELSE c.`name` END AS `shown_name`';
}

function chaos_chronicle_optin_join(): string {
	return chaos_table_exists('chaos_memorial_optin') ? ' LEFT JOIN `chaos_memorial_optin` o ON o.`player_id` = c.`player_id`' : '';
}

/** The season names of season_config.lua (id => name). */
function chaos_chronicle_season_names(): array {
	$names = array();
	if (function_exists('chaos_seasons')) {
		foreach (chaos_seasons() as $id => $s) {
			$names[(int)$id] = (string)($s['name'] ?? ('Season ' . $id));
		}
	}
	return $names;
}

/**
 * Everything the page shows:
 * ['ok' => bool, 'current' => season or null, 'past' => [season]], a season being
 * ['season', 'name', 'arc', 'chapter', 'done', 'finished', 'chapters' => [[i, title, title_pt, state, done_at, world,
 *   world_pt, pct, goals => [[label, progress, target, pct]], top => [[name, points]]]]]
 * (top: the running season's leaders from chaos_chronicle_contrib, a finished one's record).
 */
function chaos_chronicle_state(int $topLimit = 5, int $pastLimit = 5): array {
	$out = array('ok' => false, 'current' => null, 'past' => array());
	foreach (array('chaos_chronicle_state', 'chaos_chronicle_chapters', 'chaos_chronicle_progress', 'chaos_chronicle_contrib',
		'chaos_chronicle_record') as $t) {
		if (!chaos_table_exists($t)) {
			return $out;
		}
	}
	$out['ok'] = true;
	$names = chaos_chronicle_season_names();
	$topLimit = max(1, min(20, $topLimit));
	$rows = chaos_rows('SELECT `season`, `arc`, `chapter`, `done`, `finished_at` FROM `chaos_chronicle_state` ORDER BY `season` DESC LIMIT '
		. (max(1, min(20, $pastLimit)) + 1) . ';');
	foreach ($rows as $r) {
		$season = (int)$r['season'];
		$finished = (int)$r['finished_at'] > 0;
		$s = array('season' => $season, 'name' => $names[$season] ?? ('Season ' . $season), 'arc' => (string)$r['arc'],
			'chapter' => (int)$r['chapter'], 'done' => (int)$r['done'], 'finished' => $finished, 'chapters' => array());
		$goals = array();
		foreach (chaos_rows('SELECT `chapter`, `goal`, `label`, `progress`, `target` FROM `chaos_chronicle_progress` WHERE `season` = ? '
			. 'ORDER BY `chapter` ASC, `goal` ASC;', array($season)) as $g) {
			$goals[(int)$g['chapter']][] = array('label' => (string)$g['label'], 'progress' => (int)$g['progress'],
				'target' => (int)$g['target'], 'pct' => chaos_chronicle_pct((int)$g['progress'], (int)$g['target']));
		}
		$tops = array();
		if ($finished) {
			$sql = 'SELECT c.`chapter`, c.`points`, ' . chaos_chronicle_name_sql() . ' FROM `chaos_chronicle_record` c'
				. chaos_chronicle_optin_join() . ' WHERE c.`season` = ? AND c.`place` <= ' . $topLimit . ' ORDER BY c.`chapter` ASC, c.`place` ASC;';
		} else {
			$sql = 'SELECT c.`chapter`, c.`points`, ' . chaos_chronicle_name_sql() . ' FROM `chaos_chronicle_contrib` c'
				. chaos_chronicle_optin_join() . ' WHERE c.`season` = ? AND c.`points` > 0 ORDER BY c.`chapter` ASC, c.`points` DESC, '
				. 'c.`updated_at` ASC, c.`player_id` ASC;';
		}
		foreach (chaos_rows($sql, array($season)) as $t) {
			$ch = (int)$t['chapter'];
			if (count($tops[$ch] ?? array()) >= $topLimit) {
				continue;
			}
			$name = (string)$t['shown_name'];
			$tops[$ch][] = array('name' => $name === '' ? CHAOS_CHRONICLE_HIDDEN : $name, 'hidden' => $name === '',
				'points' => (int)$t['points']);
		}
		foreach (chaos_rows('SELECT `chapter`, `title`, `title_pt`, `world`, `world_pt`, `done_at` FROM `chaos_chronicle_chapters` '
			. 'WHERE `season` = ? ORDER BY `chapter` ASC;', array($season)) as $c) {
			$i = (int)$c['chapter'];
			$doneAt = (int)$c['done_at'];
			$state = $doneAt > 0 ? 'done' : ($i === $s['chapter'] && !$finished ? 'open' : 'locked');
			$g = $goals[$i] ?? array();
			$pct = 0.0;
			foreach ($g as $one) {
				$pct += $one['pct'];
			}
			$s['chapters'][] = array('i' => $i, 'title' => (string)$c['title'], 'title_pt' => (string)$c['title_pt'], 'state' => $state,
				'done_at' => $doneAt, 'world' => (string)$c['world'], 'world_pt' => (string)$c['world_pt'],
				'pct' => $state === 'done' ? 100.0 : ($g ? floor($pct / count($g) * 10) / 10 : 0.0), 'goals' => $g, 'top' => $tops[$i] ?? array());
		}
		if (!$finished && $out['current'] === null) {
			$out['current'] = $s;
		} elseif ($finished) {
			$out['past'][] = $s;
		}
	}
	$out['past'] = array_slice($out['past'], 0, max(1, min(20, $pastLimit)));
	return $out;
}

/** One goal's bar. */
function chaos_chronicle_bar_html(array $g): string {
	$pct = (float)$g['pct'];
	return '<div class="chaos-community__bar" role="progressbar" aria-valuemin="0" aria-valuemax="100" aria-valuenow="' . chaos_h($pct) . '">'
		. '<span class="chaos-community__fill" style="width:' . chaos_h(number_format($pct, 1, '.', '')) . '%"></span>'
		. '<span class="chaos-community__text">' . chaos_h($g['label'] . ': ' . number_format((int)$g['progress']) . ' / '
		. number_format((int)$g['target'])) . '</span></div>';
}

/** The names of a chapter (a table), or a line when nobody is there. */
function chaos_chronicle_top_html(array $top, string $empty): string {
	if (!$top) {
		return '<p class="chaos-muted">' . chaos_h($empty) . '</p>';
	}
	$h = '<table class="chaos-table"><thead><tr><th>#</th><th>Contributor</th><th class="num">Points</th></tr></thead><tbody>';
	foreach ($top as $i => $r) {
		$who = $r['hidden'] ? '<span class="chaos-muted">' . chaos_h($r['name']) . '</span>'
			: '<a href="characterprofile.php?name=' . rawurlencode($r['name']) . '">' . chaos_h($r['name']) . '</a>';
		$h .= '<tr><td>' . ($i + 1) . '</td><td>' . $who . '</td><td class="num chaos-gold">' . chaos_h(number_format($r['points'])) . '</td></tr>';
	}
	return $h . '</tbody></table>';
}

/** A season's chapters: titles, state, goal bars (the running season), what changed and who carried each. */
function chaos_chronicle_season_html(array $s, bool $running): string {
	$h = '<div class="chaos-chronicle">';
	foreach ($s['chapters'] as $c) {
		$state = $c['state'] === 'done' ? 'Written' . ($c['done_at'] > 0 ? ' on ' . date('j M Y', $c['done_at']) : '')
			: ($c['state'] === 'open' ? 'Open: ' . rtrim(rtrim(number_format($c['pct'], 1, '.', ''), '0'), '.') . '% written' : 'Not yet told');
		$h .= '<div class="chaos-chronicle__chapter chaos-chronicle__chapter--' . chaos_h($c['state']) . '">';
		$h .= '<h3 class="chaos-subheading">' . chaos_h($c['title']) . ($c['title_pt'] !== '' && $c['title_pt'] !== $c['title']
			? ' <span class="chaos-muted" lang="pt-BR">' . chaos_h($c['title_pt']) . '</span>' : '') . '</h3>';
		$h .= '<p class="chaos-note">' . chaos_h($state) . '</p>';
		if ($running && $c['state'] !== 'done') {
			foreach ($c['goals'] as $g) {
				$h .= chaos_chronicle_bar_html($g);
			}
		}
		if ($c['state'] === 'done' && $c['world'] !== '') {
			$h .= '<p>' . chaos_h($c['world']) . '</p>';
			if ($c['world_pt'] !== '') {
				$h .= '<p class="chaos-muted" lang="pt-BR">' . chaos_h($c['world_pt']) . '</p>';
			}
		}
		if ($c['state'] !== 'locked') {
			$h .= chaos_chronicle_top_html($c['top'], $running ? 'Nobody yet.' : 'Nobody recorded.');
		}
		$h .= '</div>';
	}
	return $h . '</div>';
}

}
