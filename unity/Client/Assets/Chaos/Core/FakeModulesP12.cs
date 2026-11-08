// Phase 12, track H: more module answers of the window smoke run (Core/FakeModules.cs has the rules: the server's real JSON shape, the server file cited per message, the keys checked
// against that file by Core.Tests/FakeModulesTests.cs). This file covers the most played windows that still showed "Loading": the bank, the stash, the store, the market, the
// Dungeons and Raid list windows, the Bounty Board, the leaderboards, and the waystone device (a context: the device pushes its window open).
using System;
using System.Collections.Generic;

namespace Chaos.Core
{
    public static partial class FakeModules
    {
        /// <summary>The request data the unit test (and the responder's own checks) send for an action of a module that needs a body; null for the rest.</summary>
        public static string SampleData(byte op, string action)
        {
            if (op == StashState.Opcode && action == "Stash") return "{'make':'SendItems'}";
            if (op == StoreState.Opcode && action == "get_page") return "{'category':1,'page':1}";
            if (op == StoreState.Opcode && action == "search") return "{'text':'wing'}";
            switch (action)
            {
                case "entry": return "{'id':1}";
                case "tiers": return "{'season':3}";
                case "looks": return "{'kind':'helmet'}";
                case "fetch": return op == CraftTableState.OpcodeId ? "{'category':'mining','page':1}" : null;
            }
            return null;
        }

        /// <summary>The module list of this file (added to FakeModules.Catalog).</summary>
        static IEnumerable<FakeModule> Phase12Modules()
        {
            yield return Mod("bank", BankState.Opcode, "bank.lua", "BankWindow", "openBank");
            yield return Mod("stash", StashState.Opcode, "stash.lua", "StashWindow", "Stash");
            yield return Mod("store", StoreState.Opcode, "shop.lua", "StoreWindow", "init", "get_page");
            yield return Mod("market", MarketPanel.Opcode, "market.lua", "MarketWindow", "open", "browse", "sellable", "mine", "history", "orders");
            yield return Mod("dungeons", DungeonsState.Opcode, "dungeons.lua", "DungeonsWindow", "fetch");
            yield return Mod("raid", RaidState.Opcode, "raid.lua", "RaidWindow", "open", "journal");
            yield return Mod("bounty", BountyState.Opcode, "bounty.lua", "BountyWindow", "open");
            yield return Mod("leaderboard", LeaderboardPanel.Opcode, "leaderboard.lua", "LeaderboardWindow", "open", "get");
            yield return Mod("autoloot", AutoLootState.Opcode, "autoloot.lua", "AutoLootWindow", "open");
            yield return Mod("pouches", PouchesState.Opcode, "pouches.lua", "PouchesWindow", "open", "as_open");
            yield return Mod("townportal", TownPortalState.Opcode, "townportal.lua", "TownPortalWindow", "open");
            yield return Mod("pvpzone", PvpZoneState.Opcode, "pvpzone.lua", "PvpZoneWindow", "open");
        }

        /// <summary>The answers of this file's modules; empty for an opcode or action not covered here.</summary>
        static List<FakeMsg> Answer12(byte op, string action, object data)
        {
            var o = new List<FakeMsg>();
            if (op == BankState.Opcode)
            {
                if (action == "openBank") o.Add(BankOpen());
            }
            else if (op == StashState.Opcode)
            {
                if (action == "Stash")
                {
                    string make = Json.Text(data, "make");
                    if (make == "SendItems") { o.Add(StashTabs()); o.Add(StashItems()); }
                    else if (make == "SendCategories") o.Add(StashBlocks());
                    else if (make == "Open") o.Add(M(StashState.Opcode, "Stash", "{'make':'Toggle','remote':'','open':true}", Sc + "stash.lua (Toggle)"));
                }
            }
            else if (op == StoreState.Opcode)
            {
                if (action == "init") { o.Add(StoreGroups()); o.Add(StoreCategories()); }
                if (action == "get_page") o.Add(StorePage(Json.Int(data, "category", 1), Json.Int(data, "page", 1)));
            }
            else if (op == MarketPanel.Opcode)
            {
                if (action == "open") o.Add(MarketMeta());
                if (action == "browse") o.Add(MarketPage());
                if (action == "sellable") o.Add(MarketSellable());
                if (action == "mine") o.Add(MarketMine());
                if (action == "history") o.Add(MarketHistory());
                if (action == "orders") o.Add(MarketOrders());
            }
            else if (op == DungeonsState.Opcode)
            {
                if (action == "fetch") o.AddRange(DungeonsAll());
            }
            else if (op == RaidState.Opcode)
            {
                if (action == "open") o.Add(RaidInfo());
                if (action == "journal") o.Add(RaidJournal());
            }
            else if (op == BountyState.Opcode)
            {
                if (action == "open") o.Add(BountyBoard());
            }
            else if (op == LeaderboardPanel.Opcode)
            {
                if (action == "open") o.Add(LeaderboardMeta());
                if (action == "get") o.Add(LeaderboardBoard());
            }
            else if (op == AutoLootState.Opcode)
            {
                if (action == "open") o.Add(AutoLootOpen());
            }
            else if (op == PouchesState.Opcode)
            {
                if (action == "open") o.Add(PouchSettings());
                if (action == "as_open") o.Add(AutoSellerState12());
            }
            else if (op == TownPortalState.Opcode)
            {
                if (action == "open") o.Add(TownPortalStateMsg());
            }
            else if (op == PvpZoneState.Opcode)
            {
                if (action == "open") o.Add(PvpZoneOpen());
            }
            return o;
        }

