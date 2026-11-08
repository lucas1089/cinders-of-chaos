// World, map and item utilities (track O): map markers, map overlay, minimap sync, Go to NPC, waystone, Town Portal, hideout, tile overlays, weather, name plates,
// Auto Loot, pouches and the Auto Seller, Orb Exchange, Gambler, Ember Cache, Unveil, Item Finder, Loadouts, Spell Supports, Chaos Pact, Candlemarks.
// Each model is driven through the extended opcode layer with the messages of the server scripts, and the packets it sends are read back.
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;

namespace Chaos.Core.Tests
{
    static class WorldTests
    {
        sealed class Rig
        {
            public readonly ExtOpcodes Ext = new ExtOpcodes();
            public readonly List<byte[]> Sent = new List<byte[]>();
            public double Now;
            public Rig() { Ext.Transmit = p => Sent.Add(p); }
            public void In(byte op, string json) => Ext.Receive(op, ExtOpcodes.ToWire(json));
            public void Text(byte op, string text) => Ext.Receive(op, text);
            public string Last() { var p = Sent[Sent.Count - 1]; return p[1] + " " + Encoding.UTF8.GetString(p, 4, p.Length - 4); }
            public string LastBody() { var p = Sent[Sent.Count - 1]; return Encoding.UTF8.GetString(p, 4, p.Length - 4); }
        }

        public static void Run(Action<bool, string> check)
        {
            Loc.Set("en");
            Marks(check);
            Overlay(check);
            Travel(check);
            Waystone(check);
            Portal(check);
            Hideout(check);
            Tiles(check);
            Weather(check);
            Plates(check);
            AutoLoot(check);
            Pouches(check);
            Orbs(check);
            Gamble(check);
            Ember(check);
            Unveil(check);
            Finder(check);
            Loadouts(check);
            Supports(check);
            Pact(check);
            Candles(check);
            Texts(check);
        }

        // ---------------------------------------------------------------------------------------------- map markers
        static void Marks(Action<bool, string> check)
        {
            var r = new Rig();
            var m = new MapMarkState(r.Ext) { Clock = () => r.Now, SelfId = () => 5 };
            m.Hello();
            check(r.Last() == "153 {\"action\":\"hello\",\"data\":{\"party\":true,\"poi\":true,\"npcmarks\":true}}", "markers: hello carries the three switches");
            r.In(153, "{\"action\":\"party\",\"data\":{\"m\":[{\"i\":5,\"n\":\"Me\",\"x\":1,\"y\":1,\"z\":7},{\"i\":9,\"n\":\"Ana\",\"x\":100,\"y\":200,\"z\":7,\"p\":80},{\"i\":3,\"n\":\"Bob\",\"x\":10,\"y\":10,\"z\":8}]}}");
            check(m.Party.Count == 2 && !m.Party.ContainsKey(5), "markers: party list without the viewer");
            check(m.SlotOf(9) == 1 && m.SlotOf(3) == 2, "markers: colour slots by order");
            r.Now = 1000;
            r.In(153, "{\"action\":\"party\",\"data\":{\"m\":[{\"i\":3,\"n\":\"Bob\",\"x\":10,\"y\":10,\"z\":8},{\"i\":9,\"n\":\"Ana\",\"x\":101,\"y\":200,\"z\":7}]}}");
            check(m.SlotOf(9) == 1 && m.SlotOf(3) == 2, "markers: a member keeps its colour");
            MapMarkMath.Glide(m.Anim[9], 1400, out double gx, out _, out bool done);
            check(Math.Abs(gx - 100.5) < 1e-6 && !done, "markers: a pin glides half way after 400 ms of 800");
            MapMarkMath.Glide(m.Anim[9], 1900, out gx, out _, out done);
            check(gx == 101 && done, "markers: the glide arrives");
            var far = MapMarkMath.Retarget(m.Anim[9], 500, 500, 7, 2000);
            check(far.Jump, "markers: a far step is a jump");
            check(MapMarkMath.FloorArrow(6, 7) == "up" && MapMarkMath.FloorArrow(8, 7) == "down" && MapMarkMath.FloorArrow(7, 7) == "", "markers: floor arrows");
            check(MapMarkMath.Dir8(1, 0) == "e" && MapMarkMath.Dir8(0, -1) == "n" && MapMarkMath.Dir8(-1, 1) == "sw" && MapMarkMath.Dir8(0, 0) == "", "markers: eight directions (y grows down)");
            bool inside = MapMarkMath.Edge(500, 50, 0, 0, 100, 100, 7, out double ex, out double ey, out string dir);
            check(!inside && ex == 93 && ey == 50 && dir == "e", "markers: a far point is clamped to the edge");
            check(MapMarkMath.Edge(50, 50, 0, 0, 100, 100, 7, out _, out _, out _), "markers: a point inside stays");
            check(MapMarkMath.MemberText(m.Party[9], new Pos(100, 200, 7), true) == "Ana, 1 square east", "markers: hover text of a member");
            check(MapMarkMath.MemberText(new PartyMark { Name = "Bo", X = 10, Y = 10, Z = 5 }, new Pos(10, 10, 7), true) == "Bo, 2 floors up", "markers: floors in the hover text");

            r.In(153, "{\"action\":\"poi\",\"data\":{\"marks\":[{\"k\":\"temple\",\"x\":10,\"y\":10,\"z\":7,\"n\":\"Temple\"},{\"k\":\"alien\",\"x\":1,\"y\":1,\"z\":7},{\"k\":\"npc\",\"x\":12,\"y\":10,\"z\":7},{\"k\":\"boss\",\"x\":3,\"y\":3}]}}");
            check(m.Pois.Count == 3 && m.Floors.ContainsKey(7) && m.Floors[7].Count == 2, "markers: poi list by floor, unknown kinds left out, a mark without z dropped");
            r.In(153, "{\"action\":\"reveal\",\"data\":{\"marks\":[{\"k\":\"temple\",\"x\":10,\"y\":10,\"z\":7},{\"k\":\"depot\",\"x\":11,\"y\":10,\"z\":7}]}}");
            check(m.Pois.Count == 4, "markers: reveal adds only new marks");
            r.In(153, "{\"action\":\"quests\",\"data\":{\"marks\":[{\"k\":\"questgoal\",\"x\":20,\"y\":20,\"z\":7},{\"k\":\"npc\",\"x\":21,\"y\":21,\"z\":7}]}}");
            check(m.Floors[7].Count == 4, "markers: only questgoal marks come from the goals");
            m.Settings.Cats["npc"] = false;
            var vis = MapMarkMath.Visible(m.Floors, 7, 0, 0, 50, 50, m.Settings, 0);
            check(vis.All(x => x.Kind != "npc") && vis.Count == 3, "markers: a category switched off hides its kinds");
            var nearest = MapMarkMath.Visible(m.Floors, 7, 0, 0, 50, 50, new MapMarkSettings(), 2);
            check(nearest.Count == 2, "markers: the limit keeps the nearest to the centre");
            m.SetKind("party", false);
            check(r.Last() == "153 {\"action\":\"set\",\"data\":{\"party\":false}}" && m.Party.Count == 0, "markers: turning a kind off tells the server and clears it");
            r.In(153, "{\"action\":\"party\",\"data\":{\"m\":[{\"i\":9,\"n\":\"Ana\",\"x\":1,\"y\":1,\"z\":7}]}}");
            check(m.Party.Count == 0, "markers: party messages are ignored while it is off");

            r.In(153, "{\"action\":\"npcmarks\",\"data\":{\"full\":true,\"set\":[{\"n\":\"Odrenna\",\"m\":\"new\"},{\"n\":\"Bad\",\"m\":\"zzz\"},{\"n\":\"Tomas\",\"m\":\"ready\"}]}}");
            check(m.Npc.Count == 2 && m.Npc.MarkFor("odrenna") == "new" && m.Npc.MarkFor("TOMAS") == "ready", "npc marks: set by lower case name, unknown kinds dropped");
            r.In(153, "{\"action\":\"npcmarks\",\"data\":{\"clear\":[\"Odrenna\"],\"set\":[{\"n\":\"Lia\",\"m\":\"locked\"}]}}");
            check(m.Npc.MarkFor("Odrenna") == "" && m.Npc.MarkFor("Lia") == "locked" && m.Npc.Count == 2, "npc marks: a difference clears and sets");
            check(NpcMarks.Glyph("ready") == "?" && NpcMarks.Glyph("new") == "!" && NpcMarks.GlyphColor("locked") == "#9a9a9a", "npc marks: glyphs and colours");
            var many = new StringBuilder("{\"action\":\"npcmarks\",\"data\":{\"full\":true,\"set\":[");
            for (int i = 0; i < 60; i++) many.Append((i > 0 ? "," : "") + "{\"n\":\"n" + i + "\",\"m\":\"new\"}");
            r.In(153, many + "]}}");
            check(m.Npc.Count == NpcMarks.Max, "npc marks: at most 40 are kept");

            var slots = new Dictionary<int, int>();
            MapMarkMath.AssignColors(slots, new[] { 1, 2, 3 });
            MapMarkMath.AssignColors(slots, new[] { 1, 3, 4 });
            check(slots[4] == 2 && slots[3] == 3, "markers: a new member takes the lowest free slot");
        }

        // ---------------------------------------------------------------------------------------------- map overlay and minimap sync
        static void Overlay(Action<bool, string> check)
        {
            var r = new Rig();
            var o = new MapOverlayState(r.Ext);
            o.Show(true);
            check(r.Last() == "245 {\"action\":\"watch\",\"data\":{\"on\":true}}" && o.Shown, "overlay: opening tells the server to watch");
            r.In(245, "{\"action\":\"marks\",\"data\":{\"marks\":[{\"k\":\"party\",\"x\":1,\"y\":1,\"z\":7},{\"k\":\"temple\",\"x\":2,\"y\":2,\"z\":7},{\"k\":\"boss\",\"x\":3,\"y\":3,\"z\":7},{\"k\":\"temple\",\"x\":4,\"y\":4,\"z\":6},{\"k\":\"zzz\",\"x\":5,\"y\":5,\"z\":7}]}}");
            check(o.VisibleMarks(7).Count == 3, "overlay: marks of the floor with a known kind");
            o.Settings.Town = false;
            check(o.VisibleMarks(7).Count == 2, "overlay: a category switched off hides its kinds");
            check(MapOverlayState.StepOpacity(0.6, 0.1) == 0.7 && MapOverlayState.StepOpacity(0.2, -0.1) == 0.2 && MapOverlayState.StepOpacity(1.0, 0.1) == 1.0, "overlay: opacity steps of 0.1 between 0.2 and 1");
            check(MapOverlayState.ClampZoom(9) == 4 && MapOverlayState.ClampZoom(-3) == 0 && MapOverlayState.PixelsPerTile(3) == 8 && MapOverlayState.ZoomLabel(2) == "x4", "overlay: zoom 0..4 is 2^zoom pixels");
            check(MapOverlayState.Percent(0.6) == "60%", "overlay: opacity percent");
            MapOverlayState.DragPan(0, 0, 40, -20, 2, out double px, out double py);
            check(px == -10 && py == 5, "overlay: dragging moves the map with the mouse");
            MapOverlayState.KeyPan(0, 0, 1, 0, 2, 48, out px, out py);
            check(px == 12 && py == 0, "overlay: a key pans about 48 pixels");
            MapOverlayState.ZoomToward(0, 0, 2, 3, 80, 0, out px, out py);
            check(Math.Abs(px - 10) < 1e-9, "overlay: zooming toward the cursor keeps its map point");
            px = 9999; py = -9999; MapOverlayState.ClampPan(ref px, ref py);
            check(px == 512 && py == -512 && MapOverlayState.IsPanned(1, 0) && !MapOverlayState.IsPanned(0.01, 0), "overlay: pan limit and the panned test");
            check(MapOverlayState.WheelAction(true, true, false) == "opacity" && MapOverlayState.WheelAction(false, true, false) == "zoom" && MapOverlayState.WheelAction(false, false, true) == "zoom" && MapOverlayState.WheelAction(false, false, false) == "",
                  "overlay: a plain wheel turn belongs to the game map");
            check(MapOverlayState.StartsPan(true, true, false) && !MapOverlayState.StartsPan(true, false, false) && !MapOverlayState.StartsPan(true, true, true), "overlay: Shift + middle button pans");
            MapOverlayState.CornerSize(1000, 700, out int cw, out int ch);
            check(cw == 320 && ch == 252, "overlay: corner box size from the panel");
            var cleared = new List<string>();
            o.ClearArea = (x1, y1, x2, y2, z) => cleared.Add(x1 + "," + y1 + "," + x2 + "," + y2 + "," + z);
            o.PanX = 5;
            r.In(245, "{\"action\":\"rift\",\"data\":{\"id\":7,\"x1\":100,\"y1\":100,\"x2\":140,\"y2\":130,\"z\":9}}");
            check(cleared.Count == 1 && cleared[0] == "100,100,140,130,9" && o.PanX == 0, "overlay: a rift run clears its square and re-centres");
            r.In(245, "{\"action\":\"rift\",\"data\":{\"id\":7,\"x1\":100,\"y1\":100,\"x2\":140,\"y2\":130,\"z\":9}}");
            check(cleared.Count == 1, "overlay: the same run is cleared once");
            r.In(245, "{\"action\":\"rift\",\"data\":{\"id\":8,\"x1\":0,\"y1\":0,\"x2\":900,\"y2\":10,\"z\":9}}");
            check(cleared.Count == 1, "overlay: a square over 512 tiles is refused");
            check(MapOverlayState.ReopenAfterDeath("Ana", 1000, "Ana", 100000) && !MapOverlayState.ReopenAfterDeath("Ana", 1000, "Ana", 200000) && !MapOverlayState.ReopenAfterDeath("Ana", 1000, "Bob", 2000) && !MapOverlayState.ReopenAfterDeath("", 0, "Ana", 5),
                  "overlay: reopens after a death for the same character within two minutes");
            o.Show(false);
            check(r.Last() == "245 {\"action\":\"watch\",\"data\":{\"on\":false}}" && o.Marks.Count == 0, "overlay: closing stops the watch and drops the marks");

            // minimap sync
            check(MinimapSyncLogic.Remember(true, false) && MinimapSyncLogic.Remember(false, true) && !MinimapSyncLogic.Remember(false, false), "minimap sync: a closed window is not remembered");
            var p = MinimapSyncLogic.Plan("start", true, false, true, false);
            check(p.ExitFullMap && p.Restore && p.Recentre && p.ConsumeWant, "minimap sync: a full map from the last session closes, the window comes back, the camera recentres");
            p = MinimapSyncLogic.Plan("teleport", true, true, true, true);
            check(!p.ExitFullMap && !p.Restore && !p.Recentre && p.ConsumeWant, "minimap sync: a teleport keeps a full map view");
            p = MinimapSyncLogic.Plan("start", false, false, false, true);
            check(!p.Restore && !p.ConsumeWant, "minimap sync: a window the player closed stays closed");
            check(MinimapSyncLogic.ValidPos(100, 100, 7) && !MinimapSyncLogic.ValidPos(70000, 1, 7) && !MinimapSyncLogic.ValidPos(1, 1, 16), "minimap sync: valid map positions");
        }

