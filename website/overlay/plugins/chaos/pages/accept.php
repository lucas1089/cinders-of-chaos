<?php
/**
 * Accept the current Terms of Use and Privacy Policy (legal_lib.php): page?plugin=chaos&p=accept[&next=...].
 * plugin.php sends a logged-in account here first while it has no chaos_legal_acceptance row for the current version
 * of the texts (the beta accounts made before the sign-up checkbox, and everyone after the texts change). The same
 * checkbox as account creation; the row is the same as at sign-up (account, version, time; no IP). Then back to the
 * page the player wanted (a page of this site only).
 */
if (!isset($config)) { http_response_code(403); die('Direct access denied.'); }
require_once dirname(__DIR__) . '/legal_lib.php';

$GLOBALS['page_title'] = 'Terms of Use';
$accountId = function_exists('getSession') ? (int)getSession('user_id') : 0;
$next = chaos_legal_safe_next((string)($_POST['next'] ?? $_GET['next'] ?? ''));

if (session_status() === PHP_SESSION_ACTIVE && empty($_SESSION['chaos_legal_csrf'])) {
	$_SESSION['chaos_legal_csrf'] = bin2hex(random_bytes(16));
}
$csrf = (string)($_SESSION['chaos_legal_csrf'] ?? '');

$error = '';
$done = false;
if ($accountId > 0 && ($_SERVER['REQUEST_METHOD'] ?? 'GET') === 'POST') {
	[$done, $error] = chaos_legal_accept_post($accountId, $_POST, $csrf, time());
	if ($done && PHP_SAPI !== 'cli' && !headers_sent()) {
		header('Location: ' . $next, true, 303);
		exit;
	}
}
$accepted = $accountId > 0 && chaos_legal_has_accepted($accountId);
?>
<div class="chaos-page">
	<div class="chaos-box chaos-legal" id="chaos-legal-accept">
		<h1 class="chaos-heading">Terms of Use / Termos de Uso</h1>
		<?php if ($accountId <= 0): ?>
			<p>Please <a href="login">log in</a> first. / <a href="login">Entre na sua conta</a> primeiro.</p>
		<?php elseif ($done): ?>
			<meta http-equiv="refresh" content="0;url=<?= chaos_h($next) ?>">
			<p id="chaos-legal-accepted">Thank you. / Obrigado.</p>
			<p><a class="chaos-btn" href="<?= chaos_h($next) ?>">Continue / Continuar</a></p>
		<?php elseif ($accepted): ?>
			<p>You have accepted the current Terms of Use and Privacy Policy. / Você já aceitou os Termos de Uso e a Política de Privacidade atuais.</p>
			<p><a class="chaos-btn" href="<?= chaos_h($next) ?>">Continue / Continuar</a></p>
		<?php else: ?>
			<p class="chaos-lead">Before you continue, please read and accept our Terms of Use and Privacy Policy. Accounts made
				before the checkbox at sign-up, and every account after the texts change, are asked once.</p>
			<p class="chaos-lead" lang="pt-BR">Antes de continuar, leia e aceite os nossos Termos de Uso e a Política de Privacidade.
				Contas criadas antes da caixa de aceite no cadastro, e todas as contas depois de uma mudança nos textos, aceitam uma vez.</p>
			<?php if ($error !== ''): ?>
				<p class="chaos-error" id="chaos-legal-accept-error" style="color:#e07060;"><?= chaos_h($error) ?></p>
			<?php endif; ?>
			<form method="post" action="<?= chaos_h(CHAOS_LEGAL_ACCEPT_URL) ?>">
				<input type="hidden" name="csrf" value="<?= chaos_h($csrf) ?>">
				<input type="hidden" name="next" value="<?= chaos_h($next) ?>">
				<p>
					<label><input type="checkbox" name="chaos_accept_terms" value="1">
					I accept the <a href="<?= chaos_h(chaos_legal_url('terms', 'en')) ?>" target="_blank">Terms of Use</a> and the
					<a href="<?= chaos_h(chaos_legal_url('privacy', 'en')) ?>" target="_blank">Privacy Policy</a>.</label><br>
					<small class="chaos-muted" lang="pt-BR">Li e aceito os <a href="<?= chaos_h(chaos_legal_url('terms')) ?>" target="_blank">Termos de Uso</a>
					e a <a href="<?= chaos_h(chaos_legal_url('privacy')) ?>" target="_blank">Política de Privacidade</a>.
					Under 18: only with the permission of a parent or guardian. / Menores de 18 anos: só com a autorização dos pais ou do responsável.</small>
				</p>
				<p><input type="submit" class="chaos-btn" value="Continue / Continuar"></p>
			</form>
			<p class="chaos-muted">If you do not accept, you can <a href="logout">log out</a>. / Se não aceitar, você pode <a href="logout">sair</a>.</p>
		<?php endif; ?>
	</div>
</div>
