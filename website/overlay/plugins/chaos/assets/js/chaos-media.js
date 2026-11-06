// Cinders of Chaos: the front page trailer and the screenshot lightbox (plugins/chaos/media_lib.php, O425).
// Trailer: video[data-chaos-trailer] has its controls in the markup (no script: a normal player). With script it plays
// muted and looped while it is on screen, without controls, unless the visitor asked for less motion or less data;
// a click gives it sound and controls and starts it over. Screenshots: a[data-chaos-shot] opens a lightbox (arrows,
// Escape, swipe, a click outside closes); the links still open the picture without script.
// No inline script and no library (the site's Content-Security-Policy).
(function () {
	'use strict';

	function lessMotionOrData() {
		try {
			if (window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches) {
				return true;
			}
		} catch (e) {
			// ignore
		}
		var c = navigator.connection;
		return !!(c && (c.saveData || /(^|-)2g$/.test(String(c.effectiveType || ''))));
	}

	function setUpTrailer(video) {
		if (video.getAttribute('data-chaos-ready') === '1') {
			return;
		}
		video.setAttribute('data-chaos-ready', '1');
		if (lessMotionOrData() || typeof video.play !== 'function') {
			return;
		}
		var asked = false;
		video.removeAttribute('controls');
		video.preload = 'auto';
		video.classList.add('is-hero');
		function tryPlay() {
			var p = video.play();
			if (p && typeof p.catch === 'function') {
				p.catch(function () {
					// autoplay refused: give the controls back
					video.setAttribute('controls', '');
					video.classList.remove('is-hero');
				});
			}
		}
		if ('IntersectionObserver' in window) {
			new IntersectionObserver(function (entries) {
				entries.forEach(function (e) {
					if (asked) {
						return;
					}
					if (e.isIntersecting) {
						tryPlay();
					} else {
						video.pause();
					}
				});
			}, { threshold: 0.4 }).observe(video);
		} else {
			tryPlay();
		}
		video.addEventListener('click', function () {
			if (asked) {
				return;
			}
			asked = true;
			video.classList.remove('is-hero');
			video.setAttribute('controls', '');
			video.muted = false;
			video.currentTime = 0;
			tryPlay();
		});
	}

	var box = null;
	var img = null;
	var cap = null;
	var links = [];
	var index = 0;
	var opener = null;
	var touchX = null;

	function build() {
		if (box) {
			return;
		}
		box = document.createElement('div');
		box.className = 'chaos-lightbox';
		box.setAttribute('role', 'dialog');
		box.setAttribute('aria-modal', 'true');
		box.hidden = true;
		box.innerHTML = '<figure class="chaos-lightbox__fig"><img class="chaos-lightbox__img" alt=""><figcaption class="chaos-lightbox__cap"></figcaption></figure>'
			+ '<button type="button" class="chaos-lightbox__btn chaos-lightbox__close" aria-label="Close">&times;</button>'
			+ '<button type="button" class="chaos-lightbox__btn chaos-lightbox__prev" aria-label="Previous">&#8249;</button>'
			+ '<button type="button" class="chaos-lightbox__btn chaos-lightbox__next" aria-label="Next">&#8250;</button>';
		document.body.appendChild(box);
		img = box.querySelector('.chaos-lightbox__img');
		cap = box.querySelector('.chaos-lightbox__cap');
		box.addEventListener('click', function (e) {
			var t = e.target;
			if (t.classList.contains('chaos-lightbox__prev')) {
				show(index - 1);
			} else if (t.classList.contains('chaos-lightbox__next')) {
				show(index + 1);
			} else if (t !== img && t !== cap) {
				close();
			}
		});
		box.addEventListener('touchstart', function (e) {
			touchX = e.changedTouches.length ? e.changedTouches[0].clientX : null;
		}, { passive: true });
		box.addEventListener('touchend', function (e) {
			if (touchX === null || !e.changedTouches.length) {
				return;
			}
			var dx = e.changedTouches[0].clientX - touchX;
			touchX = null;
			if (Math.abs(dx) > 50) {
				show(index + (dx < 0 ? 1 : -1));
			}
		}, { passive: true });
		document.addEventListener('keydown', function (e) {
			if (box.hidden) {
				return;
			}
			if (e.key === 'Escape') {
				close();
			} else if (e.key === 'ArrowLeft') {
				show(index - 1);
			} else if (e.key === 'ArrowRight') {
				show(index + 1);
			} else if (e.key === 'Tab') {
				// keep the focus on the three buttons
				var btns = box.querySelectorAll('button');
				var first = btns[0];
				var last = btns[btns.length - 1];
				if (e.shiftKey && document.activeElement === first) {
					e.preventDefault();
					last.focus();
				} else if (!e.shiftKey && document.activeElement === last) {
					e.preventDefault();
					first.focus();
				}
			}
		});
	}

	function show(i) {
		index = (i + links.length) % links.length;
		var a = links[index];
		img.src = a.getAttribute('href');
		var thumb = a.querySelector('img');
		img.alt = thumb ? thumb.alt : '';
		cap.textContent = (a.getAttribute('data-caption') || '') + '  (' + (index + 1) + '/' + links.length + ')';
	}

	function open(a) {
		build();
		links = Array.prototype.slice.call(document.querySelectorAll('a[data-chaos-shot]'));
		opener = a;
		var sec = a.closest ? a.closest('.chaos-gallery') : null;
		if (sec) {
			[['close', 'chaos-lightbox__close'], ['prev', 'chaos-lightbox__prev'], ['next', 'chaos-lightbox__next']].forEach(function (p) {
				var text = sec.getAttribute('data-l-' + p[0]);
				if (text) {
					box.querySelector('.' + p[1]).setAttribute('aria-label', text);
				}
			});
		}
		box.hidden = false;
		document.documentElement.classList.add('chaos-lightbox-open');
		show(links.indexOf(a));
		box.querySelector('.chaos-lightbox__close').focus();
	}

	function close() {
		box.hidden = true;
		img.removeAttribute('src');
		document.documentElement.classList.remove('chaos-lightbox-open');
		if (opener && opener.focus) {
			opener.focus();
		}
	}

	function init() {
		Array.prototype.forEach.call(document.querySelectorAll('video[data-chaos-trailer]'), setUpTrailer);
		Array.prototype.forEach.call(document.querySelectorAll('a[data-chaos-shot]'), function (a) {
			a.addEventListener('click', function (e) {
				if (e.metaKey || e.ctrlKey || e.shiftKey || e.altKey || e.button) {
					return;
				}
				e.preventDefault();
				open(a);
			});
		});
	}

	if (document.readyState === 'loading') {
		document.addEventListener('DOMContentLoaded', init);
	} else {
		init();
	}
}());
