<?php
/**
 * Chaos Coins: the coin packs and bonuses of the server's shop_coins_config.lua (the game server credits them; this
 * page only shows them). page.php?plugin=chaos&p=coins
 * No payment provider is connected: buying happens through the hook chaos_coin_order_paid (lib.php) once one is.
 */
if (!isset($config)) { http_response_code(403); die('Direct access denied.'); }
$GLOBALS['page_title'] = 'Chaos Coins';

$packs = chaos_coin_packs();
$settings = chaos_coin_settings();
$accountId = function_exists('getSession') ? (int)getSession('user_id') : 0;
$state = chaos_coin_account_state($accountId);
$money = static function (float $v) use ($settings): string {
	return number_format($v, 2) . ' ' . $settings['currency'];
};
?>
<div class="chaos-page">
	<div class="chaos-box">
		<h1 class="chaos-heading">Chaos Coins</h1>
		<p class="chaos-lead">Chaos Coins buy cosmetics, convenience and services in the in-game Store (Economy &gt; Store). Coins belong to your account, so every character can spend them.</p>
		<?php if ($settings['first_bonus_pct'] > 0): ?>
			<p>Your first coin pack comes with <span class="chaos-gold">+<?= (int)$settings['first_bonus_pct'] ?>% extra coins</span><?php if ($accountId > 0 && !$state['first']): ?> <span class="chaos-muted">(already used on your account)</span><?php endif; ?>.</p>
		<?php endif; ?>
		<?php if (!$packs): ?>
			<p class="chaos-empty">No coin packs are set up yet.</p>
		<?php else: ?>
			<table class="chaos-table">
				<thead><tr><th>Pack</th><th class="num">Coins</th><th class="num">Bonus</th><th class="num">You get</th><th class="num">Price</th></tr></thead>
				<tbody>
				<?php foreach ($packs as $p): ?>
					<tr>
						<td><?= chaos_h($p['name']) ?><?php if ($p['once']): ?> <span class="chaos-muted">(once per account<?= ($accountId > 0 && $p['starter'] && !$state['starter']) ? ', already bought' : '' ?>)</span><?php endif; ?></td>
						<td class="num"><?= (int)$p['coins'] ?></td>
						<td class="num"><?= $p['bonus_pct'] > 0 ? '+' . (int)$p['bonus_pct'] . '%' : '' ?><?= $p['bonus_coins'] > 0 ? '+' . (int)$p['bonus_coins'] : '' ?></td>
						<td class="num chaos-gold"><?= (int)$p['total'] ?></td>
						<td class="num"><?= chaos_h($money($p['price'])) ?></td>
					</tr>
				<?php endforeach; ?>
				</tbody>
			</table>
		<?php endif; ?>
		<p class="chaos-muted">Payments are not open yet. When they are, coins reach your account within a minute of the payment.</p>
	</div>
</div>
