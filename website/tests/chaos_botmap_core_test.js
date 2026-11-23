// node website/tests/chaos_botmap_core_test.js : the pure parts of the staff's bot map (plugins/chaos/assets/js/chaos-botmap-core.js, O727): the tile maths
// (the same vector as server/tools/gen_bot_map_tiles_test.py), the times, the floor choice, the order of the roster, the goal colours, the log rows, the
// status line. No DOM, no Leaflet, no network. Exit status 0 when every check passes.
'use strict';
const path = require('path');
const C = require(path.join(__dirname, '../overlay/plugins/chaos/assets/js/chaos-botmap-core.js'));

let failed = 0;
function check(ok, what) {
	if (!ok) {
		failed++;
		console.log('FAIL: ' + what);
	}
}
function near(a, b) {
	return Math.abs(a - b) < 1e-9;
}
function same(a, b) {
	return JSON.stringify(a) === JSON.stringify(b);
}

// the geometry of the tile build: origin 992, 1984; 3 levels: span0 = 32 * 2^2 = 128 (the vector of gen_bot_map_tiles_test.py)
const meta = { url: 'botmap-abc', origin: [992, 1984], span0: 128, minZoom: 0, maxZoom: 2, bbox: [1000, 2000, 1039, 2039],
	floors: [{ z: 7, tiles: 10 }, { z: 8, tiles: 3 }], towns: [] };

let ll = C.toLatLng(meta, 1000, 2000);
check(near(ll[0], -(2000.5 - 1984) / 128) && near(ll[1], (1000.5 - 992) / 128), 'toLatLng of the shared vector: ' + ll);
check(near(ll[0], -0.12890625) && near(ll[1], 0.06640625), 'toLatLng, the numbers the python test holds');
ll = C.toLatLng(meta, 992, 1984);
check(near(ll[0], -0.5 / 128) && near(ll[1], 0.5 / 128), 'the origin tile is next to the corner');
const back = C.fromLatLng(meta, ll[0], ll[1]);
check(back.x === 992 && back.y === 1984, 'fromLatLng undoes toLatLng');
for (const [x, y] of [[1000, 2000], [1039, 2039], [1500, 2500], [992, 1984]]) {
	const p = C.toLatLng(meta, x, y);
	const q = C.fromLatLng(meta, p[0], p[1]);
	check(q.x === x && q.y === y, 'round trip ' + x + ',' + y);
}
// a game tile lies in the tile the build wrote: at zoom 2 a tile is 32 game tiles, at zoom 0 128
const z2 = C.toLatLng(meta, 992 + 33, 1984 + 1);
check(Math.floor(z2[1] * Math.pow(2, 2)) === 1 && Math.floor(-z2[0] * Math.pow(2, 2)) === 0, 'tile x=1 y=0 at zoom 2 for game tile origin + (33, 1)');
check(Math.floor(z2[1] * Math.pow(2, 0)) === 0, 'tile x=0 at zoom 0');
check(C.tileUrl(meta, 7) === 'botmap-abc/7/{z}/{x}/{y}.png' && C.tileUrl({ url: 'a/b/' }, 8) === 'a/b/8/{z}/{x}/{y}.png', 'tile url template');
const b = C.bounds(meta);
check(b[0][0] < b[1][0] && b[0][1] < b[1][1] && b[0][0] < -(2039 - 1984) / 128 && b[1][1] > (1039 - 992) / 128, 'bounds hold the drawn world with a margin: ' + JSON.stringify(b));

// times
check(C.ago(0) === 'now' && C.ago(1) === 'now' && C.ago(2) === '2s ago' && C.ago(59.9) === '59s ago', 'ago, seconds');
check(C.ago(60) === '1m 00s ago' && C.ago(125) === '2m 05s ago' && C.ago(3599) === '59m 59s ago', 'ago, minutes');
check(C.ago(3600) === '1h 00m ago' && C.ago(3725) === '1h 02m ago', 'ago, hours');
check(C.ago(-5) === 'now' && C.ago(NaN) === 'now' && C.ago(undefined) === 'now' && C.ago('x') === 'now', 'ago, bad input');
check(C.span(0) === '0s' && C.span(12) === '12s' && C.span(725) === '12m 05s' && C.span(3780) === '1h 03m' && C.span(-1) === '0s' && C.span(null) === '0s', 'span');

