// Phase 13, track G: the module answers of the windows the phase 12 smoke run still found empty (Core/FakeModules.cs has the rules: the server's real JSON shape, the server file
// cited per message, the keys checked against that file by Core.Tests/FakeModulesTests.cs, the Unity state checked by Core.Tests/FakeModulesP13Tests.cs). Covered here: Factions, Conquest,
// Admin (the catalog the server sends to a staff account at the login), Boss Spawns, Referral, Nemesis, Community goal, Patch notes, Chronicle, Inspect, Descent (info), Invasion
// (calendar), Guild Siege, Arena and Battleground (the queue pages), Orb Exchange, Gamble, Ember Cache, Loadouts, Spell Supports, Chaos Pact, Candlemarks, Loot filter, Hideout and the
// two atlases. The trade window needs a trade partner (base protocol packets 0x7D and 0x7E: TradePacket), the How it works window needs a card and the Inspect window a name:
// the smoke run sets those up itself (ChaosApp.Smoke.cs). What has no sample is listed in unity/README.md "Window smoke run".
using System;
using System.Collections.Generic;

namespace Chaos.Core
{
    public static partial class FakeModules
    {
        /// <summary>The module list of this file (added to FakeModules.Catalog).</summary>
        static IEnumerable<FakeModule> Phase13Modules()
        {
            yield return Mod("factions", FactionsPanel.Opcode, "factions.lua", "FactionsWindow", "open");
            yield return Mod("conquest", ConquestPanel.Opcode, "conquest.lua", "ConquestWindow", "open");
            yield return Mod("admin", AdminPanel.Opcode, "admin/core.lua", "AdminWindow", "catalog");
            yield return Mod("bossspawns", BossSpawnsPanel.Opcode, "bossspawns.lua", "BossSpawnsWindow", "open", "refresh");
            yield return Mod("referral", ReferralPanel.Opcode, "referral.lua", "ReferralWindow", "open", "sync");
            yield return Mod("nemesis", NemesisPanel.Opcode, "nemesis.lua", "NemesisWindow", "get");
            yield return Mod("community", CommunityGoalPanel.Opcode, "community.lua", "CommunityGoalWindow", "open");
            yield return Mod("patchnotes", PatchNotesPanel.Opcode, "patchnotes.lua", "PatchNotesWindow", "open", "changelog");
            yield return Mod("chronicle", ChroniclePanel.Opcode, "chronicle.lua", "ChronicleWindow", "open", "mem");
            yield return Mod("inspect", InspectPanel.Opcode, "inspect.lua", "InspectWindow", "privacy", "inspect");
            yield return Mod("descent", DescentState.Opcode, "descent.lua", "DescentWindow", "open");
            yield return Mod("invasion", InvasionState.Opcode, "invasion.lua", "InvasionWindow", "calendar");
            yield return Mod("siege", SiegeState.Opcode, "siege.lua", "SiegeWindow", "open");
            yield return Mod("arena", ArenaState.Opcode, "arena.lua", "ArenaWindow", "open");
            yield return Mod("battleground", BattlegroundState.Opcode, "battleground.lua", "BattlegroundWindow", "open");
            yield return Mod("orbexchange", OrbExchangeState.Opcode, "orbexchange.lua", "OrbExchangeWindow", "open", "book", "mine");
            yield return Mod("gamble", GambleState.Opcode, "gamble.lua", "GambleWindow", "open");
            yield return Mod("embercache", EmberCacheState.Opcode, "embercache.lua", "EmberCacheWindow", "open");
            yield return Mod("loadouts", LoadoutsState.Opcode, "loadouts.lua", "LoadoutsWindow", "open");
            yield return Mod("supports", SpellSupportsState.Opcode, "supports.lua", "SpellSupportsWindow", "open");
            yield return Mod("pact", PactState.Opcode, "pact.lua", "PactWindow", "open", "sync");
            yield return Mod("candlemarks", CandlemarksState.Opcode, "candlemarks.lua", "CandlemarksWindow", "open");
            yield return Mod("lootfilter", LootFilterModel.Opcode, "lootfilter.lua", "LootWindow", "sync", "open");
            yield return Mod("hideout", HideoutState.Opcode, "hideout.lua", "HideoutWindow", "open", "visits");
            yield return Mod("riftatlas", AtlasState.RiftOpcode, "atlas.lua", "RiftAtlasWindow", "open");
            yield return Mod("waystoneatlas", AtlasState.WaystoneOpcode, "waystone_atlas.lua", "WaystoneAtlasWindow", "open");
        }

        /// <summary>The answers of this file's modules; empty for an opcode or action not covered here.</summary>
        static List<FakeMsg> Answer13(byte op, string action, object data)
        {
            var o = new List<FakeMsg>();
            if (op == FactionsPanel.Opcode) { if (action == "open") o.Add(FactionsState()); }
            else if (op == ConquestPanel.Opcode) { if (action == "open") o.Add(ConquestState()); }
            else if (op == AdminPanel.Opcode) { if (action == "catalog") o.Add(AdminCatalog()); }
            else if (op == BossSpawnsPanel.Opcode)
            {
                if (action == "open" || action == "refresh") { o.Add(BossList()); o.Add(BossPocket()); }
            }
            else if (op == ReferralPanel.Opcode) { if (action == "open" || action == "sync") o.Add(ReferralStatus(action == "open")); }
            else if (op == NemesisPanel.Opcode) { if (action == "get") o.Add(NemesisState()); }
            else if (op == CommunityGoalPanel.Opcode) { if (action == "open") o.Add(GoalState()); }
            else if (op == PatchNotesPanel.Opcode)
            {
                if (action == "open") { o.Add(PatchList()); o.Add(PatchNote()); }
                if (action == "changelog") o.Add(PatchChangelog());
            }
            else if (op == ChroniclePanel.Opcode)
            {
                if (action == "open") o.Add(ChronicleState());
                if (action == "mem") o.Add(ChronicleMem());
            }
            else if (op == InspectPanel.Opcode)
            {
                if (action == "privacy") o.Add(M(InspectPanel.Opcode, "privacy", "{'allow':true}", Sc + "inspect.lua (privacy)"));
                if (action == "inspect") o.AddRange(InspectAnswer(Json.Text(data, "name", InspectName)));
            }
            else if (op == DescentState.Opcode) { if (action == "open") o.Add(DescentInfo()); }
            else if (op == InvasionState.Opcode) { if (action == "calendar") o.Add(InvasionCalendar()); }
            else if (op == SiegeState.Opcode) { if (action == "open") o.Add(SiegeInfo()); }
            else if (op == ArenaState.Opcode) { if (action == "open") o.Add(ArenaStateMsg()); }
            else if (op == BattlegroundState.Opcode) { if (action == "open") o.Add(BattlegroundStateMsg()); }
            else if (op == OrbExchangeState.Opcode)
            {
                if (action == "open") o.Add(OrbMeta());
                if (action == "book") o.Add(OrbBook(Json.Text(data, "base", "fate"), Json.Text(data, "quote", "gold"), Json.Int(data, "seq", 1)));
                if (action == "mine") o.Add(OrbMine());
            }
            else if (op == GambleState.Opcode) { if (action == "open") o.Add(GambleStateMsg()); }
            else if (op == EmberCacheState.Opcode) { if (action == "open") o.Add(EmberState()); }
            else if (op == LoadoutsState.Opcode) { if (action == "open") o.Add(LoadoutsStateMsg()); }
            else if (op == SpellSupportsState.Opcode) { if (action == "open") { o.Add(SupportsState()); o.Add(SupportsBar()); } }
            else if (op == PactState.Opcode) { if (action == "open" || action == "sync") o.Add(PactStatus(action == "open")); }
            else if (op == CandlemarksState.Opcode) { if (action == "open") o.Add(CandleState()); }
            else if (op == LootFilterModel.Opcode)
            {
                if (action == "sync" || action == "open") o.Add(LootSettings(action == "open"));
                if (action == "sync") o.Add(LootKillSample());
            }
            else if (op == HideoutState.Opcode)
            {
                if (action == "open") o.Add(HideoutStateMsg());
                if (action == "visits") o.Add(HideoutVisits());
            }
            else if (op == AtlasState.RiftOpcode || op == AtlasState.WaystoneOpcode)
            {
                if (action == "open")
                {
                    bool rift = op == AtlasState.RiftOpcode;
                    if (Json.Bool(data, "tree", true)) o.Add(AtlasTree(rift));   // the server sends the tree only when the client has none; the smoke run's client has none
                    o.Add(AtlasStateMsg(rift));
                }
            }
            return o;
        }

