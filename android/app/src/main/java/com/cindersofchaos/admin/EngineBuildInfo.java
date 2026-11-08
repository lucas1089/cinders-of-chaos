package com.cindersofchaos.admin;

import java.util.LinkedHashMap;
import java.util.Map;
import java.util.regex.Pattern;

/**
 * The card Recompilar engine (O436) in Portuguese: what chaos-ctl.sh engine-build status reports (the run of
 * windows-package.yml on GitHub), the answer of engine-build start, the refusals of both worded for the owner, and the
 * same shape check of the GitHub token as engine-build-token-set. Pure Java, no Android classes. The token never leaves the
 * phone except on the stdin of engine-build-token-set.
 */
final class EngineBuildInfo {
    /** The sentence of the confirmation: how long GitHub takes. */
    static final String DURATION = "de 20 a 60 minutos (a primeira vez, ou depois de uma mudança grande, pode passar de uma hora)";

    private static final Pattern TOKEN = Pattern.compile(
            "^(github_pat_[A-Za-z0-9_]{20,250}|gh[pousr]_[A-Za-z0-9]{30,250})$");

    final Map<String, String> kv = new LinkedHashMap<>();

    static EngineBuildInfo parse(String out) {
        EngineBuildInfo e = new EngineBuildInfo();
        for (String line : (out == null ? "" : out).split("\n")) {
            if (line.startsWith("@")) {
                break;
            }
            int eq = line.indexOf('=');
            if (eq > 0) {
                e.kv.putIfAbsent(line.substring(0, eq).trim(), line.substring(eq + 1).trim());
            }
        }
        return e;
    }

    /** The token as engine-build-token-set accepts it; empty is fine in the card only as "remove" (checked apart). */
    static boolean validToken(String token) {
        return token != null && TOKEN.matcher(token).matches();
    }

    String get(String k) {
        String v = kv.get(k);
        return v == null || v.equals("-") ? "" : v;
    }

    boolean valid() {
        return kv.containsKey("state");
    }

    String state() {
        return get("state");
    }

    /** Queued or in progress: the card keeps asking. */
    boolean running() {
        return state().equals("queued") || state().equals("in_progress");
    }

    boolean hasToken() {
        return get("token").equals("yes");
    }

    /** The build is done, its release has the engine and it is newer than the installed one: Atualizar servidor installs it. */
    boolean newer() {
        return state().equals("success") && get("release_newer").equals("yes");
    }

    /** The client program changed since the published client: the same build number is refused, a new one is offered. */
    boolean clientChanged() {
        return get("client_changed").equals("yes");
    }

    /** The build number a new client would get (live + 1), or "" when unknown. */
    String clientNext() {
        return get("client_next");
    }

    /** The label of the second button. */
    String newClientLabel() {
        return "Recompilar com client novo" + (clientNext().isEmpty() ? "" : " (build " + clientNext() + ")");
    }

    /** The confirmation of a build with a new client. */
    static String confirmNewClientText(String n) {
        String b = n.isEmpty() ? "novo" : n;
        return "O programa do client mudou desde o client publicado. O GitHub vai compilar o engine e um client "
                + "novo, com o número de build " + b + " (o atual continua aceito pelo servidor até a atualização). "
                + "O número entra sozinho na lista clientGuardBuilds do config.lua. Leva " + DURATION + ". O jogo segue "
                + "no ar. Depois, em Atualizar servidor, o client novo é publicado e os jogadores o recebem pelo "
                + "atualizador; o APK do Android precisa acompanhar (android-client.yml com client_build " + b + "), senão "
                + "os celulares ficam sem poder jogar.";
    }

    /** "37 min", "1 h 05 min", "40 s". */
    static String elapsed(int secs) {
        if (secs < 60) {
            return secs + " s";
        }
        int min = secs / 60;
        if (min < 60) {
            return min + " min";
        }
        return (min / 60) + " h " + String.format(java.util.Locale.ROOT, "%02d", min % 60) + " min";
    }

    private int secs() {
        try {
            return Integer.parseInt(get("elapsed_s"));
        } catch (NumberFormatException e) {
            return 0;
        }
    }

    /** One line over the card. */
    String headline() {
        String tag = get("release_tag");
        switch (state()) {
            case "none":
                return "Nenhuma recompilação feita ainda.";
            case "queued":
                return "Na fila do GitHub.";
            case "in_progress":
                return "Compilando no GitHub há " + elapsed(secs()) + ".";
            case "success":
                if (get("release_newer").equals("yes")) {
                    return "Pronto: " + tag + " tem o engine novo.";
                }
                if (get("release_ready").equals("no")) {
                    return "Terminou, mas " + tag + " ainda não mostra o engine. Atualize o estado em um minuto.";
                }
                return "Pronto, mas " + tag + " é a versão que já está instalada.";
            case "failure":
                return get("conclusion").equals("cancelled") ? "A recompilação foi cancelada no GitHub."
                        : "A recompilação falhou no GitHub.";
            case "unknown":
                return "Não consegui ler o GitHub.";
            default:
                return "";
        }
    }

