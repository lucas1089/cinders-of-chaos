<?php
/**
 * Staff: balance telemetry (page?plugin=chaos&p=telemetry). Admin panel accounts with a character of group 5 or
 * higher; everyone else gets "not found". Read only. Charts are server-drawn SVG (telemetry_lib.php): no script, no CDN.
 *
 *  - GET band / class / from / to (YYYY-MM-DD, UTC days; the last 14 days by default, at most 400): the filters.
 *  - Sections: online, hunting (experience and gold per hour, per day, class and band), bosses, deaths, spell casts,
 *    gold faucets and sinks, Chaos Coins per store category. Data: the game server's chaos_telemetry_* tables
 *    (server/README.md "Balance telemetry") and chaos_shop_purchases.
 */
if (!isset($config)) { http_response_code(403); die('Direct access denied.'); }
require_once __DIR__ . '/../telemetry_lib.php';

$accountId = function_exists('getSession') ? (int)getSession('user_id') : 0;
if (!chaos_telemetry_is_admin($config, $accountId)) {
	http_response_code(404);
	$GLOBALS['page_title'] = 'Not found';
	echo '<div class="chaos-page"><div class="chaos-box"><h1 class="chaos-heading">Not found</h1><p>This page does not exist.</p></div></div>';
	return;
}
$GLOBALS['page_title'] = 'Balance Telemetry';
if (!chaos_table_exists('chaos_telemetry_hunt')) {
	echo '<div class="chaos-page"><div class="chaos-box"><h1 class="chaos-heading">Balance Telemetry</h1><p>No telemetry yet: the game server creates its tables at its next start (server/sql/chaos_telemetry.sql).</p></div></div>';
	return;
}

$f = chaos_telemetry_filters($_GET, isset($chaosTelemetryNow) ? (int)$chaosTelemetryNow : null);
$bands = chaos_telemetry_bands();
$classes = chaos_telemetry_class_options();
$col = chaos_telemetry_colors();
$num = 'chaos_telemetry_num';

$huntDays = chaos_telemetry_hunt_days($f);
$huntClasses = chaos_telemetry_hunt_classes($f);
$huntBands = chaos_telemetry_hunt_bands($f);
$online = chaos_telemetry_online_days($f);
$bosses = chaos_telemetry_bosses($f);
[$deathAreas, $deathPairs] = chaos_telemetry_deaths($f);
$casts = chaos_telemetry_casts($f);
[$ecoDays, $ecoSources] = chaos_telemetry_economy($f);
$store = chaos_table_exists('chaos_shop_purchases') ? chaos_telemetry_store($f) : array();

$pick = static function (array $days, string $key): array {
	$out = array();
	foreach ($days as $d => $r) {
		$out[$d] = $r[$key];
	}
	return $out;
};
$scope = ($f['band'] !== '' ? 'level ' . $f['band'] : 'all levels') . ', ' . ($classes[$f['class']] ?? 'All classes')
	. ', ' . gmdate('Y-m-d', $f['from']) . ' to ' . gmdate('Y-m-d', $f['to']);
