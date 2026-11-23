// node website/tests/chaos_botmap_ui_test.js : the page script of the staff's bot map (plugins/chaos/assets/js/chaos-botmap.js, O727) run on a fake DOM, a fake
// Leaflet and a fake fetch: it starts the map from the pointer, polls the bots, draws the markers of the floor shown, the roster and the panel (goal, why,
// spot, now, plan, the log with the newest at the bottom), switches floors, follows a bot, shows an error when the site answers "not found", and writes server
// text only as text. No browser, no network. Exit status 0 when every check passes.
'use strict';
const fs = require('fs');
const path = require('path');
const vm = require('vm');
const assetDir = path.join(__dirname, '../overlay/plugins/chaos/assets/js/');

let failed = 0;
function check(ok, what) {
	if (!ok) {
		failed++;
		console.log('FAIL: ' + what);
	}
}

class El {
	constructor(tag) {
		this.tagName = tag;
		this.children = [];
		this.className = '';
		this.hidden = false;
		this._text = '';
		this.handlers = {};
		this.attrs = {};
		this.scrollTop = 0;
		this.scrollHeight = 500;
		this.clientHeight = 200;
		this.checked = false;
		this.removed = false;
	}
	get textContent() { return this._text + this.children.map((c) => c.textContent).join(''); }
	set textContent(v) { this._text = String(v); this.children = []; }
	get lastChild() { return this.children[this.children.length - 1]; }
	appendChild(c) { this.children.push(c); return c; }
	addEventListener(n, f) { (this.handlers[n] = this.handlers[n] || []).push(f); }
	click() { (this.handlers.click || []).forEach((f) => f({})); }
	setAttribute(k, v) { this.attrs[k] = v; }
	getAttribute(k) { return this.attrs[k] === undefined ? null : this.attrs[k]; }
	remove() { this.removed = true; }
}

const ids = ['chaos-botmap', 'chaos-bm-status', 'chaos-bm-floors', 'chaos-bm-follow', 'chaos-bm-map', 'chaos-bm-nomap', 'chaos-bm-roster', 'chaos-bm-panel',
	'chaos-bm-empty', 'chaos-bm-error', 'chaos-bm-p-name', 'chaos-bm-p-class', 'chaos-bm-p-state', 'chaos-bm-p-fields', 'chaos-bm-p-plan', 'chaos-bm-p-noplan',
	'chaos-bm-p-log', 'chaos-bm-p-nolog'];
function makeDom() {
	const byId = {};
	ids.forEach((i) => { byId[i] = new El('div'); });
	byId['chaos-botmap'].attrs = { 'data-endpoint': 'chaos_botmap.php', 'data-poll': '3000' };
	byId['chaos-bm-follow'].tagName = 'input';
	byId['chaos-bm-panel'].hidden = true;
	byId['chaos-bm-nomap'].hidden = true;
	return { byId, document: { hidden: false, getElementById: (i) => byId[i] || null, createElement: (t) => new El(t) } };
}

function makeLeaflet(log) {
	const marker = (ll, opts) => {
		const m = { ll, opts, handlers: {}, z: 0, removed: false };
		m.on = (n, f) => { m.handlers[n] = f; return m; };
		m.addTo = () => { log.markers.push(m); return m; };
		m.setLatLng = (p) => { m.ll = p; };
		m.setZIndexOffset = (z) => { m.z = z; };
		m.remove = () => { m.removed = true; };
		return m;
	};
	const bounds = (a, b) => {
		const pts = Array.isArray(a) && Array.isArray(a[0]) && b === undefined ? a : [a, b];
		return { pts, pad: () => bounds(pts), };
	};
	return {
		CRS: { Simple: {} },
		map: (el, opts) => {
			log.mapOpts = opts;
			const m = { zoom: 2 };
			m.fitBounds = (b, o) => { log.fits.push(b); };
			m.setView = (ll, z) => { log.views.push([ll, z]); m.zoom = z; };
			m.panTo = (ll) => { log.pans.push(ll); };
			m.getZoom = () => m.zoom;
			return m;
		},
		tileLayer: (url, opts) => {
			log.tileOpts = opts;
			const t = { url, addTo: () => t, setUrl: (u) => { t.url = u; log.urls.push(u); } };
			log.tiles = t;
			return t;
		},
		latLngBounds: bounds,
		divIcon: (o) => o,
		marker
	};
}

function reply(status, body) {
	return Promise.resolve({ status, ok: status >= 200 && status < 300, json: () => Promise.resolve(body) });
}

const tick = () => new Promise((r) => setImmediate(r));
async function settle() { for (let i = 0; i < 8; i++) { await tick(); } }

