<?php
/**
 * Cinders of Chaos: character creation, shared by the website form and the client.
 *
 * ZnoteX checked and created a new character inline in createcharacter.php. Those lines moved here unchanged
 * (patches/znotex-chaos-character-create.patch makes createcharacter.php call these two functions), so the client's
 * character creation (chaos_client_api.php, plugins/chaos/client_api_lib.php) runs exactly the checks of the website
 * form: the name rules ($config minL, maxL, maxW, invalidNameTags, creatureNameTags), a taken name, the class
 * ($config['available_vocations'], narrowed to the account's class lock by plugins/chaos/plugin.php or by the API),
 * the town, the sex, the character limit ($config['max_characters'], set per account by the plugin or the API) and
 * the IP check. Only the form token is the page's own (the API has its own authentication). One check is ours: a
 * name that is a page address of the site (chaos_character_name_reserved).
 *
 * Needs ZnoteX's engine/function/general.php and users.php (validate_name, user_character_exist, t, ...), loaded by
 * engine/init.php before any caller.
 */

if (!function_exists('chaos_character_form_errors')) {

/**
 * The top-level addresses of the site (README "Web server", clean addresses): /highscores is highscores.php, so a
 * character named Highscores could never be reached at /Highscores. ZnoteX's pages (letters only: a character name
 * has no digits or _), its folders, ours and the client services path. The game's name change refuses the same list
 * (server chaos_constants.lua shopServices.name.reserved; website/tests/chaos_client_api_test.php compares them).
 */
function chaos_reserved_character_names(): array {
	return array(
		'achievements', 'auctionchar', 'bans', 'blank', 'buypoints', 'changelog', 'changepassword', 'characterprofile',
		'config', 'contact', 'createcharacter', 'creatures', 'credits', 'deaths', 'downloads', 'failed', 'faq', 'forum',
		'gallery', 'guilds', 'guildwar', 'helpdesk', 'highscores', 'house', 'houses', 'index', 'ipn', 'items', 'killers',
		'login', 'logout', 'mailtest', 'market', 'myaccount', 'onlinelist', 'page', 'payment', 'powergamers', 'protected',
		'queststatus', 'recovery', 'register', 'serverinfo', 'settings', 'shop', 'spells', 'sub', 'success', 'support',
		'team', 'topguilds', 'toponline', 'twofa', 'twtrnews', 'voting',
		'admin', 'api', 'assets', 'cache', 'docker', 'engine', 'install', 'landing', 'layouts', 'locale', 'lua', 'plugins',
		'special', 'sql', 'tests', 'tools', 'updates', 'vendor', 'clientservices',
	);
}

/** True when a character name is a top-level address of the site: the list above, or a page or folder there now. */
function chaos_character_name_reserved(string $name): bool {
	$lower = strtolower(trim($name));
	if (!preg_match('/^[a-z]+$/', $lower)) {
		return false; // more than one word: never an address
	}
	if (in_array($lower, chaos_reserved_character_names(), true)) {
		return true;
	}
	$root = dirname(__DIR__, 2);
	return is_file($root . '/' . $lower . '.php') || is_dir($root . '/' . $lower);
}

/**
 * The errors of a character creation request (an empty list: it may be created). $post is the form (name,
 * selected_vocation, selected_town, selected_gender, token); its name is trimmed in place, as the page did with
 * $_POST. $userData: the account's user_data() row (is_admin). $checkToken: the website form's CSRF token.
 */
/**
 * A word "Tester" in the name: the staff's tester bots are named "Tester Xxx" (server/README.md "Tester bots"), so
 * no player may take a name that looks like one (the game's rule: chaos_constants.lua shopServices.name.staffWords).
 */
function chaos_character_name_tester(string $name): bool {
	foreach (preg_split('/\s+/', strtolower(trim($name))) as $word) {
		if ($word === 'tester') {
			return true;
		}
	}
	return false;
}

function chaos_character_form_errors(array &$post, int $accountId, array $userData, bool $checkToken = true): array {
	global $config;
	$errors = array();
	// $_POST['']
	$required_fields = array('name', 'selected_town');
	foreach($post as $key=>$value) {
		if (empty($value) && in_array($key, $required_fields) === true) {
			$errors[] = t('reg.fill_all');
			break 1;
		}
	}

	// check errors (= user exist, pass long enough
	if (empty($errors) === true) {
		if ($checkToken && !Token::isValid($post['token'] ?? null)) {
			$errors[] = t('login.token_invalid');
		}
		$post['name'] = validate_name((string)($post['name'] ?? ''));
		if ($post['name'] === false) {
			$errors[] = t('acc.name_max_words');
		} else {
			if (user_character_exist($post['name']) !== false) {
				$errors[] = t('acc.name_taken');
			}
			if (!preg_match("/^[a-zA-Z ]+$/", $post['name'])) {
				$errors[] = t('acc.name_letters');
			}
			if (strlen($post['name']) < $config['minL'] || strlen($post['name']) > $config['maxL']) {
				$errors[] = t('acc.name_length', ['min' => $config['minL'], 'max' => $config['maxL']]);
			}
			// name restriction
			$resname = explode(" ", $post['name']);
			$username = $post['name'];
			foreach($resname as $res) {
				if(in_array(strtolower($res), $config['invalidNameTags'])) {
						$errors[] = t('reg.restricted_word');
				}
				if(strlen($res) == 1) {
					$errors[] = t('reg.words_too_short');
				}
			}
			if(in_array(strtolower($username), $config['creatureNameTags'])) {
				$errors[] = t('createchar.creature_name');
			}
			// Cinders of Chaos (not from createcharacter.php): a name that is a page address would be hidden by the page
			if (chaos_character_name_reserved($username)) {
				$errors[] = t('reg.restricted_word');
			}
			// the tester bots' names (Tester Xxx) belong to the staff
			if (chaos_character_name_tester($username)) {
				$errors[] = t('reg.restricted_word');
			}
			// Validate vocation id
			if (!in_array((int)($post['selected_vocation'] ?? 0), $config['available_vocations'])) {
				$errors[] = t('createchar.bad_vocation');
			}
			// Validate town id
			if (!in_array((int)($post['selected_town'] ?? 0), $config['available_towns'])) {
				$errors[] = t('createchar.bad_town');
			}
			// Validate gender id
			if (!in_array((int)($post['selected_gender'] ?? -1), array(0, 1))) {
				$errors[] = t('createchar.bad_gender');
			}
			if (vocation_id_to_name($post['selected_vocation'] ?? 0) === false) {
				$errors[] = t('createchar.no_vocation');
			}
			if (town_id_to_name($post['selected_town'] ?? 0) === false) {
				$errors[] = t('createchar.no_town');
			}
			if (gender_exist($post['selected_gender'] ?? -1) === false) {
				$errors[] = t('createchar.no_gender');
			}
			// Char count
			$char_count = user_character_list_count($accountId);
			if ($char_count >= $config['max_characters'] && !is_admin($userData)) {
				$errors[] = t('createchar.max_chars', ['max' => $config['max_characters']]);
			}
			if (validate_ip(getIP()) === false && $config['validate_IP'] === true) {
				$errors[] = t('reg.bad_ip');
			}
		}
	}
	return $errors;
}

/**
 * Creates the character of a request that chaos_character_form_errors() passed and runs the character.created hook
 * (the plugin's class look and depot boxes). Returns the row data written (name as stored).
 */
function chaos_character_create(array $post, int $accountId): array {
	global $config;
	if ($config['log_ip']) {
		znote_visitor_insert_detailed_data(2);
	}

	$character_data = array(
		'name'       => format_character_name($post['name']),
		'account_id' => $accountId,
		'vocation'   => $post['selected_vocation'],
		'town_id'    => $post['selected_town'],
		'sex'        => $post['selected_gender'],
		'lastip'     => getIPLong(),
		'created'    => time()
	);

	user_create_character($character_data);

	znote_hook('character.created', array(
		'name'       => $character_data['name'],
		'account_id' => $character_data['account_id'],
		'vocation'   => $character_data['vocation'],
	));
	return $character_data;
}

}