        static void AddContexts12(Dictionary<string, FakeContext> d)
        {
            // the waystone device (a base server script patched by server/tools/patch_waystone_hideout.py) sends "show" when a player uses it: the window has no request of its own
            Ctx(d, "WaystoneWindow", "server/tools/patch_waystone_hideout.py",
                Flat(WaystoneState.Opcode, "{'action':'show','tiers':[{'clientId':27189,'look':27189,'tier':1,'count':5,'level':20},{'clientId':27190,'look':27190,'tier':2,'count':2,'level':40},{'clientId':27191,'look':27191,'tier':3,'count':0}],'pick':27189}",
                    "server/tools/patch_waystone_hideout.py (the show message)"));
        }

        // ------------------------------------------------------------------------------------ 60 bank (bank.lua: {"action":"open","data":[goldCarried, goldBank, starBank, starCarried]})
        static FakeMsg BankOpen() => M(BankState.Opcode, "open", "[350000,1200000,0,0]", Sc + "bank.lua (open)");

        // ------------------------------------------------------------------------------------ 110 stash (stash.lua S.sendItems: {action:"Stash", data:{make:...}})
        static FakeMsg StashTabs() => M(StashState.Opcode, "Stash",
            "{'make':'tabs','tabs':[{'id':1,'name':'General','used':3,'size':30,'locked':false,'affinity':false,'icon':0,'old':false}," +
            "{'id':2,'name':'Orbs','used':1,'size':30,'locked':false,'affinity':true,'icon':3031,'old':false}],'limit':30,'pact':false,'tabSize':30,'slots':60,'freeSlots':30,'perPack':30,'packs':0,'maxPacks':4," +
            "'store':'Stash Slots','inbox':0,'canWithdraw':true,'canDeposit':true,'remote':''}", Sc + "stash.lua, stash_core.lua (sendItems: tabs)");

        static FakeMsg StashItems() => M(StashState.Opcode, "Stash",
            "{'make':'addItems','isFirst':true,'isLast':true,'items':[{'sprite':3031,'count':120,'name':'Gold Coin','tooltip':'Gold Coin Amount: 120','id':3031,'uniqueId':3031,'typee':'Valuables','tab':1}," +
            "{'sprite':3043,'count':4,'name':'Crystal Coin','tooltip':'Crystal Coin Amount: 4','id':3043,'uniqueId':3043,'typee':'Valuables','tab':1}," +
            "{'sprite':3035,'count':900,'name':'Platinum Coin','tooltip':'Platinum Coin Amount: 900','id':3035,'uniqueId':3035,'typee':'Valuables','tab':2,'rarity':2}]}", Sc + "stash.lua (sendItems: addItems)");

        static FakeMsg StashBlocks() => M(StashState.Opcode, "Stash",
            "{'make':'forceBlockList','items':[{'sprite':3031,'name':'Gold Coin','id':3031}]}", Sc + "stash.lua (forceBlockList)");

