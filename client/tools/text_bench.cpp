// Offline benchmark of the per-frame text path (base patch 0133, client/BASE.md "0133").
//   g++ -std=c++17 -O2 -I DIR -I client/tools client/tools/text_bench.cpp -o text_bench   (DIR holds chaostextslot.h)
//   text_bench [--seconds N] [--check]
// Old path: DrawQueue::addText -> TextRender::addText (hash of the whole string, lock, std::map find, a make_shared with
// a copy of the string on a miss) -> queue item -> TextRender::drawText (lock, find, clock read) + the once-per-entry
// layout + TextRender::poll, transcribed from the base client. New path: CachedText's TextSlot hands out the entry
// without hash, lock or lookup; the same queue item, the same layout on first draw. Both paths use the same stand-in font and
// layout (chaostext_ref.h) and the same stand-in painter (sums the quads of the entry), and are timed on the same frames.
// Scenarios, one frame = every text drawn once:
//   names       60 creature names that stay (a busy hunt screen), the case the patch is for
//   names+hits  the same plus 15 damage numbers alive at a time, each a fresh string that is laid out once and drawn ~40 frames
//   churn       every text is a new string on every frame (nothing to reuse): both paths lay out each draw; no gain expected
// Each result is checked: the quads the painter stand-in sees are identical in both paths (a checksum over every drawn quad).
// What it leaves out: the OpenGL work of Painter::drawText (the same before and after) and the rest of drawInformation, so
// the share of a frame saved in the client is smaller than the ratios here. --check (CI): exit 1 on a checksum difference
// or when `names` or `names+hits` is not at least 1.15x faster.
#include "chaostextslot.h"
#include "chaostext_ref.h"
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <map>
#include <memory>
#include <mutex>

using namespace reftext;
using Clock = std::chrono::steady_clock;

static int64_t nowMs() { return std::chrono::duration_cast<std::chrono::milliseconds>(Clock::now().time_since_epoch()).count(); }

struct Entry { // TextRenderCache
    std::shared_ptr<Font> font;
    std::string text;
    Sz size;
    int align;
    const void* texture;
    std::vector<Quad> coords;
    int64_t lastUse;
};

static void layoutIfNeeded(Entry& e)
{
    if (e.font) {
        e.coords = refCoords(*e.font, e.text, e.size, e.align);
        e.text.clear();
        e.font.reset();
    }
}

static uint64_t paint(const Entry& e, int x, int y) // stand-in for Painter::drawText: reads every quad
{
    uint64_t h = 0;
    for (const Quad& q : e.coords) h = h * 1000003ULL + uint64_t(q.screen.x + x) * 31 + uint64_t(q.screen.y + y) * 17 + uint64_t(q.tex.x) + uint64_t(q.tex.w) * 7;
    return h + uint64_t(x) * 3 + uint64_t(y);
}

struct QueueItem { // DrawQueueItemText(Entry): the point, the texture, a shared pointer to the font texture owner, the shader
    int x, y;
    uint64_t hash;
    std::shared_ptr<Entry> entry;
    std::shared_ptr<int> texture; // TexturePtr copy
    std::shared_ptr<int> shader;  // PainterShaderProgramPtr copy
};