        /// <summary>The name the Inspect window asks for in the smoke run and the name the sample answers for when the request has none.</summary>
        public const string InspectName = "Vex";

        // ------------------------------------------------------------------------------------ the trade window (base protocol, no extended opcode)
        /// <summary>A sample player trade: the partner and two offers as (item id, count). Packets: TradePacket(0x7D ...) for your offer, (0x7E ...) for theirs.</summary>
        public const string TradePartner = "Vex";
        public static readonly int[][] TradeOwn = { new[] { 3031, 5 }, new[] { 3043, 1 } };
        public static readonly int[][] TradeTheirs = { new[] { 3035, 20 } };

        /// <summary>0x7D (own offer) or 0x7E (the other player's offer): string name, u8 count, then each item as u16 id, u8 0xFF mark, for an item with a count (counted(id)) u8 count and for an animated one (phased(id)) u8 0xFE
        /// (protocolgame.cpp sendTradeItemRequest; the reader is GameSession's PlayerTradeState.Read).</summary>
        public static byte[] TradePacket(byte op, string name, int[][] items, Func<int, bool> counted, Func<int, bool> phased = null)
        {
            var w = new ByteWriter().U8(op).Str(name).U8((byte)items.Length);
            foreach (var it in items)
            {
                w.U16((ushort)it[0]).U8(0xFF);
                if (counted != null && counted(it[0])) w.U8((byte)Math.Max(1, Math.Min(100, it[1])));
                if (phased != null && phased(it[0])) w.U8(0xFE);   // an animated item carries its phase byte, as on a tile
            }
            return w.ToArray();
        }

        // ------------------------------------------------------------------------------------ 215 factions (factions.lua F.payload, factions_core.lua K.payload)
        static FakeMsg FactionsState() => M(FactionsPanel.Opcode, "state",
            "{'now':1700000000,'nextDay':36000,'nextWeek':400000,'weekCap':600,'ranks':[{'k':'wary','n':'Wary','min':0,'c':'#a89c86'},{'k':'trusted','n':'Trusted','min':500,'c':'#6fd86f'},{'k':'honored','n':'Honored','min':1500,'c':'#f6cf72'}]," +
            "'factions':[" +
            "{'k':'ash','n':'Ash Wardens','s':'Ash','c':'#c0501a','lore':'Keepers of the cinder roads.','rival':'frost','rep':820,'rank':2,'rn':'Trusted','rc':'#6fd86f','lo':500,'hi':1500,'pct':32,'nx':'Honored','wk':120,'wc':600,'dy':40,'dr':1,'npc':'Warden Ysolde','near':true,'tok':3,'tn':'Ash Tokens','tid':3031,'theme':'ash','at':'Warden Ysolde, in the market of the teleport room in Cinderhold'}," +
            "{'k':'frost','n':'Frost Order','s':'Frost','c':'#3a6fc0','lore':'Wardens of the northern passes.','rival':'ash','rep':140,'rank':1,'rn':'Wary','rc':'#a89c86','lo':0,'hi':500,'pct':28,'nx':'Trusted','wk':0,'wc':600,'dy':0,'dr':1,'npc':'Warden Brann','tok':0,'tn':'Frost Tokens','tid':3043,'theme':'frost'}]," +
            "'contracts':[{'key':'d1','f':'ash','per':'d','kind':'kill','label':'Slay 20 ghouls','p':8,'n':20,'rep':25},{'key':'d2','f':'ash','per':'d','kind':'deliver','label':'Bring 5 Ash Tokens','p':0,'n':5,'rep':40,'give':true}," +
            "{'key':'w1','f':'ash','per':'w','kind':'kill','label':'Seal 3 rifts','p':1,'n':3,'rep':120},{'key':'d3','f':'frost','per':'d','kind':'kill','label':'Slay 15 wolves','p':15,'n':15,'rep':20,'done':true}]," +
            "'offers':[{'key':'o1','f':'ash','kind':'gear','n':'Warden Helm','rank':2,'rn':'Trusted','price':20000,'tokens':5,'st':'open','item':3031,'lv':100,'rar':3,'mods':['T1 +5% fire resistance']}," +
            "{'key':'o2','f':'ash','kind':'orbs','n':'Orb Parcel','rank':2,'rn':'Trusted','price':0,'tokens':8,'st':'open','item':3043,'desc':'3 Orbs of Fate','wl':2,'wb':1}," +
            "{'key':'o3','f':'ash','kind':'mount','n':'Cinder Steed','rank':3,'rn':'Honored','price':0,'tokens':40,'st':'locked','why':'Needs Honored','item':3035,'desc':'A faction mount, yours for good.'}]," +
            "'gold':350000}", Sc + "factions.lua, factions_core.lua (F.payload and K.payload)");

