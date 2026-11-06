<?php
/**
 * Trailer, shorts and screenshot gallery of the front page (O425; website/README.md "Trailer, gallery and shorts").
 * The files are in assets/media/ (made by website/tools/gen_site_media.py, listed in media/manifest.json):
 * trailer.<lang>.mp4 with its poster, short-<name>.<lang>.mp4 with posters, shot-<name>.jpg. <lang> is en or pt-BR and
 * follows the visitor's language (i18n_lib.php). This file only builds HTML and meta data; it reads no file except
 * the manifest, and it names a file only when the manifest lists it, so a missing file never leaves a broken player.
 * Behaviour (autoplay of the muted hero, sound on click, the lightbox) is assets/js/chaos-media.js; without script
 * the trailer has its controls and the gallery links open the images.
 */

if (!function_exists('chaos_media_lang')) {

require_once __DIR__ . '/i18n_lib.php';

/** The language of the video files: the visitor's, en or pt-BR. */
function chaos_media_lang(?string $lang = null): string {
	$lang = $lang ?? chaos_lang();
	return $lang === 'pt-BR' ? 'pt-BR' : 'en';
}

/** The files of assets/media/ the manifest lists: name => size. Empty when the manifest is missing or broken. */
function chaos_media_files(?string $manifest = null): array {
	static $cache = array();
	$manifest = $manifest ?? (__DIR__ . '/assets/media/manifest.json');
	if (!isset($cache[$manifest])) {
		$out = array();
		$data = is_file($manifest) ? json_decode((string)file_get_contents($manifest), true) : null;
		foreach ((is_array($data) && isset($data['files']) && is_array($data['files'])) ? $data['files'] : array() as $name => $info) {
			if (is_string($name) && preg_match('/^[a-z0-9][a-z0-9.-]*\.(mp4|jpg)$/i', $name) && is_array($info)) {
				$out[$name] = (int)($info['size'] ?? 0);
			}
		}
		$cache[$manifest] = $out;
	}
	return $cache[$manifest];
}

/** The URL of a media file (path under the plugin's assets/media/), '' when the manifest does not list it. */
function chaos_media_url(string $file, ?array $files = null): string {
	$files = $files ?? chaos_media_files();
	if (!isset($files[$file])) {
		return '';
	}
	$path = 'media/' . $file;
	return function_exists('znote_plugin_asset') ? (string)znote_plugin_asset('chaos', $path) : 'plugins/chaos/assets/' . $path;
}

/** The shorts of the strip: file stem => English title (the pt-BR text is in i18n/pt-BR.php). */
function chaos_media_shorts(): array {
	return array(
		'short-classes' => 'All seven classes',
		'short-boss' => 'Raids and world bosses',
		'short-rift' => 'Open a rift',
	);
}

/** The gallery: file => English caption (the same text is the picture's alt text). */
function chaos_media_gallery(): array {
	return array(
		'shot-boss.jpg' => 'A world boss and a party of seven',
		'shot-passive-tree.jpg' => 'The passive tree: over 600 nodes',
		'shot-hunt.jpg' => 'A hunt with a loot-rich pack',
		'shot-ice.jpg' => 'Mystic spells clearing a pack',
		'shot-tower.jpg' => 'The Infinity Tower',
		'shot-rift.jpg' => 'A rift of the Obsidian Hall',
		'shot-arena.jpg' => 'The arena, one against one',
		'shot-inferno.jpg' => 'The boss lair on fire',
	);
}

/** The trailer: array(video, poster) URLs in the language, or null when a file is missing. */
function chaos_media_trailer(?string $lang = null, ?array $files = null): ?array {
	$lang = chaos_media_lang($lang);
	$video = chaos_media_url('trailer.' . $lang . '.mp4', $files);
	$poster = chaos_media_url('trailer.' . $lang . '.jpg', $files);
	return $video !== '' && $poster !== '' ? array('video' => $video, 'poster' => $poster) : null;
}

/** The trailer for link previews: array(url, type, width, height) with the site's absolute address, or null. */
function chaos_media_seo_video(string $siteUrl, ?string $lang = null, ?array $files = null): ?array {
	$t = chaos_media_trailer($lang, $files);
	if ($t === null || $siteUrl === '') {
		return null;
	}
	$path = $t['video'];
	return array('url' => rtrim($siteUrl, '/') . '/' . ltrim($path, '/'), 'type' => 'video/mp4', 'width' => 1280, 'height' => 720);
}

function chaos_media_h($v): string {
	return htmlspecialchars((string)$v, ENT_QUOTES, 'UTF-8');
}

/**
 * The trailer section (id "trailer"): the poster until the script autoplays the muted video; the controls stay in the
 * markup so it works without script. '' when the trailer files are missing.
 */
function chaos_media_trailer_html(?string $lang = null, ?array $files = null): string {
	$lang = chaos_media_lang($lang);
	$t = chaos_media_trailer($lang, $files);
	if ($t === null) {
		return '';
	}
	$label = chaos_t_in($lang, 'Trailer of Cinders of Chaos');
	return '<section class="chaos-box chaos-trailer" id="trailer">'
		. '<h2 class="chaos-heading">' . chaos_media_h(chaos_t_in($lang, 'Watch the trailer')) . '</h2>'
		. '<div class="chaos-trailer__frame">'
		. '<video class="chaos-trailer__video" data-chaos-trailer controls muted loop playsinline preload="none" width="1280" height="720"'
		. ' poster="' . chaos_media_h($t['poster']) . '" aria-label="' . chaos_media_h($label) . '">'
		. '<source src="' . chaos_media_h($t['video']) . '" type="video/mp4">'
		. '<a href="' . chaos_media_h($t['video']) . '">' . chaos_media_h(chaos_t_in($lang, 'Watch the trailer')) . '</a>'
		. '</video></div>'
		. '<p class="chaos-note chaos-trailer__note">' . chaos_media_h(chaos_t_in($lang, 'Recorded in the game itself, one minute. Click the video for sound and controls.')) . '</p>'
		. '</section>';
}

/** The strip of shorts: a poster each that plays on a tap, with the language's file. '' without any. */
function chaos_media_shorts_html(?string $lang = null, ?array $files = null): string {
	$lang = chaos_media_lang($lang);
	$cards = '';
	foreach (chaos_media_shorts() as $stem => $title) {
		$video = chaos_media_url($stem . '.' . $lang . '.mp4', $files);
		$poster = chaos_media_url($stem . '.' . $lang . '.jpg', $files);
		if ($video === '' || $poster === '') {
			continue;
		}
		$text = chaos_t_in($lang, $title);
		$cards .= '<figure class="chaos-short">'
			. '<video controls playsinline preload="none" width="540" height="960" poster="' . chaos_media_h($poster) . '"'
			. ' aria-label="' . chaos_media_h($text) . '"><source src="' . chaos_media_h($video) . '" type="video/mp4"></video>'
			. '<figcaption>' . chaos_media_h($text) . '</figcaption></figure>';
	}
	if ($cards === '') {
		return '';
	}
	return '<section class="chaos-box chaos-shorts">'
		. '<h2 class="chaos-heading">' . chaos_media_h(chaos_t_in($lang, 'Quick looks')) . '</h2>'
		. '<div class="chaos-shorts__strip">' . $cards . '</div></section>';
}

/** The screenshot gallery: lazy thumbnails that link to the picture; assets/js/chaos-media.js adds the lightbox. */
function chaos_media_gallery_html(?string $lang = null, ?array $files = null): string {
	$lang = chaos_media_lang($lang);
	$items = '';
	foreach (chaos_media_gallery() as $file => $caption) {
		$url = chaos_media_url($file, $files);
		if ($url === '') {
			continue;
		}
		$text = chaos_t_in($lang, $caption);
		$items .= '<a class="chaos-shot" href="' . chaos_media_h($url) . '" data-chaos-shot data-caption="' . chaos_media_h($text) . '">'
			. '<img src="' . chaos_media_h($url) . '" width="1280" height="720" loading="lazy" decoding="async" alt="' . chaos_media_h($text) . '">'
			. '<span class="chaos-shot__cap">' . chaos_media_h($text) . '</span></a>';
	}
	if ($items === '') {
		return '';
	}
	return '<section class="chaos-box chaos-gallery" id="screenshots" data-l-close="' . chaos_media_h(chaos_t_in($lang, 'Close')) . '"'
		. ' data-l-prev="' . chaos_media_h(chaos_t_in($lang, 'Previous')) . '" data-l-next="' . chaos_media_h(chaos_t_in($lang, 'Next')) . '">'
		. '<h2 class="chaos-heading">' . chaos_media_h(chaos_t_in($lang, 'Screenshots')) . '</h2>'
		. '<p class="chaos-lead">' . chaos_media_h(chaos_t_in($lang, 'Straight from the game client. Click a picture to enlarge it.')) . '</p>'
		. '<div class="chaos-gallery__grid">' . $items . '</div></section>';
}

/** The script of the trailer and the lightbox, once per page ('' when the page shows none of them). */
function chaos_media_script_html(string $sections): string {
	if ($sections === '') {
		return '';
	}
	$script = function_exists('znote_plugin_asset') ? (string)znote_plugin_asset('chaos', 'js/chaos-media.js') : 'plugins/chaos/assets/js/chaos-media.js';
	return '<script src="' . chaos_media_h($script) . '" defer></script>';
}

} // function_exists guard
