// Map marks, the map overlay and the minimap sync (client game_mapmarkers 153, game_mapoverlay 245, game_minimapsync).
// Pure models: no drawing. The windows and the map drawing are in Unity/ChaosApp.World.cs and Unity/Windows/WorldWindows.cs.
//
// mapmarkers (opcode 153, {action, data}):
//   client -> server  hello {party, poi, npcmarks} (at the login) | set {party | poi | npcmarks: bool} (one kind turned off stops it)
//   server -> client  party {m = [{i, n, x, y, z, p}]} | poi {marks = [{k, x, y, z, n?}]} | reveal {marks} (new ones) |
//                     quests {marks} (kind questgoal) | npcmarks {full, set = [{n, m: new|ready|locked}], clear = [name]}
// mapoverlay (opcode 245): client watch {on}; server marks {marks = [{k, x, y, z, n?}]} once a second while watching, rift {id, x1, y1, x2, y2, z}.
using System;
using System.Collections.Generic;

namespace Chaos.Core
{
    /// <summary>A point of interest or a party member shown on a map.</summary>
    public sealed class MapMark
    {
        public string Kind = "", Name = "";
        public int X, Y, Z;
        public string Key => Kind + ":" + X + ":" + Y + ":" + Z;
    }

    public sealed class PartyMark
    {
        public int Id, X, Y, Z, Percent = -1;
        public string Name = "";
    }

    /// <summary>The glide of a party pin to its new tile (the server sends about once a second).</summary>
    public sealed class MarkAnim
    {
        public double FromX, FromY, ToX, ToY, T0;
        public int ToZ;
        public bool Jump = true, HasFrom;
    }

    public sealed class MapMarkSettings
    {
        public bool Party = true, Poi = true, Game = true, NpcMarks = true;
        public readonly Dictionary<string, bool> Cats = new Dictionary<string, bool>();

        public MapMarkSettings() { foreach (var c in MapMarkMath.Categories) Cats[c] = true; }

        public bool Cat(string c) => !Cats.TryGetValue(c, out bool on) || on;
    }

    public static class MapMarkMath
    {
        public const double AnimMs = 800;
        public const int JumpTiles = 40, MaxPoi = 160;
        public static readonly string[] Categories = { "quest", "town", "npc", "shop", "craft", "guild", "portal", "dungeon", "boss", "hunt" };
        public static readonly Dictionary<string, string> CategoryLabel = new Dictionary<string, string>
        {
            { "quest", "Quests: givers and your next steps" }, { "town", "Temples, depots and banks" }, { "npc", "Chaos NPCs (services)" },
            { "shop", "Shops, travel and blessings" }, { "craft", "Crafting tables" }, { "guild", "Guild hall" },
            { "portal", "Entrances and portals" }, { "dungeon", "Dungeons" }, { "boss", "Boss places" }, { "hunt", "Hunting areas" },
        };
        public static readonly Dictionary<string, string> KindCategory = new Dictionary<string, string>
        {
            { "temple", "town" }, { "depot", "town" }, { "bank", "town" }, { "npc", "npc" }, { "shop", "shop" }, { "travel", "shop" }, { "bless", "shop" },
            { "craft", "craft" }, { "guild", "guild" }, { "portal", "portal" }, { "dungeon", "dungeon" }, { "boss", "boss" }, { "hunt", "hunt" },
            { "quest", "quest" }, { "questgoal", "quest" },
        };
        /// <summary>Party colours by slot (hex).</summary>
        public static readonly string[] Colors = { "#ff9d2e", "#5fd0ff", "#8ee05a", "#e070ff", "#ffd84a", "#ff6464", "#5fffc8", "#c8a0ff", "#ffffff", "#ff9ad0" };
        static readonly string[] Dirs = { "e", "se", "s", "sw", "w", "nw", "n", "ne" };
        static readonly Dictionary<string, string> Compass = new Dictionary<string, string>
        {
            { "n", "north" }, { "ne", "north-east" }, { "e", "east" }, { "se", "south-east" }, { "s", "south" }, { "sw", "south-west" }, { "w", "west" }, { "nw", "north-west" },
        };

