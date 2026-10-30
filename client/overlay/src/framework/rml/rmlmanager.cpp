// RmlUi spike. See rmlmanager.h and docs/RMLUI_SPIKE.md.
#ifdef CHAOS_RMLUI

#include "rmlmanager.h"

#include <RmlUi/Core.h>
#include <framework/core/clock.h>
#include <framework/core/logger.h>
#include <framework/core/resourcemanager.h>
#include <framework/graphics/drawqueue.h>
#include <framework/graphics/graphics.h>
#include <framework/graphics/image.h>
#include <framework/graphics/painter.h>
#include <framework/graphics/paintershaderprogram.h>
#include <framework/graphics/texture.h>
#include <framework/ui/uimanager.h>
#include <framework/ui/uiwidget.h>

#include <cstring>

RmlManager g_rml;

// ---------------------------------------------------------------------------------------------------------------
// Render interface. Logic thread: CompileGeometry copies the triangles, RenderGeometry records one queue item.
// Render thread: the item draws the triangles with its own small program (per vertex colour, premultiplied alpha).
// ---------------------------------------------------------------------------------------------------------------
namespace {

// attribute locations of PainterShaderProgram (a protected enum there): VERTEX_ATTR, TEXCOORD_ATTR, COLOR_ATTR
const int kVertexAttr = 0, kTexCoordAttr = 1, kColorAttr = 3;

struct RmlGeometry {
    std::vector<float> xy;  // 2 per vertex, triangles already expanded (no index buffer: GL ES 2 safe)
    std::vector<float> uv;  // 0..1
    std::vector<float> rgba; // 4 per vertex, 0..1, premultiplied
    int vertexCount = 0;
};

const std::string kRmlVertex = "\n\
    attribute vec2 a_Vertex;\n\
    attribute vec2 a_TexCoord;\n\
    attribute vec4 a_Color;\n\
    uniform mat3 u_ProjectionMatrix;\n\
    uniform mat3 u_TransformMatrix;\n\
    uniform mat3 u_TextureMatrix;\n\
    varying vec2 v_TexCoord;\n\
    varying vec4 v_Color;\n\
    void main()\n\
    {\n\
        gl_Position = vec4((u_ProjectionMatrix * u_TransformMatrix * vec3(a_Vertex.xy, 1.0)).xy, 1.0, 1.0);\n\
        v_TexCoord = (u_TextureMatrix * vec3(a_TexCoord, 1.0)).xy;\n\
        v_Color = a_Color;\n\
    }\n";

// RmlUi colours and textures are premultiplied; the engine blends with SRC_ALPHA, so divide the alpha out again.
const std::string kRmlFragment = "\n\
    varying vec2 v_TexCoord;\n\
    varying vec4 v_Color;\n\
    uniform sampler2D u_Tex0;\n\
    void main()\n\
    {\n\
        vec4 c = texture2D(u_Tex0, v_TexCoord) * v_Color;\n\
        if (c.a <= 0.0) discard;\n\
        gl_FragColor = vec4(c.rgb / c.a, c.a);\n\
    }\n";

struct DrawQueueItemRml : public DrawQueueItem {
    DrawQueueItemRml(std::shared_ptr<RmlGeometry> geo, const TexturePtr& texture, float tx, float ty, bool clip, const Rect& clipRect)
        : DrawQueueItem(texture), m_geo(std::move(geo)), m_tx(tx), m_ty(ty), m_clip(clip), m_clipRect(clipRect) {}

