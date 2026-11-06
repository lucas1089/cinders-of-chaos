<?php
// php website/tests/chaos_media_page_test.php : the trailer, shorts and screenshot gallery of the front page (O425;
// plugins/chaos/media_lib.php, layouts/chaos/views/index.php, assets/js/chaos-media.js, website/README.md "Trailer,
// gallery and shorts"): every file the page names is in media/manifest.json and on disk, in both languages; the
// trailer and the shorts follow the language; the gallery is lazy and links to the pictures; the call to action; a
// missing manifest renders nothing; unlisted names and paths are refused; the texts have pt-BR and no dashes; the
// script and the style rules exist. php-cli only, no ZnoteX, no database.
$failed = 0;
$checks = 0;
function check(bool $ok, string $what): void {
	global $failed, $checks;
	$checks++;
	if (!$ok) {
		$failed++;
		echo "FAIL: $what\n";
	}
}
require_once __DIR__ . '/chaos_pages_helper.php';
$root = dirname(__DIR__);
$plugin = $root . '/overlay/plugins/chaos';
require $plugin . '/media_lib.php';

// ---------------------------------------------------------------- the manifest and the files
$files = chaos_media_files();
check(count($files) === 24, 'the manifest lists 24 files: ' . count($files));
$total = 0;
foreach ($files as $name => $size) {
	$path = $plugin . '/assets/media/' . $name;
	check(is_file($path) && filesize($path) === $size, "$name is on disk with the size of the manifest");
	$total += $size;
}
check($total <= 25 * 1000 * 1000, "the media stay under 25 MB ($total)");
foreach (array('en', 'pt-BR') as $lang) {
	check(chaos_media_trailer($lang) !== null, "trailer in $lang");
	foreach (array_keys(chaos_media_shorts()) as $stem) {
		check(isset($files["$stem.$lang.mp4"], $files["$stem.$lang.jpg"]), "$stem in $lang: video and poster");
	}
}
foreach (array_keys(chaos_media_gallery()) as $file) {
	check(isset($files[$file]), "gallery picture $file is listed");
}
check(count(chaos_media_gallery()) >= 6 && count(chaos_media_gallery()) <= 8, 'six to eight screenshots');
check(chaos_media_lang('pt-BR') === 'pt-BR' && chaos_media_lang('en') === 'en' && chaos_media_lang('de') === 'en', 'the video language: pt-BR or en');

// ---------------------------------------------------------------- refusals and a missing manifest
check(chaos_media_url('../manifest.json') === '' && chaos_media_url('nothing.mp4') === '' && chaos_media_url('trailer.en.mp4', array()) === '', 'unlisted names and paths give no URL');
check(chaos_media_url('trailer.en.mp4') === 'plugins/chaos/assets/media/trailer.en.mp4', 'a listed file gets the asset URL');
check(chaos_media_files('/nonexistent/manifest.json') === array(), 'no manifest: no files');
check(chaos_media_trailer_html('en', array()) === '' && chaos_media_shorts_html('en', array()) === '' && chaos_media_gallery_html('en', array()) === '', 'no files: no sections, no broken player');
check(chaos_media_script_html('') === '' && strpos(chaos_media_script_html('x'), 'js/chaos-media.js') !== false, 'the script only with a section');
$partial = array('shot-boss.jpg' => 1);
check(substr_count(chaos_media_gallery_html('en', $partial), 'data-chaos-shot') === 1, 'only the listed pictures are shown');
$seoVideo = chaos_media_seo_video('https://x.example/', 'pt-BR');
check(chaos_media_seo_video('', 'en') === null && $seoVideo !== null && $seoVideo['url'] === 'https://x.example/plugins/chaos/assets/media/trailer.pt-BR.mp4', 'og:video address is absolute, without a double slash');