        public static string Color(int slot) => Colors[(((slot < 1 ? 1 : slot) - 1) % Colors.Length + Colors.Length) % Colors.Length];

        /// <summary>Colour slots kept between updates: a leaver frees its slot, a new member takes the lowest free one.</summary>
        public static void AssignColors(Dictionary<int, int> slots, IList<int> ids)
        {
            var present = new HashSet<int>(ids);
            var used = new HashSet<int>();
            foreach (int id in new List<int>(slots.Keys))
            {
                if (present.Contains(id)) used.Add(slots[id]); else slots.Remove(id);
            }
            foreach (int id in ids)
            {
                if (slots.ContainsKey(id)) continue;
                int i = 1;
                while (used.Contains(i)) i++;
                slots[id] = i;
                used.Add(i);
            }
        }

        /// <summary>"up" when the member is on a lower z than the shown floor, "down" when higher, "" on the same floor.</summary>
        public static string FloorArrow(int memberZ, int viewZ) => memberZ < viewZ ? "up" : memberZ > viewZ ? "down" : "";

        /// <summary>One of 8 directions of a screen vector (y grows down), "" for none.</summary>
        public static string Dir8(double dx, double dy)
        {
            if (dx == 0 && dy == 0) return "";
            double a = Math.Atan2(dy, dx);
            int i = (int)Math.Floor((a + Math.PI / 8) / (Math.PI / 4));
            i = ((i % 8) + 8) % 8;
            return Dirs[i];
        }

        /// <summary>A point in a rect: inside gives true and the point; outside (nearer than the margin to the edge counts) the point on the inset rect toward it.</summary>
        public static bool Edge(double px, double py, double rx, double ry, double rw, double rh, double margin, out double x, out double y, out string dir)
        {
            double x1 = rx + margin, y1 = ry + margin, x2 = rx + rw - margin, y2 = ry + rh - margin;
            dir = "";
            if (px >= x1 && px <= x2 && py >= y1 && py <= y2) { x = px; y = py; return true; }
            double cx = rx + rw / 2, cy = ry + rh / 2, dx = px - cx, dy = py - cy;
            double hw = Math.Max(0, rw / 2 - margin), hh = Math.Max(0, rh / 2 - margin), t = 1;
            if (dx != 0) t = Math.Min(t, hw / Math.Abs(dx));
            if (dy != 0) t = Math.Min(t, hh / Math.Abs(dy));
            x = Math.Min(Math.Max(Math.Floor(cx + dx * t + 0.5), x1), x2);
            y = Math.Min(Math.Max(Math.Floor(cy + dy * t + 0.5), y1), y2);
            dir = Dir8(dx, dy);
            return false;
        }

        public static MarkAnim Retarget(MarkAnim a, int x, int y, int z, double now)
        {
            if (a != null)
            {
                Glide(a, now, out double sx, out double sy, out _);
                bool far = Math.Max(Math.Abs(x - sx), Math.Abs(y - sy)) > JumpTiles;
                if (a.ToZ != z || far) return new MarkAnim { ToX = x, ToY = y, ToZ = z, Jump = true, T0 = now };
                return new MarkAnim { FromX = sx, FromY = sy, HasFrom = true, ToX = x, ToY = y, ToZ = z, Jump = false, T0 = now };
            }
            return new MarkAnim { ToX = x, ToY = y, ToZ = z, Jump = true, T0 = now };
        }

        /// <summary>The tile position a pin shows at `now`; done is true when it arrived.</summary>
        public static void Glide(MarkAnim a, double now, out double x, out double y, out bool done)
        {
            if (!a.HasFrom || a.Jump) { x = a.ToX; y = a.ToY; done = true; return; }
            double t = (now - a.T0) / AnimMs;
            if (t >= 1) { x = a.ToX; y = a.ToY; done = true; return; }
            if (t < 0) t = 0;
            x = a.FromX + (a.ToX - a.FromX) * t; y = a.FromY + (a.ToY - a.FromY) * t; done = false;
        }

