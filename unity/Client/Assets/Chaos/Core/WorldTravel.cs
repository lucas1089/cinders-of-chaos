// Travel and place systems (client game_npctravel 121, game_waystone 202, game_townportal 239, game_hideout 192). Pure models.
//
// npctravel 121     client travel {k} (a key of npc_travel_config.lua; the server checks combat, instances and the cooldown). No answer but a game message.
// waystone 202      raw JSON without the data wrapper. server show {tiers = [{clientId, look, tier, count, level}], pick} | teleport_done | teleport_error {text} |
//                   choice_show {choices = [{id, text}]} | choice_done | choice_error {text} | wrap_done | wrap_error {text}; client teleport {clientId} | choice | choice_apply {choiceId}
// townportal 239    client open | get | select {id} | cast; server state {open, selected, cooldown, cooldownTotal, styles = [{id, name, desc, route, how, owned, selected, clientItem, price}]}
//                   | cast {ms} | castEnd {result}
// hideout 192       client open | get | enter | leave | visit {guid} | place {key, x, y, r} | move {id, x, y, r} | remove {id} | clear | theme {key} | perm {level} | kick | visits | like {owner};
//                   server state {open, me, hideout, inside, layout, themes, catalogue, placed, permissions, categories} | visits {friends, showcase = {likes, visits}, recent} | result {ok, text}
using System;
using System.Collections.Generic;
using System.Globalization;

namespace Chaos.Core
{
    // ------------------------------------------------------------------------------------------------ npc travel
    public sealed class NpcTravel
    {
        public const byte Opcode = 121;
        public const double GapSeconds = 1.0;
        public static readonly string[] Keys =
        {
            "apothecary", "banker", "broker", "candlemarks", "conquest", "faction_choir", "faction_circle", "faction_compact", "faction_vigil", "gambler",
            "lootbuyer", "materials", "odrenna", "oracle", "pocketboss", "services", "stash", "tales", "trials",
        };
        /// <summary>Shown names of the keys.</summary>
        public static readonly Dictionary<string, string> Names = new Dictionary<string, string>
        {
            { "apothecary", "Apothecary" }, { "banker", "Banker" }, { "broker", "Broker" }, { "candlemarks", "Candle Marks" }, { "conquest", "Conquest" },
            { "faction_choir", "Choir faction" }, { "faction_circle", "Circle faction" }, { "faction_compact", "Compact faction" }, { "faction_vigil", "Vigil faction" },
            { "gambler", "Gambler" }, { "lootbuyer", "Loot buyer" }, { "materials", "Materials" }, { "odrenna", "Odrenna" }, { "oracle", "Oracle" },
            { "pocketboss", "Pocket boss" }, { "services", "Services" }, { "stash", "Stash" }, { "tales", "Tales" }, { "trials", "Trials" },
        };

        readonly ExtOpcodes ext;
        double lastAt = -1;
        public Func<double> Clock = () => 0;   // ms

        public NpcTravel(ExtOpcodes e) { ext = e; }

        public static bool Valid(string key) => Array.IndexOf(Keys, key ?? "") >= 0;

        /// <summary>The NPC key of a faction (server key "faction_" + faction key), "" when none.</summary>
        public static string FactionKey(string faction)
        {
            if (string.IsNullOrEmpty(faction)) return "";
            string k = "faction_" + faction;
            return Valid(k) ? k : "";
        }

        /// <summary>Who fronts a service panel (the goNpcButton tooltips of the main client's panels): key to the NPC as the tooltip names it.</summary>
        public static readonly Dictionary<string, string> PanelNpc = new Dictionary<string, string>
        {
            { "stash", "Tavish Coldhand, the stash keeper" }, { "pocketboss", "Vessa Hollowmark, the pocket boss NPC" }, { "candlemarks", "Osric the Chandler" },
            { "gambler", "Mordecai Ashwager, the Gambler" }, { "materials", "the Material Broker" },
        };

        /// <summary>The tooltip of the Go to NPC button of a panel: where it takes you and its rules. Plain English, translated by the caller's Loc table.</summary>
        public static string PanelTip(string key)
        {
            string npc;
            if (!PanelNpc.TryGetValue(key ?? "", out npc)) return Loc.T("Takes you in front of the NPC. Not in combat; a short wait between two trips.");
            return Loc.T("Takes you in front of {0}, in the market of the teleport room. Not in combat; a short wait between two trips.", npc);
        }

        public static bool TooSoon(double nowSec, double lastSec) => lastSec >= 0 && nowSec >= lastSec && nowSec - lastSec < GapSeconds;

        public static Dictionary<string, object> Message(string key) => Valid(key) ? new Dictionary<string, object> { { "k", key } } : null;

