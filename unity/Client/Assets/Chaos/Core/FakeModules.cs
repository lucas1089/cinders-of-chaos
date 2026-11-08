// Phase 11, track G: the module answers of the window smoke run (unity/README.md "Window smoke run"). Pure C#, no Unity types.
// The demo tour's fake server (Core/DemoTour.cs FakeGameServer) answers the base protocol and a few tour opcodes. With ModuleResponder on (only -chaosWindowSmoke) it
// also answers the requests a Chaos window sends on opening, one small sample message set per opcode, in the shape the server sends it: the Source of each entry names the
// server file that builds the message (server/data/scripts/chaos/*.lua; the number tables are samples, the keys are the server's, checked by the module list in
// Core.Tests/FakeModulesTests.cs against what the Unity parsers read). Payloads over 8192 bytes leave the fake server in parts exactly like Chaos.send does
// (the server's Out.Ext splits with ExtChunks.Split). Context HUDs that wait for a server push (raid, arena, rift ...) get theirs from Context(): the smoke run sends it
// before the step and clears it after.
using System;
using System.Collections.Generic;
using System.Linq;

namespace Chaos.Core
{
    /// <summary>One message the fake server sends: an extended opcode and the whole JSON root ({action, data}, or flat like the Infinity Tower's).</summary>
    public sealed class FakeMsg
    {
        public byte Op;
        public object Root;
        public string Source = "";
        public string Action => Json.Text(Root, "action");
    }

    /// <summary>A module the responder covers: its opcode, the server file that sends it, the windows that show it and the request actions it answers.</summary>
    public sealed class FakeModule
    {
        public string Name = "", Source = "";
        public byte Op;
        public string[] Windows = new string[0], Requests = new string[0];
    }

    /// <summary>A context HUD: the window class, the pushes that make it open, and (when no push can open it) why the run cannot show it.</summary>
    public sealed class FakeContext
    {
        public string Window = "", Source = "", Reason = "";
        public readonly List<FakeMsg> Pushes = new List<FakeMsg>();
        /// <summary>Server messages that end the context after the step (the rest is cleared in the player: see ChaosApp.Smoke.cs).</summary>
        public readonly List<FakeMsg> Close = new List<FakeMsg>();
        public bool Drivable => Reason.Length == 0;
    }

    public static partial class FakeModules
    {
        /// <summary>Single quotes stand for double quotes in the samples below (no apostrophes in the texts).</summary>
        static object J(string text) => Json.Parse(text.Replace('\'', '"'));

        static FakeMsg M(byte op, string action, string data, string source)
        {
            var root = new Dictionary<string, object> { { "action", action } };
            if (data != null) root["data"] = J(data);
            return new FakeMsg { Op = op, Root = root, Source = source };
        }

        /// <summary>A flat message: the fields sit next to "action" (the Infinity Tower).</summary>
        static FakeMsg Flat(byte op, string json, string source) => new FakeMsg { Op = op, Root = J(json), Source = source };

        const string Sc = "server/data/scripts/chaos/";

        // ------------------------------------------------------------------------------------ what is covered
        static readonly IList<FakeModule> BaseModules = new List<FakeModule>
        {
            Mod("achievements", AchievementsState.OpcodeId, "achievements.lua", "AchievementsWindow", "open", "get"),
            Mod("bestiary", BestiaryState.OpcodeId, "bestiary.lua", "BestiaryWindow", "open", "list", "summary", "entry", "board", "query"),
            Mod("charms", CharmsState.OpcodeId, "charms.lua", "CharmsWindow", "open"),
            Mod("seasonpass", PassState.OpcodeId, "seasonpass.lua", "PassWindow", "open", "tiers"),
            Mod("season", SeasonState.OpcodeId, "season.lua", "SeasonWindow", "open"),
            Mod("daily", DailyState.OpcodeId, "daily.lua", "DailyWindow", "open"),
            Mod("weeklychest", WeeklyState.OpcodeId, "weeklychest.lua", "WeeklyChestWindow", "open"),
            Mod("cosmetics", CosmeticsState.OpcodeId, "cosmetics.lua", "CosmeticsWindow", "open", "hello", "wardrobe"),
            Mod("transmog", TransmogState.OpcodeId, "transmog.lua", "TransmogWindow", "open", "looks"),
            Mod("pets", PetsState.OpcodeId, "pets.lua", "PetsWindow", "open"),
            Mod("professions", ProfessionsState.OpcodeId, "professions.lua", "ProfessionsWindow", "open"),
            Mod("crafting", CraftingState.OpcodeId, "crafting.lua", "CraftingWindow", "open"),
            Mod("crafttable", CraftTableState.OpcodeId, "tests/fixtures/base_crafting/1crafting_mod.lua", "CraftTableWindow", "fetch"),
            Mod("hunt", HuntTracker.Opcode, "hunt.lua", "HuntWindow", "open", "query"),
            Mod("goals", Goals.Opcode, "goals.lua", "GoalsWindow", "open", "tracker"),
            Mod("guild", GuildPanel.Opcode, "guild.lua", "GuildWindow", "open", "refresh"),
            Mod("guildwar", GuildWarPanel.Opcode, "guildwar.lua", "GuildWarWindow", "open", "refresh"),
            Mod("partyfinder", PartyFinderPanel.Opcode, "party_finder.lua", "PartyFinderWindow", "open", "refresh"),
            Mod("groupqueue", GroupQueuePanel.Opcode, "groupqueue.lua", "GroupQueueWindow", "open", "query"),
            Mod("tower", TowerState.Opcode, "infinitytower.lua", "TowerWindow", "request", "state"),
        };

        /// <summary>The covered modules: the phase 11 list and the phase 12 track H one (Core/FakeModulesP12.cs).</summary>
        public static readonly IList<FakeModule> Catalog = BuildCatalog();

        static IList<FakeModule> BuildCatalog()
        {
            var all = new List<FakeModule>(BaseModules);
            all.AddRange(Phase12Modules());
            return all;
        }

        static FakeModule Mod(string name, byte op, string file, string window, params string[] requests) =>
            new FakeModule { Name = name, Op = op, Source = file.StartsWith("tests/", StringComparison.Ordinal) ? "server/" + file : Sc + file, Windows = new[] { window }, Requests = requests };