        // ------------------------------------------------------------------------------------ 218 store (shop.lua: {action, data, status = {points, ad, buyUrl}})
        static FakeMsg Store(string action, string data) => new FakeMsg
        {
            Op = StoreState.Opcode, Source = Sc + "shop.lua (" + action + ")",
            Root = new Dictionary<string, object> { { "action", action }, { "data", J(data) }, { "status", J("{'points':250,'buyUrl':'','ad':{}}") } }
        };

        static FakeMsg StoreGroups() => Store("category_groups", "[{'name':'Cosmetics','type':'item','item':3031,'size':2,'children':2}]");

        static FakeMsg StoreCategories() => Store("categories",
            "[{'name':'Featured','type':'item','item':3043,'pages':1,'size':2}," +
            "{'name':'Wings','type':'item','item':3031,'pages':1,'size':1,'parent':'Cosmetics'}," +
            "{'name':'Auras','type':'item','item':3035,'pages':1,'size':1,'parent':'Cosmetics'}]");

        static FakeMsg StorePage(int category, int page) => Store("category_page",
            "{'category':" + category + ",'page':" + page + ",'offers':[" +
            "{'type':'item','item':3043,'count':1,'title':'Ember Wings','description':'A pair of glowing wings. Cosmetic only.','cost':120,'oldCost':160,'tags':['New'],'gift':true,'owned':false}," +
            "{'type':'item','item':3031,'count':50,'title':'Coin Bundle','description':'Fifty coins for your purse.','cost':30,'gift':false,'owned':true}]}");

        // ------------------------------------------------------------------------------------ 221 market (market.lua MK.meta, MK.browse, market_core.lua C.rowView)
        static FakeMsg MarketMeta() => M(MarketPanel.Opcode, "meta",
            "{'categories':['weapon','shield','helmet','armor','legs','boots','jewel','other','orb','gem','key','misc'],'durations':[1,3,7],'defaultDuration':3,'sorts':['new','price','ending']," +
            "'fee':{'pct':2,'min':100,'max':50000,'coinGold':1000},'tax':{'gold':5,'coins':5},'price':{'gold':{'min':1,'max':2000000000},'coins':{'min':1,'max':100000}},'maxActive':20,'pageSize':20," +
            "'modFilter':{'maxRows':6,'maxTier':8,'maxValue':1000000,'maxSockets':8,'maxQuality':30},'realm':0,'realmName':'Standard','gold':1200000,'coins':250,'blob':true," +
            "'orders':{'maxQuantity':1000,'maxTotal':2000000000,'sorts':['new','price'],'pageSize':20},'coinsOk':true}", Sc + "market.lua (MK.meta)");

        static FakeMsg MarketPage() => M(MarketPanel.Opcode, "page",
            "{'rows':[{'id':11,'item':3031,'count':1,'name':'Ashen Blade','rarity':3,'ilvl':180,'cat':'weapon','gold':250000,'seller':'Mira','left':86000,'state':'active'}," +
            "{'id':12,'item':3043,'count':20,'name':'Orb of Upheaval','rarity':1,'ilvl':0,'cat':'orb','gold':5000,'coins':5,'seller':'Vex','left':40000,'state':'active'}," +
            "{'id':13,'item':3035,'count':1,'name':'Cinder Helm','rarity':4,'unique':true,'ilvl':210,'cat':'helmet','coins':40,'seller':'Zed','left':120000,'state':'active','mine':true}]," +
            "'page':1,'pages':1,'total':3,'seq':0}", Sc + "market.lua, market_core.lua (MK.browse and C.rowView)");

        static FakeMsg MarketSellable() => M(MarketPanel.Opcode, "sellable",
            "{'items':[{'item':3031,'count':1,'name':'Rusty Sword','rarity':0,'ilvl':12,'stack':false,'sid':'1','iid':'7'},{'item':3043,'count':40,'name':'Crystal Coin','stack':true,'sid':'2','iid':'8'}," +
            "{'item':3035,'count':1,'name':'Bound Ring','rarity':2,'ilvl':40,'why':'Bound to you','sid':'3','iid':'9'}]}", Sc + "market.lua (sellable)");

        static FakeMsg MarketMine() => M(MarketPanel.Opcode, "mine",
            "{'active':[{'id':13,'item':3035,'count':1,'name':'Cinder Helm','rarity':4,'unique':true,'ilvl':210,'cat':'helmet','coins':40,'left':120000,'state':'active'}]," +
            "'closed':[{'id':9,'item':3031,'count':1,'name':'Old Blade','rarity':1,'cat':'weapon','gold':9000,'state':'sold','buyer':'Mira','paid':9000,'cur':'gold','tax':450,'at':1700000000}],'owed':0,'max':20,'used':1}", Sc + "market.lua (mine)");

