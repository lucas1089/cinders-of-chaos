package com.cindersofchaos.admin;

import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.Rect;
import android.graphics.Typeface;
import android.os.SystemClock;
import android.util.Base64;
import android.view.View;

import org.json.JSONArray;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.Iterator;
import java.util.List;
import java.util.Map;

/**
 * The live cast (Comandos > Ações rápidas > Assistir jogador > Ao vivo): draws the JSON lines of
 * server/tools/cast_relay.py at about 30 frames a second. The client's 15 x 11 tiles of the player's floor, scaled up
 * without smoothing: items with their patterns and animation frames, elevation, creatures walking between tiles with
 * their walking frames, effects, missiles, health bars, names, speech and the numbers over the creatures. The camera
 * follows the player's steps. Not drawn: other floors, light and the client's own interface.
 * Lines come in on the streaming thread (apply), drawing on the screen thread; both under this object's lock.
 */
final class CastView extends View {
    static final int VIEW_W = 15;
    static final int VIEW_H = 11;
    static final int TILE = 32;
    private static final long FRAME_MS = 33;
    private static final int MAX_EVENTS = 200;

    private static final class Sheet {
        Bitmap bmp;
        int cw, ch, ax, ay, np, nf, fd, ni, nw, el;
    }

    private static final class Entry {
        String key;
        int pattern, lift;
    }

    private static final class Tile {
        Entry[] under, over;
        int elev;
    }

    private static final class Cr {
        String name = "", outfit;
        int hp, dir = 2, x, y, z, type;
        boolean placed;
        int fromX, fromY;
        long walkStart, walkMs;
    }

    private static final class Fx {
        int x, y, x2, y2, pattern, colour;
        String key, text, name;
        long start, ms;
    }

    private final Map<String, Sheet> sheets = new HashMap<>();
    private final Map<Long, Tile> tiles = new HashMap<>();
    private final Map<Long, Cr> creatures = new HashMap<>();
    private final List<Fx> effects = new ArrayList<>();
    private final List<Fx> missiles = new ArrayList<>();
    private final List<Fx> numbers = new ArrayList<>();
    private final List<Fx> speech = new ArrayList<>();
    private int cx, cy, cz;
    private boolean known;
    private long player;
    private JSONObject stats;
    private boolean animating;

    private Bitmap frame;
    private Canvas frameCanvas;
    private final Paint pixel = new Paint();
    private final Paint fill = new Paint();
    private final Paint text = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint outline = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Rect src = new Rect();
    private final Rect dst = new Rect();

    CastView(Context c) {
        super(c);
        pixel.setFilterBitmap(false);
        pixel.setAntiAlias(false);
        pixel.setDither(false);
        text.setTypeface(Typeface.create(Typeface.DEFAULT, Typeface.BOLD));
        outline.setTypeface(text.getTypeface());
        outline.setStyle(Paint.Style.STROKE);
        outline.setColor(Color.BLACK);
        setContentDescription("Visão ao vivo do personagem");
    }

    private static long key(int x, int y) {
        return ((long) x << 32) ^ (y & 0xffffffffL);
    }

    // ------------------------------------------------------------------------------------------------ lines in

    /** Forgets the view (a new hello, or the card starts again). */
    synchronized void clear() {
        tiles.clear();
        creatures.clear();
        effects.clear();
        missiles.clear();
        numbers.clear();
        speech.clear();
        known = false;
        stats = null;
    }

    /** Drops the sheets too (a new run of the relay sends them again). */
    synchronized void reset() {
        clear();
        for (Sheet s : sheets.values()) {
            if (s.bmp != null) {
                s.bmp.recycle();
            }
        }
        sheets.clear();
    }

    /** The player's stats of the last line (null before the first). */
    synchronized JSONObject stats() {
        return stats;
    }

    /** One JSON line of the relay; returns its type. Called on the streaming thread. */
    String apply(JSONObject j) {
        String t = j.optString("t");
        if ("spr".equals(t)) {
            Sheet s = sheet(j);
            synchronized (this) {
                if (s != null) {
                    Sheet old = sheets.put(j.optString("key"), s);
                    if (old != null && old.bmp != null) {
                        old.bmp.recycle();
                    }
                }
            }
        } else if ("hello".equals(t)) {
            synchronized (this) {
                clear();
                player = j.optLong("id");
            }
        } else if ("full".equals(t)) {
            synchronized (this) {
                tiles.clear();
                creatures.clear();
                camera(j.optJSONArray("c"));
                player = j.optLong("id", player);
                tiles(j.optJSONArray("tiles"));
                creatures(j.optJSONObject("cr"), now());
                if (j.has("st")) {
                    stats = j.optJSONObject("st");
                }
                known = true;
            }
        } else if ("d".equals(t)) {
            synchronized (this) {
                long now = now();
                if (j.has("c")) {
                    camera(j.optJSONArray("c"));
                }
                tiles(j.optJSONArray("tiles"));
                creatures(j.optJSONObject("cr"), now);
                walks(j.optJSONArray("walk"), now);
                events(j, now);
                if (j.has("st")) {
                    stats = j.optJSONObject("st");
                }
            }
        }
        return t;
    }

