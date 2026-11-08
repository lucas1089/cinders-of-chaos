// Base gameplay actions on the map and in the slots (track P): look, use with, rotate, trade requests and the item menu. Models: Core/Play.cs.
//   Shift + left click      look (on the map, and on a slot when the chat line is not being written: then it links the item)
//   Left click after "Use with ..." or "Trade with ..."   the target (a map item, a creature, a slot)
//   Right click on a map item   use it (a multi-use item starts "Use with ..."); on a slot the same, as the main client's Classic Controls
//   Ctrl + right click      the item menu (Look, Use or Open, Use with, Rotate, Trade with and the Chaos hooks), on a slot or a map item
//   Esc or right click      ends the crosshair
// The classic view and the live view find the tile under the pointer; the HD-2D scene has no tile geometry here, so there only creatures can be picked.
using System;
using System.Collections.Generic;
using System.Linq;
using Chaos.Core;
using UnityEngine;

namespace Chaos.Client
{
    public sealed partial class ChaosApp
    {
        public readonly CrosshairState Crosshair = new CrosshairState();
        int playClickFrame = -10;
        GUIStyle crossStyle;

        void AddPlayWindows()
        {
            windows.Add(new TradeWindow());
            windows.Add(new VipWindow());
            windows.Add(new QuestLogWindow());
            windows.Add(new LookPreviewWindow());
        }

        /// <summary>A click of this frame was taken by the play actions: the creature menu and the attack on a right click stay out of it.</summary>
        bool PlayUsedClick => playClickFrame == Time.frameCount;

        static bool ShiftDown => Input.GetKey(KeyCode.LeftShift) || Input.GetKey(KeyCode.RightShift);
        static bool CtrlDown => Input.GetKey(KeyCode.LeftControl) || Input.GetKey(KeyCode.RightControl);

        /// <summary>The pointer is on the map and no window is under it.</summary>
        bool PointerOnMap => cam != null && cam.pixelRect.Contains(Input.mousePosition) && !OverUi(Input.mousePosition);

        /// <summary>While Shift is held or a crosshair is up, a held left button must not walk.</summary>
        bool PlayBlocksWalk => Crosshair.Active || (ShiftDown && !CtrlDown && PointerOnMap);

        // ------------------------------------------------------------------------------------ picking
        /// <summary>The creature under the pointer, the tile under it and the item the pointer means on that tile (by the use rule when `forUse`, else by the look rule).</summary>
        void PickAtMouse(bool forUse, out Creature creature, out Tile tile, out ItemRef? item)
        {
            creature = null; tile = null; item = null;
            if (world == null) return;
            uint me = world.PlayerId;
            Vector2 m = Input.mousePosition;
            if (HdLabelsOn)
            {
                float best = float.MaxValue;
                foreach (var l in HdLabels)
                {
                    Vector3 a = cam.WorldToScreenPoint(l.BottomLeft), b = cam.WorldToScreenPoint(l.TopRight);
                    var r = Rect.MinMaxRect(Mathf.Min(a.x, b.x), Mathf.Min(a.y, b.y), Mathf.Max(a.x, b.x), Mathf.Max(a.y, b.y));
                    if (l.C.Id != me && r.Contains(m) && a.z < best) { best = a.z; creature = l.C; }
                }
            }
            else if (view != null)
            {
                Vector3 wp = cam.ScreenToWorldPoint(new Vector3(m.x, m.y, 10f));
                foreach (var (c, at) in view.Labels)
                    if (c.Id != me && wp.x >= at.x && wp.x < at.x + 1f && wp.y <= at.y && wp.y > at.y - 1f) creature = c;
            }
            // the tile whose middle is nearest to the pointer, when the pointer is inside its box
            var centre = world.Center;
            float half = 0f;
            if (TileScreenPx(centre, out Vector3 p0) && TileScreenPx(centre.Offset(1, 0), out Vector3 p1)) half = Mathf.Abs(p1.x - p0.x) / 2f;
            if (half < 2f) half = cam.pixelRect.height / ViewTilesH / 2f;
            for (int dx = -world.Range.Left; dx <= world.Range.Right && tile == null; dx++)
                for (int dy = -world.Range.Top; dy <= world.Range.Bottom; dy++)
                {
                    var p = centre.Offset(dx, dy);
                    if (!TileScreenPx(p, out Vector3 px)) goto noTiles;
                    if (Mathf.Abs(px.x - m.x) <= half && Mathf.Abs(px.y - m.y) <= half) { tile = world.Get(p); break; }
                }
            noTiles:
            if (tile == null) return;
            if (creature == null) { var c = TilePick.TopCreature(tile); if (c != null && c.Id != me) creature = c; }
            int idx = forUse ? TilePick.UseIndex(tile) : TilePick.LookIndex(tile);
            item = TilePick.ItemAt(tile, idx);
        }

        // ------------------------------------------------------------------------------------ the map's clicks
        /// <summary>Called every frame before the combat clicks.</summary>
        void PlayUpdate()
        {
            if (session == null || world?.Player == null || chatFocused || TextEditing) return;
            if (Crosshair.Active && Input.GetKeyDown(KeyCode.Escape)) Crosshair.Cancel();
            if (!PointerOnMap) return;
            if (Input.GetMouseButtonDown(1) && Time.frameCount - groundLabelHoverFrame <= 1) return;   // the ground label under the pointer takes the right click
            if (Input.GetMouseButtonDown(0))
            {
                if (Crosshair.Active)
                {
                    PickAtMouse(false, out var c, out var t, out var it);
                    CrosshairClick(it, c);
                    playClickFrame = Time.frameCount;
                }
                else if (ShiftDown && !CtrlDown)
                {
                    PickAtMouse(false, out var c, out var t, out var it);
                    if (c != null) session.LookAtCreature(c.Id);
                    else if (it.HasValue) session.Look(it.Value);
                    playClickFrame = Time.frameCount;
                }
            }
            else if (Input.GetMouseButtonDown(1))
            {
                if (Crosshair.Active) { Crosshair.Cancel(); playClickFrame = Time.frameCount; return; }
                PickAtMouse(true, out var c, out var t, out var it);
                if (CtrlDown && c == null && it.HasValue) { ShowItemMenu(it.Value, MouseUi()); playClickFrame = Time.frameCount; }
                else if (c == null && it.HasValue && it.Value.Item.Type != null && !it.Value.Item.Type.Ground && !it.Value.Item.Type.GroundBorder)
                {
                    RightClickItem(it.Value);
                    playClickFrame = Time.frameCount;
                }
            }
        }

