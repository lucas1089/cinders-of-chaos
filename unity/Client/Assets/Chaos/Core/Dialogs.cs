// Base 10.98 dialogs the server opens: the outfit window (0xC8 in, 0xD2 request, 0xD3 set outfit, 0xD4 toggle mount), the modal window
// (0xFA in, 0xF9 answer) and the text window of books and signs (0x96 in, 0x89 write; house window 0x97 in, 0x8D out).
// Layouts: TFS 1.4.2 protocolgame.cpp (sendOutfitWindow, sendModalWindow, sendTextWindow, sendHouseWindow and the parse* functions),
// with the item attributes of src-patch 0003 after every item of the text window (feature 126). Pure C#.
//
// Outfit window (server -> client 0xC8):
//   outfit    the current look: u16 lookType, u8 head body legs feet addons (lookType 0: u16 item id), u16 mount; on an Identity.Chaos
//             connection also u16 wings, u16 aura, string shader (the same as every creature outfit, GameParser.ReadOutfit)
//   outfits   u8 count, each u16 lookType, string name, u8 addons (bit 1 first addon, bit 2 second)
//   mounts    u8 count, each u16 client id, string name
//   Chaos     (only with the markers, features GameWingsAndAura / GameOutfitShaders of the OTCv8 protocol) u8 count of wings, each id
//             and string name; the same for auras; u8 count of shaders, each id and string name. The width of the ids is not in this
//             repo (the base server tree is not committed): OTCv8 sends u16 for wings and auras and a byte for a shader (the server
//             keeps shader ids in 19..255), so those are tried first and the other width is the fallback (ReadNamed).
// Set outfit (client -> server 0xD3): u16 lookType, u8 head body legs feet addons, u16 mount, and with the markers u16 wings, u16 aura,
// string shader (the server refuses the whole change for a shader the character does not own).
using System;
using System.Collections.Generic;

namespace Chaos.Core
{
    public sealed class OutfitChoice
    {
        public int LookType, Addons;
        public string Name = "";
    }

    public sealed class NamedId
    {
        public int Id;
        public string Name = "";
    }

    public sealed class OutfitWindowState
    {
        public const byte RequestOpcode = 0xD2, SetOpcode = 0xD3, ToggleMountOpcode = 0xD4, WindowOpcode = 0xC8;

        public bool Open;
        public Outfit Current = new Outfit();
        public readonly List<OutfitChoice> Outfits = new List<OutfitChoice>();
        public readonly List<NamedId> Mounts = new List<NamedId>(), Wings = new List<NamedId>(), Auras = new List<NamedId>(), Shaders = new List<NamedId>();
        /// <summary>The window came with the Chaos lists (wings, auras, shaders).</summary>
        public bool HasExtras;
        public int Opens;
        public Action<byte[]> Send = delegate { };

        public static byte[] RequestPacket() => new byte[] { RequestOpcode };
        public static byte[] ToggleMountPacket(bool on) => new byte[] { ToggleMountOpcode, (byte)(on ? 1 : 0) };

        /// <summary>0xD3 for a look. markers: add wings, aura and shader (an Identity.Chaos connection).</summary>
        public static byte[] SetPacket(Outfit o, bool markers)
        {
            var w = new ByteWriter().U8(SetOpcode).U16((ushort)o.LookType).U8((byte)o.Head).U8((byte)o.Body).U8((byte)o.Legs).U8((byte)o.Feet)
                .U8((byte)o.Addons).U16((ushort)o.Mount);
            if (markers) w.U16((ushort)o.Wings).U16((ushort)o.Aura).Str(o.Shader ?? "");
            return w.ToArray();
        }

        public void Request() { Send(RequestPacket()); }
        public void Apply(Outfit o, bool markers) { Send(SetPacket(o, markers)); Open = false; }
        public void Close() { Open = false; }

