// Tests of src/chaosprefetch.h from engine src-patch 0031 (the login reads off the game loop). CI takes the header out
// of the patch (the step "Login reads prefetch" in .github/workflows/ci.yml), then:
//   g++ -std=c++17 -Wall -Wextra -I "$d" server/tools/chaosprefetch_test.cpp -o "$d/chaosprefetch_test" && "$d/chaosprefetch_test"
// A prefetched result may only be used when the game loop would have read the same rows: the statement is a plain
// SELECT of known tables, and no write to any of them (or to a table a cascade or trigger reaches) was committed after
// the early read started.
#include "chaosprefetch.h"

#include <cstdio>
#include <string>
#include <vector>

using namespace ChaosPrefetch;

static int checks = 0, fails = 0;
static void ok(bool cond, const std::string& what)
{
	++checks;
	if (!cond) {
		++fails;
		std::printf("FAIL %s\n", what.c_str());
	}
}

static bool hasTable(const Statement& st, const char* t)
{
	for (const std::string& s : st.tables) {
		if (s == t) {
			return true;
		}
	}
	return false;
}

static void testReads()
{
	Statement st = classify("SELECT `stat`, `value` FROM `chaos_achievement_stats` WHERE `player_id` = 3");
	ok(st.kind == Statement::Read && st.cacheable && st.tables.size() == 1 && hasTable(st, "chaos_achievement_stats"),
	   "plain select");

	st = classify("SELECT DISTINCT a.`achievement` FROM `chaos_achievements` a INNER JOIN `players` p ON p.`id` = "
	              "a.`player_id` WHERE p.`account_id` = 3");
	ok(st.cacheable && st.tables.size() == 2 && hasTable(st, "chaos_achievements") && hasTable(st, "players"), "join with aliases");

	st = classify("SELECT `ps`.`player_id` FROM `player_storage` `ps` INNER JOIN `players` `p` ON `p`.`id` = `ps`.`player_id`");
	ok(st.cacheable && st.tables.size() == 2 && hasTable(st, "player_storage"), "backticked aliases");

	st = classify("SELECT a.x FROM t1 a, t2 AS b, `T3` WHERE a.id = b.id");
	ok(st.cacheable && st.tables.size() == 3 && hasTable(st, "t1") && hasTable(st, "t2") && hasTable(st, "t3"), "comma list, case");

	st = classify("SELECT x FROM t WHERE id IN (SELECT y FROM u WHERE z = 1)");
	ok(st.cacheable && hasTable(st, "t") && hasTable(st, "u"), "subquery tables");

	st = classify("SELECT d.n FROM (SELECT COUNT(*) AS n FROM w) d");
	ok(st.cacheable && st.tables.size() == 1 && hasTable(st, "w"), "derived table");

	st = classify("SELECT `id` FROM `player_history_skill` WHERE `player_id`=3 LIMIT 1;");
	ok(st.cacheable, "a trailing semicolon");

	st = classify("SELECT 'a FROM b', `x` FROM `t` WHERE `n` = 'it''s' AND `m` = 'back\\'slash'");
	ok(st.cacheable && st.tables.size() == 1 && hasTable(st, "t"), "FROM inside a string is no table");

	const char* notCached[] = {
		"SELECT 1",
		"SELECT * FROM t WHERE at > UNIX_TIMESTAMP()",
		"SELECT NOW()",
		"SELECT * FROM t ORDER BY RAND()",
		"SELECT * FROM t FOR UPDATE",
		"SELECT * FROM t LOCK IN SHARE MODE",
		"SELECT * FROM t WHERE a = @v",
		"SELECT * FROM t; SELECT * FROM u",
		"SELECT * FROM t /* c */",
		"SELECT * FROM t -- c",
		"SELECT * FROM t # c",
		"SELECT * FROM other.t",
		"SELECT * FROM `information_schema`.`TABLES`",
		"SELECT x INTO @v FROM t",
		"SELECT SUBSTRING(n FROM 2) FROM t",
		"SELECT * FROM t WHERE n = 'open",
		"SELECT LAST_INSERT_ID()",
		"SELECT GET_LOCK('x', 1) FROM t",
		"SELECT * FROM t WHERE a = ?",
		"WITH c AS (SELECT 1) SELECT * FROM c",
	};
	for (const char* q : notCached) {
		ok(!classify(q).cacheable, std::string("not prefetched: ") + q);
	}
}

