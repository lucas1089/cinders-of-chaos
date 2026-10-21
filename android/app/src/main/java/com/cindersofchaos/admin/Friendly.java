package com.cindersofchaos.admin;

import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * The outcome of one remote command, told in Portuguese: a short title, a sentence that says what to do, and the raw
 * output for the details. Maps the usual failures (ssh refused or timed out, wrong key, host key changed, sudo, the
 * chaos-ctl.sh messages and exit codes) to plain words. Pure Java, no Android classes.
 */
final class Friendly {
    final boolean ok;
    final String title;
    final String detail;
    final String raw;

    Friendly(boolean ok, String title, String detail, String raw) {
        this.ok = ok;
        this.title = title;
        this.detail = detail == null ? "" : detail;
        this.raw = raw == null ? "" : raw;
    }

    static Friendly ok(String title, String detail, String raw) {
        return new Friendly(true, title, detail, raw);
    }

    static Friendly fail(String title, String detail, String raw) {
        return new Friendly(false, title, detail, raw);
    }

    /** A failure before the command ran: no connection, no key, a refused login, a changed host key. */
    static Friendly ofException(Throwable e) {
        String m = e.getMessage() == null ? e.toString() : e.getMessage();
        String all = chain(e);
        String low = all.toLowerCase(java.util.Locale.ROOT);
        if (e instanceof SecurityException) {
            return fail("A chave do servidor mudou",
                    "A VPS respondeu com outra impressão digital. Pode ser um ataque no caminho, ou o servidor foi "
                            + "reinstalado. Se foi você quem reinstalou, toque em Esquecer impressão digital na aba Config e "
                            + "confira a nova com: ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub", m);
        }
        if (m.startsWith("Sem servidor") || m.startsWith("Sem chave")) {
            return fail("Falta configurar", m, m);
        }
        if (low.contains("auth fail") || low.contains("auth cancel") || low.contains("userauth")) {
            return fail("Acesso negado pela VPS",
                    "A VPS não aceitou a chave deste celular para esse usuário. Na aba Config, toque em Copiar comando "
                            + "de instalação e rode na VPS como root. Confira também o usuário (padrão chaosadmin).", m);
        }
        if (low.contains("unknownhost") || low.contains("unable to resolve") || low.contains("no address associated")) {
            return fail("Endereço não encontrado",
                    "O nome do servidor não existe ou o celular está sem internet. Confira o endereço na aba Config.", m);
        }
        if (low.contains("connection refused")) {
            return fail("Conexão recusada",
                    "A VPS está no ar, mas nada atende nessa porta. Confira a porta SSH (padrão 22) e o firewall.", m);
        }
        if (low.contains("network is unreachable") || low.contains("enetunreach")) {
            return fail("Sem internet", "O celular está sem rede. Tente de novo quando a conexão voltar.", m);
        }
        if (low.contains("timeout") || low.contains("timed out") || low.contains("no route to host")
                || low.contains("ehostunreach")) {
            return fail("A VPS não respondeu",
                    "Sem resposta em 12 segundos. A VPS pode estar desligada, o endereço errado, ou um firewall "
                            + "bloqueia a porta SSH.", m);
        }
        if (low.contains("invalid privatekey") || low.contains("keystore") || low.contains("aeadbadtag")) {
            return fail("Chave do celular ilegível",
                    "A chave SSH guardada não abriu (o bloqueio de tela foi trocado?). Gere uma chave nova na aba Config "
                            + "e instale de novo na VPS.", m);
        }
        return fail("Falha na conexão", m, all);
    }