        static FakeMsg MarketHistory() => M(MarketPanel.Opcode, "history",
            "{'rows':[{'id':9,'item':3031,'count':1,'name':'Old Blade','rarity':1,'cat':'weapon','state':'sold','buyer':'Mira','paid':9000,'cur':'gold','tax':450,'at':1700000000}]}", Sc + "market.lua (history)");

        static FakeMsg MarketOrders() => M(MarketPanel.Opcode, "orders",
            "{'rows':[{'id':4,'item':3043,'name':'Orb of Upheaval','price':900,'cur':'gold','qty':50,'filled':10,'left':80000,'state':'active','buyer':'Zed'}],'page':1,'pages':1,'total':1,'seq':0}", Sc + "market.lua, market_orders_core.lua (orders and O.rowView)");

        // ------------------------------------------------------------------------------------ 109 dungeons (dungeons.lua sendAll: dungeon*, solo/group*, list)
        static IEnumerable<FakeMsg> DungeonsAll()
        {
            string src = Sc + "dungeons.lua (sendAll and dungeonPayload)";
            yield return M(DungeonsState.Opcode, "dungeon",
                "{'id':1,'title':'Ash Crypt','difficulty':3,'req':{'level':100,'party':'1-5'},'loot':[{'clientId':3043,'count':1},{'clientId':3031,'count':2}]," +
                "'queue':{'players':2,'estimated':180000},'challenges':[{'title':'Flawless','points':10,'desc':'Finish without dying.','completed':true},{'title':'Swift','points':20,'desc':'Finish in ten minutes.','completed':false}]}", src);
            yield return M(DungeonsState.Opcode, "dungeon",
                "{'id':2,'title':'Frost Vault','difficulty':1,'req':{'level':200,'party':'1-5'},'loot':[{'clientId':3035,'count':1}],'queue':{'players':0,'estimated':0},'challenges':[]}", src);
            yield return M(DungeonsState.Opcode, "solo", "{'id':1,'diff':1,'top':[{'name':'Vex','time':512000},{'name':'Mira','time':540000}]}", Sc + "dungeons.lua (sendAll: solo)");
            yield return M(DungeonsState.Opcode, "group", "{'id':1,'diff':1,'top':[{'name':'Vex\\nMira','time':380000}]}", Sc + "dungeons.lua (sendAll: group)");
            yield return M(DungeonsState.Opcode, "list",
                "[{'id':1,'title':'Ash Crypt','level':100,'boss':{'lookType':100,'lookTypeEx':0,'lookHead':0,'lookBody':0,'lookLegs':0,'lookFeet':0},'queue':2},{'id':2,'title':'Frost Vault','level':200,'boss':{'lookType':101,'lookTypeEx':0,'lookHead':0,'lookBody':0,'lookLegs':0,'lookFeet':0},'queue':0}]", Sc + "dungeons.lua (sendAll: list)");
        }

        // ------------------------------------------------------------------------------------ 213 raid (raid.lua X.sendInfo, vendorView, X.sendJournal)
        static FakeMsg RaidInfo() => M(RaidState.Opcode, "info",
            "{'name':'Ashen Sepulchre','minLevel':120,'level':310,'minPlayers':1,'maxPlayers':15,'lock':{'looted':1,'total':4,'reset':200000,'bosses':[{'n':'Gorrak','l':true},{'n':'Vorn the Hollow','l':false},{'n':'Sister Cinder','l':false},{'n':'The Sepulchre King','l':false}]}," +
            "'saved':[{'id':7,'leader':'Mira','done':1,'cleared':false,'killed':[true,false,false,false],'open':true,'mine':true}],'marks':42,'kills':5,'clears':1,'best':1500," +
            "'vendor':{'marks':42,'stock':[{'k':'orbs','n':'Orb Pouch','kind':'bundle','price':10,'weekly':3,'bought':1,'items':[{'n':'Orb of Upheaval','c':5,'cid':3043}],'cid':3043,'can':true}," +
            "{'k':'helm','n':'Sepulchre Helm','kind':'gear','price':30,'weekly':1,'bought':0,'level':130,'rarity':3,'mods':['+8% fire (T4)'],'cid':3035}]},'pz':true}", Sc + "raid.lua (X.sendInfo and vendorView)");