        /// <summary>Hover text of a member: name, health, floors and the distance with the compass direction.</summary>
        public static string MemberText(PartyMark e, Pos me, bool hasMe)
        {
            var parts = new List<string> { e.Name.Length > 0 ? e.Name : "?" };
            if (e.Percent >= 0) parts.Add(Loc.T("{0}% health", e.Percent));
            if (hasMe)
            {
                int dz = e.Z - me.Z;
                if (dz < 0) parts.Add(dz == -1 ? Loc.T("1 floor up") : Loc.T("{0} floors up", -dz));
                else if (dz > 0) parts.Add(dz == 1 ? Loc.T("1 floor down") : Loc.T("{0} floors down", dz));
                int dx = e.X - me.X, dy = e.Y - me.Y, d = Math.Max(Math.Abs(dx), Math.Abs(dy));
                if (d > 0) parts.Add(d + " " + (d == 1 ? "square" : "squares") + " " + Compass[Dir8(dx, dy)]);
            }
            return string.Join(", ", parts);
        }

        /// <summary>Text of the game view arrow: name, tiles, floors (+1 up, -2 down).</summary>
        public static string GameText(string name, int dist, int delta)
        {
            string s = name + " " + dist;
            if (delta != 0) s += " " + (delta < 0 ? "+" + (-delta) : "-" + delta);
            return s;
        }

        public static bool InView(int dx, int dy, int viewDx = 7, int viewDy = 5) => Math.Abs(dx) <= viewDx && Math.Abs(dy) <= viewDy;

        /// <summary>Marks by floor: unknown kinds and broken entries left out.</summary>
        public static Dictionary<int, List<MapMark>> ByFloor(IEnumerable<MapMark> marks)
        {
            var o = new Dictionary<int, List<MapMark>>();
            foreach (var m in marks)
            {
                if (m == null || !KindCategory.ContainsKey(m.Kind)) continue;
                if (!o.TryGetValue(m.Z, out var l)) o[m.Z] = l = new List<MapMark>();
                l.Add(m);
            }
            return o;
        }

        /// <summary>Marks to draw: the points of interest then the quest goals (only kind questgoal is taken from the goals).</summary>
        public static List<MapMark> WithGoals(IEnumerable<MapMark> pois, IEnumerable<MapMark> goals)
        {
            var o = new List<MapMark>(pois);
            foreach (var g in goals) if (g.Kind == "questgoal") o.Add(g);
            return o;
        }

        /// <summary>Adds a reveal to a list, one per kind and tile; returns how many were new.</summary>
        public static int AddMarks(List<MapMark> list, IEnumerable<MapMark> add)
        {
            var seen = new HashSet<string>();
            foreach (var m in list) seen.Add(m.Key);
            int n = 0;
            foreach (var m in add) if (seen.Add(m.Key)) { list.Add(m); n++; }
            return n;
        }

        /// <summary>Marks of the shown floor with their category on, inside the tile box; at most `limit` (nearest the centre first).</summary>
        public static List<MapMark> Visible(Dictionary<int, List<MapMark>> floors, int z, double x1, double y1, double x2, double y2, MapMarkSettings s, int limit)
        {
            var o = new List<MapMark>();
            if (!floors.TryGetValue(z, out var l)) return o;
            foreach (var m in l)
            {
                if (!KindCategory.TryGetValue(m.Kind, out string cat) || !s.Cat(cat)) continue;
                if (m.X >= x1 && m.X <= x2 && m.Y >= y1 && m.Y <= y2) o.Add(m);
            }
            if (limit > 0 && o.Count > limit)
            {
                double cx = (x1 + x2) / 2, cy = (y1 + y2) / 2;
                o.Sort((a, b) =>
                {
                    double da = Math.Max(Math.Abs(a.X - cx), Math.Abs(a.Y - cy)), db = Math.Max(Math.Abs(b.X - cx), Math.Abs(b.Y - cy));
                    return da != db ? da.CompareTo(db) : string.CompareOrdinal(a.Key, b.Key);
                });
                o.RemoveRange(limit, o.Count - limit);
            }
            return o;
        }

