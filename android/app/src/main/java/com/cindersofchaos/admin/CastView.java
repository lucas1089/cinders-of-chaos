package com.cindersofchaos.admin;

import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.PorterDuff;
import android.graphics.PorterDuffXfermode;
import android.graphics.RadialGradient;
import android.graphics.Rect;
import android.graphics.RectF;
import android.graphics.Shader;
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
 * follows the player's steps. Phase 3: the other floors the client shows (each shifted a tile up and left per floor
 * above, the ones under a ground that covers them not drawn at all), and the light: the world light darkens the
 * frame, every light source (creatures, items, effects) adds a round glow, as the client's light view does. Not drawn:
 * the client's own interface. A relay of phase 2 (hello without "v") sends neither floors nor light: the view then is
 * the camera floor, lit as it is.
 * Lines come in on the streaming thread (apply), drawing on the screen thread; both under this object's lock.
 */
final class CastView extends View {
    static final int VIEW_W = 15;
    static final int VIEW_H = 11;
    static final int TILE = 32;
    private static final long FRAME_MS = 33;
    private static final int MAX_EVENTS = 200;
    private static final int LIGHT_DIV = 4;       // the light bitmap is a quarter of the frame, smoothed up
    private static final int BUBBLE = 64;         // a glow's bitmap

    private static final class Sheet {
        Bitmap bmp;
        int cw, ch, ax, ay, np, nf, fd, ni, nw, el, lightI, lightC;
        boolean ground;
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
        int hp, dir = 2, x, y, z, type, lightI, lightC;
        boolean placed;
        int fromX, fromY;
        long walkStart, walkMs;
    }

    private static final class Fx {
        int x, y, x2, y2, z, pattern, colour;
        String key, text, name;
        long start, ms;
    }

    private final Map<String, Sheet> sheets = new HashMap<>();
    private final Map<Long, Tile> tiles = new HashMap<>();   // every floor, key(x, y, z)
    private final Map<Long, Cr> creatures = new HashMap<>();
    private final List<Fx> effects = new ArrayList<>();
    private final List<Fx> missiles = new ArrayList<>();
    private final List<Fx> numbers = new ArrayList<>();
    private final List<Fx> speech = new ArrayList<>();
    private int cx, cy, cz;
    private int firstFloor, lastFloor;
    private boolean floorsKnown;
    private int worldI = 255, worldC = 215;
    private boolean lightKnown;
    private int protocol = 2;
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
    private final RectF dstF = new RectF();
    private boolean[] covered = new boolean[0];
    private final boolean[][] skip = new boolean[16][];
    private final List<int[]> lights = new ArrayList<>();
    private final Map<Integer, Bitmap> bubbles = new HashMap<>();
    private Bitmap lightBmp;
    private Canvas lightCanvas;
    private final Paint addPaint = new Paint();
    private final Paint mulPaint = new Paint();

    CastView(Context c) {
        super(c);
        pixel.setFilterBitmap(false);
        pixel.setAntiAlias(false);
        pixel.setDither(false);
        addPaint.setFilterBitmap(true);
        addPaint.setXfermode(new PorterDuffXfermode(PorterDuff.Mode.ADD));
        mulPaint.setFilterBitmap(true);
        mulPaint.setXfermode(new PorterDuffXfermode(PorterDuff.Mode.MULTIPLY));
        text.setTypeface(Typeface.create(Typeface.DEFAULT, Typeface.BOLD));
        outline.setTypeface(text.getTypeface());
        outline.setStyle(Paint.Style.STROKE);
        outline.setColor(Color.BLACK);
        setContentDescription("Visão ao vivo do personagem");
    }

