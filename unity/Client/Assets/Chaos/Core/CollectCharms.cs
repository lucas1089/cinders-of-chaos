// Charms (client game_charms, extended opcode 198, server charms). A grid of cells you place charms on.
//   client -> server  open | place {ref, pos?, sid, iid, x, y} | move {id, x, y} | take {id} | salvage {ref, sid, iid} | reforge {ref, sid, iid}
//   server -> client  state {cols, rows, max, shards, cells [{x, y, open, why}], placed [{id, ref, sid, iid, x, y, w, h, name, rarity, ilvl, icon, item, mods [{t}], active, color, signature}],
//                     bag [{ref, sid, iid, w, h, name, rarity, ilvl, icon, item, mods, salvage, reforge}], totals [{t, v, cap}], groups [{open, text, cells}]}
//                     result {ok, text}
using System;
using System.Globalization;
using System.Collections.Generic;
using System.Linq;

namespace Chaos.Core
{
    /// <summary>What the player is carrying while dragging a charm (kind "bag" or "placed").</summary>
    public sealed class CharmDrag
    {
        public string Kind = "bag", Ref = "", Sid = "", Iid = "";
        public int Id, W = 1, H = 1, X, Y;
    }

    public sealed class CharmPreview
    {
        public int X, Y;
        public bool Ok;
        public string Why;
        public List<int[]> Cells = new List<int[]>();
    }

    public sealed class CharmAction { public string Action = ""; public Dictionary<string, object> Data = new Dictionary<string, object>(); }

    public sealed class CharmsState : CollectModel
    {
        public const byte OpcodeId = 198;
        public const float Cell = 44f, Gap = 2f;
        public const string ColorGold = "#e8b84a", ColorText = "#d8ccb4", ColorDim = "#8c8070", ColorGood = "#8fd16a", ColorBad = "#e07060", ColorWarn = "#e0a050";

        public object State;
        public string StatusText = "", StatusColor = ColorDim;
        public string SelectedRef;
        public bool Visible;

        public CharmsState(ExtOpcodes e) : base(e, OpcodeId) { }

        public void Open() { Send("open"); }
        public void Show() { Visible = true; Send("open"); }
        public void Hide() { Visible = false; }
        public void Toggle() { if (Visible) Hide(); else Show(); }
        public void Send(CharmAction a) { if (a != null) Send(a.Action, a.Data); }

        public override void Handle(string action, object data)
        {
            if (action == "state")
            {
                State = data;
                if (BagEntry(SelectedRef) == null) SelectedRef = null;
            }
            else if (action == "result") { StatusText = CF.T(data, "text"); StatusColor = CF.B(data, "ok") ? ColorGood : ColorBad; }
        }

        public void Clear() { State = null; SelectedRef = null; Visible = false; StatusText = ""; }

        public int Cols => CF.I(State, "cols");
        public int Rows => CF.I(State, "rows");
        public List<Dictionary<string, object>> Cells => CF.Rows(CF.G(State, "cells"));
        public List<Dictionary<string, object>> Placed => CF.Rows(CF.G(State, "placed"));
        public List<Dictionary<string, object>> Bag => CF.Rows(CF.G(State, "bag"));

        public Dictionary<string, object> BagEntry(string r) => r == null ? null : Bag.FirstOrDefault(b => CF.Str(CF.G(b, "ref")) == r);
        public Dictionary<string, object> PlacedEntry(int id) => Placed.FirstOrDefault(p => CF.I(p, "id") == id);

        public bool CanSalvage => BagEntry(SelectedRef) != null;
        public bool CanReforge { get { var b = BagEntry(SelectedRef); return b != null && CF.G(b, "reforge") != null; } }

        public void SalvageSelected() { var b = BagEntry(SelectedRef); if (b != null) Send("salvage", D("ref", CF.G(b, "ref"), "sid", CF.G(b, "sid"), "iid", CF.G(b, "iid"))); }
        public void ReforgeSelected() { var b = BagEntry(SelectedRef); if (b != null) Send("reforge", D("ref", CF.G(b, "ref"), "sid", CF.G(b, "sid"), "iid", CF.G(b, "iid"))); }

        // ---------------------------------------------------------------------------------------------- the grid rules
        public static string Key(int x, int y) => x + "," + y;

        /// <summary>Grid cell (1-based) under a pixel offset of the grid panel, or false outside.</summary>
        public bool CellAt(float px, float py, out int x, out int y)
        {
            float step = Cell + Gap;
            x = (int)Math.Floor(px / step) + 1; y = (int)Math.Floor(py / step) + 1;
            return !(px < 0 || py < 0 || x > Cols || y > Rows);
        }