        public static FakeModule ModuleOf(byte op) => Catalog.FirstOrDefault(m => m.Op == op);

        // ------------------------------------------------------------------------------------ the answers
        /// <summary>The messages the server sends back for a request {action, data} of an opcode. Empty for an opcode or action not covered.</summary>
        public static List<FakeMsg> Answer(byte op, object request)
        {
            string action = Json.Text(request, "action");
            object data = Json.Get(request, "data");
            var o = new List<FakeMsg>();
            if (op == AchievementsState.OpcodeId && (action == "open" || action == "get"))
            {
                o.Add(AchState(action == "open"));
                o.Add(AchTrack());
                o.Add(AchList());
            }
            else if (op == BestiaryState.OpcodeId)
            {
                if (action == "open" || action == "summary") o.Add(BestSummary(action == "open"));
                if (action == "list") o.Add(BestList());
                if (action == "entry") o.Add(BestEntry(Json.Int(data, "id", 1)));
                if (action == "board") o.Add(BestBoard());
                if (action == "query") o.Add(BestTracker(false));   // no task taken: the tracker HUD stays shut except in its own context step
            }
            else if (op == CharmsState.OpcodeId && action == "open") o.Add(CharmState());
            else if (op == PassState.OpcodeId)
            {
                if (action == "open") o.Add(PassStateMsg());
                if (action == "tiers") o.Add(PassTiers(Json.Int(data, "season", 3)));
            }
            else if (op == SeasonState.OpcodeId && action == "open") { o.Add(SeasonOverview()); o.Add(SeasonJourney()); o.Add(SeasonChapter()); }
            else if (op == DailyState.OpcodeId && action == "open") o.Add(DailyOpen());
            else if (op == WeeklyState.OpcodeId && action == "open") o.Add(WeeklyStateMsg());
            else if (op == CosmeticsState.OpcodeId)
            {
                if (action == "open") o.Add(CosmeticsStateMsg(true));
                if (action == "hello") { o.Add(CosmeticsStyle()); o.Add(CosmeticsColors()); }
                if (action == "wardrobe") o.Add(CosmeticsWardrobe());
            }
            else if (op == TransmogState.OpcodeId)
            {
                if (action == "open") o.Add(TransmogStateMsg());
                if (action == "looks") o.Add(TransmogLooks(Json.Text(data, "kind", "helmet")));
            }
            else if (op == PetsState.OpcodeId && action == "open") o.Add(PetsStateMsg());
            else if (op == ProfessionsState.OpcodeId && action == "open") o.Add(ProfessionsStateMsg());
            else if (op == CraftingState.OpcodeId && action == "open") { o.Add(CraftingInfo()); o.Add(CraftingStateMsg()); }
            else if (op == CraftTableState.OpcodeId && action == "fetch") { o.Add(CraftTableFetch(Json.Text(data, "category", "mining"), Json.Int(data, "page", 1))); o.Add(CraftTableMoney()); }
            else if (op == HuntTracker.Opcode && (action == "open" || action == "query")) o.Add(HuntStateMsg());
            else if (op == Goals.Opcode)
            {
                if (action == "open") { o.Add(GoalsMsg()); o.Add(GoalsTracker()); }
                if (action == "tracker") o.Add(GoalsTracker());
            }
            else if (op == GuildPanel.Opcode && (action == "open" || action == "refresh")) o.Add(GuildStateMsg());
            else if (op == GuildWarPanel.Opcode && (action == "open" || action == "refresh")) o.Add(GuildWarStateMsg());
            else if (op == PartyFinderPanel.Opcode)
            {
                if (action == "open") o.Add(PartyFinderInit());
                if (action == "open" || action == "refresh") o.Add(PartyFinderList());
            }
            else if (op == GroupQueuePanel.Opcode && (action == "open" || action == "query")) o.Add(GroupQueueState());
            else if (op == TowerState.Opcode && (action == "request" || action == "state"))
            {
                if (action == "request") o.Add(TowerOpen());
                if (action == "state") o.Add(Flat(TowerState.Opcode, "{'action':'state','inRun':false,'canSkip':false,'floor':0,'nextBoss':false}", Sc + "infinitytower_run.lua (sendState)"));
            }
            if (o.Count == 0) o.AddRange(Answer12(op, action, data));   // phase 12, track H: Core/FakeModulesP12.cs
            return o;
        }

        // ------------------------------------------------------------------------------------ 250 achievements (achievements.lua sendState, sendTrack, K.view)
        static FakeMsg AchState(bool open) => M(AchievementsState.OpcodeId, "state",
            "{'open':" + (open ? "true" : "false") + ",'points':30,'accountPoints':55,'maxPoints':900,'unlocked':2,'total':5," +
            "'categories':[{'key':'hunt','name':'Hunting','done':1,'total':3,'points':10,'max':40},{'key':'misc','name':'Journey','done':1,'total':2,'points':20,'max':60}]," +
            "'recent':[{'id':2,'name':'First Blood','points':5,'at':1700000000}],'titles':[{'key':'achievement:1','text':'Slayer','at':1700000000}],'titlesOn':true,'activeTitle':'Slayer','heldTitles':[{'key':'achievement:1','text':'Slayer'}]}",
            Sc + "achievements.lua");

        static FakeMsg AchTrack() => M(AchievementsState.OpcodeId, "track",
            "{'ap':120,'steps':[{'n':'Ember','k':'killfx','p':100,'d':'Burns. Reward track: 100 points.'},{'n':'Azure','k':'chatcolor','p':500,'c':'#4a8cff'}]," +
            "'cats':[{'key':'hunt','cn':'Hunting','n':'Hunter','k':'lootbeam','t':2,'dn':1,'x':0,'ti':'Hunter'}]}", Sc + "achievements.lua, cosmetics_core.lua (sendTrack and trackView)");