        // ---------------------------------------------------------------------------------------------- travel
        static void Travel(Action<bool, string> check)
        {
            var r = new Rig();
            var t = new NpcTravel(r.Ext) { Clock = () => r.Now };
            check(NpcTravel.Valid("stash") && !NpcTravel.Valid("nope") && !NpcTravel.Valid(null) && NpcTravel.Keys.Length == 19, "npc travel: the 19 keys of the server table");
            check(NpcTravel.FactionKey("choir") == "faction_choir" && NpcTravel.FactionKey("zzz") == "" && NpcTravel.FactionKey("") == "", "npc travel: faction keys");
            r.Now = 5000;
            check(t.Travel("banker") && r.Last() == "121 {\"action\":\"travel\",\"data\":{\"k\":\"banker\"}}", "npc travel: sends travel {k}");
            r.Now = 5500;
            int n = r.Sent.Count;
            check(!t.Travel("stash") && r.Sent.Count == n, "npc travel: a second request within a second is dropped");
            r.Now = 6200;
            check(t.Travel("stash"), "npc travel: later requests go");
            check(!t.Travel("bad") && NpcTravel.Message("bad") == null, "npc travel: an unknown key sends nothing");
            check(NpcTravel.TooSoon(1.5, 1.0) && !NpcTravel.TooSoon(2.5, 1.0) && !NpcTravel.TooSoon(1, -1), "npc travel: the gap rule");
        }

        static void Waystone(Action<bool, string> check)
        {
            var r = new Rig();
            var w = new WaystoneState(r.Ext);
            // raw JSON, no data wrapper
            r.In(202, "{\"action\":\"show\",\"tiers\":[{\"clientId\":27190,\"look\":27190,\"tier\":2,\"count\":3,\"level\":300},{\"clientId\":30001,\"look\":30001,\"tier\":7,\"count\":0,\"level\":1100},{\"clientId\":1,\"tier\":99,\"count\":1}],\"pick\":27191}");
            check(w.Visible && w.Rows.Count == 7, "waystone: the six base tiers and a listed tier 7");
            check(w.Rows[1].Count == 3 && w.Rows[1].Level == 300 && w.Rows[1].Usable && !w.Rows[0].Usable && w.Rows[0].Count == 0, "waystone: counts decide what is usable");
            check(w.Rows[6].Roman == "VII" && !w.Rows[6].Usable && w.Rows[6].Level == 1100, "waystone: tier VII from the server list");
            check(w.Selected == 2, "waystone: the picked tier is selected first");
            check(WaystoneState.LevelText(w.Rows[1]) == "level 300" && WaystoneState.CountText(w.Rows[1]) == "3 held" && WaystoneState.CountText(w.Rows[0]) == "none", "waystone: level and count texts");
            check(WaystoneState.SourceText(w.Rows[0]) == "None held. Tier I drops from monsters anywhere." && WaystoneState.SourceText(w.Rows[3]).Contains("tier II to IV") && WaystoneState.SourceText(w.Rows[1]) == "", "waystone: where a tier not held comes from");
            check(WaystoneState.FirstRow(w.Rows, 0) == 1, "waystone: the lowest tier held is selected without a pick");
            check(w.Teleport(1) && r.LastBody() == "{\"action\":\"teleport\",\"clientId\":27190}", "waystone: teleport is sent flat");
            int n = r.Sent.Count;
            check(!w.Teleport(0) && r.Sent.Count == n, "waystone: a tier not held sends nothing");
            r.In(202, "{\"action\":\"choice_show\",\"choices\":[{\"id\":2,\"text\":\"Ember\"},{\"id\":0,\"text\":\"Default\"},{\"id\":-1,\"text\":\"bad\"}]}");
            check(w.ChoicesVisible && w.Choices.Count == 2 && w.Choices[0].Id == 0, "waystone: pad looks sorted, bad ids dropped");
            w.ApplyChoice(2);
            check(r.LastBody() == "{\"action\":\"choice_apply\",\"choiceId\":2}", "waystone: choice_apply");
            r.In(202, "{\"action\":\"teleport_error\",\"text\":\"Not here.\"}");
            check(w.Status == "Not here.", "waystone: an error shows its text");
            r.In(202, "{\"action\":\"teleport_done\"}");
            check(!w.Visible && w.Status.Contains("60 seconds"), "waystone: portals open closes the window");
            r.In(202, "{\"action\":\"show\"}");
            check(w.Rows.Count == 6 && w.Rows.All(x => x.Count < 0 && x.Usable), "waystone: a server without counts leaves the base rows usable");
        }

        static void Portal(Action<bool, string> check)
        {
            var r = new Rig();
            var p = new TownPortalState(r.Ext);
            string castName = ""; double castMs = 0; string castEnd = "";
            p.CastStarted = (n, ms) => { castName = n; castMs = ms; };
            p.CastEnded = res => castEnd = res;
            r.In(239, "{\"action\":\"state\",\"data\":{\"open\":true,\"selected\":\"basic\",\"cooldown\":10,\"cooldownTotal\":60,\"styles\":[{\"id\":\"basic\",\"name\":\"Basic\",\"route\":\"\",\"owned\":true,\"selected\":true,\"clientItem\":1387},{\"id\":\"gold\",\"name\":\"Gold\",\"route\":\"store\",\"price\":30,\"owned\":false}, 5]}}");
            check(p.Visible && p.Styles.Count == 2 && p.SelectedId == "basic" && p.Cooldown == 10, "portal: state with two styles, a junk row dropped");
            check(TownPortalState.RouteText(p.Styles[1]) == "Store - 30 coins" && TownPortalState.RouteText(p.Styles[0]) == "Every character", "portal: route texts");
            check(p.StatusText() == "Town Portal ready in 10 s." && !p.CanCast, "portal: the cooldown shows and blocks Cast");
            p.Tick(0); p.Tick(3000);
            check(p.Cooldown == 7, "portal: the cooldown counts down once a second while shown");
            p.Cast();
            check(r.Last() == "239 {\"action\":\"cast\",\"data\":{}}", "portal: cast");
            p.Pick("gold"); p.SelectCurrent();
            check(r.Last() == "239 {\"action\":\"select\",\"data\":{\"id\":\"gold\"}}", "portal: select {id}");
            r.In(239, "{\"action\":\"cast\",\"data\":{\"ms\":2500}}");
            check(castName == "Town Portal" && castMs == 2500, "portal: the cast goes to the cast bar");
            r.In(239, "{\"action\":\"castEnd\",\"data\":{\"result\":\"moved\"}}");
            check(castEnd == "moved", "portal: castEnd carries the result");
            p.Toggle();
            check(!p.Visible, "portal: toggle closes");
            p.Toggle();
            check(p.Visible && r.Last() == "239 {\"action\":\"open\",\"data\":{}}", "portal: toggle opens by asking the server");
        }