        /// <summary>The top-left cell of a w x h charm whose middle sits at the pixel offset.</summary>
        public bool Anchor(float px, float py, int w, int h, out int x, out int y)
        {
            x = y = 0;
            if (!CellAt(px, py, out _, out _)) return false;
            float step = Cell + Gap;
            x = (int)Math.Floor((px - (w - 1) * step / 2) / step) + 1;
            y = (int)Math.Floor((py - (h - 1) * step / 2) / step) + 1;
            return true;
        }

        /// <summary>The pixel rect of a w x h block of cells anchored at (x, y): x, y, width, height.</summary>
        public static float[] Rect(int x, int y, int w, int h)
        {
            float step = Cell + Gap;
            return new[] { (x - 1) * step, (y - 1) * step, w * step - Gap, h * step - Gap };
        }

        public static List<int[]> Footprint(int w, int h, int x, int y)
        {
            var o = new List<int[]>();
            for (int dy = 0; dy < h; dy++) for (int dx = 0; dx < w; dx++) o.Add(new[] { x + dx, y + dy });
            return o;
        }

        Dictionary<string, int> Occupancy(int ignoreId)
        {
            var occ = new Dictionary<string, int>();
            foreach (var p in Placed)
            {
                int id = CF.I(p, "id");
                if (id == ignoreId && ignoreId != 0) continue;
                foreach (var c in Footprint(CF.I(p, "w"), CF.I(p, "h"), CF.I(p, "x"), CF.I(p, "y"))) occ[Key(c[0], c[1])] = id;
            }
            return occ;
        }

        /// <summary>Whether a charm fits; why is the message when not. ignoreId is the charm being moved (0 for a new one).</summary>
        public bool Check(int w, int h, int x, int y, int ignoreId, out string why)
        {
            why = null;
            if (State == null) { why = Loc.T("Drop it on the grid."); return false; }
            var cells = new Dictionary<string, Dictionary<string, object>>();
            foreach (var c in Cells) cells[Key(CF.I(c, "x"), CF.I(c, "y"))] = c;
            var occ = Occupancy(ignoreId);
            foreach (var c in Footprint(w, h, x, y))
            {
                if (!cells.TryGetValue(Key(c[0], c[1]), out var cell)) { why = Loc.T("The charm does not fit inside the grid there."); return false; }
                if (!CF.B(cell, "open")) { why = Loc.T("That cell is locked: {0}", CF.T(cell, "why")); return false; }
                if (occ.ContainsKey(Key(c[0], c[1]))) { why = Loc.T("Another charm is in the way."); return false; }
            }
            int max = CF.G(State, "max") != null ? CF.I(State, "max") : 20;
            if (ignoreId == 0 && Placed.Count >= max) { why = Loc.T("Your charm grid is full."); return false; }
            return true;
        }

        public CharmPreview Preview(CharmDrag drag, float px, float py)
        {
            if (State == null || drag == null) return null;
            if (!Anchor(px, py, drag.W, drag.H, out int x, out int y)) return null;
            bool ok = Check(drag.W, drag.H, x, y, drag.Kind == "placed" ? drag.Id : 0, out string why);
            var p = new CharmPreview { X = x, Y = y, Ok = ok, Why = why };
            foreach (var c in Footprint(drag.W, drag.H, x, y)) if (c[0] >= 1 && c[1] >= 1 && c[0] <= Cols && c[1] <= Rows) p.Cells.Add(c);
            return p;
        }

        /// <summary>What a drop does: target "grid" (px, py in the grid) or "bag". Null with a message when it is refused.</summary>
        public CharmAction DropAction(CharmDrag drag, string target, float px, float py, out string why)
        {
            why = null;
            if (drag == null) return null;
            if (target == "bag")
                return drag.Kind == "placed" ? new CharmAction { Action = "take", Data = D("id", (double)drag.Id) } : null;
            if (target != "grid") return null;
            var p = Preview(drag, px, py);
            if (p == null) { why = Loc.T("Drop it on the grid."); return null; }
            if (!p.Ok) { why = p.Why; return null; }
            if (drag.Kind == "placed")
            {
                if (p.X == drag.X && p.Y == drag.Y) return null;
                return new CharmAction { Action = "move", Data = D("id", (double)drag.Id, "x", (double)p.X, "y", (double)p.Y) };
            }
            return new CharmAction { Action = "place", Data = D("ref", drag.Ref, "sid", drag.Sid, "iid", drag.Iid, "x", (double)p.X, "y", (double)p.Y) };
        }

