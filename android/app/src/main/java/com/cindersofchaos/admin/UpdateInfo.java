package com.cindersofchaos.admin;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * The server update in Portuguese: what chaos-ctl.sh update-check reports, and the progress of update-apply /
 * update-rollback read from its log (the "STEP n/m name" lines and the final "RESULT status: text" line of
 * server/deploy/chaos_kit_update.sh). Pure Java, no Android classes.
 */
final class UpdateInfo {
    final Map<String, String> kv = new LinkedHashMap<>();
    final List<String> commits = new ArrayList<>();

    static UpdateInfo parse(String out) {
        UpdateInfo u = new UpdateInfo();
        for (String line : (out == null ? "" : out).split("\n")) {
            int eq = line.indexOf('=');
            if (eq <= 0) {
                continue;
            }
            String k = line.substring(0, eq).trim();
            String v = line.substring(eq + 1).trim();
            if (k.equals("commit")) {
                u.commits.add(v);
            } else if (!u.kv.containsKey(k)) {
                u.kv.put(k, v);
            }
        }
        return u;
    }

    String get(String k) {
        String v = kv.get(k);
        return v == null ? "" : v;
    }

    boolean valid() {
        return kv.containsKey("update_available");
    }

    boolean available() {
        return get("update_available").equals("yes");
    }

    boolean running() {
        return get("running").equals("yes");
    }

    /** The summary card text: code, engine, map master, client update, downloads, site. */
    String summary() {
        StringBuilder b = new StringBuilder();
        int behind = num(get("behind"));
        String branch = get("branch").isEmpty() ? "main" : get("branch");
        if (behind > 0) {
            b.append("Código: ").append(behind).append(behind == 1 ? " commit novo" : " commits novos")
                    .append(" em ").append(branch).append(" (").append(get("local_commit")).append(" → ")
                    .append(get("remote_commit")).append(")\n");
            for (String c : commits) {
                b.append("  • ").append(c).append('\n');
            }
            if (behind > commits.size()) {
                b.append("  • … e mais ").append(behind - commits.size()).append('\n');
            }
        } else {
            b.append("Código: em dia com ").append(branch).append(" (").append(get("local_commit")).append(")\n");
        }
        if (num(get("ahead")) > 0) {
            b.append("Atenção: a VPS tem commits que não estão no GitHub; a atualização vai recusar.\n");
        }
        String inst = get("installed_release");
        String latest = get("latest_release");
        if (get("needs_engine").equals("yes")) {
            b.append("Servidor (engine): ").append(inst.equals("unknown") ? "versão instalada desconhecida" : "winpkg-" + inst)
                    .append(" → winpkg-").append(latest).append(" (baixa e troca o tfs)\n");
        } else if (latest.isEmpty() || latest.equals("unknown")) {
            b.append("Servidor (engine): não consegui ler as releases do GitHub\n");
        } else {
            b.append("Servidor (engine): em dia (winpkg-").append(inst).append(")\n");
        }
        String master = get("map_master");
        if (get("needs_map").equals("yes")) {
            String im = get("installed_map");
            b.append("Mapa: ").append(im.isEmpty() || im.equals("0") ? "mapa da base" : "versão " + im)
                    .append(" → versão ").append(master).append(" do mapa mestre (troca o mapa, com backup)\n");
        } else if (get("needs_map").equals("unknown")) {
            b.append("Mapa: não consegui ler o mapa mestre no GitHub\n");
        } else if (!master.isEmpty() && !master.equals("none")) {
            b.append("Mapa: em dia (versão ").append(get("installed_map")).append(" do mapa mestre)\n");
        }
        b.append("Update do client: publicado ").append(get("published_client"))
                .append(get("needs_client").equals("yes") ? " → publica " + latest : " (em dia)").append('\n');
        b.append("Downloads do site: release ").append(get("downloads_release"))
                .append(get("needs_downloads").equals("yes") ? " → " + latest : " (em dia)").append('\n');
        b.append("Site: ").append(get("website_changed").equals("yes") ? "mudou, será reinstalado" : "sem mudanças");
        return b.toString();
    }

    /** The last run, from update-check or update-status. */
    String lastRun() {
        String st = get("last_status").isEmpty() ? get("status") : get("last_status");
        String res = get("last_result").isEmpty() ? get("result") : get("last_result");
        String time = get("last_time").isEmpty() ? get("time") : get("last_time");
        if (st.isEmpty()) {
            return "";
        }
        return "Última vez (" + time + "): " + statusWord(st) + (res.isEmpty() ? "" : ". " + res);
    }

    // ------------------------------------------------------------------------------------------------ progress

    static final class Progress {
        int step;
        int steps;
        String name = "";
        /** ok, warn, failed, rolled-back; empty while it runs */
        String status = "";
        String result = "";
    }

    private static final Pattern STEP = Pattern.compile("^STEP (\\d+)/(\\d+) ([a-z-]+)", Pattern.MULTILINE);
    private static final Pattern RESULT = Pattern.compile("^RESULT ([a-z-]+): (.*)$", Pattern.MULTILINE);

    static Progress progress(String log) {
        Progress p = new Progress();
        String s = log == null ? "" : log;
        Matcher m = STEP.matcher(s);
        while (m.find()) {
            p.step = Integer.parseInt(m.group(1));
            p.steps = Integer.parseInt(m.group(2));
            p.name = m.group(3);
        }
        m = RESULT.matcher(s);
        while (m.find()) {
            p.status = m.group(1);
            p.result = m.group(2).trim();
        }
        return p;
    }

    static String stepWord(String name) {
        switch (name) {
            case "check":
                return "Verificando o GitHub";
            case "download":
                return "Baixando o servidor novo";
            case "map":
                return "Conferindo o mapa mestre";
            case "backup":
                return "Backup (banco e arquivos)";
            case "install":
                return "Instalando (servidor desligado)";
            case "database":
                return "Atualizando o banco";
            case "verify":
                return "Esperando o servidor ligar";
            case "rollback":
                return "Falhou: voltando a versão anterior";
            case "client":
                return "Publicando o update do client";
            case "downloads":
                return "Trocando os downloads do site";
            case "site":
                return "Reinstalando o site";
            case "server":
                return "Voltando o servidor";
            default:
                return name;
        }
    }

    static String statusWord(String st) {
        switch (st) {
            case "ok":
                return "concluída";
            case "warn":
                return "concluída com avisos";
            case "failed":
                return "falhou";
            case "rolled-back":
                return "falhou e voltou à versão anterior";
            case "running":
                return "em andamento (ou interrompida)";
            default:
                return st;
        }
    }

    /** The result line of the script in Portuguese (the English text stays in the details). */
    static String resultText(Progress p) {
        switch (p.status) {
            case "ok":
                return "Servidor atualizado e no ar. " + p.result;
            case "warn":
                return "O servidor foi atualizado e está no ar, mas uma parte extra não foi feita (veja os detalhes): "
                        + p.result;
            case "rolled-back":
                return "A versão nova não ligou. O servidor voltou para a versão anterior e está no ar. O banco ficou "
                        + "com as tabelas novas (só acrescentam). Veja o log em Logs > Atualização.";
            case "failed":
                return "Nada foi trocado ou o servidor pode estar parado: " + p.result + ". Veja Logs > Atualização.";
            default:
                return p.result;
        }
    }

    static int num(String s) {
        try {
            return Integer.parseInt(s.trim());
        } catch (Exception e) {
            return 0;
        }
    }
}