        static void Hideout(Action<bool, string> check)
        {
            var r = new Rig();
            var h = new HideoutState(r.Ext);
            string state = "{\"action\":\"state\",\"data\":{\"open\":true,\"hideout\":{\"count\":1,\"max\":5,\"likes\":4,\"visits\":9,\"perm\":1,\"themeName\":\"Cellar\"},"
                + "\"inside\":{\"isOwner\":true,\"owner\":77,\"ownerName\":\"Ana\",\"origin\":{\"x\":1000,\"y\":2000,\"z\":7}},"
                + "\"layout\":{\"w\":6,\"h\":6,\"arrival\":[1,1],\"reserved\":[[1,1,\"arrival\"],[6,3,\"depot\"],[3,6,\"stash\"]]},"
                + "\"themes\":[{\"key\":\"cellar\",\"name\":\"Cellar\",\"owned\":true,\"selected\":true,\"maxDecor\":5}],\"permissions\":[{\"id\":1,\"name\":\"Friends\",\"desc\":\"VIPs\"}],\"categories\":[\"furniture\",\"banner\"],"
                + "\"catalogue\":[{\"key\":\"chair\",\"name\":\"Chair\",\"cat\":\"furniture\",\"source\":\"default\",\"layer\":\"object\",\"item\":100,\"placed\":0,\"max\":2,\"owned\":true,\"rots\":[[[0,0,100]],[[0,0,101]]]},"
                + "{\"key\":\"wall\",\"name\":\"Block\",\"cat\":\"furniture\",\"source\":\"store\",\"layer\":\"object\",\"block\":true,\"placed\":0,\"max\":9,\"owned\":true,\"rots\":[[[0,0,1],[1,0,1],[2,0,1]]]},"
                + "{\"key\":\"rug\",\"name\":\"Rug\",\"cat\":\"furniture\",\"source\":\"store\",\"layer\":\"floor\",\"placed\":1,\"max\":1,\"owned\":true,\"rots\":[[[0,0,5]]]},"
                + "{\"key\":\"flag\",\"name\":\"Flag\",\"cat\":\"banner\",\"source\":\"faction\",\"layer\":\"wall\",\"how\":\"Join a faction\",\"placed\":0,\"max\":2,\"owned\":false,\"rots\":[[[0,0,7]]],\"wallW\":[[0,0,8]]}],"
                + "\"placed\":[{\"id\":11,\"key\":\"rug\",\"x\":2,\"y\":2,\"r\":1}]}}";
            r.In(192, state);
            check(h.Visible && h.Loaded && h.Catalogue.Count == 4 && h.Placed.Count == 1 && h.Layout.W == 6 && h.HasInside && h.Inside.IsOwner, "hideout: state parsed");
            check(h.CountText() == "Cellar - 1 / 5 decorations", "hideout: counter text");
            var f = HideoutState.Filter(h.Catalogue, "all", "all", false, "");
            check(f[0].Owned && f[f.Count - 1].Key == "flag", "hideout: unlocked first");
            check(HideoutState.Filter(h.Catalogue, "banner", "all", false, "").Count == 1 && HideoutState.Filter(h.Catalogue, "all", "store", false, "").Count == 2 && HideoutState.Filter(h.Catalogue, "all", "all", true, "").Count == 3 && HideoutState.Filter(h.Catalogue, "all", "all", false, "  ru ").Count == 1, "hideout: category, source, owned and search filters");
            check(HideoutState.SubText(h.RowOf("chair")) == "0 / 2 placed" && HideoutState.SubText(h.RowOf("flag")) == "Locked - Join a faction", "hideout: row sub texts");
            string why;
            check(h.CanPlace(h.RowOf("chair"), out why) && !h.CanPlace(h.RowOf("flag"), out why) && why == "Locked: Join a faction" && !h.CanPlace(h.RowOf("rug"), out why) && why == "At most 1 of it.", "hideout: who may place what");
            check(HideoutState.RotCount(h.RowOf("chair")) == 2 && HideoutState.NextRot(h.RowOf("chair"), 2) == 1 && HideoutState.NextRot(h.RowOf("chair"), 1, -1) == 2 && HideoutState.RotCount(h.RowOf("flag")) == 1, "hideout: rotations wrap");
            check(HideoutState.Parts(h.RowOf("flag"), 1, "w")[0].Id == 8 && HideoutState.Parts(h.RowOf("flag"), 1, "n")[0].Id == 7, "hideout: a wall piece has its own west look");
            int gx, gy;
            check(h.ToGrid(1003, 2004, 7, out gx, out gy) && gx == 3 && gy == 4 && !h.ToGrid(1003, 2004, 6, out _, out _) && !h.ToGrid(1010, 2004, 7, out _, out _), "hideout: grid position of a world tile");
            check(HideoutState.WallSide(h.Layout, 3, 0) == "n" && HideoutState.WallSide(h.Layout, 0, 2) == "w" && HideoutState.WallSide(h.Layout, 3, 3) == "", "hideout: wall sides");
            check(h.Check(h.RowOf("chair"), 3, 3, 1, 0, out why), "hideout: a free floor tile fits");
            check(!h.Check(h.RowOf("chair"), 6, 3, 1, 0, out why) && why == "That tile is kept free.", "hideout: a fixture tile is kept free");
            check(!h.Check(h.RowOf("chair"), 0, 3, 1, 0, out why) && why == "Place it on the floor.", "hideout: the wall is not floor for an object");
            check(!h.Check(h.RowOf("rug"), 2, 2, 1, 0, out why) && why == "At most 1.", "hideout: one rug only");
            check(h.Check(h.RowOf("rug"), 2, 2, 1, 11, out why), "hideout: moving the rug ignores itself");
            check(h.Check(h.RowOf("flag"), 3, 0, 1, 0, out why) && !h.Check(h.RowOf("flag"), 3, 3, 1, 0, out why) && why == "Hang it on the north or the west wall.", "hideout: wall decorations go on the north or west wall");
            check(!h.Check(h.RowOf("wall"), 1, 1, 1, 0, out why), "hideout: a piece over the arrival tile does not fit");
            // three blocks in a row beside the arrival tile still leave a way round
            check(h.Check(h.RowOf("wall"), 2, 4, 1, 0, out why), "hideout: a three block piece with a way round fits");
            var reach = new HideoutLayout { W = 5, H = 3, ArrivalX = 1, ArrivalY = 1 };
            reach.Reserved.Add(new KeyValuePair<KeyValuePair<int, int>, string>(new KeyValuePair<int, int>(1, 1), "arrival"));
            reach.Reserved.Add(new KeyValuePair<KeyValuePair<int, int>, string>(new KeyValuePair<int, int>(5, 2), "dummy1"));
            var solid = new HashSet<string> { "3,1", "3,2", "3,3" };
            check(!HideoutState.ReachOk(reach, solid, out string what) && what == "dummy1", "hideout: a wall of blocks cuts the dummy off");
            check(HideoutState.ReachOk(reach, new HashSet<string> { "3,1", "3,2" }, out what), "hideout: a gap keeps the way");
            check(HideoutState.VisitLine(new HideoutVisit { Name = "Bo", Theme = "Cellar", Why = "friend", Likes = 3, Visits = 8 }) == "Bo  -  Cellar  -  VIP  -  3 likes  -  8 visits", "hideout: visit line");
            h.Place("chair", 3, 3, 2);
            check(r.Last() == "192 {\"action\":\"place\",\"data\":{\"key\":\"chair\",\"x\":3,\"y\":3,\"r\":2}}", "hideout: place {key, x, y, r}");
            h.Move(11, 4, 4, 1);
            check(r.Last() == "192 {\"action\":\"move\",\"data\":{\"id\":11,\"x\":4,\"y\":4,\"r\":1}}", "hideout: move {id, x, y, r}");
            h.Remove(11); check(r.Last() == "192 {\"action\":\"remove\",\"data\":{\"id\":11}}", "hideout: remove {id}");
            h.Like(); check(r.Last() == "192 {\"action\":\"like\",\"data\":{\"owner\":77}}", "hideout: like {owner}");
            h.Visit(123456789); check(r.Last() == "192 {\"action\":\"visit\",\"data\":{\"guid\":123456789}}", "hideout: visit {guid}");
            h.Theme("cellar"); h.SetPerm(2);
            check(r.Last() == "192 {\"action\":\"perm\",\"data\":{\"level\":2}}", "hideout: perm {level}");
            r.In(192, "{\"action\":\"visits\",\"data\":{\"friends\":[{\"guid\":5,\"name\":\"Bo\",\"why\":\"friend\",\"online\":true}],\"showcase\":{\"likes\":[{\"guid\":6,\"name\":\"Cy\",\"likes\":9}],\"visits\":[]},\"recent\":[]}}");
            check(h.Friends.Count == 1 && h.Friends[0].Online && h.ShowLikes[0].Likes == 9 && h.ShowVisits.Count == 0, "hideout: visits lists");
            r.In(192, "{\"action\":\"result\",\"data\":{\"ok\":false,\"text\":\"Nope\"}}");
            check(h.ResultText == "Nope" && !h.ResultOk, "hideout: result text");
        }

        // ---------------------------------------------------------------------------------------------- tile overlays, weather, plates
        static void Tiles(Action<bool, string> check)
        {
            var r = new Rig();
            var t = new TileOverlays(r.Ext) { Clock = () => r.Now };
            t.Hello();
            check(r.Last() == "156 {\"action\":\"hello\",\"data\":{}}", "tile overlays: hello");
            check(TileOverlays.FormatSeconds(9) == "9" && TileOverlays.FormatSeconds(45) == "45" && TileOverlays.FormatSeconds(65) == "1:05" && TileOverlays.FormatSeconds(720) == "12:00" && TileOverlays.FormatSeconds(-3) == "0", "tile overlays: seconds text");
            check(TileOverlays.SecondsLeft(1) == 1 && TileOverlays.SecondsLeft(1000) == 1 && TileOverlays.SecondsLeft(1001) == 2 && TileOverlays.SecondsLeft(0) == 0, "tile overlays: seconds round up");
            var pos = new Pos(100, 100, 7);
            var rec = t.FieldAdd(pos, 2128, 1000, true);
            check(rec != null && rec.Total == 20000 && rec.Name == "magic wall" && t.FieldAdd(pos, 2128, 1100, true) == rec, "tile overlays: a magic wall starts a 20 s timer, twice on a tile counts once");
            check(TileOverlays.FieldText(rec, 4000) == "17" && TileOverlays.FieldColor(rec, 4000) == "#ffffff" && TileOverlays.FieldColor(rec, 17000) == "#ffa040", "tile overlays: the text counts down, orange in the last 5 s");
            check(TileOverlays.FieldText(rec, 25000) == "~" && TileOverlays.FieldColor(rec, 25000) == "#bfb6a6", "tile overlays: a field outliving its time shows ~");
            var unknown = t.FieldAdd(new Pos(101, 100, 7), 2128, 1000, false);
            check(TileOverlays.FieldText(unknown, 5000) == "~", "tile overlays: a field that came with its tile shows ~");
            check(t.FieldAdd(pos, 55555, 0, true) == null, "tile overlays: an id that is no timed field is ignored");
            t.FieldRemove(pos, 2128, 2000);
            check(t.FieldAdd(pos, 2128, 2100, true) == rec, "tile overlays: a tile rebuilt within 250 ms keeps its timer");
            t.FieldRemove(pos, 2128, 2200);
            var again = t.FieldAdd(pos, 2128, 3000, true);
            check(again != rec && again.Start == 3000, "tile overlays: later it is a new field");
            var dropped = t.FieldSweep(3000, new Pos(500, 500, 7));
            check(dropped.Count == 2 && t.Recs.Count == 0, "tile overlays: records out of view are dropped");

            // the scan of a world
            var dat = DatFile.Parse(Program.SyntheticDat());
            var w = new World(dat);
            var me = new Creature { Id = 1, Name = "Me", Position = new Pos(100, 100, 7) };
            w.Creatures[1] = me; w.PlayerId = 1;
            w.Center = me.Position;
            var tile = w.GetOrMake(new Pos(102, 100, 7));
            var other = w.GetOrMake(new Pos(103, 100, 7));
            t.Scan(w, 10000);
            check(t.Recs.Count == 0, "tile overlays: an empty world has no fields");
            tile.Things.Add(new Thing { Item = new Item { Id = 2128 } });
            t.Scan(w, 10250);
            check(t.Recs.Count == 1 && TileOverlays.FieldText(t.Recs.Values.First(), 10250) == "20", "tile overlays: a field added to a known tile starts at once");
            var fresh = w.GetOrMake(new Pos(104, 100, 7));
            fresh.Things.Add(new Thing { Item = new Item { Id = 2128 } });
            t.Scan(w, 10500);
            check(t.Recs.Count == 2 && t.Recs.Values.Any(x => x.Pos.X == 104 && x.Start < 0), "tile overlays: a field on a tile that is new to the scan shows ~");
            tile.Things.Clear();
            t.Scan(w, 11000);
            check(t.Recs.Count == 1, "tile overlays: a removed field leaves");

            // server bars
            var store = new Dictionary<string, TileBar>();
            var del = new List<string>();
            var set = TileOverlays.ApplyBars(store, Json.Parse("{\"s\":[{\"i\":\"b1\",\"p\":[10,20,7],\"n\":\"Brazier\",\"c\":\"#FF0000\",\"v\":0.5},{\"i\":\"b2\",\"p\":[10,20,7],\"n\":\"Door\",\"l\":30000,\"t\":60000},{\"i\":\"\",\"p\":[1,1,1]},{\"i\":\"bad\",\"p\":[1,2]},{\"i\":\"bad2\",\"p\":[70000,2,3]}],\"d\":[\"gone\"]}"), 1000, del);
            check(set.Count == 2 && set[0] == "b1" && store["b1"].Color == "#ff0000" && TileOverlays.BarProgress(store["b1"], 0) == 0.5, "tile overlays: bars parsed, junk dropped, colour normalised");
            check(TileOverlays.BarProgress(store["b2"], 16000) == 0.25 && TileOverlays.BarText(store["b2"], 16000) == "Door 15" && TileOverlays.BarText(store["b1"], 0) == "Brazier", "tile overlays: a countdown bar counts itself down");
            check(store["b1"].Color == "#ff0000" && TileOverlays.BarColor("red") == "#d8b45a", "tile overlays: a bad colour falls back");
            var stack = TileOverlays.Stack(store, new Pos(10, 20, 7));
            check(stack.Count == 2 && stack[0].Id == "b1", "tile overlays: bars of a tile stack by id");
            check(TileOverlays.ExpiredBars(store, 31000 + 1400).Count == 0 && TileOverlays.ExpiredBars(store, 31000 + 1600)[0] == "b2", "tile overlays: a countdown ends 1.5 s after its time");
            check(TileOverlays.FillWidth(0.5, 64) == 32 && TileOverlays.BarWidth(10) == 66 && TileOverlays.BarWidth(100) == 112 && TileOverlays.BarLift(64, 1) == 46 && TileOverlays.BarLift(64, 2) == 68, "tile overlays: bar geometry");
            r.Now = 2000;
            r.In(156, "{\"action\":\"bars\",\"data\":{\"s\":[{\"i\":\"x\",\"p\":[1,2,3],\"l\":1000}]}}");
            check(t.Bars.ContainsKey("x"), "tile overlays: a bars message fills the store");
            r.Now = 5000; t.Tick(5000);
            check(!t.Bars.ContainsKey("x"), "tile overlays: expired countdowns are dropped by the tick");
            r.In(156, "{\"action\":\"clear\",\"data\":{}}");
            check(t.Bars.Count == 0, "tile overlays: clear");
            check(FieldData.Fields.Count == 15 && FieldData.Fields[2128].Key == 20000, "tile overlays: the field table has 15 ids");
        }