        // ------------------------------------------------------------------------------------ 167 conquest vendor (conquest.lua X.state, conquest_core.lua K.payload)
        static FakeMsg ConquestState() => M(ConquestPanel.Opcode, "state",
            "{'bal':180,'level':310,'pz':true,'band':20," +
            "'offers':[{'k':'u1','id':2400,'c':3031,'n':'Ashen Blade','g':'monster','l':320,'p':40,'s':'weapon','ok':true},{'k':'u2','id':2401,'c':3043,'n':'Warden Plate','g':'boss','l':330,'p':90,'s':'armor','ok':true}," +
            "{'k':'u3','id':2402,'c':3035,'n':'Cinder Ring','g':'set','l':300,'p':60,'s':'ring','set':'Cinder Set','ok':true},{'k':'u4','id':2403,'c':3031,'n':'Hollow Crown','g':'raid','l':400,'p':500,'s':'head','ok':false,'why':'Slay Vorn the Hollow first'}]," +
            "'groups':[{'g':'monster','n':'Monster uniques'},{'g':'boss','n':'Boss uniques'},{'g':'set','n':'Set pieces'},{'g':'raid','n':'Raid uniques'},{'g':'ascended','n':'Ascended'}]," +
            "'pity':[{'g':'monster','n':'Monster uniques','m':3,'x':1.15},{'g':'boss','n':'Boss uniques','m':0,'x':1}]," +
            "'today':[{'k':'hunt','n':'Hunting','got':12,'cap':40},{'k':'rift','n':'Rifts','got':5,'cap':20}]," +
            "'cinder':{'omenKey':50,'attune':20,'shard':30,'convert':{'shards':3,'relics':3,'fee':10},'omens':[{'k':'vorn','n':'Vorn'},{'k':'krag','n':'Krag'}],'ascended':[{'k':'ember','n':'Ember'},{'k':'frost','n':'Frost'}],'shards':{'ember':4,'frost':1},'relics':{'ember':0,'frost':3},'hasKey':true}," +
            "'refine':[{'slot':1,'n':'Ashen Helm','c':3031,'r':2,'rn':'Rare','to':'Epic','p':25,'ok':true}],'refineMax':5}", Sc + "conquest.lua, conquest_core.lua (X.state)");

        // ------------------------------------------------------------------------------------ 120 admin (admin/core.lua ChaosAdmin.buildCatalog; only a staff account gets it)
        static FakeMsg AdminCatalog() => M(AdminPanel.Opcode, "catalog",
            "{'categories':[" +
            "{'id':'players','label':'Players','actions':[" +
            "{'id':'heal','name':'Heal player','description':'Restores health and mana of a player.','params':[{'name':'player','label':'Player','type':'string','required':true,'hint':'character name'}],'confirm':false,'dangerous':false}," +
            "{'id':'kick','name':'Kick player','description':'Removes a player from the game.','params':[{'name':'player','label':'Player','type':'string','required':true},{'name':'reason','label':'Reason','type':'string','required':false}],'confirm':true,'dangerous':true}]}," +
            "{'id':'server','label':'Server','actions':[{'id':'broadcast','name':'Broadcast','description':'Sends a message to everybody online.','params':[{'name':'text','label':'Text','type':'string','required':true}],'confirm':false,'dangerous':false}," +
            "{'id':'status','name':'Server status','description':'Players online, uptime and memory.','params':[],'confirm':false,'dangerous':false}]}]," +
            "'group':6}", Sc + "admin/core.lua (ChaosAdmin.buildCatalog)");

        // ------------------------------------------------------------------------------------ 217 boss spawns (bossspawns.lua, bossspawns_core.lua K.payload, pocketboss.lua)
        static FakeMsg BossList() => M(BossSpawnsPanel.Opcode, "list",
            "{'now':1700000000,'refresh':30,'cats':[{'k':'world','n':'World bosses','c':'#e05040','t':'Roaming bosses of the open world'},{'k':'raid','n':'Raid bosses','c':'#b98ae8','t':'Bosses of the Ashen Sepulchre'}]," +
            "'rows':[{'k':'b1','c':'world','n':'Vorn the Hollow','loc':'Ashen Fields','p':{'x':1010,'y':1020,'z':7},'lv':200,'st':'alive','alive':1,'tx':'Spawns every day.','sh':'Daily'}," +
            "{'k':'b2','c':'world','n':'Krag Warlord','loc':'Cinder Pass','lv':260,'st':'respawn','in':5400,'ago':7200,'by':'Mira','kills':14,'tx':'Respawns six hours after its death.','sh':'6h'}," +
            "{'k':'b3','c':'world','n':'The Grave Warden','loc':'Old Crypt','ln':'Behind the crypt gate','lv':150,'st':'scheduled','in':90000,'at':'Wed 19:30','tx':'Wednesdays at 19:30.','sh':'Wed'}," +
            "{'k':'b4','c':'raid','n':'Sepulchre Guardian','loc':'Sepulchre','lv':320,'party':5,'pl':320,'st':'ondemand','tx':'Opens with a raid key.','sh':'Key'}]}", Sc + "bossspawns.lua, bossspawns_core.lua (K.payload)");

        static FakeMsg BossPocket() => M(BossSpawnsPanel.Opcode, "pocket",
            "{'bosses':{'b1':{'l':2,'m':3,'b':1,'lv':200,'ok':true},'b4':{'l':0,'m':3,'b':0,'lv':320}},'reset':30000}", Sc + "bossspawns.lua, pocketboss.lua (the pocket message after every list)");

        // ------------------------------------------------------------------------------------ 220 referral (referral.lua, referral_core.lua view)
        static FakeMsg ReferralStatus(bool open) => M(ReferralPanel.Opcode, "status",
            "{'open':" + (open ? "true" : "false") + ",'enabled':true,'code':'EMBER7K2Q','shareUrl':'','gift':'a supply pack','giftTitle':'Newcomer'," +
            "'milestones':[{'level':50,'reward':'200 Chaos Coins'},{'level':100,'reward':'300 Chaos Coins'}],'tiers':[{'count':3,'reward':'the title Recruiter','reached':false},{'count':10,'reward':'a cosmetic','reached':false}]," +
            "'qualifyLevel':50,'qualified':1,'canEnter':false,'enterNote':'The first week of the account has passed.','linksThisMonth':2,'monthlyLinks':20,'paidThisMonth':1,'monthlyRewards':10,'coinsEarned':200," +
            "'friends':[{'name':'Vex','level':62,'linkedAt':1699000000,'steps':[{'level':50,'state':'paid'},{'level':100,'state':'open'}]},{'name':'Zed','level':12,'linkedAt':1699900000,'steps':[{'level':50,'state':'open'}]}]}",
            Sc + "referral.lua, referral_core.lua (view)");

        // ------------------------------------------------------------------------------------ 163 nemesis (nemesis.lua)
        static FakeMsg NemesisState() => M(NemesisPanel.Opcode, "state",
            "{'has':true,'name':'Varkh','shown':'Varkh, Bane of Ember','monster':'Ghoul','level':120,'kills':2,'traits':[{'key':'vengeful','name':'Vengeful','desc':'Hits harder when you run.'},{'key':'swift','name':'Swift','desc':'Moves faster than you.'}]," +
            "'lastSeen':1700000000,'created':1699000000,'expiresIn':200000,'avenged':1,'hunted':0}", Sc + "nemesis.lua, nemesis_core.lua (state)");

