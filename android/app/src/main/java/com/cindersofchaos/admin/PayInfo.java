package com.cindersofchaos.admin;

import java.util.LinkedHashMap;
import java.util.Map;
import java.util.regex.Pattern;

/**
 * The donations card (Pagamentos, O413) in Portuguese: the settings of chaos-ctl.sh pay-set, the same checks of each
 * value (so a typo is told on the phone before anything is sent) and the reading of pay-status. Pure Java, no Android
 * classes. A secret never leaves the phone except on the stdin of pay-set; pay-status never sends one back.
 */
final class PayInfo {
    /** Text settings of pay-set -> label in the app, in the order of the card (the choices are buttons). */
    static final Map<String, String> FIELDS = new LinkedHashMap<>();

    static {
        FIELDS.put("CHAOS_MP_ACCESS_TOKEN", "Mercado Pago: Access Token (senha)");
        FIELDS.put("CHAOS_MP_WEBHOOK_SECRET", "Mercado Pago: assinatura secreta do webhook (senha)");
        FIELDS.put("CHAOS_PAYPAL_CLIENT_ID", "PayPal: Client ID");
        FIELDS.put("CHAOS_PAYPAL_CLIENT_SECRET", "PayPal: Secret (senha)");
        FIELDS.put("CHAOS_PAYPAL_WEBHOOK_ID", "PayPal: Webhook ID");
        FIELDS.put("CHAOS_PAY_SITE_URL", "Endereço do site (vazio: o do site.env)");
        FIELDS.put("CHAOS_PAY_PAYER_EMAIL", "E-mail para Pix sem e-mail da conta");
    }

    private static final Map<String, Pattern> CHECK = new LinkedHashMap<>();

    static {
        // the same patterns as pay_value_ok in chaos-ctl.sh
        CHECK.put("CHAOS_PAY_PIX_PROVIDER", Pattern.compile("^(mercadopago|off)$"));
        CHECK.put("CHAOS_PAY_PAYPAL_PROVIDER", Pattern.compile("^(paypal|off)$"));
        CHECK.put("CHAOS_PAY_SITE_URL", Pattern.compile(
                "^https://[A-Za-z0-9]([A-Za-z0-9.-]{0,250}[A-Za-z0-9])?(:[0-9]{1,5})?(/[A-Za-z0-9._~/-]{0,200})?$"));
        CHECK.put("CHAOS_PAY_PAYER_EMAIL", Pattern.compile(
                "^[A-Za-z0-9._%+{}-]{1,64}@[A-Za-z0-9-]{1,63}(\\.[A-Za-z0-9-]{1,63}){0,8}\\.[A-Za-z]{2,24}$"));
        CHECK.put("CHAOS_MP_ACCESS_TOKEN", Pattern.compile("^(APP_USR|TEST)-[A-Za-z0-9-]{20,250}$"));
        CHECK.put("CHAOS_MP_WEBHOOK_SECRET", Pattern.compile("^[A-Za-z0-9_-]{16,200}$"));
        CHECK.put("CHAOS_PAYPAL_CLIENT_ID", Pattern.compile("^[A-Za-z0-9_-]{20,200}$"));
        CHECK.put("CHAOS_PAYPAL_CLIENT_SECRET", Pattern.compile("^[A-Za-z0-9_-]{20,200}$"));
        CHECK.put("CHAOS_PAYPAL_WEBHOOK_ID", Pattern.compile("^[A-Za-z0-9]{8,40}$"));
        CHECK.put("CHAOS_PAYPAL_ENV", Pattern.compile("^(sandbox|live)$"));
        CHECK.put("CHAOS_PAYPAL_CATEGORY", Pattern.compile("^(DONATION|DIGITAL_GOODS)$"));
    }

    private PayInfo() {
    }

    /** Every name pay-set takes. */
    static boolean known(String name) {
        return CHECK.containsKey(name);
    }

    /** A password: a masked field, the window secure while it holds text. */
    static boolean secret(String name) {
        return name.equals("CHAOS_MP_ACCESS_TOKEN") || name.equals("CHAOS_MP_WEBHOOK_SECRET")
                || name.equals("CHAOS_PAYPAL_CLIENT_SECRET");
    }

    /** The value as pay-set accepts it; empty is fine (it empties the setting). */
    static boolean valid(String name, String value) {
        Pattern p = CHECK.get(name);
        return p != null && value != null && (value.isEmpty() || p.matcher(value).matches());
    }