        /// <summary>Sends "Go to NPC"; false for an unknown key or a request under a second after the last.</summary>
        public bool Travel(string key)
        {
            if (!Valid(key)) return false;
            double now = Clock() / 1000.0;
            if (TooSoon(now, lastAt)) return false;
            lastAt = now;
            return ext.Send(Opcode, "travel", Message(key));
        }

        public void Clear() { lastAt = -1; }
    }

    // ------------------------------------------------------------------------------------------------ waystone
    public sealed class WaystoneRow
    {
        public int Tier, ClientId, Look, Count = -1, Level;   // Count -1: the server did not say
        public string Roman = "";
        public bool Usable;
    }

    public sealed class WaystoneChoice { public int Id; public string Text = ""; }

    public sealed class WaystoneState
    {
        public const byte Opcode = 202;
        public static readonly int[] TierClientIds = { 27189, 27190, 27191, 27192, 27193, 27194 };
        public static readonly string[] Roman = { "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X", "XI", "XII", "XIII", "XIV", "XV" };

        readonly ExtOpcodes ext;
        public List<WaystoneRow> Rows = new List<WaystoneRow>();
        public List<WaystoneChoice> Choices = new List<WaystoneChoice>();
        public int Selected;
        public bool Visible, ChoicesVisible;
        public string Status = "";
        public Action Changed = delegate { };

        public WaystoneState(ExtOpcodes e) { ext = e; ext.On(Opcode, m => Handle(m.Root)); }

        static bool Whole(object o, string key, out int v)
        {
            v = 0;
            object x = Json.Get(o, key);
            if (!(x is double d) || double.IsNaN(d) || double.IsInfinity(d) || d != Math.Floor(d)) return false;
            v = (int)d;
            return true;
        }

        /// <summary>The rows of a "show" message in tier order: the six base tiers always; a listed tier (whole 1..15 with a client id) adds or replaces its row.</summary>
        public static List<WaystoneRow> BuildRows(object msg)
        {
            var byTier = new Dictionary<int, KeyValuePair<int, object>>();
            for (int i = 0; i < TierClientIds.Length; i++) byTier[i + 1] = new KeyValuePair<int, object>(TierClientIds[i], null);
            var tiers = Json.Get(msg, "tiers") as List<object>;
            if (tiers != null)
                foreach (object t in tiers)
                {
                    if (!(t is Dictionary<string, object>)) continue;
                    bool hasId = Whole(t, "clientId", out int id), hasTier = Whole(t, "tier", out int tier);
                    for (int i = 0; hasId && i < TierClientIds.Length; i++) if (TierClientIds[i] == id) { tier = i + 1; hasTier = true; }
                    if (hasId && hasTier && tier >= 1 && tier <= Roman.Length) byTier[tier] = new KeyValuePair<int, object>(id, t);
                }
            var o = new List<WaystoneRow>();
            for (int tier = 1; tier <= Roman.Length; tier++)
            {
                if (!byTier.TryGetValue(tier, out var e)) continue;
                var info = e.Value;
                int count = -1;
                if (tiers != null) { count = info != null && Whole(info, "count", out int c) ? c : 0; if (count < 0) count = 0; }
                int look = info != null && Whole(info, "look", out int lk) && lk > 0 ? lk : e.Key;
                int level = info != null && Whole(info, "level", out int lv) && lv > 0 ? lv : 0;
                o.Add(new WaystoneRow { Tier = tier, Roman = Roman[tier - 1], ClientId = e.Key, Look = look, Count = count, Level = level, Usable = count < 0 || count > 0 });
            }
            return o;
        }

        public static string LevelText(WaystoneRow r) => r == null || r.Level <= 0 ? "" : Loc.T("level {0}", r.Level);
        public static string CountText(WaystoneRow r) => r == null || r.Count < 0 ? "" : r.Count == 0 ? Loc.T("none") : Loc.T("{0} held", r.Count);

        /// <summary>Where a tier not held comes from ("" when held or unknown).</summary>
        public static string SourceText(WaystoneRow r)
        {
            if (r == null || r.Count != 0 || r.Tier <= 0) return "";
            if (r.Tier <= 1) return Loc.T("None held. Tier I drops from monsters anywhere.");
            int lo = Math.Max(1, r.Tier - 2);
            return Loc.T("None held. Drops in waystone maps of tier {0} to {1}; the boss of tier {2} drops one.", Roman[lo - 1], Roman[r.Tier - 1], Roman[r.Tier - 2]);
        }

        /// <summary>The row to select first: the server's pick, else the lowest tier held, else the first.</summary>
        public static int FirstRow(IList<WaystoneRow> rows, int pick)
        {
            if (pick > 0) for (int i = 0; i < rows.Count; i++) if (rows[i].ClientId == pick) return i;
            for (int i = 0; i < rows.Count; i++) if (rows[i].Count > 0) return i;
            return 0;
        }

