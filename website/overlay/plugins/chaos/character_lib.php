<?php
/**
 * The character page (O392, website/README.md "Character page"): page?plugin=chaos&p=character&name=NAME. Read only,
 * prepared statements, chaos_h() on output. What it shows of one character:
 *   class and level, the look, the worn gear (player_items, slots 1-10 without the backpack), the build code of its
 *   class, level, passive tree (the active preset of chaos_passive_tree, the Paragon points of chaos_paragon) and gear,
 *   achievements (chaos_achievements with the names of the game's achievements_data.lua), the titles they give, the
 *   level milestones (O378: the "milestones" category), best runs (Infinity Tower floor, rift tier, arena ratings,
 *   weekly board podiums) and season results (chaos_season_players, chaos_season_modes, chaos_tower_season_rewards).
 * Privacy:
 *   - the staff's tester bots (chaos_tester_sql) and characters hidden on the account page (znote_players.hide_char)
 *     have no page (404, the same answer as an unknown name);
 *   - best runs and season results follow the character's Memorial choice (chaos_memorial_optin.records = 0 hides
 *     them, as on the Memorial and the Chronicle); a Hardcore fall is named only with its yes (fallen = 1);
 *   - nothing of the account (e-mail, IP, last login, other characters) is read.
 * Tables that are missing (an older game server) leave their part out.
 */

require_once __DIR__ . '/buildcode_lib.php';