    private static Sheet sheet(JSONObject j) {
        byte[] png;
        try {
            png = Base64.decode(j.optString("png"), Base64.DEFAULT);
        } catch (IllegalArgumentException e) {
            return null;
        }
        BitmapFactory.Options o = new BitmapFactory.Options();
        o.inScaled = false;
        o.inPreferredConfig = Bitmap.Config.ARGB_8888;
        Bitmap b = BitmapFactory.decodeByteArray(png, 0, png.length, o);
        if (b == null) {
            return null;
        }
        Sheet s = new Sheet();
        s.bmp = b;
        s.cw = Math.max(1, j.optInt("cw", 32));
        s.ch = Math.max(1, j.optInt("ch", 32));
        s.ax = j.optInt("ax");
        s.ay = j.optInt("ay");
        s.np = Math.max(1, j.optInt("np", 4));
        s.nf = Math.max(1, j.optInt("nf", 1));
        s.fd = Math.max(10, j.optInt("fd", 100));
        s.ni = Math.max(0, j.optInt("ni", 1));
        s.nw = Math.max(0, j.optInt("nw", 0));
        s.el = j.optInt("el");
        return s;
    }

    private void camera(JSONArray c) {
        if (c != null && c.length() == 3) {
            int z = c.optInt(2);
            if (z != cz) {
                tiles.clear();
            }
            cx = c.optInt(0);
            cy = c.optInt(1);
            cz = z;
        }
    }

    private void tiles(JSONArray a) {
        if (a == null) {
            return;
        }
        for (int i = 0; i < a.length(); i++) {
            JSONArray t = a.optJSONArray(i);
            if (t == null || t.length() < 5) {
                continue;
            }
            Tile tile = new Tile();
            tile.under = entries(t.optJSONArray(2));
            tile.over = entries(t.optJSONArray(3));
            tile.elev = t.optInt(4);
            long k = key(t.optInt(0), t.optInt(1));
            if (tile.under.length == 0 && tile.over.length == 0) {
                tiles.remove(k);
            } else {
                tiles.put(k, tile);
            }
        }
        // tiles far from the camera are not drawn again
        if (tiles.size() > 2000) {
            Iterator<Map.Entry<Long, Tile>> it = tiles.entrySet().iterator();
            while (it.hasNext()) {
                long k = it.next().getKey();
                int x = (int) (k >> 32), y = (int) k;
                if (Math.abs(x - cx) > 20 || Math.abs(y - cy) > 20) {
                    it.remove();
                }
            }
        }
    }

    private static Entry[] entries(JSONArray a) {
        if (a == null) {
            return new Entry[0];
        }
        Entry[] out = new Entry[a.length()];
        for (int i = 0; i < out.length; i++) {
            JSONArray e = a.optJSONArray(i);
            Entry en = new Entry();
            en.key = e != null ? e.optString(0) : "";
            en.pattern = e != null ? e.optInt(1) : 0;
            en.lift = e != null ? e.optInt(2) : 0;
            out[i] = en;
        }
        return out;
    }

    private void creatures(JSONObject o, long now) {
        if (o == null) {
            return;
        }
        Iterator<String> ids = o.keys();
        while (ids.hasNext()) {
            String id = ids.next();
            JSONObject c = o.optJSONObject(id);
            long cid;
            try {
                cid = Long.parseLong(id);
            } catch (NumberFormatException e) {
                continue;
            }
            if (c == null) {
                continue;
            }
            Cr cr = creatures.get(cid);
            if (cr == null) {
                cr = new Cr();
                creatures.put(cid, cr);
            }
            cr.name = c.optString("n");
            cr.hp = c.optInt("hp");
            cr.dir = c.optInt("d", 2) & 3;
            cr.outfit = c.isNull("o") ? null : c.optString("o", null);
            cr.type = c.optInt("ty");
            JSONArray p = c.optJSONArray("p");
            if (p != null && p.length() == 3) {
                int x = p.optInt(0), y = p.optInt(1);
                if (cr.placed && (x != cr.x || y != cr.y) && now - cr.walkStart >= cr.walkMs) {
                    cr.walkMs = 0;      // moved without a walk: no sliding
                }
                cr.x = x;
                cr.y = y;
                cr.z = p.optInt(2);
                cr.placed = true;
            } else {
                cr.placed = false;
            }
        }
    }

