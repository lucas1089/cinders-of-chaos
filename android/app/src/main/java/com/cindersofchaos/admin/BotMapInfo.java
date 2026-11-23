package com.cindersofchaos.admin;

import java.util.HashMap;
import java.util.Map;
import java.util.regex.Pattern;

/**
 * Comandos > Mapa dos bots (O727): the reading of the key=value lines of chaos-ctl.sh botmap-status (bots, stale, map=yes|no,
 * built, floors, size_mb, folder, page) and their wording in Portuguese, and the one address the card opens in the browser: the
 * staff page of the site (https only, a plain host and path, never a query we did not write). The page itself asks for the
 * site's staff login, so no password or token ever passes through the app. Pure Java, tested by BotMapInfoTest on a plain JVM.
 * server/README.md "Bot live map (O727)".
 */
final class BotMapInfo {
    final int bots;
    final int stale;
    final boolean map;
    final String built;
    final int floors;
    final String sizeMb;
    /** The staff page address, "" when the site's address is not known (CHAOS_SITE_URL) or not https. */
    final String page;

    private static final Pattern PAGE = Pattern.compile("^https://[A-Za-z0-9.-]+(:[0-9]{1,5})?(/[A-Za-z0-9._~/-]*)?/page\\?plugin=chaos&p=botmap$");

    private BotMapInfo(Map<String, String> kv) {
        bots = number(kv.get("bots"));
        stale = number(kv.get("stale"));
        map = "yes".equals(kv.get("map"));
        built = kv.getOrDefault("built", "");
        floors = number(kv.get("floors"));
        sizeMb = kv.getOrDefault("size_mb", "");
        page = safePage(kv.getOrDefault("page", ""));
    }

    private static int number(String s) {
        try {
            return s == null ? 0 : Math.max(0, Integer.parseInt(s.trim()));
        } catch (NumberFormatException e) {
            return 0;
        }
    }

    /** The address when it is the staff page over https, else "". */
    static String safePage(String url) {
        String u = url == null ? "" : url.trim();
        return PAGE.matcher(u).matches() ? u : "";
    }

    /** The lines of the command's output, or null when it has no bots= line (a refusal, an ssh error). */
    static BotMapInfo parse(String out) {
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
        if (!kv.containsKey("bots") || !kv.containsKey("map")) {
            return null;
        }
        return new BotMapInfo(kv);
    }

    /** The text under the card's Status button. */
    String summary() {
        StringBuilder t = new StringBuilder();
        if (bots == 0) {
            t.append("Nenhum bot publicando agora.");
        } else {
            t.append(bots).append(bots == 1 ? " bot" : " bots").append(" no mapa");
            if (stale > 0) {
                t.append(" (").append(stale).append(stale == 1 ? " sem notícia há mais de 2 minutos, em cinza" : " sem notícia há mais de 2 minutos, em cinza").append(")");
            }
            t.append('.');
        }
        t.append('\n');
        if (map) {
            t.append("Mapa montado");
            if (!built.isEmpty()) {
                t.append(" em ").append(built);
            }
            t.append(", ").append(floors).append(floors == 1 ? " andar" : " andares");
            if (!sizeMb.isEmpty()) {
                t.append(", ").append(sizeMb).append(" MB");
            }
            t.append('.');
        } else {
            t.append("O mapa ainda não foi montado: toque em Montar o mapa.");
        }
        if (page.isEmpty()) {
            t.append("\nO endereço do site não está configurado (CHAOS_SITE_URL em /etc/chaos/site.env): o botão Abrir o mapa não funciona.");
        }
        return t.toString();
    }
}