        static void Weather(Action<bool, string> check)
        {
            var r = new Rig();
            var w = new WeatherState(r.Ext);
            w.Hello();
            check(r.Last() == "114 {\"action\":\"hello\",\"data\":{}}", "weather: hello");
            r.In(114, "{\"action\":\"set\",\"data\":{\"k\":\"rain\",\"i\":9,\"f\":99999,\"a\":\"embers\",\"m\":\"fire\"}}");
            check(w.Raining && w.Level == 3 && w.FadeMs == 10000 && w.Ambient == "embers" && w.Mood == "fire", "weather: rain level clamped to 3, fade to 10 s, ambient and mood read");
            var tg = w.Targets();
            check(tg["far"] == 1 && tg["mid"] == 1 && tg["near"] == 1, "weather: level 3 shows all three layers");
            r.In(114, "{\"action\":\"set\",\"data\":{\"k\":\"rain\",\"i\":1}}");
            tg = w.Targets();
            check(tg["far"] == 0.6 && tg["mid"] == 0 && w.FadeMs == 2500 && w.Ambient == "" && w.Mood == "", "weather: level 1 is a light far layer, a missing ambient and mood clear");
            r.In(114, "{\"action\":\"set\",\"data\":{\"k\":\"snow\",\"f\":0}}");
            check(!w.Raining && w.Targets().Values.All(v => v == 0), "weather: an unknown kind is no rain");
            r.In(114, "{\"action\":\"set\",\"data\":{\"k\":\"rain\",\"i\":2,\"f\":2000}}");
            w.Tick(0);
            w.Tick(1000);
            check(Math.Abs(w.Cur["far"] - 0.5) < 1e-9 && Math.Abs(w.Cur["near"] - 0.5) < 1e-9 && w.Cur["mid"] == 0, "weather: layers fade in over the fade time");
            w.Tick(3000);
            check(w.Cur["far"] == 1, "weather: the fade ends at the target");
            w.OptionOn = false;
            check(w.Targets().Values.All(v => v == 0), "weather: the option off hides the rain");
            w.OptionOn = true; w.Covered = true;
            check(w.Targets().Values.All(v => v == 0) && w.EffectiveFadeMs() == 600, "weather: under a roof the rain fades out fast");
            check(WeatherState.Step(0.2, 1, 5000, 2500) == 1 && Math.Abs(WeatherState.Step(0.8, 0, 500, 1000) - 0.3) < 1e-9 && WeatherState.Step(0.5, 0.2, 100, 0) == 0.2, "weather: fade steps");
            WeatherState.Offset(WeatherState.RainLayers[0], 1000, 256, out int ox, out int oy);
            check(oy == 104 && ox == 108, "weather: the far layer scrolls 360 px down a second along the slant");
            WeatherState.AmbientOffset(WeatherState.AmbientLayers[0], 0, out double ax, out double ay);
            check(Math.Abs(ax) < 1e-9 && Math.Abs(ay - 3) < 1e-9, "weather: ambient drift at time 0");
            check(WeatherState.AmbientPulse(WeatherState.AmbientLayers[4], 123) == 1 && WeatherState.AmbientPulse(WeatherState.AmbientLayers[2], 0) < 1, "weather: dust does not pulse, motes do");
            r.In(114, "{\"action\":\"set\",\"data\":{\"k\":\"none\",\"a\":\"dust\",\"m\":\"ice\"}}");
            w.Covered = false;
            for (int i = 0; i < 30; i++) w.Tick(10000 + i * 200);
            check(w.AmbientCur["dust_far"] == 0.8 && w.AmbientCur["dust_near"] == 0.9 && w.AmbientCur["embers_far"] == 0, "weather: ambient layers of the kind fade to their maximum");
            check(Math.Abs(w.Grade[2] - 0.034) < 0.002, "weather: the mood tint eases to its preset");
            w.MoodTint(out float mr, out float mg, out float mb, out float ma);
            check(ma > 0 && mb > mr, "weather: the ice mood tints blue");
            check(!WeatherState.Parse("set", null, out _, out _, out _) && !WeatherState.Parse("nope", Json.Parse("{}"), out _, out _, out _), "weather: other messages are ignored");
        }

        static void Plates(Action<bool, string> check)
        {
            var r = new Rig();
            var p = new NameplateState(r.Ext) { Clock = () => r.Now };
            var list = NameplateState.Parse("5|Slayer|ff8800|Ashen|gold\nbad line\n7||zz||nosuch\n0|x|||default");
            check(list.Count == 2 && list[0].Cid == 5 && list[0].Title == "Slayer" && list[0].Color == "#ff8800" && list[0].Guild == "Ashen" && list[0].Frame == "gold", "plates: a line is cid|title|color|guild|frame");
            check(list[1].Color == "#d6c9ae" && list[1].Frame == "default" && list[1].Title == "", "plates: a bad colour and an unknown frame fall back");
            check(NameplateState.GuildText("Ashen") == "{Ashen}" && NameplateState.GuildText("") == "" && NameplateState.GuildColorFor(2) == "#e8643c" && NameplateState.GuildColorFor(0) == "#d9a441", "plates: guild text and war colour");
            check(NameplateState.FallbackText(list[0]) == "Slayer\n{Ashen}", "plates: fallback block");
            check(NameplateState.Frames.Length == 23 && NameplateState.Frames.All(NameplateState.KnownFrame) && NameplateState.Frames.All(f => NameplateState.FrameColors.ContainsKey(f)), "plates: 23 frames, each with an accent");
            var q = NameplateState.Queries(Enumerable.Range(1, 65).Select(i => (uint)(66 - i)));
            check(q.Count == 3 && q[0].StartsWith("q|1,2,3,") && q[2] == "q|61,62,63,64,65", "plates: queries of 30 sorted ids");
            r.Now = 1000;
            p.Tick(new uint[] { 9, 4 });
            check(r.Last() == "248 q|4,9" && p.Pending.Count == 2, "plates: new players are asked for in one batch");
            int n = r.Sent.Count;
            r.Now = 1300;
            p.Tick(new uint[] { 9, 4 });
            check(r.Sent.Count == n, "plates: an asked id is not asked again at once");
            r.Text(248, "9|Hero||Crew|storm");
            check(p.Cache[9].Title == "Hero" && p.Cache[9].Frame == "storm" && !p.Pending.ContainsKey(9) && p.Pending.ContainsKey(4), "plates: an answer fills the cache and ends the wait");
            r.Now = 5000;
            p.Tick(new uint[] { 9, 4 });
            check(r.Last() == "248 q|4", "plates: an unanswered query is repeated after 3 s");
            r.Now = 9000; p.Tick(new uint[] { 4 }); r.Now = 13000; p.Tick(new uint[] { 4 }); r.Now = 17000; p.Tick(new uint[] { 4 });
            check(!p.Pending.ContainsKey(4), "plates: given up after four tries");
            var visible = new Dictionary<uint, KeyValuePair<double, int>> { { 1, new KeyValuePair<double, int>(0, 1) }, { 2, new KeyValuePair<double, int>(0, 1) } };
            check(NameplateState.Retries(visible, 4, id => id == 1).SequenceEqual(new uint[] { 1 }) && visible.Count == 1, "plates: a pending id out of view is dropped");
            check(NameplateState.NeedsQuery(null, 0, false) && !NameplateState.NeedsQuery(null, 0, true) && !NameplateState.NeedsQuery(new Nameplate { At = 0 }, 100, false) && NameplateState.NeedsQuery(new Nameplate { At = 0, Stale = true }, 100, false), "plates: who needs a query");
            check(p.BeginTry(9, "ember", 100000) && p.Shown(9, 105000).Frame == "ember" && p.Shown(9, 105000).Title == "Hero" && p.Shown(9, 111000).Frame == "storm", "plates: a tried store frame lasts 10 s and keeps the title");
            check(!p.BeginTry(9, "nope", 0) && !p.BeginTry(0, "gold", 0), "plates: a bad frame or id is no try");
        }

        // ---------------------------------------------------------------------------------------------- items and economy
        static void AutoLoot(Action<bool, string> check)
        {
            var r = new Rig();
            var a = new AutoLootState(r.Ext);
            a.Sync();
            check(r.Last() == "216 {\"action\":\"sync\",\"data\":{}}", "auto loot: sync at the start");
            r.In(216, "{\"action\":\"list\",\"data\":{\"itemsTable\":[[3031,\"gold coin\"],[2160,\"crystal coin\"]],\"currentSlot\":2,\"maxSlot\":40}}");
            check(!a.Visible && a.IsOnList(3031) && !a.IsOnList(1) && a.Rows.Count == 2, "auto loot: list is kept, not shown");
            r.In(216, "{\"action\":\"open\",\"data\":{\"itemsTable\":[[3031,\"gold coin\"]],\"currentSlot\":1,\"maxSlot\":40}}");
            check(a.Visible && a.Rows.Count == 1 && a.SlotsText() == "Current Slots: 1/40", "auto loot: open shows the window");
            check(a.AddText("12345") && r.Last() == "216 {\"action\":\"add\",\"data\":{\"clientId\":12345}}", "auto loot: a number is a client id");
            check(a.AddText(" sword ") && r.Last() == "216 {\"action\":\"add\",\"data\":{\"name\":\"sword\"}}" && !a.AddText("  "), "auto loot: text is a name");
            a.RemoveName("gold coin");
            check(r.Last() == "216 {\"action\":\"remove\",\"data\":{\"name\":\"gold coin\"}}", "auto loot: remove by name");
            a.AddItem(2400);
            check(r.Last() == "216 {\"action\":\"add\",\"data\":{\"clientId\":2400,\"quiet\":true}}" && !a.AddItem(0), "auto loot: the item menu adds quietly");
            a.RemoveItem(2400);
            check(r.Last() == "216 {\"action\":\"remove\",\"data\":{\"clientId\":2400,\"quiet\":true}}", "auto loot: the item menu removes quietly");
            a.Clear();
            check(r.Last() == "216 {\"action\":\"clear\",\"data\":{}}", "auto loot: clear");
        }

        static void Pouches(Action<bool, string> check)
        {
            var r = new Rig();
            r.Now = 10000;
            var p = new PouchesState(r.Ext) { Clock = () => r.Now };
            p.Sync();
            check(r.Last() == "226 {\"action\":\"sync\",\"data\":{}}", "pouches: sync");
            r.In(226, "{\"action\":\"settings\",\"data\":{\"rules\":{\"gold\":true,\"gear\":true,\"minRarity\":7},\"ids\":{\"loot\":2854,\"orbs\":2855},\"titles\":{\"loot\":\"Loot Bag\"},\"owned\":{\"loot\":true},\"rarities\":[\"Common\",\"Uncommon\"],\"open\":true}}");
            check(p.Visible && p.Rules.Gold && p.Rules.Gear && !p.Rules.List && p.Rules.Overflow && p.Rules.MinRarity == 5, "pouches: rules normalised (overflow on by default, rarity 7 is Legendary)");
            check(PouchesState.CanonRarity(0) == 1 && PouchesState.CanonRarity(4) == 4 && PouchesState.CanonRarity(9) == 5 && PouchesState.CanonRarity(12) == 10, "pouches: rarity ids of the seven");
            check(PouchesState.RarityIndex(5) == 4 && PouchesState.RarityIndex(10) == 5 && p.RarityName(0) == "Common" && p.RarityName(3) == "Rare", "pouches: rarity names from the server, then the built-in ones");
            check(p.StatusText().StartsWith("You have a Loot Bag."), "pouches: status for an owner");
            check(p.IsLootPouch(2854, 1) && !p.IsLootPouch(2854, 0) && !p.IsLootPouch(1, 1), "pouches: the right-click hook needs the id and the lock flag");
            p.SetFlag("supplies", true);
            check(r.LastBody() == "{\"action\":\"set\",\"data\":{\"rules\":{\"list\":false,\"gold\":true,\"uniques\":false,\"gear\":true,\"supplies\":true,\"gems\":false,\"other\":false,\"overflow\":true,\"minRarity\":5}}}", "pouches: set {rules} carries every flag");
            p.SetMinRarity(3);
            check(r.LastBody().Contains("\"minRarity\":3"), "pouches: min rarity");
            // auto seller
            r.In(226, "{\"action\":\"autoseller\",\"data\":{\"unlocked\":true,\"paused\":false,\"interval\":15,\"intervals\":[5,15,30,99],\"tiers\":[{\"key\":\"rare\",\"on\":true}],\"list\":[{\"id\":1,\"name\":\"club\",\"price\":1500},{\"name\":\"axe\",\"price\":20}],\"slots\":40,\"cooldown\":30,\"cooldownMax\":30,\"last\":{\"gold\":12345,\"count\":1},\"open\":true}}");
            var s = p.Seller;
            check(p.SellerVisible && s.Unlocked && s.Interval == 15 && s.IntervalChoices.SequenceEqual(new[] { 5, 15, 30 }), "auto seller: state, intervals filtered to the allowed ones");
            check(s.Tiers.Count == 6 && s.Tiers[3].On && !s.Tiers[0].On == false, "auto seller: tiers default on for common and uncommon");
            check(s.LastSaleText() == "Last sale: 12,345 gold (1 item)." && s.ListText() == "2/40 items: club (1,500), axe (20)", "auto seller: last sale and list texts");
            check(s.CooldownLeft(10000) == 30 && s.CooldownLeft(40000) == 0 && s.SellText(5) == "Sell all (5 s)" && !s.SellEnabled(5) && s.SellEnabled(0), "auto seller: the sell cooldown counts down");
            p.Sell(); check(r.Last() == "226 {\"action\":\"sell\",\"data\":{}}", "auto seller: sell");
            p.SetTier("rare", false); check(r.LastBody() == "{\"action\":\"asrar\",\"data\":{\"tier\":\"rare\",\"on\":false}}", "auto seller: asrar {tier, on}");
            p.SetPaused(true); check(r.LastBody() == "{\"action\":\"aspause\",\"data\":{\"on\":true}}", "auto seller: aspause");
            p.SetEvery(30); check(r.LastBody() == "{\"action\":\"asevery\",\"data\":{\"minutes\":30}}", "auto seller: asevery");
            int n = r.Sent.Count; p.SetEvery(7);
            check(r.Sent.Count == n, "auto seller: a wrong interval sends nothing");
            check(p.ListRequest("add", " club ") && r.LastBody() == "{\"action\":\"aslist\",\"data\":{\"op\":\"add\",\"item\":\"club\"}}" && !p.ListRequest("add", "  ") && !p.ListRequest("zap", "x") && p.ListRequest("clear", ""), "auto seller: aslist requests");
            r.In(226, "{\"action\":\"autoseller\",\"data\":{\"unlocked\":false,\"notice\":\"Locked.\"}}");
            check(!s.Unlocked && s.LockedTip().StartsWith("Needs the Auto Seller") && s.Notice == "Locked.", "auto seller: locked state shows the needs text");
        }