        public static MapMark ParseMark(object o)
        {
            if (!(o is Dictionary<string, object>)) return null;
            if (Json.Get(o, "x") == null || Json.Get(o, "y") == null || Json.Get(o, "z") == null) return null;
            string k = Json.Text(o, "k");
            if (k.Length == 0) return null;
            return new MapMark { Kind = k, X = Json.Int(o, "x"), Y = Json.Int(o, "y"), Z = Json.Int(o, "z"), Name = Json.Text(o, "n") };
        }

        public static List<MapMark> ParseMarks(object data)
        {
            var o = new List<MapMark>();
            foreach (object e in Json.List(data, "marks")) { var m = ParseMark(e); if (m != null) o.Add(m); }
            return o;
        }
    }

    /// <summary>The gold "!" and "?" over NPC heads (server poi.lua action npcmarks), by NPC name.</summary>
    public sealed class NpcMarks
    {
        public const int Max = 40;
        public static readonly string[] Kinds = { "new", "ready", "locked" };
        readonly Dictionary<string, string> state = new Dictionary<string, string>();
        public int Count => state.Count;

        /// <summary>A full message starts again, a difference changes what it names; returns the number kept (at most 40).</summary>
        public int Apply(object data)
        {
            if (!(data is Dictionary<string, object>)) return state.Count;
            if (Json.Truthy(data, "full")) state.Clear();
            foreach (object n in Json.List(data, "clear")) if (n is string s && s.Length > 0) state.Remove(s.ToLowerInvariant());
            foreach (object e in Json.List(data, "set"))
            {
                string n = Json.Text(e, "n"), m = Json.Text(e, "m");
                if (n.Length == 0 || Array.IndexOf(Kinds, m) < 0) continue;
                string key = n.ToLowerInvariant();
                if (!state.ContainsKey(key) && state.Count >= Max) break;
                state[key] = m;
            }
            return state.Count;
        }

        /// <summary>"new", "ready", "locked" or "" for an NPC name.</summary>
        public string MarkFor(string name) => name != null && state.TryGetValue(name.ToLowerInvariant(), out string m) ? m : "";

        /// <summary>The glyph of a mark and its colour (gold "!" new, gold "?" ready, grey "!" locked).</summary>
        public static string Glyph(string mark) => mark == "ready" ? "?" : mark == "new" || mark == "locked" ? "!" : "";
        public static string GlyphColor(string mark) => mark == "locked" ? "#9a9a9a" : "#ffd84a";

        public void Clear() => state.Clear();
    }

    /// <summary>Party pins, points of interest, quest goals and NPC marks of opcode 153.</summary>
    public sealed class MapMarkState
    {
        public const byte Opcode = 153;
        readonly ExtOpcodes ext;
        public MapMarkSettings Settings = new MapMarkSettings();
        public readonly Dictionary<int, PartyMark> Party = new Dictionary<int, PartyMark>();
        public readonly Dictionary<int, MarkAnim> Anim = new Dictionary<int, MarkAnim>();
        public readonly Dictionary<int, int> Slots = new Dictionary<int, int>();
        public readonly List<MapMark> Pois = new List<MapMark>();
        public List<MapMark> Goals = new List<MapMark>();
        public Dictionary<int, List<MapMark>> Floors = new Dictionary<int, List<MapMark>>();
        public readonly NpcMarks Npc = new NpcMarks();
        public Func<double> Clock = () => 0;
        public Func<int> SelfId = () => 0;
        public Action Changed = delegate { };