        public static List<WaystoneChoice> ParseChoices(object msg)
        {
            var o = new List<WaystoneChoice>();
            foreach (object c in Json.List(msg, "choices"))
                if (Whole(c, "id", out int id) && id >= 0) o.Add(new WaystoneChoice { Id = id, Text = Json.Text(c, "text", "?") });
            o.Sort((a, b) => a.Id.CompareTo(b.Id));
            return o;
        }

        /// <summary>"show", "close", "choices", "status" or "" with the status text.</summary>
        public static string Classify(object msg, out string text)
        {
            text = "";
            string a = Json.Text(msg, "action");
            switch (a)
            {
                case "show": return "show";
                case "teleport_done": text = Loc.T("The portals are open around the device for 60 seconds."); return "close";
                case "choice_show": return "choices";
                case "choice_done": text = Loc.T("Portal look saved."); return "status";
                case "wrap_done": return "close";
                case "teleport_error": case "choice_error": case "wrap_error":
                    text = Json.Text(msg, "text"); if (text.Length == 0) text = Loc.T("The device refused."); return "status";
            }
            return "";
        }

        public bool Teleport(int row)
        {
            if (row < 0 || row >= Rows.Count || !Rows[row].Usable) return false;
            return ext.SendText(Opcode, Json.Serialize(new Dictionary<string, object> { { "action", "teleport" }, { "clientId", Rows[row].ClientId } }));
        }

        public void AskChoice() { ext.SendText(Opcode, Json.Serialize(new Dictionary<string, object> { { "action", "choice" } })); }
        public void ApplyChoice(int id) { ext.SendText(Opcode, Json.Serialize(new Dictionary<string, object> { { "action", "choice_apply" }, { "choiceId", id } })); }

        public void Handle(object msg)
        {
            if (!(msg is Dictionary<string, object>)) return;
            switch (Classify(msg, out string text))
            {
                case "show":
                    Rows = BuildRows(msg);
                    int pick = 0; Whole(msg, "pick", out pick);
                    Selected = FirstRow(Rows, pick);
                    Visible = true; ChoicesVisible = false; Status = SourceText(Rows[Selected]);
                    break;
                case "close": Visible = false; ChoicesVisible = false; Status = text; break;
                case "choices": Choices = ParseChoices(msg); ChoicesVisible = true; break;
                case "status": Status = text; break;
                default: return;
            }
            Changed();
        }

        public void Select(int i) { if (i >= 0 && i < Rows.Count) { Selected = i; string s = SourceText(Rows[i]); if (s.Length > 0) Status = s; } }
        public void Hide() { Visible = false; ChoicesVisible = false; }
        public void Clear() { Rows.Clear(); Choices.Clear(); Visible = false; ChoicesVisible = false; Status = ""; }
    }

    // ------------------------------------------------------------------------------------------------ town portal
    public sealed class PortalStyle
    {
        public string Id = "", Name = "", Desc = "", Route = "", How = "";
        public bool Owned, Selected;
        public int ClientItem, Price;
    }

    public sealed class TownPortalState
    {
        public const byte Opcode = 239;
        readonly ExtOpcodes ext;
        public readonly List<PortalStyle> Styles = new List<PortalStyle>();
        public string SelectedId = "";
        public int Cooldown, CooldownTotal;
        public bool Visible, Loaded;
        public Action Changed = delegate { };
        /// <summary>The cast bar hand-off: name and milliseconds of a cast that starts, and the result of one that ends ("done", "moved", ...).</summary>
        public Action<string, double> CastStarted = delegate { };
        public Action<string> CastEnded = delegate { };
        double tickAt = -1;

        public TownPortalState(ExtOpcodes e) { ext = e; ext.On(Opcode, m => Handle(m.Action, m.Data)); }

        void Send(string action, Dictionary<string, object> data = null) { ext.Send(Opcode, action, data ?? new Dictionary<string, object>()); }

        public static string RouteText(PortalStyle s)
        {
            switch (s.Route)
            {
                case "store": return s.Owned ? Loc.T("Store - owned") : Loc.T("Store") + (s.Price > 0 ? " - " + s.Price + " coins" : "");
                case "achievement": return s.Owned ? Loc.T("Achievement - unlocked") : Loc.T("Achievement - locked");
                case "season": return s.Owned ? Loc.T("Season pass - unlocked") : Loc.T("Season pass - locked");
            }
            return Loc.T("Every character");
        }

        public string StatusText() => Cooldown > 0 ? Loc.T("Town Portal ready in {0} s.", Cooldown) : Loc.T("Town Portal ready.");
        public PortalStyle StyleOf(string id) { foreach (var s in Styles) if (s.Id == id) return s; return null; }
        public bool CanCast => Cooldown <= 0;