        /// <summary>The plain right click on an item (map, equipment or bag): a multi-use item starts "Use with ...", anything else is used.</summary>
        public void RightClickItem(ItemRef r)
        {
            if (session == null || r.Item == null) return;
            if (ItemMenu.RightClickIsUseWith(r.Item, session.Hud.Options.MultiUseIds, session.Hud.Options.RightClickEquips)) Crosshair.Start(CrosshairState.Kind.UseWith, r);
            else session.UseItem(r.Pos, r.Id, r.Stack, ItemSlots.FreeContainerId(this));
        }

        /// <summary>A click on a target while the crosshair is up: a map item or creature, or a slot (item only).</summary>
        public void CrosshairClick(ItemRef? item, Creature creature)
        {
            if (!Crosshair.Active || session == null) return;
            var mode = Crosshair.Mode;
            var packet = Crosshair.Click(item, creature, world?.PlayerId ?? 0);
            if (packet != null) session.SendRaw(packet);
            else if (mode == CrosshairState.Kind.Trade) PostLine(Loc.T("Click another player to trade with."));
        }

        // ------------------------------------------------------------------------------------ the item menu
        public void ShowItemMenu(ItemRef r, Vector2 at)
        {
            if (session == null || r.Item == null) return;
            var u = Utils;
            var ctx = new ItemMenuContext
            {
                OnLootList = u != null && u.AutoLoot.IsOnList(r.Id),
                IsLootPouch = u != null && u.Pouches.IsLootPouch(r.Id, r.Item.Attr(ItemAttr.Locked)),
                AnotherPlayerInView = world != null && world.Creatures.Values.Any(c => c.Type == 0 && c.Id != world.PlayerId),
                RarityOf = (int)r.Item.Attr(ItemAttr.Rarity),
            };
            var items = new List<KeyValuePair<string, Action>>();
            foreach (var e in ItemMenu.Build(r, ctx))
            {
                if (e.Separator) { items.Add(new KeyValuePair<string, Action>("", null)); continue; }
                var entry = e;
                items.Add(new KeyValuePair<string, Action>(entry.Label, () => RunItemAction(entry.Action, r)));
            }
            if (items.Count > 0) ShowMenu(at, items);
        }

        void RunItemAction(ItemAction a, ItemRef r)
        {
            var s = session;
            var u = Utils;
            if (s == null || r.Item == null) return;
            switch (a)
            {
                case ItemAction.Look: s.Look(r); break;
                case ItemAction.Use: case ItemAction.Open: s.UseItem(r.Pos, r.Id, r.Stack, ItemSlots.FreeContainerId(this)); break;
                case ItemAction.UseWith: Crosshair.Start(CrosshairState.Kind.UseWith, r); break;
                case ItemAction.Rotate: s.Rotate(r); break;
                case ItemAction.AddToHotbar: AddToHotbar(r); break;
                case ItemAction.Trade: Crosshair.Start(CrosshairState.Kind.Trade, r); break;
                case ItemAction.WhereToFind: u?.Finder.WhereToFind(r.Id); break;
                case ItemAction.LootAdd: u?.AutoLoot.AddItem(r.Id); break;
                case ItemAction.LootRemove: u?.AutoLoot.RemoveItem(r.Id); break;
                case ItemAction.PouchSettings: u?.Pouches.Open(); break;
                case ItemAction.Transmog: s.Transmog.Show(); break;
                case ItemAction.Lock: s.Crafting.LockAt(r.Pos, r.Id, true); break;
                case ItemAction.Unlock: s.Crafting.LockAt(r.Pos, r.Id, false); break;
            }
        }

        // ------------------------------------------------------------------------------------ look preview
        /// <summary>Other windows (Outfit, Cosmetics, Store) show a look on your character: the panel opens and draws the option; null shows the character as worn.</summary>
        public void ShowLookPreview(PreviewOption option)
        {
            var w = FindWindow<LookPreviewWindow>();
            if (w == null) return;
            w.Option = option;
            w.Open = true;
        }

        // ------------------------------------------------------------------------------------ the crosshair hint
        void PlayGui(float w, float h, float scale)
        {
            if (!Crosshair.Active || Event.current.type != EventType.Repaint) return;
            if (crossStyle == null) crossStyle = new GUIStyle(small) { fontSize = 12, wordWrap = false };
            string text = Crosshair.Mode == CrosshairState.Kind.Trade ? Loc.T("Trade with ...: click a player. Right click or Esc cancels.") : Loc.T("Use with ...: click a target. Right click or Esc cancels.");
            Vector2 m = MouseUi();
            var r = new Rect(Mathf.Min(m.x + 16, w - 330), Mathf.Min(m.y + 16, h - 28), 320, 22);
            Fill(r, new Color(0.05f, 0.04f, 0.06f, 0.92f));
            GUI.Label(new Rect(r.x + 6, r.y + 1, r.width - 8, 20), text, crossStyle);
        }
    }
}