        public MapMarkState(ExtOpcodes e) { ext = e; ext.On(Opcode, m => Handle(m.Action, m.Data)); }

        public void Hello() { ext.Send(Opcode, "hello", new Dictionary<string, object> { { "party", Settings.Party }, { "poi", Settings.Poi }, { "npcmarks", Settings.NpcMarks } }); }

        public void SetKind(string kind, bool on)
        {
            if (kind == "party") Settings.Party = on; else if (kind == "poi") Settings.Poi = on; else if (kind == "npcmarks") Settings.NpcMarks = on; else if (kind == "game") { Settings.Game = on; return; }
            else return;
            ext.Send(Opcode, "set", new Dictionary<string, object> { { kind, on } });
            if (!on)
            {
                if (kind == "party") { Party.Clear(); Anim.Clear(); }
                if (kind == "poi") { Pois.Clear(); Goals.Clear(); Refloor(); }
                if (kind == "npcmarks") Npc.Clear();
            }
            Changed();
        }

        void Refloor() { Floors = MapMarkMath.ByFloor(MapMarkMath.WithGoals(Pois, Goals)); }

        public void Handle(string action, object data)
        {
            switch (action)
            {
                case "party": if (Settings.Party) OnParty(data); break;
                case "poi": if (Settings.Poi) { Pois.Clear(); Pois.AddRange(MapMarkMath.ParseMarks(data)); Refloor(); Changed(); } break;
                case "reveal": if (Settings.Poi && MapMarkMath.AddMarks(Pois, MapMarkMath.ParseMarks(data)) > 0) { Refloor(); Changed(); } break;
                case "quests": if (Settings.Poi) { Goals = MapMarkMath.ParseMarks(data); Refloor(); Changed(); } break;
                case "npcmarks": if (Settings.NpcMarks) { Npc.Apply(data); Changed(); } break;
            }
        }

        void OnParty(object data)
        {
            double now = Clock();
            var seen = new HashSet<int>();
            var ids = new List<int>();
            var list = new List<PartyMark>();
            foreach (object o in Json.List(data, "m"))
            {
                if (!(o is Dictionary<string, object>) || Json.Get(o, "x") == null || Json.Get(o, "y") == null || Json.Get(o, "z") == null) continue;
                var p = new PartyMark { Id = Json.Int(o, "i"), Name = Json.Text(o, "n"), X = Json.Int(o, "x"), Y = Json.Int(o, "y"), Z = Json.Int(o, "z"), Percent = Json.Get(o, "p") == null ? -1 : Json.Int(o, "p") };
                if (p.Id == SelfId()) continue;
                list.Add(p); ids.Add(p.Id);
            }
            MapMarkMath.AssignColors(Slots, ids);
            foreach (var p in list)
            {
                seen.Add(p.Id);
                Anim.TryGetValue(p.Id, out var a);
                Anim[p.Id] = MapMarkMath.Retarget(a, p.X, p.Y, p.Z, now);
                Party[p.Id] = p;
            }
            foreach (int id in new List<int>(Party.Keys)) if (!seen.Contains(id)) { Party.Remove(id); Anim.Remove(id); }
            Changed();
        }

        public int SlotOf(int id) => Slots.TryGetValue(id, out int s) ? s : 1;

        public void Clear() { Party.Clear(); Anim.Clear(); Slots.Clear(); Pois.Clear(); Goals.Clear(); Floors.Clear(); Npc.Clear(); }
    }

    // ------------------------------------------------------------------------------------------------ map overlay
    public sealed class MapOverlaySettings
    {
        public double Opacity = 0.6;
        public int Zoom = 2;
        public bool Corner, Party = true, Town = true, Events = true, Strip = true;
    }