        static FakeMsg AchList() => M(AchievementsState.OpcodeId, "list",
            "{'first':true,'last':true,'rows':[{'i':1,'n':'First Blood','p':5,'d':'Kill one monster.','c':'hunt','t':1,'v':1,'u':1700000000,'ti':'Slayer'}," +
            "{'i':2,'n':'Walker','p':10,'d':'Walk 2000 steps.','c':'misc','t':2000,'v':500,'u':0,'r':'A pair of boots'}," +
            "{'i':3,'n':'Pack Hunter','p':15,'d':'Kill 500 monsters.','c':'hunt','t':500,'v':120,'u':0}," +
            "{'i':4,'n':'Secret','p':50,'d':'A hidden achievement. Keep playing to find it.','c':'hunt','t':0,'v':0,'u':0,'h':1}," +
            "{'i':5,'n':'Explorer','p':10,'d':'Visit ten towns.','c':'misc','t':10,'v':10,'u':1700100000}]}", Sc + "achievements.lua, achievements_core.lua (list rows from K.view)");

        // ------------------------------------------------------------------------------------ 253 bestiary (bestiary.lua summary, sendList rowOf, entry; bestiary_core.lua)
        static FakeMsg BestSummary(bool open) => M(BestiaryState.OpcodeId, "summary",
            "{'open':" + (open ? "true" : "false") + ",'total':4,'known':3,'completed':1,'percent':25,'points':12,'stagePoints':9,'taskPoints':3,'count':4," +
            "'rank':{'name':'Scout','exp':1,'next':50,'nextName':'Hunter'},'cats':[{'key':'beast','name':'Beasts','known':2,'completed':1,'total':2},{'key':'undead','name':'Undead','known':1,'completed':0,'total':2}]," +
            "'diffs':[{'key':'easy','name':'Easy','kills':100,'bonus':1},{'key':'hard','name':'Hard','kills':400,'bonus':3}],'stages':['Seen','Studied','Known','Mastered']}", Sc + "bestiary.lua");

        static FakeMsg BestList() => M(BestiaryState.OpcodeId, "list",
            "{'first':true,'last':true,'rows':[[1,'Rat','beast','easy',1,120,3,100],[2,'Wolf','beast','easy',5,30,2,101],[3,'Ghoul','undead','hard',20,5,1,102],[4,'Lich','undead','hard',60,0,0,0]]}",
            Sc + "bestiary.lua (rowOf: id, name, cat, diff, level, kills, stage, look)");

        static FakeMsg BestEntry(int id) => M(BestiaryState.OpcodeId, "entry",
            "{'id':" + id + ",'name':'Rat','cat':'beast','diff':'easy','diffName':'Easy','level':1,'kills':120,'stage':3,'th':[10,50,100],'next':400,'boss':false,'points':3,'bonus':1,'spawns':true," +
            "'health':20,'exp':5,'elements':[{'name':'Physical','pct':100}],'immunities':[],'areas':['Rat Cellar'],'loot':[{'name':'Cheese','chance':40}],'task':{'can':true,'required':100,'active':false,'reward':{}}}", Sc + "bestiary.lua (entry)");

        static FakeMsg BestBoard() => M(BestiaryState.OpcodeId, "board",
            "{'active':1,'maxActive':3,'doneDay':2,'dailyLimit':3,'doneWeek':5,'weeklyLimit':10,'rerolls':1,'nextIn':7200,'offers':[],'tasks':[]}", Sc + "bestiary.lua (board)");

        static FakeMsg BestTracker(bool rows) => M(BestiaryState.OpcodeId, "tracker",
            rows ? "{'rows':[{'k':'task','label':'Rat','p':4,'r':10},{'k':'task','label':'Wolf','p':1,'r':5}]}" : "{'rows':[]}", Sc + "bestiary.lua (tracker)");

        // ------------------------------------------------------------------------------------ 198 charms (charms.lua CH.state, charms_core.lua C.viewOf, C.totalsView)
        static FakeMsg CharmState()
        {
            var cells = new List<string>();
            for (int y = 1; y <= 3; y++) for (int x = 1; x <= 4; x++) cells.Add("{'x':" + x + ",'y':" + y + ",'open':" + (x <= 3 ? "true" : "false") + ",'why':'level 100'}");
            return M(CharmsState.OpcodeId, "state",
                "{'cols':4,'rows':3,'max':2,'shards':7,'cells':[" + string.Join(",", cells) + "]," +
                "'placed':[{'id':9,'ref':'p1','x':1,'y':1,'w':2,'h':1,'name':'Ash','rarity':'Glowing','ilvl':30}]," +
                "'bag':[{'ref':'b1','sid':'5','iid':'77','w':1,'h':2,'name':'Cinder','rarity':'Rare','ilvl':20,'salvage':3,'reforge':4,'mods':[{'t':'+5% fire'}]}]," +
                "'totals':[{'t':'+9% fire','v':9,'cap':9}],'groups':[{'open':true,'text':'Level 100','cells':9}]}", Sc + "charms.lua");
        }

        // ------------------------------------------------------------------------------------ 227 season pass (seasonpass.lua, seasonpass_core.lua)
        static FakeMsg PassStateMsg() => M(PassState.OpcodeId, "state",
            "{'open':true,'season':{'id':3,'pass':'Ash Pass','name':'Season 3','tag':'[S3]','status':'active','endsIn':90000}," +
            "'tier':2,'maxTier':3,'into':40,'need':100,'premium':false,'claimed':['10','00'],'coins':50," +
            "'daily':{'resetIn':3600,'list':[{'text':'Kill 10 monsters','target':10,'progress':4,'xp':20}]},'sources':[{'name':'Hunt','today':3,'cap':10}]," +
            "'offers':[{'what':'premium','name':'Premium','price':300,'full':300},{'what':'up','name':'Upgrade','price':100,'full':300}]}", Sc + "seasonpass.lua");

        static FakeMsg PassTiers(int season) => M(PassState.OpcodeId, "tiers",
            "{'season':" + season + ",'total':3,'rows':[{'tier':1,'free':{'text':'Gold'},'premium':{'text':'Orb'}},{'tier':2,'free':{'text':'Orb'},'premium':{'text':'Frame'}},{'tier':3,'free':{'text':'Key'},'premium':{'text':'Mount'}}]}", Sc + "seasonpass.lua (tiers)");

        // ------------------------------------------------------------------------------------ 246 seasons (season.lua)
        static FakeMsg SeasonOverview() => M(SeasonState.OpcodeId, "state",
            "{'open':true,'season':{'name':'Ember','tag':'[E]','status':'active','endsIn':7200,'modifier':{'name':'Fury','description':'More damage'}}," +
            "'mine':{'eligible':true},'track':[{'name':'Level 50','reward':'A title','value':50,'progress':20},{'name':'Level 10','value':10,'progress':10,'unlocked':true}],'titles':['Emberborn']}", Sc + "season.lua");

