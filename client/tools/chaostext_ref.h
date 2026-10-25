// Stand-in font and the stock text layout, shared by chaostextslot_test.cpp and text_bench.cpp (base patch 0133).
// refPositions / refCoords are BitmapFont::calculateGlyphsPositions and calculateDrawTextCoords of the base client
// (src/framework/graphics/bitmapfont.cpp), transcribed on a Rc / Pt / Sz stand-in of Rect / Point / Size.
#ifndef CHAOSTEXT_REF_H
#define CHAOSTEXT_REF_H
#include <algorithm>
#include <cstdint>
#include <random>
#include <string>
#include <vector>

namespace reftext {

struct Pt { int x = 0, y = 0; bool operator==(const Pt& o) const { return x == o.x && y == o.y; } };
struct Sz { int w = 0, h = 0; };
struct Rc {
    int x = 0, y = 0, w = 0, h = 0;
    int left() const { return x; }
    int top() const { return y; }
    int right() const { return x + w - 1; }
    int bottom() const { return y + h - 1; }
    bool operator==(const Rc& o) const { return x == o.x && y == o.y && w == o.w && h == o.h; }
    bool intersects(const Rc& o) const { return !(o.left() > right() || o.right() < left() || o.top() > bottom() || o.bottom() < top()); }
};
struct Quad { Rc screen, tex; bool operator==(const Quad& o) const { return screen == o.screen && tex == o.tex; } };

enum Align { AlignLeft = 1, AlignRight = 2, AlignHCenter = 4, AlignTop = 8, AlignBottom = 16, AlignVCenter = 32,
             AlignTopLeft = AlignTop | AlignLeft, AlignCenter = AlignVCenter | AlignHCenter };

struct Font {
    int id;
    int glyphHeight, yOffset, spacingW, spacingH;
    int widths[256];
    Rc texCoords[256];
    int textureTag; // stands for the identity of the font texture
    Font(int id_, uint32_t seed) : id(id_)
    {
        std::mt19937 rng(seed);
        glyphHeight = 8 + rng() % 8;
        yOffset = rng() % 3;
        spacingW = rng() % 2;
        spacingH = rng() % 3;
        textureTag = 1;
        for (int g = 0; g < 256; ++g) {
            widths[g] = 3 + rng() % 8;
            texCoords[g] = Rc{ int(g % 16) * 12, int(g / 16) * 16, widths[g], glyphHeight };
        }
        widths[32] = 4;
        widths[127] = 1;
        widths['\n'] = 1;
    }
};

// ---- reference: the stock BitmapFont::calculateGlyphsPositions / calculateDrawTextCoords, on the stand-in font ----
inline std::vector<Pt> refPositions(const Font& f, const std::string& text, int align, Sz* box)
{
    std::vector<Pt> pos(std::max<size_t>(text.size(), 1));
    std::vector<int> lineWidths(1);
    int textLength = int(text.length()), maxLineWidth = 0, lines = 0, glyph, i;
    if (textLength == 0) { if (box) { box->w = 0; box->h = f.glyphHeight; } return pos; }
    lineWidths[0] = 0;
    for (i = 0; i < textLength; ++i) {
        glyph = (unsigned char)text[i];
        if (glyph == '\n') {
            lines++;
            if (lines + 1 > int(lineWidths.size())) lineWidths.resize(lines + 1);
            lineWidths[lines] = 0;
        } else if (glyph >= 32) {
            lineWidths[lines] += f.widths[glyph];
            if (i + 1 != textLength && text[i + 1] != '\n') lineWidths[lines] += f.spacingW;
            maxLineWidth = std::max(maxLineWidth, lineWidths[lines]);
        }
    }
    Pt v{ 0, f.yOffset };
    lines = 0;
    for (i = 0; i < textLength; ++i) {
        glyph = (unsigned char)text[i];
        if (glyph == '\n' || i == 0) {
            if (glyph == '\n') { v.y += f.glyphHeight + f.spacingH; lines++; }
            if (align & AlignRight) v.x = maxLineWidth - lineWidths[lines];
            else if (align & AlignHCenter) v.x = (maxLineWidth - lineWidths[lines]) / 2;
            else v.x = 0;
        }
        pos[i] = v;
        if (glyph >= 32 && glyph != '\n') v.x += f.widths[glyph] + f.spacingW;
    }
    if (box) { box->w = maxLineWidth; box->h = v.y + f.glyphHeight; }
    return pos;
}

inline std::vector<Quad> refCoords(const Font& f, const std::string& text, Sz size, int align)
{
    std::vector<Quad> out;
    if (size.w < 0 || size.h < 0) return out;
    Rc screenCoords{ 0, 0, size.w, size.h };
    if (screenCoords.w <= 0 || screenCoords.h <= 0) return out; // Rect::isValid of the engine
    Sz box;
    std::vector<Pt> gp = refPositions(f, text, align, &box);
    for (size_t i = 0; i < text.size(); ++i) {
        int glyph = (unsigned char)text[i];
        if (glyph < 32) continue;
        Rc gs{ gp[i].x, gp[i].y, f.widths[glyph], f.glyphHeight };
        Rc gt = f.texCoords[glyph];
        if (align & AlignBottom) gs.y += screenCoords.h - box.h;
        else if (align & AlignVCenter) gs.y += (screenCoords.h - box.h) / 2;
        if (align & AlignRight) gs.x += screenCoords.w - box.w;
        else if (align & AlignHCenter) gs.x += (screenCoords.w - box.w) / 2;
        if (gs.bottom() < 0 || gs.right() < 0) continue;
        if (gs.top() < 0) { gt.h += gs.top(); gt.y -= gs.top(); gs.h += gs.top(); gs.y = 0; }
        if (gs.left() < 0) { gt.w += gs.left(); gt.x -= gs.left(); gs.w += gs.left(); gs.x = 0; }
        gs.x += screenCoords.x; gs.y += screenCoords.y;
        if (!screenCoords.intersects(gs)) continue;
        if (gs.bottom() > screenCoords.bottom()) { gt.h += screenCoords.bottom() - gs.bottom(); gs.h = screenCoords.bottom() - gs.y + 1; }
        if (gs.right() > screenCoords.right()) { gt.w += screenCoords.right() - gs.right(); gs.w = screenCoords.right() - gs.x + 1; }
        out.push_back(Quad{ gs, gt });
    }
    return out;
}

} // namespace reftext

#endif