static Statement head(const std::string& q)
{
	return classifyHead(q);
}

static bool writes(const Statement& st, const char* table, Event e)
{
	for (const auto& w : st.writes) {
		if (w.first == table && w.second == e) {
			return true;
		}
	}
	return false;
}

static void testWrites()
{
	Statement st = head("INSERT IGNORE INTO `chaos_achievements` (`player_id`, `achievement`) VALUES (3, 'x')");
	ok(st.kind == Statement::Write && writes(st, "chaos_achievements", Event::Insert) &&
	   writes(st, "chaos_achievements", Event::Update), "insert ignore (and a possible ON DUPLICATE KEY UPDATE)");

	st = head("REPLACE INTO t (a) VALUES (1)");
	ok(writes(st, "t", Event::Insert) && writes(st, "t", Event::Delete), "replace");

	st = head("UPDATE `players` SET `level` = 2 WHERE `id` = 3");
	ok(st.kind == Statement::Write && writes(st, "players", Event::Update), "update");

	st = head("UPDATE players p SET p.level = 2 WHERE p.id = 3");
	ok(st.kind == Statement::Write && writes(st, "players", Event::Update), "update with an alias");

	st = head("UPDATE a JOIN b ON a.id = b.id SET a.x = 1");
	ok(st.kind == Statement::Unknown, "multi-table update");

	st = head("UPDATE a, b SET a.x = 1");
	ok(st.kind == Statement::Unknown, "comma multi-table update");

	st = head("DELETE FROM `player_items` WHERE `player_id` = 3");
	ok(st.kind == Statement::Write && writes(st, "player_items", Event::Delete), "delete");

	st = head("DELETE FROM t");
	ok(st.kind == Statement::Write && writes(st, "t", Event::Delete), "delete everything");

	st = head("DELETE a FROM a JOIN b ON a.id = b.id");
	ok(st.kind == Statement::Unknown, "multi-table delete");

	st = head("DELETE FROM a USING a JOIN b");
	ok(st.kind == Statement::Unknown, "delete using");

	st = head("TRUNCATE TABLE `t`");
	ok(writes(st, "t", Event::Delete), "truncate");

	st = head("INSERT INTO `chaos`.`T` (a) VALUES (1)");
	ok(writes(st, "t", Event::Insert), "a qualified write counts for the table name");

	std::string big = "INSERT INTO `player_items` (`player_id`, `pid`, `sid`, `itemtype`, `count`, `attributes`) VALUES ";
	for (int i = 0; i < 2000; ++i) {
		big += (i ? ",(3," : "(3,") + std::to_string(i) + ",1,2,3,'a /* b */ ;')";
	}
	st = head(big);
	ok(st.kind == Statement::Write && writes(st, "player_items", Event::Insert), "a long insert is read from its head");

	ok(head("BEGIN").kind == Statement::Begin, "begin");
	ok(head("START TRANSACTION").kind == Statement::Begin, "start transaction");
	ok(head("COMMIT").kind == Statement::Commit, "commit");
	ok(head("ROLLBACK").kind == Statement::Rollback, "rollback");
	ok(head("ROLLBACK TO SAVEPOINT a").kind == Statement::None, "rollback to savepoint");
	ok(head("SET autocommit = 0").kind == Statement::Begin, "autocommit off");
	ok(head("SET autocommit=1").kind == Statement::Commit, "autocommit on");
	ok(head("SET NAMES utf8").kind == Statement::None, "set names");
	ok(head("SHOW VARIABLES LIKE 'max_allowed_packet'").kind == Statement::None, "show");
	ok(head("SELECT * FROM t").kind == Statement::Read, "a read writes nothing");
	ok(head("CREATE TABLE IF NOT EXISTS t (a INT)").kind == Statement::Unknown, "create");
	ok(head("ALTER TABLE t ADD b INT").kind == Statement::Unknown, "alter");
	ok(head("CALL p()").kind == Statement::Unknown, "call");
	ok(head("LOCK TABLES t WRITE").kind == Statement::Unknown, "lock tables");
	ok(head("/* x */ DELETE FROM t").kind == Statement::Unknown, "a leading comment");
	ok(head("DO SLEEP(1)").kind == Statement::Unknown, "do");
}

