// Player trade, the VIP list and the quest log (O433 phase 5, track P). Layouts of the server side are TFS 1.4.2 protocolgame.cpp (10.98):
//   0x7D own offer / 0x7E counter offer   string trader name, u8 count, count items (a container sends itself and everything inside it)
//   0x7F trade closed
//   0xD2 VIP entry   u32 guid, string name, string description, u32 icon, u8 notify, u8 status   (status 0 offline, 1 online, 2 pending)
//   0xD3 VIP status  u32 guid, u8 status
//   0xF0 quest log   u16 count, per quest: u16 id, string name, u8 completed
//   0xF1 quest line  u16 quest id, u8 count, per mission: string name, string description
// What the client sends is in PlayPackets (Play.cs). The wire is the stock one: no vip groups in 10.98. Not run against a live server.
using System;
using System.Collections.Generic;

namespace Chaos.Core
{
    // ---------------------------------------------------------------------------------------------------- player trade
    public sealed class TradeSide
    {
        public string Name = "";
        public readonly List<Item> Items = new List<Item>();
    }

    /// <summary>The trade window of a player trade: your offer (0x7D), the other player's (0x7E), accept and close. TFS has no accepted packet: the window
    /// remembers that you accepted and clears it when the other offer changes.</summary>
    public sealed class PlayerTradeState
    {
        public bool Open;
        public readonly TradeSide Own = new TradeSide(), Counter = new TradeSide();
        public bool Accepted;
        public int OfferChanges;
        public Action<byte[]> Send = delegate { };
        public Action Changed = delegate { };

        /// <summary>0x7D and 0x7E: the packet after its opcode. readItem reads one item (id first).</summary>
        public void Read(byte op, ByteReader r, Func<ByteReader, Item> readItem)
        {
            var side = op == 0x7D ? Own : Counter;
            side.Name = r.Str();
            side.Items.Clear();
            int n = r.U8();
            for (int i = 0; i < n; i++) side.Items.Add(readItem(r));
            Open = true;
            if (op == 0x7E) { Accepted = false; OfferChanges++; }
            Changed();
        }

        public void Closed()
        {
            Open = false; Accepted = false; OfferChanges = 0;
            Own.Items.Clear(); Counter.Items.Clear(); Own.Name = ""; Counter.Name = "";
            Changed();
        }

        /// <summary>Accept: sends 0x7F once; false when there is nothing to accept or it was accepted already.</summary>
        public bool Accept()
        {
            if (!Open || Accepted || Own.Items.Count == 0 || Counter.Items.Count == 0) return false;
            Accepted = true;
            Send(PlayPackets.TradeAccept());
            Changed();
            return true;
        }

        /// <summary>Reject or close the window: sends 0x80 and closes it here.</summary>
        public void Close()
        {
            if (Open) Send(PlayPackets.TradeClose());
            Closed();
        }

        /// <summary>Look at one traded item (0x7E: which side, which index).</summary>
        public bool LookAt(bool counter, int index)
        {
            var side = counter ? Counter : Own;
            if (!Open || index < 0 || index >= side.Items.Count || index > 255) return false;
            Send(PlayPackets.TradeLookIn(counter, (byte)index));
            return true;
        }

        /// <summary>The line over a side: the name and how many items.</summary>
        public static string Header(TradeSide s, bool own) => own ? Loc.T("Your offer") : Loc.T("{0}'s offer", string.IsNullOrEmpty(s.Name) ? "?" : s.Name);
    }

    // ---------------------------------------------------------------------------------------------------- VIP list
    public sealed class VipEntry
    {
        public uint Guid;
        public string Name = "", Description = "";
        public int Icon;
        public bool Notify;
        /// <summary>0 offline, 1 online, 2 pending (the player is not in the world yet).</summary>
        public int Status;
        public bool Online => Status == 1;
    }

    public sealed class VipState
    {
        /// <summary>The icons the entry editor offers (0 is none); the server clamps the icon to 10.</summary>
        public const int MaxIcon = 10, MaxName = 29, MaxDescription = 128;
        readonly Dictionary<uint, VipEntry> entries = new Dictionary<uint, VipEntry>();
        public Action<byte[]> Send = delegate { };
        public Action Changed = delegate { };

        public int Count => entries.Count;
        public bool Has(uint guid) => entries.ContainsKey(guid);
        public VipEntry Get(uint guid) { entries.TryGetValue(guid, out var e); return e; }

        public void ReadEntry(ByteReader r)
        {
            var e = new VipEntry { Guid = r.U32(), Name = r.Str(), Description = r.Str(), Icon = (int)Math.Min(MaxIcon, r.U32()), Notify = r.U8() != 0, Status = r.U8() };
            entries[e.Guid] = e;
            Changed();
        }

        public void ReadStatus(ByteReader r)
        {
            uint guid = r.U32(); int status = r.U8();
            if (entries.TryGetValue(guid, out var e)) { e.Status = status; Changed(); }
        }