// ---- the stock TextRender, transcribed ----
struct StockRender {
    static const int INDEXES = 10;
    std::map<uint64_t, std::shared_ptr<Entry>> cache[INDEXES];
    std::mutex mutex[INDEXES];
    int iteration = 0;
    int64_t clockMs = 0;
    uint64_t addText(const std::shared_ptr<Font>& font, const std::string& text, Sz size, int align, const void* tex)
    {
        uint64_t hash = 1125899906842597ULL;
        for (size_t i = 0; i < text.length(); ++i) hash = hash * 31 + text[i];
        hash = hash * 31 + size.w;
        hash = hash * 31 + size.h;
        hash = hash * 31 + (uint64_t)align;
        hash = hash * 31 + (uint64_t)font->id;
        int index = hash % INDEXES;
        mutex[index].lock();
        auto it = cache[index].find(hash);
        if (it == cache[index].end())
            cache[index][hash] = std::make_shared<Entry>(Entry{ font, text, size, align, tex, {}, nowMs() });
        mutex[index].unlock();
        return hash;
    }
    uint64_t draw(const QueueItem& item)
    {
        int index = item.hash % INDEXES;
        mutex[index].lock();
        auto _it = cache[index].find(item.hash);
        if (_it == cache[index].end()) { mutex[index].unlock(); return 0; }
        auto it = _it->second;
        it->lastUse = nowMs();
        mutex[index].unlock();
        layoutIfNeeded(*it);
        return paint(*it, item.x, item.y);
    }
    void poll(int64_t now)
    {
        int index = (iteration++) % INDEXES;
        std::lock_guard<std::mutex> lock(mutex[index]);
        auto& c = cache[index];
        if (c.size() < 100) return;
        int64_t dropPoint = now;
        if (c.size() > 500) dropPoint -= 10; else if (c.size() > 250) dropPoint -= 100; else dropPoint -= 1000;
        for (auto it = c.begin(); it != c.end();) {
            if (it->second->lastUse < dropPoint) { it = c.erase(it); continue; }
            ++it;
        }
    }
};

struct Text { // the piece of text owned by a creature / a damage number
    std::string text;
    std::shared_ptr<Font> font;
    Sz box;
    int x, y;
    uint32_t revision = 0;
    chaos::TextSlot<Entry> slot;
};

struct Scenario {
    const char* name;
    int names;
    int hits;         // alive at a time
    int hitLife;      // frames a damage number lives
    bool churn;       // every text changes every frame
    bool required;
};

static std::string nameFor(int i)
{
    static const char* base[] = { "Dragon Lord", "Rat", "Cinder Wraith", "Lochtag", "Malvorn the Hollow King", "Nightfang Widow", "Hodag", "Babayaga" };
    return std::string(base[i % 8]) + (i >= 8 ? " " + std::to_string(i) : "");
}

struct Run { double ms; uint64_t sum; };

static std::vector<Text> makeTexts(const Scenario& sc, std::shared_ptr<Font> f, std::mt19937& rng)
{
    std::vector<Text> v(sc.names + sc.hits);
    for (int i = 0; i < sc.names; ++i) {
        v[i].text = nameFor(i);
        v[i].font = f;
        Sz sz; refPositions(*f, v[i].text, AlignCenter, &sz);
        v[i].box = sz; v[i].x = int(rng() % 900); v[i].y = int(rng() % 600);
    }
    for (int i = 0; i < sc.hits; ++i) {
        Text& t = v[sc.names + i];
        t.text = std::to_string(1 + rng() % 9000); t.font = f; Sz sz; refPositions(*f, t.text, AlignCenter, &sz); t.box = sz;
        t.x = int(rng() % 900); t.y = int(rng() % 600);
    }
    return v;
}

static void advance(std::vector<Text>& v, const Scenario& sc, int frame, std::mt19937& rng)
{
    for (size_t i = 0; i < v.size(); ++i) {
        Text& t = v[i];
        bool hit = int(i) >= sc.names;
        bool change = sc.churn || (hit && ((frame + int(i) * 7) % sc.hitLife == 0));
        if (change) {
            t.text = hit || sc.churn ? std::to_string(1 + rng() % 90000) + (sc.churn && i % 2 ? " Wraith" : "") : t.text;
            Sz sz; refPositions(*t.font, t.text, AlignCenter, &sz);
            t.box = sz; ++t.revision;
        }
        t.x += 1; if (t.x > 900) t.x = 0; // the creatures move: the draw point changes, the layout does not
    }
}

