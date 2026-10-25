// Unit test of the text layout slot (base patch 0133, client/BASE.md "0133").
//   g++ -std=c++17 -I DIR client/tools/chaostextslot_test.cpp -o t   (DIR holds chaostextslot.h, extracted from the patch)
// A stand-in font with the metrics logic of BitmapFont (stock calculateGlyphsPositions and calculateDrawTextCoords, copied
// here as the reference) and a stand-in CachedText that draws through a TextSlot exactly as the patched CachedText::draw
// does (an entry laid out lazily on its first draw, like TextRender::drawEntry). Random sequences of set text / set font /
// reload font texture / change box size / change alignment / draw: after every draw the coordinates of the entry in use
// must equal the reference layout computed from scratch for the current state, glyph by glyph.
#include "chaostextslot.h"
#include <algorithm>
#include <cstdio>
#include <cstdlib>
#include <memory>
#include <random>
#include <string>
#include <vector>

#include "chaostext_ref.h"

namespace {
using namespace reftext;

// ---- the stand-ins of TextRenderCache and CachedText ----
struct Entry {
    std::shared_ptr<Font> font; // reset after the first layout, like TextRenderCache::font
    std::string text;
    Sz size;
    int align;
    std::vector<Quad> coords;
    bool laidOut = false;
};

struct Text {
    std::string text;
    std::shared_ptr<Font> font;
    int align = AlignCenter;
    uint32_t revision = 0;
    chaos::TextSlot<Entry> slot;
    int layouts = 0;

    void setText(const std::string& t) { text = t; ++revision; }
    void setFont(const std::shared_ptr<Font>& f) { font = f; ++revision; }
    // draw(): what CachedText::draw + TextRender::drawEntry do; returns the quads handed to the painter
    const std::vector<Quad>* draw(Sz box)
    {
        if (!font || text.empty() || box.w < 0 || box.h < 0) return nullptr;
        chaos::TextSlotKey key;
        key.fontId = font->id;
        key.texture = reinterpret_cast<const void*>(std::intptr_t(font->textureTag));
        key.width = box.w; key.height = box.h; key.align = align; key.revision = revision;
        auto entry = slot.get(key, [&]() { return std::make_shared<Entry>(Entry{ font, text, box, align, {}, false }); });
        if (entry->font) {
            entry->coords = refCoords(*entry->font, entry->text, entry->size, entry->align); // the engine runs BitmapFont's own layout here
            ++layouts;
            entry->text.clear();
            entry->font.reset();
        }
        return &entry->coords;
    }
};

int g_fail = 0;
#define CHECK(c) do { if (!(c)) { std::printf("FAIL %s:%d  %s\n", __FILE__, __LINE__, #c); ++g_fail; } } while (0)

std::string randomText(std::mt19937& rng)
{
    static const char* words[] = { "Lord", "Ashen", "Cinder", "of", "Chaos", "1234", "-87", "Dragon Lord", "x", "Mirewood", "\xC3\xA9" };
    int n = rng() % 5;
    std::string s;
    for (int i = 0; i < n; ++i) {
        if (i) s += (rng() % 7 == 0) ? "\n" : " ";
        s += words[rng() % 11];
    }
    if (rng() % 11 == 0) s += char(1 + rng() % 30); // control character: skipped glyph
    if (rng() % 17 == 0) s += char(127);
    return s;
}

} // namespace

int main()
{
    // 1. the slot hands out the same entry while nothing changes, a new one on each kind of change
    {
        chaos::TextSlot<int> slot;
        int built = 0;
        auto make = [&]() { ++built; return std::make_shared<int>(built); };
        chaos::TextSlotKey k;
        k.fontId = 1; k.texture = &k; k.width = 40; k.height = 12; k.align = 3; k.revision = 5;
        auto a = slot.get(k, make);
        auto b = slot.get(k, make);
        CHECK(a == b && built == 1);
        chaos::TextSlotKey v;
        v = k; v.fontId = 2;       slot.get(v, make); CHECK(built == 2);
        v = k;                     slot.get(v, make); CHECK(built == 3); // back to the old key: one entry only, rebuilt
        v = k; v.texture = nullptr; slot.get(v, make); CHECK(built == 4);
        v = k; v.width = 41;       slot.get(v, make); CHECK(built == 5);
        v = k; v.height = 13;      slot.get(v, make); CHECK(built == 6);
        v = k; v.align = 4;        slot.get(v, make); CHECK(built == 7);
        v = k; v.revision = 6;     slot.get(v, make); CHECK(built == 8);
        slot.get(v, make);         CHECK(built == 8);
        slot.reset();
        slot.get(v, make);         CHECK(built == 9);
        CHECK(slot.gets() == 11 && slot.builds() == 9);
    }

    // 2. an old entry stays valid while a queue item still holds it, after the slot moved on
    {
        Text t;
        t.font = std::make_shared<Font>(1, 11);
        t.setText("Dragon Lord");
        const std::vector<Quad>* q1 = t.draw(Sz{ 80, 20 });
        CHECK(q1 && !q1->empty());
        std::vector<Quad> held = *q1;
        t.setText("Rat");
        t.draw(Sz{ 80, 20 });
        CHECK(held == refCoords(*t.font, "Dragon Lord", Sz{ 80, 20 }, AlignCenter));
    }

    // 3. random sequences against the reference layout from scratch
    std::mt19937 rng(20261022);
    std::vector<std::shared_ptr<Font>> fonts;
    for (int i = 0; i < 4; ++i) fonts.push_back(std::make_shared<Font>(i + 1, 100 + i));
    const int aligns[] = { AlignTopLeft, AlignCenter, AlignRight | AlignTop, AlignBottom | AlignHCenter, AlignLeft | AlignVCenter };
    long draws = 0, compared = 0, quads = 0;
    for (int run = 0; run < 400; ++run) {
        Text t;
        t.font = fonts[rng() % fonts.size()];
        t.align = aligns[rng() % 5];
        t.setText(randomText(rng));
        Sz box{ int(rng() % 120) - 5, int(rng() % 60) - 5 };
        for (int step = 0; step < 120; ++step) {
            switch (rng() % 9) {
                case 0: t.setText(randomText(rng)); break;
                case 1: t.setFont(fonts[rng() % fonts.size()]); break;
                case 2: fonts[rng() % fonts.size()]->textureTag++; break; // font texture reloaded: new identity
                case 3: box.w = int(rng() % 120) - 5; break;
                case 4: box.h = int(rng() % 60) - 5; break;
                case 5: t.align = aligns[rng() % 5]; break; // the engine keeps CachedText's align fixed; the key still guards it
                default: break;                              // just draw again
            }
            const std::vector<Quad>* got = t.draw(box);
            ++draws;
            if (!t.font || t.text.empty() || box.w < 0 || box.h < 0) { CHECK(got == nullptr); continue; }
            CHECK(got != nullptr);
            if (!got) continue;
            std::vector<Quad> want = refCoords(*t.font, t.text, box, t.align);
            ++compared;
            quads += long(want.size());
            if (!(*got == want)) { CHECK(false); std::printf("  run %d step %d text '%s'\n", run, step, t.text.c_str()); }
        }
        // a draw without any change must not lay out again
        int before = t.layouts;
        for (int k = 0; k < 5; ++k) t.draw(Sz{ 50, 20 });
        CHECK(t.layouts - before <= 1);
    }
    CHECK(compared > 10000 && quads > 50000);
    std::printf("chaostextslot_test: %ld draws, %ld compared with the reference layout, %ld glyph quads, %d failures\n",
                draws, compared, quads, g_fail);
    return g_fail ? 1 : 0;
}
