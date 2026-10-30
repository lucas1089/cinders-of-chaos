// RmlUi layer: HTML/RCSS documents next to the OTUI windows. Built only with -DCHAOS_RMLUI=ON (docs/RMLUI_SPIKE.md).
// Threads: the context, the Lua calls and the input hook live on the dispatcher (logic) thread, like every widget.
// The render interface only records geometry into the frame's DrawQueue; the GL calls run on the render thread.
#ifndef CHAOS_RMLMANAGER_H
#define CHAOS_RMLMANAGER_H

#ifdef CHAOS_RMLUI

#include <framework/core/inputevent.h>
#include <framework/global.h>
#include "rmlinputlogic.h"
#include <functional>
#include <map>
#include <memory>
#include <string>

namespace Rml { class Context; class ElementDocument; class Element; }
struct RmlTouchTarget;
class RmlRenderInterface;
class RmlSystemInterface;
class RmlFileInterface;
class RmlRelay;

class RmlManager
{
public:
    RmlManager();
    ~RmlManager();

    // Lua (g_rml). Documents are plain ints so Lua never holds an Rml pointer.
    bool init();
    void terminate();
    bool isReady() const { return m_context != nullptr; }
    bool loadFont(const std::string& path, bool fallback = false);
    int loadDocument(const std::string& path);
    bool show(int doc);
    bool hide(int doc);
    bool close(int doc);
    bool isVisible(int doc);
    bool setText(int doc, const std::string& elementId, const std::string& text);
    bool setInnerRml(int doc, const std::string& elementId, const std::string& rml);
    bool setClass(int doc, const std::string& elementId, const std::string& className, bool on);
    bool setProperty(int doc, const std::string& elementId, const std::string& name, const std::string& value);
    // form controls (phase 3, the Options window): input, select. Values are UTF-8 as RmlUi keeps them; setValue and
    // setChecked fire a "change" event like a click does.
    std::string getValue(int doc, const std::string& elementId);
    bool setValue(int doc, const std::string& elementId, const std::string& value);
    bool isChecked(int doc, const std::string& elementId);
    bool setChecked(int doc, const std::string& elementId, bool checked);
    bool setDisabled(int doc, const std::string& elementId, bool disabled);
    void setEventCallback(const std::function<void(int, std::string, std::string)>& callback) { m_callback = callback; }
    void setScale(float scale);          // extra factor on top of the engine scale (default 1), see getDpRatio
    float getDpRatio() const { return m_scale; }
    float getEngineScale() const { return m_engineScale; } // g_app scale: window size / interface size
    void clearCaches();                   // style sheets and templates are read again (hot reload, module reload)
    bool isPointerOver() const { return m_overRml; }  // the pointer is over a visible RmlUi element
    bool hasTextFocus();                  // an RmlUi input, textarea or select has the focus
    float getScrollTop(int doc, const std::string& elementId);
    bool setScrollTop(int doc, const std::string& elementId, float value);
    Rect getRect(int doc, const std::string& elementId); // border box in interface pixels (empty: no such element)
    // Test hook: feeds one mouse event straight to inputEvent(), as the window code does (kind: move, press, release,
    // wheelup, wheeldown; button: left, right, touch). Returns what inputEvent returns (true = RmlUi took it).
    bool injectMouse(const std::string& kind, int x, int y, const std::string& button);
    std::string escape(const std::string& text); // cp1252 (engine text) to escaped UTF-8 for RmlUi
    int getDocumentCount() const { return static_cast<int>(m_docs.size()); }

    // engine hooks
    void render();                        // UIManager::render, foreground pane: update + record
    bool inputEvent(const InputEvent& e); // UIManager::inputEvent: true = consumed, OTUI does not see it

private:
    friend class RmlRelay;
    Rml::Element* find(int doc, const std::string& elementId);
    void dispatch(Rml::ElementDocument* doc, Rml::Element* target, const std::string& type);
    bool hoverInDocument();
    bool focusInTextField();
    chaosrml::RouteState routeState();
    void syncHoverBlock();
    void applyScroll(const chaosrml::Delta& d);
    void updateScale();

    Rml::Context* m_context = nullptr;
    std::unique_ptr<RmlRenderInterface> m_render;
    std::unique_ptr<RmlSystemInterface> m_system;
    std::unique_ptr<RmlFileInterface> m_files;
    std::unique_ptr<RmlRelay> m_relay;
    std::map<int, Rml::ElementDocument*> m_docs;
    int m_nextId = 1;
    float m_scale = 1.f;
    bool m_failed = false;
    bool m_pressedInside = false;
    Point m_lastInjected;
    bool m_overRml = false;      // last known: pointer over a visible RmlUi element
    bool m_touchInside = false;  // a finger went down over RmlUi
    float m_engineScale = 1.f;
    chaosrml::FrameSignature m_sig;
    chaosrml::TouchScroll m_touch;
    std::unique_ptr<RmlTouchTarget> m_touchTarget; // element under the finger (observer pointer)
    std::function<void(int, std::string, std::string)> m_callback;
};

extern RmlManager g_rml;

#endif // CHAOS_RMLUI
#endif
