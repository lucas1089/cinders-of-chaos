<?php
/**
 * Database access of the donation flow: prepared statements only, with the affected row count, so every state change
 * is one conditional UPDATE ("... WHERE `status` IN (...)") whose count says whether it happened. Two backends:
 * mysqli (the site and the worker, the same credentials as ZnoteX's config.local.php) and PDO (the tests use an
 * in-memory SQLite database; the SQL here is the subset both understand).
 */

interface ChaosPayDb {
	/** Rows of a SELECT as associative arrays. */
	public function rows(string $sql, array $params = array()): array;
	/** Runs a statement; returns the number of affected rows. */
	public function exec(string $sql, array $params = array()): int;
	public function begin(): void;
	public function commit(): void;
	public function rollback(): void;
}

final class ChaosPayPdo implements ChaosPayDb {
	private PDO $pdo;

	public function __construct(PDO $pdo) {
		$pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
		$this->pdo = $pdo;
	}

	public function pdo(): PDO {
		return $this->pdo;
	}

	public function rows(string $sql, array $params = array()): array {
		$st = $this->pdo->prepare($sql);
		$st->execute(array_values($params));
		return $st->fetchAll(PDO::FETCH_ASSOC);
	}

	public function exec(string $sql, array $params = array()): int {
		$st = $this->pdo->prepare($sql);
		$st->execute(array_values($params));
		return $st->rowCount();
	}

	public function begin(): void { $this->pdo->beginTransaction(); }
	public function commit(): void { $this->pdo->commit(); }
	public function rollback(): void { if ($this->pdo->inTransaction()) { $this->pdo->rollBack(); } }
}

final class ChaosPayMysqli implements ChaosPayDb {
	private mysqli $link;

	public function __construct(string $host, string $user, string $pass, string $name, int $port = 3306) {
		mysqli_report(MYSQLI_REPORT_ERROR | MYSQLI_REPORT_STRICT);
		$this->link = new mysqli($host, $user, $pass, $name, $port);
		$this->link->set_charset('utf8');
	}

	/** From ZnoteX's $config (config.local.php). */
	public static function fromConfig(array $config): self {
		$port = (int)(ini_get('mysqli.default_port') ?: 3306);
		return new self((string)($config['sqlHost'] ?? '127.0.0.1'), (string)($config['sqlUser'] ?? ''),
			(string)($config['sqlPassword'] ?? ''), (string)($config['sqlDatabase'] ?? ''), $port);
	}

	private function run(string $sql, array $params): mysqli_stmt {
		$st = $this->link->prepare($sql);
		if ($params) {
			$types = '';
			$values = array();
			foreach ($params as $p) {
				$types .= is_int($p) ? 'i' : 's';
				$values[] = is_bool($p) ? (int)$p : $p;
			}
			$st->bind_param($types, ...$values);
		}
		$st->execute();
		return $st;
	}

	public function rows(string $sql, array $params = array()): array {
		$st = $this->run($sql, array_values($params));
		$res = $st->get_result();
		$out = $res ? $res->fetch_all(MYSQLI_ASSOC) : array();
		$st->close();
		return $out;
	}

	public function exec(string $sql, array $params = array()): int {
		$st = $this->run($sql, array_values($params));
		$n = $st->affected_rows;
		$st->close();
		return max(0, (int)$n);
	}

	public function begin(): void { $this->link->begin_transaction(); }
	public function commit(): void { $this->link->commit(); }
	public function rollback(): void { $this->link->rollback(); }
}
