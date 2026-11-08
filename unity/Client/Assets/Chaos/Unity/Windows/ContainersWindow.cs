using System.Collections.Generic;
using Chaos.Core;
using UnityEngine;

namespace Chaos.Client
{
    /// <summary>Every open container, stacked: name, up and close buttons, a grid of slots (4 per row). Scrolls when long.
    /// Opens by itself when the server opens a container.</summary>
    public sealed class ContainersWindow : GameWindow
    {
        public override string Title => "Containers";
        public override KeyCode Hotkey => KeyCode.O;

        const float SlotSize = 34, Gap = 2, Head = 22, Between = 6;
        const int PerRow = 4;
        Vector2 scroll;
        // the container objects seen so far: a new object means the server opened (or reopened) one
        readonly Dictionary<byte, Container> known = new Dictionary<byte, Container>();
        readonly List<byte> gone = new List<byte>();
        // the contents last seen per container and the time peek was last asked: the loot filter's rarity rows (opcode 238 peek)
        readonly Dictionary<byte, string> peekSig = new Dictionary<byte, string>();
        readonly Dictionary<byte, float> peekAt = new Dictionary<byte, float>();

        protected override Rect Place(float w, float h)
        {
            float top = 48 + 270 + 8;
            return new Rect(w - 198, top, 188, Mathf.Clamp(h - top - 8, 160, 380));
        }

        public override void Reset() { known.Clear(); peekSig.Clear(); peekAt.Clear(); scroll = Vector2.zero; ItemSlots.Cancel(); }

        public override void Tick(ChaosApp app)
        {
            var open = app.Session?.Parser.Containers;
            if (open == null) return;
            foreach (var kv in open)
            {
                if (known.TryGetValue(kv.Key, out var old) && old == kv.Value) continue;
                known[kv.Key] = kv.Value;
                Open = true;
            }
            gone.Clear();
            foreach (var id in known.Keys) if (!open.ContainsKey(id)) gone.Add(id);
            var filter = app.FindWindow<LootWindow>()?.Filter;
            foreach (var id in gone) { known.Remove(id); peekSig.Remove(id); peekAt.Remove(id); filter?.ForgetPeek(id); }
            if (filter == null) return;
            foreach (var kv in open)
            {
                string sig = LootPeek.Signature(kv.Value);
                if (peekSig.TryGetValue(kv.Key, out var old) && old == sig) continue;
                if (peekAt.TryGetValue(kv.Key, out float at) && Time.unscaledTime - at < 0.25f) continue;
                peekSig[kv.Key] = sig; peekAt[kv.Key] = Time.unscaledTime;
                filter.RequestPeek(kv.Key);
            }
        }

        /// <summary>The loot filter on a slot: a glow for what the filter highlights, a frame in the rarity colour when the item has none of its own, a dark veil for a dimmed item of a corpse.</summary>
        static void DrawPeek(Rect r, Container c, int i, Item it, PeekSet peek, LootFilterSettings settings, bool attrsOn)
        {
            if (!peek.Items.TryGetValue(c.FirstIndex + i, out var row) || !LootPeek.RowFits(row, it, true, attrsOn)) return;
            var d = LootPeek.Decorate(row, peek.Corpse, settings);
            if (d.Color != null && (d.Glow || d.Soft))
            {
                if (ColorUtility.TryParseHtmlString(d.Color, out var col))
                {
                    col.a = d.Soft ? 0.45f : 0.8f;
                    float w = d.Soft ? 1 : 2;
                    ChaosApp.Fill(new Rect(r.x - w, r.y - w, r.width + 2 * w, w), col);
                    ChaosApp.Fill(new Rect(r.x - w, r.yMax, r.width + 2 * w, w), col);
                    ChaosApp.Fill(new Rect(r.x - w, r.y, w, r.height), col);
                    ChaosApp.Fill(new Rect(r.xMax, r.y, w, r.height), col);
                }
            }
            if (d.Color != null && !d.Soft && ItemRarity.FrameColor(it) == null) ItemSlots.Frame(r, d.Color);
            if (d.Dim) ChaosApp.Fill(r, new Color(0.04f, 0.03f, 0.05f, 0.55f));
        }

        static int Rows(Container c) => (Mathf.Max(c.Capacity, c.Items.Count) + PerRow - 1) / PerRow;

        protected override void Body(ChaosApp app, Rect inner)
        {
            var s = app.Session;
            if (s == null) return;
            var open = s.Parser.Containers;
            // copy the ids: the buttons below send packets, the dictionary changes on a later poll, not now
            var ids = new List<byte>(open.Keys);
            ids.Sort();
            if (ids.Count == 0)
            {
                GUI.Label(new Rect(inner.x + 4, inner.y + 4, inner.width - 8, 40), "No container is open.\nRight-click a bag to open it.", app.SmallStyle);
                ItemSlots.Ghost(app, new Rect(0, 0, Area.width, Area.height));
                return;
            }
            float contentH = 0;
            foreach (var id in ids) contentH += Head + Rows(open[id]) * (SlotSize + Gap) + Between;
            float viewW = inner.width - 20;
            scroll = GUI.BeginScrollView(inner, scroll, new Rect(0, 0, viewW, Mathf.Max(contentH, inner.height - 2)));
            float y = 0;
            var filter = app.FindWindow<LootWindow>()?.Filter;
            bool attrsOn = s.Parser.Features.Has(ClientFeatures.ItemCustomAttributes);
            foreach (var id in ids)
            {
                var c = open[id];
                var peek = filter?.PeekOf(id);
                ChaosApp.Fill(new Rect(0, y, viewW, Head - 2), new Color(0.16f, 0.09f, 0.06f, 0.9f));
                if (c.ItemId != 0) app.DrawItem(new Rect(1, y, Head - 2, Head - 2), c.ItemId, 0);
                GUI.Label(new Rect(Head, y - 1, viewW - Head - 44, Head), c.Name, app.SmallStyle);
                if (c.HasParent && GUI.Button(new Rect(viewW - 42, y, 20, Head - 2), "^")) s.UpContainer(c.Id);
                if (GUI.Button(new Rect(viewW - 20, y, 20, Head - 2), "x")) s.CloseContainer(c.Id);
                y += Head;
                int n = Mathf.Max(c.Capacity, c.Items.Count);
                for (int i = 0; i < n; i++)
                {
                    var r = new Rect((i % PerRow) * (SlotSize + Gap), y + (i / PerRow) * (SlotSize + Gap), SlotSize, SlotSize);
                    int slot = c.FirstIndex + i;
                    var it = i < c.Items.Count ? c.Items[i] : null;
                    ItemSlots.Slot(app, r, it, GameSession.ContainerPos(c.Id, slot), (byte)(slot & 0xFF), null);
                    if (it != null) ItemSlots.Frame(r, app.CardBorderColor(c.ItemId, it.Id));   // game_cardborder: a card in a deck bag
                    if (it != null && peek != null && Event.current.type == EventType.Repaint) DrawPeek(r, c, i, it, peek, filter.Settings, attrsOn);
                }
                y += Rows(c) * (SlotSize + Gap) + Between;
            }
            GUI.EndScrollView();
            ItemSlots.Ghost(app, new Rect(0, 0, Area.width, Area.height));
        }
    }
}
