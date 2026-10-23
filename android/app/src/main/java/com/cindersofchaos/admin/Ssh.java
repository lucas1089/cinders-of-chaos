package com.cindersofchaos.admin;

import com.jcraft.jsch.ChannelExec;
import com.jcraft.jsch.HostKey;
import com.jcraft.jsch.JSch;
import com.jcraft.jsch.KeyPair;
import com.jcraft.jsch.Session;

import java.io.ByteArrayOutputStream;
import java.nio.charset.StandardCharsets;
import java.util.Properties;

/** The ssh connection: one session reused between commands, the server's host key pinned on first use. */
final class Ssh {
    static final class Result {
        final String out;
        final int code;

        Result(String out, int code) {
            this.out = out;
            this.code = code;
        }
    }

    /** Set when the last connect saw this host for the first time (the app shows the fingerprint to compare). */
    static volatile String newHostFingerprint = "";

    private static JSch jsch;
    private static Session session;

    private Ssh() {
    }

    /** A new RSA 3072 key; returns {privatePem, publicLine}. */
    static String[] generateKey() throws Exception {
        JSch j = new JSch();
        KeyPair kp = KeyPair.genKeyPair(j, KeyPair.RSA, 3072);
        ByteArrayOutputStream priv = new ByteArrayOutputStream();
        ByteArrayOutputStream pub = new ByteArrayOutputStream();
        kp.writePrivateKey(priv);
        kp.writePublicKey(pub, "cinders-admin-app");
        kp.dispose();
        return new String[]{priv.toString("UTF-8"), pub.toString("UTF-8").trim()};
    }

    static synchronized void close() {
        if (session != null) {
            session.disconnect();
            session = null;
        }
    }

    private static synchronized Session connect(Store st) throws Exception {
        if (session != null && session.isConnected()) {
            return session;
        }
        close();
        if (st.host().isEmpty()) {
            throw new IllegalStateException("Sem servidor: preencha a aba Config.");
        }
        byte[] priv = st.loadKey();
        jsch = new JSch();
        jsch.addIdentity("cinders", priv, st.publicKey().getBytes(StandardCharsets.UTF_8), null);
        Session s = jsch.getSession(st.user(), st.host(), st.port());
        Properties cfg = new Properties();
        // the host key is checked below against the one pinned on the first connection
        cfg.put("StrictHostKeyChecking", "no");
        cfg.put("PreferredAuthentications", "publickey");
        s.setConfig(cfg);
        s.setServerAliveInterval(15000);
        s.connect(12000);
        HostKey hk = s.getHostKey();
        String fp = hk.getFingerPrint(jsch);
        String pinned = st.hostFingerprint();
        if (pinned.isEmpty()) {
            st.put("hostfp", fp);
            newHostFingerprint = fp;
        } else if (!pinned.equals(fp)) {
            s.disconnect();
            throw new SecurityException("A chave do servidor mudou (" + fp + "). Pode ser um ataque, ou o servidor foi "
                    + "reinstalado. Se foi voce, apague a impressao digital na aba Config.");
        }
        session = s;
        return s;
    }

    static Result exec(Store st, String command, int timeoutSec) throws Exception {
        return exec(st, command, timeoutSec, null);
    }

    /** As exec, with STDIN given to the command (a password: never on its command line). */
    static Result exec(Store st, String command, int timeoutSec, String stdin) throws Exception {
        Session s;
        try {
            s = connect(st);
        } catch (SecurityException e) {
            throw e;
        } catch (Exception first) {
            close();
            s = connect(st);
        }
        ChannelExec ch = (ChannelExec) s.openChannel("exec");
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        try {
            ch.setCommand(command);
            ch.setInputStream(stdin == null ? null
                    : new java.io.ByteArrayInputStream(stdin.getBytes(StandardCharsets.UTF_8)));
            ch.setOutputStream(out);
            ch.setErrStream(out);
            ch.connect(10000);
            long end = System.currentTimeMillis() + timeoutSec * 1000L;
            while (!ch.isClosed()) {
                if (System.currentTimeMillis() > end) {
                    out.write("\n[tempo esgotado]\n".getBytes(StandardCharsets.UTF_8));
                    break;
                }
                Thread.sleep(80);
            }
            Thread.sleep(80);
            return new Result(out.toString("UTF-8"), ch.getExitStatus());
        } finally {
            ch.disconnect();
        }
    }

    /** One line of a streamed command's stdout (without the line end), on the streaming thread. */
    interface Lines {
        void line(String line);
    }

    /** Lets another thread end a stream: closing the channel closes the command's stdin on the server. */
    static final class Stream {
        private volatile ChannelExec ch;
        private volatile boolean cancelled;

        void cancel() {
            cancelled = true;
            ChannelExec c = ch;
            if (c != null) {
                c.disconnect();
            }
        }

        boolean cancelled() {
            return cancelled;
        }
    }

    /**
     * Runs a long command and hands each line of its stdout to sink as it comes (chaos-ctl.sh cast: JSON lines). The
     * command's stdin stays open until the stream ends (cancel(), the command ends, or the connection drops); stderr
     * is dropped. Lines over 8 MiB end the stream. Blocks; returns the exit status (-1 when cancelled or cut).
     */
    static int stream(Store st, String command, Lines sink, Stream handle) throws Exception {
        Session s;
        try {
            s = connect(st);
        } catch (SecurityException e) {
            throw e;
        } catch (Exception first) {
            close();
            s = connect(st);
        }
        ChannelExec ch = (ChannelExec) s.openChannel("exec");
        handle.ch = ch;
        try {
            ch.setCommand(command);
            ch.setPty(false);
            ch.setErrStream(new java.io.OutputStream() {
                @Override
                public void write(int b) {
                }

                @Override
                public void write(byte[] b, int off, int len) {
                }
            });
            java.io.InputStream in = ch.getInputStream();
            if (handle.cancelled) {
                return -1;
            }
            ch.connect(10000);
            java.io.BufferedReader r = new java.io.BufferedReader(
                    new java.io.InputStreamReader(in, StandardCharsets.UTF_8), 65536);
            StringBuilder line = new StringBuilder();
            char[] buf = new char[65536];
            int n;
            while (!handle.cancelled && (n = r.read(buf)) >= 0) {
                int start = 0;
                for (int i = 0; i < n; i++) {
                    if (buf[i] == '\n') {
                        line.append(buf, start, i - start);
                        sink.line(line.toString());
                        line.setLength(0);
                        start = i + 1;
                    }
                }
                line.append(buf, start, n - start);
                if (line.length() > 8 * 1024 * 1024) {
                    throw new java.io.IOException("linha longa demais");
                }
            }
            return handle.cancelled ? -1 : ch.getExitStatus();
        } catch (java.io.IOException e) {
            if (handle.cancelled) {
                return -1;
            }
            throw e;
        } finally {
            handle.ch = null;
            ch.disconnect();
        }
    }

    /** Single quotes around a text for the remote shell. */
    static String sq(String s) {
        return "'" + s.replace("'", "'\\''") + "'";
    }
}
