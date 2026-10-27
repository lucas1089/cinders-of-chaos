package com.cindersofchaos.admin;

import java.util.LinkedHashMap;
import java.util.Map;

/**
 * The "Servidor como usuário chaos" card in Portuguese: the reading of chaos-ctl.sh server-user status (the engine warns
 * "executed as root user" when the unit runs it as root), the summary of server-user fix and the translation of its
 * refusals. Pure Java, no Android classes.
 */
final class ServerUserInfo {
    static final String VERDICT_UNKNOWN = "unknown";
    static final String VERDICT_OK = "ok";
    static final String VERDICT_FIX = "fix";
    static final String VERDICT_RESTART = "restart";
    static final String VERDICT_BLOCKED = "blocked";

    private ServerUserInfo() {
    }

    /** key=value lines of server-user status (first value of a key wins). */
    static Map<String, String> parse(String out) {
        Map<String, String> kv = new LinkedHashMap<>();
        for (String line : (out == null ? "" : out).split("\n")) {
            int eq = line.indexOf('=');
            if (eq > 0) {
                kv.putIfAbsent(line.substring(0, eq).trim(), line.substring(eq + 1).trim());
            }
        }
        return kv;
    }

    /** unknown (no reading), blocked (the checkout is not root-owned: fix refuses), fix, restart (unit ready, engine still old) or ok. */
    static String verdict(String out) {
        Map<String, String> kv = parse(out);
        if (!kv.containsKey("needs_fix")) {
            return VERDICT_UNKNOWN;
        }
        if ("no".equals(kv.get("repo_root_owned"))) {
            return VERDICT_BLOCKED;
        }
        if ("yes".equals(kv.get("needs_fix"))) {
            return VERDICT_FIX;
        }
        if ("yes".equals(kv.get("restart_needed"))) {
            return VERDICT_RESTART;
        }
        return VERDICT_OK;
    }

    /** What the card says about server-user status. */
    static String summary(String out) {
        Map<String, String> kv = parse(out);
        String v = verdict(out);
        if (v.equals(VERDICT_UNKNOWN)) {
            return "Toque em Ver.";
        }
        String target = kv.getOrDefault("target_user", "chaos");
        String engine = kv.getOrDefault("engine_user", "");
        String unit = kv.getOrDefault("unit_user", "root");
        StringBuilder s = new StringBuilder();
        if (engine.isEmpty()) {
            s.append("Motor: parado agora.\n");
        } else if (engine.equals("root")) {
            s.append("Motor: roda como root (o log avisa \"executed as root user\").\n");
        } else {
            s.append("Motor: roda como ").append(engine).append(".\n");
        }
        s.append("Unidade do systemd: User=").append(unit).append(".\n");
        s.append("Usuário ").append(target).append(" no sistema: ")
                .append("yes".equals(kv.get("user_exists")) ? "existe" : "ainda não existe").append(".\n");
        String foreign = kv.getOrDefault("foreign_files", "-1");
        if ("0".equals(foreign)) {
            s.append("Pastas do servidor: todas de ").append(target).append(".\n");
        } else if (foreign.startsWith("-")) {
            s.append("Pastas do servidor: o dono muda quando o usuário existir.\n");
        } else {
            s.append("Pastas do servidor: ").append(foreign).append(" arquivo(s) de outro dono.\n");
        }
        String db = kv.getOrDefault("db_admin", "n/a");
        if (!db.equals("n/a")) {
            s.append("Banco do kit: admin ").append(target).append(": ")
                    .append(db.equals("yes") ? "pronto" : db.equals("no") ? "falta" : "não deu para ver (banco parado)")
                    .append(".\n");
        }
        s.append("Repositório (código): ")
                .append("yes".equals(kv.get("repo_root_owned")) ? "só do root (certo)" : "o chaos ou outros podem escrever: corrija antes")
                .append(".\n");
        switch (v) {
            case VERDICT_OK:
                s.append("Tudo certo.");
                break;
            case VERDICT_RESTART:
                s.append("A unidade está pronta, mas o motor ainda roda como ").append(engine.isEmpty() ? "root" : engine)
                        .append(". Falta reiniciar o servidor (Corrigir e reiniciar, ou Painel > Reiniciar em...).");
                break;
            case VERDICT_BLOCKED:
                s.append("Corrigir recusa até o repositório voltar a ser só do root (chown root:root e sem escrita para grupo e outros).");
                break;
            default:
                s.append("Precisa corrigir: toque em Corrigir.");
                break;
        }
        return s.toString();
    }