        public void Open() { Visible = true; Send("open"); }
        public void Toggle() { if (Visible) Visible = false; else Open(); }
        public void Cast() { Send("cast"); }
        public void SelectCurrent() { if (SelectedId.Length > 0) Send("select", new Dictionary<string, object> { { "id", SelectedId } }); }
        public void Pick(string id) { if (StyleOf(id) != null) SelectedId = id; }

        /// <summary>Counts the cooldown down once a second (the window does it while it is shown).</summary>
        public void Tick(double nowMs)
        {
            if (!Visible) { tickAt = -1; return; }
            if (tickAt < 0) tickAt = nowMs;
            while (nowMs - tickAt >= 1000) { tickAt += 1000; if (Cooldown > 0) Cooldown--; }
        }

        public void Handle(string action, object data)
        {
            if (action == "state")
            {
                Styles.Clear();
                foreach (object o in Json.List(data, "styles"))
                {
                    if (!(o is Dictionary<string, object>) || Json.Get(o, "id") == null) continue;
                    Styles.Add(new PortalStyle
                    {
                        Id = Json.Text(o, "id", Json.Int(o, "id").ToString(CultureInfo.InvariantCulture)), Name = Json.Text(o, "name", "?"), Desc = Json.Text(o, "desc"),
                        Route = Json.Text(o, "route"), How = Json.Text(o, "how"), Owned = Json.Bool(o, "owned"), Selected = Json.Bool(o, "selected"),
                        ClientItem = Json.Int(o, "clientItem"), Price = Json.Int(o, "price"),
                    });
                }
                Cooldown = Json.Int(data, "cooldown"); CooldownTotal = Json.Int(data, "cooldownTotal");
                string sel = Json.Get(data, "selected") == null ? "" : Json.Text(data, "selected", Json.Int(data, "selected").ToString(CultureInfo.InvariantCulture));
                if (StyleOf(SelectedId) == null) SelectedId = sel;
                Loaded = true;
                if (Json.Bool(data, "open")) { Visible = true; tickAt = -1; }
                Changed();
            }
            else if (action == "cast") CastStarted(Loc.T("Town Portal"), Json.Number(data, "ms", 3000));
            else if (action == "castEnd") CastEnded(Json.Text(data, "result", "done"));
        }

        public void Clear() { Styles.Clear(); SelectedId = ""; Visible = false; Loaded = false; Cooldown = 0; }
    }

    // ------------------------------------------------------------------------------------------------ hideout
    public sealed class HideoutPart { public int Dx, Dy; public int Id; }

    public sealed class HideoutRow
    {
        public string Key = "", Name = "", Cat = "", Source = "", How = "", Layer = "object";
        public int Item, Placed, Max;
        public bool Owned, Block;
        public List<List<HideoutPart>> Rots = new List<List<HideoutPart>>();
        public List<HideoutPart> WallW;
    }

    public sealed class HideoutPlaced { public int Id, X, Y, R = 1; public string Key = ""; }

    public sealed class HideoutVisit
    {
        public long Guid;
        public string Name = "", Theme = "", Why = "", At = "";
        public int Likes = -1, Visits = -1;
        public bool Online;
    }

    public sealed class HideoutLayout
    {
        public int W, H, ArrivalX, ArrivalY;
        public readonly List<KeyValuePair<KeyValuePair<int, int>, string>> Reserved = new List<KeyValuePair<KeyValuePair<int, int>, string>>();
    }

    public sealed class HideoutInside
    {
        public bool IsOwner;
        public string OwnerName = "";
        public long Owner;
        public int OriginX, OriginY, OriginZ;
    }

    public sealed class HideoutTheme { public string Key = "", Name = "", Desc = "", How = ""; public bool Owned, Selected; public int MaxDecor, Item; }
    public sealed class HideoutPerm { public int Id; public string Name = "", Desc = ""; }

    public sealed class HideoutInfo { public int Count, Max, Likes, Visits, Perm; public string ThemeName = ""; }

    public sealed class HideoutState
    {
        public const byte Opcode = 192;
        public static readonly KeyValuePair<string, string>[] Sources =
        {
            new KeyValuePair<string, string>("all", "Any source"), new KeyValuePair<string, string>("default", "Every character"), new KeyValuePair<string, string>("achievement", "Achievements"),
            new KeyValuePair<string, string>("faction", "Factions"), new KeyValuePair<string, string>("trophy", "Trophies"), new KeyValuePair<string, string>("descent", "Ember Descent"),
            new KeyValuePair<string, string>("event", "Events"), new KeyValuePair<string, string>("journey", "Season journey"), new KeyValuePair<string, string>("store", "Store"),
        };