const META = { url: 'botmap-abc', tile: 256, minZoom: 0, maxZoom: 4, span0: 512, origin: [31008, 31008], bbox: [31040, 31040, 33500, 33000],
	floors: [{ z: 7, tiles: 10 }, { z: 8, tiles: 3 }], towns: [{ name: 'Cinderhold', x: 32369, y: 32241, z: 7 }, { name: 'Deep Temple', x: 32400, y: 32300, z: 8 }], built: 1 };
function bot(name, over) {
	return Object.assign({ name, class: 'Ranger', level: 120, pos: [32369, 32241, 7], goal: 'Hunt', goal_since: 1000, why: 'level 120 is inside levels 90-160 of Cave Rats',
		spot: 'Cave Rats (levels 90-160)', now: 'do: hunt ok', plan: ['Keep hunting', 'Trip to town'], log: [[1000, 'first line'], [1090, 'second line'], [1099, 'newest <b>line</b>']],
		t: 1099, age: 1, state: 'live', src: 'py' }, over || {});
}

async function run(opts) {
	const dom = makeDom();
	const log = { markers: [], fits: [], views: [], pans: [], urls: [], timers: [], mapOpts: null };
	const responses = opts.responses;
	const sandbox = {
		window: { ChaosBotMapCore: require(assetDir + 'chaos-botmap-core.js') },
		document: dom.document,
		L: opts.noLeaflet ? undefined : makeLeaflet(log),
		fetch: (url) => { log.fetched = (log.fetched || []).concat([url]); return responses(url); },
		setInterval: (f, ms) => { log.timers.push({ f, ms }); return log.timers.length; },
		Date: { now: () => 1100 * 1000 }, // server clock 1100, the staff's clock the same
		Math, parseInt, Object, Array, JSON, Promise, String, Number, isFinite
	};
	sandbox.window.L = sandbox.L;
	vm.createContext(sandbox);
	vm.runInContext(fs.readFileSync(assetDir + 'chaos-botmap.js', 'utf8'), sandbox, { filename: 'chaos-botmap.js' });
	await settle();
	return { dom, log, by: dom.byId, sandbox };
}