    void draw() override
    {
        static PainterShaderProgramPtr program;
        static TexturePtr white;
        if (!program) {
            program = PainterShaderProgram::create("rmlProgram", kRmlVertex, kRmlFragment);
            if (!program) {
                g_logger.error("[RmlUi] can't build the shader");
                return;
            }
            ImagePtr px = std::make_shared<Image>(Size(1, 1), 4);
            std::memset(px->getPixelData(), 255, 4);
            white = std::make_shared<Texture>(px, false, false, false);
        }
        if (m_geo->vertexCount == 0)
            return;

        const TexturePtr tex = m_texture ? m_texture : white;
        g_painter->setTexture(tex);
        if (m_clip)
            g_painter->setClipRect(m_clipRect);
        else
            g_painter->resetClipRect();

        g_painter->pushTransformMatrix();
        g_painter->translate(m_tx, m_ty);
        program->bind();
        program->setTransformMatrix(g_painter->getTransformMatrix());
        program->setProjectionMatrix(g_painter->getProjectionMatrix());
        program->setTextureMatrix(g_painter->getTextureMatrix());
        program->setColor(Color::white);
        PainterShaderProgram::enableAttributeArray(kColorAttr);
        program->setAttributeArray(kVertexAttr, m_geo->xy.data(), 2);
        // the engine's texture matrix works on pixel coordinates
        if (m_scaledUv.size() != m_geo->uv.size()) {
            m_scaledUv = m_geo->uv;
            const float w = static_cast<float>(tex->getWidth()), h = static_cast<float>(tex->getHeight());
            for (size_t i = 0; i + 1 < m_scaledUv.size(); i += 2) {
                m_scaledUv[i] *= w;
                m_scaledUv[i + 1] *= h;
            }
        }
        program->setAttributeArray(kTexCoordAttr, m_scaledUv.data(), 2);
        program->setAttributeArray(kColorAttr, m_geo->rgba.data(), 4);
        glDrawArrays(GL_TRIANGLES, 0, m_geo->vertexCount);
        PainterShaderProgram::disableAttributeArray(kColorAttr);
        g_painter->popTransformMatrix();
        g_painter->resetClipRect();
    }

    std::shared_ptr<RmlGeometry> m_geo;
    std::vector<float> m_scaledUv;
    float m_tx, m_ty;
    bool m_clip;
    Rect m_clipRect;
};

} // namespace

class RmlRenderInterface : public Rml::RenderInterface
{
public:
    Rml::CompiledGeometryHandle CompileGeometry(Rml::Span<const Rml::Vertex> vertices, Rml::Span<const int> indices) override
    {
        auto geo = std::make_shared<RmlGeometry>();
        const size_t n = indices.size();
        geo->xy.reserve(n * 2);
        geo->uv.reserve(n * 2);
        geo->rgba.reserve(n * 4);
        for (size_t i = 0; i < n; ++i) {
            const int idx = indices[i];
            if (idx < 0 || static_cast<size_t>(idx) >= vertices.size())
                continue;
            const Rml::Vertex& v = vertices[idx];
            geo->xy.push_back(v.position.x);
            geo->xy.push_back(v.position.y);
            geo->uv.push_back(v.tex_coord.x);
            geo->uv.push_back(v.tex_coord.y);
            geo->rgba.push_back(v.colour.red / 255.f);
            geo->rgba.push_back(v.colour.green / 255.f);
            geo->rgba.push_back(v.colour.blue / 255.f);
            geo->rgba.push_back(v.colour.alpha / 255.f);
            ++geo->vertexCount;
        }
        return reinterpret_cast<Rml::CompiledGeometryHandle>(new std::shared_ptr<RmlGeometry>(std::move(geo)));
    }

    void RenderGeometry(Rml::CompiledGeometryHandle geometry, Rml::Vector2f translation, Rml::TextureHandle texture) override
    {
        if (!g_drawQueue)
            return;
        auto& geo = *reinterpret_cast<std::shared_ptr<RmlGeometry>*>(geometry);
        TexturePtr tex;
        if (texture)
            tex = *reinterpret_cast<TexturePtr*>(texture);
        g_drawQueue->add(std::make_unique<DrawQueueItemRml>(geo, tex, translation.x, translation.y, m_scissor, m_scissorRect));
    }

    void ReleaseGeometry(Rml::CompiledGeometryHandle geometry) override
    {
        delete reinterpret_cast<std::shared_ptr<RmlGeometry>*>(geometry);
    }

