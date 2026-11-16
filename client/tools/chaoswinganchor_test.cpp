// Unit test of the body measure for wings (base patch 0204, client/BASE.md "0204").
//   g++ -std=c++17 -I DIR client/tools/chaoswinganchor_test.cpp -o t   (DIR holds chaoswinganchor.h, extracted from the patch)
//   ./t client/tools/sprites/drawn_wings/anchor_fixtures.txt
// Checks: on masks made here the torso is the body's, whatever is added to it (a thin staff, a faint ground shadow
// with a darker heart, a rider high in a big canvas), a wide cape moves it by less than half its width, an empty
// picture has no torso; the tables, the cache and the placing; and every mask of the fixtures file gives the numbers
// the Python twin wrote there (gen_drawn_wings_families.torso_anchor), so the two rules stay one.
#include "chaoswinganchor.h"
#include <cstdio>
#include <fstream>
#include <sstream>
#include <string>

using namespace chaos::winganchor;

static int failures = 0;
#define CHECK(cond, ...) do { if (!(cond)) { ++failures; std::printf("FAIL line %d: %s  ", __LINE__, #cond); std::printf(__VA_ARGS__); std::printf("\n"); } } while (0)

struct Mask {
    int w, h;
    std::vector<uint8_t> a;
    Mask(int w_, int h_) : w(w_), h(h_), a(static_cast<size_t>(w_) * h_, 0) {}
    void box(int x0, int y0, int x1, int y1, int v = 255)
    {
        for (int y = y0; y < y1; ++y)
            for (int x = x0; x < x1; ++x)
                a[y * w + x] = static_cast<uint8_t>(v);
    }
    // a head, a trunk and two legs round column cx
    void figure(int cx, int top, int bot, int half = 7)
    {
        const int hh = bot - top;
        box(cx - 4, top, cx + 4, top + hh / 4);
        box(cx - half, top + hh / 4, cx + half, top + 3 * hh / 4);
        box(cx - half, top + 3 * hh / 4, cx - 1, bot);
        box(cx + 1, top + 3 * hh / 4, cx + half, bot);
    }
};

static bool measure(const Mask& m, int& x2, int& y2) { return torso2(m.a.data(), m.w, m.h, x2, y2); }

