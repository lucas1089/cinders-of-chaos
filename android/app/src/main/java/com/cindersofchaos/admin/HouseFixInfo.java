package com.cindersofchaos.admin;

import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Casas do mapa (O758): the reading of chaos-ctl.sh house-fix [--write] (the house fixer of O742). The command prints
 * key=value lines (house_fix=dry-run|written|nothing|refused, map=, backup=, server=started|start-failed) and then the
 * fixer's own lines ("N tile(s) to rewrite; H finding(s) for a human; K known and left", "refused: ..."). It exits 1 on a
 * refusal, so the lines are read whatever the exit code was. The one-line summary in Portuguese. Pure Java, tested by
 * HouseFixInfoTest on a plain JVM. server/README.md "House fixer (O742)".
 */
final class HouseFixInfo {
    static final String DRY_RUN = "house-fix";
    static final String WRITE = "house-fix --write";
    private static final Pattern PLAN = Pattern.compile(
            "(?m)^(\\d+) tile\\(s\\) to rewrite; (\\d+) finding\\(s\\) for a human; (\\d+) known and left");
    private static final Pattern REFUSED = Pattern.compile("(?m)^refused: (.*)$");

    private HouseFixInfo() {
    }

    /** What one run said. */
    static final class Result {
        final String state;
        final int tiles;
        final int human;
        final int known;
        final String backup;
        final String server;
        final String refusal;

        Result(String state, int tiles, int human, int known, String backup, String server, String refusal) {
            this.state = state;
            this.tiles = tiles;
            this.human = human;
            this.known = known;
            this.backup = backup;
            this.server = server;
            this.refusal = refusal;
        }
    }

    private static String value(String out, String key) {
        Matcher m = Pattern.compile("(?m)^" + key + "=(.*)$").matcher(out);
        return m.find() ? m.group(1).trim() : "";
    }

    /** The run in the command's output, or null when it has no house_fix line (a refusal of chaos-ctl, an ssh error). */
    static Result parse(String out) {
        if (out == null) {
            return null;
        }
        String state = value(out, "house_fix");
        if (state.isEmpty()) {
            return null;
        }
        int tiles = 0;
        int human = 0;
        int known = 0;
        Matcher p = PLAN.matcher(out);
        if (p.find()) {
            tiles = Integer.parseInt(p.group(1));
            human = Integer.parseInt(p.group(2));
            known = Integer.parseInt(p.group(3));
        }
        Matcher r = REFUSED.matcher(out);
        return new Result(state, tiles, human, known, value(out, "backup"), value(out, "server"),
                r.find() ? r.group(1).trim() : "");
    }

    private static String tiles(int n) {
        return n == 1 ? "1 tile" : n + " tiles";
    }

    /** One sentence in Portuguese. */
    static String summary(Result r) {
        if (r == null) {
            return "O corretor de casas não respondeu. Veja os detalhes.";
        }
        String rest = r.human == 0 ? "" : " " + r.human + (r.human == 1 ? " caso fica" : " casos ficam")
                + " para uma pessoa (porta, tamanho, andares): veja os detalhes.";
        String start = "start-failed".equals(r.server)
                ? " O servidor NÃO ligou de novo: ligue em Painel > Servidor > Ligar." : "";
        switch (r.state) {
            case "dry-run":
                return "Simulação: " + tiles(r.tiles) + " de casas a corrigir (flags de zona). Nada foi gravado." + rest;
            case "nothing":
                return "Nenhuma flag de casa a corrigir." + rest + start;
            case "written":
                return "Corrigido: " + tiles(r.tiles) + " gravados no mapa. Cópia do mapa antes: " + r.backup + "." + rest
                        + start;
            case "refused":
                return "O corretor recusou" + (r.refusal.isEmpty() ? "" : " (" + r.refusal + ")")
                        + ": o mapa ficou como estava." + start;
            default:
                return "Resposta desconhecida do corretor de casas: " + r.state + ".";
        }
    }
}