?>
<div class="chaos-page" id="chaos-telemetry">
	<div class="chaos-box">
		<h1 class="chaos-heading">Balance Telemetry</h1>
		<p class="chaos-lead">Hourly aggregates from the game server: no names, no character ids. Days are UTC. Rates are shown only where at least <?= (int)CHAOS_TELEMETRY_MIN_PLAYERS ?> characters are behind them. Hover a point or bar for its value; each chart has a table below.</p>

		<form method="get" action="page" class="chaos-filter" style="margin:10px 0;display:flex;flex-wrap:wrap;gap:10px;align-items:end;">
			<input type="hidden" name="plugin" value="chaos">
			<input type="hidden" name="p" value="telemetry">
			<label>Band
				<select name="band">
					<option value="">all</option>
					<?php foreach ($bands as $b): ?>
						<option value="<?= chaos_h($b) ?>"<?= $f['band'] === $b ? ' selected' : '' ?>><?= chaos_h($b) ?></option>
					<?php endforeach; ?>
				</select>
			</label>
			<label>Class
				<select name="class">
					<?php foreach ($classes as $key => $label): ?>
						<option value="<?= chaos_h($key) ?>"<?= $f['class'] === $key ? ' selected' : '' ?>><?= chaos_h($label) ?></option>
					<?php endforeach; ?>
				</select>
			</label>
			<label>From <input type="date" name="from" value="<?= chaos_h(gmdate('Y-m-d', $f['from'])) ?>"></label>
			<label>To <input type="date" name="to" value="<?= chaos_h(gmdate('Y-m-d', $f['to'])) ?>"></label>
			<button type="submit" class="chaos-button">Show</button>
		</form>
		<p class="chaos-muted" id="chaos-telemetry-scope"><?= chaos_h($scope) ?></p>
	</div>

	<div class="chaos-box" id="telemetry-online">
		<h2 class="chaos-heading">Online</h2>
		<p class="chaos-muted">Average characters online per day (staff left out); the table has the peak.</p>
		<?= chaos_telemetry_line_svg('Average online per day', array(array('name' => 'Online', 'color' => $col['gold'], 'points' => $pick($online, 'avg')))) ?>
		<details><summary>Table</summary>
			<table class="chaos-table"><thead><tr><th>Day</th><th class="num">Average</th><th class="num">Peak</th></tr></thead><tbody>
			<?php foreach ($online as $d => $r): ?>
				<tr><td><?= gmdate('Y-m-d', $d) ?></td><td class="num"><?= chaos_h($r['avg']) ?></td><td class="num"><?= (int)$r['max'] ?></td></tr>
			<?php endforeach; ?>
			</tbody></table>
		</details>
	</div>

	<div class="chaos-box" id="telemetry-hunting">
		<h2 class="chaos-heading">Hunting</h2>
		<p class="chaos-muted">Experience and gold per hour of hunting (samples with experience or kills; gold = loot value at NPC prices minus supplies used).</p>
		<h3 class="chaos-heading" style="font-size:14px;">Experience per hour</h3>
		<?= chaos_telemetry_line_svg('Experience per hour', array(array('name' => 'XP/h', 'color' => $col['gold'], 'points' => $pick($huntDays, 'xph'))), ' xp/h') ?>
		<h3 class="chaos-heading" style="font-size:14px;">Gold per hour</h3>
		<?= chaos_telemetry_line_svg('Gold per hour', array(array('name' => 'Gold/h', 'color' => $col['gold'], 'points' => $pick($huntDays, 'gph'))), ' gold/h') ?>
		<details><summary>Table by day</summary>
			<table class="chaos-table"><thead><tr><th>Day</th><th class="num">XP/h</th><th class="num">Gold/h</th><th class="num">Hours</th><th class="num">Character-hours</th></tr></thead><tbody>
			<?php foreach ($huntDays as $d => $r): ?>
				<tr><td><?= gmdate('Y-m-d', $d) ?></td><td class="num"><?= chaos_h($num($r['xph'])) ?></td><td class="num"><?= chaos_h($num($r['gph'])) ?></td><td class="num"><?= chaos_h($r['hours']) ?></td><td class="num"><?= (int)$r['players'] ?></td></tr>
			<?php endforeach; ?>
			</tbody></table>
		</details>
		<table class="chaos-table" id="telemetry-hunt-classes"><thead><tr><th>Class</th><th class="num">XP/h</th><th class="num">Gold/h</th><th class="num">Hours</th><th class="num">Kills</th></tr></thead><tbody>
		<?php if (!$huntClasses): ?><tr><td colspan="5" class="chaos-muted">No hunting in this period.</td></tr><?php endif; ?>
		<?php foreach ($huntClasses as $voc => $r): ?>
			<tr><td><?= chaos_h(chaos_class_name((int)$voc)) ?></td><td class="num"><?= chaos_h($num($r['xph'])) ?></td><td class="num"><?= chaos_h($num($r['gph'])) ?></td><td class="num"><?= chaos_h($r['hours']) ?></td><td class="num"><?= chaos_h($num($r['kills'])) ?></td></tr>
		<?php endforeach; ?>
		</tbody></table>
		<table class="chaos-table" id="telemetry-hunt-bands"><thead><tr><th>Band</th><th class="num">XP/h</th><th class="num">Gold/h</th><th class="num">Hours</th></tr></thead><tbody>
		<?php foreach ($huntBands as $band => $r): ?>
			<tr><td><?= chaos_h($band) ?></td><td class="num"><?= chaos_h($num($r['xph'])) ?></td><td class="num"><?= chaos_h($num($r['gph'])) ?></td><td class="num"><?= chaos_h($r['hours']) ?></td></tr>
		<?php endforeach; ?>
		</tbody></table>
	</div>

	<div class="chaos-box" id="telemetry-bosses">
		<h2 class="chaos-heading">Bosses</h2>
		<p class="chaos-muted">Kills and kill times by party size. World, Ascended, guild and Omen bosses: the competitive records' time; map bosses: from the first player hit. Band and class filters do not apply.</p>
		<table class="chaos-table"><thead><tr><th>Boss</th><th class="num">Party</th><th class="num">Kills</th><th class="num">Average</th><th class="num">Best</th><th class="num">Slowest</th></tr></thead><tbody>
		<?php if (!$bosses): ?><tr><td colspan="6" class="chaos-muted">No boss kills in this period.</td></tr><?php endif; ?>
		<?php foreach ($bosses as $r): ?>
			<tr><td><?= chaos_h($r['boss']) ?></td><td class="num"><?= (int)$r['party'] ?></td><td class="num"><?= (int)$r['kills'] ?></td>
				<td class="num"><?= chaos_h(chaos_telemetry_clock((int)$r['timed'] > 0 ? intdiv((int)$r['total'], (int)$r['timed']) : null)) ?></td>
				<td class="num"><?= chaos_h(chaos_telemetry_clock($r['best'] === null ? null : (int)$r['best'])) ?></td>
				<td class="num"><?= chaos_h(chaos_telemetry_clock((int)$r['worst'])) ?></td></tr>
		<?php endforeach; ?>
		</tbody></table>
	</div>

	<div class="chaos-box" id="telemetry-deaths">
		<h2 class="chaos-heading">Deaths</h2>
		<p class="chaos-muted">Deaths per area (instance, hunting place, or the nearest town). The class filter does not apply.</p>
		<?= chaos_telemetry_bar_svg('Deaths per area', array_map(static function ($r) { return array($r['area'], (int)$r['n']); }, $deathAreas), ' deaths') ?>
		<details><summary>Table by area and killer</summary>
			<table class="chaos-table"><thead><tr><th>Area</th><th>Killer</th><th class="num">Deaths</th></tr></thead><tbody>
			<?php foreach ($deathPairs as $r): ?>
				<tr><td><?= chaos_h($r['area']) ?></td><td><?= chaos_h($r['killer']) ?></td><td class="num"><?= (int)$r['n'] ?></td></tr>
			<?php endforeach; ?>
			</tbody></table>
		</details>
	</div>

	<div class="chaos-box" id="telemetry-casts">
		<h2 class="chaos-heading">Spell casts</h2>
		<p class="chaos-muted">The most cast spells (and runes) per class. The band filter does not apply.</p>
		<?= chaos_telemetry_bar_svg('Spell casts', array_map(static function ($r) { return array($r['spell'] . ' (' . chaos_class_name((int)$r['voc']) . ')', (int)$r['n']); }, $casts), ' casts') ?>
		<details><summary>Table</summary>
			<table class="chaos-table"><thead><tr><th>Spell</th><th>Class</th><th class="num">Casts</th></tr></thead><tbody>
			<?php foreach ($casts as $r): ?>
				<tr><td><?= chaos_h($r['spell']) ?></td><td><?= chaos_h(chaos_class_name((int)$r['voc'])) ?></td><td class="num"><?= (int)$r['n'] ?></td></tr>
			<?php endforeach; ?>
			</tbody></table>
		</details>
	</div>

	<div class="chaos-box" id="telemetry-economy">
		<h2 class="chaos-heading">Gold: faucets and sinks</h2>
		<p class="chaos-muted">Faucets: loot value, Loot Bag and Auto Seller sales. Sinks: supplies used (runes, potions, ammunition at NPC prices), respecs. The class filter does not apply.</p>
		<p class="chaos-muted"><span style="color:<?= $col['gold'] ?>;">&#9632;</span> Faucets &nbsp; <span style="color:<?= $col['ember'] ?>;">&#9632;</span> Sinks</p>
		<?= chaos_telemetry_line_svg('Gold faucets and sinks per day', array(
			array('name' => 'Faucets', 'color' => $col['gold'], 'points' => $pick($ecoDays, 'faucet')),
			array('name' => 'Sinks', 'color' => $col['ember'], 'points' => $pick($ecoDays, 'sink'))), ' gold') ?>
		<table class="chaos-table"><thead><tr><th>Flow</th><th>Source</th><th class="num">Gold</th><th class="num">Events</th></tr></thead><tbody>
		<?php if (!$ecoSources): ?><tr><td colspan="4" class="chaos-muted">No gold flow in this period.</td></tr><?php endif; ?>
		<?php foreach ($ecoSources as $r): ?>
			<tr><td><?= chaos_h($r['flow']) ?></td><td><?= chaos_h($r['source']) ?></td><td class="num"><?= chaos_h($num((int)$r['g'])) ?></td><td class="num"><?= (int)$r['n'] ?></td></tr>
		<?php endforeach; ?>
		</tbody></table>
	</div>

	<div class="chaos-box" id="telemetry-store">
		<h2 class="chaos-heading">Store: Chaos Coins per category</h2>
		<p class="chaos-muted">From the store's purchase log. The band filter uses the buyer's level at the purchase; the class filter does not apply.</p>
		<?= chaos_telemetry_bar_svg('Chaos Coins per store category', array_map(static function ($r) { return array($r['category'], (int)$r['coins']); }, $store), ' coins') ?>
		<details><summary>Table</summary>
			<table class="chaos-table"><thead><tr><th>Category</th><th class="num">Coins</th><th class="num">Purchases</th></tr></thead><tbody>
			<?php foreach ($store as $r): ?>
				<tr><td><?= chaos_h($r['category']) ?></td><td class="num"><?= (int)$r['coins'] ?></td><td class="num"><?= (int)$r['n'] ?></td></tr>
			<?php endforeach; ?>
			</tbody></table>
		</details>
	</div>
</div>