    Rml::TextureHandle LoadTexture(Rml::Vector2i& dimensions, const Rml::String& source) override
    {
        ImagePtr image = Image::load(source);
        if (!image || image->getBpp() != 4)
            return 0;
        uint8_t* p = image->getPixelData(); // premultiply: RmlUi expects it
        for (int i = 0, n = image->getPixelCount(); i < n; ++i, p += 4) {
            p[0] = static_cast<uint8_t>(p[0] * p[3] / 255);
            p[1] = static_cast<uint8_t>(p[1] * p[3] / 255);
            p[2] = static_cast<uint8_t>(p[2] * p[3] / 255);
        }
        dimensions.x = image->getWidth();
        dimensions.y = image->getHeight();
        return reinterpret_cast<Rml::TextureHandle>(new TexturePtr(std::make_shared<Texture>(image, false, false, true)));
    }

    Rml::TextureHandle GenerateTexture(Rml::Span<const Rml::byte> source, Rml::Vector2i dimensions) override
    {
        ImagePtr image = std::make_shared<Image>(Size(dimensions.x, dimensions.y), 4, const_cast<uint8_t*>(source.data()));
        return reinterpret_cast<Rml::TextureHandle>(new TexturePtr(std::make_shared<Texture>(image, false, false, true)));
    }

    void ReleaseTexture(Rml::TextureHandle texture) override { delete reinterpret_cast<TexturePtr*>(texture); }

    void EnableScissorRegion(bool enable) override { m_scissor = enable; }
    void SetScissorRegion(Rml::Rectanglei region) override
    {
        m_scissorRect = Rect(region.Left(), region.Top(), region.Width(), region.Height());
    }

private:
    bool m_scissor = false;
    Rect m_scissorRect;
};

class RmlSystemInterface : public Rml::SystemInterface
{
public:
    double GetElapsedTime() override { return stdext::micros() / 1000000.0; }
    bool LogMessage(Rml::Log::Type type, const Rml::String& message) override
    {
        switch (type) {
            case Rml::Log::LT_ERROR:
            case Rml::Log::LT_ASSERT: g_logger.error("[RmlUi] " + message); break;
            case Rml::Log::LT_WARNING: g_logger.warning("[RmlUi] " + message); break;
            default: g_logger.info("[RmlUi] " + message); break;
        }
        return true;
    }
};

// Files come from the engine's resource manager (PhysFS: the packed modules, the update folder, the write dir).
class RmlFileInterface : public Rml::FileInterface
{
    struct Handle { std::string data; size_t pos = 0; };
public:
    Rml::FileHandle Open(const Rml::String& path) override
    {
        try {
            if (!g_resources.fileExists(path))
                return 0;
            auto* h = new Handle();
            h->data = g_resources.readFileContents(path);
            return reinterpret_cast<Rml::FileHandle>(h);
        } catch (...) {
            return 0;
        }
    }
    void Close(Rml::FileHandle file) override { delete reinterpret_cast<Handle*>(file); }
    size_t Read(void* buffer, size_t size, Rml::FileHandle file) override
    {
        auto* h = reinterpret_cast<Handle*>(file);
        const size_t n = std::min(size, h->data.size() - h->pos);
        std::memcpy(buffer, h->data.data() + h->pos, n);
        h->pos += n;
        return n;
    }
    bool Seek(Rml::FileHandle file, long offset, int origin) override
    {
        auto* h = reinterpret_cast<Handle*>(file);
        long base = origin == SEEK_CUR ? static_cast<long>(h->pos) : origin == SEEK_END ? static_cast<long>(h->data.size()) : 0;
        long to = base + offset;
        if (to < 0 || to > static_cast<long>(h->data.size()))
            return false;
        h->pos = static_cast<size_t>(to);
        return true;
    }
    size_t Tell(Rml::FileHandle file) override { return reinterpret_cast<Handle*>(file)->pos; }
    size_t Length(Rml::FileHandle file) override { return reinterpret_cast<Handle*>(file)->data.size(); }
};