    private static long key(int x, int y, int z) {
        return ((long) z << 48) | ((long) (x & 0xffff) << 32) | (y & 0xffffL);
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
        floorsKnown = false;
        lightKnown = false;
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
        for (Bitmap b : bubbles.values()) {
            b.recycle();
        }
        bubbles.clear();
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
                protocol = j.optInt("v", 2);
            }
        } else if ("full".equals(t)) {
            synchronized (this) {
                tiles.clear();
                creatures.clear();
                camera(j.optJSONArray("c"));
                player = j.optLong("id", player);
                floorRange(j.optJSONArray("fl"));
                tiles(j.optJSONArray("tiles"));
                floorTiles(j.optJSONArray("ft"));
                creatures(j.optJSONObject("cr"), now());
                worldLight(j.optJSONArray("light"));
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
                floorRange(j.optJSONArray("fl"));
                clearFloors(j.optJSONArray("fc"));
                tiles(j.optJSONArray("tiles"));
                floorTiles(j.optJSONArray("ft"));
                creatures(j.optJSONObject("cr"), now);
                worldLight(j.optJSONArray("light"));
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
        s.ground = j.optInt("gr") != 0;
        JSONArray lt = j.optJSONArray("lt");
        if (lt != null && lt.length() == 2) {
            s.lightI = lt.optInt(0);
            s.lightC = lt.optInt(1);
        }
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

    private void floorRange(JSONArray a) {
        if (a != null && a.length() == 2) {
            firstFloor = Math.max(0, Math.min(15, a.optInt(0)));
            lastFloor = Math.max(0, Math.min(15, a.optInt(1)));
            floorsKnown = true;
        }
    }

    /** The relay's "fc": floors that come into view whole, their old tiles go before the new ones arrive. */
    private void clearFloors(JSONArray a) {
        if (a == null || a.length() == 0) {
            return;
        }
        boolean[] gone = new boolean[16];
        for (int i = 0; i < a.length(); i++) {
            int z = a.optInt(i, -1);
            if (z >= 0 && z < 16) {
                gone[z] = true;
            }
        }
        Iterator<Long> it = tiles.keySet().iterator();
        while (it.hasNext()) {
            if (gone[(int) (it.next() >> 48) & 15]) {
                it.remove();
            }
        }
    }

    private void worldLight(JSONArray a) {
        if (a != null && a.length() == 2) {
            worldI = a.optInt(0);
            worldC = a.optInt(1);
            lightKnown = true;
        }
    }

    /** The camera floor: [x, y, under, over, elevation]. */
    private void tiles(JSONArray a) {
        if (a == null) {
            return;
        }
        for (int i = 0; i < a.length(); i++) {
            JSONArray t = a.optJSONArray(i);
            if (t == null || t.length() < 5) {
                continue;
            }
            putTile(t.optInt(0), t.optInt(1), cz, t.optJSONArray(2), t.optJSONArray(3), t.optInt(4));
        }
        prune();
    }

    /** The other floors (phase 3): [z, x, y, under, over, elevation]. */
    private void floorTiles(JSONArray a) {
        if (a == null) {
            return;
        }
        for (int i = 0; i < a.length(); i++) {
            JSONArray t = a.optJSONArray(i);
            if (t == null || t.length() < 6) {
                continue;
            }
            int z = t.optInt(0, -1);
            if (z < 0 || z > 15) {
                continue;
            }
            putTile(t.optInt(1), t.optInt(2), z, t.optJSONArray(3), t.optJSONArray(4), t.optInt(5));
        }
        prune();
    }

    private void putTile(int x, int y, int z, JSONArray under, JSONArray over, int elev) {
        Tile tile = new Tile();
        tile.under = entries(under);
        tile.over = entries(over);
        tile.elev = elev;
        long k = key(x, y, z);
        if (tile.under.length == 0 && tile.over.length == 0) {
            tiles.remove(k);
        } else {
            tiles.put(k, tile);
        }
    }

    /** Tiles far from the camera are not drawn again. */
    private void prune() {
        if (tiles.size() <= 6000) {
            return;
        }
        Iterator<Map.Entry<Long, Tile>> it = tiles.entrySet().iterator();
        while (it.hasNext()) {
            long k = it.next().getKey();
            int x = (int) (k >> 32 & 0xffff), y = (int) (k & 0xffff);
            if (Math.abs(x - cx) > 30 || Math.abs(y - cy) > 30) {
                it.remove();
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
            JSONArray lt = c.optJSONArray("lt");
            cr.lightI = lt != null && lt.length() == 2 ? lt.optInt(0) : 0;
            cr.lightC = lt != null && lt.length() == 2 ? lt.optInt(1) : 0;
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
        effectsIn(j.optJSONArray("fx"), now);
        effectsIn(j.optJSONArray("fxf"), now);
        missilesIn(j.optJSONArray("mi"), now);
        missilesIn(j.optJSONArray("mif"), now);
        JSONArray a;
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

    /** [x, y, key, pattern] on the camera floor, or with the floor as a fifth number. */
    private void effectsIn(JSONArray a, long now) {
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
            f.z = e.length() > 4 ? e.optInt(4) : cz;
            f.start = now;
            Sheet s = sheets.get(f.key);
            f.ms = s != null ? (long) s.nf * s.fd : 600;
            effects.add(f);
        }
    }

    /** [from x, from y, to x, to y, key, pattern, ms] on the camera floor, or with the floor as an eighth number. */
    private void missilesIn(JSONArray a, long now) {
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
            f.z = e.length() > 7 ? e.optInt(7) : cz;
            f.start = now;
            missiles.add(f);
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
        int first = cz, last = cz;
        if (floorsKnown) {
            first = Math.max(0, Math.min(firstFloor, cz));
            last = Math.min(15, Math.max(lastFloor, cz));
        }
        // the cells of the grid: columns gx0.., rows gy0.. (the 15 x 11 view and a tile around it)
        int gx0 = cx - VIEW_W / 2 - 1, gy0 = cy - VIEW_H / 2 - 1;
        int cols = VIEW_W + 3, rows = VIEW_H + 3;
        lights.clear();
        Map<Long, List<Cr>> on = new HashMap<>();
        for (Cr cr : creatures.values()) {
            if (cr.placed && cr.z >= first && cr.z <= last) {
                on.computeIfAbsent(key(cr.x, cr.y, cr.z), k -> new ArrayList<>()).add(cr);
            }
        }
        coverage(first, last, gx0, gy0, cols, rows);
        List<float[]> bars = new ArrayList<>();
        List<Cr> barCr = new ArrayList<>();
        int tile = TILE;
        // floors from the lowest up to the highest drawn: the upper ones are drawn over the lower ones
        for (int f = last; f >= first; f--) {
            int s = CastMath.shift(cz, f);
            boolean[] hidden = skip[f];
            for (int r = 0; r < rows; r++) {
                for (int col = 0; col < cols; col++) {
                    if (hidden != null && hidden[r * cols + col]) {
                        continue;
                    }
                    int tx = gx0 + col, ty = gy0 + r;
                    long k = key(tx + s, ty + s, f);
                    Tile t = tiles.get(k);
                    int left = tx * tile - ox, top = ty * tile - oy;
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
                            if (creature(c, cr, x, y, now) && f == cz) {
                                bars.add(new float[]{x + tile / 2f, y});
                                barCr.add(cr);
                            }
                            int li = cr == me ? CastMath.playerIntensity(cr.lightI, worldI, cz) : cr.lightI;
                            if (li > 0) {
                                lights.add(new int[]{x + tile / 2, y + tile / 2, li, cr.lightC});
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
                Fx fx = it.next();
                Sheet sh = sheets.get(fx.key);
                if (sh == null || now - fx.start >= fx.ms) {
                    if (f == last) {
                        it.remove();
                    }
                    continue;
                }
                if (fx.z != f) {
                    continue;
                }
                int fr = (int) Math.min(sh.nf - 1, (now - fx.start) / sh.fd);
                int px = CastMath.cell(fx.x, cz, f) * tile - ox, py = CastMath.cell(fx.y, cz, f) * tile - oy;
                cell(c, sh, fx.pattern, fr, px + sh.ax, py + sh.ay);
                if (sh.lightI > 0) {
                    lights.add(new int[]{px + tile / 2, py + tile / 2, sh.lightI, sh.lightC});
                }
            }
            for (Iterator<Fx> it = missiles.iterator(); it.hasNext(); ) {
                Fx fx = it.next();
                Sheet sh = sheets.get(fx.key);
                float p = (float) (now - fx.start) / fx.ms;
                if (sh == null || p >= 1f) {
                    if (f == last) {
                        it.remove();
                    }
                    continue;
                }
                if (fx.z != f) {
                    continue;
                }
                float x = (CastMath.cell(fx.x, cz, f) + (fx.x2 - fx.x) * p) * tile - ox;
                float y = (CastMath.cell(fx.y, cz, f) + (fx.y2 - fx.y) * p) * tile - oy;
                cell(c, sh, fx.pattern, 0, Math.round(x) + sh.ax, Math.round(y) + sh.ay);
                if (sh.lightI > 0) {
                    lights.add(new int[]{Math.round(x) + tile / 2, Math.round(y) + tile / 2, sh.lightI, sh.lightC});
                }
            }
        }
        if (lightKnown) {
            applyLight(c);
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

    /**
     * Marks, for every drawn floor, the cells a ground on a floor above already covers (the client skips them too):
     * skip[f][row * cols + col] is true when floor f need not be drawn there.
     */
    private void coverage(int first, int last, int gx0, int gy0, int cols, int rows) {
        int n = cols * rows;
        if (covered.length != n) {
            covered = new boolean[n];
        }
        java.util.Arrays.fill(covered, false);
        for (int f = first; f <= last; f++) {
            if (skip[f] == null || skip[f].length != n) {
                skip[f] = new boolean[n];
            }
            System.arraycopy(covered, 0, skip[f], 0, n);
            if (f == last) {
                break;
            }
            int s = CastMath.shift(cz, f);
            for (int r = 0; r < rows; r++) {
                for (int col = 0; col < cols; col++) {
                    int i = r * cols + col;
                    if (covered[i]) {
                        continue;
                    }
                    Tile t = tiles.get(key(gx0 + col + s, gy0 + r + s, f));
                    if (t != null && t.under.length > 0) {
                        Sheet sh = sheets.get(t.under[0].key);
                        if (sh != null && sh.ground) {
                            covered[i] = true;
                        }
                    }
                }
            }
        }
    }

    /**
     * The client's light view: a small bitmap filled with the ambient light, every source added as a round glow,
     * then multiplied over the frame (smoothed up, so the glow has no steps). Full daylight draws nothing.
     */
    private void applyLight(Canvas c) {
        int amb = CastMath.ambient(worldI, worldC, cz);
        if ((amb >> 16 & 0xFF) >= 0xF0 && (amb >> 8 & 0xFF) >= 0xF0 && (amb & 0xFF) >= 0xF0) {
            return;
        }
        int lw = frame.getWidth() / LIGHT_DIV, lh = frame.getHeight() / LIGHT_DIV;
        if (lightBmp == null) {
            lightBmp = Bitmap.createBitmap(lw, lh, Bitmap.Config.ARGB_8888);
            lightCanvas = new Canvas(lightBmp);
        }
        lightCanvas.drawColor(0xFF000000 | amb);
        for (int[] l : lights) {
            int radius = CastMath.radius(l[2], TILE);
            int rgb = CastMath.sourceColour(l[2], l[3]);
            if (radius <= 0 || rgb == 0) {
                continue;
            }
            float x = l[0] / (float) LIGHT_DIV, y = l[1] / (float) LIGHT_DIV, r = radius / (float) LIGHT_DIV;
            dstF.set(x - r, y - r, x + r, y + r);
            lightCanvas.drawBitmap(bubble(rgb), null, dstF, addPaint);
        }
        dst.set(0, 0, frame.getWidth(), frame.getHeight());
        c.drawBitmap(lightBmp, null, dst, mulPaint);
    }

    /** A round glow of one colour: full at the middle, half at 45 % of the radius, nothing at the edge. */
    private Bitmap bubble(int rgb) {
        Bitmap b = bubbles.get(rgb);
        if (b != null) {
            return b;
        }
        if (bubbles.size() > 96) {
            for (Bitmap old : bubbles.values()) {
                old.recycle();
            }
            bubbles.clear();
        }
        b = Bitmap.createBitmap(BUBBLE, BUBBLE, Bitmap.Config.ARGB_8888);
        Paint p = new Paint(Paint.ANTI_ALIAS_FLAG);
        float half = BUBBLE / 2f;
        p.setShader(new RadialGradient(half, half, half, new int[]{0xFF000000 | rgb, 0x80000000 | rgb, rgb},
                new float[]{0f, 0.45f, 1f}, Shader.TileMode.CLAMP));
        new Canvas(b).drawCircle(half, half, half, p);
        bubbles.put(rgb, b);
        return b;
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
