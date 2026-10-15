<?php
/**
 * Balance telemetry for the staff page (pages/telemetry.php). Reads the game server's hourly aggregates
 * (chaos_telemetry_*: server/sql/chaos_telemetry.sql, data/scripts/chaos/telemetry.lua) and the store purchase log
 * (chaos_shop_purchases, shop.lua) for coins per category. Nothing here writes. Charts are plain SVG drawn here on the
 * server: no script, no external file, no CDN.
 *
 * Access: an admin panel account (chaos_reports_is_admin) with a character of group 5 or higher, as the bazaar and
 * creator staff tools. Privacy: the tables hold aggregates only (no ids, no names); a hunting rate is shown only for a
 * day or group with at least CHAOS_TELEMETRY_MIN_PLAYERS characters behind it, so no one character's numbers can be read.
 * Every query is a prepared statement through ZnoteX's db(); every value printed goes through chaos_h().
 */

if (!function_exists('chaos_telemetry_is_admin')) {

define('CHAOS_TELEMETRY_ADMIN_GROUP', 5);
define('CHAOS_TELEMETRY_MIN_PLAYERS', 3);
define('CHAOS_TELEMETRY_MAX_DAYS', 400);

/** An admin panel account with a character of group 5 or higher. */
function chaos_telemetry_is_admin(array $config, int $accountId): bool {
	require_once __DIR__ . '/reports_lib.php';
	if (!chaos_reports_is_admin($config, $accountId)) {
		return false;
	}
	$row = db()->fetchOne('SELECT MAX(`group_id`) AS `g` FROM `players` WHERE `account_id` = ?;', [$accountId]);
	return is_array($row) && (int)($row['g'] ?? 0) >= CHAOS_TELEMETRY_ADMIN_GROUP;
}

/** The level band labels of telemetry_config.lua (read from the server data when it is there). */
function chaos_telemetry_bands(): array {
	$default = array('1-99', '100-299', '300-499', '500-999', '1000+');
	$text = function_exists('chaos_read_server_file') ? chaos_read_server_file('scripts/chaos/telemetry_config.lua') : '';
	if ($text === '' || !preg_match('/\bbands\s*=\s*\{(.*?)\}\s*,\s*\n/s', $text, $m)) {
		return $default;
	}
	$out = array();
	if (preg_match_all('/\{\s*(\d+)\s*,\s*(\d+|nil)\s*\}/', $m[1], $all, PREG_SET_ORDER)) {
		foreach ($all as $b) {
			$out[] = $b[2] === 'nil' ? ($b[1] . '+') : ($b[1] . '-' . $b[2]);
		}
	}
	return $out ?: $default;
}

/** Class filter options: '' all, 'l<base>' a line, 'c<id>' one class => label. */
function chaos_telemetry_class_options(): array {
	$out = array('' => 'All classes');
	foreach (chaos_class_lines() as $base => $line) {
		$out['l' . $base] = $line['name'] . ' (line)';
		$out['c' . $base] = $line['name'];
		foreach ($line['asc'] as $id => $asc) {
			$out['c' . $id] = $asc[0];
		}
	}
	return $out;
}

/** The vocation ids of a class filter value, or array() for every class. */
function chaos_telemetry_vocs(string $class): array {
	if (preg_match('/^l(\d+)$/', $class, $m)) {
		return chaos_line_ids((int)$m[1]);
	}
	if (preg_match('/^c(\d+)$/', $class, $m)) {
		return array((int)$m[1]);
	}
	return array();
}

/** The filters from the query string, validated (never used raw in SQL). $now: the current time (tests). */
function chaos_telemetry_filters(array $get, ?int $now = null): array {
	$now = $now ?? time();
	$band = (string)($get['band'] ?? '');
	if (!in_array($band, chaos_telemetry_bands(), true)) {
		$band = '';
	}
	$class = (string)($get['class'] ?? '');
	if (!array_key_exists($class, chaos_telemetry_class_options())) {
		$class = '';
	}
	$day = static function ($v): ?int {
		$v = (string)$v;
		if (!preg_match('/^(\d{4})-(\d{2})-(\d{2})$/', $v, $m) || !checkdate((int)$m[2], (int)$m[3], (int)$m[1])) {
			return null;
		}
		return gmmktime(0, 0, 0, (int)$m[2], (int)$m[3], (int)$m[1]);
	};
	$today = $now - $now % 86400;
	$to = $day($get['to'] ?? '') ?? $today;
	$from = $day($get['from'] ?? '') ?? ($to - 13 * 86400);
	if ($to > $today) {
		$to = $today;
	}
	if ($from > $to) {
		$from = $to;
	}
	if (($to - $from) / 86400 >= CHAOS_TELEMETRY_MAX_DAYS) {
		$from = $to - (CHAOS_TELEMETRY_MAX_DAYS - 1) * 86400;
	}
	return array('band' => $band, 'class' => $class, 'vocs' => chaos_telemetry_vocs($class), 'from' => $from,
		'to' => $to, 'until' => $to + 86400);
}

/** WHERE clause and parameters of the period, the band and the classes (only the columns the table has). */
function chaos_telemetry_where(array $f, bool $band, bool $voc): array {
	$where = array('`at` >= ?', '`at` < ?');
	$params = array($f['from'], $f['until']);
	if ($band && $f['band'] !== '') {
		$where[] = '`band` = ?';
		$params[] = $f['band'];
	}
	if ($voc && $f['vocs']) {
		$where[] = '`voc` IN (' . implode(', ', array_fill(0, count($f['vocs']), '?')) . ')';
		$params = array_merge($params, $f['vocs']);
	}
	return array(implode(' AND ', $where), $params);
}

/** XP/h and gold/h of a sums row, or null for the rates when fewer than the minimum characters are behind it. */
function chaos_telemetry_rates(array $r): array {
	$secs = (int)($r['secs'] ?? 0);
	$players = (int)($r['players'] ?? 0);
	$ok = $secs > 0 && $players >= CHAOS_TELEMETRY_MIN_PLAYERS;
	return array(
		'xph' => $ok ? (int)round((int)$r['exp'] * 3600 / $secs) : null,
		'gph' => $ok ? (int)round(((int)$r['loot'] - (int)$r['supplies']) * 3600 / $secs) : null,
		'hours' => round($secs / 3600, 1),
		'players' => $players,
	);
}

/** Hunting per day: [day => rates]. */
function chaos_telemetry_hunt_days(array $f): array {
	[$w, $p] = chaos_telemetry_where($f, true, true);
	$rows = chaos_rows("SELECT `at` - (`at` % 86400) AS `day`, SUM(`exp`) AS `exp`, SUM(`loot`) AS `loot`,
		SUM(`supplies`) AS `supplies`, SUM(`hunt_seconds`) AS `secs`, SUM(`players`) AS `players`
		FROM `chaos_telemetry_hunt` WHERE $w GROUP BY `day` ORDER BY `day`;", $p);
	$out = array();
	foreach ($rows as $r) {
		$out[(int)$r['day']] = chaos_telemetry_rates($r);
	}
	return $out;
}

/** Hunting per class (the band filter applies): [voc => rates], classes with no hunting left out. */
function chaos_telemetry_hunt_classes(array $f): array {
	[$w, $p] = chaos_telemetry_where($f, true, true);
	$rows = chaos_rows("SELECT `voc`, SUM(`exp`) AS `exp`, SUM(`loot`) AS `loot`, SUM(`supplies`) AS `supplies`,
		SUM(`hunt_seconds`) AS `secs`, SUM(`players`) AS `players`, SUM(`kills`) AS `kills`
		FROM `chaos_telemetry_hunt` WHERE $w GROUP BY `voc` ORDER BY `voc`;", $p);
	$out = array();
	foreach ($rows as $r) {
		$out[(int)$r['voc']] = chaos_telemetry_rates($r) + array('kills' => (int)$r['kills']);
	}
	return $out;
}

/** Hunting per level band (the class filter applies). */
function chaos_telemetry_hunt_bands(array $f): array {
	[$w, $p] = chaos_telemetry_where($f, false, true);
	$rows = chaos_rows("SELECT `band`, SUM(`exp`) AS `exp`, SUM(`loot`) AS `loot`, SUM(`supplies`) AS `supplies`,
		SUM(`hunt_seconds`) AS `secs`, SUM(`players`) AS `players`
		FROM `chaos_telemetry_hunt` WHERE $w GROUP BY `band`;", $p);
	$order = array_flip(chaos_telemetry_bands());
	$out = array();
	foreach ($rows as $r) {
		$out[(string)$r['band']] = chaos_telemetry_rates($r);
	}
	uksort($out, static function ($a, $b) use ($order) { return ($order[$a] ?? 99) <=> ($order[$b] ?? 99); });
	return $out;
}

/**
 * Online per day: [day => [avg, max]]. Without a band or class filter the total rows ('all'); with one, the sum of the
 * matching buckets over the total's samples (max: the highest bucket of the day, a lower bound).
 */
function chaos_telemetry_online_days(array $f): array {
	$filtered = $f['band'] !== '' || $f['vocs'];
	[$w, $p] = chaos_telemetry_where($f, true, true);
	if (!$filtered) {
		$w .= " AND `band` = 'all'";
	} else {
		$w .= " AND `band` <> 'all'";
	}
	$rows = chaos_rows("SELECT `at` - (`at` % 86400) AS `day`, SUM(`online_sum`) AS `s`, MAX(`online_max`) AS `m`
		FROM `chaos_telemetry_online` WHERE $w GROUP BY `day` ORDER BY `day`;", $p);
	$samples = array();
	foreach (chaos_rows("SELECT `at` - (`at` % 86400) AS `day`, SUM(`samples`) AS `n` FROM `chaos_telemetry_online`
		WHERE `at` >= ? AND `at` < ? AND `band` = 'all' GROUP BY `day`;", array($f['from'], $f['until'])) as $r) {
		$samples[(int)$r['day']] = (int)$r['n'];
	}
	$out = array();
	foreach ($rows as $r) {
		$n = $samples[(int)$r['day']] ?? 0;
		$out[(int)$r['day']] = array('avg' => $n > 0 ? round((int)$r['s'] / $n, 1) : 0, 'max' => (int)$r['m']);
	}
	return $out;
}

/** Bosses: kills and kill times per boss and party size (no band or class: the tables have none). */
function chaos_telemetry_bosses(array $f): array {
	[$w, $p] = chaos_telemetry_where($f, false, false);
	return chaos_rows("SELECT `boss`, `party`, SUM(`kills`) AS `kills`, SUM(`timed`) AS `timed`,
		SUM(`secs_total`) AS `total`, MIN(NULLIF(`secs_min`, 0)) AS `best`, MAX(`secs_max`) AS `worst`
		FROM `chaos_telemetry_boss` WHERE $w GROUP BY `boss`, `party` ORDER BY `boss`, `party` LIMIT 200;", $p);
}

/** Deaths per area and per area and killer (the band filter applies). [areas, pairs] */
function chaos_telemetry_deaths(array $f, int $limit = 15): array {
	[$w, $p] = chaos_telemetry_where($f, true, false);
	$areas = chaos_rows("SELECT `area`, SUM(`deaths`) AS `n` FROM `chaos_telemetry_deaths` WHERE $w
		GROUP BY `area` ORDER BY `n` DESC, `area` LIMIT $limit;", $p);
	$pairs = chaos_rows("SELECT `area`, `killer`, SUM(`deaths`) AS `n` FROM `chaos_telemetry_deaths` WHERE $w
		GROUP BY `area`, `killer` ORDER BY `n` DESC, `area`, `killer` LIMIT 30;", $p);
	return array($areas, $pairs);
}

/** Spell casts per spell (the class filter applies), most cast first. */
function chaos_telemetry_casts(array $f, int $limit = 20): array {
	[$w, $p] = chaos_telemetry_where($f, false, true);
	return chaos_rows("SELECT `voc`, `spell`, SUM(`casts`) AS `n` FROM `chaos_telemetry_casts` WHERE $w
		GROUP BY `voc`, `spell` ORDER BY `n` DESC, `spell` LIMIT $limit;", $p);
}

/** Gold faucets and sinks: [per day [day => [faucet, sink]], per source rows]. The band filter applies. */
function chaos_telemetry_economy(array $f): array {
	[$w, $p] = chaos_telemetry_where($f, true, false);
	$days = array();
	foreach (chaos_rows("SELECT `at` - (`at` % 86400) AS `day`, `flow`, SUM(`gold`) AS `g` FROM `chaos_telemetry_economy`
		WHERE $w GROUP BY `day`, `flow` ORDER BY `day`;", $p) as $r) {
		$d = (int)$r['day'];
		$days[$d] = $days[$d] ?? array('faucet' => 0, 'sink' => 0);
		$days[$d][(string)$r['flow'] === 'sink' ? 'sink' : 'faucet'] += (int)$r['g'];
	}
	$sources = chaos_rows("SELECT `flow`, `source`, SUM(`gold`) AS `g`, SUM(`events`) AS `n` FROM `chaos_telemetry_economy`
		WHERE $w GROUP BY `flow`, `source` ORDER BY `flow`, `g` DESC;", $p);
	return array($days, $sources);
}

/** Chaos Coins spent per store category (chaos_shop_purchases; the band filter applies through the buyer's level). */
function chaos_telemetry_store(array $f): array {
	$where = array('`created` >= ?', '`created` < ?');
	$params = array($f['from'], $f['until']);
	if ($f['band'] !== '' && preg_match('/^(\d+)(?:-(\d+)|\+)$/', $f['band'], $m)) {
		$where[] = '`level` >= ?';
		$params[] = (int)$m[1];
		if (isset($m[2]) && $m[2] !== '') {
			$where[] = '`level` <= ?';
			$params[] = (int)$m[2];
		}
	}
	return chaos_rows('SELECT CASE WHEN `category` = \'\' THEN \'(none)\' ELSE `category` END AS `category`,
		SUM(`price`) AS `coins`, COUNT(*) AS `n` FROM `chaos_shop_purchases` WHERE ' . implode(' AND ', $where) . '
		GROUP BY `category` ORDER BY `coins` DESC LIMIT 30;', $params);
}

// ---------------------------------------------------------------------------
// SVG charts (server-rendered; a <title> on every mark is its tooltip; a table view sits under each chart)
// ---------------------------------------------------------------------------

/** Series colours: gold (faucets, the single series) and ember (sinks); checked for colour-blind separation. */
function chaos_telemetry_colors(): array {
	return array('gold' => '#bf8a26', 'ember' => '#d0452a', 'ink' => '#d6c9ae', 'muted' => '#8c8070',
		'grid' => 'rgba(87,77,82,.45)');
}

function chaos_telemetry_num($v): string {
	if ($v === null) {
		return '-';
	}
	$a = abs((float)$v);
	if ($a >= 1e9) { return round($v / 1e9, 1) . 'B'; }
	if ($a >= 1e6) { return round($v / 1e6, 1) . 'M'; }
	if ($a >= 1e4) { return round($v / 1e3, 1) . 'k'; }
	return (string)(is_float($v) ? round($v, 1) : $v);
}

/** A "nice" axis top for the largest value. */
function chaos_telemetry_axis_max(float $max): float {
	if ($max <= 0) {
		return 1;
	}
	$p = pow(10, floor(log10($max)));
	foreach (array(1, 2, 2.5, 5, 10) as $s) {
		if ($max <= $s * $p) {
			return $s * $p;
		}
	}
	return 10 * $p;
}

/**
 * Line chart over days. $series: [['name' => ..., 'color' => ..., 'points' => [day => value|null]]]. A null value is a
 * gap (too few characters). Two series are labelled at their last point and in a legend.
 */
function chaos_telemetry_line_svg(string $title, array $series, string $unit = ''): string {
	$c = chaos_telemetry_colors();
	$w = 640; $h = 220; $l = 56; $r = 16; $t = 14; $b = 28;
	$days = array();
	$max = 0.0;
	$min = 0.0;
	foreach ($series as $s) {
		foreach ($s['points'] as $d => $v) {
			$days[(int)$d] = true;
			if ($v !== null) {
				$max = max($max, (float)$v);
				$min = min($min, (float)$v);
			}
		}
	}
	ksort($days);
	$days = array_keys($days);
	$out = '<svg class="chaos-chart" viewBox="0 0 ' . $w . ' ' . $h . '" role="img" aria-label="' . chaos_h($title) . '" '
		. 'style="width:100%;max-width:' . $w . 'px;height:auto;display:block;" xmlns="http://www.w3.org/2000/svg">';
	if (!$days) {
		return $out . '<text x="' . ($w / 2) . '" y="' . ($h / 2) . '" fill="' . $c['muted'] . '" font-size="13" text-anchor="middle">No data in this period.</text></svg>';
	}
	$top = chaos_telemetry_axis_max($max);
	$bottom = $min < 0 ? -chaos_telemetry_axis_max(-$min) : 0.0;
	$x = static function (int $i) use ($days, $w, $l, $r): float {
		return count($days) === 1 ? ($l + ($w - $l - $r) / 2) : $l + $i * ($w - $l - $r) / (count($days) - 1);
	};
	$y = static function (float $v) use ($top, $bottom, $h, $t, $b): float {
		return $t + ($top - $v) * ($h - $t - $b) / ($top - $bottom);
	};
	for ($g = 0; $g <= 4; $g++) {
		$v = $bottom + ($top - $bottom) * $g / 4;
		$gy = round($y($v), 1);
		$out .= '<line x1="' . $l . '" x2="' . ($w - $r) . '" y1="' . $gy . '" y2="' . $gy . '" stroke="' . $c['grid'] . '" stroke-width="1"/>'
			. '<text x="' . ($l - 6) . '" y="' . ($gy + 4) . '" fill="' . $c['muted'] . '" font-size="11" text-anchor="end">' . chaos_h(chaos_telemetry_num($v)) . '</text>';
	}
	$step = max(1, (int)ceil(count($days) / 8));
	foreach ($days as $i => $d) {
		if ($i % $step === 0 || $i === count($days) - 1) {
			$out .= '<text x="' . round($x($i), 1) . '" y="' . ($h - 8) . '" fill="' . $c['muted'] . '" font-size="11" text-anchor="middle">' . gmdate('m-d', $d) . '</text>';
		}
	}
	$index = array_flip($days);
	foreach ($series as $s) {
		$path = '';
		$pen = false;
		$marks = '';
		$lastPoint = null;
		foreach ($s['points'] as $d => $v) {
			if ($v === null) {
				$pen = false;
				continue;
			}
			$px = round($x($index[(int)$d]), 1);
			$py = round($y((float)$v), 1);
			$path .= ($pen ? ' L' : ' M') . $px . ' ' . $py;
			$pen = true;
			$lastPoint = array($px, $py);
			$marks .= '<circle cx="' . $px . '" cy="' . $py . '" r="4" fill="' . $s['color'] . '" stroke="#17141a" stroke-width="2">'
				. '<title>' . chaos_h($s['name'] . ' ' . gmdate('Y-m-d', (int)$d) . ': ' . chaos_telemetry_num($v) . $unit) . '</title></circle>';
		}
		if ($path !== '') {
			$out .= '<path d="' . trim($path) . '" fill="none" stroke="' . $s['color'] . '" stroke-width="2" stroke-linejoin="round" stroke-linecap="round"/>' . $marks;
		}
		if (count($series) > 1 && $lastPoint) {
			$out .= '<text x="' . min($w - $r - 2, $lastPoint[0] - 4) . '" y="' . ($lastPoint[1] - 8) . '" fill="' . $c['ink'] . '" font-size="11" text-anchor="end">' . chaos_h($s['name']) . '</text>';
		}
	}
	return $out . '</svg>';
}

/** Horizontal bars: $rows [[label, value]], one hue. */
function chaos_telemetry_bar_svg(string $title, array $rows, string $unit = ''): string {
	$c = chaos_telemetry_colors();
	$w = 640; $bar = 16; $gap = 8; $l = 200; $r = 64;
	$h = max(40, count($rows) * ($bar + $gap) + 8);
	$out = '<svg class="chaos-chart" viewBox="0 0 ' . $w . ' ' . $h . '" role="img" aria-label="' . chaos_h($title) . '" '
		. 'style="width:100%;max-width:' . $w . 'px;height:auto;display:block;" xmlns="http://www.w3.org/2000/svg">';
	if (!$rows) {
		return $out . '<text x="' . ($w / 2) . '" y="24" fill="' . $c['muted'] . '" font-size="13" text-anchor="middle">No data in this period.</text></svg>';
	}
	$max = 0.0;
	foreach ($rows as $row) {
		$max = max($max, (float)$row[1]);
	}
	$max = $max > 0 ? $max : 1;
	foreach (array_values($rows) as $i => $row) {
		$y = 4 + $i * ($bar + $gap);
		$len = max(2, round(((float)$row[1] / $max) * ($w - $l - $r), 1));
		$label = (string)$row[0];
		$short = mb_strlen($label) > 30 ? mb_substr($label, 0, 29) . '…' : $label;
		$out .= '<text x="' . ($l - 8) . '" y="' . ($y + 12) . '" fill="' . $c['ink'] . '" font-size="12" text-anchor="end">' . chaos_h($short) . '</text>'
			. '<rect x="' . $l . '" y="' . $y . '" width="' . $len . '" height="' . $bar . '" rx="4" fill="' . $c['gold'] . '">'
			. '<title>' . chaos_h($label . ': ' . chaos_telemetry_num($row[1]) . $unit) . '</title></rect>'
			. '<text x="' . ($l + $len + 6) . '" y="' . ($y + 12) . '" fill="' . $c['muted'] . '" font-size="11">' . chaos_h(chaos_telemetry_num($row[1])) . '</text>';
	}
	return $out . '</svg>';
}

/** "m:ss" of seconds. */
function chaos_telemetry_clock($secs): string {
	if ($secs === null || (int)$secs <= 0) {
		return '-';
	}
	$secs = (int)$secs;
	return $secs >= 3600 ? sprintf('%d:%02d:%02d', intdiv($secs, 3600), intdiv($secs % 3600, 60), $secs % 60)
		: sprintf('%d:%02d', intdiv($secs, 60), $secs % 60);
}

} // function_exists guard