        readonly ExtOpcodes ext;
        public bool Visible, Loaded, HasInside;
        public HideoutInfo Info = new HideoutInfo();
        public HideoutInside Inside = new HideoutInside();
        public HideoutLayout Layout = new HideoutLayout();
        public readonly List<HideoutRow> Catalogue = new List<HideoutRow>();
        public readonly List<HideoutPlaced> Placed = new List<HideoutPlaced>();
        public readonly List<HideoutTheme> Themes = new List<HideoutTheme>();
        public readonly List<HideoutPerm> Permissions = new List<HideoutPerm>();
        public readonly List<string> Categories = new List<string>();
        public List<HideoutVisit> Friends = new List<HideoutVisit>(), Recent = new List<HideoutVisit>(), ShowLikes = new List<HideoutVisit>(), ShowVisits = new List<HideoutVisit>();
        public string ResultText = "";
        public bool ResultOk;
        public Action Changed = delegate { };

        public HideoutState(ExtOpcodes e) { ext = e; ext.On(Opcode, m => Handle(m.Action, m.Data)); }

        void Send(string action, Dictionary<string, object> data = null) { ext.Send(Opcode, action, data ?? new Dictionary<string, object>()); }

        public void Open() { Visible = true; Send("open"); }
        public void Toggle() { if (Visible) Visible = false; else Open(); }
        public void Enter() { Send("enter"); }
        public void Leave() { Send("leave"); }
        public void Kick() { Send("kick"); }
        public void Visits() { Send("visits"); }
        public void Visit(long guid) { Send("visit", new Dictionary<string, object> { { "guid", guid } }); }
        public void Theme(string key) { Send("theme", new Dictionary<string, object> { { "key", key } }); }
        public void SetPerm(int level) { Send("perm", new Dictionary<string, object> { { "level", level } }); }
        public void Remove(int id) { Send("remove", new Dictionary<string, object> { { "id", id } }); }
        public void ClearAll() { if (Placed.Count > 0) Send("clear"); }
        public void Like() { if (HasInside) Send("like", new Dictionary<string, object> { { "owner", Inside.Owner } }); }
        public void Place(string key, int x, int y, int r) { Send("place", new Dictionary<string, object> { { "key", key }, { "x", x }, { "y", y }, { "r", r } }); }
        public void Move(int id, int x, int y, int r) { Send("move", new Dictionary<string, object> { { "id", id }, { "x", x }, { "y", y }, { "r", r } }); }

        public HideoutRow RowOf(string key) { foreach (var r in Catalogue) if (r.Key == key) return r; return null; }
        public HideoutPlaced PlacedOf(int id) { foreach (var p in Placed) if (p.Id == id) return p; return null; }

        // ---- catalogue rules (hideoutlogic.lua)
        /// <summary>Filter: cat "all" or a key, source "all" or a key, owned only, a search text. Unlocked first, then by name.</summary>
        public static List<HideoutRow> Filter(IEnumerable<HideoutRow> rows, string cat, string source, bool ownedOnly, string search)
        {
            string needle = (search ?? "").Trim().ToLowerInvariant();
            var o = new List<HideoutRow>();
            foreach (var r in rows)
            {
                if (!string.IsNullOrEmpty(cat) && cat != "all" && r.Cat != cat) continue;
                if (!string.IsNullOrEmpty(source) && source != "all" && r.Source != source) continue;
                if (ownedOnly && !r.Owned) continue;
                if (needle.Length > 0 && r.Name.ToLowerInvariant().IndexOf(needle, StringComparison.Ordinal) < 0) continue;
                o.Add(r);
            }
            o.Sort((a, b) => a.Owned != b.Owned ? (a.Owned ? -1 : 1) : string.CompareOrdinal(a.Name, b.Name));
            return o;
        }

        public static string SubText(HideoutRow r) => r.Owned ? Loc.T("{0} / {1} placed", r.Placed, r.Max) : "Locked - " + r.How;

        /// <summary>May the player start placing this row? Gives the reason when not.</summary>
        public bool CanPlace(HideoutRow r, out string why)
        {
            why = "";
            if (r == null) { why = Loc.T("Pick a decoration."); return false; }
            if (!HasInside || !Inside.IsOwner) { why = Loc.T("Enter your hideout to decorate it."); return false; }
            if (!r.Owned) { why = "Locked: " + r.How; return false; }
            if (r.Placed >= r.Max) { why = Loc.T("At most {0} of it.", r.Max); return false; }
            if (Info.Count >= Info.Max) { why = Loc.T("Your hideout holds at most {0} decorations.", Info.Max); return false; }
            return true;
        }

