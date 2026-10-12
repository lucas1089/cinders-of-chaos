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
			/* Cinders of Chaos: on when CHAOS_RECAPTCHA_SITE_KEY and CHAOS_RECAPTCHA_SECRET are set; ZnoteX's form never
			   loaded Google's script, so the widget did not show */
			?>
			<li>
				 <script src="https://www.google.com/recaptcha/api.js" async defer></script>
				 <div class="g-recaptcha" data-sitekey="<?= htmlspecialchars((string)$config['captcha_site_key'], ENT_QUOTES, 'UTF-8') ?>"></div>
			</li>
			<?php
		}
		?>

		<li><h2><?= t('reg.rules_title') ?></h2>
			<?php /* Cinders of Chaos: a summary of our Rules page (page.php?p=rules) instead of ZnoteX's sample rules */ ?>
			<p>Play fair and be respectful: no bugs used on purpose, no bots, macros or modified clients, no harassment, no selling of accounts, characters or items for real money.</p>
			<p>Read the full <a href="page.php?p=rules" target="_blank">rules of Cinders of Chaos</a>. Staff decide every case, from a warning to a permanent ban.</p>
		</li>

		<li><?= t('reg.rules_agree') ?><br>
			<select name="selected">
			  <option value="0">Choose...</option>
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
