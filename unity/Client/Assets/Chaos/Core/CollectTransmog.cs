// Transmog (client game_transmog, extended opcode 212, server transmog). Change how an equipped item looks.
//   client -> server  open | looks {kind} | apply {slot, look} | remove {slot}
//   server -> client  state {slots [{slot, name, item {id, cid, name, kind, kindName, applyFee, removeFee, look {id, cid, name}}}], kinds [{key, name, unlocked, total}],
//                     sets [{name, desc, owned, how, source, looks [{cid, name}]}], total {unlocked, total}, money, open}
//                     looks {kind, rows [{id, cid, name, set}]}   | result {ok, text}
using System;
using System.Collections.Generic;
using System.Linq;

namespace Chaos.Core
{
    public sealed class TransmogDetail { public bool Apply, Remove; public string Fee = "", Hint = ""; }

    public sealed class TransmogState : CollectModel
    {
        public const byte OpcodeId = 212;
        public static readonly Dictionary<string, string> SourceColors = new Dictionary<string, string>
        { { "store", "#e8b84a" }, { "achievement", "#5cc8c0" }, { "season", "#c06cff" }, { "exclusive", "#ff7a5c" } };

        public object State;
        public int SelectedSlot;
        public bool HasSlot;
        public Dictionary<string, object> SelectedLook;
        public readonly Dictionary<string, List<Dictionary<string, object>>> LooksByKind = new Dictionary<string, List<Dictionary<string, object>>>();
        readonly HashSet<string> requested = new HashSet<string>();
        public string Page = "wardrobe", Search = "", StatusText = "";
        public bool StatusOk = true, Visible;

        public TransmogState(ExtOpcodes e) : base(e, OpcodeId) { }

        public void Show() { Visible = true; Send("open"); }
        public void Hide() { Visible = false; SelectedLook = null; }
        public void Toggle() { if (Visible) Hide(); else Show(); }

        public override void Handle(string action, object data)
        {
            switch (action)
            {
                case "state":
                    State = data;
                    LooksByKind.Clear(); requested.Clear();
                    if (SelectedLook != null) { var row = SelectedRow(); if (row == null || CF.G(row, "item") == null) SelectedLook = null; }
                    PickSlot();
                    if (CF.B(data, "open")) Visible = true;
                    break;
                case "looks":
                    if (CF.G(data, "kind") is string kind) LooksByKind[kind] = CF.Rows(CF.G(data, "rows"));
                    break;
                case "result":
                    StatusText = CF.T(data, "text"); StatusOk = CF.B(data, "ok");
                    if (StatusOk) SelectedLook = null;
                    break;
            }
        }

        public void Clear() { State = null; SelectedLook = null; LooksByKind.Clear(); requested.Clear(); Visible = false; HasSlot = false; }

        public List<Dictionary<string, object>> Slots => CF.Rows(CF.G(State, "slots"));

        public Dictionary<string, object> SelectedRow() => HasSlot ? SlotRow(Slots, SelectedSlot) : null;
        public Dictionary<string, object> SelectedItem() => SelectedRow() == null ? null : CF.G(SelectedRow(), "item") as Dictionary<string, object>;

        public void SelectSlot(int slot) { if (!HasSlot || slot != SelectedSlot) { SelectedSlot = slot; HasSlot = true; SelectedLook = null; } }

        void PickSlot() { var p = PickSlotOf(Slots, HasSlot ? SelectedSlot : -1); HasSlot = p >= 0; if (HasSlot) SelectedSlot = p; }

        /// <summary>The kind of the selected item, asks the server for its looks once.</summary>
        public string KindOfSelected() => CF.T(SelectedItem(), "kind");

        public List<Dictionary<string, object>> Looks()
        {
            string kind = KindOfSelected();
            if (kind.Length == 0) return null;
            if (!LooksByKind.TryGetValue(kind, out var rows))
            {
                if (requested.Add(kind)) Send("looks", D("kind", kind));
                return null;
            }
            return Filter(rows, Search);
        }

        public void Select(Dictionary<string, object> look) { SelectedLook = look; }

        public bool ApplySelected()
        {
            var row = SelectedRow();
            if (row == null || CF.G(row, "item") == null || SelectedLook == null) return false;
            return Send("apply", D("slot", CF.G(row, "slot"), "look", CF.G(SelectedLook, "id")));
        }

        public bool RemoveSelected()
        {
            var row = SelectedRow();
            if (row == null || CF.G(row, "item") == null) return false;
            return Send("remove", D("slot", CF.G(row, "slot")));
        }