        // ------------------------------------------------------------------------------------ 203 community goal (community.lua X.payload, community_core.lua K.payload)
        static FakeMsg GoalState() => M(CommunityGoalPanel.Opcode, "state",
            "{'goal':{'n':'Ember Harvest','rn':'','d':'Everybody online gathers embers for the Great Brazier.','p':420000,'target':1000000,'pct':42,'left':345600}," +
            "'stages':[{'n':'First Flame','d':'+10% experience','s':'+10% experience','pct':25,'h':4,'done':true},{'n':'Roaring Fire','d':'+15% loot','s':'+15% loot','pct':50,'h':4,'left':3600},{'n':'Wildfire','d':'+20% damage','s':'+20% damage','pct':100,'h':6}]," +
            "'mine':{'p':8200,'rank':14,'today':2100,'cap':10000,'top':10,'title':'Ember Keeper','token':20000,'tokenText':'a Brazier trophy'}," +
            "'sources':[{'k':'kill','n':'Monster kills','mine':5000,'cap':8000},{'k':'brazier','n':'The Brazier','mine':3200,'cap':5000}]," +
            "'top':[{'n':'Vex','p':91000},{'n':'Mira','p':74000},{'n':'Zed','p':52000}]," +
            "'week':{'mods':[{'k':'fury','n':'Fury Week','d':'Monsters hit harder and drop more.'}],'left':200000,'staff':false}," +
            "'brazier':{'near':false,'gold':350000,'room':90000,'min':10000,'max':1000000,'per':10000}}", Sc + "community.lua, community_core.lua (X.payload and K.payload)");

        // ------------------------------------------------------------------------------------ 244 patch notes (patchnotes.lua, patchnotes_core.lua)
        static FakeMsg PatchList() => M(PatchNotesPanel.Opcode, "list",
            "{'weeks':[{'id':'2026-w45','title':'Ember Season','date':'2026-11-02','new':true},{'id':'2026-w44','title':'The Hollow Rises','date':'2026-10-26','new':false}],'selected':'2026-w45','open':true,'auto':false,'autoEnabled':true,'dailyFirst':false}",
            Sc + "patchnotes.lua (list)");

        static FakeMsg PatchNote() => M(PatchNotesPanel.Opcode, "note",
            "{'id':'2026-w45','title':'Ember Season','date':'2026-11-02','part':1,'parts':1,'intro':['A new season starts and the rifts grow teeth.']," +
            "'sections':[{'name':'Server','kind':'server','cont':false,'items':[{'text':'Rift tiers 12 to 15 are open.','level':1,'lead':'New'},{'text':'Raid loot is shown in the journal.','level':1}]}," +
            "{'name':'Client','kind':'client','cont':false,'items':[{'text':'Every window has a screenshot test.','level':1}]}]}", Sc + "patchnotes.lua, patchnotes_core.lua (note)");

        static FakeMsg PatchChangelog() => M(PatchNotesPanel.Opcode, "changelog",
            "{'available':true,'server':{'date':'2026-11-02'},'published':1699900000,'entries':[{'id':'c1','date':'2026-11-02','ts':1699900000,'pr':301,'text':'The window smoke run covers more windows.','tags':['client'],'client':12,'pending':false}," +
            "{'id':'c2','date':'2026-11-01','ts':1699800000,'pr':300,'text':'Rift guardians hit less hard.','tags':['server','content'],'client':0,'pending':true}]}", Sc + "patchnotes.lua, changelog_core.lua (changelog)");

        // ------------------------------------------------------------------------------------ 171 chronicle (chronicle.lua X.payload, chronicle_core.lua K.payload)
        static FakeMsg ChronicleState() => M(ChroniclePanel.Opcode, "state",
            "{'now':1700000000,'season':'Ember','active':true,'arc':'ash','title':{'en':'The Ashen Road','pt':'A Estrada de Cinzas'},'intro':{'en':['The road burns and the people walk it.'],'pt':['A estrada queima e o povo a percorre.']}," +
            "'chapters':[{'i':1,'key':'a','state':'done','pct':100,'doneAt':1699000000,'title':{'en':'The Wake','pt':'O Despertar'},'text':{'en':['The first ember was lit.'],'pt':['A primeira brasa foi acesa.']},'world':{'en':'The north gate is open.','pt':'O portao norte esta aberto.'}," +
            "'goals':[{'l':'Slay monsters','lp':'Derrote monstros','p':50000,'t':50000}],'mine':1200,'top':[{'n':'Vex','p':9000},{'n':'Mira','p':7000}]}," +
            "{'i':2,'key':'b','state':'open','pct':40,'title':{'en':'The Walk','pt':'A Caminhada'},'text':{'en':['The road climbs the ridge.'],'pt':['A estrada sobe o cume.']},'goals':[{'l':'Seal rifts','lp':'Sele fendas','p':400,'t':1000}],'mine':300,'top':[]}," +
            "{'i':3,'key':'c','state':'locked','pct':0,'title':{'en':'The Climb','pt':'A Subida'},'goals':[],'mine':0,'top':[]}],'done':1," +
            "'record':[{'season':1,'name':'Dawn','title':{'en':'The First Flame','pt':'A Primeira Chama'},'chapters':[{'i':1,'title':{'en':'Spark','pt':'Fagulha'},'top':[{'n':'Vex','p':5000}]}]}]}", Sc + "chronicle.lua, chronicle_core.lua (X.payload and K.payload)");

        static FakeMsg ChronicleMem() => M(ChroniclePanel.Opcode, "mem",
            "{'season':3,'records':true,'fallen':true,'ask':false,'firsts':[{'t':'First rift sealed','n':'Vex','at':1699000000}],'recs':[{'t':'Highest hit','v':'12,400','n':'Mira','c':'Ranger','at':1699100000}]," +
            "'falls':[{'n':'Zed','l':310,'c':'Warden','k':'a Ghoul','at':1699200000}]}", Sc + "memorial.lua, memorial_core.lua (mem)");

        // ------------------------------------------------------------------------------------ 240 inspect (inspect.lua: result, equip, records; inspect_core.lua)
        static List<FakeMsg> InspectAnswer(string name)
        {
            string n = (name ?? InspectName).Replace('\'', ' ');
            var o = new List<FakeMsg>();
            o.Add(M(InspectPanel.Opcode, "result",
                "{'name':'" + n + "','level':310,'voc':'Juggernaut','vocId':8,'ascended':true,'guild':{'name':'Ash Wardens','rank':'Leader'},'ach':420,'rift':14,'trials':3,'outfit':{'type':128,'head':78,'body':68,'legs':58,'feet':76,'addons':3,'mount':0}," +
                "'self':false,'parts':1,'title':'Slayer','paragon':120,'passive':{'spent':84,'total':120},'bestiary':{'points':220,'rank':'Hunter'},'bosses':{'got':12,'total':40},'pvp':{'name':'Arena','tier':'Gold','rating':1620},'collection':540," +
                "'combat':{'attack':980,'hit':1450,'maxHit':3200,'attackSpeed':0.12,'critChance':0.2,'critAmount':0.5,'lifeLeech':{'chance':0.05,'amount':0.04},'defense':420,'armor':380,'mitigation':0.18,'maxHealth':14500,'maxMana':6200,'moveSpeed':240," +
                "'damage':[{'k':'fire','pct':20}],'resist':[{'k':'fire','pct':15},{'k':'ice','pct':-5}]}}", Sc + "inspect.lua, inspect_core.lua (result)"));
            o.Add(M(InspectPanel.Opcode, "equip",
                "{'name':'" + n + "','part':1,'rows':[{'slot':1,'tip':{'name':'Ashen Helm','id':3031,'count':1,'rarity':3,'unique':false,'look':{'cid':3031}}},{'slot':4,'tip':{'name':'Warden Plate','id':3043,'count':1,'rarity':4,'unique':true,'look':{'cid':3043}}}," +
                "{'slot':6,'tip':{'name':'Ashen Blade','id':3035,'count':1,'rarity':2,'unique':false,'look':{'cid':3035}}}]}", Sc + "inspect.lua, inspect_core.lua, item_tooltip_core.lua (equip)"));
            o.Add(M(InspectPanel.Opcode, "records",
                "{'name':'" + n + "','rows':[{'key':'drop','name':'Best drop','value':'Ashen Blade'},{'key':'tower','name':'Infinity Tower floor','value':41},{'key':'rift','name':'Highest rift tier','value':14}]}", Sc + "inspect.lua, inspect_core.lua (records)"));
            return o;
        }

