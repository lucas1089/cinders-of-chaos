<?php
/**
 * Mentors on the website (read only). The game server writes the tables (server/data/scripts/chaos/mentor.lua,
 * server/sql/chaos_mentor.sql); this file only reads them:
 *   chaos_mentors       one row per mentor character: the card (language / region, hours, note), accepting, public
 *                       (shown here), graduates
 *   chaos_mentor_links  the links; the active ones count the places taken
 * Only mentors that opted in (public = 1), still mentor (active = 1), are no staff character and not banned are listed.
 * Used by page?plugin=chaos&p=mentors. Every query is a prepared statement; every value printed goes through chaos_h().
 */

if (!function_exists('chaos_mentor_state')) {

/** The numbers of server/data/scripts/chaos/mentor_config.lua the page explains (kept in step by the test). */
function chaos_mentor_rules(): array {
	return array('max' => 3, 'apprentice_level' => 79, 'account_days' => 60, 'graduation' => 200, 'exp' => 10, 'damage' => 5,
		'mentor_level' => 150, 'mentor_hours' => 100, 'mentor_days' => 30);
}

/**
 * Everything the page shows:
 * ['ok' => bool (tables there), 'mentors' => [[name, level, class, lang, hours, note, graduates, active, free, accepting]],
 *  'totals' => ['mentors' => n, 'graduates' => n, 'apprentices' => n]]
 */
function chaos_mentor_state(int $limit = 100): array {
	$out = array('ok' => false, 'mentors' => array(), 'totals' => array('mentors' => 0, 'graduates' => 0, 'apprentices' => 0));
	if (!chaos_table_exists('chaos_mentors') || !chaos_table_exists('chaos_mentor_links')) {
		return $out;
	}
	$out['ok'] = true;
	$rules = chaos_mentor_rules();
	$banned = chaos_table_exists('account_bans')
		? ' AND NOT EXISTS (SELECT 1 FROM `account_bans` `b` WHERE `b`.`account_id` = `p`.`account_id`)' : '';
	$rows = chaos_rows('SELECT `p`.`name`, `p`.`level`, `p`.`vocation`, `m`.`lang`, `m`.`hours`, `m`.`note`, `m`.`graduates`, '
		. '`m`.`accepting`, (SELECT COUNT(*) FROM `chaos_mentor_links` `l` WHERE `l`.`mentor_id` = `m`.`player_id` AND `l`.`status` = \'active\') AS `active` '
		. 'FROM `chaos_mentors` `m` JOIN `players` `p` ON `p`.`id` = `m`.`player_id` '
		. 'WHERE `m`.`active` = 1 AND `m`.`public` = 1 AND `p`.`group_id` < 2' . $banned . chaos_antibot_hold_sql() . chaos_tester_sql()
		. ' ORDER BY `m`.`graduates` DESC, `p`.`name` ASC LIMIT ?;', array(max(1, min(500, $limit))));
	foreach ($rows as $r) {
		$active = (int)$r['active'];
		$out['mentors'][] = array(
			'name' => (string)$r['name'],
			'level' => (int)$r['level'],
			'class' => chaos_class_name((int)$r['vocation']),
			'lang' => (string)$r['lang'],
			'hours' => (string)$r['hours'],
			'note' => (string)$r['note'],
			'graduates' => (int)$r['graduates'],
			'active' => $active,
			'free' => max(0, $rules['max'] - $active),
			'accepting' => (int)$r['accepting'] === 1,
		);
	}
	$t = db()->fetchOne('SELECT COUNT(*) AS `n`, COALESCE(SUM(`graduates`), 0) AS `g` FROM `chaos_mentors` WHERE `active` = 1;', array());
	// graduates of every mentor, retired ones too
	$all = db()->fetchOne('SELECT COALESCE(SUM(`graduates`), 0) AS `g` FROM `chaos_mentors`;', array());
	$a = db()->fetchOne('SELECT COUNT(*) AS `n` FROM `chaos_mentor_links` WHERE `status` = \'active\';', array());
	$out['totals'] = array(
		'mentors' => is_array($t) ? (int)$t['n'] : 0,
		'graduates' => is_array($all) ? (int)$all['g'] : 0,
		'apprentices' => is_array($a) ? (int)$a['n'] : 0,
	);
	return $out;
}

/** The mentor table (empty string when there is nothing to show). */
function chaos_mentor_table_html(array $state): string {
	if (empty($state['ok']) || !$state['mentors']) {
		return '';
	}
	$h = '<table class="chaos-table chaos-mentors"><thead><tr><th>Mentor</th><th>Class</th><th>Language / region</th>'
		. '<th>Hours</th><th class="num">Graduates</th><th class="num">Places</th></tr></thead><tbody>';
	foreach ($state['mentors'] as $m) {
		$places = $m['accepting'] ? ($m['free'] > 0 ? $m['free'] . ' free' : 'full') : 'not taking';
		$h .= '<tr><td><a href="characterprofile?name=' . rawurlencode($m['name']) . '">' . chaos_h($m['name']) . '</a>'
			. ' <span class="chaos-muted">Lv ' . (int)$m['level'] . '</span>'
			. ($m['note'] !== '' ? '<br><span class="chaos-muted">' . chaos_h($m['note']) . '</span>' : '') . '</td>'
			. '<td>' . chaos_h($m['class']) . '</td><td>' . chaos_h($m['lang']) . '</td><td>' . chaos_h($m['hours']) . '</td>'
			. '<td class="num chaos-gold">' . (int)$m['graduates'] . '</td><td class="num">' . chaos_h($places) . '</td></tr>';
	}
	return $h . '</tbody></table>';
}

}