        static FakeMsg SeasonJourney() => M(SeasonState.OpcodeId, "journey",
            "{'name':'Ash Road','mode':'Hardcore','current':2,'finished':1,'set':'Ash','pieces':1,'piecesTotal':4," +
            "'chapters':[{'key':'a','name':'Wake','state':'done','done':3,'total':3},{'key':'b','name':'Walk','state':'open','done':1,'total':4},{'key':'c','name':'Climb','state':'locked','level':200,'lockedWhy':'Level 200'}]}", Sc + "season_journey.lua (journey)");

        static FakeMsg SeasonChapter() => M(SeasonState.OpcodeId, "journeyChapter",
            "{'index':2,'objectives':[{'text':'Kill 10 monsters','target':10,'progress':4},{'text':'Reach level 20','target':1,'done':true}],'rewards':[{'text':'Boots','piece':true}]}", Sc + "season_journey.lua (journeyChapter)");

        // ------------------------------------------------------------------------------------ 207 daily (daily.lua), 117 weekly chest (weeklychest.lua)
        static FakeMsg DailyOpen() => M(DailyState.OpcodeId, "OpenDailyWindow",
            "{'Day':2,'TakenReward':0,'NextIn':7200,'Login':1,'DAILY_REWARDS':[{'ClientID':3031,'Count':10},{'ClientID':3031,'Count':20},{'ClientID':3031,'Count':30},{'ClientID':3031,'Count':40},{'ClientID':3031,'Count':50},{'ClientID':3031,'Count':60},{'ClientID':3031,'Count':70}]," +
            "'Streak':6,'Broken':0,'Best':9,'Grace':1,'GraceMax':2,'GraceUse':0,'Next':{'Days':7,'In':1,'Reward':'A frame'},'Title':'Loyal','Cosmetics':[{'Name':'Ash','Days':14,'Owned':0},{'Name':'Fire','Days':7,'Owned':1}]}", Sc + "daily.lua");

        static FakeMsg WeeklyStateMsg() => M(WeeklyState.OpcodeId, "state",
            "{'acts':[{'k':'dungeon','done':1,'open':1,'lv':50},{'k':'rift','done':0,'open':1,'lv':80},{'k':'tower','done':0,'open':0,'lv':300}],'got':1,'need':3,'bonusNeed':6,'open':3," +
            "'chest':{'given':0,'gold':2500000,'it':[{'n':3,'name':'Orb'}]},'bonus':{'given':0,'lo':1000,'hi':50000},'endsIn':200000,'chests':4}", Sc + "weeklychest.lua");

        // ------------------------------------------------------------------------------------ 225 cosmetics (cosmetics.lua, cosmetics_core.lua)
        static FakeMsg CosmeticsStateMsg(bool open) => M(CosmeticsState.OpcodeId, "state",
            "{'line':'mage','lineName':'Mages','rows':[{'id':11,'kind':'spellskin','line':'mage','name':'Cinder','owned':true,'selected':true},{'id':12,'kind':'spellskin','line':'mage','name':'Frost','owned':false,'how':'Reach level 100'}," +
            "{'id':21,'kind':'chatcolor','name':'Azure','owned':true,'color':'#4a8cff'}]," +
            "'collection':[{'key':'c1','name':'Ember','kind':'killfx','kindName':'Kill effect','owned':true},{'key':'c2','name':'Ash','kind':'footprint','kindName':'Footprints','owned':false,'how':'Win a duel'}]," +
            "'score':{'score':42,'next':{'points':100,'left':58},'milestones':[{'points':25,'done':true,'rewards':[{'k':'title','n':'Collector','f':true}]}],'groups':[{'g':'outfit','n':3,'p':9}]},'open':" + (open ? "true" : "false") + "}", Sc + "cosmetics.lua");

        static FakeMsg CosmeticsStyle() => M(CosmeticsState.OpcodeId, "style", "{'accent':'#100c0ef0'}", Sc + "cosmetics.lua (style)");
        static FakeMsg CosmeticsColors() => M(CosmeticsState.OpcodeId, "colors", "{'full':true,'names':{'Mira':'#4a8cff'}}", Sc + "cosmetics.lua (colors)");
        static FakeMsg CosmeticsWardrobe() => M(CosmeticsState.OpcodeId, "wardrobe",
            "{'hash':'h1','outfit':[{'l':128,'n':'Citizen','o':1},{'l':129,'n':'Hunter','o':0,'s':'Win a duel'}],'shader':[{'l':0,'n':'Ember','o':true}],'mount':[{'l':0,'n':'Ash Steed'}]}", Sc + "wardrobe.lua (wardrobe)");

        // ------------------------------------------------------------------------------------ 212 transmog (transmog.lua, transmog_core.lua)
        static FakeMsg TransmogStateMsg() => M(TransmogState.OpcodeId, "state",
            "{'open':true,'money':5000,'total':{'unlocked':4,'total':10},'kinds':[{'key':'helmet','name':'Helmets','unlocked':2,'total':5},{'key':'armor','name':'Armors','unlocked':2,'total':5}]," +
            "'slots':[{'slot':1,'name':'Head','item':{'id':100,'cid':2457,'name':'Steel Helmet','kind':'helmet','kindName':'Helmet','applyFee':1000,'removeFee':0}}," +
            "{'slot':4,'name':'Body','item':{'id':300,'name':'Cloak','look':{'id':301,'name':'Rags'},'kind':'armor','applyFee':9000,'removeFee':500}},{'slot':5,'name':'Shield'},{'slot':6,'name':'Ring','item':{'id':1,'name':'Ring'}}]," +
            "'sets':[{'name':'Ash','owned':true},{'name':'Zed','owned':false,'how':'Season 2','source':'season'}]}", Sc + "transmog.lua");

        static FakeMsg TransmogLooks(string kind) => M(TransmogState.OpcodeId, "looks",
            "{'kind':'" + kind + "','rows':[{'id':100,'cid':2457,'name':'Steel Helmet'},{'id':101,'cid':2458,'name':'Crown','set':'King'},{'id':102,'cid':2459,'name':'Iron Cap'}]}", Sc + "transmog.lua (looks)");

