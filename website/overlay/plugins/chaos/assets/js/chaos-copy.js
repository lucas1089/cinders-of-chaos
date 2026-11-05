// Cinders of Chaos: copy buttons (pages/trends.php). A button.chaos-copy with data-chaos-copy="TEXT" is hidden until this
// file runs; then it shows, copies TEXT to the clipboard on click and reads data-chaos-copied for a moment. The
// read-only field next to it (.chaos-copy__field) is hidden then. Without JavaScript the field stays for a manual copy.
// No inline script (the site's Content-Security-Policy).
(function () {
	'use strict';
	function fallback(text) {
		var area = document.createElement('textarea');
		area.value = text;
		area.setAttribute('readonly', '');
		area.style.position = 'absolute';
		area.style.left = '-9999px';
		document.body.appendChild(area);
		area.select();
		try {
			document.execCommand('copy');
		} catch (e) {
			// nothing: the field is still there to select
		}
		document.body.removeChild(area);
	}
	function setUp(button) {
		if (button.getAttribute('data-chaos-copy-ready') === '1') {
			return;
		}
		button.setAttribute('data-chaos-copy-ready', '1');
		var text = button.getAttribute('data-chaos-copy') || '';
		var label = button.textContent;
		var done = button.getAttribute('data-chaos-copied') || label;
		var field = button.parentNode ? button.parentNode.querySelector('.chaos-copy__field') : null;
		if (field) {
			field.hidden = true;
		}
		button.hidden = false;
		button.addEventListener('click', function () {
			var shown = function () {
				button.textContent = done;
				window.setTimeout(function () { button.textContent = label; }, 1500);
			};
			if (navigator.clipboard && navigator.clipboard.writeText) {
				navigator.clipboard.writeText(text).then(shown, function () { fallback(text); shown(); });
			} else {
				fallback(text);
				shown();
			}
		});
	}
	function init() {
		Array.prototype.forEach.call(document.querySelectorAll('button.chaos-copy[data-chaos-copy]'), setUp);
	}
	if (document.readyState === 'loading') {
		document.addEventListener('DOMContentLoaded', init);
	} else {
		init();
	}
}());