    /** The output (stdout and stderr together) and the exit code of a command that ran. */
    static Friendly ofResult(String out, int code) {
        String raw = out == null ? "" : out.trim();
        String low = raw.toLowerCase(java.util.Locale.ROOT);
        if (raw.contains("[tempo esgotado]")) {
            return fail("Demorou demais",
                    "O comando passou do tempo limite. Ele pode ainda estar rodando na VPS: atualize o painel em "
                            + "alguns segundos.", raw);
        }
        if (low.contains("a password is required") || low.contains("a terminal is required")
                || low.contains("is not allowed to execute") || low.contains("may not run sudo")
                || low.contains("not in the sudoers")) {
            return fail("Sem permissão de administrador",
                    "O usuário SSH não pode rodar o chaos-ctl.sh como root. Na aba Config, Copiar comando de instalação e "
                            + "rode na VPS como root (ele libera o sudo só para esse script). Se o caminho do script "
                            + "mudou, rode de novo com o caminho novo.", raw);
        }
        if (low.contains("unit-not-found") || (code == 5 && (low.contains("not found") || low.contains("not loaded")))) {
            String unit = unitName(raw);
            return fail("Serviço do jogo não instalado",
                    "O systemd não conhece a unidade " + (unit.isEmpty() ? "do jogo" : "'" + unit + "'") + " (código 5). "
                            + "Na VPS beta o jogo roda do kit em /opt/chaos-trial, sem unidade. Instale a unidade "
                            + "(server/deploy/chaos-trial-server.service como /etc/systemd/system/chaos-server.service) ou "
                            + "escreva o nome certo em /etc/chaos/ctl.conf: CHAOS_UNIT=nome. Variáveis de ambiente não "
                            + "chegam ao chaos-ctl.sh, porque o sudo as apaga; só o ctl.conf vale.", raw);
        }
        if (low.contains("mysql-not-found") || (code == 127 && (low.contains("mysql") || low.contains("mariadb")))) {
            return fail("Cliente do banco não encontrado",
                    "A VPS não tem o programa mysql (código 127). No kit ele fica em /opt/chaos-trial/mariadb/bin/mariadb: "
                            + "escreva CHAOS_MYSQL=/opt/chaos-trial/mariadb/bin/mariadb em /etc/chaos/ctl.conf.", raw);
        }
        if (code == 127 || (low.contains("no such file or directory") && low.contains("chaos-ctl"))) {
            return fail("chaos-ctl.sh não encontrado",
                    "O script não está nesse caminho na VPS (código 127). Confira o caminho do chaos-ctl.sh na aba Config "
                            + "(padrão /opt/chaos/repo/server/deploy/chaos-ctl.sh) e se o repositório está lá.", raw);
        }
        if (low.contains("cannot read the log")) {
            return fail("Log não encontrado", "O chaos-ctl.sh não achou o log do servidor. Escreva o caminho em "
                    + "/etc/chaos/ctl.conf: CHAOS_LOG=/opt/chaos-trial/logs/server.log (kit) ou o seu.", raw);
        }
        if (low.contains("cannot read") && low.contains(".env")) {
            return fail("Arquivo do banco não encontrado", "O chaos-ctl.sh não leu o arquivo com a senha do banco. "
                    + "Escreva o caminho em /etc/chaos/ctl.conf: CHAOS_ENV=/opt/chaos-trial/chaos.env (kit).", raw);
        }
        if (low.contains("no answer in 15 s")) {
            return fail("O jogo não respondeu",
                    "Nada voltou em 15 segundos. O servidor está ligado? O personagem admin (aba Config) existe e tem "
                            + "grupo de admin? O servidor tem os scripts de comando remoto?", raw);
        }
        if (low.contains("job for") && low.contains("failed")) {
            return fail("O serviço falhou", "O systemd tentou, mas o servidor não ficou de pé. Veja a aba Logs.", raw);
        }
        Matcher m = Pattern.compile("chaos-ctl: (.+)").matcher(raw);
        if (code != 0 && m.find()) {
            return fail("O chaos-ctl.sh recusou", translate(m.group(1)), raw);
        }
        if (code != 0) {
            return fail("Falhou (código " + code + ")", lastLines(raw, 6), raw);
        }
        return ok("Feito", translate(raw), raw);
    }