        static FakeMsg RaidJournal() => M(RaidState.Opcode, "journal",
            "{'bosses':[{'name':'Gorrak','intro':'A brute of the lower halls.','roles':'1 tank, 3 healers','phases':[{'n':'Charge','at':100},{'n':'Frenzy','at':40}],'mech':['Cleave: face him away from the raid.','Adds: kill the totems.']," +
            "'loot':{'gold':20000,'marks':5,'items':[{'id':3043,'count':3,'n':'Orb of Upheaval'}],'gearRolls':2,'gearLevel':[120,130],'gear':[1,2],'unique':50,'uniques':['Gorrak Maul']}}]}", Sc + "raid.lua, raid_core.lua (X.sendJournal and K.journal)");

        // ------------------------------------------------------------------------------------ 223 bounty (bounty.lua B.sendBoard, contractView)
        static FakeMsg BountyBoard() => M(BountyState.Opcode, "board",
            "{'day':20000,'nextIn':5400,'band':2,'active':1,'maxActive':3,'rerolls':1,'open':false,'week':{'done':2,'need':7,'claimed':false}," +
            "'bands':[{'index':1,'label':'Level 1-100','own':false,'contracts':[{'key':'a1','type':'kill','name':'Wolf','count':40,'tier':'','level':20,'look':27,'outfit':{'type':27},'reward':{'gold':4000,'exp':20000},'state':'open','progress':0}]}," +
            "{'index':2,'label':'Level 100-300','own':true,'contracts':[{'key':'b1','type':'kill','name':'Ghoul','count':60,'tier':'','level':120,'look':18,'outfit':{'type':18},'reward':{'gold':12000,'chaos':1},'state':'active','progress':25}," +
            "{'key':'b2','type':'elite','name':'Lich','count':3,'tier':'rare','level':200,'look':99,'outfit':{'type':99},'reward':{'gold':30000,'divine':1},'state':'open','progress':0}," +
            "{'key':'b3','type':'boss','name':'Warlord Krag','count':1,'tier':'','level':280,'look':100,'outfit':{'type':100},'reward':{'gold':80000,'exp':500000},'state':'done','progress':1}]}]}", Sc + "bounty.lua (B.sendBoard)");

        // ------------------------------------------------------------------------------------ 229 leaderboard (leaderboard.lua meta and board)
        static FakeMsg LeaderboardMeta() => M(LeaderboardPanel.Opcode, "meta",
            "{'open':true,'boards':[{'key':'worldboss','name':'World Boss','weekly':true,'value':'Damage','count':'Kills','title':'Titan Slayer','info':'Damage dealt to world bosses this week.','byClass':false,'format':'num','classAwards':false}," +
            "{'key':'rift','name':'Rifts','weekly':true,'value':'Tier','count':'Runs','title':'Rift Walker','info':'The highest rift tier of the week.','byClass':false,'format':'num','classAwards':false}," +
            "{'key':'ladder','name':'Class Ladder','weekly':false,'value':'Level','info':'Highest level per class.','byClass':true,'format':'num'}]," +
            "'groups':[{'key':1,'name':'Knight'},{'key':2,'name':'Sorcerer'}],'ownGroup':1}", Sc + "leaderboard.lua (meta)");

        static FakeMsg LeaderboardBoard() => M(LeaderboardPanel.Opcode, "board",
            "{'key':'worldboss','week':2500,'resetIn':200000,'rows':[{'rank':1,'name':'Vex','value':9000000,'count':12,'title':'Titan Slayer'},{'rank':2,'name':'Mira','value':7200000,'count':10}," +
            "{'rank':3,'name':'Zed','value':5100000,'count':9}],'own':{'rank':2,'value':7200000,'count':10},'champions':[{'rank':1,'rankName':'Champion','name':'Vex','value':8000000,'title':'Titan Slayer'}],'total':30}", Sc + "leaderboard.lua (board)");