if (!function_exists('chaos_character_find')) {

/** The character's row, or null (unknown, hidden on its account, a tester bot). */
function chaos_character_find(string $name): ?array {
	$name = trim($name);
	if ($name === '' || strlen($name) > 64) {
		return null;
	}
	$hidden = chaos_table_exists('znote_players')
		? ' AND NOT EXISTS (SELECT 1 FROM `znote_players` `z` WHERE `z`.`player_id` = `p`.`id` AND `z`.`hide_char` = 1)' : '';
	$rows = chaos_rows('SELECT `p`.`id`, `p`.`name`, `p`.`level`, `p`.`vocation`, `p`.`sex`, `p`.`looktype`, `p`.`lookhead`, '
		. '`p`.`lookbody`, `p`.`looklegs`, `p`.`lookfeet`, `p`.`lookaddons` FROM `players` `p` WHERE `p`.`name` = ?'
		. $hidden . chaos_tester_sql('`p`') . ' LIMIT 1;', array($name));
	return $rows ? $rows[0] : null;
}

/** The worn gear: [[slot, id, count]] in slot order (no backpack). */
function chaos_character_gear(int $playerId): array {
	if (!chaos_table_exists('player_items')) {
		return array();
	}
	$out = array();
	foreach (chaos_rows('SELECT `pid`, `itemtype`, `count` FROM `player_items` WHERE `player_id` = ? AND `pid` >= 1 AND `pid` <= 10 '
		. 'AND `pid` <> 3 ORDER BY `pid` ASC;', array($playerId)) as $r) {
		$out[] = array('slot' => (int)$r['pid'], 'id' => (int)$r['itemtype'], 'count' => (int)$r['count']);
	}
	return $out;
}

/** The passive tree of the active preset (the lowest one, passivetree.lua activePreset) and the Paragon points. */
function chaos_character_tree(int $playerId, int $vocation): ?array {
	if (!chaos_table_exists('chaos_passive_tree')) {
		return null;
	}
	$rows = chaos_rows('SELECT `nodes` FROM `chaos_passive_tree` WHERE `player_id` = ? ORDER BY `preset` ASC LIMIT 1;', array($playerId));
	if (!$rows) {
		return null;
	}
	$text = (string)$rows[0]['nodes'];
	$parts = explode('|', $text, 2);
	$nodes = array();
	foreach (preg_split('/\D+/', $parts[0], -1, PREG_SPLIT_NO_EMPTY) as $id) {
		$nodes[(int)$id] = (int)$id;
	}
	$masteries = array();
	if (isset($parts[1]) && preg_match_all('/(\d+):(\d+)/', $parts[1], $m, PREG_SET_ORDER)) {
		foreach ($m as $x) {
			if (isset($nodes[(int)$x[1]]) && (int)$x[2] > 0) {
				$masteries[(int)$x[1]] = (int)$x[2];
			}
		}
	}
	$paragon = array();
	if (chaos_table_exists('chaos_paragon')) {
		$keys = array_flip(chaos_buildcode_paragon_keys());
		foreach (chaos_rows('SELECT `stat`, `points` FROM `chaos_paragon` WHERE `player_id` = ?;', array($playerId)) as $r) {
			if (isset($keys[(string)$r['stat']]) && (int)$r['points'] > 0) {
				$paragon[(string)$r['stat']] = (int)$r['points'];
			}
		}
	}
	$base = chaos_base_of($vocation);
	$line = $base !== null ? (chaos_buildcode_tree_lines()[$base] ?? 0) : 0;
	return array('line' => $line, 'nodes' => array_values($nodes), 'masteries' => $masteries, 'paragon' => $paragon);
}

/** The full build code of the character (no spells: the rotation lives in the player's client). */
function chaos_character_build_code(array $p, array $gear, ?array $tree): ?string {
	$card = array('level' => max(1, min(65535, (int)$p['level'])), 'gear' => $gear);
	$class = chaos_buildcode_class_of_vocation((int)$p['vocation']);
	if ($class !== null) {
		$card['class'] = $class;
	}
	if ($tree !== null && $tree['nodes']) {
		$card['tree'] = chaos_buildcode_tree_encode($tree);
	}
	$r = chaos_buildcode_encode($card);
	return $r['code'] ?? null;
}

/**
 * The game's achievements (achievements_data.lua, read from the server data): id => [name, desc, cat, points, title,
 * target, hidden] and the categories key => name.
 */
function chaos_achievement_defs(): array {
	static $defs = null;
	if ($defs !== null) {
		return $defs;
	}
	$defs = array('list' => array(), 'categories' => array());
	$text = chaos_read_server_file('scripts/chaos/achievements_data.lua');
	if ($text === '') {
		return $defs;
	}
	if (preg_match_all('/\{key = "([a-z0-9_]+)", name = "((?:[^"\\\\]|\\\\.)*)"\}/', $text, $m, PREG_SET_ORDER)) {
		foreach ($m as $c) {
			$defs['categories'][$c[1]] = stripcslashes($c[2]);
		}
	}
	$chunks = preg_split('/\{id = "/', $text);
	array_shift($chunks);
	foreach ($chunks as $chunk) {
		if (!preg_match('/^([a-z0-9_]+)"/', $chunk, $id)) {
			continue;
		}
		$field = static function (string $key) use ($chunk): ?string {
			return preg_match('/\b' . $key . ' = "((?:[^"\\\\]|\\\\.)*)"/', $chunk, $v) ? stripcslashes($v[1]) : null;
		};
		$num = static function (string $key) use ($chunk): int {
			return preg_match('/\b' . $key . ' = (\d+)/', $chunk, $v) ? (int)$v[1] : 0;
		};
		$defs['list'][$id[1]] = array('name' => (string)($field('name') ?? $id[1]), 'desc' => (string)($field('desc') ?? ''),
			'cat' => (string)($field('cat') ?? ''), 'points' => $num('points'), 'title' => (string)($field('title') ?? ''),
			'target' => $num('target'), 'hidden' => (bool)preg_match('/\bhidden = true/', $chunk));
	}
	return $defs;
}

/** Achievements of the character: [count, points, recent => [[id, name, desc, points, at]], titles => [text],
 *  milestones => [[name, level, title, at|0]], chosen => title text or '']. */
function chaos_character_achievements(int $playerId): array {
	$out = array('count' => 0, 'points' => 0, 'recent' => array(), 'titles' => array(), 'milestones' => array(), 'chosen' => '');
	$defs = chaos_achievement_defs();
	$have = array();
	if (chaos_table_exists('chaos_achievements')) {
		foreach (chaos_rows('SELECT `achievement`, `unlocked_at` FROM `chaos_achievements` WHERE `player_id` = ? '
			. 'ORDER BY `unlocked_at` DESC, `achievement` ASC;', array($playerId)) as $r) {
			$have[(string)$r['achievement']] = (int)$r['unlocked_at'];
		}
	}
	foreach ($have as $id => $at) {
		$d = $defs['list'][$id] ?? null;
		if ($d === null) {
			continue; // retired
		}
		$out['count']++;
		$out['points'] += $d['points'];
		if (count($out['recent']) < 10) {
			$out['recent'][] = array('id' => $id, 'name' => $d['name'], 'desc' => $d['desc'], 'points' => $d['points'], 'at' => $at);
		}
		if ($d['title'] !== '') {
			$out['titles'][] = $d['title'];
		}
	}
	foreach ($defs['list'] as $id => $d) {
		if ($d['cat'] === 'milestones') {
			$out['milestones'][] = array('name' => $d['name'], 'level' => $d['target'], 'title' => $d['title'], 'at' => $have[$id] ?? 0);
		}
	}
	usort($out['milestones'], static function ($a, $b) { return $a['level'] <=> $b['level']; });
	if (chaos_table_exists('chaos_player_titles')) {
		$row = chaos_rows('SELECT `title_key` FROM `chaos_player_titles` WHERE `player_id` = ? LIMIT 1;', array($playerId));
		$key = $row ? (string)$row[0]['title_key'] : '';
		foreach ($out['titles'] as $t) {
			if ($key === 'achievement:' . strtolower($t)) {
				$out['chosen'] = $t;
			}
		}
	}
	return $out;
}

/** The character's Memorial choice: [records => bool, fallen => bool] (records on, fallen off without a row). */
function chaos_character_consent(int $playerId): array {
	$c = array('records' => true, 'fallen' => false);
	if (chaos_table_exists('chaos_memorial_optin')) {
		$row = chaos_rows('SELECT `records`, `fallen` FROM `chaos_memorial_optin` WHERE `player_id` = ? LIMIT 1;', array($playerId));
		if ($row) {
			$c = array('records' => (int)$row[0]['records'] === 1, 'fallen' => (int)$row[0]['fallen'] === 1);
		}
	}
	return $c;
}

/** Best runs: [tower => [floor, time] | null, rift => tier, arena => [[mode, rating, best, wins, losses]],
 *  podiums => [[board, places, best]]]. */
function chaos_character_runs(int $playerId): array {
	$out = array('tower' => null, 'rift' => 0, 'arena' => array(), 'podiums' => array());
	if (chaos_table_exists('chaos_tower_players')) {
		$r = chaos_rows('SELECT `best_floor`, `best_time` FROM `chaos_tower_players` WHERE `player_id` = ? AND `best_floor` > 0 '
			. 'ORDER BY `best_floor` DESC, `best_time` ASC LIMIT 1;', array($playerId));
		if ($r) {
			$out['tower'] = array('floor' => (int)$r[0]['best_floor'], 'time' => (int)$r[0]['best_time']);
		}
	}
	if (chaos_table_exists('chaos_achievement_stats')) {
		$r = chaos_rows('SELECT `value` FROM `chaos_achievement_stats` WHERE `player_id` = ? AND `stat` = ? LIMIT 1;', array($playerId, 'rift_tier'));
		$out['rift'] = $r ? (int)$r[0]['value'] : 0;
	}
	if (chaos_table_exists('chaos_arena_ratings')) {
		foreach (chaos_rows('SELECT `mode`, `rating`, `best`, `wins`, `losses` FROM `chaos_arena_ratings` WHERE `player_id` = ? '
			. 'AND (`wins` + `losses`) > 0 ORDER BY `mode` ASC;', array($playerId)) as $r) {
			$out['arena'][] = array('mode' => (string)$r['mode'], 'rating' => (int)$r['rating'], 'best' => (int)$r['best'],
				'wins' => (int)$r['wins'], 'losses' => (int)$r['losses']);
		}
	}
	if (chaos_table_exists('chaos_leaderboard_titles')) {
		foreach (chaos_rows('SELECT `board`, COUNT(*) AS `n`, MIN(`rank`) AS `best` FROM `chaos_leaderboard_titles` WHERE `player_id` = ? '
			. 'GROUP BY `board` ORDER BY `board` ASC;', array($playerId)) as $r) {
			$out['podiums'][] = array('board' => (string)$r['board'], 'places' => (int)$r['n'], 'best' => (int)$r['best']);
		}
	}
	return $out;
}

/** Season results: [[season, name, mode, fallen => [level, cause] | null, place]]. */
function chaos_character_seasons(int $playerId, bool $showFall): array {
	if (!chaos_table_exists('chaos_season_players')) {
		return array();
	}
	$names = array();
	foreach (chaos_seasons() as $id => $s) {
		$names[$id] = $s['name'];
	}
	$out = array();
	foreach (chaos_rows('SELECT `season` FROM `chaos_season_players` WHERE `player_id` = ? ORDER BY `season` DESC;', array($playerId)) as $r) {
		$id = (int)$r['season'];
		$out[$id] = array('season' => $id, 'name' => $names[$id] ?? ('Season ' . $id), 'mode' => 'Standard', 'fallen' => null, 'place' => 0);
	}
	if ($out && chaos_table_exists('chaos_season_modes')) {
		foreach (chaos_rows('SELECT `season`, `ssf`, `hc`, `fallen_at`, `fallen_level`, `fallen_cause` FROM `chaos_season_modes` WHERE `player_id` = ?;', array($playerId)) as $r) {
			$id = (int)$r['season'];
			if (!isset($out[$id])) {
				continue;
			}
			$mode = array();
			if ((int)$r['hc'] === 1) {
				$mode[] = 'Hardcore';
			}
			if ((int)$r['ssf'] === 1) {
				$mode[] = 'Self-Found';
			}
			$out[$id]['mode'] = $mode ? implode(' ', $mode) : 'Standard';
			if ((int)$r['fallen_at'] > 0 && $showFall) {
				$out[$id]['fallen'] = array('level' => (int)$r['fallen_level'], 'cause' => (string)$r['fallen_cause']);
			}
		}
	}
	if ($out && chaos_table_exists('chaos_tower_season_rewards')) {
		foreach (chaos_rows('SELECT `season`, `place` FROM `chaos_tower_season_rewards` WHERE `player_id` = ?;', array($playerId)) as $r) {
			if (isset($out[(int)$r['season']])) {
				$out[(int)$r['season']]['place'] = (int)$r['place'];
			}
		}
	}
	return array_values($out);
}

/** m:ss of seconds. */
function chaos_character_time(int $s): string {
	return intdiv($s, 60) . ':' . str_pad((string)($s % 60), 2, '0', STR_PAD_LEFT);
}

/** Every part of the page for a character row. */
function chaos_character_page(array $p): array {
	$id = (int)$p['id'];
	$gear = chaos_character_gear($id);
	$tree = chaos_character_tree($id, (int)$p['vocation']);
	$consent = chaos_character_consent($id);
	return array(
		'gear' => $gear,
		'code' => chaos_character_build_code($p, $gear, $tree),
		'achievements' => chaos_character_achievements($id),
		'consent' => $consent,
		'runs' => $consent['records'] ? chaos_character_runs($id) : null,
		'seasons' => $consent['records'] ? chaos_character_seasons($id, $consent['fallen']) : null,
	);
}

/** The HTML of the page's body (below the heading). */
function chaos_character_html(array $p, array $d, string $siteUrl = ''): string {
	$class = chaos_class_name((int)$p['vocation']);
	$look = function_exists('chaos_outfit_url') && chaos_sprites_on()
		? chaos_sprite_img(chaos_outfit_url((int)$p['looktype'], (int)$p['lookaddons'], (int)$p['lookhead'], (int)$p['lookbody'],
			(int)$p['looklegs'], (int)$p['lookfeet']), (string)$p['name'], 64, 64, 'chaos-look') : '';
	$a = $d['achievements'];
	$h = '<div class="chaos-character">' . $look . '<p class="chaos-lead">Level ' . (int)$p['level'] . ' ' . chaos_h($class)
		. ($a['chosen'] !== '' ? ', <span class="chaos-gold">' . chaos_h($a['chosen']) . '</span>' : '') . '. '
		. '<a href="characterprofile?name=' . rawurlencode((string)$p['name']) . '">Profile and deaths</a></p></div>';

	$h .= '<h2 class="chaos-subheading">Gear</h2>' . chaos_build_gear_html($d['gear']);
	if ($d['code'] !== null) {
		$h .= '<p><a href="' . chaos_h(chaos_build_url($d['code'])) . '">Open this build</a> (class, passive tree and gear) on the Build page.</p>';
	}

	$h .= '<h2 class="chaos-subheading">Achievements</h2>';
	if ($a['count'] === 0) {
		$h .= '<p class="chaos-empty">No achievements yet.</p>';
	} else {
		$h .= '<p><strong class="chaos-gold">' . $a['count'] . '</strong> achievements, <strong class="chaos-gold">' . $a['points'] . '</strong> points.</p>'
			. '<table class="chaos-table"><thead><tr><th>Latest</th><th>Points</th><th>Unlocked</th></tr></thead><tbody>';
		foreach ($a['recent'] as $r) {
			$h .= '<tr><td><strong>' . chaos_h($r['name']) . '</strong><br><span class="chaos-muted">' . chaos_h($r['desc']) . '</span></td><td>'
				. (int)$r['points'] . '</td><td>' . ($r['at'] > 0 ? chaos_h(gmdate('Y-m-d', $r['at'])) : '') . '</td></tr>';
		}
		$h .= '</tbody></table>';
		if ($a['titles']) {
			$h .= '<p>Titles: ' . chaos_h(implode(', ', $a['titles'])) . '.</p>';
		}
	}

	if ($a['milestones']) {
		$h .= '<h2 class="chaos-subheading">Level milestones</h2><ul class="chaos-build__list chaos-character__milestones">';
		foreach ($a['milestones'] as $m) {
			$done = $m['at'] > 0;
			$h .= '<li class="' . ($done ? 'chaos-gold' : 'chaos-muted') . '">' . (int)$m['level'] . ': ' . chaos_h($m['name'])
				. ($m['title'] !== '' ? ' (' . chaos_h($m['title']) . ')' : '') . ($done ? ', reached ' . chaos_h(gmdate('Y-m-d', $m['at'])) : '') . '</li>';
		}
		$h .= '</ul>';
	}

	$h .= '<h2 class="chaos-subheading">Best runs</h2>';
	if ($d['runs'] === null) {
		$h .= '<p class="chaos-note">This player keeps their records private (in the game: Adventure &gt; Chronicle &gt; Memorial).</p>';
	} else {
		$r = $d['runs'];
		$rows = array();
		if ($r['tower'] !== null) {
			$rows[] = array('Infinity Tower', 'floor ' . $r['tower']['floor'] . ($r['tower']['time'] > 0 ? ' in ' . chaos_character_time($r['tower']['time']) : ''));
		}
		if ($r['rift'] > 0) {
			$rows[] = array('Sealed rifts', 'tier ' . $r['rift']);
		}
		foreach ($r['arena'] as $x) {
			$rows[] = array('Arena ' . $x['mode'], 'rating ' . $x['rating'] . ' (best ' . $x['best'] . '), ' . $x['wins'] . ' wins, ' . $x['losses'] . ' losses');
		}
		foreach ($r['podiums'] as $x) {
			$rows[] = array('Weekly board: ' . ucfirst($x['board']), $x['places'] . ' podium' . ($x['places'] === 1 ? '' : 's') . ', best place ' . $x['best']);
		}
		if (!$rows) {
			$h .= '<p class="chaos-empty">No runs on the boards yet.</p>';
		} else {
			$h .= '<table class="chaos-table"><tbody>';
			foreach ($rows as $row) {
				$h .= '<tr><td>' . chaos_h($row[0]) . '</td><td>' . chaos_h($row[1]) . '</td></tr>';
			}
			$h .= '</tbody></table>';
		}
		if ($d['seasons']) {
			$h .= '<h2 class="chaos-subheading">Seasons</h2><table class="chaos-table"><thead><tr><th>Season</th><th>Mode</th><th>Result</th></tr></thead><tbody>';
			foreach ($d['seasons'] as $s) {
				$result = array();
				if ($s['place'] > 0) {
					$result[] = 'Infinity Tower place ' . $s['place'];
				}
				if ($s['fallen'] !== null) {
					$result[] = 'fell at level ' . $s['fallen']['level'] . ($s['fallen']['cause'] !== '' ? ', ' . $s['fallen']['cause'] : '');
				}
				$h .= '<tr><td>' . chaos_h($s['name']) . '</td><td>' . chaos_h($s['mode']) . '</td><td>' . chaos_h(implode('; ', $result)) . '</td></tr>';
			}
			$h .= '</tbody></table>';
		}
	}

	$link = ($siteUrl !== '' ? rtrim($siteUrl, '/') . '/' : '') . 'page?plugin=chaos&p=character&name=' . rawurlencode((string)$p['name']);
	$h .= '<h2 class="chaos-subheading">Share</h2><p><label>Link <input class="chaos-build__share" type="text" readonly value="' . chaos_h($link) . '"></label></p>';
	return $h;
}

} // function_exists