int main(int argc, char** argv)
{
    int x2 = 0, y2 = 0, px = 0, py = 0;

    Mask plain(64, 64);
    plain.figure(34, 18, 58);
    CHECK(measure(plain, px, py), "a plain figure has a torso");
    CHECK(px == 67, "x is the middle of the trunk (columns 27..40): %d", px);
    CHECK(py / 2 >= 30 && py / 2 <= 45, "y is in the trunk: %d", py);

    Mask staff(plain);
    staff.box(50, 4, 52, 60);
    staff.box(41, 30, 50, 32);
    CHECK(measure(staff, x2, y2) && x2 == px && y2 == py, "a thin staff changes nothing: %d %d", x2, y2);

    Mask shadow(plain);
    shadow.box(38, 56, 62, 63, 40);
    shadow.box(46, 58, 58, 62, 120);
    CHECK(measure(shadow, x2, y2) && x2 == px && y2 == py, "a faint ground shadow and its heart change nothing: %d %d", x2, y2);

    Mask cape(64, 64);
    cape.figure(30, 18, 58);
    cape.box(37, 26, 58, 54);
    CHECK(measure(cape, x2, y2), "a caped figure has a torso");
    CHECK(x2 > 59 && x2 - 59 <= 21, "a cape 21 wide moves the torso by less than half of it: %d", x2);

    Mask rider(96, 96);
    rider.figure(52, 20, 52, 6);
    Point2 p{ 0, 0 };
    CHECK(torso(rider.a.data(), 96, 96, p), "a rider in a big canvas");
    CHECK(p.x == 52 - 64 && p.y < -20, "its torso from the creature's place: %d %d", p.x, p.y);

    Mask empty(64, 64);
    CHECK(!measure(empty, x2, y2), "an empty picture has no torso");
    CHECK(!torso2(nullptr, 64, 64, x2, y2) && !torso2(plain.a.data(), 0, 64, x2, y2) &&
          !torso2(plain.a.data(), kMaxSide + 1, 1, x2, y2), "bad input is refused");

    Mask faint(32, 32);
    faint.box(12, 10, 20, 24, 30);
    CHECK(measure(faint, x2, y2) && x2 == 31, "only faint pixels: they are the figure: %d", x2);

    // tables, cache, placing
    clearAnchors();
    Point2 anchor{ 0, 0 }, body{ 0, 0 }, move{ 0, 0 };
    CHECK(!wingsAnchor(2414, anchor), "no anchor: the draw as before");
    CHECK(setWingsAnchor(2414, -16, 0) && wingsAnchor(2414, anchor) && anchor.x == -16 && anchor.y == 0, "an anchor row");
    CHECK(!setWingsAnchor(0, 0, 0) && !setWingsAnchor(5, 9999, 0), "bad anchor rows are refused");
    CHECK(!bodyOverride(2073, 2, body), "no hand row");
    CHECK(setBodyAnchor(2073, 2, -30, -4) && bodyOverride(2073, 2, body) && body.x == -30 && body.y == -4, "a hand row");
    CHECK(!bodyOverride(2073, 1, body) && !bodyOverride(2073, 7, body) && !setBodyAnchor(2073, 4, 0, 0), "a hand row is per direction");

    const uint64_t k = key(2073, 2, 0);
    CHECK(key(2073, 2, 1) != k && key(2073, 1, 0) != k && key(2074, 2, 0) != k, "one measure a look, column and z pattern");
    CHECK(cached(k, body) == -1, "not measured yet");
    CHECK(remember(k, plain.a.data(), 64, 64, body) && cached(k, body) == 1, "measured once, then kept");
    CHECK(body.x == 34 - 32 && body.y == (py + 1) / 2 - 32, "the kept torso: %d %d", body.x, body.y);
    const uint64_t k2 = key(9, 0, 0);
    CHECK(!remember(k2, empty.a.data(), 64, 64, body) && cached(k2, body) == 0, "an empty picture is kept as empty");

    // the anchor lands on the torso: the wings are drawn at dest + move, their anchor at wingDest + anchor
    body = Point2{ -30, -4 };
    CHECK(place(body, anchor, move) && move.x + anchor.x == body.x && move.y + anchor.y == body.y, "the anchor lands on the torso");
    body = Point2{ 400, 0 };
    CHECK(!place(body, anchor, move), "a move out of range is refused");
    clearAnchors();
    CHECK(!wingsAnchor(2414, anchor) && cached(k, body) == -1, "clear empties the tables and the measures");

    // the shared fixtures: the same numbers as the Python twin
    if (argc > 1) {
        std::ifstream in(argv[1]);
        CHECK(in.good(), "fixtures file %s", argv[1]);
        std::string line;
        int count = 0;
        while (std::getline(in, line)) {
            if (line.empty() || line[0] == '#')
                continue;
            std::istringstream head(line);
            std::string name, sx, sy;
            int w = 0, h = 0;
            head >> name >> w >> h >> sx >> sy;
            CHECK(w > 0 && h > 0 && w <= kMaxSide && h <= kMaxSide, "fixture %s size", name.c_str());
            if (w <= 0 || h <= 0 || w > kMaxSide || h > kMaxSide)
                break;
            Mask m(w, h);
            for (int y = 0; y < h; ++y) {
                std::getline(in, line);
                CHECK(static_cast<int>(line.size()) == w, "fixture %s row %d", name.c_str(), y);
                for (int x = 0; x < w && x < static_cast<int>(line.size()); ++x)
                    m.a[y * w + x] = line[x] == '#' ? 255 : line[x] == '+' ? 100 : line[x] == '-' ? 30 : 0;
            }
            int fx = 0, fy = 0;
            const bool ok = measure(m, fx, fy);
            if (sx == "-") {
                CHECK(!ok, "fixture %s: nothing to measure", name.c_str());
            } else {
                CHECK(ok && fx == std::stoi(sx) && fy == std::stoi(sy), "fixture %s: %d %d, the file says %s %s", name.c_str(), fx, fy,
                      sx.c_str(), sy.c_str());
            }
            ++count;
        }
        CHECK(count >= 8, "fixtures read: %d", count);
        std::printf("%d shared fixtures agree with the Python twin\n", count);
    }

    if (failures) {
        std::printf("%d failure(s)\n", failures);
        return 1;
    }
    std::printf("chaoswinganchor_test OK\n");
    return 0;
}