static Run runStock(const Scenario& sc, int frames, std::shared_ptr<Font> f)
{
    std::mt19937 rng(7);
    auto texts = makeTexts(sc, f, rng);
    StockRender tr;
    auto texture = std::make_shared<int>(0);
    auto shader = std::shared_ptr<int>();
    std::vector<QueueItem> queue;
    queue.reserve(texts.size());
    uint64_t sum = 0;
    auto t0 = Clock::now();
    for (int fr = 0; fr < frames; ++fr) {
        advance(texts, sc, fr, rng);
        queue.clear();
        for (const Text& t : texts) { // CachedText::draw -> DrawQueue::addText
            uint64_t hash = tr.addText(t.font, t.text, t.box, AlignCenter, texture.get());
            queue.push_back(QueueItem{ t.x, t.y, hash, nullptr, texture, shader });
        }
        for (const QueueItem& it : queue) sum += tr.draw(it);
        tr.poll(nowMs());
    }
    return Run{ std::chrono::duration<double, std::milli>(Clock::now() - t0).count(), sum };
}

static Run runSlot(const Scenario& sc, int frames, std::shared_ptr<Font> f)
{
    std::mt19937 rng(7);
    auto texts = makeTexts(sc, f, rng);
    auto texture = std::make_shared<int>(0);
    auto shader = std::shared_ptr<int>();
    std::vector<QueueItem> queue;
    queue.reserve(texts.size());
    uint64_t sum = 0;
    auto t0 = Clock::now();
    for (int fr = 0; fr < frames; ++fr) {
        advance(texts, sc, fr, rng);
        queue.clear();
        for (Text& t : texts) { // patched CachedText::draw -> DrawQueue::addTextEntry
            chaos::TextSlotKey key;
            key.fontId = t.font->id; key.texture = texture.get(); key.width = t.box.w; key.height = t.box.h;
            key.align = AlignCenter; key.revision = t.revision;
            const std::shared_ptr<Entry>& e = t.slot.get(key, [&]() {
                return std::make_shared<Entry>(Entry{ t.font, t.text, t.box, AlignCenter, texture.get(), {}, 0 });
            });
            queue.push_back(QueueItem{ t.x, t.y, 0, e, texture, shader });
        }
        for (const QueueItem& it : queue) { layoutIfNeeded(*it.entry); sum += paint(*it.entry, it.x, it.y); }
    }
    return Run{ std::chrono::duration<double, std::milli>(Clock::now() - t0).count(), sum };
}

int main(int argc, char** argv)
{
    double seconds = 0.6;
    bool check = false;
    for (int i = 1; i < argc; ++i) {
        if (!std::strcmp(argv[i], "--check")) check = true;
        else if (!std::strcmp(argv[i], "--seconds") && i + 1 < argc) seconds = std::atof(argv[++i]);
    }
    auto font = std::make_shared<Font>(1, 5);
    const Scenario scenarios[] = {
        { "names", 60, 0, 1, false, true },
        { "names+hits", 60, 15, 40, false, true },
        { "churn", 30, 0, 1, true, false },
    };
    int bad = 0;
    std::printf("%-12s %12s %12s %8s\n", "scenario", "stock us/fr", "slot us/fr", "ratio");
    for (const Scenario& sc : scenarios) {
        const int frames = 1500;
        double bestStock = 1e18, bestSlot = 1e18;
        uint64_t sumStock = 0, sumSlot = 0;
        double spent = 0;
        for (int round = 0; round < 12 || spent < seconds * 1000; ++round) {
            Run a = runStock(sc, frames, font);
            Run b = runSlot(sc, frames, font);
            bestStock = std::min(bestStock, a.ms);
            bestSlot = std::min(bestSlot, b.ms);
            sumStock = a.sum; sumSlot = b.sum;
            spent += a.ms + b.ms;
            if (round >= 40) break;
        }
        double ratio = bestStock / bestSlot;
        bool same = sumStock == sumSlot && sumStock != 0;
        std::printf("%-12s %12.2f %12.2f %7.2fx  %s\n", sc.name, bestStock * 1000 / frames, bestSlot * 1000 / frames, ratio,
                    same ? "same quads" : "QUADS DIFFER");
        if (!same) ++bad;
        if (check && sc.required && ratio < 1.15) { std::printf("  below 1.15x\n"); ++bad; }
    }
    if (check && bad) return 1;
    return bad ? 1 : 0;
}
