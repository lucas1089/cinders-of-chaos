<?php
/**
 * Account creation form: ZnoteX's default register_form view with one more field, the optional referral code
 * (plugins/chaos/referral.php checks it; the game server accepts or rejects it at the first login). Pre-filled from a
 * shared link register.php?ref=CODE. Keep the rest in step with layouts/default/views/register_form.php of ZnoteX.
 */
$chaosRefValue = function_exists('chaos_referral_form_value') ? chaos_referral_form_value() : null;
$chaosRefDays = function_exists('chaos_referral_settings') ? (int)chaos_referral_settings()['entryDays'] : 7;
?>
<form action="" method="post">
	<ul>
		<li><?= t('reg.label_name') ?><br>
			<input type="text" name="username">
		</li>

		<li><?= t('reg.label_pw') ?><br>
			<input type="password" name="password">
		</li>

		<li><?= t('reg.label_pw2') ?><br>
			<input type="password" name="password_again">
		</li>

		<li><?= t('login.email') ?>:<br>
			<input type="text" name="email">
		</li>

		<?php if ($chaosRefValue !== null) { ?>
		<li>Referral code (optional):<br>
			<input type="text" name="referral_code" maxlength="12" placeholder="XXXX-XXXX" value="<?= chaos_h($chaosRefValue) ?>"><br>
			<small class="chaos-muted">From a friend who plays: you get a welcome gift (potions and a title), your friend gets
			cosmetic rewards as you level. One code per account; it can also be entered in game in the first <?= $chaosRefDays ?> days.</small>
		</li>
		<?php } ?>

		<li><?= t('reg.label_country') ?><br>
			<select name="flag">
				<option value=""><?= t('reg.please_choose') ?></option>
				<?php
				foreach(array('pl', 'se', 'br', 'us', 'gb', ) as $c)
					echo '<option value="' . $c . '">' . $config['countries'][$c] . '</option>';

					echo '<option value="">----------</option>';
					foreach($config['countries'] as $code => $c)
						echo '<option value="' . $code . '">' . $c . '</option>';
				?>
			</select>
		</li>

		<?php
		if ($config['use_captcha']) {
			?>
			<li>
				 <div class="g-recaptcha" data-sitekey="<?php echo $config['captcha_site_key']; ?>"></div>
			</li>
			<?php
		}
		?>

		<li><h2><?= t('reg.rules_title') ?></h2>
			<p><?= t('reg.rule_golden') ?></p>
			<p><?= t('reg.rule_pwned') ?></p>
			<p><?= t('reg.rule_no_cheating', ['link' => '<a href="https://en.wikipedia.org/wiki/Cheating_in_video_games" target="_blank">' . t('reg.cheating_word') . '</a>']) ?></p>
			<p><?= t('reg.rule_no_botting', ['link' => '<a href="https://en.wikipedia.org/wiki/Video_game_bot" target="_blank">' . t('reg.botting_word') . '</a>']) ?></p>
			<p><?= t('reg.rule_staff_power') ?></p>
		</li>

		<li><?= t('reg.rules_agree') ?><br>
			<select name="selected">
			  <option value="0"><?= t('reg.agree_umh') ?></option>
			  <option value="1"><?= t('reg.agree_yes') ?></option>
			  <option value="2"><?= t('reg.agree_no') ?></option>
			</select>
		</li>
		<?php
			/* Form file */
			Token::create();
		?>
		<li>
			<input type="submit" value="<?= t('reg.submit') ?>">
		</li>
	</ul>
</form>
