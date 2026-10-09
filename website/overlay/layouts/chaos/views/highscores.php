<?php
/**
 * Highscores with the Cinders of Chaos classes.
 *
 * Prepared by highscores.php: $vocGroups, $vocation ('all' or a class id), $type, $page, $highscore,
 * $configVocations, $loadFlags, $loadOutfits. Each class is its own group (config: fromVoc false), and the class
 * filter lists them by line; the Leaderboards page has the class lines together (the Class Ladder).
 */
$h = static function ($v): string { return htmlspecialchars((string)$v, ENT_QUOTES, 'UTF-8'); };
$className = static function (int $id): string {
	return function_exists('chaos_class_name') ? chaos_class_name($id) : (string)vocation_id_to_name($id);
};
$types = array(7 => t('skill.experience'), 8 => t('skill.magic'), 5 => t('skill.shield'), 2 => t('skill.sword'), 1 => t('skill.club'),
	3 => t('skill.axe'), 4 => t('skill.distance'), 6 => t('skill.fishing'), 9 => t('skill.fist'));
$lines = function_exists('chaos_class_lines') ? chaos_class_lines() : array();
?>
<div class="chaos-page">
<div class="chaos-box">
<?php if (!$vocGroups): ?>
	<h1 class="chaos-heading">Highscores</h1>
	<p class="chaos-empty"><?= $h(t('common.nothing')) ?></p>
<?php else:
	$vocGroup = is_array($vocGroups[$vocation] ?? null) ? $vocGroups[$vocation] : ($vocGroups[$vocGroups[$vocation] ?? 'all'] ?? array());
	$rows = $vocGroup[$type] ?? false;
	$rowsPerPage = (int)$highscore['rowsPerPage'];
	$pages = ($rows !== false) ? (int)ceil(min($highscore['rows'] / $rowsPerPage, count($rows) / $rowsPerPage)) : 1;
	?>
	<h1 class="chaos-heading">Highscores <small><?= $h($types[$type] ?? '') ?>, <?= $h($vocation === 'all' ? 'all classes' : $className((int)$vocation)) ?></small></h1>

	<form action="" method="get" class="chaos-tabs">
		<select name="type" aria-label="Skill">
			<?php foreach ($types as $id => $label): ?>
				<option value="<?= (int)$id ?>"<?= $type === $id ? ' selected' : '' ?>><?= $h($label) ?></option>
			<?php endforeach; ?>
		</select>
		<select name="vocation" aria-label="Class">
			<option value="all"<?= $vocation === 'all' ? ' selected' : '' ?>>All classes</option>
			<?php if ($lines): foreach ($lines as $base => $line): ?>
				<optgroup label="<?= $h($line['name']) ?> line">
					<?php foreach (array_merge(array($base), array_keys($line['asc'])) as $id): if (!isset($configVocations[$id])) continue; ?>
						<option value="<?= (int)$id ?>"<?= ($vocation !== 'all' && (int)$vocation === $id) ? ' selected' : '' ?>><?= $h($className($id)) ?></option>
					<?php endforeach; ?>
				</optgroup>
			<?php endforeach; else: foreach ($configVocations as $id => $v): if ((int)$id === 0) continue; ?>
				<option value="<?= (int)$id ?>"<?= ($vocation !== 'all' && (int)$vocation === (int)$id) ? ' selected' : '' ?>><?= $h($v['name']) ?></option>
			<?php endforeach; endif; ?>
		</select>
		<select name="page" aria-label="Page">
			<?php for ($i = 1; $i <= max(1, $pages); $i++): ?>
				<option value="<?= $i ?>"<?= $i === $page ? ' selected' : '' ?>><?= $h(t('highscores.page', ['n' => $i])) ?></option>
			<?php endfor; ?>
		</select>
		<button type="submit" class="chaos-btn"><?= $h(t('common.view')) ?></button>
	</form>

	<table class="chaos-table" id="highscoresTable">
		<thead><tr>
			<th>#</th><th><?= $h(t('common.name')) ?></th><th>Class</th>
			<th class="num"><?= $h($type === 7 ? t('common.level') : $types[$type] ?? '') ?></th>
			<?php if ($type === 7): ?><th class="num"><?= $h(t('common.points')) ?></th><?php endif; ?>
		</tr></thead>
		<tbody>
		<?php if ($rows === false): ?>
			<tr><td colspan="5" class="chaos-empty"><?= $h(t('common.nothing')) ?></td></tr>
		<?php else: foreach ($rows as $i => $r): if (!pageCheck($i, $page, $rowsPerPage)) continue; ?>
			<tr class="<?= $i < 3 ? 'chaos-top chaos-top-' . ($i + 1) : '' ?>">
				<td><?= $i + 1 ?></td>
				<td><a href="characterprofile.php?name=<?= rawurlencode((string)$r['name']) ?>"><?= $h($r['name']) ?></a></td>
				<td><?= $h($className((int)$r['vocation'])) ?></td>
				<td class="num"><?= (int)$r['value'] ?></td>
				<?php if ($type === 7): ?><td class="num"><?= $h(number_format((float)$r['experience'])) ?></td><?php endif; ?>
			</tr>
		<?php endforeach; endif; ?>
		</tbody>
	</table>
	<p class="chaos-note">Staff characters are not listed. Weekly boards, titles and the Class Ladder: <a href="page.php?plugin=chaos&amp;p=leaderboards">Leaderboards</a>.</p>
<?php endif; ?>
</div>
</div>