// ---------------------------------------------------------------- the front page in both languages
function render_home(string $lang): string {
	$code = '$config = array("chaos" => array()); $GLOBALS["config"] = $config; $_GET = array("l" => ' . var_export($lang, true) . ');'
		. '$news = array(); $view = ""; $page = 0; ob_start(); error_reporting(E_ALL & ~E_WARNING);'
		. 'function znote_plugin_asset(string $p, string $a): string { return "plugins/" . $p . "/assets/" . $a; }'
		. 'include ' . var_export(CHAOS_TEST_REPO . '/website/overlay/layouts/chaos/views/index.php', true) . '; echo ob_get_clean();';
	$out = array();
	exec(escapeshellarg(PHP_BINARY) . ' -r ' . escapeshellarg($code) . ' 2>&1', $out);
	return implode("\n", $out);
}
$en = render_home('en');
$pt = render_home('pt-BR');
check(strpos($en, 'id="trailer"') !== false && strpos($en, 'plugins/chaos/assets/media/trailer.en.mp4') !== false && strpos($en, 'trailer.en.jpg') !== false, 'en: the trailer and its poster');
check(strpos($en, 'trailer.pt-BR') === false && strpos($en, '.pt-BR.mp4') === false, 'en: no Portuguese file');
check(strpos($pt, 'trailer.pt-BR.mp4') !== false && strpos($pt, 'trailer.en.') === false && strpos($pt, 'short-boss.pt-BR.mp4') !== false, 'pt-BR: the Portuguese files');
check(strpos($en, 'href="#trailer">Watch the trailer</a>') !== false, 'en: the call to action next to the download button');
check(strpos($pt, 'href="#trailer">Assista ao trailer</a>') !== false, 'pt-BR: the call to action');
check(strpos($en, 'href="downloads">Download the client</a>') < strpos($en, 'href="#trailer"'), 'the trailer link comes after the download button');
check(strpos($en, 'data-chaos-trailer') !== false && strpos($en, ' controls ') !== false && strpos($en, ' muted ') !== false && strpos($en, ' loop ') !== false && strpos($en, ' playsinline ') !== false, 'the hero video: controls without script, muted, loop, playsinline');
check(strpos($en, 'preload="none"') !== false, 'nothing is downloaded before the script or a click');
check(substr_count($en, 'data-chaos-shot') === count(chaos_media_gallery()), 'one link per screenshot');
check(substr_count($en, 'loading="lazy"') === count(chaos_media_gallery()), 'the screenshots are lazy');
check(substr_count($en, '<figure class="chaos-short">') === 3, 'three shorts');
check(substr_count($en, '<script src="plugins/chaos/assets/js/chaos-media.js" defer></script>') === 1, 'the script once');
check(strpos($pt, 'A árvore passiva: mais de 600 nós') !== false && strpos($pt, 'Capturas de tela') !== false && strpos($pt, 'data-l-close="Fechar"') !== false, 'pt-BR: captions, heading, lightbox labels');
check(strpos($en, 'Warning') === false && strpos($en, 'Notice') === false && strpos($en, 'Fatal') === false, 'no PHP message in the page');
check(strpos($en, 'chaos-hero') < strpos($en, 'id="trailer"') && strpos($en, 'id="trailer"') < strpos($en, 'chaos-shorts') && strpos($en, 'chaos-shorts') < strpos($en, 'id="screenshots"'), 'order: hero, trailer, shorts, screenshots');

// ---------------------------------------------------------------- texts: pt-BR for every one, no dashes
$table = require $plugin . '/i18n/pt-BR.php';
$keys = array_merge(array_values(chaos_media_shorts()), array_values(chaos_media_gallery()), array('Watch the trailer', 'Trailer of Cinders of Chaos',
	'Recorded in the game itself, one minute. Click the video for sound and controls.', 'Quick looks', 'Screenshots',
	'Straight from the game client. Click a picture to enlarge it.', 'Close', 'Previous', 'Next'));
foreach ($keys as $k) {
	check(isset($table[$k]) && $table[$k] !== '', "pt-BR text for '$k'");
	check(chaos_no_dashes($k) && chaos_no_dashes((string)($table[$k] ?? '')), "no dash in '$k'");
}

// ---------------------------------------------------------------- script and style
$js = (string)file_get_contents($plugin . '/assets/js/chaos-media.js');
check(strpos($js, 'prefers-reduced-motion') !== false && strpos($js, 'saveData') !== false && strpos($js, "'Escape'") !== false && strpos($js, 'aria-modal') !== false, 'the script: less motion, less data, Escape, a modal dialog');
check(strpos($js, 'onclick') === false && strpos($js, 'eval(') === false, 'the script: no inline handlers, no eval');
$css = (string)file_get_contents($root . '/overlay/layouts/chaos/assets/css/chaos.css');
foreach (array('.chaos-trailer__video', '.chaos-shorts__strip', '.chaos-gallery__grid', '.chaos-lightbox', 'chaos-lightbox-open') as $rule) {
	check(strpos($css, $rule) !== false, "style rule $rule");
}
check(strpos($css, '/* media (O425) phones */') !== false, 'phone rules for the gallery and the strip');
check(chaos_no_dashes((string)file_get_contents($plugin . '/media_lib.php')), 'no em or en dash in media_lib.php');

echo $failed ? "chaos_media_page_test: $failed of $checks checks failed\n" : "chaos_media_page_test: $checks checks OK\n";
exit($failed ? 1 : 0);