        public static int RotCount(HideoutRow r) => r == null || r.Layer == "wall" ? 1 : Math.Max(1, r.Rots.Count);
        public static int NextRot(HideoutRow r, int rot, int step = 1)
        {
            int n = RotCount(r);
            rot += step;
            if (rot > n) rot = 1;
            if (rot < 1) rot = n;
            return rot;
        }

        public static List<HideoutPart> Parts(HideoutRow r, int rot, string side)
        {
            if (r == null) return new List<HideoutPart>();
            if (r.Layer == "wall")
            {
                if (side == "w" && r.WallW != null) return r.WallW;
                return r.Rots.Count > 0 ? r.Rots[0] : new List<HideoutPart>();
            }
            if (r.Rots.Count == 0) return new List<HideoutPart>();
            return rot >= 1 && rot <= r.Rots.Count ? r.Rots[rot - 1] : r.Rots[0];
        }

        /// <summary>Grid position of a world tile in the room (walls included); false outside it.</summary>
        public bool ToGrid(int x, int y, int z, out int gx, out int gy)
        {
            gx = gy = 0;
            if (!HasInside || z != Inside.OriginZ) return false;
            gx = x - Inside.OriginX; gy = y - Inside.OriginY;
            return !(gx < 0 || gy < 0 || gx > Layout.W + 1 || gy > Layout.H + 1);
        }

        public static string WallSide(HideoutLayout l, int gx, int gy)
        {
            if (gy == 0 && gx >= 1 && gx <= l.W) return "n";
            if (gx == 0 && gy >= 1 && gy <= l.H) return "w";
            return "";
        }

        class Occ { public Dictionary<string, int> Object = new Dictionary<string, int>(), Floor = new Dictionary<string, int>(), Wall = new Dictionary<string, int>(); public HashSet<string> Solid = new HashSet<string>(); }
        static string K(int x, int y) => x + "," + y;

        Occ Occupancy(int ignoreId, out int total)
        {
            var occ = new Occ();
            total = 0;
            foreach (var p in Placed)
            {
                if (p.Id == ignoreId) continue;
                var r = RowOf(p.Key);
                if (r == null) continue;
                total++;
                string side = r.Layer == "wall" ? WallSide(Layout, p.X, p.Y) : "";
                var map = r.Layer == "wall" ? occ.Wall : r.Layer == "floor" ? occ.Floor : occ.Object;
                foreach (var part in Parts(r, p.R, side))
                {
                    string k = K(p.X + part.Dx, p.Y + part.Dy);
                    map[k] = p.Id;
                    if (r.Block && r.Layer == "object") occ.Solid.Add(k);
                }
            }
            return occ;
        }

        static bool FixtureSolid(string name) => name == "depot" || name == "stash" || name == "waystone" || name.StartsWith("dummy", StringComparison.Ordinal) || name.StartsWith("light", StringComparison.Ordinal);

        /// <summary>Every fixture except the lights keeps a walkable neighbour reachable from the arrival tile (8 directions).</summary>
        public static bool ReachOk(HideoutLayout l, HashSet<string> solid, out string what)
        {
            what = "";
            var blocked = new HashSet<string>(solid);
            foreach (var t in l.Reserved) if (FixtureSolid(t.Value)) blocked.Add(K(t.Key.Key, t.Key.Value));
            var seen = new HashSet<string> { K(l.ArrivalX, l.ArrivalY) };
            var queue = new List<KeyValuePair<int, int>> { new KeyValuePair<int, int>(l.ArrivalX, l.ArrivalY) };
            for (int head = 0; head < queue.Count; head++)
            {
                int x = queue[head].Key, y = queue[head].Value;
                for (int dy = -1; dy <= 1; dy++)
                    for (int dx = -1; dx <= 1; dx++)
                    {
                        int nx = x + dx, ny = y + dy;
                        string k = K(nx, ny);
                        if ((dx != 0 || dy != 0) && nx >= 1 && ny >= 1 && nx <= l.W && ny <= l.H && !seen.Contains(k) && !blocked.Contains(k))
                        {
                            seen.Add(k);
                            queue.Add(new KeyValuePair<int, int>(nx, ny));
                        }
                    }
            }
            foreach (var t in l.Reserved)
            {
                string name = t.Value;
                if (name == "arrival" || name.StartsWith("light", StringComparison.Ordinal) || name.StartsWith("waystonepad", StringComparison.Ordinal)) continue;
                bool reached = false;
                if (!FixtureSolid(name)) reached = seen.Contains(K(t.Key.Key, t.Key.Value));
                else
                    for (int dy = -1; dy <= 1 && !reached; dy++)
                        for (int dx = -1; dx <= 1; dx++)
                            if (seen.Contains(K(t.Key.Key + dx, t.Key.Value + dy))) { reached = true; break; }
                if (!reached) { what = name; return false; }
            }
            return true;
        }

