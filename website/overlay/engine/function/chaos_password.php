<?php
/**
 * Cinders of Chaos: account password hashes, shared with the game server (engine patch 0014,
 * server/src-patches/0014-salted-password-hashes.patch, src/passwordhash.cpp).
 *
 * accounts.password holds
 *   pbkdf2-sha256$<iterations>$<salt, standard base64>$<derived key, standard base64>
 * PBKDF2-HMAC-SHA256, a 16-byte random salt, a 32-byte key. A 40-hex-digit value is the old unsalted SHA-1 of the
 * password: it is still accepted and replaced by a PBKDF2 hash at the first successful login (website or game).
 *
 * Loaded by engine/function/users.php (website/patches/znotex-chaos-passwords.patch). Plain functions without
 * ZnoteX dependencies except db() in chaos_password_check_account(), so tests/chaos_password_test.php can run
 * them with php-cli alone.
 */

const CHAOS_PASSWORD_PREFIX = 'pbkdf2-sha256';
const CHAOS_PASSWORD_DEFAULT_ITERATIONS = 120000;
const CHAOS_PASSWORD_MIN_ITERATIONS = 1000;
const CHAOS_PASSWORD_MAX_ITERATIONS = 10000000;
const CHAOS_PASSWORD_SALT_BYTES = 16;
const CHAOS_PASSWORD_KEY_BYTES = 32;

/** Iterations of new hashes: $config['chaos_password_iterations'] (config.local.php), like passwordHashIterations
 *  in the server's config.lua. Verification always uses the count stored in the hash. */
function chaos_password_iterations(): int {
	$n = CHAOS_PASSWORD_DEFAULT_ITERATIONS;
	if (function_exists('config')) {
		$v = config('chaos_password_iterations');
		if (is_int($v) || (is_string($v) && ctype_digit($v))) {
			$n = (int)$v;
		}
	}
	return max(CHAOS_PASSWORD_MIN_ITERATIONS, min(CHAOS_PASSWORD_MAX_ITERATIONS, $n));
}

function chaos_password_hash(string $password, ?int $iterations = null): string {
	$iterations = max(CHAOS_PASSWORD_MIN_ITERATIONS, min(CHAOS_PASSWORD_MAX_ITERATIONS, $iterations ?? chaos_password_iterations()));
	$salt = random_bytes(CHAOS_PASSWORD_SALT_BYTES);
	$key = hash_pbkdf2('sha256', $password, $salt, $iterations, CHAOS_PASSWORD_KEY_BYTES, true);
	return CHAOS_PASSWORD_PREFIX . '$' . $iterations . '$' . base64_encode($salt) . '$' . base64_encode($key);
}

function chaos_password_is_legacy_sha1(string $stored): bool {
	return strlen($stored) === 40 && ctype_xdigit($stored);
}

/** ['iterations' => int, 'salt' => bytes, 'key' => bytes] or null when $stored is not a PBKDF2 hash of ours. */
function chaos_password_parse(string $stored): ?array {
	$parts = explode('$', $stored);
	if (count($parts) !== 4 || $parts[0] !== CHAOS_PASSWORD_PREFIX || !preg_match('/^[0-9]{1,8}$/', $parts[1])) {
		return null;
	}
	$iterations = (int)$parts[1];
	$salt = base64_decode($parts[2], true);
	$key = base64_decode($parts[3], true);
	if ($iterations < 1 || $iterations > CHAOS_PASSWORD_MAX_ITERATIONS || $salt === false || $salt === ''
		|| $key === false || strlen($key) < 16 || strlen($key) > 64) {
		return null;
	}
	return array('iterations' => $iterations, 'salt' => $salt, 'key' => $key);
}

/** Costs what checking a real PBKDF2 hash costs (unknown account, failed legacy check). */
function chaos_password_dummy(string $password): void {
	hash_pbkdf2('sha256', $password, str_repeat("\x5a", CHAOS_PASSWORD_SALT_BYTES), chaos_password_iterations(), CHAOS_PASSWORD_KEY_BYTES, true);
}

/**
 * True when $password matches $stored (PBKDF2, or the legacy SHA-1; $legacySalt only for TFS 0.3 salted SHA-1).
 * Comparisons are constant-time; a wrong password costs one PBKDF2 run whatever the stored kind.
 */
function chaos_password_verify(string $password, string $stored, string $legacySalt = ''): bool {
	if (chaos_password_is_legacy_sha1($stored)) {
		if (hash_equals(strtolower($stored), sha1($legacySalt . $password))) {
			return true;
		}
		chaos_password_dummy($password);
		return false;
	}
	$parsed = chaos_password_parse($stored);
	if ($parsed === null) {
		chaos_password_dummy($password);
		return false;
	}
	$key = hash_pbkdf2('sha256', $password, $parsed['salt'], $parsed['iterations'], strlen($parsed['key']), true);
	return hash_equals($parsed['key'], $key);
}

/** True for a legacy SHA-1 value, or a PBKDF2 hash weaker than the configured one. */
function chaos_password_needs_rehash(string $stored): bool {
	if (chaos_password_is_legacy_sha1($stored)) {
		return true;
	}
	$parsed = chaos_password_parse($stored);
	return $parsed === null || $parsed['iterations'] < chaos_password_iterations() || strlen($parsed['key']) !== CHAOS_PASSWORD_KEY_BYTES;
}

/**
 * Checks the password of account $accountId against its stored accounts.password and, after a successful check of
 * an old hash, writes a fresh PBKDF2 hash (only if the stored value did not change meanwhile, e.g. in the game).
 */
function chaos_password_check_account(int $accountId, string $password, string $stored, string $legacySalt = ''): bool {
	if (!chaos_password_verify($password, $stored, $legacySalt)) {
		return false;
	}
	if (chaos_password_needs_rehash($stored) && function_exists('db')) {
		db()->execute("UPDATE `accounts` SET `password` = ? WHERE `id` = ? AND `password` = ?;",
			[chaos_password_hash($password), $accountId, $stored]);
	}
	return true;
}
