-- Salted account passwords (src-patches/0014-salted-password-hashes.patch, website/patches/znotex-chaos-passwords.patch):
-- accounts.password holds "pbkdf2-sha256$<iterations>$<salt base64>$<key base64>" (about 90 characters) instead of the
-- stock CHAR(40) SHA-1. Old SHA-1 values stay valid and are re-hashed at the next successful login (game or website).
-- Idempotent: running it again changes nothing. website/setup/chaos_setup.php makes the same change if it runs first.
ALTER TABLE `accounts` MODIFY `password` VARCHAR(255) NOT NULL;