    /// <summary>The see-through explored map over the game view (mapmath.lua): zoom 0..4 (2^zoom pixels per tile), opacity 20..100 percent, pan.</summary>
    public sealed class MapOverlayState
    {
        public const byte Opcode = 245;
        public const int MinZoom = 0, MaxZoom = 4, PanLimit = 512;
        public const double DeathReopenMs = 120000;
        public static readonly Dictionary<string, string> Category = new Dictionary<string, string>
        {
            { "party", "party" }, { "temple", "town" }, { "depot", "town" }, { "npc", "town" }, { "entry", "events" }, { "guardian", "events" },
            { "chest", "events" }, { "coffer", "events" }, { "goblin", "events" }, { "worldboss", "events" }, { "invasion", "events" }, { "boss", "events" },
        };

        readonly ExtOpcodes ext;
        public MapOverlaySettings Settings = new MapOverlaySettings();
        public bool Shown;
        public double PanX, PanY;
        public List<MapMark> Marks = new List<MapMark>();
        readonly HashSet<string> riftTokens = new HashSet<string>();
        public int RiftClears;
        public Action<int, int, int, int, int> ClearArea = delegate { };
        public Action Changed = delegate { };

        public MapOverlayState(ExtOpcodes e) { ext = e; ext.On(Opcode, m => Handle(m.Action, m.Data)); }

        public static int ClampZoom(int z) => Math.Max(MinZoom, Math.Min(MaxZoom, z));
        public static double StepOpacity(double cur, double delta) => Math.Max(0.2, Math.Min(1.0, Math.Floor((cur + delta) * 10 + 0.5) / 10));
        public static int PixelsPerTile(int zoom) => 1 << ClampZoom(zoom);
        public static string Percent(double o) => (int)Math.Floor(o * 100 + 0.5) + "%";
        public static string ZoomLabel(int z) => "x" + PixelsPerTile(z);
        public static bool IsPanned(double x, double y) => Math.Abs(x) >= 0.05 || Math.Abs(y) >= 0.05;
        static double Clamp(double v, double lo, double hi) => v < lo ? lo : v > hi ? hi : v;

        public static void ClampPan(ref double x, ref double y, double limit = PanLimit) { x = Clamp(x, -limit, limit); y = Clamp(y, -limit, limit); }

        /// <summary>Dragging the map by (dx, dy) pixels from a pan: the map follows the mouse.</summary>
        public static void DragPan(double sx, double sy, double dx, double dy, int zoom, out double x, out double y)
        {
            int ppt = PixelsPerTile(zoom);
            x = sx - dx / ppt; y = sy - dy / ppt;
            ClampPan(ref x, ref y);
        }

        public static void KeyPan(double px, double py, int dirX, int dirY, int zoom, double pixels, out double x, out double y)
        {
            double step = Math.Max(1, pixels / PixelsPerTile(zoom));
            x = px + dirX * step; y = py + dirY * step;
            ClampPan(ref x, ref y);
        }

        /// <summary>Zooming keeps the map point under the cursor (ox, oy: pixels from the anchor) where it is.</summary>
        public static void ZoomToward(double px, double py, int oldZoom, int newZoom, double ox, double oy, out double x, out double y)
        {
            int a = PixelsPerTile(oldZoom), b = PixelsPerTile(newZoom);
            x = px + ox / a - ox / b; y = py + oy / a - oy / b;
            ClampPan(ref x, ref y);
        }

        /// <summary>"opacity" with Ctrl, "zoom" with Shift or over the strip, else "" (a plain wheel turn belongs to the game map).</summary>
        public static string WheelAction(bool ctrl, bool shift, bool overStrip) => ctrl ? "opacity" : shift || overStrip ? "zoom" : "";
        public static bool StartsPan(bool middle, bool shift, bool overStrip) => middle && shift && !overStrip;

        /// <summary>The corner box size for a game view panel.</summary>
        public static void CornerSize(double panelW, double panelH, out int w, out int h)
        {
            w = (int)Math.Floor(Clamp(panelW * 0.32, 180, 420));
            h = (int)Math.Floor(Clamp(panelH * 0.36, 140, 320));
        }