        public TransmogDetail Detail() => DetailOf(SelectedRow(), SelectedLook, CF.N(State, "money"));

        // ---------------------------------------------------------------------------------------------- the view rules
        public static string ProgressText(object unlocked, object total)
        {
            double u = CF.Num(unlocked), t = CF.Num(total);
            return string.Format("{0} / {1} ({2}%)", (long)u, (long)t, t > 0 ? (long)Math.Floor(u * 100 / t) : 0);
        }

        public static double Percent(object unlocked, object total)
        {
            double u = CF.Num(unlocked), t = CF.Num(total);
            return t <= 0 ? 0 : Math.Max(0, Math.Min(100, u * 100 / t));
        }

        public static string Gold(object n) => CF.Group(CF.Num(n));

        public static string SlotSub(Dictionary<string, object> row)
        {
            var item = CF.G(row, "item") as Dictionary<string, object>;
            if (item == null) return Loc.T("Empty");
            if (CF.G(item, "kind") == null) return Loc.T("Cannot change its look");
            if (CF.G(item, "look") is Dictionary<string, object> look) return Loc.T("Look: {0}", CF.T(look, "name"));
            return Loc.T("{0}, own look", CF.T(item, "kindName", CF.T(item, "kind")));
        }

        /// <summary>The slot to select: the wanted one when it holds an item, else the first changeable one, -1 for none.</summary>
        public static int PickSlotOf(IEnumerable<Dictionary<string, object>> slots, int wanted)
        {
            int first = -1;
            foreach (var s in slots)
            {
                var item = CF.G(s, "item") as Dictionary<string, object>;
                if (CF.I(s, "slot") == wanted && item != null) return wanted;
                if (first < 0 && item != null && CF.G(item, "kind") != null) first = CF.I(s, "slot");
            }
            return first;
        }

        public static Dictionary<string, object> SlotRow(IEnumerable<Dictionary<string, object>> slots, int slot) => slots.FirstOrDefault(s => CF.I(s, "slot") == slot);

        public static List<Dictionary<string, object>> Filter(List<Dictionary<string, object>> rows, string text)
        {
            text = (text ?? "").Trim().ToLowerInvariant();
            if (text.Length == 0) return rows;
            return rows.Where(r => CF.T(r, "name").ToLowerInvariant().Contains(text)).ToList();
        }

        public static TransmogDetail DetailOf(Dictionary<string, object> row, Dictionary<string, object> look, double money)
        {
            var d = new TransmogDetail();
            var item = row == null ? null : CF.G(row, "item") as Dictionary<string, object>;
            if (item == null) { d.Hint = Loc.T("Equip an item in this slot to change its look."); return d; }
            if (CF.G(item, "kind") == null) { d.Hint = Loc.T("This item cannot change its look."); return d; }
            double applyFee = CF.N(item, "applyFee");
            d.Fee = Loc.T("Fee: {0} gold", Gold(applyFee));
            var cur = CF.G(item, "look") as Dictionary<string, object>;
            if (cur != null)
            {
                d.Remove = true;
                double removeFee = CF.N(item, "removeFee");
                d.Fee += removeFee > 0 ? Loc.T("  -  remove: {0} gold", Gold(removeFee)) : Loc.T("  -  remove: free");
            }
            if (look == null) d.Hint = Loc.T("Pick an appearance on the right to preview it.");
            else if (CF.Str(CF.G(look, "id")) == CF.Str(CF.G(item, "id"))) d.Hint = Loc.T("That is the item's own look.");
            else if (cur != null && CF.Str(CF.G(cur, "id")) == CF.Str(CF.G(look, "id"))) d.Hint = Loc.T("The item already has this look.");
            else if (money < applyFee) d.Hint = Loc.T("Not enough gold (backpack and bank).");
            else { d.Apply = true; d.Hint = Loc.T("Appearance only: stats and tooltip stay the item's own."); }
            return d;
        }

        public List<Dictionary<string, object>> SortedSets()
        {
            return StableSort(CF.Rows(CF.G(State, "sets")), (a, b) =>
            {
                bool oa = CF.B(a, "owned"), ob = CF.B(b, "owned");
                if (oa != ob) return oa ? -1 : 1;
                return string.CompareOrdinal(CF.T(a, "name"), CF.T(b, "name"));
            });
        }

        public static string SetLine(object set) => CF.B(set, "owned") ? Loc.T("Owned") : CF.T(set, "how");
    }
}
