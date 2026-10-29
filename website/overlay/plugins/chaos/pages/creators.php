<?php
/**
 * Creator program ("Programa de Criadores"): who qualifies, what a creator gets, how to apply and the media kit
 * (creators_lib.php, creators/creators_data.json, website/README.md "Creator program"). The creator code itself is
 * the existing creator code system (pages/creator.php). Undecided parts say "To be set" ("A definir").
 * page?plugin=chaos&p=creators[&l=en|pt-BR]
 */
if (!isset($config)) { http_response_code(403); die('Direct access denied.'); }
require_once __DIR__ . '/../creator_lib.php';
require_once __DIR__ . '/../creators_lib.php';
require_once __DIR__ . '/../i18n_lib.php';
$GLOBALS['page_title'] = chaos_t('Creator Program');
$accountId = function_exists('getSession') ? (int)getSession('user_id') : 0;
if (session_status() === PHP_SESSION_ACTIVE && empty($_SESSION['chaos_creators_csrf'])) {
	$_SESSION['chaos_creators_csrf'] = bin2hex(random_bytes(16));
}
$csrf = (string)($_SESSION['chaos_creators_csrf'] ?? '');
$message = '';
$messageOk = true;
$posted = array();
if ($accountId > 0 && ($_SERVER['REQUEST_METHOD'] ?? 'GET') === 'POST' && ($_POST['do'] ?? '') === 'apply') {
	if ($csrf === '' || !hash_equals($csrf, (string)($_POST['csrf'] ?? ''))) {
		[$messageOk, $message, $messageArgs] = array(false, 'The form expired. Please try again.', array());
	} else {
		$posted = $_POST;
		[$messageOk, $message, $messageArgs] = chaos_creators_submit($accountId, $_POST, (string)($_SERVER['REMOTE_ADDR'] ?? '')) + array(2 => array());
		if ($messageOk) { $posted = array(); }
	}
}
$discord = trim((string)($GLOBALS['config']['chaos']['discord_url'] ?? '')); // CHAOS_DISCORD_URL; shown only when set
$crit = chaos_creators_criteria();
$val = static function (string $k) use ($posted): string { return chaos_h((string)($posted[$k] ?? '')); };