        // ------------------------------------------------------------------------------------ 254 pets (pets.lua), 195 professions (professions.lua)
        static FakeMsg PetsStateMsg() => M(PetsState.OpcodeId, "state",
            "{'open':true,'active':'wolf','out':true,'secondAt':10,'cooldowns':{'death':0,'summon':5},'zone':'utility only'," +
            "'pets':[{'species':'wolf','speciesName':'Wolf','name':'Fang','look':27,'level':4,'xp':50,'into':10,'need':40,'pct':25,'element':'Ice','abilities':[{'name':'Bite','kind':'combat','desc':'Bites.','cooldown':8,'unlocked':true},{'name':'Howl','kind':'utility','desc':'Buffs.','unlocked':false,'unlockAt':10}]}]," +
            "'catalog':[{'key':'wolf','name':'Wolf','look':27,'how':'A gift'},{'key':'owl','name':'Owl','look':28,'how':'Find an egg','abilities':['Scout','Dive']}]}", Sc + "pets.lua");

        static FakeMsg ProfessionsStateMsg() => M(ProfessionsState.OpcodeId, "state",
            "{'bonus':4.5,'per':0.5,'cap':20,'broker':true,'full':20,'late':0.5,'capDay':40,'nextDay':3700,'nextWeek':100000," +
            "'tiers':{'1':{'n':'Common','col':'#c4cebc'},'2':{'n':'Fine','col':'#5fd35f'}}," +
            "'profs':[{'k':'delving','n':'Delving','lv':9,'xp':50,'need':200,'pct':25,'tier':2,'d':'Dig for ore.','tool':'Pick','g':1234,'bp':2.5,'book':'mining','perks':[{'k':'channel','v':0.9,'lv':5,'n':'Swift','on':true},{'k':'lucky','v':0.05,'lv':20,'n':'Lucky','on':false}]},{'k':'flaying','n':'Flaying','lv':40,'xp':1,'need':0,'pct':0,'tier':1}]," +
            "'demand':[{'id':1,'c':5880,'n':'iron ore','p':'delving','t':2,'g':100,'l':50,'m':1.5,'h':30,'s':10},{'id':2,'n':'hide','p':'flaying','t':1,'g':10,'l':5,'m':0.8,'h':0,'s':0}]," +
            "'areas':[{'n':'Old Mine','t':2,'h':true,'m':'Trolls','near':'Cinderhold','x':100,'y':200,'z':7,'nodes':[{'k':'delving','r':3,'t':5},{'k':'angling'}]}]}", Sc + "professions.lua");

        // ------------------------------------------------------------------------------------ 232 crafting bench (crafting.lua), 91 crafting tables (base crafting module fixture)
        static FakeMsg CraftingInfo() => M(CraftingState.OpcodeId, "info",
            "{'orbs':[{'key':'transmutation','name':'Orb of Awakening','clientId':3001,'text':'Gives a rarity.'},{'key':'binding','name':'Orb of Binding','clientId':3002,'text':'Binds a bonus.'}],'reasons':{'noslots':'No free slot.'}}", Sc + "crafting.lua (info)");

        static FakeMsg CraftingStateMsg() => M(CraftingState.OpcodeId, "state",
            "{'open':true,'counts':{'transmutation':3,'binding':1},'item':{'path':'p1','id':9,'sig':'s','clientId':2400,'name':'Ash Blade','rarity':3,'rarityName':'Magic','level':40,'maxTier':4,'maxMods':4," +
            "'mods':[{'key':'fire','text':'+9 fire','short':'+9 fire','tier':2,'lo':5,'hi':9,'side':'prefix','group':'element'},{'key':'hp','text':'+5 hp','side':'suffix','bound':true}],'prefixes':[1,2],'suffixes':[1,2],'quality':4,'qualityCap':20," +
            "'orbs':{'transmutation':'noslots'},'pick':{'binding':['fire','hp']},'preview':{},'sockets':{'count':2,'max':3,'list':[{'index':1,'id':5,'name':'Ruby','text':'+1','cost':2500},{'index':2,'id':0}]}," +
            "'salvage':{'ok':true,'shards':4,'orbChance':12}},'items':[{'path':'p1','id':9,'name':'Ash Blade','rarity':3}],'history':[{'time':1700000000,'orb':'Orb of Awakening','item':'Ash Blade','text':'ok'}]," +
            "'salvage':{'mode':'salvage','installed':true,'shards':120,'shardName':'Rune shards','shardSingular':'Rune shard','bags':[{'name':'Backpack','path':'b'}],'rarityNames':['Common','Uncommon'],'rarityIds':[1,2]," +
            "'batch':{'bag':'b','maxRarity':2,'count':3,'shards':9,'orbs':6,'skipped':{'locked':2,'cap':1},'cap':50,'sig':'bs'},'recipes':[{'key':'transmutation','name':'Orb of Awakening','cost':30,'count':2,'back':10}],'maxCombine':20}}",
            Sc + "crafting.lua, salvage.lua, server/data/lib/chaos_crafting.lua, server/data/lib/chaos_item_mods.lua");

        static FakeMsg CraftTableFetch(string category, int page) => M(CraftTableState.OpcodeId, "fetch",
            "{'category':'" + category + "','totalPages':1,'page':" + page + ",'crafts':[" +
            "{'index':1,'name':'Iron Bar','id':5,'clientId':3000,'level':10,'cost':100,'count':2,'materials':[{'id':7,'clientId':3001,'count':2,'player':5,'name':'Iron Ore'}]}," +
            "{'index':2,'name':'Gem Ring','id':6,'clientId':3002,'level':50,'cost':900,'storage':100,'playerStorage':0,'storageText':'Do the quest.','materials':[{'id':8,'clientId':3003,'count':1,'player':0,'name':'Ruby'}]," +
            "'bonus':{'kind':'gear','level':30,'odds':[{'rarity':2,'name':'Uncommon','pct':20},{'rarity':1,'name':'Common','pct':80}]}}]}", "server/tests/fixtures/base_crafting/1crafting_mod.lua, " + Sc + "craft_bonus.lua (fetch and the recipe bonus)");

        static FakeMsg CraftTableMoney() => new FakeMsg { Op = CraftTableState.OpcodeId, Root = new Dictionary<string, object> { { "action", "money" }, { "data", 12500.0 } }, Source = "server/tests/fixtures/base_crafting/1crafting_mod.lua (money)" };