        /// <summary>Reads the body of a 0xC8 message (after the opcode). readOutfit is the parser's outfit reader.</summary>
        public void Read(ByteReader r, Func<ByteReader, Outfit> readOutfit, bool markers)
        {
            Current = readOutfit(r);
            Outfits.Clear(); Mounts.Clear(); Wings.Clear(); Auras.Clear(); Shaders.Clear();
            for (int n = r.U8(), i = 0; i < n; i++)
                Outfits.Add(new OutfitChoice { LookType = r.U16(), Name = r.Str(), Addons = r.U8() });
            for (int n = r.U8(), i = 0; i < n; i++)
                Mounts.Add(new NamedId { Id = r.U16(), Name = r.Str() });
            HasExtras = markers;
            if (markers)
            {
                ReadNamed(r, Wings, true);
                ReadNamed(r, Auras, true);
                ReadNamed(r, Shaders, false);
            }
            Open = true;
            Opens++;
        }

        /// <summary>u8 count then (id, name) pairs. preferWide: u16 ids first, else a byte id first; when the first width does not read
        /// sensible names the other one is used.</summary>
        static void ReadNamed(ByteReader r, List<NamedId> into, bool preferWide)
        {
            int start = r.Pos;
            for (int attempt = 0; attempt < 2; attempt++)
            {
                bool wide = attempt == 0 ? preferWide : !preferWide;
                r.Pos = start;
                into.Clear();
                try
                {
                    int n = r.U8();
                    bool ok = true;
                    for (int i = 0; i < n && ok; i++)
                    {
                        int id = wide ? r.U16() : r.U8();
                        string name = r.Str();
                        ok = Sensible(name);
                        into.Add(new NamedId { Id = id, Name = name });
                    }
                    if (ok) return;
                }
                catch (ProtocolException) { }
            }
            // neither width reads: no list, and the rest of the packet cannot be trusted
            r.Pos = start;
            into.Clear();
            throw new ProtocolException("outfit window: the wings, auras or shaders list does not read");
        }

        static bool Sensible(string name)
        {
            if (name.Length == 0 || name.Length > 64) return false;
            foreach (char c in name) if (c < 32 || c == 127) return false;
            return true;
        }

        public NamedId FindOutfit(int lookType)
        {
            foreach (var o in Outfits) if (o.LookType == lookType) return new NamedId { Id = o.LookType, Name = o.Name };
            return null;
        }

        /// <summary>The addons of an outfit the character may wear (0 when the look is not in the list).</summary>
        public int AddonsOf(int lookType)
        {
            foreach (var o in Outfits) if (o.LookType == lookType) return o.Addons;
            return 0;
        }

        /// <summary>The look with a new look type: addons the new look does not allow are cleared.</summary>
        public Outfit WithLook(Outfit o, int lookType)
        {
            var n = Copy(o);
            n.LookType = lookType; n.LookTypeEx = 0;
            n.Addons &= AddonsOf(lookType);
            return n;
        }

        public static Outfit Copy(Outfit o) => new Outfit(o.LookType, o.Head, o.Body, o.Legs, o.Feet, o.Addons, o.Mount)
        { LookTypeEx = o.LookTypeEx, Wings = o.Wings, Aura = o.Aura, Shader = o.Shader };
    }

    // ---------------------------------------------------------------------------------------------------- modal windows
    public sealed class ModalButton { public string Text = ""; public int Id; }

    public sealed class ModalWindowData
    {
        public uint Id;
        public string Title = "", Message = "";
        public readonly List<ModalButton> Buttons = new List<ModalButton>(), Choices = new List<ModalButton>();
        public int EscapeButton, EnterButton;
        public bool Priority;
    }

    /// <summary>The modal windows of 0xFA, in the order they arrived; the first is on screen.</summary>
    public sealed class ModalWindows
    {
        public const byte WindowOpcode = 0xFA, AnswerOpcode = 0xF9;
        public const int NoChoice = 0xFF;
        public readonly List<ModalWindowData> Queue = new List<ModalWindowData>();
        public Action<byte[]> Send = delegate { };
        public int Received;

        public ModalWindowData Current => Queue.Count > 0 ? Queue[0] : null;

