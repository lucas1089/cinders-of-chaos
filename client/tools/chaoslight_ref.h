// Stand-ins for the light map test and bench (base patch 0140, client/BASE.md "0140"): the Color of the base client
// (only what LightView::draw uses, same arithmetic) and a transcription of the stock per-tile loop of LightView::draw.
#ifndef CHAOSLIGHT_REF_H
#define CHAOSLIGHT_REF_H

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <vector>

namespace reflight {

struct Point { int x = 0, y = 0; };
struct Light { Point pos; uint8_t color = 215; uint8_t intensity = 0; };
struct TileLight { size_t start; uint8_t color; };

class Color {
public:
    Color() : m_r(1.0f), m_g(1.0f), m_b(1.0f) {}
    Color(int r, int g, int b) : m_r(r / 255.0f), m_g(g / 255.0f), m_b(b / 255.0f) {}
    Color(float r, float g, float b) : m_r(r), m_g(g), m_b(b) {}
    uint8_t r() const { return 255.0f * m_r; }
    uint8_t g() const { return 255.0f * m_g; }
    uint8_t b() const { return 255.0f * m_b; }
    Color operator*(float v) const { return Color(m_r * v, m_g * v, m_b * v); }
    static Color from8bit(int color)
    {
        if (color >= 216 || color <= 0)
            return Color(0, 0, 0);
        int r = int(color / 36) % 6 * 51;
        int g = int(color / 6) % 6 * 51;
        int b = color % 6 * 51;
        return Color(r, g, b);
    }
private:
    float m_r, m_g, m_b;
};

// LightView::draw of the base client, buffer part only (the texture upload and the quad are the same after the patch)
inline void stockFill(std::vector<uint8_t>& buffer, int w, int h, int spriteSize, const Color& globalLight,
                      const std::vector<Light>& lights, const std::vector<TileLight>& tiles)
{
    if (buffer.size() < 4u * size_t(w) * size_t(h))
        buffer.resize(size_t(w) * size_t(h) * 4);
    for (int x = 0; x < w; ++x) {
        for (int y = 0; y < h; ++y) {
            Point pos{ x * spriteSize + spriteSize / 2, y * spriteSize + spriteSize / 2 };
            int index = (y * w + x);
            int colorIndex = index * 4;
            buffer[colorIndex] = globalLight.r();
            buffer[colorIndex + 1] = globalLight.g();
            buffer[colorIndex + 2] = globalLight.b();
            buffer[colorIndex + 3] = 255;
            for (size_t i = tiles[index].start; i < lights.size(); ++i) {
                const Light& light = lights[i];
                float distance = std::sqrt((pos.x - light.pos.x) * (pos.x - light.pos.x) +
                                           (pos.y - light.pos.y) * (pos.y - light.pos.y));
                distance /= spriteSize;
                float intensity = (-distance + light.intensity) * 0.2f;
                if (intensity < 0.01f) continue;
                if (intensity > 1.0f) intensity = 1.0f;
                Color lightColor = Color::from8bit(light.color) * intensity;
                buffer[colorIndex] = std::max<int>(buffer[colorIndex], lightColor.r());
                buffer[colorIndex + 1] = std::max<int>(buffer[colorIndex + 1], lightColor.g());
                buffer[colorIndex + 2] = std::max<int>(buffer[colorIndex + 2], lightColor.b());
            }
        }
    }
}

} // namespace reflight

#endif
