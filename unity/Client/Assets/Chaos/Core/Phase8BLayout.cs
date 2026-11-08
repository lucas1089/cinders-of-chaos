// Phase 8, track B: game_chaoslayout, the open containers (client/overlay/modules/game_chaoslayout/containers_logic.lua, O412). A container window is remembered by where its container
// item sits, not by the server's container id (new at every login): a key is the steps from an inventory slot, "3_2854/1_1987/0_1991" (the backpack slot's container, its 2nd item, that
// one's 1st). The open ones are saved per character and opened again after the login, each after its parent. Pure logic, no UnityEngine. Tests: Core.Tests/Phase8BTests.cs.
using System;
using System.Collections.Generic;
using System.Globalization;

namespace Chaos.Core
{
    /// <summary>One remembered container: its key and how far its list was scrolled (in slot rows).</summary>
    public sealed class ContainerEntry { public string Key = ""; public int Scroll; }

    public static class ContainerKeys
    {
        public const int Max = 16, MaxDepth = 8, MaxSlot = 11;
        public const double GapMs = 150, WaitMs = 2000, PendingMs = 3000;

        public struct Step { public int I, Id; }

        public static string KeyOf(IList<Step> steps)
        {
            if (steps == null || steps.Count == 0 || steps.Count > MaxDepth) return null;
            var parts = new List<string>();
            for (int k = 0; k < steps.Count; k++)
            {
                var s = steps[k];
                if (s.Id <= 0 || s.I < 0) return null;
                if (k == 0 && (s.I < 1 || s.I > MaxSlot)) return null;
                parts.Add(s.I.ToString(CultureInfo.InvariantCulture) + "_" + s.Id.ToString(CultureInfo.InvariantCulture));
            }
            return string.Join("/", parts);
        }

        public static List<Step> Parse(string key)
        {
            if (string.IsNullOrEmpty(key)) return null;
            var steps = new List<Step>();
            foreach (string part in key.Split('/'))
            {
                int us = part.IndexOf('_');
                if (us <= 0 || !int.TryParse(part.Substring(0, us), NumberStyles.None, CultureInfo.InvariantCulture, out int i) || !int.TryParse(part.Substring(us + 1), NumberStyles.None, CultureInfo.InvariantCulture, out int id)) return null;
                steps.Add(new Step { I = i, Id = id });
            }
            return KeyOf(steps) == key ? steps : null;
        }

        public static int Depth(string key) { var s = Parse(key); return s == null ? 0 : s.Count; }

        public static string ParentKey(string key)
        {
            var s = Parse(key);
            if (s == null || s.Count < 2) return null;
            s.RemoveAt(s.Count - 1);
            return KeyOf(s);
        }

        /// <summary>The key of a container item the player opens, from the item's position: an inventory slot (x 65535, y the slot) or a slot of an open container (x 65535, y 64 + container id,
        /// z the index) whose key is known. null otherwise (the map, a corpse, a container not seen open).</summary>
        public static string FromPosition(Pos pos, int itemId, Func<int, string> keyOfContainer)
        {
            if (pos.X != 65535) return null;
            if (pos.Y >= 64)
            {
                string parent = keyOfContainer != null ? keyOfContainer(pos.Y - 64) : null;
                if (parent == null || pos.Z < 0) return null;
                var steps = Parse(parent);
                if (steps == null) return null;
                steps.Add(new Step { I = pos.Z, Id = itemId });
                return KeyOf(steps);
            }
            return KeyOf(new List<Step> { new Step { I = pos.Y, Id = itemId } });
        }

        /// <summary>The saved entries, cleaned: a valid key each, one per key, at most Max.</summary>
        public static List<ContainerEntry> Entries(IEnumerable<ContainerEntry> list)
        {
            var o = new List<ContainerEntry>();
            var seen = new HashSet<string>();
            if (list == null) return o;
            foreach (var e in list)
                if (e != null && Parse(e.Key) != null && seen.Add(e.Key) && o.Count < Max) o.Add(e);
            return o;
        }

        public struct Plan { public string Key; public bool Transient; }

