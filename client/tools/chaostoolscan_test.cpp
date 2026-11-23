// Tests of src/client/chaostoolscan.h (client base patch 0207, the known-tool scan of the bot detection, O722; client/BASE.md "0207"). CI cuts the
// header out of the patch and builds this file against it:
//   g++ -std=c++17 -Wall -Wextra -I <dir with chaostoolscan.h> client/tools/chaostoolscan_test.cpp
// Checks: the hash (FNV-1a 64 over the lower-cased bytes, the vector staff use to make the list), the list parser, the words of a name and of a
// title, the matching of codes, that the answer holds codes only (never a name or a title), the caps, and that every other platform answers "".
#include "chaostoolscan.h"

#include <cstdio>

using namespace chaos::toolscan;

static int failures = 0;
static int checks = 0;

static void eq(long long got, long long want, const char* what)
{
	++checks;
	if (got != want) {
		++failures;
		std::printf("FAIL %s: got %lld, want %lld\n", what, got, want);
	}
}

static void eqs(const std::string& got, const std::string& want, const char* what)
{
	++checks;
	if (got != want) {
		++failures;
		std::printf("FAIL %s: got '%s', want '%s'\n", what, got.c_str(), want.c_str());
	}
}

int main()
{
	// the hash: the FNV-1a 64 vectors, case folded
	eqs(hex16(fnv1a64("")), "cbf29ce484222325", "empty string");
	eqs(hex16(fnv1a64("a")), "af63dc4c8601ec8c", "a");
	eqs(hex16(fnv1a64("foobar")), "85944171f73967e8", "foobar");
	eq(fnv1a64("FooBar") == fnv1a64("foobar"), 1, "upper case folds");
	eq(fnv1a64("foo bar") != fnv1a64("foobar"), 1, "a space is part of the text");
	eqs(hex16(0x1), "0000000000000001", "hex16 pads");

	// the list
	const std::string good = "cave1:" + hex16(fnv1a64("cavebotx")) + ",rumo:" + hex16(fnv1a64("rumo"));
	eq(parseSpec(good).size(), 2, "two entries");
	eq(parseSpec(good)[0].hash == fnv1a64("cavebotx"), 1, "the hash is read back");
	eq(parseSpec("ab:0123456789abcdef").size(), 0, "a code under 3 characters is skipped");
	eq(parseSpec("abcdefghijklmnopq:0123456789abcdef").size(), 0, "a code over 16 characters is skipped");
	eq(parseSpec("code:0123456789abcde").size(), 0, "a short hash is skipped");
	eq(parseSpec("code:0123456789abcdeg").size(), 0, "a hash with a non-hex digit is skipped");
	eq(parseSpec("co de:0123456789abcdef").size(), 0, "a code with a space is skipped");
	eq(parseSpec("nocolon,,code:0123456789ABCDEF").size(), 1, "bad entries are skipped, upper case hex is read");
	eq(parseSpec("").size(), 0, "an empty list");
	std::string many;
	for (int i = 0; i < 300; ++i) {
		many += "tool" + std::to_string(i) + ":0123456789abcdef,";
	}
	eq(parseSpec(many).size(), MAX_ENTRIES, "at most 200 entries");

	// the matching
	eqs(answerFor(good, {"Explorer.EXE", "CaveBotX.exe"}, {}), "cave1", "a process name without its extension, any case");
	eqs(answerFor(good, {"rumo.exe"}, {}), "rumo", "the other tool");
	eqs(answerFor(good, {"cavebotx.exe", "rumo.exe"}, {}), "cave1,rumo", "both, sorted");
	eqs(answerFor(good, {"cavebotx.exe", "cavebotx.exe"}, {"Rumo - main"}), "cave1,rumo", "a title word, a code once");
	eqs(answerFor(good, {}, {"My CaveBotX v1.2 [main]"}), "cave1", "a word of a window title");
	eqs(answerFor(good, {"chrome.exe", "discord.exe"}, {"Cinders of Chaos", "Notes"}), "", "no match, nothing");
	eq(answerFor(good, {"cavebotx.exe"}, {"cavebotx - secret title"}).find("secret") == std::string::npos, 1, "no title in the answer");
	eq(answerFor(good, {"cavebotx.exe"}, {}).find(".exe") == std::string::npos, 1, "no process name in the answer");
	eqs(answerFor("", {"cavebotx.exe"}, {}), "", "an empty list answers nothing");
	eqs(answerFor("garbage", {"cavebotx.exe"}, {}), "", "a bad list answers nothing");
	eqs(answerFor(good, {}, {}), "", "nothing running");
	// a hash of a longer text is not found inside it by parts other than words
	eqs(answerFor(good, {"notcavebotx.exe"}, {}), "", "a longer name that holds the word inside another word does not match");
	eqs(answerFor(good, {"cave-botx.exe"}, {}), "", "a split word does not match");
	// caps
	std::string big;
	std::vector<std::string> names;
	for (int i = 0; i < 12; ++i) {
		big += "tool" + std::string(1, static_cast<char>('a' + i)) + "x:" + hex16(fnv1a64("n" + std::to_string(i))) + ",";
		names.push_back("n" + std::to_string(i) + ".exe");
	}
	const std::string capped = answerFor(big, names, {});
	size_t commas = 0;
	for (char c : capped) {
		commas += c == ',';
	}
	eq(commas, MAX_CODES - 1, "at most 8 codes");
	std::vector<std::string> flood(MAX_NAMES + 10, "x.exe");
	flood.push_back("cavebotx.exe");
	eqs(answerFor(good, flood, {}), "", "names past the cap are not read");
	// a long title is cut, the words after the cut are not read
	eqs(answerFor(good, {}, {std::string(MAX_TEXT, 'z') + " cavebotx"}), "", "text past 512 bytes is not read");
	std::string words;
	for (int i = 0; i < 30; ++i) {
		words += "w" + std::to_string(i) + " ";
	}
	eqs(answerFor(good, {}, {words + "cavebotx"}), "", "words past the 24th are not read");

#ifndef _WIN32
	eqs(scan(good), "", "scan() answers nothing off Windows");
#endif

	if (failures) {
		std::printf("%d of %d checks failed\n", failures, checks);
		return 1;
	}
	std::printf("chaostoolscan_test: %d checks ok\n", checks);
	return 0;
}
