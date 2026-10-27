package com.cindersofchaos.admin;

import java.util.LinkedHashMap;
import java.util.Map;
import java.util.regex.Pattern;

/**
 * The Discord card in Portuguese: the channels of chaos-ctl.sh discord-set, the same strict check of a webhook URL
 * (so a typo is told on the phone before anything is sent) and the reading of discord-status. Pure Java, no Android
 * classes. The URL never leaves the phone except on the stdin of discord-set.
 */
final class DiscordInfo {
    /** Channel name of chaos-ctl.sh -> label in the app, in the order of the card. */
    static final Map<String, String> CHANNELS = new LinkedHashMap<>();

    static {
        CHANNELS.put("records", "Recordes e firsts do reino");
        CHANNELS.put("bosses", "Chefes (mundo, Ascended, Cinderheart)");
        CHANNELS.put("players", "Jogadores (níveis 500 e 1000)");
        CHANNELS.put("announce", "Anúncios (temporada, Crônica)");
        CHANNELS.put("status", "Status do servidor");
        CHANNELS.put("bazaar", "Character Bazaar");
        CHANNELS.put("drops", "Drops raros");
        CHANNELS.put("default", "Padrão (todo canal sem webhook próprio)");
    }

    private static final Pattern URL = Pattern.compile(
            "^https://(discord\\.com|discordapp\\.com|canary\\.discord\\.com|ptb\\.discord\\.com)"
                    + "/api/webhooks/[0-9]{5,25}/[A-Za-z0-9_-]{20,100}$");

    private DiscordInfo() {
    }

    /** The URL as discord-set accepts it (the same pattern as chaos-ctl.sh). */
    static boolean valid(String url) {
        return url != null && URL.matcher(url).matches();
    }

    /** What the card says about discord-status: the channels with a webhook, the timer. */
    static String summary(String out) {
        Map<String, String> kv = new LinkedHashMap<>();
        for (String line : (out == null ? "" : out).split("\n")) {
            if (line.startsWith("@")) {
                break;
            }
            int eq = line.indexOf('=');
            if (eq > 0) {
                kv.putIfAbsent(line.substring(0, eq).trim(), line.substring(eq + 1).trim());
            }
        }
        if (kv.isEmpty()) {
            return "Toque em Atualizar status.";
        }
        StringBuilder on = new StringBuilder();
        for (String ch : CHANNELS.keySet()) {
            String v = kv.get("channel_" + ch);
            if (v != null && v.startsWith("yes")) {
                on.append(on.length() == 0 ? "" : ", ").append(ch);
            }
        }
        boolean enabled = "enabled".equals(kv.get("timer_enabled"));
        boolean active = "active".equals(kv.get("timer_active"));
        String timer = enabled && active ? "ligado" : enabled ? "ativado, mas parado" : "desligado";
        return "Postagem: " + timer + ". Webhooks salvos: " + (on.length() == 0 ? "nenhum" : on) + ".";
    }

    /** Whether discord-status says the channel has a webhook, and its id's last digits ("" when none). */
    static String idEnd(String out, String channel) {
        for (String line : (out == null ? "" : out).split("\n")) {
            if (line.startsWith("@")) {
                break;
            }
            if (line.startsWith("channel_" + channel + "=yes")) {
                int i = line.indexOf("id_end=");
                return i < 0 ? "?" : line.substring(i + 7).trim();
            }
        }
        return "";
    }
}
