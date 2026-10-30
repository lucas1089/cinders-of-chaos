// RmlUi spike: HTML/RCSS documents next to the OTUI windows. Built only with -DCHAOS_RMLUI=ON.
// Threads: the context, the Lua calls and the input hook live on the dispatcher (logic) thread, like every widget.
// The render interface only records geometry into the frame's DrawQueue; the GL calls run on the render thread.
#ifndef CHAOS_RMLMANAGER_H
#define CHAOS_RMLMANAGER_H

#ifdef CHAOS_RMLUI

#include <framework/core/inputevent.h>
#include <framework/global.h>
#include <functional>
#include <map>
#include <memory>
#include <string>

namespace Rml { class Context; class ElementDocument; class Element; }
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
    void setEventCallback(const std::function<void(int, std::string, std::string)>& callback) { m_callback = callback; }
    void setScale(float scale);
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
    std::function<void(int, std::string, std::string)> m_callback;
};

extern RmlManager g_rml;

#endif // CHAOS_RMLUI
#endif
