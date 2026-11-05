// Attacking from the map, the red frame round the target and the remembered minimap. Used by the Battle list and Minimap windows.
using Chaos.Core;
using UnityEngine;

namespace Chaos.Client
{
    public sealed partial class ChaosApp
    {
        /// <summary>True while the chat line has the keyboard focus: hotkeys must not fire then.</summary>
        public bool ChatFocused => chatFocused;

        int textEditFrame = -10;
        /// <summary>A window text field has the keyboard: call every frame it is edited. Walking and Enter-to-chat pause.</summary>
        public void MarkTextEditing() { textEditFrame = Time.frameCount; }
        bool TextEditing => Time.frameCount - textEditFrame <= 1;

        /// <summary>What the minimap remembers of this character's walks.</summary>
        public readonly MinimapMemory Minimap = new MinimapMemory();
        World minimapWorld;
        float minimapNext;

        void CombatUpdate()
        {
            // a new world (another character): forget the old minimap
            if (minimapWorld != world) { minimapWorld = world; Minimap.Clear(); minimapNext = 0f; }
            if (world != null && Time.unscaledTime >= minimapNext)
            {
                minimapNext = Time.unscaledTime + 0.2f;
                Minimap.Update(world);
            }
            // right-click on a creature on the map attacks it
            if (view != null && Input.GetMouseButtonDown(1) && !OverUi(Input.mousePosition) && cam.pixelRect.Contains(Input.mousePosition))
            {
                Vector3 wp = cam.ScreenToWorldPoint(new Vector3(Input.mousePosition.x, Input.mousePosition.y, 10f));
                uint me = world?.PlayerId ?? 0;
                Creature hit = null;
                foreach (var (c, at) in view.Labels)
                    if (c.Id != me && wp.x >= at.x && wp.x < at.x + 1f && wp.y <= at.y && wp.y > at.y - 1f) hit = c;
                if (hit != null) session.Attack(hit.Id);
            }
        }

        /// <summary>A red square frame round the attacked creature. Called inside the map group (map is its rect, in UI units).</summary>
        void DrawAttackFrame(Rect map, float scale)
        {
            uint target = session?.AttackTarget ?? 0;
            if (target == 0 || view == null) return;
            foreach (var (c, at) in view.Labels)
            {
                if (c.Id != target) continue;
                Vector3 a = cam.WorldToScreenPoint(new Vector3(at.x, at.y, 0f));
                Vector3 b = cam.WorldToScreenPoint(new Vector3(at.x + 1f, at.y - 1f, 0f));
                float x0 = a.x / scale - map.x, y0 = (UnityEngine.Screen.height - a.y) / scale - map.y;
                float x1 = b.x / scale - map.x, y1 = (UnityEngine.Screen.height - b.y) / scale - map.y;
                var red = new Color(0.95f, 0.1f, 0.1f, 1f);
                const float t = 2f;
                Fill(new Rect(x0, y0, x1 - x0, t), red);
                Fill(new Rect(x0, y1 - t, x1 - x0, t), red);
                Fill(new Rect(x0, y0, t, y1 - y0), red);
                Fill(new Rect(x1 - t, y0, t, y1 - y0), red);
                return;
            }
        }
    }
}
