package com.cindersofchaos.admin;

/**
 * Plain-JVM check of PayInfo (no JUnit needed): javac -d out app/src/main/java/com/cindersofchaos/admin/PayInfo.java
 * app/src/test/java/com/cindersofchaos/admin/PayInfoTest.java && java -cp out com.cindersofchaos.admin.PayInfoTest
 */
public final class PayInfoTest {
    private static int fails = 0;
    private static int count = 0;

    private static void expect(boolean ok, String what) {
        count++;
        if (!ok) {
            fails++;
            System.out.println("FAIL " + what);
        }
    }

    public static void main(String[] args) {
        String tok = "APP_USR-1234567890123456-110512-0a1b2c3d4e5f60718293a4b5c6d7e8f9-123456789";
        expect(PayInfo.valid("CHAOS_MP_ACCESS_TOKEN", tok), "live token");
        expect(PayInfo.valid("CHAOS_MP_ACCESS_TOKEN", "TEST-" + tok.substring(8)), "test token");
        expect(PayInfo.valid("CHAOS_MP_ACCESS_TOKEN", ""), "empty empties");
        expect(PayInfo.valid("CHAOS_PAY_PIX_PROVIDER", "mercadopago") && PayInfo.valid("CHAOS_PAY_PIX_PROVIDER", "off"), "pix provider");
        expect(PayInfo.valid("CHAOS_PAY_PAYPAL_PROVIDER", "paypal") && PayInfo.valid("CHAOS_PAYPAL_ENV", "live")
                && PayInfo.valid("CHAOS_PAYPAL_ENV", "sandbox"), "paypal provider and env");
        expect(PayInfo.valid("CHAOS_PAY_SITE_URL", "https://example.org") && PayInfo.valid("CHAOS_PAY_SITE_URL", "https://a.example.org:8443/site/"),
                "site url");
        expect(PayInfo.valid("CHAOS_PAY_PAYER_EMAIL", "donor+{account}@example.org"), "payer e-mail pattern");
        expect(PayInfo.valid("CHAOS_PAYPAL_WEBHOOK_ID", "1JE4291016473214C"), "webhook id");
        String[][] bad = {{"CHAOS_PAY_PIX_PROVIDER", "mock"}, {"CHAOS_PAY_PAYPAL_PROVIDER", "mock"}, {"CHAOS_PAYPAL_ENV", "production"},
            {"CHAOS_PAY_SITE_URL", "http://example.org"}, {"CHAOS_PAY_SITE_URL", "https://example.org/?a=1"},
            {"CHAOS_PAY_SITE_URL", "https://u@example.org"}, {"CHAOS_MP_ACCESS_TOKEN", "abc"},
            {"CHAOS_MP_ACCESS_TOKEN", tok + "$(id)"}, {"CHAOS_MP_ACCESS_TOKEN", " " + tok},
            {"CHAOS_MP_WEBHOOK_SECRET", "abc\nX=1"}, {"CHAOS_PAYPAL_CLIENT_SECRET", "short"},
            {"CHAOS_PAYPAL_WEBHOOK_ID", "ab cd"}, {"CHAOS_PAY_PAYER_EMAIL", "nope"}, {"CHAOS_PAYPAL_CATEGORY", "GOODS"},
            {"CHAOS_PAY_ALLOW_MOCK", "1"}, {"CHAOS_PAY_PAYER_SALT", "x"}};
        for (String[] b : bad) {
            expect(!PayInfo.valid(b[0], b[1]), "refused: " + b[0] + "=" + b[1].replace("\n", "\\n"));
        }
        expect(!PayInfo.valid("CHAOS_MP_ACCESS_TOKEN", null), "null");
        expect(PayInfo.secret("CHAOS_MP_ACCESS_TOKEN") && PayInfo.secret("CHAOS_PAYPAL_CLIENT_SECRET")
                && !PayInfo.secret("CHAOS_PAYPAL_CLIENT_ID"), "secrets");
        for (String k : PayInfo.FIELDS.keySet()) {
            expect(PayInfo.known(k), "field is a pay-set name: " + k);
        }
        expect(!PayInfo.known("CHAOS_PAY_ALLOW_MOCK"), "mock switch is not settable");

        String out = "pix_provider=mercadopago\npaypal_provider=paypal\npaypal_env=sandbox\nmp_token=test\n"
                + "set_CHAOS_MP_ACCESS_TOKEN=yes\nset_CHAOS_MP_WEBHOOK_SECRET=no\nset_CHAOS_PAYPAL_CLIENT_ID=yes\n"
                + "set_CHAOS_PAYPAL_CLIENT_SECRET=yes\nset_CHAOS_PAYPAL_WEBHOOK_ID=yes\nenv_file=640 root:www-data\nenv_ok=yes\n"
                + "site_url=https://example.org\nwebhook_mercadopago=https://example.org/chaos_pay_webhook.php?psp=mercadopago\n"
                + "webhook_paypal=https://example.org/chaos_pay_webhook.php?psp=paypal\nworker_enabled=enabled\nworker_active=active\n"
                + "mock=no\n@log\nwebhook_paypal=https://evil.example/\n";
        String sum = PayInfo.summary(out);
        expect(sum.equals("Pix: ligado (Mercado Pago, token de teste). PayPal: ligado (sandbox, teste). Worker: rodando. "
                + "Falta: assinatura do webhook."), "summary: " + sum);
        expect(PayInfo.webhook(out, "paypal").equals("https://example.org/chaos_pay_webhook.php?psp=paypal"), "webhook before @log");
        expect(PayInfo.webhook(out, "mercadopago").endsWith("?psp=mercadopago"), "mp webhook");
        expect(PayInfo.fieldState(out, "CHAOS_MP_ACCESS_TOKEN").startsWith("Salvo") && PayInfo.fieldState(out, "CHAOS_MP_WEBHOOK_SECRET").startsWith("Vazio")
                && PayInfo.fieldState(out, "CHAOS_PAY_SITE_URL").isEmpty(), "field states");
        String off = "pix_provider=off\npaypal_provider=off\nworker_enabled=disabled\nworker_active=inactive\nenv_file=missing\nenv_ok=no\n";
        expect(PayInfo.summary(off).equals("Pix: desligado. PayPal: desligado. Worker: desligado."), "off: " + PayInfo.summary(off));
        String mock = "pix_provider=mock\npaypal_provider=paypal\npaypal_env=live\nset_CHAOS_PAYPAL_CLIENT_ID=yes\n"
                + "set_CHAOS_PAYPAL_CLIENT_SECRET=yes\nset_CHAOS_PAYPAL_WEBHOOK_ID=yes\nsite_url=\nmock=yes\nenv_ok=no\nenv_file=644 root:root\n";
        String ms = PayInfo.summary(mock);
        expect(ms.contains("MOCK") && ms.contains("ATENÇÃO") && ms.contains("live, dinheiro real") && ms.contains("Falta: endereço do site")
                && ms.contains("640"), "mock, live, no site, bad mode: " + ms);
        expect(PayInfo.summary("").equals("Toque em Estado."), "empty");
        expect(PayInfo.webhook("", "paypal").isEmpty(), "no webhook before status");
        System.out.println("PayInfoTest: " + count + " checks, " + fails + " failures");
        System.exit(fails == 0 ? 0 : 1);
    }
}