        /// <summary>An item dragged in from a bag or a container onto the grid (charms.lua onDropItem): its size is known from the list of charms you carry (same per-item id),
        /// else 1 x 1; the server gets the item's map position and per-item id and the anchor cell. Null with a message when it does not fit.</summary>
        public CharmAction ItemDropAction(Pos pos, ulong iid, float px, float py, out string why)
        {
            why = null;
            int w = 1, h = 1;
            if (iid > 0)
                foreach (var b in Bag)
                    if (CF.Str(CF.G(b, "iid")) == iid.ToString(CultureInfo.InvariantCulture)) { w = Math.Max(1, CF.I(b, "w")); h = Math.Max(1, CF.I(b, "h")); }
            if (!Anchor(px, py, w, h, out int x, out int y)) { why = Loc.T("Drop it on the grid."); return null; }
            if (!Check(w, h, x, y, 0, out string bad)) { why = bad; return null; }
            var p = new Dictionary<string, object> { { "x", (double)pos.X }, { "y", (double)pos.Y }, { "z", (double)pos.Z } };
            return new CharmAction { Action = "place", Data = D("pos", p, "iid", iid.ToString(CultureInfo.InvariantCulture), "x", (double)x, "y", (double)y) };
        }

        public static CharmDrag DragOf(Dictionary<string, object> c, string kind) => new CharmDrag
        {
            Kind = kind, Id = CF.I(c, "id"), Ref = CF.Str(CF.G(c, "ref")), Sid = CF.Str(CF.G(c, "sid")), Iid = CF.Str(CF.G(c, "iid")),
            W = Math.Max(1, CF.I(c, "w")), H = Math.Max(1, CF.I(c, "h")), X = CF.I(c, "x"), Y = CF.I(c, "y"),
        };

        public static bool Glows(object c) { string r = CF.T(c, "rarity"); return r == "Glowing" || r == "Radiant" || r == "Unique"; }

        public static string Tooltip(object c, bool placed)
        {
            if (c == null) return "";
            var lines = new List<string> { CF.T(c, "name", "Charm") };
            lines.Add(Loc.T("{0}, item level {1}, {2}x{3}", CF.T(c, "rarity", "?"), CF.I(c, "ilvl"), CF.I(c, "w"), CF.I(c, "h")));
            foreach (var m in CF.Rows(CF.G(c, "mods"))) lines.Add("  " + (CF.G(m, "t") != null ? CF.T(m, "t") : CF.Str(CF.G(m, "k")) + " " + CF.Str(CF.G(m, "v"))));
            if (CF.G(c, "signature") != null) lines.Add(CF.T(c, "signature"));
            if (placed && CF.G(c, "active") != null && !CF.B(c, "active")) lines.Add(Loc.T("Inactive: it covers a cell that is locked again."));
            if (placed) lines.Add(Loc.T("Drag it to move it; drag it onto your charms list to take it out."));
            else
            {
                lines.Add(Loc.T("Drag it onto the grid to place it."));
                var tail = new List<string>();
                if (CF.G(c, "salvage") != null) tail.Add(Loc.T("salvage: {0} shards", CF.I(c, "salvage")));
                if (CF.G(c, "reforge") != null) tail.Add(Loc.T("reforge: {0} shards", CF.I(c, "reforge")));
                if (tail.Count > 0) lines.Add(string.Join(", ", tail));
            }
            return string.Join("\n", lines);
        }

        /// <summary>The totals lines (text, capped).</summary>
        public List<KeyValuePair<string, string>> TotalsLines()
        {
            var o = new List<KeyValuePair<string, string>>();
            foreach (var r in CF.Rows(CF.G(State, "totals")))
            {
                bool capped = CF.N(r, "cap") > 0 && CF.N(r, "v") >= CF.N(r, "cap");
                o.Add(new KeyValuePair<string, string>(CF.T(r, "t") + (capped ? "  " + Loc.T("(cap)") : ""), capped ? ColorWarn : ColorText));
            }
            if (o.Count == 0) o.Add(new KeyValuePair<string, string>(Loc.T("No charm placed yet."), ColorDim));
            return o;
        }

        public List<KeyValuePair<string, string>> UnlockLines()
        {
            var o = new List<KeyValuePair<string, string>>();
            foreach (var g in CF.Rows(CF.G(State, "groups")))
            {
                bool open = CF.B(g, "open");
                o.Add(new KeyValuePair<string, string>(Loc.T("{0} {1}: {2} cells", open ? "[open]" : "[locked]", CF.T(g, "text"), CF.I(g, "cells")), open ? ColorGood : ColorDim));
            }
            return o;
        }

        public string Header()
        {
            if (State == null) return "";
            int open = Cells.Count(c => CF.B(c, "open"));
            return Loc.T("{0} of {1} cells open  -  {2} charms placed  -  {3} charm shards", open, Cols * Rows, Placed.Count, CF.I(State, "shards"));
        }
    }
}