    /** The lines under the headline: run, step, result, what to do next. */
    String details() {
        StringBuilder b = new StringBuilder();
        if (get("run_number").length() > 0) {
            b.append("Rodada ").append(get("run_number"));
            if (!get("commit").isEmpty()) {
                b.append(", código ").append(get("commit"));
            }
            if (!get("client_build").isEmpty() && !get("client_build").equals("unknown")) {
                b.append(", client build ").append(get("client_build"));
            }
            b.append('\n');
        }
        if (running()) {
            if (!get("job").isEmpty()) {
                b.append("Etapa: ").append(get("job"));
                if (!get("step").isEmpty()) {
                    b.append(" > ").append(get("step"));
                }
                b.append('\n');
            }
            if (!get("jobs_done").isEmpty()) {
                b.append("Etapas prontas: ").append(get("jobs_done")).append('\n');
            }
            b.append("O jogo segue no ar. Pode fechar o app; a compilação continua no GitHub.\n");
        } else if (state().equals("failure")) {
            if (!get("failed_job").isEmpty()) {
                b.append("Parou em ").append(get("failed_job"));
                if (!get("failed_step").isEmpty()) {
                    b.append(" > ").append(get("failed_step"));
                }
                b.append('\n');
            }
            b.append("Nada foi trocado no servidor. Veja os passos em Ver passos; o log completo está na página da rodada no GitHub.\n");
        } else if (state().equals("success")) {
            if (secs() > 0) {
                b.append("Levou ").append(elapsed(secs())).append(".\n");
            }
            if (newer()) {
                b.append("Próximo passo: em Atualizar servidor, toque em Verificar e depois em Aplicar e reiniciar. "
                        + "Ele baixa o engine novo, instala e confere se o servidor ligou.\n");
            }
        }
        if (!get("installed_release").isEmpty() && !state().equals("unknown")) {
            b.append("Instalado no servidor: ").append(get("installed_release").equals("unknown") ? "desconhecido"
                    : "winpkg-" + get("installed_release")).append('\n');
        }
        if (clientChanged() && !running()) {
            b.append("O programa do client mudou desde o client publicado: Recompilar com o mesmo número de build seria "
                    + "recusado. Use Recompilar com client novo").append(clientNext().isEmpty() ? "" : " (build " + clientNext() + ")")
                    .append(".\n");
        }
        if (!hasToken()) {
            b.append("Sem token do GitHub: toque em Definir token do GitHub antes de recompilar.\n");
        }
        return b.toString().trim();
    }

    /** The text of the confirmation before a build starts. */
    static String confirmText() {
        return "O GitHub compila o engine do servidor com todos os patches do código novo. Leva " + DURATION + ". "
                + "O jogo segue no ar e nada é trocado no servidor agora. Quando terminar, use Atualizar servidor "
                + "para instalar.";
    }

    /** What the start answered, in one line. */
    static String startText(String out) {
        EngineBuildInfo e = parse(out);
        if (!e.get("started").equals("yes")) {
            return "Não começou.";
        }
        String run = e.get("run_id");
        StringBuilder b = new StringBuilder("A recompilação começou no GitHub");
        if (!run.isEmpty() && !run.equals("unknown")) {
            b.append(" (rodada ").append(run).append(')');
        }
        b.append(", client build ").append(e.get("client_build")).append('.');
        if (e.get("guard").equals("added")) {
            b.append(" O build entrou na lista clientGuardBuilds do config.lua (os antigos continuam).");
        } else if (e.get("guard").equals("missing")) {
            b.append(" Atenção: não consegui editar clientGuardBuilds no config.lua; coloque o build nele antes de Atualizar servidor.");
        }
        for (String line : (out == null ? "" : out).split("\n")) {
            if (line.startsWith("note: client build")) {
                b.append(" É um número novo de client: depois de Atualizar servidor, publique também um APK com esse código.");
            }
        }
        return b.toString();
    }

    /** A refusal of chaos-ctl.sh (its "word: text" error line) in Portuguese; empty when the text is not one of ours. */
    static String refusal(String out) {
        String s = out == null ? "" : out;
        String[][] words = {
            {"token-missing", "Falta o token do GitHub. Toque em Definir token do GitHub e cole um token só deste repositório, com Actions leitura e escrita."},
            {"token-refused", "O GitHub recusou o token (401). Ele pode ter vencido ou sido apagado: defina um novo."},
            {"no-access", "O token não alcança o repositório ou não tem Actions leitura e escrita. Crie outro com essas permissões."},
            {"build-running", "Já há uma recompilação em andamento. Espere ela terminar."},
            {"client-changed", "O programa do client mudou desde o client publicado: o mesmo número de client apontaria para dois executáveis diferentes. Use Recompilar com client novo."},
            {"update-running", "Uma atualização do servidor está rodando. Espere ela terminar para recompilar com client novo."},
            {"client-build-backwards", "O número do client não pode ser menor que o do client publicado."},
            {"client-build-unknown", "Não há update de client publicado para tirar o número do client. Dê o número na linha de comando."},
            {"client-check-failed", "Não consegui comparar o programa do client com o publicado. Rode Atualizar servidor uma vez e tente de novo."},
            {"fetch-failed", "A VPS não conseguiu buscar o código no GitHub."},
            {"workflow-refused", "O GitHub recusou o pedido (422): a branch não tem o workflow manual de pacote."},
            {"dispatch-failed", "O GitHub não aceitou o pedido. Tente de novo em alguns minutos."},
            {"github-unreachable", "O GitHub não respondeu. Tente de novo em alguns minutos."},
        };
        for (String[] w : words) {
            if (s.contains(w[0] + ":")) {
                return w[1];
            }
        }
        return "";
    }
}
