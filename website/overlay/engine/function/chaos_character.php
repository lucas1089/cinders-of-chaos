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
 * the IP check. Only the form token is the page's own (the API has its own authentication).
 *
 * Needs ZnoteX's engine/function/general.php and users.php (validate_name, user_character_exist, t, ...), loaded by
 * engine/init.php before any caller.
 */

if (!function_exists('chaos_character_form_errors')) {

/**
 * The errors of a character creation request (an empty list: it may be created). $post is the form (name,
 * selected_vocation, selected_town, selected_gender, token); its name is trimmed in place, as the page did with
 * $_POST. $userData: the account's user_data() row (is_admin). $checkToken: the website form's CSRF token.
 */
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