    /** The result of server-user fix in a few Portuguese sentences. */
    static String fixSummary(String out) {
        StringBuilder s = new StringBuilder();
        for (String line : (out == null ? "" : out).split("\n")) {
            String t = line.trim();
            if (t.startsWith("user:") && t.endsWith("created")) {
                s.append("Usuário criado (sem login).\n");
            } else if (t.startsWith("database: socket admin") && t.endsWith("ready")) {
                s.append("Banco do kit: admin pelo socket criado.\n");
            } else if (t.startsWith("folders owned by")) {
                s.append("Pastas que o jogo grava passadas para o usuário (o repositório não foi tocado).\n");
            } else if (t.startsWith("unit: installed")) {
                s.append("Unidade nova instalada (a antiga ficou guardada em /var/lib/chaos/server-user).\n");
            } else if (t.startsWith("unit: User=") && t.contains("already")) {
                s.append("A unidade já tinha o usuário.\n");
            } else if (t.startsWith("restart: needed")) {
                s.append("Falta reiniciar: o motor segue como root até a unidade reiniciar. Use Corrigir e reiniciar, ou "
                        + "Painel > Reiniciar em... (o salvamento diário não basta).\n");
            } else if (t.startsWith("restart: in ")) {
                s.append("Reinício marcado, os jogadores foram avisados. Depois toque em Ver e em Log do reinício.\n");
            } else if (t.startsWith("restart: not needed")) {
                s.append("O motor já roda como o usuário certo.\n");
            } else if (t.startsWith("restart: the server is not running")) {
                s.append("O servidor está parado: liga já como o usuário certo.\n");
            } else if (t.startsWith("RESULT ok: nothing to change")) {
                s.append("Nada a mudar.\n");
            }
        }
        String r = s.toString().trim();
        return r.isEmpty() ? (out == null ? "" : out.trim()) : r;
    }

    /** The English refusals of server-user in Portuguese; null when the text is not one of them. */
    static String translateError(String msg) {
        String t = msg == null ? "" : msg.trim();
        if (t.startsWith("repo-not-root-owned")) {
            return "O repositório (código) não é só do root: o usuário chaos ou grupo/outros podem escrever nele. Nada foi mudado. "
                    + "Corrija na VPS: chown root:root e chmod go-w nas pastas do repositório.";
        }
        if (t.startsWith("kit-not-traversable")) {
            return "O usuário chaos não consegue entrar na pasta do kit (falta a permissão de entrar para outros). Nada foi mudado.";
        }
        if (t.startsWith("layout-mismatch")) {
            return "A unidade instalada é de outro layout que o do ctl.conf (kit ou /opt/chaos). Instalar a errada pararia o "
                    + "servidor, então nada foi mudado. Confira CHAOS_KIT_DIR e CHAOS_ROOT em /etc/chaos/ctl.conf.";
        }
        if (t.startsWith("layout-unsupported")) {
            return "A unidade do repositório é escrita para /opt/chaos. Neste caminho instale a mão (server/README.md, Servidor como usuário chaos).";
        }
        if (t.startsWith("unit-verify-failed")) {
            return "O systemd recusou a unidade nova (systemd-analyze verify). A antiga ficou como estava.";
        }
        if (t.startsWith("unit-user-not-applied")) {
            return "O systemd continuou com o usuário antigo (um drop-in em /etc/systemd/system/chaos-server.service.d?). A unidade antiga voltou.";
        }
        if (t.startsWith("database-down") && t.contains("start the server first")) {
            return "O banco do kit não respondeu. Ligue o servidor primeiro (ele roda como o usuário antigo) e tente de novo. Nada foi mudado.";
        }
        if (t.startsWith("server-user-running")) {
            return "Já tem um Corrigir rodando. Espere e toque em Ver.";
        }
        if (t.startsWith("unit-file-not-found")) {
            return "Não achei o arquivo da unidade em /etc/systemd/system (ou ele é um link). Nada foi mudado.";
        }
        if (t.startsWith("no-unit-template")) {
            return "O repositório da VPS não tem o arquivo da unidade deste layout. Atualize o servidor primeiro.";
        }
        if (t.startsWith("no-backup")) {
            return "Não há unidade antiga guardada para voltar.";
        }
        return null;
    }
}
