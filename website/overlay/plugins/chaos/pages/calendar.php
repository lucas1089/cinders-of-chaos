<?php
/**
 * The calendar: betas, wipe, launch, seasons, patch notes and the wipe rules (calendar_lib.php,
 * calendar/calendar_data.json, website/README.md "Calendar"). What is undecided shows as "To be set" ("A definir").
 * page?plugin=chaos&p=calendar[&l=en|pt-BR]
 */
if (!isset($config)) { http_response_code(403); die('Direct access denied.'); }
require_once __DIR__ . '/../calendar_lib.php';
require_once __DIR__ . '/../i18n_lib.php';
$GLOBALS['page_title'] = chaos_t('Calendar');

$self = 'page?plugin=chaos&p=calendar';
$data = chaos_calendar_data();
$now = isset($GLOBALS['chaos_calendar_now']) ? (int)$GLOBALS['chaos_calendar_now'] : time(); // the tests set the clock
$view = chaos_calendar_view($data, $now);
$lang = chaos_lang();
$tbd = chaos_t('To be set');
$statusLabel = static function (string $status): string {
	return $status === 'confirmed' ? chaos_t('Confirmed') : ($status === 'proposal' ? chaos_t('Proposed, to be confirmed') : chaos_t('Planned'));
};
?>
<div class="chaos-page" id="chaos-calendar">
	<div class="chaos-box">
		<h1 class="chaos-heading"><?= chaos_h(chaos_t('Calendar')) ?></h1>
		<p class="chaos-muted chaos-lang-row"><?= chaos_lang_link($self) ?></p>
		<p class="chaos-lead"><?= chaos_h(chaos_t('The open betas, the launch, the seasons and the patch notes in one place. Times are server time (UTC-3). Dates marked as a proposal are not final, and what is not decided yet says "To be set".')) ?></p>

		<div class="chaos-box" id="chaos-calendar-optional">
			<h2 class="chaos-subheading"><?= chaos_h(chaos_t('Your character is permanent, seasons are optional, the legacy is cosmetic')) ?></h2>
			<p><?= chaos_h(chaos_t('A season never wipes or resets a standard character. If you do not join, you lose nothing.')) ?></p>
			<p><?= chaos_h(chaos_t('What a season gives: a new character on its own ladder, a season modifier, season uniques while it runs and a track of rewards.')) ?></p>
			<p><?= chaos_h(chaos_t('What carries over: the track rewards go to your account for good (outfits, mounts and titles). When the season ends, its character becomes a standard character and keeps its level, skills, items and passive tree.')) ?></p>
		</div>

		<?php if ($view['next'] !== null): $n = $view['next']; ?>
			<div class="chaos-season" id="chaos-calendar-next">
				<div class="chaos-season__state"><?= chaos_h(chaos_t('Next on the calendar')) ?></div>
				<h2 class="chaos-season__name"><?= chaos_h(chaos_bi($n['title'])) ?> <span class="chaos-muted"><?= chaos_h(chaos_calendar_fmt((string)$n['start'], $lang, !empty($n['hasTime']))) ?></span></h2>
				<p class="chaos-muted"><?= chaos_h($statusLabel((string)$n['status'])) ?></p>
			</div>
		<?php endif; ?>

		<h2 class="chaos-subheading"><?= chaos_h(chaos_t('Betas and launch')) ?></h2>
		<table class="chaos-table" id="chaos-calendar-events">
			<thead><tr><th><?= chaos_h(chaos_t('When')) ?></th><th><?= chaos_h(chaos_t('What')) ?></th><th><?= chaos_h(chaos_t('State')) ?></th></tr></thead>
			<tbody>
			<?php foreach ($data['events'] as $e): ?>
				<tr id="event-<?= chaos_h($e['id']) ?>">
					<td><?= chaos_h(chaos_calendar_fmt((string)$e['start'], $lang, !empty($e['hasTime']))) ?><?php if (!empty($e['end'])): ?><br><span class="chaos-muted"><?= chaos_h(chaos_t('until %s', chaos_calendar_fmt((string)$e['end'], $lang))) ?></span><?php endif; ?></td>
					<td><strong><?= chaos_h(chaos_bi($e['title'])) ?></strong><br><span class="chaos-muted"><?= chaos_h(chaos_bi($e['text'] ?? '')) ?></span>
						<?php if (!empty($e['patchnoteReady'])): ?><br><a href="page?plugin=chaos&amp;p=patchnotes&amp;id=<?= rawurlencode((string)$e['patchnote']) ?>"><?= chaos_h(chaos_t('Patch note')) ?></a><?php endif; ?></td>
					<td><?= chaos_h($statusLabel((string)$e['status'])) ?></td>
				</tr>
			<?php endforeach; ?>
			</tbody>
		</table>

		<h2 class="chaos-subheading"><?= chaos_h(chaos_t('Seasons')) ?></h2>
		<?php foreach ($view['seasons'] as $row): $s = $row['season']; ?>
			<div class="chaos-season" id="season-<?= (int)$s['id'] ?>">
				<h3 class="chaos-season__name"><?= chaos_h($s['name']) ?> <span class="chaos-muted"><?= chaos_h($s['tag']) ?></span></h3>
				<dl class="chaos-facts">
					<dt><?= chaos_h(chaos_t('Length')) ?></dt><dd><?= chaos_h(chaos_t('%d weeks (%d days)', (int)$s['lengthWeeks'], (int)$s['lengthDays'])) ?></dd>
					<dt><?= chaos_h(chaos_t('Starts')) ?></dt>
					<dd><?php if ($row['known']): ?><?= chaos_h(chaos_calendar_fmt((string)$s['start'], $lang)) ?><?php else: ?><span class="chaos-gold"><?= chaos_h($tbd) ?></span> <span class="chaos-muted"><?= chaos_h(chaos_t('Proposal: %s', chaos_calendar_fmt((string)$s['proposed']['start'], $lang))) ?></span><?php endif; ?></dd>
					<dt><?= chaos_h(chaos_t('Ends')) ?></dt>
					<dd><?php if ($row['known']): ?><?= chaos_h(chaos_calendar_fmt((string)$s['finish'], $lang)) ?><?php else: ?><span class="chaos-gold"><?= chaos_h($tbd) ?></span> <span class="chaos-muted"><?= chaos_h(chaos_t('Proposal: %s', chaos_calendar_fmt((string)$s['proposed']['finish'], $lang))) ?></span><?php endif; ?></dd>
					<dt><?= chaos_h(chaos_t('State')) ?></dt>
					<dd><?= chaos_h($row['state'] === 'running' ? chaos_t('Running now') : ($row['state'] === 'coming' ? chaos_t('Coming soon') : ($row['state'] === 'ended' ? chaos_t('Ended') : $tbd))) ?></dd>
				</dl>
			</div>
		<?php endforeach; ?>
		<?php if (!empty($data['nextSeason'])): $ns = $data['nextSeason']; ?>
			<p id="chaos-calendar-next-season"><strong><?= chaos_h(chaos_bi($ns['title'])) ?>:</strong> <?= chaos_h(chaos_t('starts %s', chaos_calendar_fmt((string)$ns['start'], $lang))) ?> (<?= chaos_h($statusLabel((string)$ns['status'])) ?>). <span class="chaos-muted"><?= chaos_h(chaos_bi($ns['text'])) ?></span></p>
		<?php else: ?>
			<p id="chaos-calendar-next-season"><strong><?= chaos_h(chaos_t('The season after that')) ?>:</strong> <span class="chaos-gold"><?= chaos_h($tbd) ?></span> <span class="chaos-muted"><?= chaos_h(chaos_t('Dates, name and modifier are not decided.')) ?></span></p>
		<?php endif; ?>

		<h2 class="chaos-subheading"><?= chaos_h(chaos_t('Other cycles')) ?></h2>
		<table class="chaos-table" id="chaos-calendar-cycles">
			<thead><tr><th><?= chaos_h(chaos_t('Cycle')) ?></th><th><?= chaos_h(chaos_t('Now or next')) ?></th></tr></thead>
			<tbody>
			<?php foreach ($view['cycles'] as $row): $c = $row['cycle']; ?>
				<tr id="cycle-<?= chaos_h($c['id']) ?>">
					<td><strong><?= chaos_h(chaos_bi($c['title'])) ?></strong><br><span class="chaos-muted"><?= chaos_h(chaos_bi($c['text'] ?? '')) ?></span></td>
					<td><?php if ($row['show'] !== null): $w = $row['show']['window']; ?>
						<?= chaos_h(chaos_t($row['show']['running'] ? 'Season %d, running: until %s' : 'Season %d, starts %s', (int)$w['n'], chaos_calendar_fmt((string)($row['show']['running'] ? $w['end'] : $w['start']), $lang))) ?>
					<?php else: ?><span class="chaos-muted"><?= chaos_h(chaos_t('Every Monday at 06:00')) ?></span><?php endif; ?></td>
				</tr>
			<?php endforeach; ?>
			</tbody>
		</table>

		<h2 class="chaos-subheading"><?= chaos_h(chaos_bi($data['patchnotes']['title'] ?? '')) ?></h2>
		<?php $pn = $data['patchnotes']; if (!empty($pn['weekdayName'])): ?>
			<p id="chaos-calendar-patchday"><strong><?= chaos_h(chaos_t('Patch note day: %s', chaos_bi($pn['weekdayName']))) ?></strong><?php if (!empty($pn['firstRegular'])): ?> <span class="chaos-muted"><?= chaos_h(chaos_t('The first regular one: %s.', chaos_calendar_fmt((string)$pn['firstRegular'] . 'T00:00:00-03:00', $lang, false))) ?></span><?php endif; ?></p>
		<?php endif; ?>
		<p id="chaos-calendar-patchnotes"><?= chaos_h(chaos_bi($data['patchnotes']['text'] ?? '')) ?> <a href="page?plugin=chaos&amp;p=patchnotes"><?= chaos_h(chaos_t('Read the patch notes')) ?></a></p>

		<h2 class="chaos-subheading"><?= chaos_h(chaos_t('What stays and what resets')) ?></h2>
		<?php foreach ($data['wipe'] as $key => $w): ?>
			<div class="chaos-box" id="wipe-<?= chaos_h($key) ?>">
				<h3 class="chaos-season__name"><?= chaos_h(chaos_bi($w['title'])) ?></h3>
				<p class="chaos-muted"><?= chaos_h(chaos_bi($w['status'])) ?></p>
				<?php if (!empty($w['reset'])): ?>
				<h4><?= chaos_h(chaos_t('Resets')) ?></h4>
				<ul><?php foreach ($w['reset'] as $line): ?><li><?= chaos_h(chaos_bi($line)) ?></li><?php endforeach; ?></ul>
				<?php endif; ?>
				<h4><?= chaos_h(chaos_t('Stays')) ?></h4>
				<ul><?php foreach ($w['kept'] as $line): ?><li><?= chaos_h(chaos_bi($line)) ?></li><?php endforeach; ?></ul>
				<?php if (!empty($w['gift'])): ?>
				<h4><?= chaos_h(chaos_t('Thank-you')) ?></h4>
				<ul><?php foreach ($w['gift'] as $line): ?><li><?= chaos_h(chaos_bi($line)) ?></li><?php endforeach; ?></ul>
				<?php endif; ?>
				<p class="chaos-muted"><?= chaos_h(chaos_bi($w['why'])) ?></p>
			</div>
		<?php endforeach; ?>

		<h2 class="chaos-subheading"><?= chaos_h(chaos_t('Still to be decided')) ?></h2>
		<ul id="chaos-calendar-open">
			<?php foreach ($data['open'] as $q): ?><li id="open-<?= chaos_h($q['id']) ?>"><?= chaos_h(chaos_bi($q['text'])) ?></li><?php endforeach; ?>
		</ul>
		<p><a href="page?plugin=chaos&amp;p=seasons"><?= chaos_h(chaos_t('The running season and its ladder')) ?></a></p>
	</div>
</div>
