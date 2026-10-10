<?php
/**
 * Register page heading (ZnoteX's default register_header view). register.php renders it after its own checks and
 * before it creates the account, so a refused referral code (plugins/chaos/referral.php) is added to the errors here.
 */
if (function_exists('chaos_referral_add_error')) {
	chaos_referral_add_error();
}
?>
<h1><?= t('reg.heading') ?></h1>