static void testTemplates()
{
	std::string t;
	const std::string name = "'Loadbot Aac'";
	ok(makeTemplate("SELECT a FROM t WHERE `player_id` = 210 AND acc = 5009 AND n = 'Loadbot Aac'", 210, 5009, name, t),
	   "template made");
	ok(expand(t, 211, 5010, "'Other'") == "SELECT a FROM t WHERE `player_id` = 211 AND acc = 5010 AND n = 'Other'",
	   "template expands (an account id with hex digits after the marker)");
	ok(t.find("210") == std::string::npos && t.find("5009") == std::string::npos, "the ids are taken out");

	ok(makeTemplate("SELECT a FROM t WHERE x = 'level_210' AND y = 2100 AND z = 1.210 AND w = 210.5", 210, 5009, name, t) &&
	   expand(t, 7, 8, name) == "SELECT a FROM t WHERE x = 'level_210' AND y = 2100 AND z = 1.210 AND w = 210.5",
	   "numbers inside strings, longer numbers and decimals are kept");

	ok(!makeTemplate("SELECT a FROM t WHERE id = 5", 5, 5, name, t), "same player and account id: nothing learnt");
	ok(!makeTemplate("SELECT a FROM t WHERE id = 5 /* x */", 5, 6, name, t), "a comment: nothing learnt");
	ok(makeTemplate("SELECT a FROM t WHERE id = 1", 5, 6, name, t) && t == "SELECT a FROM t WHERE id = 1",
	   "no id in the statement: the same text");
}

static void testDependencies()
{
	Dependencies d;
	d.addForeignKey("player_items", "players", "RESTRICT", "CASCADE");
	d.addForeignKey("players", "accounts", "RESTRICT", "CASCADE");
	d.addForeignKey("ip_bans", "players", "CASCADE", "CASCADE");
	d.addForeignKey("notes", "players", "RESTRICT", "SET NULL");
	d.addForeignKey("note_tags", "notes", "CASCADE", "RESTRICT");
	d.addForeignKey("plain", "players", "RESTRICT", "NO ACTION");
	d.addTrigger("players", "DELETE", "BEGIN UPDATE `houses` SET `owner` = 0 WHERE `owner` = OLD.`id`; END");
	d.addTrigger("guilds", "INSERT", "BEGIN INSERT INTO `guild_ranks` (`name`) VALUES ('a'); END");
	d.addTrigger("weird", "UPDATE", "BEGIN CALL something(); END");

	std::set<std::string> tables;
	bool all = false;
	d.affected({{"accounts", Event::Delete}}, tables, all);
	ok(!all && tables.count("accounts") && tables.count("players") && tables.count("player_items") &&
	   tables.count("ip_bans") && tables.count("houses") && tables.count("notes") && tables.count("note_tags") &&
	   !tables.count("plain"), "cascade chain, trigger, set null then on update cascade");

	tables.clear();
	d.affected({{"players", Event::Update}}, tables, all);
	ok(!all && tables.count("ip_bans") && !tables.count("player_items") && !tables.count("houses"), "on update cascade only");

	tables.clear();
	d.affected({{"players", Event::Insert}}, tables, all);
	ok(!all && tables.size() == 1, "an insert does not cascade");

	tables.clear();
	d.affected({{"guilds", Event::Insert}}, tables, all);
	ok(!all && tables.count("guild_ranks"), "an insert trigger");

	tables.clear();
	d.affected({{"weird", Event::Update}}, tables, all);
	ok(all, "a trigger that calls a procedure may write anything");

	d.addFunction("Grant_Reward");
	ok(d.callsFunction(classify("SELECT grant_reward(`id`) FROM `players` WHERE `id` = 3")),
	   "a SELECT that calls a stored function of the database");
	ok(!d.callsFunction(classify("SELECT COUNT(*) AS `n`, MAX(`level`) FROM `players` WHERE `id` IN (3, 4)")),
	   "built-in functions and IN lists are fine");
}