    private void walks(JSONArray a, long now) {
        if (a == null) {
            return;
        }
        for (int i = 0; i < a.length(); i++) {
            JSONArray w = a.optJSONArray(i);
            if (w == null || w.length() < 6) {
                continue;
            }
            Cr cr = creatures.get(w.optLong(0));
            if (cr == null) {
                continue;
            }
            cr.fromX = w.optInt(1);
            cr.fromY = w.optInt(2);
            cr.walkStart = now;
            cr.walkMs = Math.max(50, Math.min(3000, w.optInt(5)));
        }
    }

    private void events(JSONObject j, long now) {
        JSONArray a = j.optJSONArray("fx");
        for (int i = 0; a != null && i < a.length() && effects.size() < MAX_EVENTS; i++) {
            JSONArray e = a.optJSONArray(i);
            if (e == null) {
                continue;
            }
            Fx f = new Fx();
            f.x = e.optInt(0);
            f.y = e.optInt(1);
            f.key = e.optString(2);
            f.pattern = e.optInt(3);
            f.start = now;
            Sheet s = sheets.get(f.key);
            f.ms = s != null ? (long) s.nf * s.fd : 600;
            effects.add(f);
        }
        a = j.optJSONArray("mi");
        for (int i = 0; a != null && i < a.length() && missiles.size() < MAX_EVENTS; i++) {
            JSONArray e = a.optJSONArray(i);
            if (e == null) {
                continue;
            }
            Fx f = new Fx();
            f.x = e.optInt(0);
            f.y = e.optInt(1);
            f.x2 = e.optInt(2);
            f.y2 = e.optInt(3);
            f.key = e.optString(4);
            f.pattern = e.optInt(5);
            f.ms = Math.max(50, e.optInt(6, 300));
            f.start = now;
            missiles.add(f);
        }
        a = j.optJSONArray("tx");
        for (int i = 0; a != null && i < a.length() && numbers.size() < MAX_EVENTS; i++) {
            JSONArray e = a.optJSONArray(i);
            if (e == null) {
                continue;
            }
            Fx f = new Fx();
            f.x = e.optInt(0);
            f.y = e.optInt(1);
            f.colour = colour216(e.optInt(2));
            f.text = e.optString(3);
            f.start = now;
            f.ms = 1000;
            numbers.add(f);
        }
        a = j.optJSONArray("say");
        for (int i = 0; a != null && i < a.length(); i++) {
            JSONArray e = a.optJSONArray(i);
            if (e == null) {
                continue;
            }
            Fx f = new Fx();
            f.x = e.optInt(0);
            f.y = e.optInt(1);
            int kind = e.optInt(2);
            f.name = e.optString(3);
            f.text = e.optString(4);
            f.colour = kind >= 36 ? Color.rgb(0xF0, 0x80, 0x10) : Color.rgb(0xFF, 0xFF, 0x00);
            f.start = now;
            f.ms = 3000 + 40L * f.text.length();
            // one speech bubble per speaker
            for (Iterator<Fx> it = speech.iterator(); it.hasNext(); ) {
                if (it.next().name.equals(f.name)) {
                    it.remove();
                }
            }
            speech.add(f);
            if (speech.size() > 20) {
                speech.remove(0);
            }
        }
    }

    /** the client's 8-bit colour: 6 x 6 x 6 */
    static int colour216(int c) {
        c = Math.max(0, Math.min(215, c));
        return Color.rgb(c / 36 * 51, c / 6 % 6 * 51, c % 6 * 51);
    }

    // ------------------------------------------------------------------------------------------------ drawing

    /** Starts or stops the redraw loop (about 30 frames a second while running). */
    void animate(boolean on) {
        animating = on;
        if (on) {
            postInvalidateOnAnimation();
        }
    }

    private static long now() {
        return SystemClock.uptimeMillis();
    }

    @Override
    protected void onMeasure(int wSpec, int hSpec) {
        int w = MeasureSpec.getSize(wSpec);
        setMeasuredDimension(w, w * VIEW_H / VIEW_W);
    }

    @Override
    protected void onDraw(Canvas canvas) {
        super.onDraw(canvas);
        long now = now();
        canvas.drawColor(Color.BLACK);
        synchronized (this) {
            if (known) {
                draw(canvas, now);
            }
        }
        if (animating) {
            postInvalidateDelayed(FRAME_MS);
        }
    }