        public void Read(ByteReader r)
        {
            var m = new ModalWindowData { Id = r.U32(), Title = r.Str(), Message = r.Str() };
            for (int n = r.U8(), i = 0; i < n; i++) m.Buttons.Add(new ModalButton { Text = r.Str(), Id = r.U8() });
            for (int n = r.U8(), i = 0; i < n; i++) m.Choices.Add(new ModalButton { Text = r.Str(), Id = r.U8() });
            m.EscapeButton = r.U8();
            m.EnterButton = r.U8();
            m.Priority = r.U8() != 0;
            Received++;
            // a window with the same id replaces the old one (the server sends it again to refresh); a priority one goes first
            for (int i = 0; i < Queue.Count; i++) if (Queue[i].Id == m.Id) { Queue.RemoveAt(i); break; }
            if (m.Priority) Queue.Insert(0, m); else Queue.Add(m);
        }

        public static byte[] AnswerPacket(uint id, int button, int choice) => new ByteWriter().U8(AnswerOpcode).U32(id).U8((byte)button).U8((byte)choice).ToArray();

        /// <summary>Answers the window on screen with a button and the picked choice (NoChoice when the window lists none or none is picked).</summary>
        public bool Answer(int button, int choice)
        {
            var m = Current;
            if (m == null) return false;
            Send(AnswerPacket(m.Id, button, choice));
            Queue.RemoveAt(0);
            return true;
        }

        /// <summary>Escape: the window's default escape button, no choice.</summary>
        public bool Cancel() { var m = Current; return m != null && Answer(m.EscapeButton, NoChoice); }

        public void Clear() { Queue.Clear(); }
    }

    // ---------------------------------------------------------------------------------------------------- text windows
    public sealed class TextWindowData
    {
        public uint Id;
        public Item Item;
        public bool CanWrite;
        public int MaxLength;
        public string Text = "", Writer = "", Date = "";
        /// <summary>A house window (0x97, the door list): DoorId is the byte the answer needs.</summary>
        public bool House;
        public int DoorId;
    }

    public sealed class TextWindows
    {
        public const byte WindowOpcode = 0x96, HouseOpcode = 0x97, WriteOpcode = 0x89, HouseAnswerOpcode = 0x8D;
        public TextWindowData Current;
        public Action<byte[]> Send = delegate { };
        public int Received;

        /// <summary>0x96 body: u32 window id, the item, then for a writable text u16 max length + string, else u16 length + string (the
        /// length is only the text's size), string writer, string date. A text window is sent either as writable or read-only by the server
        /// (sendTextWindow canWrite); the wire does not say which except through the max length, which a read-only one repeats as the text
        /// length: so CanWrite is "the max length is above the text length".</summary>
        public void ReadText(ByteReader r, Func<ByteReader, Item> readItem)
        {
            var t = new TextWindowData { Id = r.U32(), Item = readItem(r) };
            t.MaxLength = r.U16();
            t.Text = r.Str();
            t.Writer = r.Str();
            t.Date = r.Str();
            t.CanWrite = t.MaxLength > t.Text.Length;
            Current = t;
            Received++;
        }

        /// <summary>0x97 body: u8 door id (0), u32 window id, string text (the door's guest list; the owner edits it).</summary>
        public void ReadHouse(ByteReader r)
        {
            Current = new TextWindowData { House = true, DoorId = r.U8(), Id = r.U32(), Text = r.Str(), CanWrite = true, MaxLength = 1024 };
            Received++;
        }

        public static byte[] WritePacket(uint id, string text) => new ByteWriter().U8(WriteOpcode).U32(id).Str(text ?? "").ToArray();
        public static byte[] HouseAnswerPacket(int doorId, uint id, string text) => new ByteWriter().U8(HouseAnswerOpcode).U8((byte)doorId).U32(id).Str(text ?? "").ToArray();

        /// <summary>Closes the window. text: what to write (null: nothing changed, the server is still told with the old text so it closes
        /// its side: a writable window that is closed unchanged sends the same text, as the main client's Ok does).</summary>
        public void Close(string text)
        {
            var t = Current;
            Current = null;
            if (t == null || !t.CanWrite || text == null) return;
            if (t.MaxLength > 0 && text.Length > t.MaxLength) text = text.Substring(0, t.MaxLength);
            Send(t.House ? HouseAnswerPacket(t.DoorId, t.Id, text) : WritePacket(t.Id, text));
        }

        public void Clear() { Current = null; }
    }
}
