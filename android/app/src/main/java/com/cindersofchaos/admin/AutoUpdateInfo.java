package com.cindersofchaos.admin;

import java.util.HashMap;
import java.util.Map;

/**
 * Painel > Atualização automática (O767): the reading of the key=value lines of chaos-ctl.sh auto-update status
 * (installed, enabled, save_time, game_save_time, prep_at, save_run_at, next_prep, next_save, running, prep_*, save_*,
 * applied_*, client_pair) and their wording in Portuguese, plus the check of a time typed for auto-update time HH:MM.
 * Pure Java, tested by AutoUpdateInfoTest on a plain JVM. server/README.md "Automatic daily update (O767)".
 */
final class AutoUpdateInfo {
    private final Map<String, String> kv;

    private AutoUpdateInfo(Map<String, String> kv) {
        this.kv = kv;
    }

    /** The status lines, or null when the output has no enabled= line (a refusal, an ssh error, an old script). */
    static AutoUpdateInfo parse(String out) {
        if (out == null) {
            return null;
        }
        Map<String, String> kv = new HashMap<>();
        for (String line : out.split("\n")) {
            int eq = line.indexOf('=');
            if (eq <= 0) {
                continue;
            }
            String k = line.substring(0, eq).trim();
            if (k.matches("[a-z_]+") && !kv.containsKey(k)) {
                kv.put(k, line.substring(eq + 1).trim());
            }
        }
        if (!kv.containsKey("enabled") || !kv.containsKey("save_time")) {
            return null;
        }
        return new AutoUpdateInfo(kv);
    }

    String get(String k) {
        return kv.getOrDefault(k, "");
    }

    boolean enabled() {
        return "yes".equals(get("enabled"));
    }

    boolean running() {
        return "yes".equals(get("running"));
    }

    /** HH:MM from 00:00 to 23:59, the only time auto-update time takes (besides "game"). */
    static boolean validTime(String t) {
        return t != null && t.matches("([01][0-9]|2[0-3]):[0-5][0-9]");
    }

    /** A typed time made HH:MM ("6:00" -> "06:00", "0600" -> "06:00"), or "" when it is no time. */
    static String normalTime(String t) {
        if (t == null) {
            return "";
        }
        String s = t.trim();
        if (s.matches("\\d{4}")) {
            s = s.substring(0, 2) + ":" + s.substring(2);
        } else if (s.matches("\\d:\\d{2}")) {
            s = "0" + s;
        }
        return validTime(s) ? s : "";
    }

    static String resultWord(String r) {
        switch (r) {
            case "ok":
                return "atualizado";
            case "warn":
                return "atualizado com aviso";
            case "nothing":
                return "nada novo";
            case "skipped":
                return "pulado";
            case "dispatched":
                return "builds disparadas";
            case "rolled-back":
                return "revertido";
            case "failed":
                return "falhou";
            case "":
                return "nunca rodou";
            default:
                return r;
        }
    }

    /** One line for the card's title. */
    String headline() {
        if (!enabled()) {
            return "Desligada. As atualizações seguem à mão (Atualizar servidor).";
        }
        return "Ligada: atualiza no server save das " + get("save_time") + (running() ? " (rodando agora)" : "") + ".";
    }

    /** The details under the title, in Portuguese. */
    String details() {
        StringBuilder b = new StringBuilder();
        String src = "set".equals(get("save_time_source")) ? "definido aqui" : "do jogo";
        b.append("Server save: ").append(get("save_time")).append(" (").append(src).append(")");
        String g = get("game_save_time");
        if (!g.isEmpty() && !"unknown".equals(g) && !g.equals(get("save_time"))) {
            b.append("; o jogo salva às ").append(g).append(": confira o horário");
        }
        b.append(".\nBuilds às ").append(get("prep_at")).append(", instalação começa às ").append(get("save_run_at"))
                .append(" e entra no save.");
        if (!get("next_save").isEmpty()) {
            b.append("\nPróximo preparo: ").append(get("next_prep")).append("\nPróximo save: ").append(get("next_save"));
        }
        b.append("\n\nÚltimo preparo: ").append(resultWord(get("prep_result")));
        if (!get("prep_time").isEmpty()) {
            b.append(" (").append(get("prep_time")).append(")");
        }
        if (!get("prep_engine").isEmpty()) {
            b.append("\n  Engine: ").append(get("prep_engine"))
                    .append("\n  Android: ").append(get("prep_android"))
                    .append("\n  App admin: ").append(get("prep_admin"));
        } else if (!get("prep_text").isEmpty()) {
            b.append("\n  ").append(get("prep_text"));
        }
        b.append("\nÚltimo save: ").append(resultWord(get("save_result")));
        if (!get("save_time_run").isEmpty()) {
            b.append(" (").append(get("save_time_run")).append(")");
        }
        if (!get("save_text").isEmpty()) {
            b.append("\n  ").append(get("save_text"));
        }
        if (!get("applied_time").isEmpty()) {
            b.append("\nInstalado em ").append(get("applied_time")).append(": commit ").append(get("applied_commit"))
                    .append(", engine ").append(get("applied_release")).append(", ").append(get("applied_pair"))
                    .append(", client ").append(get("applied_client")).append(", APK ").append(get("applied_apk"));
        }
        if (!get("client_pair").isEmpty()) {
            b.append("\nPar do client agora: ").append(get("client_pair"));
        }
        return b.toString();
    }

    static String confirmOnText(String saveTime) {
        return "Todo dia, 3 horas antes do server save (" + saveTime + "), a VPS manda o GitHub compilar o que mudou "
                + "(engine, client Android, app admin), uma vez por dia. 45 minutos antes do save ela instala o que é novo "
                + "numa cópia, e o próprio save faz a única reinicialização. Pula quando o CI está vermelho. Se algo falhar, "
                + "volta a versão anterior e avisa no Discord.";
    }

    static String confirmPrepText() {
        return "Dispara agora as builds cujo código mudou (no máximo uma vez por dia). O jogo segue no ar.";
    }

    static String confirmSaveText() {
        return "Prepara a atualização agora e instala no próximo server save (sem reiniciar antes dele).";
    }

    static String confirmNowText() {
        return "Instala agora e REINICIA o jogo já, sem esperar o server save. Os jogadores caem por alguns minutos.";
    }
}