    /** walk progress offset in pixels of a creature: where it still is between its old tile and its new one */
    private static float[] offset(Cr c, long now) {
        if (c.walkMs <= 0 || now - c.walkStart >= c.walkMs) {
            return new float[]{0, 0};
        }
        float left = 1f - (float) (now - c.walkStart) / c.walkMs;
        return new float[]{(c.fromX - c.x) * TILE * left, (c.fromY - c.y) * TILE * left};
    }

    private void draw(Canvas screen, long now) {
        if (frame == null) {
            frame = Bitmap.createBitmap(VIEW_W * TILE, VIEW_H * TILE, Bitmap.Config.ARGB_8888);
            frameCanvas = new Canvas(frame);
        }
        Canvas c = frameCanvas;
        c.drawColor(Color.BLACK);
        // the camera follows the player's step
        Cr me = creatures.get(player);
        float camX = 0, camY = 0;
        if (me != null && me.placed && me.x == cx && me.y == cy) {
            float[] o = offset(me, now);
            camX = o[0];
            camY = o[1];
        }
        int ox = (cx - VIEW_W / 2) * TILE + Math.round(camX);
        int oy = (cy - VIEW_H / 2) * TILE + Math.round(camY);
        Map<Long, List<Cr>> on = new HashMap<>();
        for (Cr cr : creatures.values()) {
            if (cr.placed && cr.z == cz) {
                on.computeIfAbsent(key(cr.x, cr.y), k -> new ArrayList<>()).add(cr);
            }
        }
        List<float[]> bars = new ArrayList<>();
        List<Cr> barCr = new ArrayList<>();
        for (int ty = cy - VIEW_H / 2 - 1; ty <= cy + VIEW_H / 2 + 2; ty++) {
            for (int tx = cx - VIEW_W / 2 - 1; tx <= cx + VIEW_W / 2 + 2; tx++) {
                long k = key(tx, ty);
                Tile t = tiles.get(k);
                int left = tx * TILE - ox, top = ty * TILE - oy;
                if (t != null) {
                    for (Entry e : t.under) {
                        item(c, e, left, top, now);
                    }
                }
                List<Cr> crs = on.get(k);
                if (crs != null) {
                    int elev = t != null ? t.elev : 0;
                    for (Cr cr : crs) {
                        float[] o = offset(cr, now);
                        int x = left + Math.round(o[0]) - elev, y = top + Math.round(o[1]) - elev;
                        if (creature(c, cr, x, y, now)) {
                            bars.add(new float[]{x + TILE / 2f, y});
                            barCr.add(cr);
                        }
                    }
                }
                if (t != null) {
                    for (Entry e : t.over) {
                        item(c, e, left, top, now);
                    }
                }
            }
        }
        for (Iterator<Fx> it = effects.iterator(); it.hasNext(); ) {
            Fx f = it.next();
            Sheet s = sheets.get(f.key);
            if (s == null || now - f.start >= f.ms) {
                it.remove();
                continue;
            }
            int fr = (int) Math.min(s.nf - 1, (now - f.start) / s.fd);
            cell(c, s, f.pattern, fr, f.x * TILE - ox + s.ax, f.y * TILE - oy + s.ay);
        }
        for (Iterator<Fx> it = missiles.iterator(); it.hasNext(); ) {
            Fx f = it.next();
            Sheet s = sheets.get(f.key);
            float p = (float) (now - f.start) / f.ms;
            if (s == null || p >= 1f) {
                it.remove();
                continue;
            }
            float x = (f.x + (f.x2 - f.x) * p) * TILE - ox, y = (f.y + (f.y2 - f.y) * p) * TILE - oy;
            cell(c, s, f.pattern, 0, Math.round(x) + s.ax, Math.round(y) + s.ay);
        }

        // the frame scaled up without smoothing, then text in screen pixels
        float scale = (float) getWidth() / (VIEW_W * TILE);
        src.set(0, 0, frame.getWidth(), frame.getHeight());
        dst.set(0, 0, getWidth(), Math.round(VIEW_H * TILE * scale));
        screen.drawBitmap(frame, src, dst, pixel);
        float size = Math.max(9f, 10f * scale);
        text.setTextSize(size);
        outline.setTextSize(size);
        outline.setStrokeWidth(Math.max(2f, size / 5f));
        text.setTextAlign(Paint.Align.CENTER);
        outline.setTextAlign(Paint.Align.CENTER);
        for (int i = 0; i < bars.size(); i++) {
            float[] b = bars.get(i);
            Cr cr = barCr.get(i);
            int col = health(cr.hp);
            float x = b[0] * scale, y = (b[1] - 6) * scale;
            float bw = 27 * scale, bh = Math.max(3f, 4 * scale);
            fill.setColor(Color.BLACK);
            screen.drawRect(x - bw / 2, y, x + bw / 2, y + bh, fill);
            fill.setColor(col);
            screen.drawRect(x - bw / 2 + 1, y + 1, x - bw / 2 + 1 + (bw - 2) * cr.hp / 100f, y + bh - 1, fill);
            label(screen, cr.name, x, y - 2, col);
        }
        for (Iterator<Fx> it = numbers.iterator(); it.hasNext(); ) {
            Fx f = it.next();
            float p = (float) (now - f.start) / f.ms;
            if (p >= 1f) {
                it.remove();
                continue;
            }
            float x = ((f.x * TILE - ox) + TILE / 2f) * scale, y = ((f.y * TILE - oy) - p * TILE) * scale;
            label(screen, f.text, x, y, f.colour);
        }
        for (Iterator<Fx> it = speech.iterator(); it.hasNext(); ) {
            Fx f = it.next();
            if (now - f.start >= f.ms) {
                it.remove();
                continue;
            }
            float x = ((f.x * TILE - ox) + TILE / 2f) * scale, y = ((f.y * TILE - oy) - 14) * scale;
            String line = f.text.length() > 60 ? f.text.substring(0, 60) + "..." : f.text;
            label(screen, f.name + ":", x, y - size * 1.1f, f.colour);
            label(screen, line, x, y, f.colour);
        }
    }