        /// <summary>What to open at the restore, in order: the saved containers not open now, each after its parent. A parent that is neither open nor saved is opened too (the server needs it
        /// open to reach the child) and closed again at the end (transient).</summary>
        public static List<Plan> PlanOf(IEnumerable<ContainerEntry> saved, ICollection<string> open)
        {
            var entries = Entries(saved);
            var want = new Dictionary<string, int>();
            for (int n = 0; n < entries.Count; n++) want[entries[n].Key] = n;
            var items = new List<KeyValuePair<Plan, int>>();
            var added = new HashSet<string>();
            Action<string, bool, int> add = null;
            add = (key, transient, rank) =>
            {
                if (added.Contains(key) || (open != null && open.Contains(key))) return;
                string parent = ParentKey(key);
                if (parent != null) add(parent, !want.ContainsKey(parent), rank);
                added.Add(key);
                items.Add(new KeyValuePair<Plan, int>(new Plan { Key = key, Transient = transient }, rank));
            };
            foreach (var e in entries) add(e.Key, false, want[e.Key]);
            items.Sort((a, b) =>
            {
                int da = Depth(a.Key.Key), db = Depth(b.Key.Key);
                if (da != db) return da.CompareTo(db);
                if (a.Value != b.Value) return a.Value.CompareTo(b.Value);
                return string.CompareOrdinal(a.Key.Key, b.Key.Key);
            });
            var o = new List<Plan>();
            foreach (var it in items) o.Add(it.Key);
            return o;
        }

        public struct Slot { public int Index, Id; public bool Container; }

        /// <summary>Which item of the parent to open for a step: the item at the saved index when it is still that container, else the first container of that id not taken by another step. -1 none.</summary>
        public static int Resolve(IList<Slot> items, Step step, ICollection<int> used)
        {
            if (items == null) return -1;
            foreach (var it in items) if (it.Index == step.I && it.Id == step.Id && it.Container && (used == null || !used.Contains(it.Index))) return it.Index;
            foreach (var it in items) if (it.Id == step.Id && it.Container && (used == null || !used.Contains(it.Index))) return it.Index;
            return -1;
        }
    }

    /// <summary>Which open container is which key, and the save of it. An open the client asked for is noted as pending (the item used, its key); the window that opens within PendingMs takes the
    /// oldest pending one of its item id. Keys of the windows open now, in container id order, are what is saved per character.</summary>
    public sealed class ContainerMemory
    {
        public const string Pref = "chaos.containers.";
        public static string PrefKey(string character) => string.IsNullOrEmpty(character) ? null : Pref + character.ToLowerInvariant();

        sealed class Pending { public string Key; public int ItemId; public double At; }
        readonly List<Pending> pending = new List<Pending>();
        readonly Dictionary<int, string> keyOfCid = new Dictionary<int, string>();
        readonly Dictionary<int, int> scrollOfCid = new Dictionary<int, int>();
        public bool Dirty;
        /// <summary>The option "Remember open backpacks" (on unless turned off).</summary>
        public bool Enabled = true;

        public string KeyOfContainer(int cid) { keyOfCid.TryGetValue(cid, out string k); return k; }
        public bool Known(int cid) => keyOfCid.ContainsKey(cid);
        public int CidOf(string key) { foreach (var kv in keyOfCid) if (kv.Value == key) return kv.Key; return -1; }
        public ICollection<string> OpenKeys() => new List<string>(keyOfCid.Values);

        /// <summary>The player used an item at a position: if it can open a container it is a pending open.</summary>
        public void NoteUse(Pos pos, int itemId, double now)
        {
            string key = ContainerKeys.FromPosition(pos, itemId, KeyOfContainer);
            if (key == null) return;
            pending.RemoveAll(p => now - p.At > ContainerKeys.PendingMs || p.Key == key);
            pending.Add(new Pending { Key = key, ItemId = itemId, At = now });
        }

        /// <summary>A container window opened: it takes the oldest pending open of its item id still in time. Returns its key, null for one this client cannot name.</summary>
        public string Opened(int cid, int itemId, double now)
        {
            pending.RemoveAll(p => now - p.At > ContainerKeys.PendingMs);
            string key = null;
            for (int i = 0; i < pending.Count; i++)
                if (pending[i].ItemId == itemId) { key = pending[i].Key; pending.RemoveAt(i); break; }
            if (key == null) { if (keyOfCid.Remove(cid)) Dirty = true; return null; }
            foreach (var old in new List<int>(keyOfCid.Keys)) if (keyOfCid[old] == key && old != cid) keyOfCid.Remove(old);
            keyOfCid[cid] = key;
            Dirty = true;
            return key;
        }

        public void Closed(int cid) { if (keyOfCid.Remove(cid)) { scrollOfCid.Remove(cid); Dirty = true; } }
        public void SetScroll(int cid, int rows) { scrollOfCid.TryGetValue(cid, out int old); if (old != rows) { scrollOfCid[cid] = rows; Dirty = true; } }
        public void Clear() { pending.Clear(); keyOfCid.Clear(); scrollOfCid.Clear(); Dirty = false; }

