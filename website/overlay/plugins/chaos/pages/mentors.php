<?php
/**
 * Mentors: the mentors who chose to be shown (their card, graduates, free places) and the totals, read from the game
 * server's chaos_mentor* tables (mentor_lib.php). page?plugin=chaos&p=mentors
 */
if (!isset($config)) { http_response_code(403); die('Direct access denied.'); }
require_once dirname(__DIR__) . '/mentor_lib.php';
$GLOBALS['page_title'] = 'Mentors';

$state = chaos_mentor_state(100);
$rules = chaos_mentor_rules();
$table = chaos_mentor_table_html($state);
?>
<div class="chaos-page">
	<div class="chaos-box">
		<h1 class="chaos-heading">Mentors</h1>
		<p class="chaos-lead">New to the Cinders? A mentor hunts with you while you learn. Characters up to level <?= (int)$rules['apprentice_level'] ?> on an account up to <?= (int)$rules['account_days'] ?> days old can pick a mentor in the game (Social &gt; Mentors). In a party with your mentor you get +<?= (int)$rules['exp'] ?>% experience and take <?= (int)$rules['damage'] ?>% less damage from monsters, as long as your mentor is not far above the monsters you hunt. You graduate at level <?= (int)$rules['graduation'] ?>, and both of you get a reward.</p>
		<p class="chaos-note">Veterans (a level <?= (int)$rules['mentor_level'] ?> character, <?= (int)$rules['mentor_hours'] ?> hours of play, an account at least <?= (int)$rules['mentor_days'] ?> days old) can mentor up to <?= (int)$rules['max'] ?> apprentices and earn Mentor Marks for titles, cosmetics and supplies, never power.</p>
		<?php if (!empty($state['ok'])): ?>
			<p class="chaos-mentors__totals"><span class="chaos-gold"><?= (int)$state['totals']['mentors'] ?></span> mentors, <span class="chaos-gold"><?= (int)$state['totals']['apprentices'] ?></span> apprentices learning now, <span class="chaos-gold"><?= (int)$state['totals']['graduates'] ?></span> graduates.</p>
		<?php endif; ?>
		<?php if ($table === ''): ?>
			<p class="chaos-empty">No mentor is listed yet.</p>
		<?php else: ?>
			<?= $table ?>
		<?php endif; ?>
	</div>
</div>