        /// <summary>Can row r go to (gx, gy) at rotation rot? The server decides; this only colours the preview.</summary>
        public bool Check(HideoutRow r, int gx, int gy, int rot, int ignoreId, out string why)
        {
            why = "";
            if (r == null) { why = Loc.T("Pick a decoration."); return false; }
            var occ = Occupancy(ignoreId, out int total);
            if (total >= Info.Max) { why = Loc.T("The hideout is full."); return false; }
            int same = 0;
            foreach (var p in Placed) if (p.Key == r.Key && p.Id != ignoreId) same++;
            if (same >= r.Max) { why = Loc.T("At most {0}.", r.Max); return false; }
            if (r.Layer == "wall")
            {
                if (WallSide(Layout, gx, gy).Length == 0) { why = Loc.T("Hang it on the north or the west wall."); return false; }
                if (occ.Wall.ContainsKey(K(gx, gy))) { why = Loc.T("Something already hangs there."); return false; }
                return true;
            }
            var reserved = new HashSet<string>();
            foreach (var t in Layout.Reserved) reserved.Add(K(t.Key.Key, t.Key.Value));
            var layerMap = r.Layer == "floor" ? occ.Floor : occ.Object;
            var newSolid = new HashSet<string>();
            foreach (var part in Parts(r, rot, ""))
            {
                int x = gx + part.Dx, y = gy + part.Dy;
                string k = K(x, y);
                if (x < 1 || y < 1 || x > Layout.W || y > Layout.H) { why = Loc.T("Place it on the floor."); return false; }
                if (reserved.Contains(k)) { why = Loc.T("That tile is kept free."); return false; }
                if (layerMap.ContainsKey(k)) { why = r.Layer == "floor" ? Loc.T("There is a rug there.") : Loc.T("Something stands there."); return false; }
                if (r.Layer == "object" && r.Block) newSolid.Add(k);
            }
            if (newSolid.Count > 0)
            {
                foreach (string k in occ.Solid) newSolid.Add(k);
                if (!ReachOk(Layout, newSolid, out string what))
                {
                    why = Loc.T("That would wall off the {0}.", what.StartsWith("dummy", StringComparison.Ordinal) ? Loc.T("dummies") : what);
                    return false;
                }
            }
            return true;
        }

        public string PermName(int id) { foreach (var p in Permissions) if (p.Id == id) return p.Name; return "?"; }

        public static string WhyText(string why) => why == "friend" ? "VIP" : why == "party" ? "Party" : why == "guild" ? "Guild" : why;

        public static string VisitLine(HideoutVisit v)
        {
            var parts = new List<string> { v.Name };
            if (v.Theme.Length > 0) parts.Add(v.Theme);
            if (v.Why.Length > 0) parts.Add(WhyText(v.Why));
            if (v.Likes >= 0) parts.Add(v.Likes + " likes");
            if (v.Visits >= 0) parts.Add(v.Visits + " visits");
            if (v.At.Length > 0) parts.Add(v.At);
            return string.Join("  -  ", parts);
        }

        public string CountText() => Loaded ? Loc.T("{0} - {1} / {2} decorations", Info.ThemeName, Info.Count, Info.Max) : "";

        static List<HideoutPart> ParseParts(object o)
        {
            var l = new List<HideoutPart>();
            if (o is List<object> list)
                foreach (object p in list)
                    if (p is List<object> a && a.Count >= 2)
                        l.Add(new HideoutPart { Dx = (int)(a[0] is double d0 ? d0 : 0), Dy = (int)(a[1] is double d1 ? d1 : 0), Id = a.Count > 2 && a[2] is double d2 ? (int)d2 : 0 });
            return l;
        }

        static List<HideoutVisit> ParseVisits(object o)
        {
            var l = new List<HideoutVisit>();
            if (!(o is List<object> list)) return l;
            foreach (object v in list)
            {
                if (!(v is Dictionary<string, object>)) continue;
                l.Add(new HideoutVisit
                {
                    Guid = (long)Json.Number(v, "guid"), Name = Json.Text(v, "name"), Theme = Json.Text(v, "theme"), Why = Json.Text(v, "why"), At = Json.Text(v, "at"),
                    Likes = Json.Get(v, "likes") == null ? -1 : Json.Int(v, "likes"), Visits = Json.Get(v, "visits") == null ? -1 : Json.Int(v, "visits"), Online = Json.Bool(v, "online"),
                });
            }
            return l;
        }