        // ------------------------------------------------------------------------------------ 241 hunt tracker (hunt.lua, hunt_core.lua), 178 goals (goals.lua, goals_core.lua)
        static FakeMsg HuntStateMsg() => M(HuntTracker.Opcode, "state",
            "{'open':true,'t':3725,'p':0,'xp':1234567,'xph':50000,'lvl':300,'left':999,'ttl':3600,'lv':2500000,'lvh':900000,'sv':1200,'svh':400,'pf':2498800,'pfh':-5,'dmg':1000,'dps':12.5,'heal':50,'hps':1,'kc':30," +
            "'k':[['rat',20],['bat',10]],'l':[[2400,3,150,'magic sword',5,0,0],[2500,1,1,'gold',0,0,0],[2600,2,5,'orb of upheaval',0,0,1]],'s':[[100,5,20,'arrow']],'x':[[3000,1,'soulreaper',0,1,0]]}", Sc + "hunt.lua");

        static FakeMsg GoalsMsg() => M(Goals.Opcode, "goals",
            "{'header':{'level':310,'done':4,'total':9,'season':{},'more':2,'next':500,'nextName':'Deep Rifts','band':{'key':'b','name':'World bosses','text':'Hunt world bosses.','from':300,'to':499,'index':4,'count':13}}," +
            "'goals':[{'key':'a','level':300,'state':'open','title':'Slay a boss','why':'Bosses drop uniques.','effort':'1h','progress':0,'target':1,'reward':'Orb','where':{'k':'info','page':'rift'}}," +
            "{'key':'b','level':400,'state':'locked','title':'Later','progress':0,'target':3},{'key':'c','level':300,'state':'open','title':'Kill 10 monsters','progress':4,'target':10}]," +
            "'upcoming':[{'key':'u','level':350,'title':'Arena'}],'gear':[{'text':'Wear a rare','where':{'k':'finder','id':5}}],'hunts':[{'id':'h1','name':'Ruins','lo':300,'hi':350,'where':{'k':'hunts'}}]}", Sc + "goals.lua");

        static FakeMsg GoalsTracker() => M(Goals.Opcode, "tracker", "{'rows':[{'key':'a','title':'Slay a boss','progress':0,'target':1},{'key':'c','title':'Kill 10 monsters','progress':4,'target':10}]}", Sc + "goals.lua (tracker)");

        // ------------------------------------------------------------------------------------ 252 guild (guild.lua), 197 guild wars (guildwar.lua), 208 party finder (partyfinder.lua), 160 group queue (groupqueue.lua)
        static FakeMsg GuildStateMsg() => M(GuildPanel.Opcode, "state",
            "{'open':true,'tab':'overview','guild':{'name':'Ash Wardens','level':3,'maxLevel':20,'into':400,'need':1000,'pct':40,'bank':250000,'rankName':'Leader','weekPoints':900,'weekRank':2,'canWithdraw':true,'minDeposit':1000,'scroll':true,'scrollTaken':false}," +
            "'perks':{'now':{'xp':5,'loot':3,'scroll':true},'list':[{'level':2,'text':'+3% loot','active':true},{'level':5,'text':'Aura','active':false}]},'members':[{'name':'Vex','rank':'Member','level':120,'week':50,'total':900,'online':true}]," +
            "'hall':{'owned':true,'slot':4,'rent':100000,'rentState':'grace','graceLeft':7200,'canManage':true,'upgrades':[{'key':'trunk','name':'Large Trunk','tier':0,'max':1,'cost':500000,'level':4,'canBuy':true,'info':'A trunk'}],'hub':['Cinderhold']}," +
            "'depot':{'owned':true,'active':true,'used':1,'capacity':40,'items':[{'id':5,'clientId':2160,'count':2,'name':'Ember Blade'}],'log':['Vex stored a blade']},'log':['Vex deposited 5,000 gold'],'top':{'resetIn':90000,'rows':[{'rank':1,'name':'Ash Wardens','level':3,'points':9000,'own':true}],'lastWinner':'Rival'}}", Sc + "guild.lua, guild_hall.lua");

        static FakeMsg GuildWarStateMsg() => M(GuildWarPanel.Opcode, "state",
            "{'open':true,'tab':'wars','guild':{'name':'Ash','wars':2,'bank':900000,'canDeclare':true,'canStake':true}," +
            "'options':{'stakeMin':100000,'stakeMax':5000000,'fee':10,'fragLimits':[10,25,50],'durations':[6,24,72],'offerHours':24,'maxWars':3,'minVictimLevel':50,'sameVictimMinutes':30,'emblemsLive':false}," +
            "'wars':{'pending':[{'id':1,'status':'pending','incoming':true,'own':'Ash','enemy':'Rival','left':3600,'stake':200000,'terms':'10 kills'}]," +
            "'active':[{'id':3,'status':'active','fragLimit':25,'left':50000,'own':'Ash','enemy':'Rival','ownKills':3,'enemyKills':5}],'history':[{'id':4,'status':'ended','result':'won','reason':'frag limit','own':'Ash','enemy':'Rival','ownKills':25,'enemyKills':9}]}," +
            "'board':{'active':[{'status':'active','fragLimit':25,'left':3600,'own':'Ash','enemy':'Rival','ownKills':3,'enemyKills':5}],'history':[]}}", Sc + "guildwar.lua");

        static FakeMsg PartyFinderInit() => M(PartyFinderPanel.Opcode, "init",
            "{'acts':[{'k':'rift','n':'Rift','range':{'min':1,'max':10,'label':'Tier'},'max':5,'per':{'tank':1,'healer':1,'dps':3},'suggest':{'tank':1,'healer':1,'dps':2}}," +
            "{'k':'hunt','n':'Hunt','targets':['Wasps','Trolls'],'bands':[[10,50],[60,120]],'max':10}],'roles':[{'k':'tank','n':'Tank','c':'#7fb8e8'},{'k':'dps','n':'DPS','c':'#e8a07f'}],'my':['tank','dps'],'lv':100,'exp':[30,60,120],'defExp':60," +
            "'lim':{'note':80,'title':24,'party':10,'perRole':6},'notes':['Chill run','Fast run']}", Sc + "party_finder.lua (init)");

