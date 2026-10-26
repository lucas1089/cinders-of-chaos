package com.cindersofchaos.admin;

/**
 * The plain arithmetic of the live cast's floors and light (no Android classes, so a JVM can run it): which cell of
 * the screen a tile of another floor lands on, the client's 8-bit colours, the light a source casts and the ambient
 * light. CastView draws with it; server/README.md "Live spectator", phase 3.
 */
final class CastMath {
    private CastMath() {
    }

    /** The client's highest floor with sky (floor 7 is ground level; the floors under it are underground). */
    static final int SEA_FLOOR = 7;
    /** Lights above this intensity are drawn as this one (the client caps them too). */
    static final int MAX_LIGHT = 8;

    /**
     * How many tiles up and to the left a floor is drawn: the camera's floor 0, each floor above one more, each
     * floor below one less (it moves down and to the right).
     */
    static int shift(int cameraFloor, int floor) {
        return cameraFloor - floor;
    }

    /** The screen cell (in tiles, on the camera floor's grid) where world coordinate w of floor f is drawn. */
    static int cell(int w, int cameraFloor, int floor) {
        return w - shift(cameraFloor, floor);
    }

    /** The world coordinate drawn at a screen cell on floor f. */
    static int world(int cell, int cameraFloor, int floor) {
        return cell + shift(cameraFloor, floor);
    }

    /** The client's 8-bit colour (6 x 6 x 6) as 0xRRGGBB; 216 and above: white. */
    static int rgb8(int c) {
        if (c >= 216 || c < 0) {
            return 0xFFFFFF;
        }
        return (c / 36 * 51) << 16 | (c / 6 % 6 * 51) << 8 | (c % 6 * 51);
    }

    /** Scales the three channels of 0xRRGGBB by f (0..1). */
    static int scale(int rgb, float f) {
        f = Math.max(0f, Math.min(1f, f));
        int r = Math.round((rgb >> 16 & 0xFF) * f), g = Math.round((rgb >> 8 & 0xFF) * f);
        int b = Math.round((rgb & 0xFF) * f);
        return r << 16 | g << 8 | b;
    }

    /** The radius of a light in pixels of the frame (32 px a tile). */
    static int radius(int intensity, int tile) {
        return Math.min(Math.max(intensity, 0), MAX_LIGHT) * tile;
    }

    /** A source lights brighter the stronger it is: from half at intensity 0 to full at the cap. */
    static float brightness(int intensity) {
        return 0.5f + Math.min(Math.max(intensity, 0), MAX_LIGHT) / (float) MAX_LIGHT * 0.5f;
    }

    /** The colour (0xRRGGBB) a source adds at its centre. */
    static int sourceColour(int intensity, int colour8) {
        return scale(rgb8(colour8), brightness(intensity));
    }

    /**
     * The light of the whole map: the world light's colour at its intensity (0..255) above ground; underground the
     * sun does not reach, so only the sources light.
     */
    static int ambient(int intensity, int colour8, int cameraFloor) {
        return ambient(intensity, colour8, cameraFloor, 0);
    }

    /**
     * Same, but never darker than minimum (0..255, like the client's minimum ambient light): the spectator sees the
     * map at night and underground. 2026-10-26: with the game's own darkness (night: world light 40 of 255; underground:
     * 0) the view looked black except the names and health bars, which are drawn after the light.
     */
    static int ambient(int intensity, int colour8, int cameraFloor, int minimum) {
        int i = cameraFloor > SEA_FLOOR ? 0 : Math.max(0, Math.min(255, intensity));
        i = Math.max(i, Math.max(0, Math.min(255, minimum)));
        int base = cameraFloor > SEA_FLOOR ? 0xFFFFFF : rgb8(colour8);
        return scale(base, i / 255f);
    }

    /** true when the light would leave the map (nearly) dark: the app tells the owner why */
    static boolean dark(int ambientRgb) {
        return Math.max(ambientRgb >> 16 & 0xFF, Math.max(ambientRgb >> 8 & 0xFF, ambientRgb & 0xFF)) < 0x60;
    }

    /** The lightest the spectator's map gets by default (about 40 %): readable at night and underground. */
    static final int READABLE = 104;

    /** The client gives the player a little light of his own in the dark and underground. */
    static int playerIntensity(int own, int worldIntensity, int cameraFloor) {
        if (worldIntensity < 64 || cameraFloor > SEA_FLOOR) {
            return Math.max(own, 2);
        }
        return own;
    }
}