        public void Handle(string action, object data)
        {
            if (!(data is Dictionary<string, object>) && action != "result") return;
            if (action == "state") ApplyState(data);
            else if (action == "visits")
            {
                Friends = ParseVisits(Json.Get(data, "friends")); Recent = ParseVisits(Json.Get(data, "recent"));
                object sc = Json.Get(data, "showcase");
                ShowLikes = ParseVisits(Json.Get(sc, "likes")); ShowVisits = ParseVisits(Json.Get(sc, "visits"));
                Changed();
            }
            else if (action == "result") { ResultText = Json.Text(data, "text"); ResultOk = Json.Bool(data, "ok"); Changed(); }
        }

        void ApplyState(object d)
        {
            var h = Json.Get(d, "hideout");
            Info = new HideoutInfo { Count = Json.Int(h, "count"), Max = Json.Int(h, "max"), Likes = Json.Int(h, "likes"), Visits = Json.Int(h, "visits"), Perm = Json.Int(h, "perm"), ThemeName = Json.Text(h, "themeName") };
            var ins = Json.Get(d, "inside");
            HasInside = ins is Dictionary<string, object>;
            Inside = new HideoutInside();
            if (HasInside)
            {
                var org = Json.Get(ins, "origin");
                Inside = new HideoutInside { IsOwner = Json.Bool(ins, "isOwner"), OwnerName = Json.Text(ins, "ownerName"), Owner = (long)Json.Number(ins, "owner"), OriginX = Json.Int(org, "x"), OriginY = Json.Int(org, "y"), OriginZ = Json.Int(org, "z") };
            }
            var lay = Json.Get(d, "layout");
            Layout = new HideoutLayout { W = Json.Int(lay, "w"), H = Json.Int(lay, "h") };
            if (Json.Get(lay, "arrival") is List<object> ar && ar.Count >= 2) { Layout.ArrivalX = (int)(ar[0] as double? ?? 0); Layout.ArrivalY = (int)(ar[1] as double? ?? 0); }
            foreach (object t in Json.List(lay, "reserved"))
                if (t is List<object> a && a.Count >= 3 && a[2] is string nm) Layout.Reserved.Add(new KeyValuePair<KeyValuePair<int, int>, string>(new KeyValuePair<int, int>((int)(a[0] as double? ?? 0), (int)(a[1] as double? ?? 0)), nm));
            Catalogue.Clear();
            foreach (object o in Json.List(d, "catalogue"))
            {
                var r = new HideoutRow
                {
                    Key = Json.Text(o, "key"), Name = Json.Text(o, "name"), Cat = Json.Text(o, "cat"), Source = Json.Text(o, "source"), How = Json.Text(o, "how"),
                    Layer = Json.Text(o, "layer", "object"), Item = Json.Int(o, "item"), Placed = Json.Int(o, "placed"), Max = Json.Int(o, "max"), Owned = Json.Bool(o, "owned"), Block = Json.Bool(o, "block"),
                };
                foreach (object rot in Json.List(o, "rots")) r.Rots.Add(ParseParts(rot));
                if (Json.Get(o, "wallW") != null) r.WallW = ParseParts(Json.Get(o, "wallW"));
                Catalogue.Add(r);
            }
            Placed.Clear();
            foreach (object o in Json.List(d, "placed"))
                Placed.Add(new HideoutPlaced { Id = Json.Int(o, "id"), Key = Json.Text(o, "key"), X = Json.Int(o, "x"), Y = Json.Int(o, "y"), R = Math.Max(1, Json.Int(o, "r", 1)) });
            Themes.Clear();
            foreach (object o in Json.List(d, "themes"))
                Themes.Add(new HideoutTheme { Key = Json.Text(o, "key"), Name = Json.Text(o, "name"), Desc = Json.Text(o, "desc"), How = Json.Text(o, "how"), Owned = Json.Bool(o, "owned"), Selected = Json.Bool(o, "selected"), MaxDecor = Json.Int(o, "maxDecor"), Item = Json.Int(o, "item") });
            Permissions.Clear();
            foreach (object o in Json.List(d, "permissions")) Permissions.Add(new HideoutPerm { Id = Json.Int(o, "id"), Name = Json.Text(o, "name"), Desc = Json.Text(o, "desc") });
            Categories.Clear();
            foreach (object o in Json.List(d, "categories")) if (o is string s) Categories.Add(s); else if (o is Dictionary<string, object>) Categories.Add(Json.Text(o, "key"));
            Loaded = true;
            if (Json.Bool(d, "open")) Visible = true;
            Changed();
        }

        public void Clear()
        {
            Visible = false; Loaded = false; HasInside = false; Catalogue.Clear(); Placed.Clear(); Themes.Clear(); Permissions.Clear(); Categories.Clear();
            Friends = new List<HideoutVisit>(); Recent = new List<HideoutVisit>(); ShowLikes = new List<HideoutVisit>(); ShowVisits = new List<HideoutVisit>();
        }
    }
}
