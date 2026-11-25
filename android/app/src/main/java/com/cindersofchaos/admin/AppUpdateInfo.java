package com.cindersofchaos.admin;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Self-update of the admin app (O765, owner 2026-11-25 "coloque um auto update no app do celular"): the pure part. Reads
 * the GitHub releases list of the public repository (GET /repos/OWNER/REPO/releases, no token), picks the newest
 * adminapp-N release (prereleases count, drafts do not; the highest N wins, since admin-app.yml sets versionCode to its
 * run number N), compares N with the installed versionCode and reads the CindersAdmin.apk.sha256 file the workflow
 * publishes next to the APK. A small JSON reader, so no Android class is needed: AppUpdateInfoTest runs it on a plain JVM.
 * docs/ADMIN_APP.md "Atualização do app".
 */
final class AppUpdateInfo {
    static final String REPO = "lucas1089/cinders-of-chaos";
    static final String API = "https://api.github.com/repos/" + REPO + "/releases?per_page=100";
    static final String APK = "CindersAdmin.apk";
    static final String SHA = "CindersAdmin.apk.sha256";
    /** The automatic check at start runs at most once in this many milliseconds. */
    static final long DAY_MS = 24L * 60 * 60 * 1000;
    private static final Pattern TAG = Pattern.compile("^adminapp-([1-9][0-9]{0,8})$");
    private static final Pattern HEX64 = Pattern.compile("(?i)(?:^|\\s)([0-9a-f]{64})(?:\\s|$)");

    private AppUpdateInfo() {
    }

    /** One adminapp-N release with its APK. */
    static final class Release {
        final int number;
        final String tag;
        final String apkUrl;
        final long apkSize;
        final String shaUrl;

        Release(int number, String tag, String apkUrl, long apkSize, String shaUrl) {
            this.number = number;
            this.tag = tag;
            this.apkUrl = apkUrl;
            this.apkSize = apkSize;
            this.shaUrl = shaUrl;
        }

        /** The version as the app shows it (admin-app.yml: versionName 2.N). */
        String versionName() {
            return "2." + number;
        }
    }

    /** True when the automatic check is due (last check time in ms, 0 = never). */
    static boolean due(long lastMs, long nowMs) {
        return lastMs <= 0 || nowMs - lastMs >= DAY_MS || nowMs < lastMs;
    }

    /** True when the release is newer than the installed versionCode. */
    static boolean newer(Release r, long versionCode) {
        return r != null && r.number > versionCode;
    }

    private static boolean httpsGithub(String url) {
        return url != null && url.startsWith("https://github.com/" + REPO + "/releases/download/");
    }

    /**
     * The newest usable adminapp-N release of the GitHub releases JSON (an array), or null: tag adminapp-N, not a draft,
     * an asset CindersAdmin.apk with a size above 0 and a download address of this repository on github.com, and an
     * asset CindersAdmin.apk.sha256 (a release without it is older than O765 and is skipped: its APK cannot be checked).
     */
    static Release pick(String json) {
        Object root;
        try {
            root = new Json(json).value();
        } catch (IllegalArgumentException e) {
            return null;
        }
        if (!(root instanceof List)) {
            return null;
        }
        Release best = null;
        for (Object o : (List<?>) root) {
            if (!(o instanceof Map)) {
                continue;
            }
            Map<?, ?> rel = (Map<?, ?>) o;
            Object tagO = rel.get("tag_name");
            if (!(tagO instanceof String) || Boolean.TRUE.equals(rel.get("draft"))) {
                continue;
            }
            Matcher m = TAG.matcher((String) tagO);
            if (!m.matches()) {
                continue;
            }
            int n = Integer.parseInt(m.group(1));
            String apkUrl = null;
            String shaUrl = null;
            long size = 0;
            Object assets = rel.get("assets");
            if (assets instanceof List) {
                for (Object ao : (List<?>) assets) {
                    if (!(ao instanceof Map)) {
                        continue;
                    }
                    Map<?, ?> as = (Map<?, ?>) ao;
                    Object name = as.get("name");
                    Object url = as.get("browser_download_url");
                    if (!(url instanceof String) || !httpsGithub((String) url)) {
                        continue;
                    }
                    if (APK.equals(name) && as.get("size") instanceof Number) {
                        apkUrl = (String) url;
                        size = ((Number) as.get("size")).longValue();
                    } else if (SHA.equals(name)) {
                        shaUrl = (String) url;
                    }
                }
            }
            if (apkUrl == null || shaUrl == null || size <= 0) {
                continue;
            }
            if (best == null || n > best.number) {
                best = new Release(n, (String) tagO, apkUrl, size, shaUrl);
            }
        }
        return best;
    }

    /** The SHA-256 of a .sha256 file ("HEX" or "HEX  NAME", sha256sum's format), lowercase, or "" when there is none. */
    static String shaOf(String text) {
        if (text == null) {
            return "";
        }
        Matcher m = HEX64.matcher(text.trim());
        return m.find() ? m.group(1).toLowerCase(Locale.ROOT) : "";
    }