        static void Orbs(Action<bool, string> check)
        {
            var r = new Rig();
            var o = new OrbExchangeState(r.Ext);
            check(OrbExchangeState.ParseAmount("1.5k") == 1500 && OrbExchangeState.ParseAmount("2m") == 2000000 && OrbExchangeState.ParseAmount("1,000") == 1000 && OrbExchangeState.ParseAmount("x") == -1 && OrbExchangeState.ParseAmount("") == -1, "orbs: amounts with k, m, b");
            check(OrbExchangeState.ParsePrice("0.25") == 0.25 && OrbExchangeState.ParsePrice("0") == -1 && OrbExchangeState.ParsePrice("-3") == -1, "orbs: prices must be positive");
            check(OrbExchangeState.Money(1234567) == "1,234,567" && OrbExchangeState.PriceText(1234.4) == "1,234" && OrbExchangeState.PriceText(12.5) == "12.5", "orbs: money text");
            check(OrbExchangeState.PriceText(0.5) == "0.5" && OrbExchangeState.PriceText(150.26) == "150.3" && OrbExchangeState.PriceText(2) == "2", "orbs: price text trims zeros");
            check(OrbExchangeState.Compact(15000) == "15k" && OrbExchangeState.Compact(2500000) == "2.5m" && OrbExchangeState.Compact(999) == "999", "orbs: compact totals");
            check(OrbExchangeState.Ago(30) == "now" && OrbExchangeState.Ago(7200) == "2h" && OrbExchangeState.TimeLeft(90000) == "1d 1h" && OrbExchangeState.TimeLeft(0) == "ending", "orbs: time texts");
            r.In(209, "{\"action\":\"meta\",\"data\":{\"orbs\":[{\"k\":\"chaos\",\"n\":\"Orb of Chaos\",\"item\":100},{\"k\":\"alter\",\"n\":\"Orbs of Alteration\",\"item\":101}],\"fees\":{\"goldBps\":500,\"orbPairGold\":1000},\"min\":{\"gold\":10,\"orb\":1},\"max\":{\"gold\":1000000,\"orb\":500},\"durations\":[1,3,7],\"defaultDuration\":3,\"gold\":5000,\"have\":{\"chaos\":4}}}");
            check(o.Base == "chaos" && r.Last() == "209 {\"action\":\"book\",\"data\":{\"base\":\"chaos\",\"quote\":\"gold\",\"seq\":1}}", "orbs: meta selects the first orb and asks for its book");
            check(o.AssetName("chaos") == "Orb of Chaos" && o.ShortName("alter") == "Alteration" && o.OrbItem("alter") == 101 && o.Quotes("chaos").SequenceEqual(new[] { "gold", "alter" }) && o.Have("chaos") == 4 && o.GoldHeld() == 5000, "orbs: names, items, quotes and wallet");
            var form = new OrbForm { Side = "sell", Qty = "2", Price = "100" };
            check(o.Form(form, "chaos", "gold", out var req, out string why, out double total, out double fee, out double pf, out double recv), "orbs: a sell form checks");
            check((double)req["giveQty"] == 2 && (string)req["give"] == "chaos" && (double)req["wantQty"] == 200 && (string)req["want"] == "gold" && (int)req["days"] == 3, "orbs: a sell gives the orb and wants gold");
            check(fee == 10 && recv == 190, "orbs: 5 percent fee on the gold the seller receives");
            form.Side = "buy"; form.Price = "33.3"; form.Qty = "3";
            check(o.Form(form, "chaos", "gold", out req, out why, out total, out fee, out pf, out recv) && total == 100 && fee == 0 && (string)req["give"] == "gold" && (double)req["giveQty"] == 100 && recv == 3, "orbs: a buy rounds the cost up and has no fee");
            form.Qty = ""; check(!o.Form(form, "chaos", "gold", out req, out why, out total, out fee, out pf, out recv) && why == "Enter how many Orb of Chaos.", "orbs: a missing amount");
            form.Qty = "1000"; check(!o.Form(form, "chaos", "gold", out req, out why, out total, out fee, out pf, out recv) && why.StartsWith("At most 500 "), "orbs: the server's maximum");
            form.Qty = "1"; form.Price = "1"; form.Side = "buy";
            check(!o.Form(form, "chaos", "gold", out req, out why, out total, out fee, out pf, out recv) && why.StartsWith("At least 10 gold"), "orbs: the server's minimum");
            form.Qty = "10"; form.Price = "2"; form.Side = "sell";
            check(o.Form(form, "chaos", "alter", out req, out why, out total, out fee, out pf, out recv) && pf == 1000, "orbs: an orb for orb order costs the placing fee");
            string book = "{\"action\":\"book\",\"data\":{\"base\":\"chaos\",\"quote\":\"gold\",\"asks\":[{\"p\":110,\"q\":5,\"n\":2,\"t\":550},{\"p\":120,\"q\":10,\"t\":1200}],\"bids\":[{\"p\":100,\"q\":20,\"n\":1,\"t\":2000}],\"last\":105,\"change\":2.5}}";
            r.In(209, book);
            var rows = OrbExchangeState.BookRows(o.Book);
            check(rows.Count == 4 && rows[0].Kind == "ask" && rows[0].P == 120 && rows[1].P == 110 && rows[2].Kind == "spread" && rows[3].Kind == "bid" && rows[2].Price == "Spread 10", "orbs: book rows are asks high to low, the spread, then bids");
            check(rows[3].Bar == 1 && rows[0].Bar == 0.5 && rows[1].Orders == "2" && rows[0].Orders == "1", "orbs: depth bars and order counts");
            check(OrbExchangeState.FromRow(rows[1], out var fr) && fr.Side == "buy" && fr.Price == "110" && fr.Qty == "5" && OrbExchangeState.FromRow(rows[3], out fr) && fr.Side == "sell" && !OrbExchangeState.FromRow(rows[2], out _), "orbs: a clicked row fills the form");
            check(OrbExchangeState.ChangeText(2.5, out string col) == "+2.5%" && col == "#6cc46c" && OrbExchangeState.ChangeText(null, out col) == "-", "orbs: change text");
            r.In(209, book.Replace("\"base\":\"chaos\"", "\"base\":\"alter\""));
            check(Json.Number(o.Book, "last") == 105, "orbs: a book for another pair is ignored");
            o.Place(req);
            check(r.Last().StartsWith("209 {\"action\":\"place\",\"data\":{\"give\":\"chaos\",\"giveQty\":10,\"want\":\"alter\",\"wantQty\":20,\"days\":3}"), "orbs: place sends the request");
            o.Cancel(42); check(r.LastBody() == "{\"action\":\"cancel\",\"data\":{\"id\":42}}", "orbs: cancel {id}");
            r.In(209, "{\"action\":\"wallet\",\"data\":{\"gold\":9,\"have\":{\"chaos\":1}}}");
            check(o.GoldHeld() == 9 && o.Have("chaos") == 1, "orbs: wallet message");
            int n = r.Sent.Count;
            r.In(209, "{\"action\":\"done\",\"data\":{\"what\":\"place\",\"text\":\"Order placed.\"}}");
            check(o.Status == "Order placed." && o.StatusGood && r.Sent.Count == n + 2, "orbs: done shows the text and refreshes the book and the wallet");
            r.In(209, "{\"action\":\"error\",\"data\":{\"text\":\"No.\"}}");
            check(o.Status == "No." && !o.StatusGood, "orbs: error text");
            r.In(209, "{\"action\":\"mine\",\"data\":{\"open\":[{\"id\":1,\"give\":\"chaos\",\"giveQty\":10,\"want\":\"gold\",\"wantQty\":1000,\"given\":5,\"got\":500,\"state\":\"active\",\"left\":7200}],\"fills\":[{\"ago\":120,\"gave\":\"chaos\",\"gaveQty\":1,\"got\":\"gold\",\"gotQty\":100,\"fee\":5}]}}");
            var ord = Json.List(o.Mine, "open")[0];
            check(o.OrderTitle(ord) == "10 Orb of Chaos for 1,000 gold" && o.OrderPrice(ord) == "100 gold per Chaos" && OrbExchangeState.Progress(ord) == 0.5 && o.OrderSub(ord) == "5 / 10 given, 500 received  |  100 gold per Chaos  |  2h 0m left", "orbs: order lines");
            check(o.FillText(Json.List(o.Mine, "fills")[0]) == "2m ago: gave 1 Orb of Chaos, got 100 gold (fee 5)", "orbs: fill line");
        }

        static void Gamble(Action<bool, string> check)
        {
            var r = new Rig();
            r.Now = 1000;
            var g = new GambleState(r.Ext) { Clock = () => r.Now };
            g.Open();
            check(g.Visible && r.Last() == "199 {\"action\":\"open\",\"data\":{}}", "gamble: open");
            r.In(199, "{\"action\":\"state\",\"data\":{\"w\":77,\"near\":true,\"npc\":\"Rufus\",\"money\":5000,\"level\":100,\"gate\":120,\"at\":\"12:00\",\"tz\":\"CET\",\"left\":3700,\"reroll\":900,\"rerolls\":1,\"rerollMax\":3,\"items\":[{\"i\":1,\"id\":501,\"c\":2400,\"n\":\"dark sword\",\"s\":\"weapon\",\"sn\":\"Weapon\",\"l\":110,\"p\":1500},{\"i\":2,\"id\":502,\"c\":2401,\"n\":\"cheap\",\"l\":50,\"p\":9000},{\"i\":3,\"sold\":true},5],\"odds\":[{\"n\":\"Rare\",\"p\":30.5,\"r\":4},{\"n\":\"Legendary\",\"p\":0.25,\"r\":5}]}}");
            var cells = g.Cells();
            check(cells.Count == 4 && cells[0].Name == "Dark sword" && cells[0].CanBuy && cells[0].BuyText == "Buy 1.5k".Replace("1.5k", "1,500") && cells[0].ClientId == 2400, "gamble: cells with a capitalised name and a price button");
            check(!cells[1].CanBuy && cells[1].PriceColor == "#e07060" && cells[2].Sold && !cells[2].CanBuy && cells[2].BuyText == "Sold", "gamble: a crate you cannot pay and a sold one cannot be bought");
            check(g.Header() == "Sealed crates for level 100 (item level up to 120): 1 of 4 sold. Your gold: 5,000", "gamble: header counts the sold crates");
            check(g.NearText(out string nc) == "You stand before Rufus: pick a crate." && nc == "#8fd16a", "gamble: near text");
            check(g.RefreshText(100) == "New crates at 12:00 (CET), in 1h 00m", "gamble: refresh countdown");
            check(g.RerollText(out bool ok, out string tip) == "Fresh Crates (900)" && ok && tip.Contains("1 of 3"), "gamble: reroll button");
            check(g.OddsText() == "Odds per crate: Rare 30.5%, Legendary 0.25%", "gamble: odds text");
            check(GambleState.Countdown(59) == "59s" && GambleState.Countdown(125) == "2m 05s" && GambleState.Countdown(7500) == "2h 05m", "gamble: countdown formats");
            check(g.Buy(cells[0]) && r.Last() == "199 {\"action\":\"buy\",\"data\":{\"i\":1,\"w\":77,\"id\":501}}", "gamble: buy {i, w, id}");
            check(!g.Buy(cells[0]), "gamble: one purchase at a time");
            r.Now = 6000; g.Tick(6000);
            check(!g.Buying, "gamble: the buttons come back after 4 s without an answer");
            check(g.Buy(cells[0]), "gamble: buying works again");
            r.In(199, "{\"action\":\"result\",\"data\":{\"ok\":true,\"text\":\"Bought.\",\"reveal\":{\"r\":4,\"rn\":\"Rare\",\"n\":\"dark sword\",\"l\":110,\"c\":2400}}}");
            check(!g.Buying && g.Status == "Bought." && g.StatusColor == "#a35cf0", "gamble: a result frees the buttons and colours the status by rarity");
            check(GambleState.RevealText(g.Reveal, out string rc) == "The seal breaks: Rare Dark sword (item level 110)" && GambleState.RevealItem(g.Reveal) == 2400, "gamble: the reveal line and item");
            g.Reroll();
            check(r.Last() == "199 {\"action\":\"reroll\",\"data\":{\"w\":77}}", "gamble: reroll {w}");
            check(GambleState.SameCells(cells, g.Cells()) && !GambleState.SameCells(cells, new List<GambleCell>()), "gamble: the same stock refills in place");
            g.Hide();
            check(!g.Visible && r.Last() == "199 {\"action\":\"close\",\"data\":{}}", "gamble: close");
            r.In(199, "{\"action\":\"npc\",\"data\":{}}");
            check(g.Visible, "gamble: the Gambler NPC opens the window");
        }

