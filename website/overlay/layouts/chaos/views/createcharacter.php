<?php
/**
 * Create character, as class cards.
 *
 * Prepared by createcharacter.php: $formState ('success' | 'errors' | 'form'), $errors.
 * The classes offered are $config['available_vocations']: the four base classes, plus the Monk, Necromancer and
 * Templar for an account that unlocked them (plugins/chaos/plugin.php narrows the list before createcharacter.php
 * validates the form, so a forged form for a locked class is refused by the server too).
 */
$h = static function ($v): string { return htmlspecialchars((string)$v, ENT_QUOTES, 'UTF-8'); };
$lines = function_exists('chaos_class_lines') ? chaos_class_lines() : array();
$offered = array_map('intval', (array)($config['available_vocations'] ?? array()));
$towns = (array)($config['available_towns'] ?? array());
$posted = (int)($_POST['selected_vocation'] ?? ($offered[0] ?? 0));
// character slots (plugins/chaos/plugin.php sets max_characters per account)
$slotLimit = (int)($config['max_characters'] ?? 0);
$slotUsed = (isset($session_user_id) && function_exists('user_character_list_count')) ? (int)user_character_list_count($session_user_id) : -1;
$hidden = 0;
foreach ($lines as $base => $line) {
	if ($line['lock'] !== '' && !in_array($base, $offered, true)) {
		$hidden++;
	}
}
?>
<div class="chaos-page">
<div class="chaos-box">
	<h1 class="chaos-heading"><?= $h(t('createchar.title')) ?></h1>

	<?php if ($formState === 'success'): ?>
		<div class="chaos-msg chaos-msg--ok"><?= $h(t('createchar.success')) ?> Log in with the client: your character wakes up on the tutorial island.</div>
		<p><a class="chaos-btn" href="myaccount.php">My account</a></p>
	<?php else: ?>
		<?php if ($formState === 'errors'): ?>
			<div class="chaos-msg chaos-msg--error"><?= output_errors($errors) ?></div>
		<?php endif; ?>

		<?php if ($slotUsed >= 0 && $slotLimit > 0): ?>
			<p class="chaos-note">Character slots: <?= (int)$slotUsed ?> of <?= (int)$slotLimit ?> used.<?php if ($slotUsed >= $slotLimit): ?> More slots are sold in the game store (Storage &amp; Slots &gt; Character Slot).<?php endif; ?></p>
		<?php endif; ?>
		<form action="" method="post" class="chaos-create">
			<div class="chaos-field">
				<label for="cc-name"><?= $h(t('createchar.name')) ?></label>
				<input id="cc-name" type="text" name="name" maxlength="<?= (int)($config['maxL'] ?? 20) ?>" value="<?= $h($_POST['name'] ?? '') ?>" required>
			</div>

			<div>
				<div class="chaos-field"><label><?= $h(t('createchar.vocation')) ?></label></div>
				<div class="chaos-classes" role="radiogroup">
					<?php foreach ($offered as $i => $id):
						$line = $lines[$id] ?? array('name' => vocation_id_to_name($id), 'icon' => '', 'plays' => '', 'asc' => array(), 'lock' => '');
						$img = ($line['icon'] !== '' && function_exists('znote_plugin_asset')) ? znote_plugin_asset('chaos', 'img/class-' . $line['icon'] . '.png') : ''; ?>
						<label class="chaos-pick">
							<input type="radio" name="selected_vocation" value="<?= (int)$id ?>"<?= ($posted === $id || ($i === 0 && !in_array($posted, $offered, true))) ? ' checked' : '' ?>>
							<div class="chaos-class<?= $line['lock'] !== '' ? ' is-unlocked' : '' ?>">
								<?php if ($img !== ''): ?><img src="<?= $h($img) ?>" alt=""><?php endif; ?>
								<div class="chaos-class__name"><?= $h($line['name']) ?></div>
								<div class="chaos-class__plays"><?= $h($line['plays']) ?></div>
								<?php if ($line['asc']): ?>
									<ul class="chaos-class__asc">
										<?php foreach ($line['asc'] as $asc): ?><li><strong><?= $h($asc[0]) ?></strong><?= $h($asc[1]) ?></li><?php endforeach; ?>
									</ul>
								<?php endif; ?>
							</div>
						</label>
					<?php endforeach; ?>
				</div>
				<p class="chaos-note">You ascend at level 100, in the game (<code>!ascend</code>).<?php if ($hidden > 0): ?> More classes (the Monk, the Necromancer and the Templar) are unlocked for your whole account in the game store.<?php endif; ?></p>
			</div>

			<div class="chaos-field">
				<label for="cc-sex"><?= $h(t('createchar.gender')) ?></label>
				<select id="cc-sex" name="selected_gender">
					<option value="1"><?= $h(t('createchar.male')) ?></option>
					<option value="0"<?= (($_POST['selected_gender'] ?? '') === '0') ? ' selected' : '' ?>><?= $h(t('createchar.female')) ?></option>
				</select>
			</div>

			<?php if (count($towns) > 1): ?>
				<div class="chaos-field">
					<label for="cc-town">Home town</label>
					<select id="cc-town" name="selected_town">
						<?php foreach ($towns as $tid): ?>
							<option value="<?= (int)$tid ?>"<?= ((int)($_POST['selected_town'] ?? 0) === (int)$tid) ? ' selected' : '' ?>><?= $h(town_id_to_name($tid)) ?></option>
						<?php endforeach; ?>
					</select>
					<span class="chaos-note">Every new character starts on the tutorial island; its temple is where you go when you leave it.</span>
				</div>
			<?php else: ?>
				<input type="hidden" name="selected_town" value="<?= (int)reset($towns) ?>">
			<?php endif; ?>

			<?php Token::create(); ?>
			<div><button type="submit" class="chaos-btn"><?= $h(t('createchar.title')) ?></button></div>
		</form>
	<?php endif; ?>
</div>
</div>
