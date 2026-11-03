<?php
// php website/tests/chaos_character_page_test.php : the character page (O392; plugins/chaos/character_lib.php,
// pages/character.php) over an in-memory SQLite database with the game's tables: gear without the backpack, the build
// code of class, tree, Paragon and gear (read back by the build code decoder), achievements with the names of the
// game's achievements_data.lua, the chosen title, the level milestones (O378), best runs, season results, and the
// privacy rules: tester bots and hidden characters have no page, the Memorial choice hides runs and seasons, a
// Hardcore fall is named only with its yes, names are escaped. No ZnoteX, no network.
$repo = realpath(__DIR__ . '/../..');
$config = array('chaos' => array('server_data' => $repo . '/server/data'));
$GLOBALS['config'] = $config;
require $repo . '/website/overlay/plugins/chaos/lib.php';
require $repo . '/website/overlay/plugins/chaos/character_lib.php';
function znote_plugin_asset(string $plugin, string $path): string { return 'plugins/' . $plugin . '/assets/' . $path; }

$failed = 0;
$checks = 0;
$fails = array(); // printed at the end: the page sets response codes, which output before would block
function check(bool $ok, string $what): void {
	global $failed, $checks, $fails;
	$checks++;
	if (!$ok) { $failed++; $fails[] = "FAIL: $what"; }
}

$pdo = new PDO('sqlite::memory:');
$pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
final class FakeZnoteDb {
	public PDO $pdo;
	public function __construct(PDO $pdo) { $this->pdo = $pdo; }
	private function run(string $sql, array $p): PDOStatement {
		$st = $this->pdo->prepare($sql);
		foreach (array_values($p) as $i => $v) {
			$st->bindValue($i + 1, $v, is_int($v) ? PDO::PARAM_INT : PDO::PARAM_STR);
		}
		$st->execute();
		return $st;
	}
	public function fetchOne(string $sql, array $p = array()) {
		if (strpos($sql, 'information_schema') !== false) {
			$n = $this->pdo->prepare("SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = ?");
			$n->execute(array($p[0]));
			return array('n' => (int)$n->fetchColumn());
		}
		$r = $this->run($sql, $p)->fetch(PDO::FETCH_ASSOC);
		return $r === false ? false : $r;
	}
	public function fetchAll(string $sql, array $p = array()) { return $this->run($sql, $p)->fetchAll(PDO::FETCH_ASSOC); }
	public function execute(string $sql, array $p = array()) { $this->run($sql, $p); return true; }
}
$DB = new FakeZnoteDb($pdo);
function db() { return $GLOBALS['DB']; }