        static void Ember(Action<bool, string> check)
        {
            var r = new Rig();
            var e = new EmberCacheState(r.Ext);
            e.Open();
            check(e.Visible && r.Last() == "174 {\"action\":\"open\",\"data\":{}}", "ember: open");
            r.In(174, "{\"action\":\"state\",\"data\":{\"week\":{\"pts\":12,\"got\":1,\"ends\":200000,\"sparks\":2,\"tiers\":[{\"p\":10,\"g\":5000,\"it\":[[1,2,\"Orb\"]]},{\"p\":30,\"g\":1000000}]},\"day\":{\"pts\":3,\"spark\":0,\"goal\":5,\"g\":1000,\"bonus\":4},\"book\":{\"xp\":2500000,\"lv\":1,\"kills\":40,\"loot\":3000,\"sup\":5000,\"orbs\":1,\"uniq\":0,\"rares\":2,\"deaths\":0,\"secs\":4000},\"src\":[[\"kill\",1,5,200,50],[\"rift\",3],[\"bogus\",1]]}}");
            check(e.WeekLine() == "This week: 12 Ember points" && e.WeekEndsLine() == "The week ends in 2 days" && e.SparksLine() == "Daily Sparks this week: 2" && e.TodayLine() == "Today: 3 Ember points", "ember: week and day lines");
            var t = e.Tiers();
            check(t.Count == 2 && t[0].Reached && !t[1].Reached && t[0].Reward == "5k gold, 2x Orb" && t[1].Reward == "1M gold" && t[1].Status == "18 to go" && t[0].Title == "Milestone 1: 10 points", "ember: milestones, rewards, what is left");
            check(e.SparkLine(out bool lit) == "Daily Spark at 5 points: 2 to go" && !lit && e.SparkReward() == "1k gold" && e.BonusLine() == "Your next 4 points today count double.", "ember: spark line");
            var book = e.BookRows();
            check(book[0][1] == "2.5M" && book[5][1] == "-2k" && book[8][1] == "1 h 6 min" && book[6][1] == "1 / 0 / 2", "ember: day book values");
            var src = EmberCacheState.SourceRows(Json.Get(e.State, "src"));
            check(src.Count == 2 && src[0][0] == "Monster kills", "ember: sources rows skip unknown keys");
            check(src[0][1] == "5 for 1 point" && src[1][1] == "3 points", "ember: points per source");
            check(src[0][2] == "at most 200 a day (50 today)" && src[1][2] == "", "ember: daily cap text");
            e.AskOffer(); check(r.Last() == "174 {\"action\":\"offerQuote\",\"data\":{}}", "ember: offerQuote");
            r.In(174, "{\"action\":\"offer\",\"data\":{\"orbs\":20,\"points\":2,\"room\":8,\"per\":10,\"carried\":25}}");
            check(e.QuoteVisible && EmberCacheState.OfferText(e.Quote, out bool can) == "Offer 20 junk orbs for 2 Ember points? They are destroyed. (10 orbs a point, 8 points left today)" && can, "ember: the offer box text");
            check(EmberCacheState.OfferText(Json.Parse("{\"room\":0}"), out can) == "The Ember Cache takes no more junk orbs today. More tomorrow." && !can, "ember: no room today");
            check(EmberCacheState.OfferText(Json.Parse("{\"room\":3,\"points\":0,\"carried\":4,\"per\":10}"), out can).StartsWith("You carry 4 junk orbs") && !can, "ember: too few orbs");
            e.Offer(); check(r.Last() == "174 {\"action\":\"offer\",\"data\":{}}" && !e.QuoteVisible, "ember: offer sends no number");
            e.Hide(); check(r.Last() == "174 {\"action\":\"close\",\"data\":{}}", "ember: close");
        }

        static void Unveil(Action<bool, string> check)
        {
            var r = new Rig();
            var u = new UnveilState(r.Ext);
            r.In(196, "{\"action\":\"open\",\"data\":{\"name\":\"dark blade\",\"rarityName\":\"Rare\",\"level\":90,\"orbs\":2,\"path\":\"bag/1\",\"id\":88,\"sig\":\"abc\",\"offers\":[{\"i\":1,\"key\":\"a\",\"name\":\"Fire\",\"text\":\"adds fire damage to the sword when you strike\",\"tier\":2,\"tn\":\"V2\",\"lo\":3,\"hi\":9,\"hook\":true},{\"i\":2,\"name\":\"Life\",\"text\":\"more life\",\"tier\":1,\"lo\":5,\"hi\":5},{\"i\":3,\"name\":\"X\"},{\"i\":4,\"name\":\"Y\",\"text\":\"y\"},{\"i\":5,\"name\":\"Z\",\"text\":\"z\"},{\"i\":6,\"name\":\"W\",\"text\":\"w\"}]}}");
            check(u.Visible && u.HeaderText() == "Dark blade  -  Rare  -  Item Level 90" && u.OrbsText() == "Orbs of Unveiling: 2", "unveil: header and orbs");
            var c = u.Cards();
            check(c.Count == 3 && c[0].Name == "Fire" && c[0].TierText == "Veiled tier V2" && c[0].RangeText == "Range 3-9" && c[0].HookText == "Effect of its own" && c[1].RangeText == "Range 5" && c[1].TierText == "Veiled tier V1", "unveil: three cards at most, junk cards dropped");
            check(c[0].Lines.Count == 2 && c[0].Lines.All(l => l.Length <= 26), "unveil: the card text wraps at 26 characters");
            check(u.StatusText() == "Choose one of the three modifiers. The choice is final." && !u.Confirm(), "unveil: no choice, nothing sent");
            u.Selected = 2;
            check(u.StatusText() == "Reveal Life? The choice is final and takes one orb." && u.CanConfirm(2) && !u.CanConfirm(9), "unveil: status of a picked card");
            check(u.Confirm() && r.Last() == "196 {\"action\":\"choose\",\"data\":{\"path\":\"bag/1\",\"id\":88,\"sig\":\"abc\",\"choice\":2}}", "unveil: choose {path, id, sig, choice}");
            r.In(196, "{\"action\":\"result\",\"data\":{\"ok\":true,\"veil\":{\"n\":\"Life\",\"tn\":\"V1\"}}}");
            check(u.Done && u.Result == "The veil lifts: Life (V1) is yours." && !u.Confirm(), "unveil: the choice is final");
            r.In(196, "{\"action\":\"result\",\"data\":{\"ok\":false,\"text\":\"No orb.\"}}");
            check(u.Result == "No orb.", "unveil: a refusal shows its text");
            check(UnveilState.ResultTextOf(Json.Parse("{\"ok\":true}"), out _) == "The veil lifts." && UnveilState.ResultTextOf(Json.Parse("{\"ok\":false}"), out _) == "That did not work.", "unveil: default result texts");
            u.Handle("open", Json.Parse("{\"name\":\"a\",\"orbs\":0,\"offers\":[{\"i\":1,\"name\":\"n\",\"text\":\"t\"}]}"));
            check(u.StatusText() == "You have no Orb of Unveiling." && !u.CanConfirm(1), "unveil: no orb");
        }

        static void Finder(Action<bool, string> check)
        {
            var r = new Rig();
            r.Now = 1000;
            var f = new ItemFinderState(r.Ext) { Clock = () => r.Now };
            check(ItemFinderState.Query("  dark   sword  ") == "dark sword" && ItemFinderState.Query(new string('x', 60)).Length == 40, "finder: the query folds spaces and is cut at 40");
            check(ItemFinderState.ShouldSearch("ab", "", out _) && !ItemFinderState.ShouldSearch("a", "", out _) && !ItemFinderState.ShouldSearch("Sword", "sword", out _), "finder: two letters, not the last text again");
            f.TypeAhead("sword");
            r.Now = 1200; f.Tick();
            check(r.Sent.Count == 0, "finder: type-ahead waits 350 ms after the last key");
            r.Now = 1400; f.Tick();
            check(r.Last() == "155 {\"action\":\"search\",\"data\":{\"q\":\"sword\",\"p\":1}}", "finder: the search goes out");
            r.Now = 2400; f.Tick();
            check(r.Sent.Count == 2, "finder: an unanswered request is sent once more after 900 ms");
            r.In(155, "{\"action\":\"results\",\"data\":{\"q\":\"sword\",\"p\":1,\"pages\":2,\"total\":12,\"rows\":[{\"id\":10,\"cid\":2400,\"name\":\"dark sword\",\"n\":5,\"kinds\":[\"monster\",\"shop\",\"craft\",\"gather\",\"use\"]},{\"name\":\"junk\"}]}}");
            check(f.Results.Rows.Count == 1 && f.Results.Pages == 2 && ItemFinderState.PageText(1, 2) == "1 / 2" && ItemFinderState.PageText(1, 1) == "", "finder: results, junk rows dropped");
            check(ItemFinderState.KindsText(f.Results.Rows[0].Kinds) == "drops, shops, recipes, gathering, ...", "finder: kinds text is cut at four");
            r.Now = 9000; f.Tick();
            check(r.Sent.Count == 2, "finder: an answer clears the pending request");
            f.ShowItem(10, 2400);
            check(r.Last() == "155 {\"action\":\"item\",\"data\":{\"id\":10}}", "finder: item {id}");
            r.In(155, "{\"action\":\"item\",\"data\":{\"id\":10,\"cid\":2400,\"name\":\"dark sword\",\"total\":7,\"secs\":[{\"k\":\"shop\",\"p\":1,\"pages\":1,\"total\":1,\"rows\":[{\"n\":\"Ana\",\"d\":\"Town\",\"v\":\"500 gold\"}]},{\"k\":\"monster\",\"p\":1,\"pages\":3,\"total\":30,\"rows\":[{\"n\":\"Wolf\",\"b\":true,\"c\":\"2%\",\"v\":\"drop\"}]},{\"k\":\"craft\",\"rows\":[{\"n\":\"Dark Sword\",\"i\":10,\"m\":[{\"i\":5,\"n\":\"Iron\",\"c\":3}]}]}]}}");
            check(f.Item.Secs.Select(s => s.K).SequenceEqual(new[] { "monster", "craft", "shop" }), "finder: sections in the server's order");
            check(ItemFinderState.SectionHead(f.Item.Secs[0]) == "Monsters and bosses (30)" && ItemFinderState.TotalText(7) == "7 sources and uses" && ItemFinderState.TotalText(1) == "1 source or use", "finder: section heads and totals");
            ItemFinderState.RowTexts(f.Item.Secs[0].Rows[0], out string main, out string desc, out string value);
            check(main == "Wolf (boss)" && value == "drop  2%" && desc == "", "finder: row texts");
            check(ItemFinderState.MaterialText(f.Item.Secs[1].Rows[0].Materials[0]) == "3 x Iron", "finder: material text");
            f.Page("monster", 2);
            check(r.Last() == "155 {\"action\":\"page\",\"data\":{\"id\":10,\"k\":\"monster\",\"p\":2}}", "finder: page {id, k, p}");
            r.In(155, "{\"action\":\"page\",\"data\":{\"id\":10,\"k\":\"monster\",\"p\":2,\"pages\":3,\"total\":30,\"rows\":[{\"n\":\"Bear\"}]}}");
            check(f.Item.Secs[0].P == 2 && f.Item.Secs[0].Rows[0].N == "Bear", "finder: a page replaces its section");
            r.In(155, "{\"action\":\"page\",\"data\":{\"id\":99,\"k\":\"monster\",\"p\":3,\"rows\":[]}}");
            check(f.Item.Secs[0].P == 2, "finder: a page of another item is ignored");
            f.ShowItem(11, 0);
            check(f.History.Count == 1 && f.History[0].Key == 10, "finder: opening a linked item pushes the one before");
            check(f.Back() && r.Last() == "155 {\"action\":\"item\",\"data\":{\"id\":10}}" && f.History.Count == 0, "finder: Back goes to the item before");
            check(f.WhereToFind(2400) && r.Last() == "155 {\"action\":\"item\",\"data\":{\"cid\":2400}}" && !f.WhereToFind(0) && !f.WhereToFind(70000), "finder: Where to find sends the client id");
            var hist = new List<KeyValuePair<int, int>>();
            for (int i = 0; i < 30; i++) ItemFinderState.Push(hist, i, 0);
            ItemFinderState.Push(hist, 29, 0);
            check(hist.Count == 20 && hist[0].Key == 10, "finder: history keeps 20 and skips a repeat");
            r.In(155, "{\"action\":\"busy\",\"data\":{}}");
            check(f.Status.Contains("busy"), "finder: busy");
        }

