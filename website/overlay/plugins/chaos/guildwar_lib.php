<?php
/**
 * Guild wars on the website (read only): the wars declared and fought in game. The game server writes the tables
 * (server/data/scripts/chaos/guildwar.lua, server/sql/chaos_guildwar.sql); this file only reads them:
 *   chaos_guildwar        one row per declaration: the two guilds, the terms (frag limit, hours, stake), the status
 *                         (pending, active, ended, declined, cancelled, expired), the score, the winner and the payout
 *   chaos_guildwar_kills  every war kill with its verdict (counted, or the anti-farming reason it did not count)
 * Used by page?plugin=chaos&p=guildwars (pages/guildwars.php). Every query is a prepared statement; every value
 * printed goes through chaos_h().
 */

if (!function_exists('chaos_guildwar_state')) {

/** "1d 4h", "3h 12m", "8m" */
function chaos_guildwar_left(int $seconds): string {
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

/** The end reason as guildwar_core.lua C.reasonText says it. */
function chaos_guildwar_reason(string $reason): string {
	$map = array('limit' => 'frag limit reached', 'time' => 'time is up', 'surrender' => 'surrender',
		'disband' => 'a guild disbanded', 'staff' => 'ended by the staff', 'external' => 'ended outside the game');
	return $map[$reason] ?? $reason;
}

/** The terms of a war row: "first to 25 kills, 24 hours, 500,000 gold at stake per side". */
function chaos_guildwar_terms(array $w): string {
	$t = 'first to ' . (int)$w['frag_limit'] . ' kills, ' . (int)$w['hours'] . ' hours, ';
	$stake = (int)$w['stake'];
	return $t . ($stake > 0 ? number_format($stake) . ' gold at stake per side' : 'no stake');
}

/**
 * The board at time $now: ['ok' => bool (tables there), 'active' => [war], 'history' => [war]] where a war is
 * [id, guild1, guild2, kills1, kills2, terms, left (active), ended_at, reason, winner (guild name or '' for a draw),
 *  payout, stake, counted, refused]. History: ended wars only, newest first.
 */
function chaos_guildwar_state(int $now, int $limit = 20): array {
	$out = array('ok' => false, 'active' => array(), 'history' => array());
	if (!chaos_table_exists('chaos_guildwar')) {
		return $out;
	}
	$out['ok'] = true;
	$limit = max(1, min(100, $limit));
	$hasKills = chaos_table_exists('chaos_guildwar_kills');
	$row = static function (array $w) use ($now, $hasKills): array {
		$winner = '';
		if ((int)$w['winner'] !== 0) {
			$winner = (int)$w['winner'] === (int)$w['guild1'] ? (string)$w['name1'] : (string)$w['name2'];
		}
		$counted = $refused = 0;
		if ($hasKills) {
			foreach (chaos_rows('SELECT `counted`, COUNT(*) AS `n` FROM `chaos_guildwar_kills` WHERE `war_id` = ? GROUP BY `counted`;',
				array((int)$w['id'])) as $k) {
				if ((int)$k['counted'] === 1) {
					$counted = (int)$k['n'];
				} else {
					$refused = (int)$k['n'];
				}
			}
		}
		return array(
			'id' => (int)$w['id'],
			'guild1' => (string)$w['name1'],
			'guild2' => (string)$w['name2'],
			'kills1' => (int)$w['kills1'],
			'kills2' => (int)$w['kills2'],
			'frag_limit' => (int)$w['frag_limit'],
			'terms' => chaos_guildwar_terms($w),
			'stake' => (int)$w['stake'],
			'left' => max(0, (int)$w['ends_at'] - $now),
			'started_at' => (int)$w['started_at'],
			'ended_at' => (int)$w['ended_at'],
			'reason' => chaos_guildwar_reason((string)$w['reason']),
			'winner' => $winner,
			'payout' => (int)$w['payout'],
			'counted' => $counted,
			'refused' => $refused,
		);
	};
	$cols = '`id`, `name1`, `name2`, `guild1`, `guild2`, `frag_limit`, `hours`, `stake`, `started_at`, `ends_at`, `ended_at`, '
		. '`kills1`, `kills2`, `winner`, `reason`, `payout`';
	foreach (chaos_rows('SELECT ' . $cols . ' FROM `chaos_guildwar` WHERE `status` = ? ORDER BY `started_at` DESC, `id` DESC LIMIT ' . $limit . ';',
		array('active')) as $w) {
		$out['active'][] = $row($w);
	}
	foreach (chaos_rows('SELECT ' . $cols . ' FROM `chaos_guildwar` WHERE `status` = ? ORDER BY `ended_at` DESC, `id` DESC LIMIT ' . $limit . ';',
		array('ended')) as $w) {
		$out['history'][] = $row($w);
	}
	return $out;
}

/** A guild name linked to ZnoteX's guild page. */
function chaos_guildwar_guild_link(string $name): string {
	return '<a href="guilds?name=' . rawurlencode($name) . '">' . chaos_h($name) . '</a>';
}

/** The two tables of the page: current wars and the history. */
function chaos_guildwar_html(array $state): string {
	if (empty($state['ok'])) {
		return '';
	}
	$h = '<h2 class="chaos-subheading">Wars now</h2>';
	if (!$state['active']) {
		$h .= '<p class="chaos-empty">No guilds are at war.</p>';
	} else {
		$h .= '<table class="chaos-table chaos-wars"><thead><tr><th>War</th><th class="num">Score</th><th>Terms</th><th class="num">Ends in</th></tr></thead><tbody>';
		foreach ($state['active'] as $w) {
			$h .= '<tr><td>' . chaos_guildwar_guild_link($w['guild1']) . ' <span class="chaos-muted">vs</span> ' . chaos_guildwar_guild_link($w['guild2'])
				. '</td><td class="num chaos-gold">' . (int)$w['kills1'] . ' : ' . (int)$w['kills2'] . '</td><td>' . chaos_h($w['terms'])
				. '</td><td class="num">' . chaos_h(chaos_guildwar_left((int)$w['left'])) . '</td></tr>';
		}
		$h .= '</tbody></table>';
	}
	$h .= '<h2 class="chaos-subheading">History</h2>';
	if (!$state['history']) {
		$h .= '<p class="chaos-empty">No war has ended yet.</p>';
	} else {
		$h .= '<table class="chaos-table chaos-wars"><thead><tr><th>War</th><th class="num">Score</th><th>Result</th><th class="num">Kills not counted</th><th>Ended</th></tr></thead><tbody>';
		foreach ($state['history'] as $w) {
			$result = $w['winner'] === '' ? 'Draw' : chaos_h($w['winner']) . ' won';
			if ($w['winner'] !== '' && (int)$w['payout'] > 0) {
				$result .= ' <span class="chaos-muted">(' . chaos_h(number_format((int)$w['payout'])) . ' gold)</span>';
			}
			$h .= '<tr><td>' . chaos_guildwar_guild_link($w['guild1']) . ' <span class="chaos-muted">vs</span> ' . chaos_guildwar_guild_link($w['guild2'])
				. '</td><td class="num chaos-gold">' . (int)$w['kills1'] . ' : ' . (int)$w['kills2'] . '</td><td>' . $result
				. ' <span class="chaos-muted">' . chaos_h($w['reason']) . '</span></td><td class="num">' . (int)$w['refused']
				. '</td><td>' . chaos_h(date('j M Y', (int)$w['ended_at'])) . '</td></tr>';
		}
		$h .= '</tbody></table>';
	}
	return $h;
}

}
