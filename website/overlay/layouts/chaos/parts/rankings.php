<?php
/**
 * Right sidebar: top characters (with their class badge and class name) and guilds. Replaces the parent's part,
 * which draws stock job pictures. Read-only, cached like the parent's.
 */
$chaosH = static function ($v): string { return htmlspecialchars((string)$v, ENT_QUOTES, 'UTF-8'); };
$chaosIgnoreGroup = (int)($config['highscore']['ignoreGroupId'] ?? 2);

$chaosTopCache = new Cache('engine/cache/chaosTopPlayers');
if ($chaosTopCache->hasExpired()) {
	$chaosTop = db()->fetchAll('SELECT `name`, `level`, `vocation` FROM `players` WHERE `group_id` < ? AND `deletion` = 0 ORDER BY `experience` DESC, `id` ASC LIMIT 10;', [$chaosIgnoreGroup]);
	$chaosTopCache->setContent($chaosTop);
	$chaosTopCache->save();
} else {
	$chaosTop = $chaosTopCache->load();
}
$chaosGuildCache = new Cache('engine/cache/chaosTopGuilds');
if ($chaosGuildCache->hasExpired()) {
	$chaosGuilds = db()->fetchAll('SELECT `g`.`name` AS `name`, COUNT(`gm`.`player_id`) AS `members` FROM `guilds` `g` LEFT JOIN `guild_membership` `gm` ON `gm`.`guild_id` = `g`.`id` GROUP BY `g`.`id` ORDER BY `members` DESC, `g`.`name` ASC LIMIT 10;');
	$chaosGuildCache->setContent($chaosGuilds);
	$chaosGuildCache->save();
} else {
	$chaosGuilds = $chaosGuildCache->load();
}
$chaosBadge = static function (int $vocation): string {
	if (!function_exists('chaos_base_of') || !function_exists('znote_plugin_asset')) {
		return theme_asset('img/favicon.png');
	}
	$base = chaos_base_of($vocation);
	$lines = chaos_class_lines();
	return $base !== null ? znote_plugin_asset('chaos', 'img/class-' . $lines[$base]['icon'] . '.png') : theme_asset('img/favicon.png');
};
$chaosName = static function (int $vocation): string {
	return function_exists('chaos_class_name') ? chaos_class_name($vocation) : (string)vocation_id_to_name($vocation);
};
$chaosRank = static fn (int $i): string => 'sh-rank-' . ($i <= 3 ? $i : 'n');
?>
<div class="sh-panel">
	<div class="sh-panel-title"><i class="fa fa-trophy"></i> <?= t('void.rank.players') ?></div>
	<ul class="sh-player-list" style="padding:8px 12px 2px;">
		<?php if ($chaosTop): foreach ($chaosTop as $i => $p): $rank = $i + 1; ?>
			<li>
				<span class="sh-rank-num <?= $chaosRank($rank) ?>"><?= $rank ?></span>
				<div class="sh-rank-avatar"><img src="<?= $chaosH($chaosBadge((int)$p['vocation'])) ?>" alt="" loading="lazy" title="<?= $chaosH($chaosName((int)$p['vocation'])) ?>"></div>
				<span class="sh-rank-name" title="<?= $chaosH($chaosName((int)$p['vocation'])) ?>"><a href="characterprofile?name=<?= rawurlencode((string)$p['name']) ?>"><?= $chaosH($p['name']) ?></a></span>
				<span class="sh-rank-level"><?= (int)$p['level'] ?></span>
			</li>
		<?php endforeach; else: ?>
			<li><span class="sh-rank-name"><?= t('common.nothing') ?></span></li>
		<?php endif; ?>
	</ul>
	<a href="page?plugin=chaos&amp;p=leaderboards" class="sh-see-more"><i class="fa fa-list"></i> Leaderboards</a>
</div>

<div class="sh-panel">
	<div class="sh-panel-title"><i class="fa fa-shield"></i> <?= t('void.rank.guilds') ?></div>
	<div style="padding:8px 12px 2px;">
		<?php if ($chaosGuilds): foreach ($chaosGuilds as $i => $g): $rank = $i + 1; ?>
			<div class="sh-guild-item">
				<span class="sh-rank-num <?= $chaosRank($rank) ?>"><?= $rank ?></span>
				<div class="sh-guild-info">
					<div class="sh-guild-name"><a href="guilds?name=<?= rawurlencode((string)$g['name']) ?>"><?= $chaosH($g['name']) ?></a></div>
					<div class="sh-guild-sub"><?= t('void.rank.members') ?></div>
				</div>
				<div class="sh-guild-pts"><?= (int)$g['members'] ?></div>
			</div>
		<?php endforeach; else: ?>
			<div class="sh-guild-item"><span class="sh-guild-name"><?= t('common.nothing') ?></span></div>
		<?php endif; ?>
	</div>
	<a href="topguilds" class="sh-see-more"><i class="fa fa-list"></i> <?= t('void.rank.view_full') ?></a>
</div>