        static void Loadouts(Action<bool, string> check)
        {
            var r = new Rig();
            r.Now = 1000;
            var l = new LoadoutsState(r.Ext) { Clock = () => r.Now };
            string castName = ""; double castMs = 0; string castEnd = ""; var saved = new List<int>(); var loaded = new List<int>();
            l.CastStarted = (n, ms) => { castName = n; castMs = ms; }; l.CastEnded = res => castEnd = res;
            l.ProfileSaved = s => saved.Add(s); l.ProfileLoaded = s => loaded.Add(s);
            l.Open();
            check(l.Visible && r.Last() == "206 {\"action\":\"open\",\"data\":{}}", "loadouts: open");
            r.In(206, "{\"action\":\"state\",\"data\":{\"level\":120,\"minLevel\":50,\"baseSlots\":2,\"unlockLevels\":[200,400],\"cooldown\":20,\"castMs\":3000,\"inPz\":false,\"icons\":[\"skills\",\"spells\"],"
                + "\"slots\":[{\"slot\":1,\"name\":\"Fire\",\"icon\":\"spells\",\"active\":true,\"points\":40,\"pointsTotal\":60,\"cls\":\"mage\",\"voc\":\"Pyromancer\",\"keystones\":[\"Inferno\"],\"paragon\":3,\"supports\":{\"count\":2,\"spells\":[{\"name\":\"Bolt\",\"runes\":[\"Chain\",\"Fork\"]}]},\"gear\":{\"total\":3,\"ready\":2,\"missing\":[{\"name\":\"Ring\",\"where\":\"missing\"}]},\"warnings\":[\"Low level.\"]},"
                + "{\"slot\":2,\"empty\":true},{\"slot\":3,\"empty\":true,\"locked\":true}]}}");
            check(l.Selected == 1, "loadouts: the active slot is selected first");
            var s1 = l.SlotRow(l.SlotOf(1));
            check(s1.Title == "Fire" && s1.Sub == "40 pts | 2 runes | gear 2/3" && s1.Tag == "ACTIVE", "loadouts: a filled row");
            check(l.SlotRow(l.SlotOf(2)).Title == "Empty slot" && l.SlotRow(l.SlotOf(3)).Sub == "Opens at level 200" && l.SlotRow(l.SlotOf(3)).Dim, "loadouts: empty and locked rows");
            var sum = l.Summary(l.SlotOf(1), "main");
            check(sum.Any(x => x.Text == "Class: Mage (Pyromancer)") && sum.Any(x => x.Text == "Passive points: 40 / 60") && sum.Any(x => x.Text == "Keystones: Inferno") && sum.Any(x => x.Text == "  Bolt: Chain, Fork") && sum.Any(x => x.Text == "Gear set: 2/3 ready") && sum.Any(x => x.Text == "  Missing: Ring (not found)") && sum.Any(x => x.Text == "Action bar: main") && sum.Any(x => x.Text == "Low level."), "loadouts: the detail lines");
            check(l.Summary(l.SlotOf(3), "")[0].Text.Contains("level 200"), "loadouts: a locked slot says when it opens");
            check(l.SwitchHint(r.Now, out _) == "Next switch in 20 s." && l.SwitchHint(r.Now + 25000, out _) == "Switching takes 3.0 s here (stand still). Free.", "loadouts: the switch hint counts the cooldown");
            var b = l.Buttons(l.SlotOf(1), r.Now);
            check(b.Save && !b.Load && b.Rename && b.Delete && b.SaveText == "Save", "loadouts: the active slot cannot be loaded, it saves");
            b = l.Buttons(l.SlotOf(2), r.Now);
            check(b.Save && !b.Load && !b.Rename && !b.Delete && b.SaveText == "Save here", "loadouts: an empty slot saves");
            check(!l.Buttons(l.SlotOf(3), r.Now).Save, "loadouts: a locked slot does not save");
            check(LoadoutsState.NextIcon(new[] { "a", "b" }, "a") == "b" && LoadoutsState.NextIcon(new[] { "a", "b" }, "b") == "a" && LoadoutsState.NextIcon(new[] { "a", "b" }, "x") == "a", "loadouts: the icon cycles");
            check(LoadoutsState.ProfileKey("Ana", 2) == "ana:2", "loadouts: the action bar profile key");
            l.Select(2);
            l.Save("Ice");
            check(r.Last() == "206 {\"action\":\"save\",\"data\":{\"slot\":2,\"name\":\"Ice\",\"icon\":\"skills\"}}", "loadouts: save {slot, name, icon}");
            r.In(206, "{\"action\":\"result\",\"data\":{\"ok\":true,\"text\":\"Saved.\",\"lines\":[\"2 notes\"]}}");
            check(saved.SequenceEqual(new[] { 2 }) && l.Status == "Saved.\n2 notes", "loadouts: a saved loadout remembers the action bar profile");
            l.Select(1);
            l.Load();
            check(r.Last() == "206 {\"action\":\"load\",\"data\":{\"slot\":1}}", "loadouts: load {slot}");
            r.In(206, "{\"action\":\"cast\",\"data\":{\"ms\":3000,\"slot\":1}}");
            check(castName == "Loadout" && castMs == 3000, "loadouts: a switch with a cast shows the cast bar");
            r.In(206, "{\"action\":\"castEnd\",\"data\":{\"result\":\"done\"}}");
            r.In(206, "{\"action\":\"result\",\"data\":{\"ok\":true,\"text\":\"Loaded.\"}}");
            check(castEnd == "done" && loaded.SequenceEqual(new[] { 1 }), "loadouts: a loaded loadout applies its action bar profile");
            r.In(206, "{\"action\":\"result\",\"data\":{\"ok\":false,\"text\":\"Busy.\"}}");
            check(loaded.Count == 1, "loadouts: a refused load changes nothing");
            check(!l.Delete() && l.ConfirmDelete == 1 && l.Status.StartsWith("Click Confirm to delete"), "loadouts: delete asks for a second click");
            check(l.Delete() && r.Last() == "206 {\"action\":\"delete\",\"data\":{\"slot\":1}}", "loadouts: delete {slot}");
            l.Rename("New"); check(r.Last().StartsWith("206 {\"action\":\"rename\",\"data\":{\"slot\":1,\"name\":\"New\""), "loadouts: rename");
            check(l.PickSelection(9) == 1 && l.PickSelection(2) == 2, "loadouts: a slot that is gone falls back to the active one");
        }

        static void Supports(Action<bool, string> check)
        {
            var r = new Rig();
            var s = new SpellSupportsState(r.Ext) { Clock = () => r.Now };
            string state = "{\"level\":300,\"orbId\":9,\"orbClientId\":2500,\"orbCount\":3,\"orbsNeeded\":2,\"spells\":[{\"id\":10,\"name\":\"Bolt\",\"words\":\"exori\",\"kind\":\"single\",\"kindName\":\"Single\",\"level\":20,\"count\":2,\"max\":3,\"secondLevel\":100,\"thirdLevel\":400,\"opened\":false,\"canOpen\":true,\"runes\":[{\"slot\":1,\"name\":\"Chain\",\"text\":\"Chains\",\"color\":\"#ff0000\",\"cost\":2500}]},5],"
                + "\"runes\":[{\"id\":70,\"name\":\"Fork\",\"count\":3,\"combine\":true,\"fits\":\"single\",\"text\":\"Forks\"},{\"id\":71,\"name\":\"Pierce\",\"count\":1,\"combine\":true}]}";
            // a bigger answer comes as parts
            string a = state.Substring(0, state.Length / 2), b = state.Substring(state.Length / 2);
            r.In(243, "{\"action\":\"part\",\"data\":{\"id\":1,\"index\":2,\"total\":2,\"text\":" + Json.Serialize(b) + "}}");
            check(s.State == null, "supports: one part alone shows nothing");
            r.In(243, "{\"action\":\"part\",\"data\":{\"id\":1,\"index\":1,\"total\":2,\"text\":" + Json.Serialize(a) + "}}");
            check(s.State == null, "supports: the parts of a message are joined as JSON text (the joined text is a state without its wrapper)");
            r.In(243, "{\"action\":\"part\",\"data\":{\"id\":2,\"index\":1,\"total\":2,\"text\":" + Json.Serialize("{\"action\":\"state\",\"data\":" + a) + "}}");
            r.In(243, "{\"action\":\"part\",\"data\":{\"id\":2,\"index\":2,\"total\":2,\"text\":" + Json.Serialize(b + "}") + "}}");
            check(s.State != null && s.Spells().Count == 1 && s.Runes().Count == 2 && s.Visible, "supports: a state in two parts is handled whole, a junk spell row dropped");
            check(s.SelectedSpell == 10, "supports: the first spell is selected");
            var sp = s.SpellById(10);
            check(SpellSupportsState.KindLine(sp) == "single, level 20" && s.InfoLine(sp).StartsWith("Single spell, level 20. Sockets open: 2 of 3"), "supports: spell lines");
            var v1 = s.Socket(sp, 1, 0);
            check(v1.HasRune && v1.Name == "Chain" && v1.Button1 == "Remove (2k)" && v1.Button2 == "Shatter", "supports: a socketed rune offers Remove and Shatter");
            var v2 = s.Socket(sp, 2, 0);
            check(v2.Name == "Empty socket" && v2.Button1 == "Socket" && !v2.Button1On, "supports: an empty socket needs a selected rune");
            s.SelectedRune = 70;
            check(s.Socket(sp, 2, 0).Button1On, "supports: a selected rune enables Socket");
            var v3 = s.Socket(sp, 3, 0);
            check(v3.Name == "Locked socket" && v3.Button1 == "Open" && v3.Button1On && v3.Text.StartsWith("Opens with 2 Orbs of Sockets (you have 3)."), "supports: the third socket opens with orbs");
            s.SocketRune(10, 2, 70);
            check(r.Last() == "243 {\"action\":\"socket\",\"data\":{\"spell\":10,\"slot\":2,\"rune\":70}}", "supports: socket {spell, slot, rune}");
            s.SocketItem(10, 2, new Pos(65535, 64, 0), 2501);
            check(r.Last() == "243 {\"action\":\"socket\",\"data\":{\"spell\":10,\"slot\":2,\"pos\":{\"x\":65535,\"y\":64,\"z\":0},\"clientId\":2501}}", "supports: socket from a backpack item");
            check(!s.Shatter(10, 1, 100) && s.Socket(sp, 1, 200).Button2 == "Sure?", "supports: Shatter arms first");
            int n = r.Sent.Count;
            check(s.Shatter(10, 1, 1000) && r.Last() == "243 {\"action\":\"remove\",\"data\":{\"spell\":10,\"slot\":1,\"keep\":false}}", "supports: the second Shatter within 3 s destroys the rune");
            check(!s.Shatter(10, 1, 5000), "supports: the arm runs out after 3 s");
            s.Remove(10, 1, true); check(r.Last().EndsWith("\"keep\":true}}"), "supports: Remove keeps the rune");
            s.Unlock(10); check(r.Last() == "243 {\"action\":\"unlock\",\"data\":{\"spell\":10}}", "supports: unlock {spell}");
            check(s.CanCombine(s.RuneById(70)) && !s.CanCombine(s.RuneById(71)) && s.RuneInfo(s.RuneById(70)) == "Fork (x3): Forks. Fits single spells.", "supports: combine needs three");
            s.Combine(); check(r.Last() == "243 {\"action\":\"combine\",\"data\":{\"rune\":70}}", "supports: combine {rune}");
            r.In(243, "{\"action\":\"bar\",\"data\":{\"spells\":{\"10\":[{\"name\":\"Chain\",\"text\":\"Chains\",\"slot\":1}]},\"words\":{\"exori\":10,\"exura\":11}}}");
            check(s.BarRunes(10).Count == 1 && s.BarRunes(11).Count == 0, "supports: the bar data for the hotbar pips");
            check(s.BookLine("exori", out string tip) == "Supports: Chain." && tip == "Supports:\n  Chain: Chains" && s.BookLine("exura", out tip) == "Supports: none socketed (Character > Spell Supports)." && s.BookLine("nope", out tip) == null, "supports: the spellbook line");
            r.In(243, "{\"action\":\"result\",\"data\":{\"ok\":false,\"text\":\"No gold.\"}}");
            check(s.Result == "No gold." && !s.ResultOk, "supports: result text");
            s.OpenFor("exura"); check(s.SelectedSpell == 11 && r.Last() == "243 {\"action\":\"open\",\"data\":{}}", "supports: the spellbook button opens on its spell");
        }