// One listener for every document: click and change go to the Lua callback with the id of the nearest element that has one.
class RmlRelay : public Rml::EventListener
{
public:
    void ProcessEvent(Rml::Event& event) override
    {
        Rml::Element* target = event.GetTargetElement();
        if (!target)
            return;
        g_rml.dispatch(target->GetOwnerDocument(), target, event.GetType());
    }
};

// ---------------------------------------------------------------------------------------------------------------

namespace {

int mapModifiers(int fw)
{
    int m = 0;
    if (fw & Fw::KeyboardCtrlModifier) m |= Rml::Input::KM_CTRL;
    if (fw & Fw::KeyboardShiftModifier) m |= Rml::Input::KM_SHIFT;
    if (fw & Fw::KeyboardAltModifier) m |= Rml::Input::KM_ALT;
    return m;
}

Rml::Input::KeyIdentifier mapKey(Fw::Key k)
{
    using namespace Rml::Input;
    if (k >= Fw::KeyA && k <= Fw::KeyZ) return static_cast<KeyIdentifier>(KI_A + (k - Fw::KeyA));
    if (k >= Fw::Key0 && k <= Fw::Key9) return static_cast<KeyIdentifier>(KI_0 + (k - Fw::Key0));
    switch (k) {
        case Fw::KeyEscape: return KI_ESCAPE;
        case Fw::KeyTab: return KI_TAB;
        case Fw::KeyBackspace: return KI_BACK;
        case Fw::KeyEnter: return KI_RETURN;
        case Fw::KeyInsert: return KI_INSERT;
        case Fw::KeyDelete: return KI_DELETE;
        case Fw::KeyHome: return KI_HOME;
        case Fw::KeyEnd: return KI_END;
        case Fw::KeyPageUp: return KI_PRIOR;
        case Fw::KeyPageDown: return KI_NEXT;
        case Fw::KeyUp: return KI_UP;
        case Fw::KeyDown: return KI_DOWN;
        case Fw::KeyLeft: return KI_LEFT;
        case Fw::KeyRight: return KI_RIGHT;
        case Fw::KeySpace: return KI_SPACE;
        default: return KI_UNKNOWN;
    }
}

} // namespace

RmlManager::RmlManager() = default;
RmlManager::~RmlManager() = default;

bool RmlManager::init()
{
    if (m_context)
        return true;
    if (m_failed)
        return false;
    m_render = std::make_unique<RmlRenderInterface>();
    m_system = std::make_unique<RmlSystemInterface>();
    m_files = std::make_unique<RmlFileInterface>();
    m_relay = std::make_unique<RmlRelay>();
    Rml::SetRenderInterface(m_render.get());
    Rml::SetSystemInterface(m_system.get());
    Rml::SetFileInterface(m_files.get());
    if (!Rml::Initialise()) {
        m_failed = true;
        g_logger.error("[RmlUi] Initialise failed");
        return false;
    }
    Size size(960, 540);
    if (auto root = g_ui.getRootWidget())
        size = root->getSize();
    m_context = Rml::CreateContext("chaos", Rml::Vector2i(std::max(1, size.width()), std::max(1, size.height())));
    if (!m_context) {
        m_failed = true;
        g_logger.error("[RmlUi] CreateContext failed");
        return false;
    }
    g_logger.info(std::string("[RmlUi] ready, version ") + Rml::GetVersion());
    return true;
}

void RmlManager::terminate()
{
    if (!m_context && !m_render)
        return;
    m_docs.clear();
    m_context = nullptr;
    Rml::Shutdown(); // releases every geometry and texture through the render interface
    m_relay.reset();
    m_files.reset();
    m_system.reset();
    m_render.reset();
}

bool RmlManager::loadFont(const std::string& path, bool fallback)
{
    return init() && Rml::LoadFontFace(path, fallback);
}

