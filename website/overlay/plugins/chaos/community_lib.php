<?php
/**
 * Community goals and the weekly world modifier on the website (read only). The game server writes the tables
 * (server/data/scripts/chaos/community.lua, server/sql/chaos_community.sql); this file only reads them:
 *   chaos_community_goal     the goal of the current period per realm (name, target, progress, stage, finish)
 *   chaos_community_buffs    the stage buff windows open now
 *   chaos_community_week     the week's world modifiers (names and texts, seed or staff)
 *   chaos_community_contrib  the top contributors of the period
 *   chaos_community_history  the latest news lines (a stage reached, a period's end)
 * Used by the front page block (layouts/chaos/views/index.php) and page.php?plugin=chaos&p=community.
 * Every query is a prepared statement; every value printed goes through chaos_h().
 */

if (!function_exists('chaos_community_state')) {

/** The stage percents of community_config.lua (25 / 50 / 75 / 100), for the bar's marks. */
function chaos_community_stage_marks(): array {
	return array(25, 50, 75, 100);
}

/** Percent of a goal, 0..100 with one decimal. */
function chaos_community_pct(int $progress, int $target): float {
	if ($target <= 0) {
		return 0.0;
	}
	return min(100.0, floor($progress * 1000 / $target) / 10);
}

/** "1d 4h", "3h 12m", "8m" */
function chaos_community_left(int $seconds): string {
	$seconds = max(0, $seconds);
	$d = intdiv($seconds, 86400);
	$h = intdiv($seconds % 86400, 3600);
	$m = intdiv($seconds % 3600, 60);
	if ($d > 0) {
		return $d . 'd ' . $h . 'h';
	}
	if ($h > 0) {
		return $h . 'h ' . $m . 'm';
	}
	return max(1, $m) . 'm';
}

/** The realm's label: 0 is everybody (one goal), another number a season realm (goal.realms = "separate"). */
function chaos_community_realm_name(int $realm, int $realms): string {
	if ($realm === 0) {
		return $realms > 1 ? 'Standard realm' : '';
	}
	return 'Season realm ' . $realm;
}

/**
 * Everything the block and the page show, at time $now:
 * ['ok' => bool (tables there), 'goals' => [[realm, realm_name, name, target, progress, pct, stage, left, top => [[name, points]]]],
 *  'buffs' => [[realm, stage, name, text, left]], 'week' => ['mods' => [[key, name, text]], 'left', 'staff'] or null,
 *  'news' => [[text, at]]]
 */
function chaos_community_state(int $now, int $topLimit = 5): array {
	$out = array('ok' => false, 'goals' => array(), 'buffs' => array(), 'week' => null, 'news' => array());
	foreach (array('chaos_community_goal', 'chaos_community_buffs', 'chaos_community_week', 'chaos_community_contrib', 'chaos_community_history') as $t) {
		if (!chaos_table_exists($t)) {
			return $out;
		}
	}
	$out['ok'] = true;
	// the goals of the newest period that has not ended
	$goals = chaos_rows('SELECT `period`, `realm`, `name`, `target`, `progress`, `stage`, `finish` FROM `chaos_community_goal` '
		. 'WHERE `finish` > ? ORDER BY `period` DESC, `realm` ASC LIMIT 8;', array($now));
	$period = $goals ? (int)$goals[0]['period'] : 0;
	$realms = 0;
	foreach ($goals as $g) {
		if ((int)$g['period'] === $period) {
			$realms++;
		}
	}
	foreach ($goals as $g) {
		if ((int)$g['period'] !== $period) {
			continue;
		}
		$realm = (int)$g['realm'];
		$top = array();
		foreach (chaos_rows('SELECT `name`, `points` FROM `chaos_community_contrib` WHERE `period` = ? AND `realm` = ? AND `points` > 0 '
			. 'ORDER BY `points` DESC, `updated_at` ASC, `player_id` ASC LIMIT ' . max(1, min(20, $topLimit)) . ';', array($period, $realm)) as $r) {
			$top[] = array('name' => (string)$r['name'], 'points' => (int)$r['points']);
		}
		$out['goals'][] = array(
			'realm' => $realm,
			'realm_name' => chaos_community_realm_name($realm, $realms),
			'name' => (string)$g['name'],
			'target' => (int)$g['target'],
			'progress' => (int)$g['progress'],
			'pct' => chaos_community_pct((int)$g['progress'], (int)$g['target']),
			'stage' => (int)$g['stage'],
			'left' => max(0, (int)$g['finish'] - $now),
			'top' => $top,
		);
	}
	foreach (chaos_rows('SELECT `realm`, `stage`, `name`, `text`, `ends_at` FROM `chaos_community_buffs` WHERE `ends_at` > ? '
		. 'ORDER BY `realm` ASC, `stage` ASC;', array($now)) as $b) {
		$out['buffs'][] = array('realm' => (int)$b['realm'], 'stage' => (int)$b['stage'], 'name' => (string)$b['name'],
			'text' => (string)$b['text'], 'left' => max(0, (int)$b['ends_at'] - $now));
	}
	$week = chaos_rows('SELECT `week`, `mods`, `names`, `texts`, `source`, `finish` FROM `chaos_community_week` WHERE `finish` > ? '
		. 'ORDER BY `week` DESC LIMIT 1;', array($now));
	if ($week) {
		$w = $week[0];
		$keys = $w['mods'] === '' ? array() : explode(',', (string)$w['mods']);
		$names = explode('|', (string)$w['names']);
		$texts = explode('|', (string)($w['texts'] ?? ''));
		$mods = array();
		foreach ($keys as $i => $k) {
			if (!preg_match('/^[a-z_]+$/', $k)) {
				continue;
			}
			$mods[] = array('key' => $k, 'name' => (string)($names[$i] ?? $k), 'text' => (string)($texts[$i] ?? ''));
		}
		$out['week'] = array('week' => (int)$w['week'], 'mods' => $mods, 'left' => max(0, (int)$w['finish'] - $now),
			'staff' => $w['source'] === 'staff');
	}
	foreach (chaos_rows('SELECT `text`, `created_at` FROM `chaos_community_history` WHERE `kind` IN (\'stage\', \'end\') '
		. 'ORDER BY `created_at` DESC, `id` DESC LIMIT 5;') as $h) {
		$out['news'][] = array('text' => (string)$h['text'], 'at' => (int)$h['created_at']);
	}
	return $out;
}

/** The bar of one goal, with the stage marks. */
function chaos_community_bar_html(array $g): string {
	$marks = '';
	foreach (chaos_community_stage_marks() as $p) {
		if ($p < 100) {
			$marks .= '<span class="chaos-community__mark" style="left:' . (int)$p . '%"></span>';
		}
	}
	$pct = (float)$g['pct'];
	return '<div class="chaos-community__bar" role="progressbar" aria-valuemin="0" aria-valuemax="100" aria-valuenow="' . chaos_h($pct) . '">'
		. '<span class="chaos-community__fill" style="width:' . chaos_h(number_format($pct, 1, '.', '')) . '%"></span>' . $marks
		. '<span class="chaos-community__text">' . chaos_h(number_format((int)$g['progress']) . ' / ' . number_format((int)$g['target'])
		. '  (' . rtrim(rtrim(number_format($pct, 1, '.', ''), '0'), '.') . '%)') . '</span></div>';
}

/** The front page block (and the top of the page): the goal(s), the open stage buffs, the week's modifiers. */
function chaos_community_block_html(array $state, bool $full = false): string {
	if (empty($state['ok']) || (!$state['goals'] && !$state['week'])) {
		return '';
	}
	$h = '<div class="chaos-community">';
	foreach ($state['goals'] as $g) {
		$h .= '<div class="chaos-community__goal">';
		$h .= '<div class="chaos-community__head"><strong class="chaos-gold">' . chaos_h($g['name']) . '</strong>'
			. ($g['realm_name'] !== '' ? ' <span class="chaos-muted">' . chaos_h($g['realm_name']) . '</span>' : '')
			. '<span class="chaos-community__left">Ends in ' . chaos_h(chaos_community_left((int)$g['left'])) . '</span></div>';
		$h .= chaos_community_bar_html($g);
		$open = array();
		foreach ($state['buffs'] as $b) {
			if ($b['realm'] === $g['realm']) {
				$open[] = '<li><span class="chaos-gold">' . chaos_h($b['name']) . '</span>: ' . chaos_h($b['text'])
					. ' <span class="chaos-muted">(' . chaos_h(chaos_community_left((int)$b['left'])) . ' left)</span></li>';
			}
		}
		if ($open) {
			$h .= '<ul class="chaos-community__buffs">' . implode('', $open) . '</ul>';
		}
		if ($full && $g['top']) {
			$h .= '<table class="chaos-table chaos-community__top"><thead><tr><th>#</th><th>Contributor</th><th class="num">Points</th></tr></thead><tbody>';
			foreach ($g['top'] as $i => $r) {
				$h .= '<tr><td>' . ($i + 1) . '</td><td><a href="characterprofile.php?name=' . rawurlencode($r['name']) . '">'
					. chaos_h($r['name']) . '</a></td><td class="num chaos-gold">' . chaos_h(number_format($r['points'])) . '</td></tr>';
			}
			$h .= '</tbody></table>';
		}
		$h .= '</div>';
	}
	if ($state['week'] && $state['week']['mods']) {
		$h .= '<div class="chaos-community__week"><div class="chaos-community__head"><strong class="chaos-gold">This week\'s world</strong>'
			. ($state['week']['staff'] ? ' <span class="chaos-muted">set by the staff</span>' : '')
			. '<span class="chaos-community__left">' . chaos_h(chaos_community_left((int)$state['week']['left'])) . ' left</span></div><ul>';
		foreach ($state['week']['mods'] as $m) {
			$h .= '<li><strong>' . chaos_h($m['name']) . '</strong> ' . chaos_h($m['text']) . '</li>';
		}
		$h .= '</ul></div>';
	}
	if ($full && $state['news']) {
		$h .= '<div class="chaos-community__news"><h3 class="chaos-subheading">Latest</h3><ul>';
		foreach ($state['news'] as $n) {
			$h .= '<li><span class="chaos-muted">' . chaos_h(date('j M, H:i', $n['at'])) . '</span> ' . chaos_h($n['text']) . '</li>';
		}
		$h .= '</ul></div>';
	}
	return $h . '</div>';
}

}