        // ------------------------------------------------------------------------------------ 216 auto loot (autoloot.lua: open {itemsTable = [[clientId, name]], currentSlot, maxSlot})
        static FakeMsg AutoLootOpen() => M(AutoLootState.Opcode, "open",
            "{'itemsTable':[[3031,'Gold Coin'],[3043,'Crystal Coin'],[3035,'Platinum Coin']],'currentSlot':3,'maxSlot':40}", Sc + "autoloot.lua (open)");

        // ------------------------------------------------------------------------------------ 226 pouches (pouches.lua sendSettings, autosell.lua A.state)
        static FakeMsg PouchSettings() => M(PouchesState.Opcode, "settings",
            "{'rules':{'list':true,'gold':true,'uniques':false,'gear':false,'supplies':true,'gems':false,'other':false,'overflow':true,'minRarity':5},'ids':{'loot':3031,'orbs':3043,'keys':3035}," +
            "'titles':{'loot':'Loot Bag','orbs':'Orb Pouch','keys':'Key Ring'},'owned':{'loot':true,'orbs':false,'keys':false},'rarities':['Common','Uncommon','Magic','Rare','Legendary','Divine'],'rarityIds':[1,2,3,4,5,10],'open':true}",
            Sc + "pouches.lua (sendSettings)");

        static FakeMsg AutoSellerState12() => M(PouchesState.Opcode, "autoseller",
            "{'unlocked':true,'needs':'Needs the Auto Seller (Store > Convenience) or an active Chaos Pact.','paused':false,'interval':15,'intervals':[5,10,15,30,60],'nextIn':420," +
            "'tiers':[{'key':'common','on':true},{'key':'uncommon','on':true},{'key':'magic','on':false}],'list':[{'id':3031,'name':'Gold Coin','price':1}],'slots':40,'cooldown':0,'cooldownMax':30," +
            "'last':{'gold':12500,'count':7},'notice':'','open':true}", Sc + "pouches.lua, autosell.lua (A.state)");

        // ------------------------------------------------------------------------------------ 239 town portal (townportal.lua sendState, townportal_core.lua K.view)
        static FakeMsg TownPortalStateMsg() => M(TownPortalState.Opcode, "state",
            "{'open':true,'selected':'ember','cooldown':0,'cooldownTotal':60,'styles':[{'id':'ember','name':'Ember Gate','desc':'The default portal.','route':'free','how':'Every character has it.','owned':true,'selected':true,'clientItem':3031}," +
            "{'id':'frost','name':'Frost Gate','desc':'A cold, blue portal.','route':'store','how':'Store: 200 Chaos Coins (Portal Styles)','owned':false,'selected':false,'price':200,'clientItem':3043}]}", Sc + "townportal.lua, townportal_core.lua (sendState, K.view)");

        // ------------------------------------------------------------------------------------ 193 Scorched Marches (pvpzone.lua Z.stateOf: the window state, no confirm)
        static FakeMsg PvpZoneOpen() => M(PvpZoneState.Opcode, "state",
            "{'open':true,'confirm':false,'name':'Scorched Marches','minLevel':200,'level':310,'inside':false,'carried':350,'carryMax':1000,'banked':1200,'weekBanked':300,'total':5400,'kills':12,'defeats':3,'captures':1," +
            "'rules':['Anyone can attack you here.','A defeat drops your embers.'],'hc':{'isHc':false,'allow':false},'ssf':false,'canEnter':true,'exitSeconds':5,'everyMinutes':120,'holdMinutes':30,'buff':{'exp':10,'loot':10}," +
            "'monsters':{'hp':1.5,'damage':1.25,'exp':2,'loot':1.5},'repPerKill':4,'repDailyCap':40,'repToday':8,'pledgeChangeIn':0,'pickup':{'perKill':100,'perDay':500,'ownerSeconds':30}," +
            "'factions':[{'key':'ash','name':'Ash Order','color':'#c0501a','pledged':true,'can':false,'rival':'frost','rivalName':'Frost Pact'},{'key':'frost','name':'Frost Pact','color':'#3a6fc0','pledged':false,'can':true,'why':''}]," +
            "'vendor':[{'key':'orb','kind':'item','id':3043,'name':'Orb of Upheaval','cost':400,'can':true,'owned':false,'weekly':5,'bought':1},{'key':'wings','kind':'cosmetic','name':'Ash Wings','cost':2500,'can':false,'owned':false}]," +
            "'contest':{'phase':'idle','left':0}}", Sc + "pvpzone.lua (Z.stateOf)");
    }
}