    /** What the field says when the value is refused. */
    static String hint(String name) {
        switch (name) {
            case "CHAOS_MP_ACCESS_TOKEN":
                return "Começa com APP_USR- (produção) ou TEST- (teste).";
            case "CHAOS_PAY_SITE_URL":
                return "Precisa começar com https:// (ex.: https://seu-site.com).";
            case "CHAOS_PAY_PAYER_EMAIL":
                return "Um e-mail (pode ter {account}, ex.: doacao+{account}@seu-dominio).";
            case "CHAOS_PAYPAL_WEBHOOK_ID":
                return "Só letras e números (ex.: 1JE4291016473214C).";
            default:
                return "Não parece esse valor. Copie de novo do painel.";
        }
    }

    /** The key=value lines of pay-status before the first "@" section. */
    static Map<String, String> parse(String out) {
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
        return kv;
    }

    /** What the card says about pay-status: the methods, the PayPal mode, the worker, what is missing. */
    static String summary(String out) {
        Map<String, String> kv = parse(out);
        if (kv.isEmpty()) {
            return "Toque em Estado.";
        }
        StringBuilder s = new StringBuilder();
        String pix = kv.getOrDefault("pix_provider", "off");
        String pp = kv.getOrDefault("paypal_provider", "off");
        s.append("Pix: ").append(pix.equals("mercadopago") ? "ligado (Mercado Pago" + tokenKind(kv) + ")" : word(pix));
        s.append(". PayPal: ").append(pp.equals("paypal")
                ? "ligado (" + ("live".equals(kv.get("paypal_env")) ? "live, dinheiro real" : "sandbox, teste") + ")" : word(pp));
        boolean active = "active".equals(kv.get("worker_active"));
        boolean enabled = "enabled".equals(kv.get("worker_enabled"));
        s.append(". Worker: ").append(active ? "rodando" : enabled ? "ativado, mas parado" : "desligado").append('.');
        String miss = missing(kv);
        if (!miss.isEmpty()) {
            s.append(" Falta: ").append(miss).append('.');
        }
        if ("yes".equals(kv.get("mock"))) {
            s.append(" ATENÇÃO: provedor mock no arquivo (doação sem dinheiro). Salve Desligado ou o provedor real.");
        }
        if ("no".equals(kv.get("env_ok")) && !"missing".equals(kv.get("env_file"))) {
            s.append(" O arquivo não está em 640 root:www-data: qualquer Salvar corrige.");
        }
        return s.toString();
    }

    private static String tokenKind(Map<String, String> kv) {
        String t = kv.getOrDefault("mp_token", "no");
        return t.equals("test") ? ", token de teste" : t.equals("live") ? "" : ", sem token";
    }

    private static String word(String provider) {
        return provider.equals("off") ? "desligado" : provider.equals("mock") ? "MOCK (teste sem dinheiro)" : provider;
    }

    /** The settings a method that is on still needs, as short names ("" when nothing is missing). */
    static String missing(Map<String, String> kv) {
        StringBuilder m = new StringBuilder();
        if ("mercadopago".equals(kv.get("pix_provider"))) {
            add(m, kv, "CHAOS_MP_ACCESS_TOKEN", "Access Token");
            add(m, kv, "CHAOS_MP_WEBHOOK_SECRET", "assinatura do webhook");
        }
        if ("paypal".equals(kv.get("paypal_provider"))) {
            add(m, kv, "CHAOS_PAYPAL_CLIENT_ID", "Client ID");
            add(m, kv, "CHAOS_PAYPAL_CLIENT_SECRET", "Secret");
            add(m, kv, "CHAOS_PAYPAL_WEBHOOK_ID", "Webhook ID");
        }
        if (("mercadopago".equals(kv.get("pix_provider")) || "paypal".equals(kv.get("paypal_provider")))
                && kv.getOrDefault("site_url", "").isEmpty()) {
            m.append(m.length() == 0 ? "" : ", ").append("endereço do site");
        }
        return m.toString();
    }

    private static void add(StringBuilder m, Map<String, String> kv, String key, String label) {
        if (!"yes".equals(kv.get("set_" + key))) {
            m.append(m.length() == 0 ? "" : ", ").append(label);
        }
    }

    /** The field's helper text after pay-status: saved or not, never the value. */
    static String fieldState(String out, String name) {
        String v = parse(out).get("set_" + name);
        if (v == null) {
            return "";
        }
        return v.equals("yes") ? "Salvo. Cole outro valor para trocar; vazio + Salvar apaga."
                : "Vazio. Cole o valor e toque em Salvar.";
    }

    /** The webhook URL to paste in the provider's panel (psp mercadopago or paypal), "" when the site has no address. */
    static String webhook(String out, String psp) {
        return parse(out).getOrDefault("webhook_" + psp, "");
    }
}
