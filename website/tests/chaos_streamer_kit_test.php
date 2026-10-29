<?php
// php website/tests/chaos_streamer_kit_test.php : the streamer / partner kit (website/tools/gen_streamer_kit.py, README "Streamer kit"):
// the committed art (sizes, transparency, circle-safe Discord icon), the OBS browser source page (static, no cookies, no requests),
// the partner guide (both languages, its numbers against creator_codes_config.lua, the Discord link from CHAOS_DISCORD_URL), the
// creators page showing it, the media kit manifest listing it, and where the files live. php-cli only (GD is used when present).
require __DIR__ . '/chaos_pages_helper.php';
$plugin = CHAOS_TEST_REPO . '/website/overlay/plugins/chaos';
require $plugin . '/lib.php';
require $plugin . '/i18n_lib.php';
require $plugin . '/creator_lib.php';
require $plugin . '/creators_lib.php';

$failed = 0;
$checks = 0;
function check(bool $ok, string $what): void {
	global $failed, $checks;
	$checks++;
	if (!$ok) { $failed++; echo "FAIL: $what\n"; }
}

$dir = $plugin . '/assets/streamer';
$sizes = array(
	'overlays/webcam-frame.png' => array(1920, 1080), 'overlays/bottom-bar.pt-BR.png' => array(1920, 1080), 'overlays/bottom-bar.en.png' => array(1920, 1080),
	'overlays/starting-soon.pt-BR.png' => array(1920, 1080), 'overlays/starting-soon.en.png' => array(1920, 1080),
	'overlays/be-right-back.pt-BR.png' => array(1920, 1080), 'overlays/be-right-back.en.png' => array(1920, 1080),
	'overlays/ending.pt-BR.png' => array(1920, 1080), 'overlays/ending.en.png' => array(1920, 1080),
	'banners/twitch-panel-sobre.pt-BR.png' => array(320, 100), 'banners/twitch-panel-codigo.pt-BR.png' => array(320, 100),
	'banners/twitch-panel-discord.pt-BR.png' => array(320, 100), 'banners/twitch-panel-regras.pt-BR.png' => array(320, 100),
	'banners/twitch-panel-about.en.png' => array(320, 100), 'banners/twitch-panel-code.en.png' => array(320, 100),
	'banners/twitch-panel-discord.en.png' => array(320, 100), 'banners/twitch-panel-rules.en.png' => array(320, 100),
	'banners/social-1500x500.pt-BR.png' => array(1500, 500), 'banners/social-1500x500.en.png' => array(1500, 500),
	'banners/offline.pt-BR.png' => array(1920, 1080), 'banners/offline.en.png' => array(1920, 1080),
	'banners/youtube-thumbnail-template-1280x720.png' => array(1280, 720), 'discord/icon-circle-512.png' => array(512, 512),
);
foreach ($sizes as $rel => $wh) {
	$info = is_file("$dir/$rel") ? getimagesize("$dir/$rel") : false;
	check($info !== false && $info[0] === $wh[0] && $info[1] === $wh[1] && $info[2] === IMAGETYPE_PNG, "$rel is a PNG of {$wh[0]}x{$wh[1]}");
}
// every committed file is one of the listed ones, the OBS page or slots.json (--check of the generator says the same)
$found = array();
foreach (new RecursiveIteratorIterator(new RecursiveDirectoryIterator($dir, FilesystemIterator::SKIP_DOTS)) as $f) {
	$found[] = str_replace('\\', '/', substr((string)$f, strlen($dir) + 1));
}
sort($found);
$want = array_merge(array_keys($sizes), array('obs-overlay.html', 'obs-overlay.js', 'slots.json'));
sort($want);
check($found === $want, 'the streamer folder holds exactly the kit files: ' . implode(',', array_diff($found, $want)) . implode(',', array_diff($want, $found)));