$self = 'page?plugin=chaos&p=creators';
$data = chaos_creators_data();
$kit = chaos_creators_kit();
$streamer = chaos_creators_streamer_files();
$guide = chaos_creators_guide(chaos_lang(), $discord);
$state = static function (string $s): string {
	return $s === 'built' ? chaos_t('Available') : ($s === 'proposal' ? chaos_t('Proposed, to be confirmed') : chaos_t('To be set'));
};
?>
<div class="chaos-page" id="chaos-creators">
	<div class="chaos-box">
		<h1 class="chaos-heading"><?= chaos_h(chaos_t('Creator Program')) ?></h1>
		<p class="chaos-muted chaos-lang-row"><?= chaos_lang_link($self) ?></p>
		<p class="chaos-lead"><?= chaos_h(chaos_t('Streamers and video makers are how many players find Cinders of Chaos. This is what we offer them, what is ready and what is still to be set.')) ?></p>

		<h2 class="chaos-subheading"><?= chaos_h(chaos_t('Who qualifies')) ?></h2>
		<p class="chaos-muted"><?= chaos_h(chaos_bi($data['qualify']['intro'])) ?></p>
		<ul id="chaos-creators-qualify">
			<?php foreach ($data['qualify']['items'] as $line): ?><li><?= chaos_h(chaos_bi($line)) ?></li><?php endforeach; ?>
		</ul>

		<h2 class="chaos-subheading"><?= chaos_h(chaos_t('What you get')) ?></h2>
		<table class="chaos-table" id="chaos-creators-benefits">
			<thead><tr><th><?= chaos_h(chaos_t('Benefit')) ?></th><th><?= chaos_h(chaos_t('How it works')) ?></th><th><?= chaos_h(chaos_t('State')) ?></th></tr></thead>
			<tbody>
			<?php foreach ($data['benefits'] as $b): ?>
				<tr id="benefit-<?= chaos_h($b['id']) ?>">
					<td><strong><?= chaos_h(chaos_bi($b['title'])) ?></strong></td>
					<td><?= chaos_h(chaos_bi($b['text'])) ?></td>
					<td><?= chaos_h($state((string)$b['status'])) ?></td>
				</tr>
			<?php endforeach; ?>
			</tbody>
		</table>
		<p class="chaos-muted"><?= chaos_h(chaos_t('Donations are always voluntary.')) ?> <a href="page?plugin=chaos&amp;p=creator"><?= chaos_h(chaos_t('Creator Codes')) ?></a> &middot; <a href="page?plugin=chaos&amp;p=fairplay"><?= chaos_h(chaos_t('What the store never sells')) ?></a></p>

		<h2 class="chaos-subheading"><?= chaos_h(chaos_t('How to apply')) ?></h2>
		<p class="chaos-muted"><?= chaos_h(chaos_bi($data['apply']['intro'])) ?></p>
		<ol id="chaos-creators-apply">
			<?php foreach ($data['apply']['steps'] as $line): ?><li><?= chaos_h(chaos_bi($line)) ?></li><?php endforeach; ?>
		</ol>

		<?php if ($discord !== '' && preg_match('#^https://#', $discord)): ?>
			<p id="chaos-creators-discord"><?= chaos_h(chaos_t('Questions? Talk to the staff on the server Discord:')) ?> <a href="<?= chaos_h($discord) ?>" rel="noopener"><?= chaos_h(chaos_t('Discord')) ?></a></p>
		<?php endif; ?>

		<h3 class="chaos-subheading" id="chaos-creators-form-title"><?= chaos_h(chaos_t('Application form')) ?></h3>
		<?php if ($message !== ''): ?>
			<p class="<?= $messageOk ? 'chaos-gold' : 'chaos-error' ?>" id="chaos-creators-message"><?= chaos_h(chaos_t($message, ...$messageArgs)) ?></p>
		<?php endif; ?>
		<?php if ($accountId <= 0): ?>
			<p class="chaos-muted" id="chaos-creators-login"><?= chaos_h(chaos_t('Log in to send an application. You need an account and a character.')) ?></p>
		<?php else: ?>
			<form method="post" action="<?= chaos_h($self) ?>#chaos-creators-form-title" id="chaos-creators-form">
				<input type="hidden" name="csrf" value="<?= chaos_h($csrf) ?>">
				<p><label><?= chaos_h(chaos_t('Platform')) ?>
					<select name="platform" required>
						<?php foreach (chaos_creators_platforms() as $pl): ?><option value="<?= chaos_h($pl) ?>"<?= ($posted['platform'] ?? '') === $pl ? ' selected' : '' ?>><?= chaos_h(ucfirst($pl)) ?></option><?php endforeach; ?>
					</select></label></p>
				<p><label><?= chaos_h(chaos_t('Channel link (https)')) ?> <input type="url" name="channel_url" maxlength="255" required value="<?= $val('channel_url') ?>"></label></p>
				<p><label><?= chaos_h(chaos_t('Your character')) ?> <input type="text" name="character_name" maxlength="29" required value="<?= $val('character_name') ?>"></label></p>
				<p><label><?= chaos_h(chaos_t('Hours a week of streams or videos of the game')) ?> <input type="number" name="hours_week" min="0" max="168" required value="<?= $val('hours_week') ?>"></label></p>
				<p><label><?= chaos_h(chaos_t('Average live viewers')) ?> <input type="number" name="viewers_avg" min="0" required value="<?= $val('viewers_avg') ?>"></label></p>
				<p><label><?= chaos_h(chaos_t('Followers')) ?> <input type="number" name="followers" min="0" required value="<?= $val('followers') ?>"></label></p>
				<p><label><?= chaos_h(chaos_t('A few words about your channel (optional)')) ?><br><textarea name="message" rows="4" maxlength="1000"><?= $val('message') ?></textarea></label></p>
				<p><label><input type="checkbox" name="agree" value="1" required> <?= chaos_h(chaos_t('I do not trade accounts, items or coins for real money, and I follow the Rules and the Donation Terms.')) ?></label></p>
				<button type="submit" name="do" value="apply" class="chaos-button"><?= chaos_h(chaos_t('Send application')) ?></button>
				<p class="chaos-muted"><?= chaos_h(chaos_t('Criteria: at least %d hours a week, and at least %d average live viewers or %d followers.', $crit['hoursWeek'], $crit['viewers'], $crit['followers'])) ?></p>
			</form>
		<?php endif; ?>

		<h2 class="chaos-subheading"><?= chaos_h(chaos_t('Media kit')) ?></h2>
		<?php if ($kit['zip']): ?>
			<p id="chaos-creators-kit"><a class="chaos-button" href="<?= chaos_h((string)$kit['zip']['path']) ?>"><?= chaos_h(chaos_t('Download the media kit (%s)', chaos_creators_size((int)$kit['zip']['bytes']))) ?></a></p>
			<ul class="chaos-muted">
				<?php foreach ($kit['files'] as $f): ?><li><?= chaos_h((string)$f['name']) ?> <span>(<?= chaos_h(chaos_creators_size((int)$f['bytes'])) ?>)</span></li><?php endforeach; ?>
			</ul>
		<?php else: ?>
			<p class="chaos-muted"><?= chaos_h(chaos_t('The media kit is not available right now.')) ?></p>
		<?php endif; ?>

		<h2 class="chaos-subheading" id="chaos-creators-streamer"><?= chaos_h(chaos_t('Streamer kit')) ?></h2>
		<p class="chaos-muted"><?= chaos_h(chaos_t('Overlays for OBS, Twitch panels, banners and the Discord icon, all original art. They are in the media kit too. File names end with pt-BR or en for the language.')) ?></p>
		<div id="chaos-creators-streamer-files">
		<?php foreach (array('overlays' => 'OBS overlays and scenes', 'banners' => 'Panels and banners', 'discord' => 'Discord icon') as $dir => $label): ?>
			<?php if (!empty($streamer[$dir])): ?>
			<h3 class="chaos-subheading"><?= chaos_h(chaos_t($label)) ?></h3>
			<ul class="chaos-muted">
				<?php foreach ($streamer[$dir] as $name): ?><li><a href="<?= chaos_h(chaos_creators_streamer_url($dir . '/' . $name)) ?>" download><?= chaos_h($name) ?></a></li><?php endforeach; ?>
			</ul>
			<?php endif; ?>
		<?php endforeach; ?>
		</div>
		<p class="chaos-muted" id="chaos-creators-obs"><?= chaos_h(chaos_t('OBS browser source (shows the server name and your code, no cookies, no requests):')) ?> <code><?= chaos_h(chaos_creators_streamer_url('obs-overlay.html')) ?>?code=YOURCODE</code></p>

		<h2 class="chaos-subheading" id="chaos-creators-guide"><?= chaos_h($guide['title']) ?></h2>
		<p class="chaos-muted"><?= chaos_h($guide['intro']) ?></p>
		<?php foreach ($guide['sections'] as $sec): ?>
			<h3 class="chaos-subheading" id="guide-<?= chaos_h($sec['id']) ?>"><?= chaos_h($sec['title']) ?></h3>
			<?php foreach ($sec['blocks'] as [$kind, $val]): ?>
				<?php if ($kind === 'p'): ?><p><?= chaos_h($val) ?></p>
				<?php else: $tag = $kind === 'ol' ? 'ol' : 'ul'; ?>
				<<?= $tag ?>><?php foreach ($val as $line): ?><li><?= $kind === 'check' ? '&#9744; ' : '' ?><?= chaos_h($line) ?></li><?php endforeach; ?></<?= $tag ?>>
				<?php endif; ?>
			<?php endforeach; ?>
		<?php endforeach; ?>

		<h2 class="chaos-subheading"><?= chaos_h(chaos_t('Still to be decided')) ?></h2>
		<ul id="chaos-creators-open">
			<?php foreach ($data['open'] as $q): ?><li id="open-<?= chaos_h($q['id']) ?>"><?= chaos_h(chaos_bi($q['text'])) ?></li><?php endforeach; ?>
		</ul>
		<?php if ($data['updated'] !== ''): ?><p class="chaos-muted" style="font-size:12px;"><?= chaos_h(chaos_t('Last reviewed: %s.', $data['updated'])) ?></p><?php endif; ?>
	</div>
</div>