    private void label(Canvas screen, String s, float x, float y, int colour) {
        float half = text.measureText(s) / 2f;
        x = Math.max(half + 2, Math.min(getWidth() - half - 2, x));
        y = Math.max(text.getTextSize(), y);
        screen.drawText(s, x, y, outline);
        text.setColor(colour);
        screen.drawText(s, x, y, text);
    }

    /** the client's colour of a name and a health bar */
    static int health(int pct) {
        if (pct > 92) {
            return Color.rgb(0x00, 0xBC, 0x00);
        }
        if (pct > 60) {
            return Color.rgb(0x50, 0xA1, 0x50);
        }
        if (pct > 30) {
            return Color.rgb(0xA1, 0xA1, 0x00);
        }
        if (pct > 8) {
            return Color.rgb(0xBF, 0x0A, 0x0A);
        }
        if (pct > 3) {
            return Color.rgb(0x91, 0x0F, 0x0F);
        }
        return Color.rgb(0x85, 0x0C, 0x0C);
    }

    private void item(Canvas c, Entry e, int left, int top, long now) {
        Sheet s = sheets.get(e.key);
        if (s == null) {
            return;
        }
        int fr = s.nf > 1 ? (int) ((now / s.fd) % s.nf) : 0;
        cell(c, s, e.pattern, fr, left + s.ax - e.lift, top + s.ay - e.lift);
    }

    /** true when drawn (an invisible creature has no look: no bar, no name) */
    private boolean creature(Canvas c, Cr cr, int x, int y, long now) {
        if (cr.outfit == null) {
            return false;
        }
        Sheet s = sheets.get(cr.outfit);
        if (s == null) {
            return true;
        }
        if (cr.outfit.startsWith("i")) {
            cell(c, s, 0, s.nf > 1 ? (int) ((now / s.fd) % s.nf) : 0, x + s.ax, y + s.ay);
            return true;
        }
        int col = 0;
        boolean walking = cr.walkMs > 0 && now - cr.walkStart < cr.walkMs;
        if (walking && s.nw > 0) {
            col = s.ni + (int) (((now - cr.walkStart) / Math.max(10, s.fd)) % s.nw);
        }
        cell(c, s, cr.dir, col, x + s.ax, y + s.ay);
        return true;
    }

    /** one cell of a sheet (row, column) with its top-left at (x, y) in the frame */
    private void cell(Canvas c, Sheet s, int row, int col, int x, int y) {
        int rows = s.bmp.getHeight() / s.ch, cols = s.bmp.getWidth() / s.cw;
        if (rows <= 0 || cols <= 0) {
            return;
        }
        row = Math.floorMod(row, rows);
        col = Math.floorMod(col, cols);
        src.set(col * s.cw, row * s.ch, (col + 1) * s.cw, (row + 1) * s.ch);
        dst.set(x, y, x + s.cw, y + s.ch);
        c.drawBitmap(s.bmp, src, dst, pixel);
    }
}