        public static bool ShouldClearRift(HashSet<string> tokens, string id, int x1, int y1, int x2, int y2)
            => id.Length > 0 && Math.Abs(x2 - x1) <= 512 && Math.Abs(y2 - y1) <= 512 && !tokens.Contains(id);

        /// <summary>The marks to draw: a known kind, the shown floor, its category switched on.</summary>
        public List<MapMark> VisibleMarks(int z)
        {
            var o = new List<MapMark>();
            foreach (var m in Marks)
            {
                if (!Category.TryGetValue(m.Kind, out string cat) || m.Z != z) continue;
                bool on = cat == "party" ? Settings.Party : cat == "town" ? Settings.Town : Settings.Events;
                if (on) o.Add(m);
            }
            return o;
        }

        /// <summary>A death note: the overlay was open; the next game start reopens it for the same character within two minutes.</summary>
        public static bool ReopenAfterDeath(string noteName, double noteAt, string name, double now)
        {
            if (string.IsNullOrEmpty(noteName) || noteName != name) return false;
            double dt = now - noteAt;
            return dt >= 0 && dt <= DeathReopenMs;
        }

        public void Show(bool on)
        {
            if (Shown == on) return;
            Shown = on;
            if (!on) { PanX = PanY = 0; Marks.Clear(); }
            ext.Send(Opcode, "watch", new Dictionary<string, object> { { "on", on } });
            Changed();
        }

        public void Toggle() => Show(!Shown);

        public void Centre() { PanX = PanY = 0; }

        public void Handle(string action, object data)
        {
            if (action == "marks") { Marks = MapMarkMath.ParseMarks(data); Changed(); }
            else if (action == "rift")
            {
                string id = Json.Get(data, "id") == null ? "" : Json.Text(data, "id", Json.Int(data, "id").ToString());
                int x1 = Json.Int(data, "x1"), y1 = Json.Int(data, "y1"), x2 = Json.Int(data, "x2"), y2 = Json.Int(data, "y2"), z = Json.Int(data, "z");
                if (Json.Get(data, "x1") == null || Json.Get(data, "z") == null || !ShouldClearRift(riftTokens, id, x1, y1, x2, y2)) return;
                riftTokens.Add(id);
                PanX = PanY = 0;
                RiftClears++;
                ClearArea(x1, y1, x2, y2, z);
            }
        }

        public void Clear() { Shown = false; PanX = PanY = 0; Marks.Clear(); riftTokens.Clear(); }
    }

    // ------------------------------------------------------------------------------------------------ minimap sync
    /// <summary>What the minimap window does after a death and the relog (minimapsync_logic.lua): it comes back where it was, centred on the character.</summary>
    public sealed class MinimapSyncPlan
    {
        public bool ExitFullMap, Reparent, Restore, Recentre, ConsumeWant;
    }

    public static class MinimapSyncLogic
    {
        public static readonly int[] PassesMs = { 0, 400, 1200, 3000 };

        public static bool ValidPos(int x, int y, int z) => x >= 0 && y >= 0 && z >= 0 && x < 65535 && y < 65535 && z <= 15;

        /// <summary>What to do now: reason "start", "teleport" or "end".</summary>
        public static MinimapSyncPlan Plan(string reason, bool fullmap, bool windowShown, bool wantOpen, bool camOnPlayer)
        {
            var p = new MinimapSyncPlan();
            if (fullmap && reason != "teleport") p.ExitFullMap = true;
            if (wantOpen && !windowShown) p.Restore = true;
            if (!camOnPlayer) p.Recentre = true;
            if (!wantOpen || windowShown || p.Restore) p.ConsumeWant = wantOpen;
            return p;
        }

        /// <summary>The window as it was at a death or the end of a session; false when it was closed (the player's choice is kept).</summary>
        public static bool Remember(bool visible, bool fullmap) => visible || fullmap;
    }
}
