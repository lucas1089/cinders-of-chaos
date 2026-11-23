/*
 * The staff's live map of our tester bots (pages/botmap.php; O727; website/README.md "Bot live map (O727)").
 * Leaflet (cdnjs, pinned) on a simple CRS draws the tile pyramid of server/tools/gen_bot_map_tiles.py; every 3 seconds the script asks
 * /chaos_botmap.php for the bots and moves their markers. Click a marker or a name: the panel shows the bot's goal, why, spot, now, plan and last log.
 * Everything that comes from the server goes to the screen with textContent, never as HTML. The pure parts are chaos-botmap-core.js.
 */
(function () {
	'use strict';
	var C = window.ChaosBotMapCore;
	var root = document.getElementById('chaos-botmap');
	if (!root || !C) {
		return;
	}
	var endpoint = root.getAttribute('data-endpoint') || 'chaos_botmap.php';
	var pollMs = Math.max(1000, parseInt(root.getAttribute('data-poll'), 10) || 3000);
	var $ = function (id) { return document.getElementById(id); };
	var el = {
		status: $('chaos-bm-status'), floors: $('chaos-bm-floors'), follow: $('chaos-bm-follow'), map: $('chaos-bm-map'), nomap: $('chaos-bm-nomap'),
		roster: $('chaos-bm-roster'), panel: $('chaos-bm-panel'), empty: $('chaos-bm-empty'), error: $('chaos-bm-error')
	};

	var state = {
		meta: null, map: null, tiles: null, floor: null, wantedFloor: null, bots: [], selected: null, markers: {}, townMarkers: [],
		serverNow: 0, recvAt: 0, okAt: 0, failing: false, logKey: '', polling: false
	};

	function make(tag, cls, text) {
		var e = document.createElement(tag);
		if (cls) {
			e.className = cls;
		}
		if (text !== undefined && text !== null) {
			e.textContent = text;
		}
		return e;
	}

	/** server seconds now: the answer's clock plus the time since it came (the staff's own clock is never compared with the bots') */
	function now() {
		return state.serverNow + (Date.now() - state.recvAt) / 1000;
	}

	function selectedBot() {
		return state.bots.filter(function (b) { return b.name === state.selected; })[0] || null;
	}

	// ------------------------------------------------------------------ the map
	function startMap(meta) {
		state.meta = meta;
		var b = C.bounds(meta);
		var map = L.map(el.map, {
			crs: L.CRS.Simple, minZoom: meta.minZoom, maxZoom: meta.maxZoom + 2, zoomSnap: 0.5, zoomDelta: 1, attributionControl: false,
			maxBounds: L.latLngBounds(b[0], b[1]).pad(0.4), maxBoundsViscosity: 0.7, zoomControl: true
		});
		state.map = map;
		state.floor = C.pickFloor(meta, state.bots, state.wantedFloor, state.selected);
		state.tiles = L.tileLayer(C.tileUrl(meta, state.floor), {
			tileSize: C.TILE, minZoom: meta.minZoom, maxZoom: meta.maxZoom + 2, maxNativeZoom: meta.maxZoom, noWrap: true, bounds: L.latLngBounds(b[0], b[1]),
			errorTileUrl: 'data:image/gif;base64,R0lGODlhAQABAAAAACH5BAEKAAEALAAAAAABAAEAAAICTAEAOw==', keepBuffer: 4, className: 'chaos-bm__tile'
		}).addTo(map);
		map.fitBounds(L.latLngBounds(b[0], b[1]));
		var here = C.onFloor(state.bots, state.floor);
		if (here.length) {
			var pts = here.map(function (x) { return C.toLatLng(meta, x.pos[0], x.pos[1]); });
			map.fitBounds(L.latLngBounds(pts).pad(0.6), { maxZoom: meta.maxZoom });
		}
		buildFloors();
		drawTowns();
		el.nomap.hidden = true;
		el.map.hidden = false;
	}

	function drawTowns() {
		state.townMarkers.forEach(function (m) { m.remove(); });
		state.townMarkers = [];
		if (!state.map) {
			return;
		}
		(state.meta.towns || []).forEach(function (t) {
			if (t.z !== state.floor) {
				return;
			}
			var box = make('div', 'chaos-bm-town');
			box.appendChild(make('span', 'chaos-bm-town__rune'));
			box.appendChild(make('span', 'chaos-bm-town__name', t.name));
			var m = L.marker(C.toLatLng(state.meta, t.x, t.y), {
				icon: L.divIcon({ className: 'chaos-bm-town-icon', html: box, iconSize: [0, 0] }), interactive: false, keyboard: false, zIndexOffset: -500
			}).addTo(state.map);
			state.townMarkers.push(m);
		});
	}

	function setFloor(z) {
		state.wantedFloor = z;
		if (!state.meta || z === state.floor) {
			return;
		}
		state.floor = z;
		state.tiles.setUrl(C.tileUrl(state.meta, z));
		drawTowns();
		syncMarkers();
		buildFloors();
	}

	function buildFloors() {
		el.floors.textContent = '';
		if (!state.meta) {
			return;
		}
		var counts = C.countByFloor(state.bots);
		state.meta.floors.slice().sort(function (a, b) { return a.z - b.z; }).forEach(function (f) {
			var btn = make('button', 'chaos-tab' + (f.z === state.floor ? ' is-active' : ''), C.floorLabel(f.z) + (counts[f.z] ? ' · ' + counts[f.z] : ''));
			btn.type = 'button';
			btn.setAttribute('aria-pressed', f.z === state.floor ? 'true' : 'false');
			btn.addEventListener('click', function () { setFloor(f.z); });
			el.floors.appendChild(btn);
		});
	}

	// ------------------------------------------------------------------ markers
	function markerBox(bot) {
		var box = make('div', 'chaos-bm-mk');
		box.appendChild(make('span', 'chaos-bm-mk__sig'));
		box.appendChild(make('span', 'chaos-bm-mk__lbl'));
		paintMarker(box, bot);
		return box;
	}

	function paintMarker(box, bot) {
		box.className = 'chaos-bm-mk chaos-bm-mk--' + C.goalKind(bot.goal) + (bot.state === 'stale' ? ' is-stale' : '') + (bot.name === state.selected ? ' is-selected' : '');
		box.lastChild.textContent = C.markerLabel(bot);
	}

	function syncMarkers() {
		if (!state.map) {
			return;
		}
		var visible = {};
		C.onFloor(state.bots, state.floor).forEach(function (bot) {
			visible[bot.name] = true;
			var ll = C.toLatLng(state.meta, bot.pos[0], bot.pos[1]);
			var m = state.markers[bot.name];
			if (!m) {
				var box = markerBox(bot);
				m = L.marker(ll, { icon: L.divIcon({ className: 'chaos-bm-mk-icon', html: box, iconSize: [0, 0] }), title: bot.name, keyboard: true, riseOnHover: true });
				m.on('click', function () { select(bot.name, false); });
				m.addTo(state.map);
				m._box = box;
				state.markers[bot.name] = m;
			} else {
				m.setLatLng(ll);
				paintMarker(m._box, bot);
			}
			m.setZIndexOffset(bot.name === state.selected ? 1000 : (bot.state === 'stale' ? -200 : 0));
		});
		Object.keys(state.markers).forEach(function (name) {
			if (!visible[name]) {
				state.markers[name].remove();
				delete state.markers[name];
			}
		});
	}

	// ------------------------------------------------------------------ roster and panel
	function drawRoster() {
		el.roster.textContent = '';
		C.sortBots(state.bots).forEach(function (bot) {
			var row = make('button', 'chaos-bm-row' + (bot.state === 'stale' ? ' is-stale' : '') + (bot.name === state.selected ? ' is-selected' : ''));
			row.type = 'button';
			row.appendChild(make('span', 'chaos-bm-row__dot chaos-bm-mk--' + C.goalKind(bot.goal)));
			row.appendChild(make('span', 'chaos-bm-row__name', bot.name));
			row.appendChild(make('span', 'chaos-bm-row__meta', 'L' + bot.level + (bot.class ? ' ' + bot.class : '')));
			row.appendChild(make('span', 'chaos-bm-row__goal', (bot.goal || '-') + (bot.pos ? ' · ' + C.floorLabel(bot.pos[2]) : '')));
			row.addEventListener('click', function () { select(bot.name, true); });
			el.roster.appendChild(row);
		});
		el.empty.hidden = state.bots.length > 0;
	}

	function select(name, fly) {
		state.selected = name;
		state.logKey = '';
		var bot = selectedBot();
		if (bot && bot.pos && state.meta) {
			if (C.floorOf(bot) !== state.floor) {
				setFloor(C.floorOf(bot));
			}
			if (fly || el.follow.checked) {
				state.map.setView(C.toLatLng(state.meta, bot.pos[0], bot.pos[1]), Math.max(state.map.getZoom(), state.meta.maxZoom - 1));
			}
		}
		syncMarkers();
		drawRoster();
		drawPanel();
	}

	function field(label, value, cls) {
		var d = make('div', 'chaos-bm-f' + (cls ? ' ' + cls : ''));
		d.appendChild(make('dt', null, label));
		d.appendChild(make('dd', null, value || '-'));
		return d;
	}

	function drawPanel() {
		var bot = selectedBot();
		el.panel.hidden = !bot;
		if (!bot) {
			return;
		}
		var t = now();
		$('chaos-bm-p-name').textContent = bot.name;
		$('chaos-bm-p-class').textContent = (bot.class || 'unknown class') + ', level ' + bot.level;
		var st = $('chaos-bm-p-state');
		st.textContent = bot.state === 'stale' ? 'No news for ' + C.ago(bot.age + (t - state.serverNow)).replace(' ago', '') : 'Live';
		st.className = 'chaos-bm-tag' + (bot.state === 'stale' ? ' is-stale' : '');
		var dl = $('chaos-bm-p-fields');
		dl.textContent = '';
		dl.appendChild(field('Position', C.posText(bot) + (bot.pos ? ' (' + C.floorLabel(bot.pos[2]) + ')' : '')));
		dl.appendChild(field('Goal', (bot.goal || '-') + (bot.goal_since ? ', for ' + C.goalFor(bot, t) : '')));
		dl.appendChild(field('Why', bot.why));
		dl.appendChild(field('Spot', bot.spot));
		dl.appendChild(field('Now', bot.now));
		var plan = $('chaos-bm-p-plan');
		plan.textContent = '';
		(bot.plan || []).forEach(function (s) { plan.appendChild(make('li', null, s)); });
		$('chaos-bm-p-noplan').hidden = (bot.plan || []).length > 0;
		var log = $('chaos-bm-p-log');
		var atEnd = log.scrollHeight - log.scrollTop - log.clientHeight < 24;
		var top = log.scrollTop;
		log.textContent = '';
		C.logRows(bot, t).forEach(function (r) {
			var li = make('li');
			li.appendChild(make('time', null, r.ago));
			li.appendChild(make('span', null, r.text));
			log.appendChild(li);
		});
		// newest at the bottom: it follows the end of the list, and stays where it is when the staff scrolled up to read
		log.scrollTop = (atEnd || state.logKey !== bot.name) ? log.scrollHeight : top;
		state.logKey = bot.name;
		$('chaos-bm-p-nolog').hidden = (bot.log || []).length > 0;
	}

	function drawStatus() {
		if (state.failing) {
			el.status.textContent = 'Cannot reach the site: trying again';
			return;
		}
		if (!state.okAt) {
			el.status.textContent = 'Loading';
			return;
		}
		el.status.textContent = C.summary(state.bots, (Date.now() - state.okAt) / 1000);
	}

	function fail(text) {
		el.error.textContent = text;
		el.error.hidden = !text;
	}

	// ------------------------------------------------------------------ polling
	function get(query) {
		return fetch(endpoint + query, { credentials: 'same-origin', cache: 'no-store', headers: { 'Accept': 'application/json' } }).then(function (r) {
			if (r.status === 404) {
				throw new Error('gone');
			}
			if (!r.ok) {
				throw new Error('http ' + r.status);
			}
			return r.json();
		});
	}

	function take(d) {
		state.serverNow = d.now;
		state.recvAt = Date.now();
		state.okAt = Date.now();
		state.failing = false;
		fail('');
		state.bots = d.bots || [];
		if (state.selected && !selectedBot()) {
			state.selected = null;
		}
		if (state.map) {
			var follow = selectedBot();
			if (el.follow.checked && follow && follow.pos) {
				if (C.floorOf(follow) !== state.floor) {
					setFloor(C.floorOf(follow));
				}
				state.map.panTo(C.toLatLng(state.meta, follow.pos[0], follow.pos[1]), { animate: true, duration: 0.8 });
			}
			syncMarkers();
			buildFloors();
		}
		drawRoster();
		drawPanel();
		drawStatus();
	}

	function poll() {
		if (document.hidden || state.polling) {
			return;
		}
		state.polling = true;
		get('').then(take).catch(function (e) {
			if (e && e.message === 'gone') {
				fail('The map says "not found": your login ended or this account is not staff. Log in again.');
			} else {
				state.failing = true;
			}
			drawStatus();
		}).then(function () { state.polling = false; });
	}

	function init() {
		el.follow.addEventListener('change', function () {
			if (el.follow.checked && selectedBot()) {
				select(state.selected, true);
			}
		});
		get('?a=meta').then(function (d) {
			if (d.map && typeof L !== 'undefined') {
				state.serverNow = d.now;
				state.recvAt = Date.now();
				return get('').then(function (b) {
					state.bots = b.bots || [];
					startMap(d.map);
					take(b);
				});
			}
			el.map.hidden = true;
			el.nomap.hidden = false;
			return get('').then(take);
		}).catch(function (e) {
			fail(e && e.message === 'gone' ? 'The map says "not found": your login ended or this account is not staff. Log in again.' : 'Cannot load the map: ' + (e && e.message));
		}).then(function () {
			setInterval(poll, pollMs);
			// the ages tick between two answers
			setInterval(function () { drawPanel(); drawStatus(); }, 1000);
		});
	}

	init();
}());
