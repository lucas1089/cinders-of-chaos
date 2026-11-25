package com.cindersofchaos.admin;

import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Dados de spawn (O765): the reading of chaos-ctl.sh spawn-data [--write] (the bounty pool, the bestiary spawns and the
 * map markers made again from the loaded map). The command prints key=value lines (bounty_pool and bestiary_spawns
 * =same|changed|new, NAME_repo_copy=same|differs, NAME_lines, poi= with --write, spawn_data=dry-run|nothing|written|failed,
 * restart_needed=yes|no) and then the generators' own lines. The one-line summary in Portuguese. Pure Java, tested by
 * SpawnDataInfoTest on a plain JVM. server/README.md "Spawn data from the loaded map (O765)".
 */
final class SpawnDataInfo {
    static final String DRY_RUN = "spawn-data";
    static final String WRITE = "spawn-data --write";

    private SpawnDataInfo() {
    }

    static String value(String out, String key) {
        if (out == null) {
            return "";
        }
        Matcher m = Pattern.compile("(?m)^" + Pattern.quote(key) + "=(.*)$").matcher(out);
        return m.find() ? m.group(1).trim() : "";
    }

    private static String file(String what, String state) {
        switch (state) {
            case "changed":
                return what + " muda";
            case "new":
                return what + " é novo";
            case "same":
                return what + " igual";
            default:
                return what + " ?";
        }
    }

    /** One sentence in Portuguese, or null when the output has no spawn_data line (a refusal of chaos-ctl, an ssh error). */
    static String summary(String out) {
        String state = value(out, "spawn_data");
        if (state.isEmpty()) {
            return null;
        }
        String files = file("caçadas (bounty)", value(out, "bounty_pool")) + ", "
                + file("bestiário", value(out, "bestiary_spawns"));
        boolean behind = value(out, "bounty_pool_repo_copy").equals("differs")
                || value(out, "bestiary_spawns_repo_copy").equals("differs");
        String repo = behind ? " O repositório ainda tem a cópia antiga: Atualizar servidor volta a ela até o "
                + "repositório receber os arquivos novos (rode de novo depois de cada atualização)." : "";
        switch (state) {
            case "dry-run":
                return "Do mapa carregado: " + files + ". Nada foi gravado: toque em Gravar dados de spawn." + repo;
            case "nothing":
                return "Os dados de spawn já batem com o mapa carregado (" + files + ")." + repo;
            case "written":
                String poi = value(out, "poi");
                return "Gravado: " + files + (poi.equals("changed") ? ", marcadores do mapa mudam" : "")
                        + (poi.equals("failed") ? ", marcadores do mapa falharam (veja os detalhes)" : "")
                        + ". Vale no próximo reinício (Painel > Reiniciar em...)." + repo;
            case "failed":
                return "Um gerador falhou (o mapa ou o config.lua não foram lidos). Nada foi gravado. Veja os detalhes.";
            default:
                return "Resposta desconhecida: veja os detalhes.";
        }
    }
}