        static FakeMsg PartyFinderList() => M(PartyFinderPanel.Opcode, "list",
            "{'badge':2,'rows':[{'id':1,'a':'rift','an':'Rift','ld':'Brannoc','ml':300,'xl':450,'left':600,'open':{'healer':1,'dps':2},'comp':[{'r':'tank','n':'Brannoc','st':'leader'}]}," +
            "{'id':3,'a':'hunt','an':'Hunt','ld':'Zed','ml':1,'left':900,'open':{'dps':1,'tank':1},'comp':[]}],'queue':null}", Sc + "party_finder.lua (list)");

        static FakeMsg GroupQueueState() => M(GroupQueuePanel.Opcode, "state",
            "{'open':true,'enabled':true,'leader':true,'size':2,'inParty':true,'arena':{'order':['1v1','2v2','3v3']},'bg':{'partyMax':5},'dungeons':[{'id':4,'title':'Ash Crypt','level':100,'max':3}],'raid':true}", Sc + "groupqueue.lua, dungeons.lua (the dungeons list)");

        // ------------------------------------------------------------------------------------ 214 Infinity Tower (flat messages, infinitytower.lua header and infinitytower_run.lua)
        static FakeMsg TowerOpen() => Flat(TowerState.Opcode,
            "{'action':'open','seasonNum':2,'seasonEnd':4102444800,'nextTry':0,'playerPoints':95000," +
            "'milestones':[{'points':60000,'claimed':true,'items':[{'id':3043,'count':30,'name':'Gold Coin'}]},{'points':120000,'claimed':false,'items':[{'id':51964,'count':1,'name':'Tower Chest'}]}]," +
            "'rankings':[{'name':'Vex','floor':41,'time':5200},{'name':'Mira','floor':38,'time':5600}]," +
            "'topRewards':[{'place':1,'name':'Gold Tower Chest','id':51964,'text':'First place'}],'floorRewards':{'nextFloor':13,'first':[{'id':3043,'count':50,'name':'Gold Coin'}],'repeatable':[{'id':3043,'count':10,'name':'Gold Coin'}]}}", Sc + "infinitytower.lua");

        // ------------------------------------------------------------------------------------ the context HUDs
        static readonly Dictionary<string, FakeContext> contexts = BuildContexts();

        /// <summary>The window classes with a context entry (every context HUD of the smoke run).</summary>
        public static IEnumerable<string> ContextWindows => contexts.Keys;

        /// <summary>The context of a window class, null for a window that needs none.</summary>
        public static FakeContext Context(string windowClass) => windowClass != null && contexts.TryGetValue(windowClass, out var c) ? c : null;

        static void Ctx(Dictionary<string, FakeContext> d, string window, string source, params FakeMsg[] pushes)
        {
            var c = new FakeContext { Window = window, Source = source };
            c.Pushes.AddRange(pushes);
            d[window] = c;
        }