(async () => {
	const bots = [bot('Tester Abc'), bot('Tester Bcd', { goal: 'Town trip', pos: [32390, 32250, 8], state: 'live' }),
		bot('Tester Cde', { goal: 'Check: rift', state: 'stale', age: 300, pos: [32370, 32242, 7] })];
	const server = (url) => {
		if (url.indexOf('a=meta') >= 0) { return reply(200, { ok: true, now: 1100, map: META }); }
		return reply(200, { ok: true, now: 1100, bots, count: 3, stale: 1 });
	};
	const t = await run({ responses: server });
	const L = t.log;

	// start
	check(L.fetched[0] === 'chaos_botmap.php?a=meta' && L.fetched[1] === 'chaos_botmap.php', 'it asks for the map pointer, then the bots: ' + L.fetched);
	check(L.mapOpts && L.mapOpts.minZoom === 0 && L.mapOpts.maxZoom === 6 && L.mapOpts.crs, 'a simple CRS map from zoom 0, two levels of overzoom');
	check(L.tileOpts.maxNativeZoom === 4 && L.tileOpts.tileSize === 256 && L.tileOpts.noWrap === true, 'tiles: 256 px, native up to the top zoom');
	check(L.tiles.url === 'botmap-abc/7/{z}/{x}/{y}.png', 'the floor with most bots (7) is shown: ' + L.tiles.url);
	check(L.fits.length >= 1, 'the map is fitted to the bots');
	check(t.by['chaos-bm-map'].hidden === false && t.by['chaos-bm-nomap'].hidden === true, 'map shown, the no-map note hidden');

	// markers: two bots and the town on floor 7
	const live = L.markers.filter((m) => !m.removed);
	const botMarkers = live.filter((m) => m.opts.title);
	const townMarkers = live.filter((m) => m.opts.interactive === false);
	check(botMarkers.length === 2 && botMarkers.map((m) => m.opts.title).sort().join() === 'Tester Abc,Tester Cde', 'a marker for each bot of floor 7: ' + botMarkers.map((m) => m.opts.title));
	check(townMarkers.length === 1 && townMarkers[0].opts.icon.html.lastChild.textContent === 'Cinderhold', 'the town of floor 7 is labelled');
	const stale = botMarkers.filter((m) => m.opts.title === 'Tester Cde')[0];
	check(stale.opts.icon.html.className.indexOf('is-stale') >= 0 && stale.opts.icon.html.className.indexOf('chaos-bm-mk--check') >= 0, 'a stale bot is greyed, its colour is its goal');
	check(stale.opts.icon.html.lastChild.textContent === 'Tester Cde L120 Check: rift', 'the label under a marker');
	const abc = botMarkers.filter((m) => m.opts.title === 'Tester Abc')[0];
	check(abc.opts.icon.html.className.indexOf('chaos-bm-mk--hunt') >= 0, 'a hunt is red');

	// the floor buttons and the roster
	const fl = t.by['chaos-bm-floors'].children;
	check(fl.length === 2 && fl[0].textContent === 'Ground (7) · 2' && fl[1].textContent === 'Floor 8 · 1' && fl[0].className.indexOf('is-active') >= 0, 'floor buttons with the bots on each: ' + fl.map((x) => x.textContent));
	const rows = t.by['chaos-bm-roster'].children;
	check(rows.length === 3 && rows[0].children[1].textContent === 'Tester Abc' && rows[2].children[1].textContent === 'Tester Cde' && rows[2].className.indexOf('is-stale') >= 0, 'roster: live first, stale last');
	check(rows[1].children[3].textContent === 'Town trip · Floor 8', 'a roster row says its goal and floor');
	check(t.by['chaos-bm-empty'].hidden === true, 'the "no bot" note is hidden with bots');
	check(t.by['chaos-bm-status'].textContent === '2 bots live, 1 stale (greyed, dropped after 10 minutes), updated now', 'status line: ' + t.by['chaos-bm-status'].textContent);
	check(t.by['chaos-bm-panel'].hidden === true, 'no panel until a bot is picked');

	// pick a bot by its marker: the panel
	abc.handlers.click();
	const panel = t.by['chaos-bm-panel'];
	check(panel.hidden === false && t.by['chaos-bm-p-name'].textContent === 'Tester Abc', 'the panel opens with the name');
	check(t.by['chaos-bm-p-class'].textContent === 'Ranger, level 120' && t.by['chaos-bm-p-state'].textContent === 'Live', 'class, level and state');
	const f = t.by['chaos-bm-p-fields'].children;
	check(f.length === 5 && f.map((x) => x.children[0].textContent).join() === 'Position,Goal,Why,Spot,Now', 'the five fields in order');
	check(f[0].children[1].textContent === '32369, 32241, 7 (Ground (7))', 'position with its floor: ' + f[0].children[1].textContent);
	check(f[1].children[1].textContent === 'Hunt, for 1m 40s', 'goal and for how long: ' + f[1].children[1].textContent);
	check(f[2].children[1].textContent.indexOf('level 120 is inside levels 90-160') === 0 && f[3].children[1].textContent === 'Cave Rats (levels 90-160)' && f[4].children[1].textContent === 'do: hunt ok', 'why, spot, now');
	const plan = t.by['chaos-bm-p-plan'].children;
	check(plan.length === 2 && plan[0].textContent === 'Keep hunting' && t.by['chaos-bm-p-noplan'].hidden === true, 'the plan, numbered by the browser (an ol)');
	const lg = t.by['chaos-bm-p-log'].children;
	check(lg.length === 3 && lg[0].children[1].textContent === 'first line' && lg[2].children[1].textContent === 'newest <b>line</b>', 'the log: newest at the bottom; server text kept as text');
	check(lg[0].children[0].textContent === '1m 40s ago' && lg[2].children[0].textContent === 'now' && lg[2].children[0].tagName === 'time', 'with the seconds ago');
	check(t.by['chaos-bm-p-log'].scrollTop === 500, 'the log scrolls to its end for a bot just picked');
	check(t.by['chaos-bm-p-nolog'].hidden === true, 'no "nothing logged" note');
	check(abc.z === 1000 && rows.length === 3, 'the picked marker rises');

	// pick a bot on another floor by the roster: the floor changes
	t.by['chaos-bm-roster'].children[1].click();
	check(L.tiles.url === 'botmap-abc/8/{z}/{x}/{y}.png' && L.urls.length === 1, 'the roster switches the floor to the bot\'s');
	check(t.by['chaos-bm-p-name'].textContent === 'Tester Bcd', 'and opens its panel');
	check(L.views.length >= 1 && L.views[L.views.length - 1][1] === 3, 'it flies to the bot (zoom of the top level - 1)');
	const markers8 = L.markers.filter((m) => !m.removed && m.opts.title);
	check(markers8.length === 1 && markers8[0].opts.title === 'Tester Bcd', 'only the bots of floor 8 are on the map; the others are removed');
	const towns8 = L.markers.filter((m) => !m.removed && m.opts.interactive === false);
	check(towns8.length === 1 && towns8[0].opts.icon.html.lastChild.textContent === 'Deep Temple', 'towns of that floor');
	check(t.by['chaos-bm-floors'].children[1].className.indexOf('is-active') >= 0, 'the floor button follows');

	// a floor button
	t.by['chaos-bm-floors'].children[0].click();
	check(L.tiles.url === 'botmap-abc/7/{z}/{x}/{y}.png', 'a floor button switches the floor');

	// poll: a bot moves, one is gone, the text changes
	const poll = t.log.timers.filter((x) => x.ms === 3000)[0];
	check(!!poll && t.log.timers.some((x) => x.ms === 1000), 'polling every 3 s, a clock tick every second');
	const moved = [bot('Tester Abc', { pos: [32380, 32250, 7], now: 'moved', age: 0, log: [[1100, 'a new line']] })];
	t.sandbox.fetch = (url) => { t.log.fetched.push(url); return reply(200, { ok: true, now: 1103, bots: moved, count: 1, stale: 0 }); };
	poll.f();
	await settle();
	const m7 = L.markers.filter((m) => !m.removed && m.opts.title && m.opts.title === 'Tester Abc');
	check(m7.length === 1 && m7[0].ll[1] > abc.ll[1] - 1, 'the marker of a bot that moved is moved, not made again: ' + m7.length);
	check(t.by['chaos-bm-roster'].children.length === 1, 'the roster follows (two bots gone)');
	check(t.by['chaos-bm-status'].textContent === '1 bot live, updated now', 'status after the poll: ' + t.by['chaos-bm-status'].textContent);
	check(t.by['chaos-bm-panel'].hidden === true, 'the bot picked is gone: the panel closes');

	// follow
	t.by['chaos-bm-follow'].checked = true;
	t.by['chaos-bm-roster'].children[0].click();
	const pansBefore = L.pans.length;
	t.sandbox.fetch = (url) => reply(200, { ok: true, now: 1106, bots: [bot('Tester Abc', { pos: [32390, 32255, 7] })], count: 1, stale: 0 });
	poll.f();
	await settle();
	check(L.pans.length === pansBefore + 1, 'with "follow" the map pans to the bot picked on every poll');

	// errors: not staff, network
	t.sandbox.fetch = () => reply(404, { ok: false, error: 'not_found' });
	poll.f();
	await settle();
	check(t.by['chaos-bm-error'].hidden === false && t.by['chaos-bm-error'].textContent.indexOf('not found') >= 0, 'a 404 says the login ended or the account is not staff');
	t.sandbox.fetch = () => Promise.reject(new Error('offline'));
	poll.f();
	await settle();
	check(t.by['chaos-bm-status'].textContent === 'Cannot reach the site: trying again', 'a network error: trying again');
	t.sandbox.fetch = () => reply(200, { ok: true, now: 1110, bots: [], count: 0, stale: 0 });
	poll.f();
	await settle();
	check(t.by['chaos-bm-error'].hidden === true && t.by['chaos-bm-empty'].hidden === false && t.by['chaos-bm-roster'].children.length === 0, 'back up: the error is gone, an empty list says no bot is running');
	t.sandbox.document.hidden = true;
	const n = t.log.fetched.length;
	poll.f();
	await settle();
	check(t.log.fetched.length === n, 'a hidden tab does not poll');

	// no map built yet: the list works without Leaflet markers
	const t2 = await run({ responses: (url) => url.indexOf('a=meta') >= 0 ? reply(200, { ok: true, now: 1100, map: null }) : reply(200, { ok: true, now: 1100, bots, count: 3, stale: 1 }) });
	check(t2.by['chaos-bm-map'].hidden === true && t2.by['chaos-bm-nomap'].hidden === false && t2.log.markers.length === 0, 'no map: the note shows, no markers');
	check(t2.by['chaos-bm-roster'].children.length === 3, 'no map: the roster still lists the bots');
	t2.by['chaos-bm-roster'].children[0].click();
	check(t2.by['chaos-bm-panel'].hidden === false && t2.by['chaos-bm-p-name'].textContent === 'Tester Abc', 'no map: the panel still opens');

	// the staff page says not found from the first call
	const t3 = await run({ responses: () => reply(404, { ok: false }) });
	check(t3.by['chaos-bm-error'].hidden === false, 'not staff: the error at once');

	// source rules
	const src = fs.readFileSync(assetDir + 'chaos-botmap.js', 'utf8');
	check(!/innerHTML|insertAdjacentHTML|document\.write|eval\(/.test(src), 'no HTML injection, no eval');

	if (failed) {
		console.log('chaos_botmap_ui_test: ' + failed + ' FAILED');
		process.exit(1);
	}
	console.log('chaos_botmap_ui_test: OK');
})().catch((e) => {
	console.log('chaos_botmap_ui_test: crashed: ' + (e && e.stack || e));
	process.exit(1);
});
