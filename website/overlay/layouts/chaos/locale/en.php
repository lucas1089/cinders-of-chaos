<?php
// Cinders of Chaos wording for the strings of the parent layout (the rest falls back to it).
return array(
	'void.header.download_meta' => 'The Cinders of Chaos client - free to play',
	'void.header.discord_meta' => 'Join the community',
	'void.rank.players' => 'Mightiest',
	'void.rank.guilds' => 'Guilds',
	'void.user.panel' => 'Account',
	// the copyright line of every page's footer also links the player wiki (plugins/chaos/pages/wiki.php), the legal
	// texts (plugins/chaos/pages/legal.php) and the credits (plugins/chaos/pages/credits.php), so the links stay when the owner edits the theme's footer text
	'void.footer.copyright' => '&copy; {year} {site} &middot; <span class="chaos-legal-links">'
		. '<a href="page.php?plugin=chaos&amp;p=wiki">Wiki</a> &middot; '
		. '<a href="page.php?plugin=chaos&amp;p=legal&amp;doc=terms">Termos de Uso / Terms of Use</a> &middot; '
		. '<a href="page.php?plugin=chaos&amp;p=legal&amp;doc=privacy">Privacidade / Privacy</a> &middot; '
		. '<a href="page.php?plugin=chaos&amp;p=legal&amp;doc=donations">Doações / Donations</a> &middot; '
		. '<a href="page.php?plugin=chaos&amp;p=credits">Créditos / Credits</a></span>',
	// the stock download texts name another game's client; ours is the Cinders of Chaos client
	'downloads.win' => 'Cinders of Chaos client for Windows',
	'downloads.linux' => 'Cinders of Chaos client for Linux',
	'downloads.intro' => 'In order to play, you need the Cinders of Chaos client.',
	'downloads.step1' => 'and unpack the Cinders of Chaos client into a folder of your choice.',
	'downloads.step3' => 'Start the client from that folder.',
	'downloads.step5' => 'Now you can log in with your account and play by clicking',
	'downloads.os_step_settings' => 'Start the Cinders of Chaos client.',
	'downloads.os_step_browse' => 'Log in with your account name and password.',
	'downloads.os_step_apply' => 'Pick your character and enter the world.',
	// no premium accounts here: the stock "You have a free account." line of the account page says nothing
	'acc.free_account' => '',
	// account creation: the same answer for a malformed and a taken e-mail address, never "already in use"
	'reg.email_invalid' => 'Please use another e-mail address.',
	'reg.email_taken' => 'Please use another e-mail address.',
	'createchar.vocation' => 'Class',
	'createchar.male' => 'Male',
	'createchar.female' => 'Female',
);