        // ------------------------------------------------------------------------------------ 205 descent info (descent.lua X.sendInfo)
        static FakeMsg DescentInfo() => M(DescentState.Opcode, "info",
            "{'name':'The Ember Descent','minLevel':100,'level':310,'maxPlayers':4,'rooms':[8,12],'freeDaily':true,'freeDailyCount':2,'freeWeekly':false,'nextDaily':0,'sigils':1," +
            "'craft':{'shards':20,'gold':50000,'haveShards':35,'haveGold':350000,'name':'Ember Sigil'},'best':9,'bestClear':false,'runs':14,'clears':3,'weekBest':7,'week':'2026-w45','weekSeed':4711," +
            "'titles':[{'text':'Cinder Walker','depth':5,'held':true},{'text':'Ember Lord','clear':true,'held':false}],'inRun':false,'timeLimit':900}", Sc + "descent.lua (X.sendInfo)");

        // ------------------------------------------------------------------------------------ 251 invasion calendar (invasion.lua V.calendar)
        static FakeMsg InvasionCalendar() => M(InvasionState.Opcode, "calendar",
            "{'list':[{'kind':'invasion','at':1700007200,'inSeconds':7200,'when':'Wed 19:30','name':'Ash Horde invades Ashen Fields'},{'kind':'merchant','at':1700050000,'inSeconds':50000,'when':'Thu 08:00','name':'The Wandering Merchant arrives'}," +
            "{'kind':'buff','at':1700003600,'inSeconds':0,'when':'until 20:00','name':'Victory: +20% experience'}],'open':true}", Sc + "invasion.lua, worldevents.lua (V.calendar)");

        // ------------------------------------------------------------------------------------ 233 guild siege (siege.lua S.sendInfo)
        static FakeMsg SiegeInfo() => M(SiegeState.Opcode, "info",
            "{'open':true,'phase':'idle','at':1700100000,'whenText':'Sat 20:00','inSeconds':90000,'signupsOpen':true,'signups':[{'name':'Ash Wardens','own':true},{'name':'Frost Order','own':false}],'capacity':16," +
            "'guild':'Ash Wardens','rank':3,'signed':true,'members':12,'canJoin':false,'joinReason':'','canLeave':true,'champions':[{'name':'Frost Order','untilText':'Sat 27 Nov 20:00'}],'status':'No siege is running.'," +
            "'rules':['Every Saturday at 20:00 server time: ten minutes of gathering, then a 45-minute war for the Chaos Obelisk.','The guild leader or a vice-leader signs up in the Guild Siege window; the guild needs 5 members.']}", Sc + "siege.lua (S.sendInfo)");

        // ------------------------------------------------------------------------------------ 236 arena (arena.lua S.sendState, arena_season.lua P.viewOf)
        static FakeMsg ArenaStateMsg() => M(ArenaState.Opcode, "state",
            "{'open':true,'ratings':{'1v1':{'rating':1500,'wins':8,'losses':5,'draws':1,'best':1540},'2v2':{'rating':1420,'wins':3,'losses':4,'draws':0,'best':1480},'3v3':{'rating':1000,'wins':0,'losses':0,'draws':0,'best':1000}}," +
            "'modes':['1v1','2v2','3v3'],'queueCount':{'1v1':2,'2v2':0,'3v3':1},'rules':{'minLevel':50,'levelLow':260,'levelHigh':360,'countdown':10,'fight':300},'firstWinDone':false," +
            "'recent':[{'mode':'1v1','result':'win','before':1480,'after':1500,'opponents':'Vex','partner':'','reason':'defeat','at':1699990000},{'mode':'2v2','result':'loss','before':1450,'after':1420,'opponents':'Zed and Mira','partner':'Ember','reason':'timeout','at':1699980000}]," +
            "'now':1700000000,'season':{'id':3,'brackets':{'1v1':{'rating':1500,'rd':80,'matches':14,'wins':8,'losses':5,'draws':1,'peak':1540,'placed':true,'placementLeft':0,'tier':3,'tierName':'Gold','color':'#f6cf72','decayIn':0,'name':'Duel'}," +
            "'2v2':{'rating':1420,'rd':120,'matches':7,'wins':3,'losses':4,'draws':0,'peak':1480,'placed':false,'placementLeft':3,'tier':1,'tierName':'Ashen','color':'#a89c86','decayIn':0,'name':'Team'},'3v3':{'rating':1000,'rd':350,'matches':0,'wins':0,'losses':0,'draws':0,'peak':1000,'placed':false,'placementLeft':5,'tier':1,'tierName':'Ashen','color':'#a89c86','decayIn':0,'name':'Warband'}}}}",
            Sc + "arena.lua, arena_season.lua (S.sendState and P.viewOf)");

        // ------------------------------------------------------------------------------------ 200 battleground (battleground.lua B.stateOf, battleground_core.lua K.rewardPreview)
        static FakeMsg BattlegroundStateMsg() => M(BattlegroundState.Opcode, "state",
            "{'open':true,'enabled':true,'minLevel':100,'level':310,'realm':'main','roles':['tank','healer','dps'],'role':'dps','honor':640,'weekHonor':210,'weekCap':1500,'firstWinDone':false," +
            "'record':{'matches':22,'wins':12,'losses':9,'draws':1,'kills':140,'captures':31},'deserter':0,'now':1700000000," +
            "'rules':{'teamMin':5,'teamMax':10,'win':1000,'match':900,'wave':15,'prep':30,'partyMax':5},'bracket':{'key':'b3','name':'Level 300 to 399','ref':350},'waiting':6,'est':45," +
            "'season':{'id':3,'endsIn':900000,'order':['1v1','2v2','3v3','bg'],'placement':5,'weeks':8,'decay':{'from':2000,'perWeek':30,'graceDays':14}," +
            "'brackets':{'1v1':{'name':'Duel','rating':1500,'wins':8,'losses':5,'draws':1,'placed':true,'tier':3,'tierName':'Gold','color':'#f6cf72'},'2v2':{'name':'Team','rating':1420,'wins':3,'losses':4,'draws':0,'placed':false,'placementLeft':3}," +
            "'3v3':{'name':'Warband','rating':1000,'wins':0,'losses':0,'draws':0,'placed':false,'placementLeft':5},'bg':{'name':'Battleground','rating':1610,'wins':12,'losses':9,'draws':1,'placed':true,'tier':4,'tierName':'Platinum','color':'#7fb8e8'}}," +
            "'tiers':[{'key':'ashen','name':'Ashen','color':'#a89c86','min':0,'honor':50},{'key':'gold','name':'Gold','color':'#f6cf72','min':1500,'title':'Gold Warrior','frame':'Gold','cosmetics':['aura'],'honor':300}]}," +
            "'vendor':[{'key':'v1','name':'Ember Banner','cost':300,'kind':'cosmetic','can':true,'owned':false},{'key':'v2','name':'Honor Potion','cost':100,'kind':'item','can':true,'item':3031},{'key':'v3','name':'War Cloak','cost':900,'kind':'cosmetic','can':false,'why':'Needs more honor','owned':false}]}",
            Sc + "battleground.lua, battleground_core.lua, arena_season.lua (B.stateOf)");