// transparent overlays and the circle-safe icon (GD); alpha is 0 (opaque) to 127 (clear), read through the palette when there is one
function chaos_alpha($im, int $x, int $y): int {
	$c = imagecolorat($im, $x, $y);
	return imageistruecolor($im) ? (($c >> 24) & 0x7F) : (int)imagecolorsforindex($im, $c)['alpha'];
}
function chaos_sum($im, int $x, int $y): int {
	$c = imagecolorsforindex($im, imagecolorat($im, $x, $y));
	return $c['red'] + $c['green'] + $c['blue'];
}
if (function_exists('imagecreatefrompng')) {
	foreach (array('overlays/webcam-frame.png', 'overlays/bottom-bar.pt-BR.png', 'overlays/bottom-bar.en.png') as $rel) {
		$im = imagecreatefrompng("$dir/$rel");
		check(chaos_alpha($im, 5, 5) === 127, "$rel: the corner is transparent");
		check(chaos_alpha($im, 960, 400) === 127, "$rel: the middle is transparent");
	}
	$cam = json_decode((string)file_get_contents("$dir/slots.json"), true)['slots']['overlays/webcam-frame.png']['camera'] ?? array(0, 0, 0, 0);
	$im = imagecreatefrompng("$dir/overlays/webcam-frame.png");
	check(chaos_alpha($im, (int)(($cam[0] + $cam[2]) / 2), (int)(($cam[1] + $cam[3]) / 2)) === 127, 'webcam frame: the camera window is transparent');
	$icon = imagecreatefrompng("$dir/discord/icon-circle-512.png");
	$opaque = true;
	foreach (array(array(0, 0), array(511, 0), array(0, 511), array(511, 511), array(256, 0), array(0, 256)) as $pt) {
		$opaque = $opaque && (chaos_alpha($icon, $pt[0], $pt[1]) === 0);
	}
	check($opaque, 'discord icon: corners and edges are opaque (the background fills the square)');
	// the key art sits inside the inscribed circle: no bright (gold or lit) pixel outside radius 0.97 * 256 except the ring, none
	// beyond the ring; compare the C: bright pixels (sum > 450) inside the circle of radius 0.78 * 256 only, ring excluded
	$bad = 0;
	for ($y = 0; $y < 512; $y += 2) {
		for ($x = 0; $x < 512; $x += 2) {
			$r = sqrt(($x - 255.5) ** 2 + ($y - 255.5) ** 2) / 256;
			if ($r > 0.86 && $r < 1.5) {
				$sum = chaos_sum($icon, $x, $y);
				if ($sum > 330 && !($r > 0.89 && $r < 0.96)) { $bad++; }
			}
		}
	}
	check($bad === 0, "discord icon: no key art outside 86% of the radius apart from the ring ($bad stray pixels)");
	$ringOutside = 0;
	for ($y = 0; $y < 512; $y += 2) {
		for ($x = 0; $x < 512; $x += 2) {
			if (sqrt(($x - 255.5) ** 2 + ($y - 255.5) ** 2) / 256 > 0.97) {
				if (chaos_sum($icon, $x, $y) > 150) { $ringOutside++; }
			}
		}
	}
	check($ringOutside === 0, 'discord icon: nothing but dark background beyond 97% of the radius, so a circle crop loses nothing');
} else {
	echo "note: GD is not installed: transparency and circle checks skipped\n";
}

// the OBS browser source: static, no cookies, no storage, no requests, no account data
$html = (string)file_get_contents("$dir/obs-overlay.html");
$js = (string)file_get_contents("$dir/obs-overlay.js");
foreach (array('document.cookie', 'localStorage', 'sessionStorage', 'indexedDB', 'fetch(', 'XMLHttpRequest', 'WebSocket', 'sendBeacon', 'import(', 'eval(') as $bad) {
	check(strpos($js, $bad) === false && strpos($html, $bad) === false, "obs page does not use $bad");
}
check(preg_match('#https?://#i', $html . $js) === 0, 'obs page names no other site');
check(strpos($html, 'src="obs-overlay.js"') !== false && strpos($html, 'transparent') !== false, 'obs page: own script, transparent background');
check(strpos($js, 'textContent') !== false && strpos($js, 'innerHTML') === false, 'obs page writes text only');
check(strpos($js, "[^A-Z0-9]") !== false && strpos($js, 'slice(0, 16)') !== false, 'obs page cleans the code to 3-16 letters and digits');
check(chaos_no_dashes($html . $js), 'no em or en dash in the obs page');