        public void ReadLogout(ByteReader r)
        {
            uint guid = r.U32();
            if (entries.TryGetValue(guid, out var e)) { e.Status = 0; Changed(); }
        }

        /// <summary>The list as shown: online first, then by name (a case-blind order); pending entries last of the offline ones.</summary>
        public List<VipEntry> Sorted(string filter = null)
        {
            var o = new List<VipEntry>();
            foreach (var e in entries.Values)
                if (string.IsNullOrEmpty(filter) || e.Name.IndexOf(filter, StringComparison.OrdinalIgnoreCase) >= 0) o.Add(e);
            o.Sort((a, b) =>
            {
                int ra = a.Online ? 0 : 1, rb = b.Online ? 0 : 1;
                if (ra != rb) return ra.CompareTo(rb);
                int c = string.Compare(a.Name, b.Name, StringComparison.OrdinalIgnoreCase);
                return c != 0 ? c : a.Guid.CompareTo(b.Guid);
            });
            return o;
        }

        public int OnlineCount() { int n = 0; foreach (var e in entries.Values) if (e.Online) n++; return n; }

        /// <summary>The text of the add box: a name of 2 to 29 letters, spaces, apostrophes and hyphens; not already on the list. Returns the reason for a no, "" for a yes.</summary>
        public string CheckName(string name)
        {
            name = (name ?? "").Trim();
            if (name.Length < 2) return Loc.T("Type the name of a player.");
            if (name.Length > MaxName) return Loc.T("The name is too long.");
            foreach (char c in name) if (!(char.IsLetter(c) || c == ' ' || c == '\'' || c == '-')) return Loc.T("A name has letters only.");
            foreach (var e in entries.Values) if (string.Equals(e.Name, name, StringComparison.OrdinalIgnoreCase)) return Loc.T("{0} is on the list already.", e.Name);
            return "";
        }

        public bool Add(string name)
        {
            if (CheckName(name).Length > 0) return false;
            Send(PlayPackets.VipAdd(name.Trim()));
            return true;
        }

        public bool Remove(uint guid)
        {
            if (!entries.Remove(guid)) return false;
            Send(PlayPackets.VipRemove(guid));
            Changed();
            return true;
        }

        public bool Edit(uint guid, string description, int icon, bool notify)
        {
            if (!entries.TryGetValue(guid, out var e)) return false;
            description = (description ?? "").Trim();
            if (description.Length > MaxDescription) description = description.Substring(0, MaxDescription);
            icon = Math.Max(0, Math.Min(MaxIcon, icon));
            e.Description = description; e.Icon = icon; e.Notify = notify;
            Send(PlayPackets.VipEdit(guid, description, (uint)icon, notify));
            Changed();
            return true;
        }

        public void Clear() { entries.Clear(); Changed(); }
    }

    // ---------------------------------------------------------------------------------------------------- quest log
    public sealed class QuestEntry
    {
        public ushort Id;
        public string Name = "";
        public bool Completed;
    }

    public sealed class QuestMission
    {
        public string Name = "", Description = "";
    }

    public sealed class QuestLogState
    {
        public readonly List<QuestEntry> Quests = new List<QuestEntry>();
        public readonly Dictionary<ushort, List<QuestMission>> Lines = new Dictionary<ushort, List<QuestMission>>();
        public bool Loaded;
        public int Selected = -1;
        public bool HideCompleted;
        public Action<byte[]> Send = delegate { };
        public Action Changed = delegate { };

        public void ReadLog(ByteReader r)
        {
            Quests.Clear();
            for (int n = r.U16(), i = 0; i < n; i++) Quests.Add(new QuestEntry { Id = r.U16(), Name = r.Str(), Completed = r.U8() != 0 });
            Loaded = true;
            if (Selected >= 0 && !Quests.Exists(q => q.Id == Selected)) Selected = -1;
            Changed();
        }

        public void ReadLine(ByteReader r)
        {
            ushort id = r.U16();
            var l = new List<QuestMission>();
            for (int n = r.U8(), i = 0; i < n; i++) l.Add(new QuestMission { Name = r.Str(), Description = r.Str() });
            Lines[id] = l;
            Changed();
        }

        public void Request() { Send(PlayPackets.QuestLog()); }

        /// <summary>Picks a quest and asks its mission lines (every pick asks again: the server's text follows the player's progress).</summary>
        public void Select(ushort id)
        {
            Selected = id;
            Send(PlayPackets.QuestLine(id));
            Changed();
        }

        public List<QuestEntry> Visible()
        {
            var o = new List<QuestEntry>();
            foreach (var q in Quests) if (!HideCompleted || !q.Completed) o.Add(q);
            return o;
        }

        public List<QuestMission> Missions(ushort id) => Lines.TryGetValue(id, out var l) ? l : null;
        public int Done() { int n = 0; foreach (var q in Quests) if (q.Completed) n++; return n; }
        public string Summary() => Loc.T("{0} of {1} quests done", Done(), Quests.Count);
    }
}