        // ------------------------------------------------------------------------------------ 209 orb exchange (orbexchange.lua X.meta, X.book, X.mine)
        static FakeMsg OrbMeta() => M(OrbExchangeState.Opcode, "meta",
            "{'orbs':[{'k':'fate','n':'Orb of Fate','item':29857},{'k':'upheaval','n':'Orb of Upheaval','item':29856}],'fees':{'goldBps':200,'orbPairGold':1000},'min':{'gold':10,'orb':1},'max':{'gold':100000000,'orb':10000}," +
            "'durations':[1,3,7],'defaultDuration':7,'maxOpen':10,'realm':'main','realmName':'Main','gold':1200000,'have':{'fate':20,'upheaval':5},'hours':24}", Sc + "orbexchange.lua, orbexchange_config.lua (X.meta)");

        static FakeMsg OrbBook(string b, string q, int seq) => M(OrbExchangeState.Opcode, "book",
            "{'base':'" + b + "','quote':'" + q + "','asks':[{'p':1250,'q':5,'n':1,'t':6250},{'p':1300,'q':12,'n':3,'t':15600}],'bids':[{'p':1180,'q':8,'n':2,'t':9440},{'p':1100,'q':20,'n':4,'t':22000}]," +
            "'last':1200,'open':1150,'high':1250,'low':1100,'change':4.3,'vol':120,'volQuote':144000,'points':[{'h':1,'p':1150,'v':10},{'h':8,'p':1180,'v':40},{'h':16,'p':1200,'v':70}]," +
            "'trades':[{'ago':120,'p':1200,'q':2,'side':'buy'}],'mine':1,'hours':24,'seq':" + seq + "}", Sc + "orbexchange.lua (X.book)");

        static FakeMsg OrbMine() => M(OrbExchangeState.Opcode, "mine",
            "{'open':[{'id':41,'give':'fate','giveQty':5,'want':'gold','wantQty':6000,'given':2,'got':2400,'state':'active','left':86400,'at':1699990000}]," +
            "'closed':[{'id':39,'give':'gold','giveQty':12000,'want':'fate','wantQty':10,'given':12000,'got':10,'state':'filled','left':0,'at':1699900000}]," +
            "'fills':[{'ago':3600,'order':41,'gave':'fate','gaveQty':2,'got':'gold','gotQty':2352,'fee':48,'role':'maker'}],'owed':0,'max':10}", Sc + "orbexchange.lua (X.mine)");

        // ------------------------------------------------------------------------------------ 199 gamble (gamble.lua P.send, gamble_core.lua K.payload)
        static FakeMsg GambleStateMsg() => M(GambleState.Opcode, "state",
            "{'w':12,'items':[{'i':1,'id':2400,'c':3031,'n':'ashen blade','s':'weapon','sn':'Weapon','l':310,'p':250000},{'i':2,'id':2401,'c':3043,'n':'warden plate','s':'armor','sn':'Armor','l':320,'p':310000}," +
            "{'i':3,'id':2402,'c':3035,'n':'cinder ring','s':'ring','sn':'Ring','l':300,'p':180000,'sold':true},{'i':4,'id':2403,'c':3031,'n':'hollow crown','s':'head','sn':'Helmet','l':330,'p':420000}]," +
            "'level':310,'gate':330,'near':true,'money':900000,'left':5400,'hours':4,'at':'18:00','tz':'UTC+0','reroll':50000,'rerolls':0,'rerollMax':2," +
            "'odds':[{'r':1,'n':'Common','p':60.5},{'r':2,'n':'Uncommon','p':25},{'r':3,'n':'Rare','p':10.5}],'npc':'Brokk the Gambler','last':{'r':3,'rn':'Rare','n':'cinder ring','l':300,'c':3035}}", Sc + "gamble.lua, gamble_core.lua (K.payload)");

        // ------------------------------------------------------------------------------------ 174 ember cache (embercache.lua E.view, embercache_core.lua K.view, daybook_core.lua D.view)
        static FakeMsg EmberState() => M(EmberCacheState.Opcode, "state",
            "{'open':1,'week':{'pts':340,'got':1,'sparks':3,'ends':200000,'tiers':[{'p':100,'g':5000,'it':[[3031,2,'Gold Coin']]},{'p':300,'g':20000,'it':[]},{'p':600,'g':60000,'it':[[3043,1,'Crystal Coin']]}]}," +
            "'day':{'pts':55,'raw':30,'bonus':20,'goal':50,'spark':1,'ends':30000,'g':2000,'it':[]}," +
            "'src':[['kill',1,10,200,35],['dungeon',20,1,5,1],['offering',1,5,10,0]]," +
            "'book':{'xp':1200000,'lv':3,'kills':450,'loot':300000,'sup':120000,'orbs':4,'uniq':1,'rares':6,'deaths':0,'secs':5400,'pts':55}}", Sc + "embercache.lua, embercache_core.lua, daybook_core.lua (E.view)");

        // ------------------------------------------------------------------------------------ 206 loadouts (loadouts.lua L.state, slotView)
        static FakeMsg LoadoutsStateMsg() => M(LoadoutsState.Opcode, "state",
            "{'slots':[{'slot':1,'locked':false,'active':true,'name':'Fire build','icon':'skills','updated':1699990000,'voc':'Pyromancer','cls':'fire','points':84,'pointsTotal':120,'keystones':['Ember Heart'],'paragon':12," +
            "'supports':{'count':2,'spells':[{'name':'Fireball','runes':['Echo','Fork']}]},'gear':{'total':6,'ready':6,'missing':[]},'warnings':[]}," +
            "{'slot':2,'locked':false,'active':false,'name':'Ward build','icon':'inventory','updated':1699900000,'voc':'Pyromancer','cls':'fire','points':70,'pointsTotal':120,'keystones':[],'paragon':0," +
            "'supports':{'count':0,'spells':[]},'gear':{'total':6,'ready':4,'missing':[{'slot':1,'name':'Ashen Helm','where':'depot'}]},'warnings':['When loaded: 4 points are refunded.']}," +
            "{'slot':3,'locked':false,'active':false,'empty':true},{'slot':4,'locked':true,'active':false,'empty':true}]," +
            "'limit':3,'max':8,'active':1,'level':310,'minLevel':50,'cooldown':0,'cooldownSeconds':60,'castMs':3000,'inPz':true,'nextUnlock':400,'casting':false,'nameMax':20,'icons':['skills','inventory','options'],'baseSlots':3,'unlockLevels':[100,200,300,400,500]," +
            "'live':{'points':84,'pointsTotal':120,'paragon':12,'runes':2}}", Sc + "loadouts.lua, loadouts_core.lua (L.state)");

