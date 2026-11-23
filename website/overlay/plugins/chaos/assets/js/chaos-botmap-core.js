/*
 * The pure parts of the staff's bot map (pages/botmap.php; O727). No DOM, no Leaflet: the tile maths, the times, the order of the lists and the rows of the
 * log panel, tested by website/tests/chaos_botmap_core_test.js with node. The Python twin of the tile maths is server/tools/gen_bot_map_tiles.py
 * (to_latlng, tile_of); both read the same meta.json of the tile build.
 *
 * Geometry: Leaflet's simple CRS has 256 px for one map unit at zoom 0. The tile build puts game tile (x, y) at
 *   lng = (x - origin.x) / span0, lat = -(y - origin.y) / span0     (span0 = game tiles a tile covers at zoom 0)
 * so tile (tx, ty) at zoom z is the square lng [tx, tx + 1] / 2^z, lat [-(ty + 1), -ty] / 2^z, and a floor's tiles are <url>/<floor>/<z>/<tx>/<ty>.png.
 */
(function (root, factory) {
	if (typeof module === 'object' && module.exports) {
		module.exports = factory();
	} else {
		root.ChaosBotMapCore = factory();
	}
}(typeof self !== 'undefined' ? self : this, function () {
	'use strict';

	var TILE = 256;
	var GROUND_FLOOR = 7;

	function toLatLng(meta, x, y) {
		return [-(y + 0.5 - meta.origin[1]) / meta.span0, (x + 0.5 - meta.origin[0]) / meta.span0];
	}

	function fromLatLng(meta, lat, lng) {
		return { x: Math.floor(lng * meta.span0 + meta.origin[0]), y: Math.floor(-lat * meta.span0 + meta.origin[1]) };
	}

	/** the corners [[south, west], [north, east]] of the drawn world, a little tile of margin all round */
	function bounds(meta) {
		var b = meta.bbox, pad = 8;
		return [toLatLng(meta, b[0] - pad, b[3] + pad), toLatLng(meta, b[2] + pad, b[1] - pad)];
	}

	function tileUrl(meta, floor) {
		return meta.url.replace(/\/+$/, '') + '/' + floor + '/{z}/{x}/{y}.png';
	}

	function floorLabel(z) {
		return z === GROUND_FLOOR ? 'Ground (7)' : 'Floor ' + z;
	}

	function pad2(n) {
		return n < 10 ? '0' + n : String(n);
	}

	/** "now", "5s ago", "2m 05s ago", "1h 03m ago"; a negative or missing number is "now" */
	function ago(sec) {
		if (typeof sec !== 'number' || !isFinite(sec) || sec < 2) {
			return 'now';
		}
		sec = Math.floor(sec);
		if (sec < 60) {
			return sec + 's ago';
		}
		if (sec < 3600) {
			return Math.floor(sec / 60) + 'm ' + pad2(sec % 60) + 's ago';
		}
		return Math.floor(sec / 3600) + 'h ' + pad2(Math.floor((sec % 3600) / 60)) + 'm ago';
	}

	/** "12s", "12m 05s", "1h 03m": how long something has gone on */
	function span(sec) {
		if (typeof sec !== 'number' || !isFinite(sec) || sec < 0) {
			return '0s';
		}
		sec = Math.floor(sec);
		if (sec < 60) {
			return sec + 's';
		}
		if (sec < 3600) {
			return Math.floor(sec / 60) + 'm ' + pad2(sec % 60) + 's';
		}
		return Math.floor(sec / 3600) + 'h ' + pad2(Math.floor((sec % 3600) / 60)) + 'm';
	}

	function floorOf(bot) {
		return bot && bot.pos ? bot.pos[2] : null;
	}

	/** the bots on a floor */
	function onFloor(bots, z) {
		return bots.filter(function (b) { return floorOf(b) === z; });
	}

	/** {floor: count} of the bots with a position */
	function countByFloor(bots) {
		var out = {};
		bots.forEach(function (b) {
			var z = floorOf(b);
			if (z !== null) {
				out[z] = (out[z] || 0) + 1;
			}
		});
		return out;
	}

	/** the floor to show: the one asked for if the map has it, else the floor of the bot picked, else the floor with most bots, else the ground floor, else the first */
	function pickFloor(meta, bots, wanted, selected) {
		var have = (meta && meta.floors ? meta.floors : []).map(function (f) { return f.z; });
		if (wanted !== null && wanted !== undefined && have.indexOf(wanted) >= 0) {
			return wanted;
		}
		var sel = bots.filter(function (b) { return b.name === selected; })[0];
		if (sel && floorOf(sel) !== null && have.indexOf(floorOf(sel)) >= 0) {
			return floorOf(sel);
		}
		var counts = countByFloor(bots), best = null;
		have.forEach(function (z) {
			if (counts[z] && (best === null || counts[z] > counts[best])) {
				best = z;
			}
		});
		if (best !== null) {
			return best;
		}
		return have.indexOf(GROUND_FLOOR) >= 0 ? GROUND_FLOOR : (have.length ? have[0] : GROUND_FLOOR);
	}

	/** the order of the roster: live before stale, then by name */
	function sortBots(bots) {
		return bots.slice().sort(function (a, b) {
			if (a.state !== b.state) {
				return a.state === 'live' ? -1 : 1;
			}
			return a.name < b.name ? -1 : a.name > b.name ? 1 : 0;
		});
	}

	/** the css class of a goal: what colour its marker has (hunt, town, check, walk, other) */
	function goalKind(goal) {
		var g = String(goal || '').toLowerCase();
		if (g.indexOf('hunt') === 0) {
			return 'hunt';
		}
		if (/^(town|depot|shop|bag|loot|back to town)/.test(g)) {
			return 'town';
		}
		if (/^(check|system|keystones)/.test(g)) {
			return 'check';
		}
		if (/^(journey|walk|wander|start|wait)/.test(g)) {
			return 'walk';
		}
		return 'other';
	}

	/** the one line under a marker */
	function markerLabel(bot) {
		return bot.name + ' L' + bot.level + (bot.goal ? ' ' + bot.goal : '');
	}

	/** rows of the log panel, oldest first (the newest is at the bottom): {ago, text} with the age at `now` (server seconds) */
	function logRows(bot, now) {
		return (bot.log || []).map(function (l) {
			return { ago: ago(now - l[0]), text: l[1] };
		});
	}

	/** how long the bot has pursued its goal, at `now` */
	function goalFor(bot, now) {
		return bot.goal_since ? span(now - bot.goal_since) : '';
	}

	/** the position as text: "32369, 32241, 7" */
	function posText(bot) {
		return bot.pos ? bot.pos.join(', ') : 'not known yet';
	}

	/** the status line over the map */
	function summary(bots, ageSec) {
		var stale = bots.filter(function (b) { return b.state === 'stale'; }).length;
		var live = bots.length - stale;
		var t = live + (live === 1 ? ' bot' : ' bots') + ' live';
		if (stale) {
			t += ', ' + stale + ' stale (greyed, dropped after 10 minutes)';
		}
		return t + ', updated ' + (ageSec < 2 ? 'now' : ago(ageSec));
	}

	/** which names are new, gone and kept between two lists */
	function diff(prevNames, bots) {
		var now = {};
		bots.forEach(function (b) { now[b.name] = true; });
		var prev = {};
		prevNames.forEach(function (n) { prev[n] = true; });
		return {
			add: bots.map(function (b) { return b.name; }).filter(function (n) { return !prev[n]; }),
			remove: prevNames.filter(function (n) { return !now[n]; })
		};
	}

	return {
		TILE: TILE, GROUND_FLOOR: GROUND_FLOOR,
		toLatLng: toLatLng, fromLatLng: fromLatLng, bounds: bounds, tileUrl: tileUrl, floorLabel: floorLabel,
		ago: ago, span: span, floorOf: floorOf, onFloor: onFloor, countByFloor: countByFloor, pickFloor: pickFloor, sortBots: sortBots,
		goalKind: goalKind, markerLabel: markerLabel, logRows: logRows, goalFor: goalFor, posText: posText, summary: summary, diff: diff
	};
}));