        static void Pact(Action<bool, string> check)
        {
            var r = new Rig();
            var p = new PactState(r.Ext);
            p.Sync();
            check(r.Last() == "222 {\"action\":\"sync\",\"data\":{}}", "pact: sync");
            string title = p.StatusTitle(out string line);
            check(title == "Loading..." && line == "", "pact: loading text before the first status");
            r.In(222, "{\"action\":\"status\",\"data\":{\"active\":true,\"ends\":\"Dec 1\",\"daysLeft\":1,\"title\":\"Pactbound\",\"canClaim\":true,\"dailyMarks\":5,\"marks\":120,\"marksEarned\":999,\"monthExp\":2000000,\"monthExpAccount\":3000000,\"buildLimit\":2,"
                + "\"shelf\":[{\"key\":\"frame\",\"name\":\"Frame\",\"marks\":100,\"owned\":false},{\"key\":\"aura\",\"name\":\"Aura\",\"marks\":500,\"monthly\":true},{\"key\":\"old\",\"name\":\"Old\",\"marks\":1,\"owned\":true}],"
                + "\"limits\":[{\"key\":\"tabs\",\"label\":\"Stash tabs\",\"free\":2,\"pact\":3,\"pactActive\":true,\"extra\":1,\"maxExtra\":4,\"total\":6}],\"special\":[{\"name\":\"Gems\",\"owned\":true}],\"tabSize\":60,"
                + "\"builds\":[{\"slot\":1,\"name\":\"Tank\",\"cls\":\"knight\",\"nodes\":30},{\"slot\":3,\"name\":\"Old build\",\"nodes\":1}],\"open\":true}}");
            title = p.StatusTitle(out line);
            check(p.Visible && title == "Chaos Pact active" && line == "Until Dec 1 (1 day left). Title: Pactbound.", "pact: active status");
            check(p.ClaimText(out bool can) == "Claim 5 Pact Marks" && can, "pact: claim button");
            check(p.MarksLine() == "Pact Marks: 120 (earned so far: 999). They buy only the cosmetics below.", "pact: marks line");
            check(p.MonthLine() == "This month the Pact gave you 2,000,000 extra experience (3,000,000 on all your characters).", "pact: month line");
            var shelf = p.ShelfRows();
            check(shelf[0].CanBuy && shelf[0].Price == "100 Marks" && !shelf[1].CanBuy && shelf[1].Name == "Aura (this month)" && shelf[2].Button == "Owned" && !shelf[2].CanBuy, "pact: shelf rows by what the marks pay for");
            var lim = p.LimitRows();
            check(lim.Count == 1 && lim[0].SequenceEqual(new[] { "Stash tabs", "2", "+3", "1 / 4", "6" }), "pact: limit row");
            check(p.SpecialText() == "Affinity stash tabs: Gems (owned). The free stash tab holds 60 entries; Slot Expansions make it bigger.", "pact: special text");
            var builds = p.BuildRows();
            check(builds.Count == 3 && builds[0].Sub == "Knight line, 30 nodes" && builds[0].Editable && builds[1].Name == "Empty slot" && builds[2].Sub == "no class, 1 node - read-only" && !builds[2].Editable, "pact: build rows, a slot above the limit is read-only");
            check(p.BuildHeader() == "Saved builds: 2 of 2 slots (account-wide)", "pact: build header");
            p.Claim(); check(r.Last() == "222 {\"action\":\"claim\",\"data\":{}}", "pact: claim");
            p.Buy("frame"); check(r.Last() == "222 {\"action\":\"marksBuy\",\"data\":{\"key\":\"frame\"}}", "pact: marksBuy {key}");
            p.Save(2, "Mage"); check(r.Last() == "222 {\"action\":\"buildSave\",\"data\":{\"slot\":2,\"name\":\"Mage\"}}", "pact: buildSave");
            p.Rename(1, "T"); check(r.Last() == "222 {\"action\":\"buildRename\",\"data\":{\"slot\":1,\"name\":\"T\"}}", "pact: buildRename");
            p.LoadBuild(1); check(r.Last() == "222 {\"action\":\"buildLoad\",\"data\":{\"slot\":1}}", "pact: buildLoad");
            check(!p.Delete(1) && p.ArmedDelete == 1 && p.Delete(1) && r.Last() == "222 {\"action\":\"buildDelete\",\"data\":{\"slot\":1}}", "pact: delete asks for a second click");
            int code = 0; string codeText = "";
            p.BuildCode = (s, c) => { code = s; codeText = c; };
            r.In(222, "{\"action\":\"buildCode\",\"data\":{\"slot\":1,\"code\":\"AAAA\"}}");
            check(code == 1 && codeText == "AAAA", "pact: a loaded build's code goes to the passive tree");
            r.In(222, "{\"action\":\"message\",\"data\":{\"text\":\"Full.\",\"error\":true}}");
            check(p.Note == "Full." && p.NoteColor == "#e07060", "pact: error message colour");
            r.In(222, "{\"action\":\"status\",\"data\":{\"active\":false,\"endsAt\":5,\"ends\":\"Nov 1\"}}");
            title = p.StatusTitle(out line);
            check(title == "Chaos Pact ended" && line.StartsWith("Ended Nov 1.") && p.ClaimText(out can) == "Daily Pact Marks" && !can, "pact: an ended pact");
            r.In(222, "{\"action\":\"status\",\"data\":{\"active\":false,\"dailyMarks\":5}}");
            title = p.StatusTitle(out line);
            check(title == "No Chaos Pact" && line.Contains("5 Pact Marks a day"), "pact: no pact");
        }

        static void Candles(Action<bool, string> check)
        {
            var r = new Rig();
            r.Now = 10000;
            var c = new CandlemarksState(r.Ext) { Clock = () => r.Now };
            r.In(176, "{\"action\":\"hud\",\"data\":{\"b\":12,\"p\":600,\"n\":1800,\"e\":true}}");
            check(c.CounterText() == "12 Candlemarks, next in 20 min", "candlemarks: the counter counts the minutes to the next one");
            r.Now = 10000 + 60000;
            check(c.CounterText() == "12 Candlemarks, next in 19 min", "candlemarks: a minute later");
            r.In(176, "{\"action\":\"hud\",\"data\":{\"b\":12,\"p\":600,\"n\":1800,\"e\":false,\"w\":\"staff\"}}");
            check(c.CounterText() == "12 Candlemarks (paused)" && c.CounterTip() == "Staff characters do not earn Candlemarks.", "candlemarks: paused with a reason");
            CandlemarksState.Counter(Json.Parse("{\"balance\":3,\"block\":100,\"progress\":10,\"earning\":true}"), 0, out int bal, out int left, out bool earning, out _);
            check(bal == 3 && left == 90 && earning && CandlemarksState.Minutes(61) == 2, "candlemarks: long keys work and the block is at least 60 s");
            check(CandlemarksState.WhyText("ip").StartsWith("Two other characters") && CandlemarksState.WhyText("level").StartsWith("Your character is below") && CandlemarksState.WhyText("x").StartsWith("Not earning"), "candlemarks: why texts");
            r.In(176, "{\"action\":\"state\",\"data\":{\"balance\":10,\"level\":100,\"near\":true,\"weekEnds\":200000,\"offers\":[{\"k\":\"mount\",\"n\":\"Wolf Mount\",\"b\":\"Fenrir\",\"p\":8,\"w\":1,\"u\":0,\"l\":50,\"c\":2400,\"d\":\"A mount\"},{\"k\":\"hat\",\"n\":\"Hat\",\"p\":20,\"l\":10},{\"k\":\"old\",\"n\":\"Old\",\"p\":1,\"own\":true},{\"k\":\"cap\",\"n\":\"Cap\",\"p\":1,\"w\":2,\"u\":2},{\"k\":\"lvl\",\"n\":\"Lvl\",\"p\":1,\"l\":500},{\"n\":\"no key\"}]}}");
            var offers = c.Offers();
            check(offers.Count == 5 && offers[0].CanBuy && offers[0].Cid == 2400 && CandlemarksState.OfferTitle(offers[0]) == "Wolf Mount: Fenrir" && CandlemarksState.OfferPrice(offers[0]) == "8 Candlemarks" && CandlemarksState.OfferLimit(offers[0]) == "This week: 0 of 1", "candlemarks: an offer you can buy");
            check(offers[1].Why == "Not enough Candlemarks" && offers[2].Why == "Owned" && offers[3].Why == "Weekly limit reached" && offers[4].Why == "Level 500", "candlemarks: why an offer cannot be bought");
            check(c.HeaderBalance() == "Your account has 10 Candlemarks" && c.HeaderWeek() == "Weekly limits reset in 2 days" && c.HeaderShop() == "Osric the Chandler is here: you can buy.", "candlemarks: header lines");
            check(c.Buy(offers[0]) && r.Last() == "176 {\"action\":\"buy\",\"data\":{\"k\":\"mount\"}}" && !c.Buy(offers[0]), "candlemarks: buy {k}, one at a time");
            check(!c.Buy(offers[1]), "candlemarks: an offer that cannot be bought sends nothing");
            r.In(176, "{\"action\":\"result\",\"data\":{\"ok\":true,\"text\":\"Bought.\"}}");
            check(!c.Buying && c.Result == "Bought." && c.ResultColor == "#70d070", "candlemarks: a result frees the buy button");
            r.In(176, "{\"action\":\"state\",\"data\":{\"balance\":10,\"near\":false,\"offers\":[{\"k\":\"a\",\"n\":\"A\",\"p\":1}]}}");
            check(c.Offers()[0].Why.StartsWith("Visit Osric") && c.HeaderShop().StartsWith("Visit Osric"), "candlemarks: away from Osric the offers say where to buy");
            c.Visible = false;
            r.In(176, "{\"action\":\"npc\",\"data\":{}}");
            check(c.Visible && r.Last() == "176 {\"action\":\"open\",\"data\":{}}", "candlemarks: Osric opens the window");
        }

        // ---------------------------------------------------------------------------------------------- texts
        static void Texts(Action<bool, string> check)
        {
            // every Loc.T literal of the new models and windows has a pt-BR entry, and the placeholders match
            string root = FindUp("unity/Client/Assets/Chaos");
            var keys = new HashSet<string>();
            var pat = new Regex("Loc\\.T\\(\\s*(\"(?:[^\"\\\\]|\\\\.)*\")");
            foreach (string f in new[] { "Core/WorldMarks.cs", "Core/WorldTravel.cs", "Core/WorldTiles.cs", "Core/WorldItems.cs", "Core/WorldItems2.cs", "Core/GameWorld.cs", "Unity/Windows/WorldWindows.cs", "Unity/Windows/ItemWindows.cs", "Unity/ChaosApp.World.cs" })
                foreach (Match m in pat.Matches(File.ReadAllText(Path.Combine(root, f))))
                    keys.Add(m.Groups[1].Value.Substring(1, m.Groups[1].Value.Length - 2).Replace("\\n", "\n").Replace("\\\"", "\""));
            foreach (var kv in MapMarkMath.CategoryLabel) keys.Add(kv.Value);
            foreach (var kv in NpcTravel.Names) keys.Add(kv.Value);
            foreach (var kv in EmberCacheState.Sources) keys.Add(kv.Value);
            foreach (var kv in HideoutState.Sources) keys.Add(kv.Value);
            foreach (string k in AutoSellerState.TierNames) keys.Add(k);
            foreach (string k in new[] { "Spell Supports", "Chaos Pact", "Loadouts", "Town Portal", "Hideout", "Map Overlay", "Map Markers", "Auto Loot", "Ember Cache", "Item Finder", "Orb Exchange", "Candlemarks", "Auto Seller" }) keys.Add(k);
            var missing = keys.Where(k => !LocStrings.PtBr.ContainsKey(k)).ToList();
            check(missing.Count == 0, "world: every text has a pt-BR entry; missing: " + string.Join(" | ", missing.Take(8)));
            var bad = LocWorld.PtBr.Where(kv => Regex.Matches(kv.Key, "\\{\\d\\}").Count != Regex.Matches(kv.Value, "\\{\\d\\}").Count).Select(kv => kv.Key).ToList();
            check(bad.Count == 0, "world: placeholders of the pt-BR texts match: " + string.Join(" | ", bad.Take(5)));
            Loc.Set("pt-BR");
            check(Loc.T("Town Portal ready in {0} s.", 4) == "Portal da Cidade pronto em 4 s." && Loc.T("Hideout") == "Esconderijo", "world: pt-BR text through Loc.T");
            Loc.Set("en");
            check(!LocWorld.PtBr.Any(kv => kv.Value.Contains("\u2014") || kv.Value.Contains("\u2013")), "world: no em dashes in the pt-BR texts");
        }

        static string FindUp(string rel)
        {
            string dir = AppContext.BaseDirectory;
            for (int i = 0; i < 10 && dir != null; i++)
            {
                string p = Path.Combine(dir, rel);
                if (Directory.Exists(p)) return p;
                dir = Path.GetDirectoryName(dir);
            }
            return Path.GetFullPath(Path.Combine(Directory.GetCurrentDirectory(), "..", "Client", "Assets", "Chaos"));
        }
    }
}