int RmlManager::loadDocument(const std::string& path)
{
    if (!init())
        return 0;
    Rml::ElementDocument* doc = m_context->LoadDocument(path);
    if (!doc) {
        g_logger.error("[RmlUi] can't load document " + path);
        return 0;
    }
    doc->AddEventListener("click", m_relay.get());
    doc->AddEventListener("change", m_relay.get());
    const int id = m_nextId++;
    m_docs[id] = doc;
    return id;
}

Rml::Element* RmlManager::find(int doc, const std::string& elementId)
{
    auto it = m_docs.find(doc);
    if (it == m_docs.end())
        return nullptr;
    return elementId.empty() ? it->second : it->second->GetElementById(elementId);
}

bool RmlManager::show(int doc)
{
    auto it = m_docs.find(doc);
    if (it == m_docs.end())
        return false;
    it->second->Show();
    return true;
}

bool RmlManager::hide(int doc)
{
    auto it = m_docs.find(doc);
    if (it == m_docs.end())
        return false;
    it->second->Hide();
    return true;
}

bool RmlManager::close(int doc)
{
    auto it = m_docs.find(doc);
    if (it == m_docs.end())
        return false;
    it->second->Close();
    m_docs.erase(it);
    return true;
}

bool RmlManager::isVisible(int doc)
{
    auto it = m_docs.find(doc);
    return it != m_docs.end() && it->second->IsVisible();
}

bool RmlManager::setText(int doc, const std::string& elementId, const std::string& text)
{
    Rml::Element* e = find(doc, elementId);
    if (!e)
        return false;
    e->SetInnerRML(escape(text));
    return true;
}

bool RmlManager::setInnerRml(int doc, const std::string& elementId, const std::string& rml)
{
    Rml::Element* e = find(doc, elementId);
    if (!e)
        return false;
    e->SetInnerRML(rml);
    return true;
}

bool RmlManager::setClass(int doc, const std::string& elementId, const std::string& className, bool on)
{
    Rml::Element* e = find(doc, elementId);
    if (!e)
        return false;
    e->SetClass(className, on);
    return true;
}

bool RmlManager::setProperty(int doc, const std::string& elementId, const std::string& name, const std::string& value)
{
    Rml::Element* e = find(doc, elementId);
    return e && e->SetProperty(name, value);
}

void RmlManager::setScale(float scale)
{
    m_scale = scale > 0.1f ? scale : 1.f;
    if (m_context)
        m_context->SetDensityIndependentPixelRatio(m_scale);
}

// The engine draws and stores text as cp1252 (patch 0028, client_chaos_locale), RmlUi wants UTF-8. Bytes below 0x80 are
// the same in both; 0xA0-0xFF are the same code points as Latin-1; 0x80-0x9F are the cp1252 punctuation block.
static void appendUtf8(std::string& out, unsigned char c)
{
    static const unsigned short cp1252[32] = {
        0x20AC, 0x81, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021, 0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0x8D, 0x017D, 0x8F,
        0x90, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014, 0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0x9D, 0x017E, 0x0178};
    unsigned cp = c < 0x80 ? c : (c < 0xA0 ? cp1252[c - 0x80] : c);
    if (cp < 0x80) {
        out += static_cast<char>(cp);
    } else if (cp < 0x800) {
        out += static_cast<char>(0xC0 | (cp >> 6));
        out += static_cast<char>(0x80 | (cp & 0x3F));
    } else {
        out += static_cast<char>(0xE0 | (cp >> 12));
        out += static_cast<char>(0x80 | ((cp >> 6) & 0x3F));
        out += static_cast<char>(0x80 | (cp & 0x3F));
    }
}

