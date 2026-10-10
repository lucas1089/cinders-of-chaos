<?php
// The tables of the donation flow in an in-memory SQLite database (chaos_pay_test.php, chaos_donation_page_test.php).
function chaos_pay_test_db(): ChaosPayPdo {
	$pdo = new PDO('sqlite::memory:');
	$db = new ChaosPayPdo($pdo);
	$pdo->exec("CREATE TABLE accounts (id INTEGER PRIMARY KEY, email TEXT NOT NULL DEFAULT '')");
	$pdo->exec("CREATE TABLE chaos_coin_orders (id INTEGER PRIMARY KEY AUTOINCREMENT, account_id INT NOT NULL, pack_key TEXT NOT NULL,
		provider TEXT NOT NULL DEFAULT '', provider_ref TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'paid', coins INT NOT NULL DEFAULT 0,
		bonus INT NOT NULL DEFAULT 0, first_bonus INT NOT NULL DEFAULT 0, note TEXT NOT NULL DEFAULT '', created INT NOT NULL,
		credited INT NOT NULL DEFAULT 0, UNIQUE (provider, provider_ref))");
	$pdo->exec("CREATE TABLE chaos_coin_payments (order_id INT PRIMARY KEY, method TEXT NOT NULL, token TEXT NOT NULL UNIQUE,
		amount_cents INT NOT NULL, currency TEXT NOT NULL, source TEXT NOT NULL DEFAULT 'client', psp TEXT NOT NULL DEFAULT '',
		psp_id TEXT NOT NULL DEFAULT '', psp_ref TEXT NOT NULL DEFAULT '', psp_status TEXT NOT NULL DEFAULT '', qr_code TEXT NOT NULL DEFAULT '',
		pay_url TEXT NOT NULL DEFAULT '', qr_image TEXT NULL, expires INT NOT NULL DEFAULT 0, attempts INT NOT NULL DEFAULT 0,
		claimed INT NOT NULL DEFAULT 0, checked INT NOT NULL DEFAULT 0, cancel_sent INT NOT NULL DEFAULT 0, paid_at INT NOT NULL DEFAULT 0,
		reversal TEXT NOT NULL DEFAULT '', reversal_cents INT NOT NULL DEFAULT 0, reversal_done INT NOT NULL DEFAULT 0,
		reversal_coins INT NOT NULL DEFAULT 0, reversal_at INT NOT NULL DEFAULT 0, note TEXT NOT NULL DEFAULT '', updated INT NOT NULL DEFAULT 0)");
	$pdo->exec("INSERT INTO accounts (id, email) VALUES (77, 'player@example.invalid'), (78, '')");
	return $db;
}