        static Dictionary<string, FakeContext> BuildContexts()
        {
            var d = new Dictionary<string, FakeContext>(StringComparer.Ordinal);
            Ctx(d, "TowerPanelWindow", Sc + "infinitytower_run.lua",
                Flat(TowerState.Opcode, "{'action':'state','inRun':true,'canSkip':false,'floor':12,'nextBoss':false,'isLeader':true,'cleared':11,'waiting':false,'remaining':7,'total':10,'boss':false,'floorLeft':95}", Sc + "infinitytower_run.lua (sendState)"));
            Ctx(d, "DungeonCounterWindow", Sc + "dungeons.lua",
                M(DungeonsState.Opcode, "start", "{'boss':'The Grave Warden','left':40,'duration':900000,'need':85,'objectives':['Light three braziers','Free the prisoner']}", Sc + "dungeons.lua (start)"));
            Ctx(d, "RaidHudWindow", Sc + "raid.lua, raid_core.lua",
                M(RaidState.Opcode, "hud",
                    "{'raid':'Sepulchre of Ash','id':1,'boss':'Vorn the Hollow','idx':2,'total':4,'done':1,'killed':[true,null,null,null],'state':'fight','hp':64,'phase':2,'phases':3,'phaseName':'The Hollow Rises'," +
                    "'enrage':240,'adds':3,'totems':1,'players':[{'name':'Ember','hp':80}],'fallen':1,'alerts':['Spread out!'],'stacks':{'sunder':2,'hexed':0}}", Sc + "raid.lua, raid_core.lua (hudData and K.hud)"));
            Ctx(d, "RaidCalloutWindow", Sc + "raid.lua",
                M(RaidState.Opcode, "alert", "{'text':'The Hollow Rises: kill the totems!','kind':'phase'}", Sc + "raid.lua (alert)"));
            Ctx(d, "DescentHudWindow", Sc + "descent.lua",
                M(DescentState.Opcode, "hud",
                    "{'name':'The Ember Descent','room':3,'rooms':8,'type':'combat','typeName':'Combat','theme':'Cinder Vault','depth':3,'state':'fight','left':600,'limit':900,'wave':1,'waves':3,'monsters':6,'embers':120,'reward':15," +
                    "'boons':[{'k':'fury','n':'Fury','d':'More damage','s':1,'m':3,'kind':'boon'}],'curses':[],'ward':0,'weekly':false,'seed':1234,'party':[{'name':'Ember','alive':true,'hp':90}],'ready':false,'bossName':'Cinder Lord'}", Sc + "descent.lua (hudData)"));
            Ctx(d, "DescentOfferWindow", Sc + "descent.lua",
                M(DescentState.Opcode, "offer",
                    "{'id':1,'source':'shrine','cards':[{'k':'fury','n':'Fury','d':'More damage','s':0,'m':3,'kind':'boon'},{'k':'ward','n':'Ward','d':'A shield of embers','s':0,'m':3,'kind':'boon'}],'curse':{'k':'frail','n':'Frail','d':'Less health','r':20,'e':50},'timeout':30}", Sc + "descent.lua (offer)"));
            Ctx(d, "DescentShopWindow", Sc + "descent.lua",
                M(DescentState.Opcode, "shop", "{'embers':120,'wares':[{'k':'heal','n':'Embered Salve','d':'Heals you fully','p':40},{'k':'cleanse','n':'Cleanse','d':'Removes a curse','p':60,'off':true}],'room':4}", Sc + "descent.lua (sendShop)"));
            Ctx(d, "InvasionHudWindow", Sc + "invasion.lua, invasion_core.lua",
                M(InvasionState.Opcode, "hud",
                    "{'phase':'running','area':'Ashen Fields','faction':'Ash Horde','color':'#c0501a','target':'Cinderhold','wave':2,'waves':5,'left':14,'progress':35,'breach':10,'time':420,'boss':'Warlord Krag','bossHp':80,'top':[{'name':'Ember','share':40},{'name':'Mira','share':25}]}", Sc + "invasion.lua, invasion_core.lua (I.hud)"));
            Ctx(d, "SiegeHudWindow", Sc + "siege.lua",
                M(SiegeState.Opcode, "hud",
                    "{'phase':'match','left':900,'bracket':1,'brackets':1,'teams':[{'name':'Ash Wardens','score':120,'kills':14,'color':'#c0501a','side':1,'own':true,'members':8},{'name':'Rival','score':90,'kills':11,'color':'#3a6fc0','side':2,'own':false,'members':7}]," +
                    "'holder':'Ash Wardens','holderColor':'#c0501a','contested':false,'you':{'kills':3,'deaths':1,'points':20}}", Sc + "siege.lua (hudData)"));
            Ctx(d, "ArenaHudWindow", Sc + "arena.lua",
                M(ArenaState.Opcode, "hud",
                    "{'phase':'fight','mode':'2v2','left':120,'team':1,'sides':[[{'name':'Ember','hp':80,'defeated':false,'cid':1},{'name':'Mira','hp':55,'defeated':false,'cid':2}],[{'name':'Vex','hp':0,'defeated':true,'cid':3},{'name':'Zed','hp':40,'defeated':false,'cid':4}]]}", Sc + "arena.lua (hud)"));
            Ctx(d, "BattlegroundHudWindow", Sc + "battleground.lua",
                M(BattlegroundState.Opcode, "hud",
                    "{'phase':'fight','left':600,'score':[120,95],'win':300,'braziers':[{'name':'North Well','owner':1,'progress':100,'contested':false},{'name':'South Well','owner':0,'progress':40,'contested':true}]," +
                    "'team':1,'teams':['Ash','Frost'],'colors':['#c0501a','#3a6fc0'],'players':[8,8]}", Sc + "battleground.lua (hudOf)"));
            Ctx(d, "BattlegroundBoardWindow", Sc + "battleground.lua",
                M(BattlegroundState.Opcode, "hud", "{'phase':'fight','left':600,'score':[120,95],'win':300,'braziers':[],'team':1,'teams':['Ash','Frost'],'colors':['#c0501a','#3a6fc0'],'players':[8,8]}", Sc + "battleground.lua (hudOf)"),
                M(BattlegroundState.Opcode, "end",
                    "{'result':'win','reason':'score','rated':true,'team':1,'teams':['Ash','Frost'],'score':[300,210],'winner':1,'honor':40,'firstWin':true,'items':'','duration':900," +
                    "'rows':[{'name':'Ember','team':1,'role':'dps','level':300,'kills':12,'assists':4,'downs':2,'captures':3,'damage':250000,'healing':1000,'honor':40,'voc':'Juggernaut'},{'name':'Vex','team':2,'role':'tank','level':310,'kills':8,'assists':2,'downs':5,'captures':1,'damage':180000,'healing':0,'honor':10,'voc':'Warden'}]}", Sc + "battleground.lua (end and scoreboardOf)"));
            Ctx(d, "PvpZoneConfirmWindow", Sc + "pvpzone.lua",
                M(PvpZoneState.Opcode, "state",
                    "{'confirm':true,'name':'Scorched Marches','minLevel':200,'level':310,'inside':false,'carried':350,'carryMax':1000,'banked':1200,'rules':['Anyone can attack you here.','A defeat drops your embers.']," +
                    "'hc':{'isHc':false,'allow':false},'ssf':false,'canEnter':true,'pickup':{'perKill':100,'perDay':500,'ownerSeconds':30},'factions':[],'contest':{}}", Sc + "pvpzone.lua (Z.stateOf)"));
            Ctx(d, "PvpZoneHudWindow", Sc + "pvpzone.lua",
                M(PvpZoneState.Opcode, "hud",
                    "{'name':'Scorched Marches','embers':350,'cap':1000,'banked':1200,'pledge':{'key':'ash','name':'Ash Order','short':'Ash','color':'#c0501a'},'contest':{'phase':'idle','left':0},'protect':20,'piles':2}", Sc + "pvpzone.lua (Z.sendHud)"));
            Ctx(d, "RiftWindow", Sc + "rift.lua",
                M(RiftHud.Opcode, "start",
                    "{'tier':4,'theme':'Ash','left':300,'limit':300,'total':50,'killed':10,'bossAt':40,'boss':'waiting','state':'running','bossName':'Vorn','mods':[{'name':'Teeming','text':'+30% packs','tier':3},{'name':'Gift','text':'More loot','boon':true}]," +
                    "'bonus':{'quantity':20,'rarity':0,'experience':10},'notes':['A coffer'],'lives':2,'livesMax':4,'swift':120}", Sc + "rift.lua"));
            Ctx(d, "ReadyCheckWindow", Sc + "groupqueue.lua",
                M(GroupQueuePanel.Opcode, "check", "{'key':'arena','label':'Arena 2v2','left':20,'seconds':20,'accepted':1,'total':2,'mine':false}", Sc + "groupqueue.lua (check)"));
            d["ReadyCheckWindow"].Close.Add(M(GroupQueuePanel.Opcode, "checkEnd", "{}", Sc + "groupqueue.lua (checkEnd)"));
            Ctx(d, "TaskTrackerWindow", Sc + "bestiary.lua", BestTracker(true));
            d["TaskTrackerWindow"].Close.Add(BestTracker(false));
            // no server push opens it: the Bot HUD follows the helper's own client setting (HelperConfig Hud.Enabled), saved in the player
            AddContexts12(d);
            d["HelperHudWindow"] = new FakeContext { Window = "HelperHudWindow", Source = "client setting", Reason = "the Bot HUD opens from the helper's own setting (Hud.Enabled), no server message drives it" };
            return d;
        }
    }
}
