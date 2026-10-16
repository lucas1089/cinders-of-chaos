// Cinders of Chaos: the dropdown filter forms (lib.php chaos_pick_form). The forms work without this file (a GET form
// with a "Show" button); with it, a changed dropdown submits its form at once and the button is hidden. A dropdown with
// data-chaos-reset="a b" drops those fields first (another board has other bosses and party sizes). Loaded once per
// form with defer; each form is set up only once. No inline script (the site's Content-Security-Policy).
(function () {
	'use strict';
	function setUp(form) {
		if (form.getAttribute('data-chaos-pick-ready') === '1') {
			return;
		}
		form.setAttribute('data-chaos-pick-ready', '1');
		var go = form.querySelector('.chaos-pick__go');
		if (go) {
			go.hidden = true;
		}
		var selects = form.querySelectorAll('select[data-chaos-autosubmit]');
		Array.prototype.forEach.call(selects, function (select) {
			select.addEventListener('change', function () {
				var reset = (select.getAttribute('data-chaos-reset') || '').split(/\s+/);
				Array.prototype.forEach.call(form.elements, function (field) {
					if (field !== select && field.name && reset.indexOf(field.name) !== -1) {
						field.disabled = true;
					}
				});
				form.submit();
			});
		});
	}
	function init() {
		Array.prototype.forEach.call(document.querySelectorAll('form.chaos-pick'), setUp);
	}
	// back to the page from the cache: the dropped fields are enabled again
	window.addEventListener('pageshow', function () {
		Array.prototype.forEach.call(document.querySelectorAll('form.chaos-pick [disabled]'), function (field) {
			field.disabled = false;
		});
	});
	if (document.readyState === 'loading') {
		document.addEventListener('DOMContentLoaded', init);
	} else {
		init();
	}
})();
