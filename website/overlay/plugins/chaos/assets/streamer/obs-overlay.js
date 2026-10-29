// OBS browser source for streamers (README "Streamer kit"). Shows the server name and the creator code from the address:
//   .../obs-overlay.html?code=YOURCODE[&lang=en|pt-BR]
// Plain text only. No cookies, no storage, no requests, no account data. The code is cleaned to 3-16 letters and digits.
(function () {
	var q = new URLSearchParams(window.location.search);
	var code = (q.get('code') || '').toUpperCase().replace(/[^A-Z0-9]/g, '').slice(0, 16);
	var lang = q.get('lang') || (navigator.language || 'en');
	var pt = /^pt/i.test(lang);
	document.documentElement.lang = pt ? 'pt-BR' : 'en';
	document.getElementById('lead').textContent = pt ? 'use o código' : 'use code';
	document.getElementById('code').textContent = code.length >= 3 ? code : (pt ? 'SEUCODIGO' : 'YOURCODE');
})();
