<?php
// php website/tests/chaos_escape_patch_test.php : patches/znotex-chaos-escape-output.patch (guild names, ranks, MOTD and
// member names on guilds.php and its views, guild names on topguilds, the character comment on characterprofile.php).
// Every line the patch adds is rendered here with malicious database values: no markup and no script may come out,
// and the onclick of a guild row must stay a plain navigation. php-cli only; ZnoteX itself is not needed.
$failed = 0;
function check(bool $ok, string $what): void {
	global $failed;
	if (!$ok) { $failed++; echo "FAIL: $what\n"; }
}
function url($path = false) { return 'https://site.example.invalid/' . $path; }
function t(string $key, array $vars = array()): string { return $key; }
function convert_number_to_words($n) { return (string)$n; }
function logo_exists($name) { echo 'engine/guildimg/default@logo.gif'; }

$patch = (string)file_get_contents(__DIR__ . '/../patches/znotex-chaos-escape-output.patch');
check($patch !== '', 'patch present');
foreach (array('guilds.php', 'characterprofile.php', 'layouts/default/views/guilds.php', 'layouts/default/views/topguilds.php') as $f) {
	check(strpos($patch, "+++ b/$f") !== false, "patch covers $f");
}

// the helper functions the patch adds to guilds.php
if (preg_match('/^\+function chaos_guild_h.*?^\+function chaos_guild_go.*?^\+\}$/ms', $patch, $m)) {
	eval(preg_replace('/^\+/m', '', $m[0]));
}
check(function_exists('chaos_guild_h') && function_exists('chaos_guild_go'), 'helpers defined');

$evil = '"><script>alert(1)</script><img src=x onerror=alert(1)>\';alert(1);//';
$guild = array('name' => $evil, 'motd' => '<img src=x onerror=alert(2)><script>alert(2)</script>', 'id' => 1, 'total' => 1);
$player = array('name' => $evil, 'rank_name' => '<script>alert(3)</script>', 'guildnick' => '<b onmouseover=alert(4)>x</b>', 'rank_level' => 1, 'id' => 5);
$inv = array('name' => $evil, 'player_id' => 6);
$rank = array('name' => '"><script>alert(5)</script>', 'id' => 2, 'level' => 1);
$wars = array('id' => '1 onmouseover=alert(6)', 'name1' => $evil, 'name2' => '<script>alert(7)</script>');
$profile_znote_data = array('comment' => "<script>alert(8)</script>\nsecond line");
$rankName = '';
$highest_access = 3;
$count = 1;
$url = '';

$rendered = 0;
$out = '';
foreach (preg_split('/\R/', $patch) as $line) {
	if ($line === '' || $line[0] !== '+' || strpos($line, '+++') === 0) {
		continue;
	}
	$code = substr($line, 1);
	$trim = trim($code);
	if ($trim === '' || strpos($trim, '//') === 0 || strpos($trim, 'function ') === 0 || strpos($trim, 'return ') === 0 || $trim === '}') {
		continue;
	}
	if (strpos($trim, '<?php') === false && strpos($trim, '<?=') === false && $trim[0] === '<') {
		continue; // plain HTML without PHP
	}
	ob_start();
	try {
		if (strpos($trim, '<?php') !== false || strpos($trim, '<?=') !== false) {
			eval('?>' . $code . '<?php ');
		} else {
			eval($code);
		}
	} catch (Throwable $e) {
		echo '[error: ' . $e->getMessage() . ']';
	}
	$html = (string)ob_get_clean();
	$rendered++;
	$out .= $html . "\n";
	check(stripos($html, '<script') === false && stripos($html, '<img') === false && stripos($html, '<b ') === false,
		'no markup from the database: ' . $trim);
	check(strpos($html, '[error:') === false, 'renders: ' . $trim . ' ' . $html);
	if (preg_match('/onclick="([^"]*)"/', $html, $oc) && $oc[1] !== 'return false') {
		$js = html_entity_decode($oc[1], ENT_QUOTES, 'UTF-8');
		$ok = strpos($js, 'window.location.href=') === 0 && is_string(json_decode(substr($js, strlen('window.location.href=')), true));
		check($ok, 'onclick is a plain navigation: ' . $js);
	}
	// every attribute stays one attribute: the payload's quote cannot close it (quoted values are left out of the check)
	preg_match_all('/<[^>]*>/', $html, $tags);
	check(!preg_match('/\s(onerror|onmouseover)=/i', preg_replace('/"[^"]*"/', '""', implode(' ', $tags[0]))), 'no injected attribute: ' . $trim);
}
check($rendered >= 20, "rendered the patched lines ($rendered)");
check(strpos($out, '&lt;script&gt;alert(8)&lt;/script&gt;<br/>second line') !== false, 'comment escaped, line breaks kept');
check(strpos($out, 'name=' . rawurlencode($evil)) !== false || strpos($out, htmlspecialchars('name=' . rawurlencode($evil), ENT_QUOTES)) !== false, 'guild link encodes the name');
// a value the site stored already encoded (ZnoteX sanitize()) is not encoded twice
check(chaos_guild_h('Tom&#039;s &amp; co') === 'Tom&#039;s &amp; co', 'no double encoding');
check(chaos_guild_h('a & b <c>') === 'a &amp; b &lt;c&gt;', 'raw value encoded');

echo $failed === 0 ? "chaos_escape_patch_test: OK\n" : "chaos_escape_patch_test: $failed failed\n";
exit($failed === 0 ? 0 : 1);