    /** One sentence in Portuguese for the check's result. */
    static String summary(Release r, long versionCode) {
        if (r == null) {
            return "Nenhuma versão do app com atualização automática no GitHub ainda.";
        }
        if (!newer(r, versionCode)) {
            return "O app está na versão mais nova (2." + versionCode + ").";
        }
        return "Versão nova: " + r.versionName() + " (instalada: 2." + versionCode + "), "
                + String.format(Locale.ROOT, "%.1f", r.apkSize / 1048576.0).replace('.', ',') + " MB.";
    }

    /** The Portuguese words of a download failure code of AppApkFetcher. */
    static String failure(String code) {
        switch (code) {
            case "net":
                return "A conexão caiu. Tente de novo: o download continua de onde parou.";
            case "size":
                return "O arquivo baixado não tem o tamanho certo. Tente de novo.";
            case "hash":
                return "O arquivo baixado não confere (SHA-256). Nada foi instalado. Tente de novo.";
            case "storage":
                return "Sem espaço ou sem acesso à pasta do app no celular.";
            case "aborted":
                return "Download cancelado.";
            default:
                return "Não deu para baixar a atualização.";
        }
    }

    /** A small JSON reader: objects as maps, arrays as lists, strings, numbers (Long or Double), booleans, null. */
    static final class Json {
        private final String s;
        private int i;

        Json(String s) {
            this.s = s == null ? "" : s;
        }

        Object value() {
            Object v = read();
            ws();
            if (i != s.length()) {
                throw new IllegalArgumentException("trailing text at " + i);
            }
            return v;
        }

        private void ws() {
            while (i < s.length() && Character.isWhitespace(s.charAt(i))) {
                i++;
            }
        }

        private IllegalArgumentException bad(String what) {
            return new IllegalArgumentException(what + " at " + i);
        }

        private Object read() {
            ws();
            if (i >= s.length()) {
                throw bad("end");
            }
            char c = s.charAt(i);
            if (c == '{') {
                i++;
                Map<String, Object> m = new LinkedHashMap<>();
                ws();
                if (i < s.length() && s.charAt(i) == '}') {
                    i++;
                    return m;
                }
                while (true) {
                    ws();
                    if (i >= s.length() || s.charAt(i) != '"') {
                        throw bad("key");
                    }
                    String k = string();
                    ws();
                    if (i >= s.length() || s.charAt(i) != ':') {
                        throw bad("colon");
                    }
                    i++;
                    m.put(k, read());
                    ws();
                    if (i < s.length() && s.charAt(i) == ',') {
                        i++;
                    } else if (i < s.length() && s.charAt(i) == '}') {
                        i++;
                        return m;
                    } else {
                        throw bad("object");
                    }
                }
            }
            if (c == '[') {
                i++;
                List<Object> l = new ArrayList<>();
                ws();
                if (i < s.length() && s.charAt(i) == ']') {
                    i++;
                    return l;
                }
                while (true) {
                    l.add(read());
                    ws();
                    if (i < s.length() && s.charAt(i) == ',') {
                        i++;
                    } else if (i < s.length() && s.charAt(i) == ']') {
                        i++;
                        return l;
                    } else {
                        throw bad("array");
                    }
                }
            }
            if (c == '"') {
                return string();
            }
            if (s.startsWith("true", i)) {
                i += 4;
                return Boolean.TRUE;
            }
            if (s.startsWith("false", i)) {
                i += 5;
                return Boolean.FALSE;
            }
            if (s.startsWith("null", i)) {
                i += 4;
                return null;
            }
            int st = i;
            while (i < s.length() && "+-0123456789.eE".indexOf(s.charAt(i)) >= 0) {
                i++;
            }
            String num = s.substring(st, i);
            if (num.isEmpty()) {
                throw bad("value");
            }
            try {
                if (num.matches("-?[0-9]{1,18}")) {
                    return Long.parseLong(num);
                }
                return Double.parseDouble(num);
            } catch (NumberFormatException e) {
                throw bad("number");
            }
        }

        private String string() {
            i++; // the opening quote
            StringBuilder b = new StringBuilder();
            while (i < s.length()) {
                char c = s.charAt(i++);
                if (c == '"') {
                    return b.toString();
                }
                if (c != '\\') {
                    b.append(c);
                    continue;
                }
                if (i >= s.length()) {
                    break;
                }
                char e = s.charAt(i++);
                switch (e) {
                    case 'n':
                        b.append('\n');
                        break;
                    case 't':
                        b.append('\t');
                        break;
                    case 'r':
                        b.append('\r');
                        break;
                    case 'b':
                        b.append('\b');
                        break;
                    case 'f':
                        b.append('\f');
                        break;
                    case 'u':
                        if (i + 4 > s.length()) {
                            throw bad("escape");
                        }
                        try {
                            b.append((char) Integer.parseInt(s.substring(i, i + 4), 16));
                        } catch (NumberFormatException x) {
                            throw bad("escape");
                        }
                        i += 4;
                        break;
                    default:
                        b.append(e);
                }
            }
            throw bad("string");
        }
    }
}