foreach (array(
	'CREATE TABLE players (id INT PRIMARY KEY, name TEXT, level INT, vocation INT, sex INT, looktype INT, lookhead INT, lookbody INT, looklegs INT, lookfeet INT, lookaddons INT, account_id INT DEFAULT 1, email TEXT DEFAULT \'secret@mail\')',
	'CREATE TABLE player_storage (player_id INT, key INT, value INT)',
	'CREATE TABLE znote_players (player_id INT, hide_char INT)',
	'CREATE TABLE player_items (player_id INT, pid INT, sid INT, itemtype INT, count INT)',
	'CREATE TABLE chaos_passive_tree (player_id INT, preset INT, name TEXT, nodes TEXT)',
	'CREATE TABLE chaos_paragon (player_id INT, stat TEXT, points INT)',
	'CREATE TABLE chaos_achievements (player_id INT, achievement TEXT, unlocked_at INT)',
	'CREATE TABLE chaos_achievement_stats (player_id INT, stat TEXT, value INT)',
	'CREATE TABLE chaos_player_titles (player_id INT, title_key TEXT, updated INT)',
	'CREATE TABLE chaos_memorial_optin (player_id INT, records INT, fallen INT, asked INT, updated_at INT)',
	'CREATE TABLE chaos_tower_players (player_id INT, season INT, points INT, best_floor INT, best_time INT, claimed_mask INT, last_attempt INT)',
	'CREATE TABLE chaos_arena_ratings (player_id INT, mode TEXT, rating INT, wins INT, losses INT, draws INT, best INT, updated_at INT)',
	'CREATE TABLE chaos_leaderboard_titles (week INT, board TEXT, rank INT, player_id INT, value INT, title TEXT, rewarded INT, awarded_at INT)',
	'CREATE TABLE chaos_season_players (player_id INT, account_id INT, season INT, joined_at INT, migrated_at INT)',
	'CREATE TABLE chaos_season_modes (player_id INT, season INT, ssf INT, hc INT, chosen_at INT, fallen_at INT, fallen_level INT, fallen_cause TEXT, reset_at INT)',
	'CREATE TABLE chaos_tower_season_rewards (season INT, player_id INT, place INT, best_floor INT, best_time INT, chest TEXT, rewarded INT, awarded_at INT, delivered_at INT)',
) as $sql) {
	$pdo->exec($sql);
}
$t = 1795000000;
$pdo->exec("INSERT INTO players (id, name, level, vocation, sex, looktype, lookhead, lookbody, looklegs, lookfeet, lookaddons) VALUES
	(1, 'Vexa', 1210, 7, 0, 130, 1, 2, 3, 4, 3), (2, 'Bot One', 900, 7, 1, 130, 0, 0, 0, 0, 0), (3, 'Hidden Hal', 50, 4, 1, 130, 0, 0, 0, 0, 0),
	(4, '<b>Bold</b>', 20, 23, 1, 130, 0, 0, 0, 0, 0), (5, 'Quiet Quin', 300, 11, 1, 130, 0, 0, 0, 0, 0)");
$pdo->exec('INSERT INTO player_storage VALUES (2, 7102900, 1)');
$pdo->exec('INSERT INTO znote_players VALUES (1, 0), (3, 1)');
// worn: head, backpack (left out), armour, a ring; something inside the backpack (pid 64) is never read
$pdo->exec('INSERT INTO player_items VALUES (1, 1, 101, 2466, 1), (1, 3, 102, 1988, 1), (1, 4, 103, 8209, 1), (1, 9, 104, 2357, 1), (1, 64, 105, 2160, 50)');
$pdo->exec("INSERT INTO chaos_passive_tree VALUES (1, 2, 'Other', '2,3'), (1, 1, 'Main', '2,3,4,104,542,666|666:2,3:9')");
$pdo->exec("INSERT INTO chaos_paragon VALUES (1, 'damage', 20), (1, 'health', 5), (1, 'chiMastery', 3), (1, 'speed', 0)");
$pdo->exec("INSERT INTO chaos_achievements VALUES (1, 'level_800', " . ($t - 500) . "), (1, 'level_900', " . ($t - 100) . "), (1, 'level_1000', " . ($t - 50) . "), (1, 'retired_one', $t)");
$pdo->exec("INSERT INTO chaos_achievement_stats VALUES (1, 'rift_tier', 14)");
$pdo->exec("INSERT INTO chaos_player_titles VALUES (1, 'achievement:the unbroken', 0)");
$pdo->exec("INSERT INTO chaos_tower_players VALUES (1, 1, 10, 31, 754, 0, 0), (1, 2, 10, 44, 1000, 0, 0), (5, 1, 1, 12, 300, 0, 0)");
$pdo->exec("INSERT INTO chaos_arena_ratings VALUES (1, '1v1', 1180, 12, 4, 0, 1210, 0), (1, '2v2', 1000, 0, 0, 0, 1000, 0)");
$pdo->exec("INSERT INTO chaos_leaderboard_titles VALUES (20261123, 'rift', 2, 1, 14, 'Riftwalker', 1, 0), (20261130, 'rift', 1, 1, 15, 'Riftwalker', 1, 0)");
$pdo->exec("INSERT INTO chaos_season_players VALUES (1, 1, 1, 0, 0), (5, 1, 1, 0, 0)");
$pdo->exec("INSERT INTO chaos_season_modes VALUES (1, 1, 0, 1, 0, $t, 640, 'killed by a lich', 0), (5, 1, 1, 1, 0, $t, 300, 'killed by a rat', 0)");
$pdo->exec("INSERT INTO chaos_tower_season_rewards VALUES (1, 1, 2, 31, 754, 'silver', 1, 0, 0)");
$pdo->exec("INSERT INTO chaos_memorial_optin VALUES (1, 1, 0, 1, 0), (5, 0, 1, 1, 0)");

// ---------------------------------------------------------------- the parts
check(chaos_character_find('Bot One') === null, 'a tester bot has no page');
check(chaos_character_find('Hidden Hal') === null, 'a character hidden on its account has no page');
check(chaos_character_find('Nobody') === null && chaos_character_find('') === null, 'unknown and empty names');
$vexa = chaos_character_find('Vexa');
check($vexa !== null && (int)$vexa['id'] === 1 && !isset($vexa['email']) && !isset($vexa['account_id']), 'found, without account data');
$gear = chaos_character_gear(1);
check(array_column($gear, 'slot') === array(1, 4, 9), 'gear: worn slots only, no backpack, no backpack content');
$tree = chaos_character_tree(1, 7);
check($tree['line'] === 2 && $tree['nodes'] === array(2, 3, 4, 104, 542, 666), 'the active preset (the lowest), Deadeye = Ranger line');
check($tree['masteries'] === array(666 => 2, 3 => 9), 'mastery choices of nodes in the preset');
check($tree['paragon'] === array('damage' => 20, 'health' => 5), 'Paragon: code keys only, no zero');
$data = chaos_character_page($vexa);
$card = chaos_buildcode_decode((string)$data['code'])['card'] ?? null;
check($card !== null && $card['class'] === 'deadeye' && $card['level'] === 1210 && count($card['gear']) === 3, 'the build code: class, level, gear');
check($card !== null && $card['tree_info']['nodes'] === array(2, 3, 4, 104, 542, 666) && $card['tree_info']['paragon'] === array('damage' => 20, 'health' => 5)
	&& $card['tree_info']['masteries'] === array(3 => 9, 666 => 2) && $card['tree_info']['line'] === 2, 'the build code: the tree as the server would write it');
check(empty($card['spells']), 'no spells (the rotation is in the client)');
$a = $data['achievements'];
check($a['count'] === 3 && $a['points'] === 100, 'achievements counted, a retired one left out: ' . $a['count'] . '/' . $a['points']);
check($a['recent'][0]['name'] === 'The Thousandth Step', 'newest first');
check($a['chosen'] === 'the Unbroken', 'the chosen title');
check(in_array('Emberborn', $a['titles'], true), 'titles of the achievements');
check(count($a['milestones']) === 15 && $a['milestones'][0]['level'] === 800 && $a['milestones'][0]['at'] > 0
	&& $a['milestones'][3]['at'] === 0 && $a['milestones'][14]['level'] === 2200, 'the 15 level milestones, reached or not');
check($data['runs']['tower'] === array('floor' => 44, 'time' => 1000) && $data['runs']['rift'] === 14, 'best tower floor of every season, rift tier');
check(count($data['runs']['arena']) === 1 && $data['runs']['arena'][0]['best'] === 1210, 'arena: modes played only');
check($data['runs']['podiums'] === array(array('board' => 'rift', 'places' => 2, 'best' => 1)), 'weekly podiums');
check(count($data['seasons']) === 1 && $data['seasons'][0]['name'] === 'Season of Ash' && $data['seasons'][0]['mode'] === 'Hardcore'
	&& $data['seasons'][0]['place'] === 2 && $data['seasons'][0]['fallen'] === null, 'season: name, mode, tower place; the fall without its yes is not named');
$quin = chaos_character_page(chaos_character_find('Quiet Quin'));
check($quin['runs'] === null && $quin['seasons'] === null, 'records off: no runs, no seasons');

// ---------------------------------------------------------------- the page
function render_char(array $get): array {
	global $config;
	$_GET = $get;
	$GLOBALS['page_title'] = '';
	$GLOBALS['page_description'] = '';
	http_response_code(200);
	ob_start();
	include __DIR__ . '/../overlay/plugins/chaos/pages/character.php';
	return array((string)ob_get_clean(), (int)http_response_code(), $GLOBALS['page_title'], $GLOBALS['page_description']);
}
list($html, $status, $title, $desc) = render_char(array('name' => 'Vexa'));
check($status === 200 && $title === 'Vexa', 'title');
check($desc === 'Vexa, level 1210 Deadeye: 3 achievements, gear and best runs.', 'description: ' . $desc);
check(strpos($html, 'Aetherbound Plate') !== false && strpos($html, 'Ring') !== false, 'gear on the page');
check(strpos($html, 'p=build&amp;c=CC1-') !== false, 'the build link');
check(strpos($html, 'floor 44 in 16:40') !== false && strpos($html, 'tier 14') !== false && strpos($html, '2 podiums, best place 1') !== false, 'best runs');
check(strpos($html, 'Infinity Tower place 2') !== false && strpos($html, 'killed by a lich') === false, 'season row without the fall');
check(strpos($html, 'Tempered in the Dark') !== false && strpos($html, 'reached') !== false, 'milestones');
check(strpos($html, 'secret@mail') === false, 'no account data printed');
check(strpos($html, 'p=character&amp;name=Vexa') !== false && strpos($html, 'characterprofile?name=Vexa') !== false, 'share link and the profile link');
list($html, $status) = render_char(array('name' => 'Quiet Quin'));
check(strpos($html, 'keeps their records private') !== false && strpos($html, 'killed by a rat') === false && strpos($html, 'floor 12') === false, 'records off on the page');
list($html, $status, $title) = render_char(array('name' => '<b>Bold</b>'));
check($title === '<b>Bold</b>' && strpos($html, '&lt;b&gt;Bold&lt;/b&gt;') !== false && strpos($html, '<b>Bold</b>') === false, 'names escaped');
check(strpos($html, 'No achievements yet') !== false && strpos($html, 'This code has no gear') !== false, 'an empty character');
list($html, $status) = render_char(array('name' => 'Bot One'));
check($status === 404 && strpos($html, 'No character with this name') !== false && strpos($html, '900') === false, 'a tester bot: 404 like an unknown name');
list($html, $status) = render_char(array('name' => "x' OR 1=1 --"));
check($status === 404, 'a hostile name: just not found');
list($html, $status) = render_char(array());
check($status === 200 && strpos($html, 'name="name"') !== false && strpos($html, 'chaos-error') === false, 'no name: the form');
check(strpos((string)file_get_contents(__DIR__ . '/../overlay/plugins/chaos/character_lib.php'), "\u{2014}") === false, 'no dashes');

echo $fails ? implode("\n", $fails) . "\n" : '';
echo $failed === 0 ? "chaos_character_page_test: OK ($checks checks)\n" : "chaos_character_page_test: $failed of $checks failed\n";
exit($failed === 0 ? 0 : 1);