static void testClock()
{
	Dependencies d;
	d.addForeignKey("player_items", "players", "RESTRICT", "CASCADE");
	WriteClock clock;
	TxnState txn;
	const std::vector<std::string> read = {"player_items"};

	Snapshot s = clock.snapshot(read);
	statementDone(clock, &d, txn, "SELECT * FROM player_items");
	statementDone(clock, &d, txn, "UPDATE other SET a = 1");
	ok(clock.unchanged(read, s), "reads and other tables leave it valid");

	statementDone(clock, &d, txn, "DELETE FROM players WHERE id = 3");
	ok(!clock.unchanged(read, s), "a cascading delete makes it stale");

	s = clock.snapshot(read);
	statementDone(clock, &d, txn, "BEGIN");
	statementDone(clock, &d, txn, "INSERT INTO player_items (a) VALUES (1)");
	ok(clock.unchanged(read, s), "inside a transaction nothing counts yet (the other connection cannot see it)");
	statementDone(clock, &d, txn, "COMMIT");
	ok(!clock.unchanged(read, s), "the commit makes it stale");

	s = clock.snapshot(read);
	statementDone(clock, &d, txn, "BEGIN");
	statementDone(clock, &d, txn, "INSERT INTO player_items (a) VALUES (1)");
	statementDone(clock, &d, txn, "ROLLBACK");
	ok(!clock.unchanged(read, s), "a rollback counts too (more invalidation, never less)");

	s = clock.snapshot(read);
	statementDone(clock, &d, txn, "CREATE TABLE x (a INT)");
	ok(!clock.unchanged(read, s), "an unknown statement makes everything stale");

	s = clock.snapshot(read);
	statementDone(clock, nullptr, txn, "INSERT INTO unrelated (a) VALUES (1)");
	ok(!clock.unchanged(read, s), "before the dependencies are known every write counts as any write");

	s = clock.snapshot(read);
	statementDone(clock, &d, txn, "SET autocommit = 0");
	statementDone(clock, &d, txn, "UPDATE player_items SET a = 2");
	ok(clock.unchanged(read, s), "autocommit off: the write waits for the commit");
	statementDone(clock, &d, txn, "SET autocommit = 1");
	ok(!clock.unchanged(read, s), "autocommit on commits");

	s = clock.snapshot(read);
	statementDone(clock, &d, txn, "BEGIN");
	statementDone(clock, &d, txn, "UPDATE player_items SET a = 3");
	statementDone(clock, &d, txn, "BEGIN"); // commits the first
	ok(!clock.unchanged(read, s), "BEGIN inside a transaction commits it");
	statementDone(clock, &d, txn, "COMMIT");
}

static void testTemplatesSet()
{
	Templates t;
	t.learn("a", {"x"});
	t.learn("a", {"x"});
	t.learn("once", {"x"});
	std::vector<Templates::Entry> list = t.take();
	ok(list.size() == 2 && list[0].text == "a", "the most used first");
	t.take(); // "once" prefetched twice, never run again
	list = t.take();
	ok(list.size() == 1 && list[0].text == "a", "a template one login ran is dropped after 2 unused prefetches");
	for (uint32_t i = 0; i < Templates::DROP_KNOWN; ++i) {
		t.take();
	}
	ok(t.take().empty(), "a known template is dropped after DROP_KNOWN unused prefetches");
	t.learn("b", {"x"});
	t.learn("b", {"x"});
	for (int i = 0; i < 200; ++i) {
		t.take();
		t.learn("b", {"x"});
	}
	ok(t.take().size() == 1, "a template every login runs stays");
	Templates many;
	for (size_t i = 0; i < Templates::MAX_TEMPLATES + 10; ++i) {
		many.learn("q" + std::to_string(i), {"x"});
	}
	ok(many.size() == Templates::MAX_TEMPLATES, "at most MAX_TEMPLATES");
	ok(many.take(10).size() == 10, "at most the asked number per login");
}

int main()
{
	testReads();
	testWrites();
	testTemplates();
	testDependencies();
	testClock();
	testTemplatesSet();
	std::printf("%d checks, %d failed\n", checks, fails);
	return fails == 0 ? 0 : 1;
}