        // ------------------------------------------------------------------------------------ 243 spell supports (supports.lua sendState, sendBar)
        static FakeMsg SupportsState() => M(SpellSupportsState.Opcode, "state",
            "{'level':310,'orbId':24692,'orbClientId':24692,'orbName':'Orb of Sockets','orbCount':3,'orbsNeeded':2," +
            "'spells':[{'id':1,'name':'Fireball','words':'exevo flam','level':20,'kind':'single','kindName':'single target','count':2,'max':3,'opened':false,'secondLevel':40,'thirdLevel':100,'canOpen':true," +
            "'runes':[{'slot':1,'id':5,'clientId':24700,'key':'echo','name':'Echo','level':10,'color':'#c0501a','text':'Repeats the hit once.','cost':5000}]}," +
            "{'id':2,'name':'Ash Storm','words':'exevo gran','level':60,'kind':'area','kindName':'area','count':3,'max':3,'opened':true,'secondLevel':80,'thirdLevel':140,'canOpen':false,'runes':[]}]," +
            "'runes':[{'id':5,'clientId':24700,'key':'echo','name':'Echo','level':10,'color':'#c0501a','text':'Repeats the hit once.','fits':'single','count':1,'combine':false}," +
            "{'id':6,'clientId':24701,'key':'fork','name':'Fork','level':10,'color':'#3a6fc0','text':'Hits one more target.','fits':'single and area','count':4,'combine':true}]}", Sc + "supports.lua (sendState)");

        static FakeMsg SupportsBar() => M(SpellSupportsState.Opcode, "bar",
            "{'spells':{'1':[{'slot':1,'id':5,'key':'echo','name':'Echo','level':10,'color':'#c0501a','text':'Repeats the hit once.'}]},'words':{'exevo flam':1,'exevo gran':2}}", Sc + "supports.lua (sendBar)");

        // ------------------------------------------------------------------------------------ 222 chaos pact (pact.lua sendStatus)
        static FakeMsg PactStatus(bool open) => M(PactState.Opcode, "status",
            "{'open':" + (open ? "true" : "false") + ",'name':'Chaos Pact','active':true,'endsAt':1702000000,'ends':'2026-12-08 12:00','daysLeft':24,'totalDays':30,'dailyMarks':5,'canClaim':true,'claimedTotal':12," +
            "'marks':85,'marksEarned':140,'shelf':[{'key':'cape','marks':60,'name':'Ashen Cape','owned':false},{'key':'aura','marks':120,'name':'Ember Aura','owned':false,'monthly':true,'endsAt':1702000000},{'key':'frame','marks':30,'name':'Pact Frame','owned':true}]," +
            "'monthExp':1800000,'monthExpAccount':2600000,'month':11,'premiumDays':24,'coins':250,'title':'Pact Bearer','titleText':'Pact Bearer'," +
            "'limits':[{'key':'stash','label':'Stash tabs','free':3,'pact':2,'pactActive':true,'extra':1,'maxExtra':4,'total':6},{'key':'builds','label':'Saved builds','free':3,'pact':3,'pactActive':true,'extra':0,'maxExtra':0,'total':6}]," +
            "'tabSize':30,'special':[{'name':'Orbs','owned':true},{'name':'Keys','owned':false}],'buildLimit':6,'builds':[{'slot':1,'name':'Fire route','nodes':84,'cls':'fire','editable':true,'updated':1699990000}]}", Sc + "pact.lua, pact_core.lua (sendStatus)");

        // ------------------------------------------------------------------------------------ 176 candlemarks (candlemarks.lua, candlemarks_core.lua K.view)
        static FakeMsg CandleState() => M(CandlemarksState.Opcode, "state",
            "{'balance':14,'progress':900,'block':1800,'earning':true,'today':3,'cap':10,'level':310,'weekEnds':400000,'near':true," +
            "'offers':[{'k':'o1','n':'Ember Lantern','b':'','d':'A lantern that never burns out.','p':6,'w':2,'u':1,'l':100,'c':3031,'kind':'item'}," +
            "{'k':'o2','n':'Pocket boss ticket','b':'Vorn the Hollow','d':'A private fight with Vorn.','p':10,'w':1,'u':0,'l':200,'c':3043,'kind':'pocketboss'}," +
            "{'k':'o3','n':'Ash Cloak','b':'','d':'A cosmetic cloak.','p':30,'w':0,'u':0,'l':50,'c':3035,'kind':'cosmetic','own':true}]}", Sc + "candlemarks.lua, candlemarks_core.lua (K.view)");

        // ------------------------------------------------------------------------------------ 238 loot filter (lootfilter.lua sendSettings, the kill message)
        static FakeMsg LootSettings(bool open) => M(LootFilterModel.Opcode, "settings",
            "{'s':{'highlight':3,'dim':0,'lootMin':0,'lootFrom':0,'show':{'equipment':true,'currency':true,'supplies':true,'other':true},'icons':true,'notify':true,'tier':0},'unlocked':true," +
            "'presets':[{'key':'all','name':'Show everything','desc':'Nothing is hidden.'},{'key':'rare','name':'Rare and better','desc':'Dims common items.'}]," +
            "'samples':{'gear':3031,'unique':3043,'orb':3035,'coin':3031,'supply':3043,'other':3035},'open':" + (open ? "true" : "false") + ",'snd':{'rules':{'unique':1,'orb':2},'vol':60,'mute':false,'hunt':true}," +
            "'rules':[{'key':'unique','name':'Uniques'},{'key':'orb','name':'Orbs'}],'sounds':[{'id':1,'key':'chime','name':'Chime'},{'id':2,'key':'bell','name':'Bell'}],'counts':{'session':{'unique':1,'orb':3},'total':{'unique':12,'orb':140}}}",
            Sc + "lootfilter.lua (sendSettings)");

        static FakeMsg LootKillSample() => M(LootFilterModel.Opcode, "kill",
            "{'k':1,'m':'Ghoul','items':[{'n':1,'id':3031,'c':1,'r':3,'t':2,'u':false,'o':false,'pw':false,'g':'equipment','nm':'Ashen Helm'},{'n':2,'id':3043,'c':4,'r':0,'g':'currency','nm':'Gold Coin'},{'n':3,'id':3035,'c':1,'o':true,'g':'currency','nm':'Orb of Fate'}]," +
            "'counts':{'session':{'unique':1,'orb':4},'total':{'unique':12,'orb':141}},'hits':{'orb':1}}", Sc + "lootfilter.lua (the kill message)");

