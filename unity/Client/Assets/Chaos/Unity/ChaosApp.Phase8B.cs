// Phase 8, track B: the app side of the P2 gap closers (docs/UNITY_PARITY.md, unity/README.md "Phase 8, track B"). Pure logic is Core/Phase8B*.cs.
using System.Collections.Generic;
using Chaos.Core;
using UnityEngine;

namespace Chaos.Client
{
    public sealed partial class ChaosApp
    {
        readonly KeyRepeat overlayPanRepeat = new KeyRepeat();
        readonly ContainerMemory containerMem = new ContainerMemory();
        ContainerRestore containerRestore;
        GameSession containersHooked;
        string containersFor;
        double containersRestoreAt;

        /// <summary>Called every frame from VisualUpdate.</summary>
        void Phase8BUpdate()
        {
            using var _slow = SlowCalls.Scope("Phase8BUpdate", "Update");
            OverlayKeysUpdate();
            ContainerMemoryUpdate();
            var market = session?.Social?.Market;
            if (market != null && market.CodexSource == null) market.CodexSource = () => InfoStore.Codex;   // game_market: the modifier typeahead reads the Codex
        }

        /// <summary>game_chaoslayout: the open backpacks come back after a login (O412). Keys come from where the container item sits (Core/Phase8BLayout.cs); the list is saved per character in
        /// PlayerPrefs "chaos.containers.name" when it changes (never while the restore runs), and the restore opens them one at a time after the login. The option key
        /// "chaos.rememberbackpacks" (1 on, the default).</summary>
        void ContainerMemoryUpdate()
        {
            string name = screen == Screen.Game ? world?.Player?.Name : null;
            if (string.IsNullOrEmpty(name) || session == null)
            {
                if (containersFor != null) { containerMem.Clear(); containerRestore = null; containersFor = null; containersHooked = null; }
                return;
            }
            double now = session.Now;
            if (containersHooked != session)
            {
                containersHooked = session;
                var p = session.Parser;
                session.ItemUsed += (pos, id) => containerMem.NoteUse(pos, id, session.Now);
                var open = p.ContainerOpened; var closed = p.ContainerClosed;
                p.ContainerOpened = cid => { open(cid); if (p.Containers.TryGetValue(cid, out var c)) containerMem.Opened(cid, c.ItemId, session.Now); };
                p.ContainerClosed = cid => { closed(cid); containerMem.Closed(cid); };
            }
            if (containersFor != name)
            {
                containersFor = name;
                containerMem.Clear();
                string key = ContainerMemory.PrefKey(name);
                string json = ""; try { json = key != null ? PlayerPrefs.GetString(key, "") : ""; } catch (System.Exception) { }
                containerMem.Enabled = PlayerPrefs.GetInt("chaos.rememberbackpacks", 1) != 0;
                containerRestore = containerMem.Enabled ? new ContainerRestore(ContainerMemory.FromJson(json), containerMem.OpenKeys(), now) : null;
                containersRestoreAt = now + 2500;   // after the login's own packets
            }
            if (containerRestore != null && !containerRestore.Done && now >= containersRestoreAt)
            {
                var p = session.Parser;
                if (containerRestore.Step(now, slot => slot >= 1 && slot < p.Inventory.Length && p.Inventory[slot] != null ? (int)p.Inventory[slot].Id : 0,
                    key => containerMem.CidOf(key) >= 0, key => containerMem.CidOf(key),
                    cid =>
                    {
                        var list = new List<ContainerKeys.Slot>();
                        if (p.Containers.TryGetValue((byte)cid, out var c))
                            for (int i = 0; i < c.Items.Count; i++)
                            {
                                var it = c.Items[i];
                                var type = it != null && it.Type != null ? it.Type : null;
                                list.Add(new ContainerKeys.Slot { Index = c.FirstIndex + i, Id = it != null ? it.Id : 0, Container = type != null && type.Container });
                            }
                        return list;
                    }, out Pos pos, out int id, out int stack, out int closeCid))
                {
                    if (closeCid >= 0) session.CloseContainer((byte)closeCid);
                    else session.UseItem(pos, (ushort)id, (byte)stack);
                }
            }
            else if (containerMem.Dirty && containerMem.Enabled && (containerRestore == null || containerRestore.Done))
            {
                string key = ContainerMemory.PrefKey(name);
                if (key != null) { try { PlayerPrefs.SetString(key, containerMem.ToJson()); } catch (System.Exception) { } }
            }
        }

        /// <summary>game_mapoverlay: Tab toggles the overlay (not in the chat line, not with Ctrl); with it open Shift + the arrows pan it (MapOverlayState.KeyPan).</summary>
        void OverlayKeysUpdate()
        {
            var u = screen == Screen.Game ? Utils : null;
            if (u == null || session == null || world?.Player == null) { overlayPanRepeat.Reset(); return; }
            bool ctrl = Input.GetKey(KeyCode.LeftControl) || Input.GetKey(KeyCode.RightControl), shift = Input.GetKey(KeyCode.LeftShift) || Input.GetKey(KeyCode.RightShift);
            if (Input.GetKeyDown(KeyCode.Tab) && !shift && OverlayKeys.ToggleTab(chatFocused, ctrl, TextEditing)) { u.Overlay.Show(!u.Overlay.Shown); return; }
            bool pan = OverlayKeys.Pans(u.Overlay.Shown, shift, chatFocused || TextEditing);
            OverlayKeys.Dir(Input.GetKey(KeyCode.UpArrow), Input.GetKey(KeyCode.DownArrow), Input.GetKey(KeyCode.LeftArrow), Input.GetKey(KeyCode.RightArrow), out int dx, out int dy);
            if (overlayPanRepeat.Step(pan && (dx != 0 || dy != 0), Time.unscaledTimeAsDouble * 1000.0))
            {
                var o = u.Overlay;
                MapOverlayState.KeyPan(o.PanX, o.PanY, dx, dy, o.Settings.Zoom, OverlayKeys.PanPixels, out double px, out double py);
                o.PanX = px; o.PanY = py;
            }
        }
    }
}