std::string RmlManager::escape(const std::string& text)
{
    std::string out;
    out.reserve(text.size());
    for (char ch : text) {
        const unsigned char c = static_cast<unsigned char>(ch);
        if (c >= 0x80) {
            appendUtf8(out, c);
            continue;
        }
        switch (ch) {
            case '&': out += "&amp;"; break;
            case '<': out += "&lt;"; break;
            case '>': out += "&gt;"; break;
            case '"': out += "&quot;"; break;
            default: out += ch;
        }
    }
    return out;
}

void RmlManager::dispatch(Rml::ElementDocument* doc, Rml::Element* target, const std::string& type)
{
    if (!m_callback || !doc)
        return;
    int docId = 0;
    for (auto& kv : m_docs)
        if (kv.second == doc) { docId = kv.first; break; }
    for (Rml::Element* e = target; e && e != doc->GetParentNode(); e = e->GetParentNode()) {
        if (!e->GetId().empty()) {
            m_callback(docId, e->GetId(), type);
            return;
        }
    }
}

void RmlManager::render()
{
    if (!m_context || m_docs.empty())
        return;
    if (auto root = g_ui.getRootWidget()) {
        const Size s = root->getSize();
        const Rml::Vector2i want(std::max(1, s.width()), std::max(1, s.height()));
        if (m_context->GetDimensions() != want)
            m_context->SetDimensions(want);
    }
    m_context->Update();
    m_context->Render();
}

bool RmlManager::hoverInDocument()
{
    Rml::Element* h = m_context->GetHoverElement();
    return h && h != m_context->GetRootElement() && h->GetOwnerDocument() && h->GetOwnerDocument()->IsVisible();
}

bool RmlManager::focusInTextField()
{
    Rml::Element* f = m_context->GetFocusElement();
    if (!f)
        return false;
    const Rml::String& tag = f->GetTagName();
    return tag == "input" || tag == "textarea" || tag == "select";
}

bool RmlManager::inputEvent(const InputEvent& e)
{
    if (!m_context || m_docs.empty())
        return false;
    const int mods = mapModifiers(e.keyboardModifiers);
    switch (e.type) {
        case Fw::MouseMoveInputEvent:
            m_context->ProcessMouseMove(e.mousePos.x, e.mousePos.y, mods);
            return hoverInDocument() || m_pressedInside;
        case Fw::MousePressInputEvent: {
            m_context->ProcessMouseMove(e.mousePos.x, e.mousePos.y, mods);
            if (!hoverInDocument())
                return false;
            m_pressedInside = true;
            int button = e.mouseButton == Fw::MouseRightButton ? 1 : e.mouseButton == Fw::MouseMidButton ? 2 : 0;
            m_context->ProcessMouseButtonDown(button, mods);
            return true;
        }
        case Fw::MouseReleaseInputEvent: {
            if (!m_pressedInside)
                return false;
            m_pressedInside = false;
            int button = e.mouseButton == Fw::MouseRightButton ? 1 : e.mouseButton == Fw::MouseMidButton ? 2 : 0;
            m_context->ProcessMouseButtonUp(button, mods);
            return true;
        }
        case Fw::MouseWheelInputEvent:
            m_context->ProcessMouseMove(e.mousePos.x, e.mousePos.y, mods);
            if (!hoverInDocument())
                return false;
            m_context->ProcessMouseWheel(Rml::Vector2f(0.f, e.wheelDirection == Fw::MouseWheelUp ? -1.f : 1.f), mods);
            return true;
        case Fw::KeyDownInputEvent:
            if (!focusInTextField())
                return false;
            m_context->ProcessKeyDown(mapKey(e.keyCode), mods);
            return true;
        case Fw::KeyUpInputEvent:
            if (!focusInTextField())
                return false;
            m_context->ProcessKeyUp(mapKey(e.keyCode), mods);
            return true;
        case Fw::KeyPressInputEvent:
            return focusInTextField();
        case Fw::KeyTextInputEvent:
            if (!focusInTextField())
                return false;
            m_context->ProcessTextInput(Rml::String(e.keyText));
            return true;
        default:
            return false;
    }
}

#endif // CHAOS_RMLUI