        // ------------------------------------------------------------------------------------ 192 hideout (hideout.lua M.sendState, hideout_core.lua K.layoutView, K.catalogueView, K.themesView)
        static FakeMsg HideoutStateMsg() => M(HideoutState.Opcode, "state",
            "{'open':true,'me':1,'inside':{'owner':1,'ownerName':'Ember','isOwner':true,'origin':{'x':100,'y':100,'z':7}},'layout':{'w':9,'h':7,'arrival':[2,2],'reserved':[[1,1,'depot'],[8,1,'stash'],[5,6,'waystone']]}," +
            "'hideout':{'theme':'ash','themeName':'Ashen Hold','perm':1,'likes':3,'visits':12,'count':2,'max':30}," +
            "'themes':[{'key':'ash','name':'Ashen Hold','desc':'Warm stone and embers.','how':'Every character','owned':true,'selected':true,'maxDecor':30,'item':3031},{'key':'frost','name':'Frozen Keep','desc':'Blue ice.','how':'Season journey','owned':false,'selected':false,'maxDecor':36,'item':3043}]," +
            "'catalogue':[{'key':'rug','name':'Ember Rug','cat':'floor','source':'default','how':'Every character','layer':'floor','item':3031,'placed':1,'max':4,'owned':true,'block':false,'rots':[[[0,0,3031]]]}," +
            "{'key':'brazier','name':'Standing Brazier','cat':'light','source':'achievement','how':'Achievement: Walker','layer':'object','item':3043,'placed':1,'max':2,'owned':true,'block':true,'rots':[[[0,0,3043]]]}," +
            "{'key':'banner','name':'Ash Banner','cat':'wall','source':'faction','how':'Ash Wardens: Trusted','layer':'wall','item':3035,'placed':0,'max':3,'owned':false,'block':false,'rots':[[[0,0,3035]]],'wallW':[[0,0,3035]]}]," +
            "'placed':[{'id':1,'key':'rug','x':3,'y':3,'r':1},{'id':2,'key':'brazier','x':6,'y':3,'r':1}],'permissions':[{'id':0,'name':'Private','desc':'Nobody can visit.'},{'id':1,'name':'Friends','desc':'Your VIP list can visit.'}]," +
            "'categories':[{'key':'floor','name':'Floors'},{'key':'light','name':'Lights'},{'key':'wall','name':'Wall'}]}", Sc + "hideout.lua, hideout_core.lua (M.sendState with layoutView and catalogueView)");

        static FakeMsg HideoutVisits() => M(HideoutState.Opcode, "visits",
            "{'friends':[{'guid':2,'name':'Mira','theme':'Ashen Hold','why':'friend','likes':5,'visits':20,'online':true}],'recent':[{'guid':3,'name':'Vex','theme':'Frozen Keep','at':'2 h ago'}]," +
            "'showcase':{'likes':[{'guid':3,'name':'Vex','theme':'Frozen Keep','likes':42,'visits':300}],'visits':[{'guid':2,'name':'Mira','theme':'Ashen Hold','likes':5,'visits':410}]}}", Sc + "hideout.lua (the visits message)");

        // ------------------------------------------------------------------------------------ 210 rift atlas, 159 waystone atlas (atlas.lua, waystone_atlas.lua; atlas_core.lua A.treePayload, waystone_atlas_core.lua WC.treePayload)
        static FakeMsg AtlasTree(bool rift)
        {
            string nodes =
                "[{'i':1,'n':'Start','k':'start','b':'','x':0,'y':0,'c':0,'l':[2,3,4],'t':[],'g':'" + (rift ? "density" : "rolls") + "'}," +
                "{'i':2,'n':'Dense Rifts','k':'small','b':'','x':80,'y':-40,'c':1,'l':[1,5],'t':['+3% monster density'],'g':'" + (rift ? "density" : "rolls") + "'}," +
                "{'i':3,'n':'Abyssal Ties','k':'notable','b':'abyss','x':-90,'y':20,'c':2,'l':[1,6],'t':['+10% abyssal loot'],'g':'theme'}," +
                "{'i':4,'n':'Crypt Keys','k':'small','b':'crypt','x':10,'y':90,'c':1,'l':[1,7],'t':['+2% crypt loot'],'g':'theme'}," +
                "{'i':5,'n':'Swarm','k':'keystone','b':'','x':170,'y':-70,'c':3,'l':[2],'t':['Packs are larger','Packs drop more'],'g':'" + (rift ? "density" : "rolls") + "'}," +
                "{'i':6,'n':'Deep Abyss','k':'small','b':'abyss','x':-170,'y':40,'c':1,'l':[3],'t':['+2% abyssal experience'],'g':'theme'}," +
                "{'i':7,'n':'Old Vaults','k':'notable','b':'crypt','x':20,'y':170,'c':2,'l':[4],'t':['+8% vault loot'],'g':'theme'}]";
            string branches = "[{'k':'abyss','n':'Abyss','th':'Abyssal Rift','d':1,'c':'#7a5ad8'},{'k':'crypt','n':'Crypt','th':'Ashen Crypt','d':2,'c':'#c8a040'}]";
            if (rift)
                return M(AtlasState.RiftOpcode, "tree",
                    "{'nodes':" + nodes + ",'branches':" + branches + ",'start':1,'keystoneMax':1,'grid':{'themes':['Abyssal Rift','Ashen Crypt'],'tiers':3,'omens':[{'k':'vorn','n':'Vorn','b':'Vorn the Hollow'}]," +
                    "'points':{'cell':1,'flawless':1,'swift':1,'omen':2},'swift':300,'swiftTiers':[300,280,260]},'max':40}", Sc + "atlas.lua, atlas_core.lua (A.treePayload)");
            return M(AtlasState.WaystoneOpcode, "tree",
                "{'kind':'waystone','nodes':" + nodes + ",'branches':" + branches + ",'start':1,'keystoneMax':1,'grid':{'tiers':3,'rows':[{'label':'Map I','color':'#d6c9ae','cells':[{'k':'w1.1','n':'Map I tier 1','c':1,'p':1,'co':'#7a5ad8'},{'k':'w1.2','n':'Map I tier 2','c':2,'p':1}]}," +
                "{'label':'Rare','color':'#f6cf72','cells':[{'k':'r1','n':'Rare waystone','c':1,'p':2}]}]},'max':40}", Sc + "waystone_atlas.lua, waystone_atlas_core.lua (WC.treePayload)");
        }

        static FakeMsg AtlasStateMsg(bool rift) => M(rift ? AtlasState.RiftOpcode : AtlasState.WaystoneOpcode, "state",
            "{'earned':6,'spent':3,'points':3,'max':40,'alloc':[2,3],'done':['" + (rift ? "c1.1" : "w1.1") + "','" + (rift ? "f1" : "r1") + "'],'refund':{'gold':10000,'orbs':1},'reset':{'gold':8000,'orbs':2},'orb':'Orb of Reset'," +
            "'totals':['+3% monster density','+10% abyssal loot']}", Sc + (rift ? "atlas.lua, atlas_core.lua (A.statePayload)" : "waystone_atlas.lua, waystone_atlas_core.lua (WC.statePayload)"));
    }
}