        /// <summary>The saved list: the keyed windows in container id order.</summary>
        public List<ContainerEntry> Snapshot()
        {
            var ids = new List<int>(keyOfCid.Keys);
            ids.Sort();
            var o = new List<ContainerEntry>();
            foreach (int id in ids) { scrollOfCid.TryGetValue(id, out int sc); o.Add(new ContainerEntry { Key = keyOfCid[id], Scroll = sc }); }
            return ContainerKeys.Entries(o);
        }

        public string ToJson()
        {
            var l = new List<object>();
            foreach (var e in Snapshot()) l.Add(new Dictionary<string, object> { { "key", e.Key }, { "scroll", e.Scroll } });
            Dirty = false;
            return Json.Serialize(new Dictionary<string, object> { { "containers", l } });
        }

        public static List<ContainerEntry> FromJson(string json)
        {
            var o = new List<ContainerEntry>();
            var d = Json.TryParse(json) as Dictionary<string, object>;
            if (d == null) return o;
            foreach (var x in Json.List(d, "containers")) o.Add(new ContainerEntry { Key = Json.Text(x, "key"), Scroll = Math.Max(0, Json.Int(x, "scroll")) });
            return ContainerKeys.Entries(o);
        }
    }

    /// <summary>The restore after a login: walks the plan, one open at a time (GapMs apart, waiting at most WaitMs for the server's window), then closes the transient parents.</summary>
    public sealed class ContainerRestore
    {
        readonly List<ContainerKeys.Plan> plan;
        int next;
        double ready, waitUntil = -1;
        string waiting;
        readonly List<string> transient = new List<string>();
        public bool Done;
        /// <summary>The count of opens sent and of the ones skipped (an item that is gone).</summary>
        public int Sent, Skipped;

        public ContainerRestore(IEnumerable<ContainerEntry> saved, ICollection<string> open, double now) { plan = ContainerKeys.PlanOf(saved, open); ready = now; Done = plan.Count == 0; }

        public int Count => plan.Count;

        /// <summary>One step. itemAt(slot) is the inventory item id there (0 none); the open step is returned through `open` as the position and the item to use, else null.
        /// keyIsOpen(key) tells whether that container's window is open; cidOf(key) its container id; childrenOf(cid) its visible slots. closeCid is set when a transient parent is to be closed.</summary>
        public bool Step(double now, Func<int, int> itemAt, Func<string, bool> keyIsOpen, Func<string, int> cidOf, Func<int, IList<ContainerKeys.Slot>> childrenOf,
            out Pos usePos, out int useId, out int useStack, out int closeCid)
        {
            usePos = default(Pos); useId = 0; useStack = 0; closeCid = -1;
            if (Done || now < ready) return false;
            if (waiting != null)
            {
                if (keyIsOpen(waiting) || now >= waitUntil) { waiting = null; ready = now + ContainerKeys.GapMs; }
                return false;
            }
            if (next >= plan.Count)
            {
                if (transient.Count > 0)
                {
                    string t = transient[transient.Count - 1];
                    transient.RemoveAt(transient.Count - 1);
                    int cid = cidOf(t);
                    if (cid >= 0) { closeCid = cid; ready = now + ContainerKeys.GapMs; return true; }
                    return false;
                }
                Done = true; return false;
            }
            var p = plan[next++];
            if (keyIsOpen(p.Key)) return false;
            var steps = ContainerKeys.Parse(p.Key);
            var last = steps[steps.Count - 1];
            if (steps.Count == 1)
            {
                if (itemAt(last.I) != last.Id) { Skipped++; return false; }
                usePos = new Pos(65535, last.I, 0); useId = last.Id; useStack = last.I;
            }
            else
            {
                int cid = cidOf(ContainerKeys.ParentKey(p.Key));
                if (cid < 0) { Skipped++; return false; }
                var slots = childrenOf(cid);
                int index = ContainerKeys.Resolve(slots, last, null);
                if (index < 0) { Skipped++; return false; }
                usePos = new Pos(65535, 64 + cid, index); useId = last.Id; useStack = index;
            }
            if (p.Transient) transient.Add(p.Key);
            waiting = p.Key; waitUntil = now + ContainerKeys.WaitMs;
            Sent++;
            return true;
        }
    }
}