// the partner guide
$cfg = chaos_creator_config();
$lua = (string)file_get_contents(CHAOS_TEST_REPO . '/server/data/scripts/chaos/creator_codes_config.lua');
foreach (array('sharePct', 'launchBonusPct', 'supportDays', 'holdDays', 'orderCap', 'monthlyCap', 'launchBonusDays') as $k) {
	check(preg_match('/^\s*' . $k . '\s*=\s*' . (int)$cfg[$k] . '\b/m', $lua) === 1, "the guide reads $k from creator_codes_config.lua");
}
$raw = (string)file_get_contents($plugin . '/creators/partner_guide.json');
check(chaos_no_dashes($raw), 'no em or en dash in the guide');
$j = json_decode($raw, true);
check(is_array($j) && count($j['sections']) >= 8, 'the guide has its sections');
$ids = array_map(static function ($s) { return $s['id']; }, (array)$j['sections']);
foreach (array('start', 'apply', 'code', 'rules', 'brand', 'kit', 'obs', 'promo', 'checklist') as $want) { check(in_array($want, $ids, true), "guide section: $want"); }
$allowed = array('share', 'bonus', 'support', 'hold', 'orderCap', 'monthlyCap', 'bonusDays', 'launch', 'end', 'discord');
$leaf = static function ($v, $f) use (&$leaf) { if (is_array($v) && isset($v['en'])) { $f($v); } elseif (is_array($v)) { foreach ($v as $x) { $leaf($x, $f); } } };
$leaf($j, static function ($pair) use ($allowed) {
	check(($pair['pt-BR'] ?? '') !== '' && ($pair['en'] ?? '') !== '', 'guide text in both languages: ' . substr((string)($pair['en'] ?? ''), 0, 40));
	foreach (array('pt-BR', 'en') as $l) {
		check(strpos($pair[$l] ?? '', '(') === false, "no parenthesis in the guide ($l): " . substr((string)($pair[$l] ?? ''), 0, 40));
		preg_match_all('/\{([A-Za-z]+)\}/', (string)($pair[$l] ?? ''), $m);
		foreach ($m[1] as $tok) { check(in_array($tok, $allowed, true), "known token {{$tok}}"); }
	}
});
foreach (array('pt-BR', 'en') as $lang) {
	$g = chaos_creators_guide($lang, 'https://discord.gg/example');
	$text = json_encode($g, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
	check(strpos($text, '{') === false || strpos($text, '{"') !== false && preg_match('/\{[A-Za-z]+\}/', $text) === 0, "$lang guide: every token is filled");
	check(strpos($text, (int)$cfg['sharePct'] . '%') !== false && strpos($text, (int)$cfg['launchBonusPct'] . '%') !== false, "$lang guide: share and launch percent");
	check(strpos($text, (string)$cfg['orderCap']) !== false && strpos($text, (string)$cfg['monthlyCap']) !== false, "$lang guide: caps");
	check(strpos($text, 'https://discord.gg/example') !== false, "$lang guide: the Discord link of CHAOS_DISCORD_URL");
	check(strpos(json_encode(chaos_creators_guide($lang, 'javascript:alert(1)')), 'javascript:') === false, "$lang guide: only an https Discord link");
}
$ptGuide = chaos_creators_guide_numbers('pt-BR');
check($ptGuide['launch'] === '20/11/2026 15:00' && $ptGuide['end'] === '20/12/2026 15:00', 'pt-BR launch window dates: ' . $ptGuide['launch'] . ' to ' . $ptGuide['end']);
$enGuide = chaos_creators_guide_numbers('en');
check($enGuide['launch'] === '20 Nov 2026, 15:00' && $enGuide['end'] === '20 Dec 2026, 15:00', 'en launch window dates');

// the Python side quotes the same numbers
$py = array();
exec('python3 -I ' . escapeshellarg(CHAOS_TEST_REPO . '/website/tools/gen_streamer_kit.py') . ' --preview ' . escapeshellarg(sys_get_temp_dir() . '/chaos_streamer_kit_test_' . getmypid()) . ' 2>&1', $py, $pyStatus);
$pdir = sys_get_temp_dir() . '/chaos_streamer_kit_test_' . getmypid();
if ($pyStatus === 0 && is_file("$pdir/guide/guia-do-parceiro.pt-BR.md")) {
	$md = (string)file_get_contents("$pdir/guide/guia-do-parceiro.pt-BR.md");
	check(strpos($md, $ptGuide['launch']) !== false && strpos($md, $ptGuide['end']) !== false, 'the markdown guide has the same launch window as the page');
	check(strpos((string)file_get_contents("$pdir/chat/chat-commands.txt"), '{CODE}') !== false, 'chat commands keep the {CODE} field');
	check(is_file("$pdir/obs-overlay.html"), 'the preview carries the OBS page');
} else {
	echo "note: python3 with Pillow not usable here: markdown comparison skipped\n";
}
exec('rm -rf ' . escapeshellarg($pdir));

// the page shows the kit and the guide, in both languages
foreach (array('en' => array('Streamer kit', 'Partner guide', 'Discord icon'), 'pt-BR' => array('Kit para streamers', 'Guia do parceiro', 'Ícone do Discord')) as $lang => $words) {
	$html = chaos_render_page('creators', $lang);
	foreach ($words as $w) { check(strpos($html, $w) !== false, "page $lang says: $w"); }
	check(strpos($html, 'plugins/chaos/assets/streamer/discord/icon-circle-512.png') !== false, "page $lang links the Discord icon");
	check(strpos($html, 'plugins/chaos/assets/streamer/obs-overlay.html') !== false, "page $lang names the OBS page");
	check(strpos($html, 'id="guide-code"') !== false && strpos($html, 'id="guide-checklist"') !== false, "page $lang has the guide sections");
	check(strpos($html, '{') === false || preg_match('/\{[A-Za-z]+\}/', $html) === 0, "page $lang: no unfilled token");
	check(strpos($html, 'Fatal') === false && strpos($html, 'Notice') === false, "page $lang: no PHP error");
}
$i18n = (string)file_get_contents($plugin . '/i18n/pt-BR.php');
foreach (array('Streamer kit', 'OBS overlays and scenes', 'Panels and banners', 'Discord icon') as $k) { check(strpos($i18n, "'$k' =>") !== false, "pt-BR text for: $k"); }

// the manifest lists the kit files and they match the disk
$manifest = json_decode((string)file_get_contents($plugin . '/creators/media_kit_manifest.json'), true);
$names = array_map(static function ($f) { return $f['name']; }, $manifest['files']);
foreach (array('streamer/discord/icon-circle-512.png', 'streamer/guide/guia-do-parceiro.pt-BR.md', 'streamer/guide/partner-guide.en.md', 'streamer/chat/chat-commands.txt',
	'streamer/obs-overlay.html', 'streamer/slots.json', 'streamer/overlays/bottom-bar.en.png', 'streamer/banners/social-1500x500.en.png') as $n) {
	check(in_array($n, $names, true), "media kit lists $n");
}

// where things live: under a reserved top-level overlay folder only, no zip in the repository
check(!is_dir(CHAOS_TEST_REPO . '/website/overlay/press'), 'no website/overlay/press folder (the zip is built there at install)');
check(glob(CHAOS_TEST_REPO . '/website/{,overlay/}{press,art}/{,*/}*.zip', GLOB_BRACE) === array(), 'no zip committed');
check(strpos((string)file_get_contents(CHAOS_TEST_REPO . '/website/install_site.sh'), 'gen_media_kit.py') !== false, 'the installer builds the zip with the streamer kit');
$ci = (string)file_get_contents(CHAOS_TEST_REPO . '/.github/workflows/ci.yml');
check(strpos($ci, 'gen_streamer_kit.py --check') !== false, 'CI runs gen_streamer_kit.py --check');
check(strpos((string)file_get_contents(CHAOS_TEST_REPO . '/CLAUDE.md'), 'gen_streamer_kit.py') !== false, 'CLAUDE.md lists gen_streamer_kit.py');
check(strpos((string)file_get_contents(CHAOS_TEST_REPO . '/website/README.md'), '### Streamer kit') !== false, 'website/README.md has the Streamer kit section');

echo $failed ? "chaos_streamer_kit_test: $failed of $checks checks failed\n" : "chaos_streamer_kit_test: $checks checks OK\n";
exit($failed ? 1 : 0);