// floors
const bots = [
	{ name: 'Tester Abc', state: 'live', pos: [1, 2, 7], level: 10, goal: 'Hunt' },
	{ name: 'Tester Bcd', state: 'live', pos: [1, 2, 8], level: 11, goal: 'Town trip' },
	{ name: 'Tester Cde', state: 'stale', pos: [1, 2, 8], level: 12, goal: 'Check: rift' },
	{ name: 'Tester Def', state: 'live', pos: null, level: 13, goal: '' }
];
check(same(C.countByFloor(bots), { 7: 1, 8: 2 }), 'bots per floor, none for a bot without a position');
check(C.onFloor(bots, 8).length === 2 && C.onFloor(bots, 9).length === 0, 'bots on a floor');
check(C.pickFloor(meta, bots, 7, null) === 7, 'the floor asked for');
check(C.pickFloor(meta, bots, 3, null) === 8, 'a floor the map has not: the one with most bots');
check(C.pickFloor(meta, bots, null, 'Tester Abc') === 7, 'the floor of the bot picked');
check(C.pickFloor(meta, [], null, null) === 7, 'no bots: the ground floor');
check(C.pickFloor({ floors: [{ z: 9 }] }, [], null, null) === 9 && C.pickFloor(null, [], null, null) === 7, 'no ground floor: the first; no map: 7');
check(C.floorLabel(7) === 'Ground (7)' && C.floorLabel(9) === 'Floor 9', 'floor labels');

// roster
check(same(C.sortBots(bots).map(function (x) { return x.name; }), ['Tester Abc', 'Tester Bcd', 'Tester Def', 'Tester Cde']), 'live before stale, then by name');
check(bots[0].name === 'Tester Abc' && bots[3].name === 'Tester Def', 'the list is not changed in place');

// goals and labels
check(C.goalKind('Hunt') === 'hunt' && C.goalKind('Town trip') === 'town' && C.goalKind('Back to town') === 'town' && C.goalKind('Depot') === 'town', 'goal kinds: hunt and town');
check(C.goalKind('Check: rift') === 'check' && C.goalKind('System checks') === 'check' && C.goalKind('Journey') === 'walk' && C.goalKind('Walk to a hunt') === 'walk', 'goal kinds: check and walk');
check(C.goalKind('') === 'other' && C.goalKind(null) === 'other' && C.goalKind('Party') === 'other', 'goal kinds: other');
check(C.markerLabel(bots[0]) === 'Tester Abc L10 Hunt' && C.markerLabel(bots[3]) === 'Tester Def L13', 'marker label');
check(C.posText(bots[0]) === '1, 2, 7' && C.posText(bots[3]) === 'not known yet', 'position text');

// the log: oldest first, newest at the bottom, with the age
const bot = { log: [[1000, 'a'], [1090, 'b'], [1099, 'c']], goal_since: 400 };
const rows = C.logRows(bot, 1100);
check(rows.length === 3 && rows[0].text === 'a' && rows[2].text === 'c' && rows[0].ago === '1m 40s ago' && rows[2].ago === 'now', 'log rows keep their order with their age: ' + JSON.stringify(rows));
check(rows[1].ago === '10s ago', 'seconds ago of a line');
check(C.logRows({}, 5).length === 0, 'no log, no rows');
check(C.goalFor(bot, 1100) === '11m 40s' && C.goalFor({}, 1100) === '', 'how long the goal has gone on');

// status line
check(C.summary(bots.slice(0, 2), 0) === '2 bots live, updated now', 'summary: all live');
check(C.summary([bots[0]], 5) === '1 bot live, updated 5s ago', 'summary: one bot');
check(C.summary(bots, 3).indexOf('3 bots live, 1 stale (greyed, dropped after 10 minutes)') === 0, 'summary: with a stale one');

// what changed
const d = C.diff(['Tester Abc', 'Tester Zzz'], bots);
check(same(d.add, ['Tester Bcd', 'Tester Cde', 'Tester Def']) && same(d.remove, ['Tester Zzz']), 'diff of two lists');

if (failed) {
	console.log('chaos_botmap_core_test: ' + failed + ' FAILED');
	process.exit(1);
}
console.log('chaos_botmap_core_test: OK');