    /** The English answers of chaos-ctl.sh, in Portuguese. Unknown text is kept. */
    static String translate(String s) {
        String t = s.trim();
        if (t.startsWith("queued:")) {
            return "Enviado. O servidor executa em alguns segundos.";
        }
        Matcher m = Pattern.compile("^(start|stop): done \\((\\w*)\\)").matcher(t);
        if (m.find()) {
            return (m.group(1).equals("start") ? "Servidor ligado" : "Servidor desligado") + " (" + state(m.group(2)) + ").";
        }
        m = Pattern.compile("^restarted \\((\\w*)\\)").matcher(t);
        if (m.find()) {
            return "Servidor reiniciado (" + state(m.group(1)) + ").";
        }
        m = Pattern.compile("^restart in (\\d+) seconds").matcher(t);
        if (m.find()) {
            return "Reinício marcado para daqui a " + duration(Long.parseLong(m.group(1))) + ". Os jogadores foram avisados.";
        }
        if (t.startsWith("save requested")) {
            return "Salvamento pedido. Os jogadores são salvos aos poucos, sem travar o jogo.";
        }
        if (t.startsWith("started (update") || t.startsWith("started (rollback")) {
            return "Começou. Acompanhe em Logs, Atualização.";
        }
        if (t.startsWith("started (site-install")) {
            return "Começou a reinstalar o site. Acompanhe em Logs, Atualização, log do site.";
        }
        if (t.startsWith("started (publish-update")) {
            return "Começou a publicar o update do client. Acompanhe em Logs, Atualização, log da publicação.";
        }
        if (t.startsWith("kit-not-found")) {
            return "Essa função é do kit Linux (/opt/chaos-trial). Escreva CHAOS_KIT_DIR=/opt/chaos-trial em "
                    + "/etc/chaos/ctl.conf.";
        }
        if (t.startsWith("kit-layout")) {
            return "No kit Linux a versão vem do GitHub: use Atualizar servidor no Painel.";
        }
        if (t.startsWith("update-running")) {
            return "Já tem uma atualização ou volta de versão rodando. Acompanhe em Logs, Atualização.";
        }
        if (t.startsWith("account-exists")) {
            return "Essa conta já existe. Para trocar a senha, use Trocar senha.";
        }
        if (t.startsWith("account-not-found")) {
            return "Não existe conta com esse nome.";
        }
        if (t.startsWith("database-down")) {
            return "O banco não respondeu. O servidor está ligado? (no kit o banco liga junto com o servidor)";
        }
        if (t.startsWith("the password must")) {
            return "A senha precisa ter de 6 a 64 caracteres, numa linha só.";
        }
        Matcher pm = Pattern.compile("^account (\\S+) created").matcher(t);
        if (pm.find()) {
            return "Conta " + pm.group(1) + " criada. O personagem é criado no client ou no site.";
        }
        pm = Pattern.compile("^password of (\\S+) changed").matcher(t);
        if (pm.find()) {
            return "Senha da conta " + pm.group(1) + " trocada.";
        }
        if (t.contains("applies at the next restart")) {
            return "Gravado no config.lua. Vale no próximo reinício do servidor.";
        }
        if (t.startsWith("N must be a number")) {
            return "O número de linhas precisa ser um número.";
        }
        if (t.startsWith("at most 900 seconds")) {
            return "No máximo 15 minutos.";
        }
        return t;
    }

    static String state(String s) {
        switch (s) {
            case "active":
                return "no ar";
            case "inactive":
                return "parado";
            case "failed":
                return "falhou";
            case "activating":
                return "ligando";
            case "deactivating":
                return "desligando";
            default:
                return s.isEmpty() ? "?" : s;
        }
    }

    /** 90 -> "1 min 30 s", 7300 -> "2 h 1 min", 200000 -> "2 d 7 h". */
    static String duration(long sec) {
        if (sec < 60) {
            return sec + " s";
        }
        long d = sec / 86400;
        long h = (sec % 86400) / 3600;
        long m = (sec % 3600) / 60;
        if (d > 0) {
            return d + " d" + (h > 0 ? " " + h + " h" : "");
        }
        if (h > 0) {
            return h + " h" + (m > 0 ? " " + m + " min" : "");
        }
        long s = sec % 60;
        return m + " min" + (s > 0 && m < 10 ? " " + s + " s" : "");
    }

    private static String unitName(String raw) {
        Matcher m = Pattern.compile("unit ([A-Za-z0-9@._-]+) does not exist").matcher(raw);
        if (m.find()) {
            return m.group(1);
        }
        m = Pattern.compile("Unit ([A-Za-z0-9@._-]+?)(\\.service)? (not found|could not be found|not loaded)").matcher(raw);
        return m.find() ? m.group(1) : "";
    }

    private static String lastLines(String s, int n) {
        String[] lines = s.split("\n");
        StringBuilder b = new StringBuilder();
        for (int i = Math.max(0, lines.length - n); i < lines.length; i++) {
            b.append(lines[i]).append('\n');
        }
        return b.toString().trim();
    }

    private static String chain(Throwable e) {
        StringBuilder b = new StringBuilder();
        for (Throwable t = e; t != null && b.length() < 2000; t = t.getCause()) {
            b.append(t).append('\n');
            if (t.getCause() == t) {
                break;
            }
        }
        return b.toString().trim();
    }
}
