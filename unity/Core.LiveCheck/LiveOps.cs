// The extended opcodes the live check drives: every client-facing opcode Unity handles (tools/ci/check_unity_opcodes.py), the request the
// Unity window sends to open it (the first request of Core/FakeModules.cs Catalog, the list the window smoke run uses), and the opcodes that are
// pushes only or answered by the session on its own (the guard, spells, party frames, the HUD hello, the progression start).
using System.Collections.Generic;
using System.Linq;

namespace Chaos.Core.LiveCheck
{
    public sealed class OpPlan
    {
        public byte Op;
        public string Name = "";
        /// <summary>The request action ("" when the opcode has no request of its own).</summary>
        public string Action = "";
        public object Data;
        /// <summary>The way the opcode is sent: "request" (this check sends it), "session" (GameSession sends it on its own after the login), "push" (the server sends, no request exists).</summary>
        public string Kind = "push";
        /// <summary>Plain text opcode (no JSON).</summary>
        public bool Text;
    }

    public static class LiveOps
    {
        static readonly (byte, string)[] All =
        {
            (60,"bank"),(65,"passivetree"),(79,"notifications"),(91,"craftTable"),(96,"nameshaders"),(109,"dungeons"),(110,"stash"),(113,"npcCurrency"),(114,"weather"),(115,"unlocks"),
            (116,"everfull"),(117,"weeklyChest"),(118,"templarAura"),(119,"combatStats"),(120,"admin"),(121,"npcTravel"),(122,"survey"),(125,"monsterbar"),(151,"notificationsAction"),
            (152,"notificationsQueue"),(153,"mapMarkers"),(154,"deathRecap"),(155,"itemFinder"),(156,"tileBars"),(157,"displayScale"),(159,"waystoneAtlas"),
            (160,"groupQueue"),(163,"nemesis"),(167,"conquest"),(171,"chronicle"),(172,"cardState"),(174,"emberCache"),(176,"candlemarks"),(178,"goals"),(186,"kiteWalk"),
            (188,"rightClickEquip"),(191,"levelWings"),(192,"hideout"),(193,"pvpZone"),(194,"mentor"),(195,"professions"),(196,"veiled"),(197,"guildWar"),
            (198,"charms"),(199,"gamble"),(200,"battleground"),(203,"community"),(204,"combatLog"),(205,"descent"),(206,"loadouts"),(207,"daily"),(208,"partyFinder"),
            (209,"orbExchange"),(210,"riftAtlas"),(211,"antibot"),(212,"transmog"),(213,"raid"),(214,"infinitytower"),(215,"factions"),(216,"autoloot"),
            (217,"bossSpawns"),(218,"shop"),(219,"spellbook"),(220,"referral"),(221,"market"),(222,"pact"),(223,"bounty"),(224,"energyShield"),(225,"cosmetics"),
            (226,"pouches"),(227,"seasonPass"),(228,"rift"),(229,"leaderboard"),(230,"groundLoot"),(231,"castbar"),(232,"crafting"),(233,"siege"),(234,"buffs"),
            (235,"partyFrames"),(236,"arena"),(237,"info"),(238,"lootfilter"),(239,"townPortal"),(240,"inspect"),(241,"hunt"),(242,"itemTooltip"),(243,"supports"),
            (244,"patchnotes"),(245,"mapmarks"),(246,"season"),(247,"monkChi"),(248,"nameplate"),(249,"itemLink"),(250,"achievements"),(251,"invasion"),
            (252,"guild"),(253,"bestiary"),(254,"pets"),
        };

        /// <summary>Opcodes the session asks for itself after the login (Core/Game.cs Poll, GameCollect, GameWorld, Hud, Progression).</summary>
        static readonly HashSet<byte> SessionAsks = new HashSet<byte> { 115, 119, 153, 156, 157, 178, 219, 224, 225, 235, 228, 114 };
        static readonly HashSet<byte> TextOps = new HashSet<byte> { 224, 247, 248 };

        /// <summary>Requests the window sends that need data (the Catalog's first action alone would be refused or ignored).</summary>
        static readonly Dictionary<byte, (string, object)> Override = new Dictionary<byte, (string, object)>
        {
            { 65, ("requestPoints", null) },                                                         // PassiveTree.Open (then requestNodesUnlocked, see More)
            { 91, ("fetch", new Dictionary<string, object> { { "category", "herbalist" }, { "page", 1 } }) },   // CraftTableState: a page of recipes
            { 96, ("open", null) },                                                                  // Visual.cs name shaders
            { 155, ("search", new Dictionary<string, object> { { "q", "sword" }, { "p", 1 } }) },    // ItemFinderState.Search
            { 204, ("open", null) },                                                                 // DpsMeter.Start, watch the current segment
            { 237, ("services", null) },                                                             // ChaosInfo.RequestServices
            { 245, ("watch", new Dictionary<string, object> { { "on", true } }) },                   // map overlay marks
        };

        /// <summary>A second request some windows send right after the first.</summary>
        public static readonly Dictionary<byte, (string, object)> More = new Dictionary<byte, (string, object)>
        {
            { 65, ("requestNodesUnlocked", null) },
        };

        /// <summary>Opcodes that stay silent for a good reason on a quiet character (the check lists the reason next to the status).</summary>
        public static readonly Dictionary<byte, string> Silent = new Dictionary<byte, string>
        {
            { 228, "rift: the server answers a query only inside a rift" },
            { 120, "admin panel: the server answers staff accounts only" },
            { 96, "name shaders: no server script answers opcode 96 on this server (base module)" },
            { 159, "waystone atlas: opens at level 1100 (waystone_atlas_config minLevel)" },
        };

        public static List<OpPlan> Plan()
        {
            var plan = new List<OpPlan>();
            foreach (var (op, name) in All)
            {
                var p = new OpPlan { Op = op, Name = name, Text = TextOps.Contains(op) };
                var mod = FakeModules.ModuleOf(op);
                if (Override.TryGetValue(op, out var ov)) { p.Action = ov.Item1; p.Data = ov.Item2; p.Kind = "request"; }
                else if (mod != null && mod.Requests.Length > 0 && !SessionAsks.Contains(op)) { p.Action = mod.Requests[0]; p.Kind = "request"; }
                else if (SessionAsks.Contains(op)) p.Kind = "session";
                plan.Add(p);
            }
            return plan;
        }

        /// <summary>The opcodes the Catalog covers that the table above lacks (a self check: must be empty).</summary>
        public static List<byte> CatalogMissing() =>
            FakeModules.Catalog.Where(m => All.All(a => a.Item1 != m.Op)).Select(m => m.Op).ToList();
    }
}
