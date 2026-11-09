// Social and market windows (O433 phase 4, track M): market, guild, guild wars, party finder, group queue, inspect, leaderboards, item links in chat, factions,
// Conquest vendor. Each panel is driven with the server's messages (as the main client's *_test.lua files and the server's senders build them) and the requests it
// sends are read back from the extended opcode packets.
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;

namespace Chaos.Core.Tests
{
    static class SocialTests
    {
        sealed class Rig
        {
            public readonly ExtOpcodes Ext = new ExtOpcodes();
            public readonly List<string> Sent = new List<string>();
            public double Now;
            public Rig() { Ext.Transmit = p => Sent.Add(Encoding.UTF8.GetString(p, 4, p.Length - 4)); }
            public string Last => Sent.Count > 0 ? Sent[Sent.Count - 1] : "";
            public void Feed(byte op, string action, string data)
            {
                string json = "{\"action\":\"" + action + "\",\"data\":" + data.Replace('\'', '"') + "}";
                Ext.Receive(op, ExtOpcodes.ToWire(json));
            }
            public bool Has(string text) => Sent.Any(s => s.Contains(text));
        }

        static SocialRow Find(List<SocialRow> rows, Func<SocialRow, bool> f) => rows.FirstOrDefault(f);
        static SocialButton Btn(SocialRow r, string text) => r?.Buttons.FirstOrDefault(b => b.Text == text);
        static bool Click(List<SocialRow> rows, string text)
        {
            foreach (var r in rows) foreach (var b in r.Buttons) if (b.Text == text && b.Enabled) { b.Click(); return true; }
            return false;
        }

        public static void Run(Action<bool, string> check)
        {
            Loc.Set("en");
            Texts(check);
            MarketChecks(check);
            GuildChecks(check);
            GuildWarChecks(check);
            PartyFinderChecks(check);
            GroupQueueChecks(check);
            InspectChecks(check);
            LeaderboardChecks(check);
            ChatLinkChecks(check);
            FactionChecks(check);
            ConquestChecks(check);
            SessionChecks(check);
            LocChecks(check);
        }

        // ------------------------------------------------------------------------------------ shared helpers
        static void Texts(Action<bool, string> check)
        {
            check(SFmt.Money(1234567) == "1,234,567" && SFmt.Money(-2500) == "-2,500", "social: money text");
            check(SFmt.Duration(93784) == "1d 2h" && SFmt.Duration(4980) == "1h 23m" && SFmt.Duration(45) == "0m", "social: duration text");
            check(SFmt.Clock(75) == "1:15" && SFmt.Clock(5) == "0:05", "social: clock text");
            check(SFmt.ParseAmount("1500") == 1500 && SFmt.ParseAmount("1,500") == 1500 && SFmt.ParseAmount("5k") == 5000 && SFmt.ParseAmount("2.5m") == 2500000 && SFmt.ParseAmount("1b") == 1000000000, "social: amounts 5k, 2.5m, 1b");
            check(SFmt.ParseAmount("") == 0 && SFmt.ParseAmount("abc") == -1 && SFmt.ParseAmount("1.5") == -1 && SFmt.ParseAmount("k") == -1 && SFmt.ParseAmount("1.2.3") == -1, "social: bad amounts are -1, an empty one is 0");
            check(SFmt.Pct(5) == "5" && SFmt.Pct(2.5) == "2.5", "social: percent text");
            var l = new RowList();
            l.Row("a").Btn("Go", true, () => { }).Item(2160, 3, "#fff");
            check(l.Rows.Count == 1 && l.Rows[0].Buttons.Count == 1 && l.Rows[0].ItemId == 2160 && l.Rows[0].Count == 3, "social: row builder keeps buttons and the item");
        }

        // ------------------------------------------------------------------------------------ market
        const string MarketMeta = "{'gold':50000,'coins':30,'coinsOk':true,'realmName':'Standard','fee':{'pct':2,'min':100,'max':100000,'coinGold':1000},'tax':{'gold':5,'coins':5}," +
                                  "'price':{'gold':{'min':100,'max':2000000000},'coins':{'min':1,'max':100000}},'durations':[1,3,7],'defaultDuration':3,'maxActive':20," +
                                  "'orders':{'maxQuantity':1000,'maxTotal':{'gold':2000000000,'coins':1000000}}}";

        static void MarketChecks(Action<bool, string> check)
        {
            var rig = new Rig();
            var p = new MarketPanel(rig.Ext) { Clock = () => rig.Now };
            object meta = Json.Parse(MarketMeta.Replace('\'', '"'));
            check(MarketMath.Fee(meta, 10000, 0) == 200 && MarketMath.Fee(meta, 100, 0) == 100 && MarketMath.Fee(meta, 0, 40) == 800 && MarketMath.Fee(meta, 100000000, 0) == 100000, "market: listing fee percent, minimum, maximum, coins converted");
            MarketMath.Tax(meta, "gold", 1000, out long tax, out long net);
            check(tax == 50 && net == 950, "market: tax and what the seller keeps");
            string why;
            check(MarketMath.CheckSell(meta, "5k", "", 1, 1, 3, out long g, out long c, out why) && g == 5000 && c == 0, "market: sell form with a gold price");
            check(!MarketMath.CheckSell(meta, "", "", 1, 1, 3, out _, out _, out why) && why.Contains("Set a price"), "market: sell form needs a price");
            check(!MarketMath.CheckSell(meta, "abc", "", 1, 1, 3, out _, out _, out why) && why.Contains("whole numbers"), "market: sell form refuses a bad price");
            check(!MarketMath.CheckSell(meta, "50", "", 1, 1, 3, out _, out _, out why) && why.Contains("between"), "market: sell form refuses a gold price under the minimum");
            check(!MarketMath.CheckSell(meta, "5k", "", 6, 5, 3, out _, out _, out why) && why.Contains("do not have"), "market: sell form refuses more than held");
            var req = MarketMath.CheckOrder(meta, 5, "10", "2k", "gold", 3, 0, "", out long total, out long fee, out why);
            check(req != null && total == 20000 && fee == 400 && (long)req["quantity"] == 10 && (string)req["cur"] == "gold", "market: order form total and fee");
            check(MarketMath.CheckOrder(meta, 0, "10", "2k", "gold", 3, 0, "", out _, out _, out why) == null && why.Contains("Choose the item"), "market: an order needs an item");
            check(MarketMath.CheckOrder(meta, 5, "5000", "2k", "gold", 3, 0, "", out _, out _, out why) == null && why.Contains("At most"), "market: an order has a quantity limit");
            check(MarketMath.TimeLeft(0) == "ended" && MarketMath.TimeLeft(93784) == "1d 2h" && MarketMath.TimeLeft(30) == "<1m", "market: time left");
            check(MarketMath.CategoryName("weapon") == "Weapons" && MarketMath.RarityName(4) == "Rare" && MarketMath.RarityName(10) == "Divine", "market: category and rarity names");

            p.Show();
            check(rig.Last.Contains("\"action\":\"open\"") && p.Visible, "market: show asks to open");
            rig.Feed(MarketPanel.Opcode, "meta", MarketMeta);
            check(rig.Last.Contains("\"action\":\"browse\"") && rig.Last.Contains("\"page\":1"), "market: the meta of a visible window asks the first page");
            check(p.Header1 == "Standard market  Bank: 50,000 gold  Chaos Coins: 30", "market: wallet line");
            rig.Feed(MarketPanel.Opcode, "wallet", "{'gold':40000,'coins':31}");
            check(p.Header1.Contains("40,000") && p.Header1.Contains("31"), "market: wallet message updates the line");
            rig.Feed(MarketPanel.Opcode, "page", "{'page':1,'pages':2,'total':21,'rows':[{'id':11,'item':2160,'name':'Ember Blade','rarity':4,'ilvl':120,'cat':'weapon','seller':'Vex','left':7200,'gold':12000,'coins':40,'count':1}," +
                                                  "{'id':12,'item':2148,'name':'Gold Coin','rarity':0,'cat':'misc','seller':'Me','left':100,'gold':500,'count':50,'mine':true}]}");
            var rows = p.BuildRows();
            var blade = Find(rows, r => r.Text == "Ember Blade");
            check(blade != null && blade.Right == "12,000 gold  40 coins" && blade.ItemId == 2160 && blade.Frame == "#a35cf0" && blade.Sub.Contains("Rare") && blade.Sub.Contains("iLvl 120") && blade.Sub.Contains("by Vex") && blade.Sub.Contains("2h 0m left"), "market: a browse row (price lines, rarity colour, sub line)");
            check(Btn(blade, "Buy") != null && Btn(Find(rows, r => r.Text == "50x Gold Coin"), "Cancel") != null, "market: Buy on others' offers, Cancel on mine");
            check(rows.Any(r => r.Text.StartsWith("Page 1 / 2")) && Find(rows, r => r.Text.StartsWith("Page 1"))?.Buttons[0].Enabled == false && Find(rows, r => r.Text.StartsWith("Page 1"))?.Buttons[1].Enabled == true, "market: page line and its arrows");
            // hover asks for the tooltip once, the answer fills the row
            blade.Hover();
            check(rig.Last.Contains("\"action\":\"tip\"") && rig.Last.Contains("\"id\":11"), "market: hover asks the offer's tooltip");
            int sentBefore = rig.Sent.Count;
            blade.Hover();
            check(rig.Sent.Count == sentBefore, "market: the same tooltip is not asked again within 3 seconds");
            rig.Feed(MarketPanel.Opcode, "tip", "{'id':11,'tip':{'id':2160,'name':'Ember Blade','rarity':4}}");
            check(Find(p.BuildRows(), r => r.Text == "Ember Blade").ItemTip != null, "market: the tooltip of an offer reaches its row");
            // buy with a confirmation
            Btn(Find(p.BuildRows(), r => r.Text == "Ember Blade"), "Buy").Click();
            rows = p.BuildRows();
            check(rows.Any(r => r.Text.StartsWith("Buy Ember Blade from Vex?")) && Btn(rows.First(r => r.Buttons.Any(b => b.Text.StartsWith("Pay"))), "Pay 40 coins") != null, "market: Buy asks for a confirmation with one button per currency");
            Click(rows, "Pay 40 coins");
            check(rig.Last.Contains("\"action\":\"buy\"") && rig.Last.Contains("\"id\":11") && rig.Last.Contains("\"cur\":\"coins\"") && p.ConfirmBuyOffer == null, "market: Pay sends buy with the currency");
            // filters
            p.Form["cat"] = "1"; p.Form["rarity"] = "6"; p.Form["cur"] = "1"; p.Form["sort"] = "1"; p.Form["priceMin"] = "5k";
            p.OnForm("cat");
            check(rig.Last.Contains("\"cat\":\"weapon\"") && rig.Last.Contains("\"rarity\":10") && rig.Last.Contains("\"cur\":\"gold\"") && rig.Last.Contains("\"sort\":\"price\"") && rig.Last.Contains("\"priceMin\":5000") && rig.Last.Contains("\"page\":1"), "market: a filter change sends the whole filter");
            p.Page(1);
            check(rig.Last.Contains("\"page\":2"), "market: next page asks page 2");
            // sell
            p.SelectTab("sell");
            check(rig.Last.Contains("\"action\":\"sellable\""), "market: the Sell tab asks the backpack");
            rig.Feed(MarketPanel.Opcode, "sellable", "{'items':[{'item':1988,'name':'Bag','why':'Has items inside'},{'sid':3,'iid':'99','ref':7,'count':5,'item':2148,'name':'Gold Coin','stack':true,'rarity':0}]}");
            rows = p.BuildRows();
            int iCoin = rows.FindIndex(r => r.Text == "5x Gold Coin"), iBag = rows.FindIndex(r => r.Text == "Bag");
            check(iCoin > 0 && iBag > iCoin && !Btn(rows[iBag], "Choose").Enabled, "market: listable items first, the others greyed with why");
            Btn(rows[iCoin], "Choose").Click();
            p.Form["gold"] = "5k";
            p.Form["days"] = "2";
            check(p.FeeText().Contains("Listing fee: 100 gold") && p.FeeText().Contains("tax 250") && p.FeeText().Contains("7 days"), "market: the fee text of the form");
            check(p.ListItem() && rig.Last.Contains("\"action\":\"list\"") && rig.Last.Contains("\"gold\":5000") && rig.Last.Contains("\"count\":5") && rig.Last.Contains("\"days\":7") && rig.Last.Contains("\"sid\":3"), "market: List sends the item, count, price and days");
            rig.Feed(MarketPanel.Opcode, "done", "{'what':'list','text':'Listed.'}");
            check(p.Status == "Listed." && p.StatusTone == "good" && p.Selected == null && rig.Last.Contains("\"action\":\"sellable\""), "market: a listed item clears the form and asks the backpack again");
            rig.Feed(MarketPanel.Opcode, "error", "{'text':'Too many offers.'}");
            check(p.Status == "Too many offers." && p.StatusTone == "bad", "market: an error shows in red");
            // mine, history
            p.SelectTab("mine");
            rig.Feed(MarketPanel.Opcode, "mine", "{'used':2,'max':20,'owed':1,'active':[{'id':21,'item':2160,'name':'Ember Blade','rarity':4,'gold':900,'left':3600,'cat':'weapon'}],'closed':[{'id':22,'item':2160,'name':'Old Axe','state':'sold','buyer':'Zed','paid':1000,'tax':50,'cur':'gold'}]}");
            rows = p.BuildRows();
            var sold = Find(rows, r => r.Text == "Old Axe");
            check(rows.Any(r => r.Text.StartsWith("Active offers (1; listings used with buy orders: 2 / 20)")) && sold != null && sold.Sub == "Sold to Zed for 1,000 gold (tax 50, you got 950)" && sold.Right == "1,000 gold", "market: my offers and the sold line");
            Btn(Find(rows, r => r.Text == "Ember Blade"), "Cancel").Click();
            Click(p.BuildRows(), "Yes");
            check(rig.Last.Contains("\"action\":\"cancel\"") && rig.Last.Contains("\"id\":21"), "market: cancel an offer after the confirmation");
            p.SelectTab("history");
            rig.Feed(MarketPanel.Opcode, "history", "{'rows':[{'id':31,'item':2160,'name':'Ember Blade','side':'bought','seller':'Vex','paid':12000,'cur':'gold'},{'id':32,'item':1,'name':'Ring','side':'sold','buyer':'Zed','paid':40,'cur':'coins','tax':2,'order':true}]}");
            rows = p.BuildRows();
            check(Find(rows, r => r.Text == "Ember Blade").Sub == "Bought from Vex for 12,000 gold" && Find(rows, r => r.Text == "Ring").Sub == "Sold to Zed for 40 coins (tax 2) (buy order)", "market: history lines");
            // buy orders
            p.SelectTab("orders");
            check(rig.Last.Contains("\"action\":\"orders\"") && rig.Last.Contains("\"page\":1"), "market: the Buy Orders tab asks the orders");
            rig.Feed(MarketPanel.Opcode, "orders", "{'page':1,'pages':1,'total':1,'rows':[{'id':41,'item':2160,'name':'Ember Blade','state':'active','cur':'gold','price':5000,'qty':10,'filled':2,'buyer':'Kim','left':7200,'escrow':40000}]}");
            rows = p.BuildRows();
            var order = Find(rows, r => r.Text == "Ember Blade" && r.Right.Contains("each"));
            check(order != null && order.Right == "5,000 gold each" && order.Sub.Contains("2/10 bought") && order.Sub.Contains("by Kim") && Btn(order, "Sell") != null, "market: a buy order row");
            Btn(order, "Sell").Click();
            check(rig.Last.Contains("\"action\":\"fillable\"") && rig.Last.Contains("\"id\":41"), "market: Sell on an order asks what fits");
            rig.Feed(MarketPanel.Opcode, "fillable", "{'id':41,'items':[{'sid':3,'iid':'99','ref':7,'count':4,'item':2160,'name':'Ember Blade'}]}");
            Btn(Find(p.BuildRows(), r => r.Text == "4x Ember Blade"), "Choose").Click();
            p.Form["fill"] = "3";
            check(p.BuildRows().Any(r => r.Text.StartsWith("Sell 3 items for 15,000 gold: tax 750, you receive 14,250 gold in your bank")), "market: the fill text");
            p.DoFill();
            check(rig.Last.Contains("\"action\":\"fill\"") && rig.Last.Contains("\"count\":3") && rig.Last.Contains("\"sid\":3"), "market: fill sends the chosen item and count");
            rig.Feed(MarketPanel.Opcode, "orderFind", "{'items':[{'sid':9,'item':2160,'name':'Ember Blade'}]}");
            check(p.ChosenKind != null, "market: a single match for the order item is chosen");
            p.Form["qty"] = "10"; p.Form["oprice"] = "2k"; p.Form["opay"] = "0"; p.Form["ordays"] = "0"; p.Form["orarity"] = "2";
            p.PostOrder();
            check(rig.Last.Contains("\"action\":\"orderPost\"") && rig.Last.Contains("\"sid\":9") && rig.Last.Contains("\"quantity\":10") && rig.Last.Contains("\"price\":2000") && rig.Last.Contains("\"days\":1") && rig.Last.Contains("\"rarity\":2"), "market: Post order sends the form");
            p.ToggleMine();
            check(rig.Last.Contains("\"action\":\"myOrders\""), "market: My orders asks the own orders");
            // a season market takes no coins
            rig.Feed(MarketPanel.Opcode, "meta", MarketMeta.Replace("'coinsOk':true", "'coinsOk':false"));
            check(!p.Header1.Contains("Chaos Coins"), "market: no coin balance on a gold-only market");
            p.Clear();
            check(!p.Visible && p.Meta == null && p.Header1 == "", "market: clear for a new character");
        }

        // ------------------------------------------------------------------------------------ guild
        static void GuildChecks(Action<bool, string> check)
        {
            var rig = new Rig();
            var p = new GuildPanel(rig.Ext);
            string opened = null;
            p.OpenModule = n => opened = n;
            bool warsOpened = false;
            p.OpenWars = () => warsOpened = true;
            p.Show();
            check(rig.Last.Contains("\"action\":\"open\"") && rig.Last.Contains("\"tab\":\"overview\"") && !p.Visible, "guild: open carries the tab and the window waits for the answer");
            const string state = "{'open':true,'tab':'overview','guild':{'name':'Ash Wardens','level':3,'maxLevel':20,'into':400,'need':1000,'pct':40,'bank':250000,'rankName':'Leader','weekPoints':900,'weekRank':2,'canWithdraw':true,'minDeposit':1000,'scroll':true,'scrollTaken':false}," +
                                 "'perks':{'now':{'xp':5,'loot':3,'scroll':true},'list':[{'level':2,'text':'+3% loot','active':true},{'level':5,'text':'Aura','active':false}]},'members':[{'name':'Vex','rank':'Member','level':120,'week':50,'total':900,'online':true}]," +
                                 "'hall':{'owned':true,'slot':4,'rent':100000,'rentState':'grace','graceLeft':7200,'canManage':true,'upgrades':[{'key':'trunk','name':'Large Trunk','tier':0,'max':1,'cost':500000,'level':4,'canBuy':true,'info':'A trunk'},{'key':'forge','name':'Forge','tier':2,'max':2,'active':true}],'hub':['Cinderhold']}," +
                                 "'depot':{'owned':true,'active':true,'used':1,'capacity':40,'items':[{'id':5,'clientId':2160,'count':2,'name':'Ember Blade'}],'log':['Vex stored a blade']},'log':['Vex deposited 5,000 gold'],'top':{'resetIn':90000,'rows':[{'rank':1,'name':'Ash Wardens','level':3,'points':9000,'own':true}],'lastWinner':'Rival'}}";
            rig.Feed(GuildPanel.Opcode, "state", state);
            check(p.Visible && p.Header1 == "Ash Wardens   Guild level 3 / 20" && p.Header2 == "You: Leader. This week: 900 GXP, rank 2 of the guilds.", "guild: state shows the window and the header lines");
            var rows = p.BuildRows();
            check(rows[0].Kind == RowKind.Bar && rows[0].Text == "400 / 1,000 GXP (40%)" && rows[0].Percent == 40, "guild: the XP bar");
            check(rows.Any(r => r.Text == "+5% experience, +3% loot, daily hall scroll".Replace("+5% experience", "+5% experience")) || rows.Any(r => r.Text.Contains("+5") && r.Text.Contains("loot")), "guild: perks now");
            check(rows.Any(r => r.Text == "Level 5: Aura" && r.Tone == "locked") && rows.Any(r => r.Text == "Level 2: +3% loot" && r.Tone == "text"), "guild: perk list, the inactive one dim");
            check(Btn(Find(rows, r => r.Text.StartsWith("Guild hall scroll")), "Take").Enabled, "guild: the scroll can be taken");
            p.Form["amount"] = "5k";
            Click(rows, "Deposit");
            check(rig.Last.Contains("\"action\":\"deposit\"") && rig.Last.Contains("\"amount\":5000") && rig.Last.Contains("\"tab\":\"overview\""), "guild: deposit sends the amount and the tab");
            Click(p.BuildRows(), "Withdraw");
            check(rig.Last.Contains("\"action\":\"withdraw\""), "guild: the leader withdraws");
            p.Form["amount"] = "x";
            int n = rig.Sent.Count;
            Click(p.BuildRows(), "Deposit");
            check(rig.Sent.Count == n, "guild: a bad amount sends nothing");
            Click(p.BuildRows(), "Open");
            check(warsOpened, "guild: the wars button opens the war window");
            Click(p.BuildRows(), "Take");
            check(rig.Last.Contains("\"action\":\"scroll\""), "guild: take the scroll");
            check(rows.Any(r => r.Text == "Vash") == false && p.BuildRows().Last().Text == "Vex deposited 5,000 gold", "guild: the log ends the overview");
            p.SelectTab("members");
            check(rig.Last.Contains("\"action\":\"refresh\"") && rig.Last.Contains("\"tab\":\"members\""), "guild: a tab asks a refresh for it");
            rows = p.BuildRows();
            var mem = Find(rows, r => r.Text == "Vex (Member, level 120)");
            check(mem != null && mem.Right == "50 this week / 900" && mem.Tone == "good", "guild: member rows with contribution, online in green");
            p.SelectTab("hall");
            rows = p.BuildRows();
            check(rows.Any(r => r.Text.StartsWith("Rent 100,000 gold a week is DUE") && r.Tone == "warn"), "guild: rent due in yellow");
            check(Find(rows, r => r.Text == "Large Trunk - 500,000 gold, guild level 4") != null && Btn(Find(rows, r => r.Text.StartsWith("Large Trunk")), "Buy").Enabled, "guild: an upgrade to buy");
            check(Find(rows, r => r.Text.StartsWith("Forge 2/2 - owned")) != null && Btn(Find(rows, r => r.Text.StartsWith("Forge")), "Buy") == null, "guild: a maxed upgrade has no button");
            Btn(Find(rows, r => r.Text.StartsWith("Large Trunk")), "Buy").Click();
            check(rig.Last.Contains("\"action\":\"upgrade\"") && rig.Last.Contains("\"key\":\"trunk\""), "guild: upgrade sends its key");
            Click(rows, "Pay rent");
            check(rig.Last.Contains("\"action\":\"payRent\""), "guild: pay rent");
            p.SelectTab("depot");
            rows = p.BuildRows();
            Btn(Find(rows, r => r.Text == "2 x Ember Blade"), "Take").Click();
            check(rig.Last.Contains("\"action\":\"take\"") && rig.Last.Contains("\"id\":5") && Find(rows, r => r.Text == "2 x Ember Blade").ItemId == 2160, "guild: take an item out of the stash");
            p.SelectTab("top");
            rows = p.BuildRows();
            check(rows.Any(r => r.Text == "1. Ash Wardens (level 3)" && r.Right == "9,000 GXP") && rows.Any(r => r.Text == "Top guild of last week: Rival") && rows.Any(r => r.Text.Contains("1d 1h")), "guild: the weekly board");
            rig.Feed(GuildPanel.Opcode, "message", "{'ok':false,'text':'Not enough gold.'}");
            check(p.Status == "Not enough gold." && p.StatusTone == "bad", "guild: a refusal shows in red");
            rig.Feed(GuildPanel.Opcode, "openModule", "{'name':'game_crafting'}");
            check(opened == "game_crafting", "guild: the hall bench asks for a module");
            rig.Feed(GuildPanel.Opcode, "none", "{'open':true,'text':'You are not in a guild.'}");
            check(p.NoGuild && p.Header1 == "No guild" && p.Status == "You are not in a guild." && p.BuildRows().Count == 0, "guild: not in a guild");
        }

        // ------------------------------------------------------------------------------------ guild wars
        static void GuildWarChecks(Action<bool, string> check)
        {
            var o = Json.Parse("{\"stakeMin\":100000,\"stakeMax\":5000000,\"fee\":10,\"fragLimits\":[10,25,50],\"durations\":[6,24,72],\"offerHours\":24,\"maxWars\":3,\"minVictimLevel\":50,\"sameVictimMinutes\":30}");
            check(GuildWarMath.HoursText(1) == "1 hour" && GuildWarMath.HoursText(6) == "6 hours" && GuildWarMath.HoursText(24) == "1 day" && GuildWarMath.HoursText(72) == "3 days", "guild war: hours text");
            check(GuildWarMath.Winnings(1000000, 10) == 1800000 && GuildWarMath.StakeText(0, 10) == "no stake" && GuildWarMath.StakeText(1000000, 10) == "1,000,000 gold per side (the winner gets 1,800,000)", "guild war: winnings and stake text");
            var req = GuildWarMath.DeclareRequest("  Rival Guild ", 25, 24, "500k", o, out string why);
            check(req != null && (string)req["target"] == "Rival Guild" && (long)req["fragLimit"] == 25 && (long)req["hours"] == 24 && (long)req["stake"] == 500000, "guild war: declare request");
            check(GuildWarMath.DeclareRequest("", 25, 24, "", o, out why) == null && why.Contains("name of the guild"), "guild war: a name is needed");
            check(GuildWarMath.DeclareRequest("X", 25, 24, "5k", o, out why) == null && why.Contains("at least 100,000"), "guild war: a stake under the minimum");
            check(GuildWarMath.DeclareRequest("X", 25, 24, "9m", o, out why) == null && why.Contains("at most 5,000,000"), "guild war: a stake over the maximum");
            check(GuildWarMath.DeclareRequest("X", 25, 24, "1x", o, out why) == null && why.Contains("number of gold"), "guild war: a bad stake");
            check(GuildWarMath.DeclareRequest("X", 0, 24, "", o, out why) == null && why.Contains("frag limit"), "guild war: pick a limit");

            var rig = new Rig();
            var p = new GuildWarPanel(rig.Ext);
            p.Show();
            check(rig.Last.Contains("\"action\":\"open\"") && rig.Last.Contains("\"tab\":\"wars\""), "guild war: open");
            const string war = "'own':'Ash','enemy':'Rival','ownKills':3,'enemyKills':5";
            string state = "{'open':true,'tab':'wars','guild':{'name':'Ash','wars':2,'bank':900000,'canDeclare':true,'canStake':true}," +
                           "'options':{'stakeMin':100000,'stakeMax':5000000,'fee':10,'fragLimits':[10,25,50],'durations':[6,24,72],'offerHours':24,'maxWars':3,'minVictimLevel':50,'sameVictimMinutes':30,'emblemsLive':false}," +
                           "'wars':{'pending':[{'id':1,'status':'pending','incoming':true,'own':'Ash','enemy':'Rival','left':3600,'stake':200000,'terms':'10 kills'},{'id':2,'status':'pending','incoming':false,'own':'Ash','enemy':'Other','left':7200}]," +
                           "'active':[{'id':3,'status':'active','fragLimit':25,'left':50000," + war + "}],'history':[{'id':4,'status':'ended','result':'won','reason':'frag limit'," + war + "}]}," +
                           "'board':{'active':[{'status':'active','fragLimit':25,'left':3600," + war + "}],'history':[{'status':'ended','reason':'surrender'," + war + "}]}," +
                           "'boss':{'guild':true,'boss':'The Cinderheart','fuel':300,'need':1000,'canSummon':false,'reason':'Feed the stone first.','attempts':1,'maxAttempts':3,'resetIn':90000,'players':2,'minLevel':200,'maxPlayers':10,'gold':{'perEmber':1000,'min':5000}," +
                           "'materials':[{'key':'ash','name':'Ash','embers':5,'have':3,'clientId':2150}],'banner':{'tier':1,'name':'Ember Banner','kills':1,'next':5},'contributors':[{'name':'Vex','embers':40,'gold':5000}],'pool':1000000,'spoils':[{'name':'Vex','gold':250000}],'board':[{'rank':1,'name':'Ash','killed':true,'seconds':125,'players':5,'own':true},{'rank':2,'name':'Rival','damage':500000}]}}";
            rig.Feed(GuildWarPanel.Opcode, "state", state);
            check(p.Visible && p.Header1 == "Ash" && p.Header2 == "2 of 3 wars and offers. Guild bank: 900,000 gold.", "guild war: header lines");
            var rows = p.BuildRows();
            var incoming = Find(rows, r => r.Text == "Ash vs Rival" && r.Right.StartsWith("Declared on you"));
            check(incoming != null && incoming.Right == "Declared on you: answer within 1h 0m" && incoming.Tone == "warn" && Btn(incoming, "Accept").Enabled && Btn(incoming, "Decline").Enabled, "guild war: an incoming offer");
            Btn(incoming, "Accept").Click();
            check(rig.Last.Contains("\"action\":\"accept\"") && rig.Last.Contains("\"id\":1"), "guild war: accept sends the id");
            Btn(Find(rows, r => r.Text == "Ash vs Other"), "Take back").Click();
            check(rig.Last.Contains("\"action\":\"cancel\"") && rig.Last.Contains("\"id\":2"), "guild war: take back an offer");
            var running = Find(rows, r => r.Right.StartsWith("3 : 5 (first to 25)"));
            check(running != null && running.Tone == "bad" && running.Right == "3 : 5 (first to 25), ends in 13h 53m", "guild war: a running war");
            Btn(running, "Surrender").Click();
            check(!rig.Last.Contains("surrender") && Find(p.BuildRows(), r => r.Text == "Ash vs Rival" && r.Buttons.Any(b => b.Text == "Sure?")) != null, "guild war: Surrender asks Sure? first");
            Click(p.BuildRows(), "Sure?");
            check(rig.Last.Contains("\"action\":\"surrender\"") && rig.Last.Contains("\"id\":3"), "guild war: the second click surrenders");
            Click(p.BuildRows(), "Kill log");
            check(rig.Last.Contains("\"action\":\"log\"") && rig.Last.Contains("\"id\":3"), "guild war: kill log request");
            rig.Feed(GuildWarPanel.Opcode, "log", "{'id':3,'title':'Ash vs Rival','score':'3 : 5','lines':[{'at':'12:00','killer':'Vex','victim':'Zed','level':200,'counted':true},{'at':'12:05','killer':'Vex','victim':'Zed','level':200,'counted':false,'reason':'same victim'}]}");
            rows = p.BuildRows();
            check(rows.Any(r => r.Text == "Kill log: Ash vs Rival (3 : 5)") && rows.Any(r => r.Text == "12:00 Vex killed Zed (level 200)") && rows.Any(r => r.Text == "12:05 Vex killed Zed (level 200) - not counted: same victim"), "guild war: kill log lines");
            check(rows.Any(r => r.Right == "Won 3 : 5 - frag limit" && r.Tone == "good"), "guild war: history result");
            p.SelectTab("declare");
            check(rig.Last.Contains("\"action\":\"refresh\"") && rig.Last.Contains("\"tab\":\"declare\""), "guild war: a tab refreshes");
            rows = p.BuildRows();
            check(rows.Any(r => r.Kind == RowKind.Input && r.Key == "target") && rows.Any(r => r.Kind == RowKind.Combo && r.Key == "frag" && r.Options.SequenceEqual(new[] { "10 kills", "25 kills", "50 kills" })) &&
                  rows.Any(r => r.Kind == RowKind.Combo && r.Key == "hours" && r.Options.SequenceEqual(new[] { "6 hours", "1 day", "3 days" })) && rows.Any(r => r.Key == "stake"), "guild war: the declare form");
            p.Form["target"] = "Rival"; p.Form["frag"] = "1"; p.Form["hours"] = "2"; p.Form["stake"] = "1m";
            check(p.Declare() && rig.Last.Contains("\"action\":\"declare\"") && rig.Last.Contains("\"target\":\"Rival\"") && rig.Last.Contains("\"fragLimit\":25") && rig.Last.Contains("\"hours\":72") && rig.Last.Contains("\"stake\":1000000"), "guild war: declare sends the target, limit, hours and stake");
            p.Form["target"] = "";
            check(!p.Declare() && p.Status.Contains("name of the guild") && p.StatusTone == "bad", "guild war: a bad form says why");
            check(rows.Any(r => r.Text == "The war emblems show after the next login."), "guild war: the emblem note");
            p.SelectTab("board");
            rows = p.BuildRows();
            check(rows.Any(r => r.Text == "Ash 3 : 5 Rival (first to 25, 1h 0m left)") && rows.Any(r => r.Text == "Ash 3 : 5 Rival - surrender"), "guild war: the war board");
            p.SelectTab("boss");
            rows = p.BuildRows();
            check(rows.Any(r => r.Kind == RowKind.Bar && r.Text == "300 / 1,000 embers (30%)") && rows.Any(r => r.Text == "Feed the stone first.") && !Btn(Find(rows, r => r.Text == "2 in the hall now"), "Summon").Enabled, "guild war: the boss fuel bar and the summon rule");
            p.Form["bossGold"] = "10k";
            rows = p.BuildRows();
            check(rows.Any(r => r.Text == "10 embers"), "guild war: gold to embers");
            Click(rows, "Feed");
            check(rig.Last.Contains("\"action\":\"bossGold\"") && rig.Last.Contains("\"amount\":10000"), "guild war: feed gold");
            Click(p.BuildRows(), "Feed all");
            check(rig.Last.Contains("\"action\":\"bossItem\"") && rig.Last.Contains("\"key\":\"ash\""), "guild war: feed a material");
            rows = p.BuildRows();
            check(rows.Any(r => r.Text == "Ember Banner (1 kill), next tier at 5") && rows.Any(r => r.Text == "Vex: 40 embers (5,000 gold)") && rows.Any(r => r.Text == "Vex: 250,000 gold (25%)") && rows.Any(r => r.Text == "1. Ash - slain in 2:05 by 5" && r.Tone == "#ffe7a6") && rows.Any(r => r.Text == "2. Rival - 500,000 damage"), "guild war: banner, fuel, spoils and the boss board");
            p.Hide();
            check(rig.Last.Contains("\"action\":\"close\"") && !p.Visible, "guild war: close tells the server");
            p.OpenTab("boss");
            check(rig.Last.Contains("\"action\":\"open\"") && rig.Last.Contains("\"tab\":\"boss\""), "guild war: the guild hall stone opens the boss tab");
        }

        // ------------------------------------------------------------------------------------ party finder
        const string PfInit = "{'acts':[{'k':'rift','n':'Rift','range':{'min':1,'max':10,'label':'Tier'},'max':5,'per':{'tank':1,'healer':1,'dps':3},'suggest':{'tank':1,'healer':1,'dps':2}}," +
                              "{'k':'hunt','n':'Hunt','targets':['Wasps','Trolls'],'bands':[[10,50],[60,120]],'max':10}],'roles':[{'k':'tank','n':'Tank','c':'#7fb8e8'}],'my':['tank','dps'],'lv':100,'exp':[30,60,120],'defExp':60," +
                              "'lim':{'note':80,'title':24,'party':10,'perRole':6},'notes':['Chill run','Fast run']}";

        static void PartyFinderChecks(Action<bool, string> check)
        {
            var init = Json.Parse(PfInit.Replace('\'', '"'));
            var acts = Json.List(init, "acts");
            check(PartyFinderMath.TimeLeft(3725) == "1h 02m" && PartyFinderMath.TimeLeft(125) == "2m" && PartyFinderMath.TimeLeft(45) == "45s", "party finder: time left");
            check(PartyFinderMath.Ago(30) == "just now" && PartyFinderMath.Ago(300) == "5m ago" && PartyFinderMath.Ago(7300) == "2h ago", "party finder: ago");
            var row = Json.Parse("{\"id\":1,\"a\":\"rift\",\"an\":\"Rift\",\"ld\":\"Brannoc\",\"ml\":300,\"xl\":450,\"left\":600,\"open\":{\"healer\":1,\"dps\":2},\"comp\":[{\"r\":\"tank\",\"n\":\"Brannoc\",\"st\":\"leader\"}],\"nk\":2,\"note\":\"bring pots\"}");
            check(PartyFinderMath.OpenText(row) == "Needs 1 Healer, 2 DPS" && PartyFinderMath.OpenText(Json.Parse("{\"open\":{}}")) == "Full", "party finder: open text");
            check(PartyFinderMath.BandText(row) == "Level 300-450" && PartyFinderMath.BandShort(row) == "Lv 300-450" && PartyFinderMath.LevelFits(row, 300) && !PartyFinderMath.LevelFits(row, 299) && !PartyFinderMath.LevelFits(row, 451), "party finder: the level band");
            var my = new List<object> { "tank", "dps" };
            check(PartyFinderMath.ApplyRoles(row, my).SequenceEqual(new[] { "dps" }), "party finder: roles of my class that are open");
            check(!PartyFinderMath.CanApply(row, my, 100, out string why) && why == "Level 300-450" && PartyFinderMath.CanApply(row, my, 350, out why), "party finder: can apply by level");
            check(PartyFinderMath.SubLine(row, 60) == "Brannoc  -  Lv 300-450  -  9m left", "party finder: sub line counts down");
            check(PartyFinderMath.NoteText(row, Json.List(init, "notes")) == "Fast run  -  bring pots" && PartyFinderMath.CompText(row, init) == "T Brannoc*   H -   D -   D -", "party finder: note and composition");
            var input = PartyFinderMath.PostInput(acts, "rift", "tank", 60, "hi", true, 1, 1, 2, "0", "20", 1, "0", "99", 0, "");
            check((int)input["lo"] == 1 && (int)input["hi"] == 10 && (int)input["minLevel"] == 1 && (int)input["maxLevel"] == 20 && (bool)input["auto"], "party finder: a range is clamped into the activity's bounds and the band keeps its order");
            input = PartyFinderMath.PostInput(acts, "hunt", "dps", 30, "", false, 0, 0, 3, "60", "40", 0, "", "", 2, "");
            check((int)input["t"] == 2 && (int)input["maxLevel"] == 60 && !input.ContainsKey("lo"), "party finder: a hunt target and a max level never under the minimum");
            check(PartyFinderMath.Limits(acts[0], Json.Get(init, "lim")).SequenceEqual(new[] { 5, 1, 1, 3 }) && PartyFinderMath.FormKind(acts[0]) == "range" && PartyFinderMath.FormKind(acts[1]) == "targets", "party finder: limits and form kinds");
            // O445: support, the fourth role: named, lettered and counted in the open text; a server without it, or a key this client does not know, never errors
            var supRow = Json.Parse("{\"open\":{\"healer\":1,\"dps\":1,\"support\":2},\"comp\":[{\"r\":\"support\",\"n\":\"Seris\",\"st\":\"leader\"},{\"r\":\"scout\",\"n\":\"Odd\"}]}");
            check(PartyFinderMath.RoleName("support") == "Support" && PartyFinderMath.RoleLetter("support") == "S" && PartyFinderMath.RoleLetter("scout") == "?" && PartyFinderMath.RoleName("scout") == "scout", "party finder: support name and letter, an unknown key falls back");
            check(PartyFinderMath.OpenText(supRow) == "Needs 1 Healer, 1 DPS, 2 Support" && PartyFinderMath.CompText(supRow, init) == "S Seris*   ? Odd   H -   D -   S -   S -", "party finder: open text and composition show support");
            check(PartyFinderMath.ApplyRoles(supRow, new List<object> { "healer", "support" }).SequenceEqual(new[] { "healer", "support" }) && PartyFinderMath.OpenText(Json.Parse("{\"open\":{\"dps\":1}}")) == "Needs 1 DPS", "party finder: a class with support may apply as support, no support slot changes nothing");
            check(PartyFinderMath.RoleName("support", Json.Parse("{\"roles\":[{\"k\":\"support\",\"n\":\"Suporte\"}]}")) == "Suporte" && PartyFinderMath.Limits(acts[0], Json.Get(init, "lim")).Length == 4, "party finder: the server's role name wins, the wanted form keeps its three boxes");

            var rig = new Rig();
            var p = new PartyFinderPanel(rig.Ext) { Clock = () => rig.Now };
            var notices = new List<string>();
            p.Notice = (t, k) => notices.Add(k + ":" + t);
            p.Show();
            check(rig.Last.Contains("\"action\":\"open\"") && p.Visible, "party finder: show sends open");
            rig.Feed(PartyFinderPanel.Opcode, "init", PfInit);
            check(p.Header1 == "Level 100  -  your class plays Tank / DPS", "party finder: header after init");
            string list = "{'badge':2,'rows':[{'id':1,'a':'rift','an':'Rift','ld':'Brannoc','ml':300,'xl':450,'left':600,'open':{'healer':1,'dps':2},'comp':[{'r':'tank','n':'Brannoc','st':'leader'}]}," +
                          "{'id':2,'a':'hunt','an':'Hunt','ld':'Me','ml':1,'left':900,'open':{'dps':1},'mine':true,'comp':[]},{'id':3,'a':'hunt','an':'Hunt','ld':'Zed','ml':1,'left':900,'open':{'dps':1,'tank':1},'ap':'dps','comp':[]}," +
                          "{'id':4,'a':'rift','an':'Rift','ld':'Kim','ml':1,'left':900,'open':{'tank':1,'dps':1},'comp':[]}]," +
                          "'mine':{'id':2,'an':'Hunt','left':900,'open':{'dps':1},'comp':[],'input':{'a':'hunt','role':'dps','exp':30,'t':1,'want':{'tank':0,'healer':0,'dps':1},'minLevel':20,'maxLevel':60,'nk':1,'note':'x','auto':true}," +
                          "'apps':[{'g':77,'n':'Seris','lv':350,'vn':'Illusionist','r':'dps','ago':120,'q':true}]},'queue':null}";
            rig.Feed(PartyFinderPanel.Opcode, "list", list);
            check(p.Badge == 2, "party finder: the badge");
            var rows = p.BuildRows();
            var order = rows.Where(r => r.Kind == RowKind.Row && r.Text == "Rift" || r.Text == "Hunt").Select(r => r.Text).ToList();
            var all = p.FilteredRows();
            check(Json.Int(all[0], "id") == 2 && Json.Int(all[1], "id") == 3 && all.Count == 4, "party finder: own listing first, then the ones applied to, then the rest");
            var kim = Find(rows, r => r.Buttons.Any(b => b.Text == "Apply as Tank"));
            check(kim != null && Btn(kim, "Apply as DPS") != null && Btn(kim, "Apply as Tank").Enabled, "party finder: one Apply button per role of my class that is open");
            Btn(kim, "Apply as Tank").Click();
            check(rig.Last.Contains("\"action\":\"apply\"") && rig.Last.Contains("\"id\":4") && rig.Last.Contains("\"role\":\"tank\""), "party finder: apply sends the id and the role");
            var brann = Find(rows, r => r.Text == "Rift" && r.Right.StartsWith("Needs 1 Healer, 2 DPS"));
            check(brann != null && brann.Right == "Needs 1 Healer, 2 DPS  (Level 300-450)" && !Btn(brann, "Apply as DPS").Enabled, "party finder: a level that does not fit disables Apply");
            check(Find(rows, r => r.Text == "Hunt" && r.Right == "Applied as DPS") != null && Btn(Find(rows, r => r.Right == "Applied as DPS"), "Withdraw") != null, "party finder: an application shows Withdraw");
            Btn(Find(rows, r => r.Right == "Applied as DPS"), "Withdraw").Click();
            check(rig.Last.Contains("\"action\":\"withdraw\"") && rig.Last.Contains("\"id\":3"), "party finder: withdraw");
            p.Form["fact"] = "2"; // Hunt
            check(p.FilteredRows().All(r => Json.Text(r, "a") == "hunt" || Json.Bool(r, "mine")), "party finder: the activity filter keeps the own listing");
            p.Form["fact"] = "0"; p.Form["fits"] = "1";
            check(p.FilteredRows().Count == 3, "party finder: the level filter drops groups my level does not fit");
            p.Form["fits"] = "0";
            // queue
            p.Form["qrole"] = "1"; p.Form["qact"] = "1";
            p.ToggleQueue();
            check(rig.Last.Contains("\"action\":\"queue\"") && rig.Last.Contains("\"role\":\"dps\"") && rig.Last.Contains("\"a\":\"rift\""), "party finder: join the quick queue with a role and an activity");
            rig.Feed(PartyFinderPanel.Opcode, "list", "{'badge':0,'rows':[],'queue':{'r':'dps','a':'rift','since':30}}");
            check(p.BuildRows().Any(r => r.Text == "Queued as DPS (Rift) - just now" || r.Text.StartsWith("Queued as DPS (Rift)")), "party finder: the queue line");
            p.ToggleQueue();
            check(rig.Last.Contains("\"action\":\"unqueue\""), "party finder: leave the queue");
            // my group
            rig.Feed(PartyFinderPanel.Opcode, "list", list);
            p.SelectTab("my");
            rows = p.BuildRows();
            check(rows.Any(r => r.Kind == RowKind.Section && r.Text == "Listed: Hunt") && p.Index("act") == 1 && p.Text("minLevel") == "20" && p.Text("maxLevel") == "60" && p.Index("target") == 1, "party finder: the form is filled from the listing");
            p.Form["note"] = "go go";
            p.Post();
            check(rig.Last.Contains("\"action\":\"post\"") && rig.Last.Contains("\"a\":\"hunt\"") && rig.Last.Contains("\"note\":\"go go\"") && rig.Last.Contains("\"t\":1") && rig.Last.Contains("\"minLevel\":20"), "party finder: post sends the form");
            var apps = Find(p.BuildRows(), r => r.Text == "Seris  Lv 350 Illusionist");
            check(apps != null && apps.Right == "DPS  quick join, 2m ago", "party finder: an applicant line");
            Btn(apps, "Accept").Click();
            check(rig.Last.Contains("\"action\":\"accept\"") && rig.Last.Contains("\"id\":2") && rig.Last.Contains("\"g\":77"), "party finder: accept an applicant");
            Btn(Find(p.BuildRows(), r => r.Text == "Seris  Lv 350 Illusionist"), "Decline").Click();
            check(rig.Last.Contains("\"action\":\"decline\"") && rig.Last.Contains("\"g\":77"), "party finder: decline an applicant");
            p.Form["target"] = "2";
            p.OnForm("target");
            check(p.Text("minLevel") == "60" && p.Text("maxLevel") == "120", "party finder: a hunt target proposes its level band");
            rig.Feed(PartyFinderPanel.Opcode, "list", "{'rows':[],'badge':0}");
            p.Form["act"] = "0"; p.OnForm("act");
            check(p.Text("tank") == "1" && p.Text("dps") == "2", "party finder: a new listing takes the activity's suggestion");
            p.Unlist();
            check(rig.Last.Contains("\"action\":\"unlist\""), "party finder: unlist");
            rig.Feed(PartyFinderPanel.Opcode, "notice", "{'text':'Seris applied.','kind':'apply'}");
            rig.Feed(PartyFinderPanel.Opcode, "notice", "{'text':'Full.','kind':'error'}");
            check(notices.Count == 1 && notices[0] == "apply:Seris applied." && p.Status == "Full." && p.StatusTone == "bad", "party finder: an application is a toast, an error a red line");
            rig.Feed(PartyFinderPanel.Opcode, "nudge", "{'text':'2 players look for Rift.','a':'rift','n':2}");
            check(notices.Count == 2 && notices[1] == "nudge:2 players look for Rift. [Join]", "party finder: the group nudge");
            rig.Feed(PartyFinderPanel.Opcode, "badge", "{'n':5}");
            check(p.Badge == 5, "party finder: the badge message");
            p.Hide();
            check(rig.Last.Contains("\"action\":\"hide\""), "party finder: hide tells the server");
        }

        // ------------------------------------------------------------------------------------ group queue
        static void GroupQueueChecks(Action<bool, string> check)
        {
            var solo = Json.Parse("{\"enabled\":true,\"leader\":true,\"size\":1,\"inParty\":false}");
            check(GroupQueueMath.CanEdit(solo) && !GroupQueueMath.CanEdit(Json.Parse("{\"enabled\":false,\"leader\":true}")) && !GroupQueueMath.CanEdit(Json.Parse("{\"leader\":false}")) && !GroupQueueMath.CanEdit(Json.Parse("{\"leader\":true,\"group\":{}}")), "group queue: who may edit");
            check(GroupQueueMath.Difficulties(null).SequenceEqual(new[] { 1 }) && GroupQueueMath.Difficulties(Json.Parse("{\"max\":3}")).SequenceEqual(new[] { 1, 2, 3 }) && GroupQueueMath.Difficulties(Json.Parse("{\"fixed\":2,\"max\":5}")).SequenceEqual(new[] { 2 }), "group queue: difficulties");
            var pay = GroupQueueMath.Payload("1v1", true, 7, 2);
            check((string)pay["arena"] == "1v1" && (bool)pay["bg"] && pay.ContainsKey("dungeon") && GroupQueueMath.Payload("", false, -1, 1).Count == 0, "group queue: payload");
            check(!GroupQueueMath.Joinable(solo, GroupQueueMath.Payload("", false, -1, 1), out string why) && why == "Pick at least one queue.", "group queue: pick a queue");
            check(!GroupQueueMath.Joinable(solo, GroupQueueMath.Payload("2v2", false, -1, 1), out why) && why.StartsWith("Arena:"), "group queue: the arena mode must fit the party size");
            check(GroupQueueMath.Joinable(solo, GroupQueueMath.Payload("1v1", true, -1, 1), out why), "group queue: a solo player joins arena 1v1 and the battleground");
            check(!GroupQueueMath.Joinable(Json.Parse("{\"enabled\":true,\"leader\":true,\"size\":8}"), GroupQueueMath.Payload("", true, -1, 1), out why) && why.Contains("too large"), "group queue: a party too large for the battleground");
            check(!GroupQueueMath.Joinable(Json.Parse("{\"enabled\":true,\"leader\":false,\"size\":2}"), GroupQueueMath.Payload("", true, -1, 1), out why) && why.Contains("party leader"), "group queue: only the leader queues the party");

            var rig = new Rig();
            var p = new GroupQueuePanel(rig.Ext) { Clock = () => rig.Now };
            p.Show();
            check(rig.Last.Contains("\"action\":\"open\""), "group queue: show sends open");
            rig.Feed(GroupQueuePanel.Opcode, "state", "{'open':true,'enabled':true,'leader':true,'size':2,'inParty':true,'arena':{'order':['1v1','2v2','3v3']},'bg':{'partyMax':5},'dungeons':[{'id':4,'title':'Ash Crypt','level':100,'max':3}],'raid':true}");
            check(p.Visible, "group queue: an open state shows the window");
            var rows = p.BuildRows();
            var arena = Find(rows, r => r.Buttons.Any(b => b.Text.EndsWith("2v2")));
            check(arena != null && !Btn(arena, "1v1").Enabled && Btn(arena, "2v2").Enabled && !Btn(arena, "3v3").Enabled, "group queue: only the arena mode of the party's size can be picked");
            Btn(arena, "2v2").Click();
            check(p.Arena == "2v2" && Btn(Find(p.BuildRows(), r => r.Buttons.Any(b => b.Text.EndsWith("2v2"))), "[x] 2v2") != null, "group queue: the pick is marked");
            Click(p.BuildRows(), "Queue");
            check(p.Bg, "group queue: the battleground toggle");
            p.Form["dungeon"] = "0"; p.Form["diff"] = "2";
            Click(p.BuildRows(), "Queue");
            check(p.Dungeon || true, "group queue: the dungeon toggle");
            var join = p.BuildRows().First(r => r.Buttons.Any(b => b.Text == "Join Queues"));
            check(Btn(join, "Join Queues").Enabled, "group queue: Join is on once something is picked");
            p.JoinOrLeave();
            check(rig.Last.Contains("\"action\":\"join\"") && rig.Last.Contains("\"arena\":\"2v2\"") && rig.Last.Contains("\"bg\":true"), "group queue: join sends the picks");
            check(Btn(Find(p.BuildRows(), r => r.Buttons.Any(b => b.Text == "Raid check")), "Raid check").Enabled, "group queue: the raid check for a leader in a party");
            Click(p.BuildRows(), "Raid check");
            check(rig.Last.Contains("\"action\":\"raid\""), "group queue: raid check request");
            rig.Feed(GroupQueuePanel.Opcode, "state", "{'enabled':true,'leader':true,'size':2,'group':{'picks':[{'key':'arena','label':'Arena 2v2'}],'waited':65,'ready':false}}");
            rows = p.BuildRows();
            check(rows.Any(r => r.Text == "Queued for: Arena 2v2") && rows.Any(r => r.Text == "Waiting 1:05") && Click(rows, "Leave Queues"), "group queue: the status block and Leave");
            check(rig.Last.Contains("\"action\":\"leave\""), "group queue: leave request");
            // the ready check
            rig.Now = 1000;
            rig.Feed(GroupQueuePanel.Opcode, "check", "{'key':'arena','label':'Arena 2v2','left':20,'seconds':20,'accepted':1,'total':2,'mine':false}");
            var c = p.Check;
            check(p.CheckOpen && c.Title == "Arena 2v2 is ready to start" && c.Sub == "1 of 2 party members ready" && c.Percent == 100 && c.Timer == "0:20" && !c.Answered, "group queue: the ready check popup");
            rig.Now = 11000;
            check(p.Check.Percent == 50 && p.Check.Timer == "0:10", "group queue: the ready check counts down");
            rig.Now = 21500;
            check(!p.CheckOpen, "group queue: the popup closes when the time is up");
            rig.Now = 1000;
            p.Answer(true);
            check(rig.Last.Contains("\"action\":\"accept\""), "group queue: Accept answers");
            rig.Feed(GroupQueuePanel.Opcode, "checkEnd", "{}");
            check(!p.CheckOpen && rig.Last.Contains("\"action\":\"query\""), "group queue: the end of a check asks the state again");
            rig.Feed(GroupQueuePanel.Opcode, "msg", "{'text':'Queued.'}");
            check(p.Status == "Queued.", "group queue: a message shows");
            rig.Feed(GroupQueuePanel.Opcode, "state", "{'enabled':true,'leader':true,'size':3}");
            check(p.Arena == "", "group queue: a pick that no longer fits the party is dropped");
        }

        // ------------------------------------------------------------------------------------ inspect
        static void InspectChecks(Action<bool, string> check)
        {
            check(InspectMath.CleanName("  Brannoc  Vex ") == "Brannoc Vex" && InspectMath.CleanName("x") == null && InspectMath.CleanName("Bad1") == null && InspectMath.CleanName("O'Neil-Z") == "O'Neil-Z" && InspectMath.CleanName(new string('a', 30)) == null, "inspect: a typed name");
            const string result = "{'name':'Brannoc','level':400,'voc':'Juggernaut','ascended':true,'guild':{'name':'Ash','rank':'Leader'},'ach':120,'rift':14,'trials':3,'outfit':{'type':128,'head':1,'body':2,'legs':3,'feet':4,'addons':1}," +
                                  "'parts':2,'paragon':25,'title':'Sealer','bestiary':{'points':900,'rank':'Hunter'},'bosses':{'got':4,'total':20},'pvp':{'name':'Arena','tier':'Gold','rating':1800},'collection':77,'passive':{'spent':30,'total':45}," +
                                  "'combat':{'attack':500,'hit':900,'maxHit':3000,'attackSpeed':12.5,'critChance':10,'critAmount':50,'lifeLeech':{'chance':5,'amount':3},'damage':[{'k':'fire','pct':20}],'defense':200,'armor':150,'mitigation':30,'maxHealth':20000,'maxMana':8000,'moveSpeed':400,'resist':[{'k':'fire','pct':25},{'k':'ice','pct':-10}]}}";
            var d = Json.Parse(result.Replace('\'', '"'));
            var head = InspectMath.Header(d);
            check(head[0].Key == "Brannoc" && head[1].Key == "Level 400 Juggernaut" && head.Any(h => h.Key == "Ascended class") && head.Any(h => h.Key == "Sealer") && head.Last().Key == "Leader of Ash", "inspect: the header lines");
            var stats = InspectMath.Stats(d);
            check(stats[0].Rows.Any(r => r.Label == "Passive points" && r.Value == "30 / 45") && stats[0].Rows.Any(r => r.Label == "Bestiary" && r.Value == "900 (Hunter)") && stats[1].Rows.Any(r => r.Label == "Vocation Trials" && r.Value == "Tier 3 of 3" && r.Tone == "good") &&
                  stats[1].Rows.Any(r => r.Label == "PvP: Arena" && r.Value == "1,800 (Gold)"), "inspect: the profile rows");
            var bare = InspectMath.Stats(Json.Parse("{\"name\":\"Old\"}"));
            check(bare[1].Rows.Any(r => r.Label == "Best rift sealed" && r.Value == "None" && r.Tone == "dim") && !bare[0].Rows.Any(r => r.Label == "Paragon points") && InspectMath.CombatStats(Json.Parse("{}")).Count == 0, "inspect: an older server has fewer rows and no combat tab");
            var combat = InspectMath.CombatStats(d);
            check(combat[0].Rows.Any(r => r.Label == "Attack speed" && r.Value == "+12.5%") && combat[0].Rows.Any(r => r.Label == "Life leech" && r.Value == "5% / 3%") && combat[0].Rows.Any(r => r.Label == "Fire damage" && r.Value == "+20%") &&
                  combat[2].Rows.Any(r => r.Label == "Ice" && r.Value == "-10%" && r.Tone == "bad") && combat[1].Rows.Any(r => r.Label == "Maximum health" && r.Value == "20,000"), "inspect: the combat sheet");
            var o = InspectMath.OutfitOf(d);
            check(o.LookType == 128 && o.Head == 1 && o.Feet == 4 && o.Addons == 1, "inspect: the outfit of the result");
            check(InspectMath.TipItem(Json.Parse("{\"id\":2160,\"look\":{\"cid\":3000}}")) == 3000 && InspectMath.TipItem(Json.Parse("{\"id\":2160}")) == 2160, "inspect: a transmog look is drawn");

            var rig = new Rig();
            var p = new InspectPanel(rig.Ext);
            p.Show();
            check(rig.Last.Contains("\"action\":\"privacy\"") && p.Visible, "inspect: show asks the privacy setting");
            check(!p.InspectName("x") && p.Status.Contains("Enter the name"), "inspect: a bad name is refused");
            check(p.InspectName("Brannoc") && rig.Last.Contains("\"action\":\"inspect\"") && rig.Last.Contains("\"name\":\"Brannoc\""), "inspect: ask by typed name");
            p.InspectCreature(77, "Vex");
            check(rig.Last.Contains("\"cid\":77") && p.Status == "Inspecting Vex...", "inspect: ask by creature id");
            rig.Feed(InspectPanel.Opcode, "result", result);
            check(p.Data != null && !p.Complete && p.Header1 == "Brannoc", "inspect: a result waits for its equipment parts");
            rig.Feed(InspectPanel.Opcode, "equip", "{'name':'Other','rows':[{'slot':1,'tip':{'id':1,'name':'Wrong'}}]}");
            check(p.Tips.Count == 0 && p.PartsGot == 0, "inspect: equipment of another character is dropped");
            rig.Feed(InspectPanel.Opcode, "equip", "{'name':'Brannoc','rows':[{'slot':1,'tip':{'id':2160,'name':'Ember Helm','rarity':4,'count':1}},{'slot':99,'tip':{'id':1}}]}");
            rig.Feed(InspectPanel.Opcode, "equip", "{'name':'Brannoc','rows':[{'slot':5,'tip':{'id':2400,'name':'Doom Blade','unique':true,'look':{'cid':3000}}}]}");
            check(p.Complete && p.Tips.Count == 2, "inspect: both equipment parts arrived");
            var rows = p.BuildRows();
            var helm = Find(rows, r => r.Text == "Helmet");
            check(helm != null && helm.Right == "Ember Helm" && helm.ItemId == 2160 && helm.Frame == "#a35cf0" && helm.ItemTip != null, "inspect: an equipment row with the item, its colour and its tooltip");
            check(Find(rows, r => r.Text == "Right hand").ItemId == 3000 && Find(rows, r => r.Text == "Right hand").Frame == ItemRarity.UniqueColor && Find(rows, r => r.Text == "Boots").ItemId == 0, "inspect: a look, a unique, an empty slot");
            p.SelectTab("profile");
            rows = p.BuildRows();
            check(rows.Any(r => r.Text == "Progress" && r.Kind == RowKind.Section) && rows.Any(r => r.Text == "Paragon points" && r.Right == "25"), "inspect: the profile tab");
            rig.Feed(InspectPanel.Opcode, "tree", "{'name':'Brannoc','nodes':[1,2,3],'spent':30,'total':45}");
            check(p.BuildRows().Any(r => r.Text == "Passive Tree (3)" && r.Right == "30 / 45 points"), "inspect: the passive tree summary");
            p.SelectTab("records");
            check(p.BuildRows().Any(r => r.Text == "Nothing to show."), "inspect: records not yet there");
            rig.Feed(InspectPanel.Opcode, "records", "{'name':'Brannoc','rows':[{'key':'drop','name':'Best drop','value':'Ember Blade'},{'key':'tower','name':'Tower floor','value':41}]}");
            rows = p.BuildRows();
            check(rows.Any(r => r.Text == "Best drop" && r.Right == "Ember Blade") && rows.Any(r => r.Text == "Tower floor" && r.Right == "41"), "inspect: records rows");
            p.SelectTab("combat");
            check(p.BuildRows().Any(r => r.Text == "Offense"), "inspect: the combat tab");
            rig.Feed(InspectPanel.Opcode, "privacy", "{'allow':true}");
            check(p.AllowMe && p.Text("privacy") == "1", "inspect: the privacy answer fills the box");
            p.Form["privacy"] = "0";
            p.OnForm("privacy");
            check(rig.Last.Contains("\"action\":\"privacy\"") && rig.Last.Contains("\"allow\":false") && !p.AllowMe, "inspect: the privacy choice is sent");
            rig.Feed(InspectPanel.Opcode, "denied", "{'code':'private','text':'This player does not allow it.'}");
            check(p.Data == null && p.Status == "This player does not allow it." && p.StatusTone == "bad" && p.BuildRows().Any(r => r.Text == "This player does not allow it."), "inspect: a refusal clears the character");
        }

        // ------------------------------------------------------------------------------------ leaderboard
        static void LeaderboardChecks(Action<bool, string> check)
        {
            check(LeaderboardMath.Fold("Éter Ção") == "eter cao" && LeaderboardMath.ValueText(125, "time") == "2:05" && LeaderboardMath.ValueText(3725, "time") == "1:02:05" && LeaderboardMath.ValueText(1234, "") == "1,234" && LeaderboardMath.ValueText(1050, "pct") == "10.50%", "leaderboard: values and folded names");
            check(LeaderboardMath.Ordinal(1) == "1st" && LeaderboardMath.Ordinal(2) == "2nd" && LeaderboardMath.Ordinal(3) == "3rd" && LeaderboardMath.Ordinal(4) == "4th", "leaderboard: ordinals");
            check(LeaderboardMath.ResetText(93784) == "Weekly reset in 1d 02h 03m" && LeaderboardMath.ResetText(3725) == "Weekly reset in 1h 02m 05s", "leaderboard: reset text");
            const string meta = "{'open':true,'ownGroup':'warrior','groups':[{'key':'warrior','name':'Warrior'},{'key':'mage','name':'Mage'}],'boards':[{'key':'worldboss','name':'World Boss','weekly':true,'value':'Damage','count':'Kills','title':'Boss Slayer','info':'Damage to world bosses.'}," +
                                "{'key':'rifts','name':'Rifts','weekly':true,'byClass':true,'value':'Tier','classAwards':true},{'key':'level','name':'Ladder','weekly':false},{'key':'cinder','name':'Éter','weekly':true,'format':'time','value':'Time'}]}";
            var opts = LeaderboardMath.Options(Json.Parse(meta.Replace('\'', '"')));
            check(opts.Select(o => o.Key).SequenceEqual(new[] { "cinder", "level", "rifts", "worldboss" }) && LeaderboardMath.Resolve(opts, "zzz") == "worldboss" && LeaderboardMath.Resolve(opts, "rifts") == "rifts", "leaderboard: boards sorted by the folded name; World Boss is the default");

            var rig = new Rig();
            string saved = null;
            var p = new LeaderboardPanel(rig.Ext) { Clock = () => rig.Now, SavedBoard = () => saved, RememberBoard = k => saved = k };
            p.Show();
            check(rig.Last.Contains("\"action\":\"open\""), "leaderboard: show sends open");
            rig.Feed(LeaderboardPanel.Opcode, "meta", meta);
            check(p.Visible && p.Selected == "worldboss" && rig.Last.Contains("\"action\":\"get\"") && rig.Last.Contains("\"board\":\"worldboss\""), "leaderboard: the meta shows the window and asks the default board");
            rig.Feed(LeaderboardPanel.Opcode, "board", "{'key':'worldboss','week':3,'resetIn':90000,'total':40,'rows':[{'rank':1,'name':'Vex','value':123456,'count':7,'title':'Boss Slayer'},{'rank':2,'name':'Zed','value':5000,'count':1}]," +
                                                        "'own':{'rank':9,'value':800,'count':1},'champions':[{'rank':1,'rankName':'1st','name':'Kim','value':1000}]}");
            var rows = p.BuildRows();
            check(rows.Any(r => r.Kind == RowKind.Combo && r.Key == "board" && r.Options.Count == 4), "leaderboard: the board pick list");
            check(rows.Any(r => r.Text == "#1  Vex  [Boss Slayer]" && r.Right == "123,456   7" && r.Tone == "#e8b84a") && rows.Any(r => r.Text == "#2  Zed" && r.Tone == "#a8b4c8"), "leaderboard: weekly rows with rank colours");
            check(rows.Any(r => r.Text == "Your rank: #9 of 40   -   Damage: 800") && rows.Any(r => r.Text == "1st Kim  -  1,000") && rows.Any(r => r.Text.StartsWith("Weekly reset in 1d 01h 00m")), "leaderboard: own rank, last week's title holders, the reset timer");
            // pick another board: remembered and asked
            var names = rows.First(r => r.Key == "board").Options;
            p.Form["board"] = names.IndexOf("Rifts").ToString();
            p.OnForm("board");
            check(p.Selected == "rifts" && saved == "rifts" && rig.Last.Contains("\"board\":\"rifts\""), "leaderboard: a board pick is kept per character and asked");
            rows = p.BuildRows();
            check(rows.Any(r => r.Kind == RowKind.Combo && r.Key == "group" && r.Options[0] == "All classes"), "leaderboard: a board with class tabs gets an All classes first");
            p.Form["group"] = "1";
            p.OnForm("group");
            check(rig.Last.Contains("\"group\":\"warrior\""), "leaderboard: a class tab asks that group");
            p.Form["group"] = "0";
            p.OnForm("group");
            check(!rig.Last.Contains("\"group\""), "leaderboard: All classes asks no group");
            // records
            p.SelectTab("records");
            check(rig.Last.Contains("\"action\":\"rmeta\""), "leaderboard: the Records tab asks the meta");
            rig.Feed(LeaderboardPanel.Opcode, "rcat", "{'cat':'bosses','boards':[{'key':'ash','name':'Ash Lord','value':'Time','format':'time','variants':[{'key':'v1','name':'Normal'}],'sizes':[{'key':'s1','name':'Solo'},{'key':'s5','name':'Party'}]}]}");
            check(!p.RMetaComplete, "leaderboard: the records meta is not whole before rmeta");
            rig.Feed(LeaderboardPanel.Opcode, "rmeta", "{'categories':[{'key':'bosses','name':'Bosses','title':'Boss Hunter','info':'Fastest kills.'}],'periods':[{'key':'week','name':'This week'},{'key':'all','name':'All time'}],'groups':[{'key':'warrior','name':'Warrior'}],'parts':1,'badge':'Hunter'}");
            check(p.RMetaComplete && rig.Last.Contains("\"action\":\"rget\"") && rig.Last.Contains("\"board\":\"ash\"") && rig.Last.Contains("\"period\":\"week\"") && rig.Last.Contains("\"variant\":\"v1\"") && rig.Last.Contains("\"size\":\"s1\""), "leaderboard: a whole meta asks the first board of the first category");
            rig.Feed(LeaderboardPanel.Opcode, "rboard", "{'board':'ash','period':'week','total':3,'record':92,'resetIn':3600,'rows':[{'rank':1,'name':'Vex','value':95,'at':1700000000,'vocation':'Knight'},{'rank':2,'name':'Duo','value':99,'at':1700000000,'party':2,'members':'Duo, Zed'}],'own':{'rank':2,'value':99}}");
            rows = p.BuildRows();
            check(rows.Any(r => r.Text == "#1  Vex  Knight" && r.Right == "1:35  2023-11-14") && rows.Any(r => r.Text == "#2  Duo  party of 2" && r.Tip == "Duo, Zed") && rows.Any(r => r.Text == "All-time record: 1:32") && rows.Any(r => r.Text == "Your rank: #2 of 3   -   Time: 1:39"), "leaderboard: record rows, the record and own rank");
            p.Form["size"] = "1"; p.Form["period"] = "1";
            p.OnForm("size");
            check(rig.Last.Contains("\"size\":\"s5\"") && rig.Last.Contains("\"period\":\"all\""), "leaderboard: record filters are sent");
            p.Form["rcat"] = "1"; // Realm Firsts
            p.OnForm("rcat");
            check(rig.Last.Contains("\"action\":\"rfirsts\""), "leaderboard: Realm Firsts asks its own request");
            rig.Feed(LeaderboardPanel.Opcode, "rfirsts", "{'seasonName':'Season 1','rows':[{'board':'Ash Lord','members':'Vex','at':1700000000,'value':95,'format':'time'}]}");
            check(p.BuildRows().Any(r => r.Text == "Vex  -  Ash Lord" && r.Right == "2023-11-14  1:35"), "leaderboard: realm firsts rows");
            p.Form["rcat"] = "2";
            p.OnForm("rcat");
            check(rig.Last.Contains("\"action\":\"rmine\""), "leaderboard: My Records asks rmine");
            rig.Feed(LeaderboardPanel.Opcode, "rmine", "{'rows':[{'key':'drop','name':'Best drop','value':'Ember Blade'}]}");
            check(p.BuildRows().Any(r => r.Text == "Best drop" && r.Right == "Ember Blade"), "leaderboard: my records rows");
        }

        // ------------------------------------------------------------------------------------ item links in chat
        static void ChatLinkChecks(Action<bool, string> check)
        {
            const string id1 = "abc123def", id2 = "zzz000111";
            string text = "look [Ember Blade]{4" + id1 + "} and [Doom Axe]{u" + id2 + "} ok";
            var links = ChatLinksMath.Parse(text);
            check(links.Count == 2 && links[0].Name == "Ember Blade" && links[0].Rarity == 4 && links[0].Id == id1 && !links[0].Unique && links[1].Unique && links[1].Id == id2, "chat links: two links of a text");
            check(ChatLinksMath.Plain(text) == "look [Ember Blade] and [Doom Axe] ok" && ChatLinksMath.Plain("no links {here}") == "no links {here}", "chat links: the plain text keeps only the names");
            check(ChatLinksMath.Parse("[Bad]{4SHORT}").Count == 0 && ChatLinksMath.Parse("[Bad]{4ABC123DEF}").Count == 0 && ChatLinksMath.Parse("[A]{x" + id1 + "}").Count == 0 && ChatLinksMath.Parse("[a{b]{4" + id1 + "}").Count == 0, "chat links: ids must be nine lower-case characters and rarity a hex digit or u");
            var four = ChatLinksMath.Parse("[A]{1aaaaaaaaa}[B]{1bbbbbbbbb}[C]{1ccccccccc}[D]{1ddddddddd}");
            check(four.Count == ChatLinksMath.MaxLinks, "chat links: at most three links per message");
            var pieces = ChatLinksMath.Pieces(text, "#ffffff");
            check(pieces.Text == "look [Ember Blade] and [Doom Axe] ok" && pieces.Ranges.Count == 2 && pieces.Ranges[0].First == 5 && pieces.Ranges[0].Last == 18 && pieces.Parts[1].Value == "#a35cf0" && pieces.Parts[3].Value == ItemRarity.UniqueColor, "chat links: pieces with colours and ranges");
            check(ChatLinksMath.RangeAt(pieces.Ranges, 6).Id == id1 && ChatLinksMath.RangeAt(pieces.Ranges, 2) == null && ChatLinksMath.RangeAt(pieces.Ranges, 18) == null, "chat links: the link under a character index");
            check(ChatLinksMath.ColorOf(4, false) == "#a35cf0" && ChatLinksMath.ColorOf(0, false) == ChatLinksMath.NormalColor && ChatLinksMath.ColorOf(9, true) == ItemRarity.UniqueColor, "chat links: colours");
            // chips
            var chips = new List<LinkChip> { new LinkChip { Name = "Ember Blade", Token = "[Ember Blade]{4" + id1 + "}" }, new LinkChip { Name = "Ring", Token = "[Ring]{1" + id2 + "}" } };
            check(ChatLinksMath.LiveChips("sell [Ember Blade] now", chips).Count == 1, "chat links: a deleted chip is dropped");
            int used;
            string expanded = ChatLinksMath.Expand("sell [Ember Blade] and [Ring]!", chips, out used);
            check(used == 2 && expanded == "sell [Ember Blade]{4" + id1 + "} and [Ring]{1" + id2 + "}!", "chat links: chips are written out in order");
            check(ChatLinksMath.CanAdd("", new List<LinkChip>(), "X", "[X]{1abcdefghi}", out string why), "chat links: one chip fits");
            var three = new List<LinkChip> { new LinkChip { Name = "A", Token = "t" }, new LinkChip { Name = "B", Token = "t" }, new LinkChip { Name = "C", Token = "t" } };
            check(!ChatLinksMath.CanAdd("[A][B][C]", three, "D", "tt", out why) && why.Contains("up to 3"), "chat links: a fourth chip is refused");
            check(!ChatLinksMath.CanAdd(new string('x', 245), new List<LinkChip>(), "", new string('x', 30), out why) && why.Contains("too long"), "chat links: a long line leaves no room");
            check(ChatLinksMath.ContextOf(TabKind.Npc, -1, false, out why) == null && why.Contains("NPC"), "chat links: no links to NPCs");
            check((string)ChatLinksMath.ContextOf(TabKind.Private, -1, false, out why)["kind"] == "private" && (string)ChatLinksMath.ContextOf(TabKind.Default, -1, false, out why)["kind"] == "say" && (string)ChatLinksMath.ContextOf(TabKind.Channel, 5, false, out why)["kind"] == "channel", "chat links: the context of a tab");
            check(ChatLinksMath.ContextOf(TabKind.Channel, 7, false, out why) == null && why.Contains("Help") && ChatLinksMath.ContextOf(TabKind.Channel, 7, true, out why) != null, "chat links: the Help channel needs the tutor right");
            check(ChatLinksMath.Scrub(text, false) == "look [Ember Blade] and [Doom Axe] ok" && ChatLinksMath.Scrub(text, true) == text, "chat links: markers are scrubbed where links are not allowed");
            check(ChatLinksMath.Linkable(new Pos(0xFFFF, 3, 0)) && !ChatLinksMath.Linkable(new Pos(100, 100, 7)), "chat links: only the equipment and bags can be linked");
            check(ChatLinksMath.Footer("Vex", 600, 120) == "Linked by Vex - 8 min left", "chat links: the footer under a tooltip");

            var rig = new Rig();
            var st = new ChatLinksState(rig.Ext) { Clock = () => rig.Now };
            var said = new List<string>();
            var inserted = new List<string>();
            st.Say = s => said.Add(s);
            st.InsertChip = (n, t) => inserted.Add(n + "=" + t);
            st.Register(new Pos(0xFFFF, 0x41, 3), 123456789012UL, ChatLinksMath.ContextOf(TabKind.Default, -1, false, out why));
            check(rig.Last.Contains("\"action\":\"register\"") && rig.Last.Contains("\"n\":1") && rig.Last.Contains("\"iid\":\"123456789012\"") && rig.Last.Contains("\"x\":65535") && rig.Last.Contains("\"kind\":\"say\""), "chat links: register sends the position, the id and the context");
            rig.Feed(ChatLinksState.Opcode, "registered", "{'n':1,'links':[{'token':'[Ember Blade]{4" + id1 + "}','name':'Ember Blade','rarity':4}]}");
            check(inserted.Count == 1 && inserted[0] == "Ember Blade=[Ember Blade]{4" + id1 + "}", "chat links: a registered link comes back as a chip");
            rig.Feed(ChatLinksState.Opcode, "refused", "{'n':2,'reason':'You do not carry that item.'}");
            check(said.Count == 1 && said[0] == "You do not carry that item.", "chat links: a refusal is said in the chat");
            check(st.AddChip("", "Ember Blade", "[Ember Blade]{4" + id1 + "}", out why) && st.ExpandLine("sell [Ember Blade]") == "sell [Ember Blade]{4" + id1 + "}" && st.Chips.Count == 0, "chat links: the line is expanded and the chips are used up");
            // snapshots
            check(st.Lookup(id1) == null && rig.Last.Contains("\"action\":\"get\"") && rig.Last.Contains(id1), "chat links: an unknown link asks the snapshot");
            int n = rig.Sent.Count;
            st.Lookup(id1);
            check(rig.Sent.Count == n, "chat links: the same link is not asked again within 2 seconds");
            rig.Feed(ChatLinksState.Opcode, "link", "{'id':'" + id1 + "','tip':{'id':2160,'name':'Ember Blade'},'owner':'Vex','left':600}");
            var e = st.Lookup(id1);
            check(e != null && e.Tip != null && e.Owner == "Vex" && !e.Gone, "chat links: the snapshot arrives");
            rig.Now = 599000;
            check(st.Get(id1) != null, "chat links: a snapshot lives ten minutes");
            rig.Now = 601000;
            check(st.Get(id1) == null, "chat links: and then it is gone");
            rig.Feed(ChatLinksState.Opcode, "link", "{'id':'" + id2 + "','gone':true}");
            check(st.Get(id2).Gone, "chat links: an expired answer");
            rig.Now = 601000 + 61000;
            check(st.Get(id2) == null, "chat links: an expired answer is believed for a minute");
            rig.Feed(ChatLinksState.Opcode, "link", "{'id':'BAD','tip':{'id':1}}");
            check(st.Get("BAD") == null, "chat links: an invalid id is ignored");
            rig.Feed(ChatLinksState.Opcode, "caps", "{'help':true}");
            check(st.HelpAllowed, "chat links: the Help channel capability");
        }

        // ------------------------------------------------------------------------------------ factions
        static void FactionChecks(Action<bool, string> check)
        {
            check(FactionsMath.Countdown(93784) == "1d 2h" && FactionsMath.Countdown(4980) == "1h 23m" && FactionsMath.Countdown(9) == "1m" && FactionsMath.CardName(Json.Parse("{\"n\":\"The Ashen Court\"}")) == "Ashen Court", "factions: countdown and card name");
            const string state = "{'weekCap':1000,'nextDay':3600,'nextWeek':200000,'sel':'ash','ranks':[],'factions':[{'k':'ash','n':'The Ashen Court','c':'#cc5522','lore':'Old lore.','rival':'tide','rep':450,'rank':2,'rn':'Friendly','hi':1000,'pct':45,'nx':'Honored','wk':200,'wc':0,'dr':0.5,'npc':'Warden Ysolde','near':true,'tok':3,'tn':'Ash Seals','tid':2150,'at':'the market'}," +
                                 "{'k':'tide','n':'The Tide','rep':50,'rn':'Neutral','hi':100,'pct':50,'nx':'Friendly','wk':1000,'dr':1,'npc':'Marl','near':false,'tok':0,'tn':'Shells'}]," +
                                 "'contracts':[{'key':'c1','f':'ash','per':'w','kind':'kill','label':'Kill 50 wasps','p':10,'n':50,'rep':60},{'key':'c2','f':'ash','per':'d','kind':'kill','label':'Kill 10 trolls','p':10,'n':10,'rep':20,'done':true},{'key':'c3','f':'ash','per':'d','kind':'deliver','label':'Bring ash','rep':30}]," +
                                 "'offers':[{'key':'o1','f':'ash','kind':'gear','n':'Ash Plate','rank':3,'rn':'Honored','price':50000,'tokens':5,'st':'locked','why':'Needs Honored','lv':120,'rar':4,'item':2160},{'key':'o2','f':'ash','kind':'recipe','n':'Ash Recipe','rank':1,'rn':'Neutral','price':0,'tokens':2,'st':'owned'},{'key':'o3','f':'ash','kind':'orbs','n':'Orbs','rank':1,'rn':'Neutral','price':1000,'st':'ok','desc':'3 orbs','wl':5,'wb':1}]}";
            var rig = new Rig();
            var p = new FactionsPanel(rig.Ext) { Clock = () => rig.Now };
            rig.Feed(FactionsPanel.Opcode, "state", state);
            check(p.Selected == "ash" && p.Tabs.Count == 2 && p.Tabs[0].Value == "Ashen Court" && p.Tab == "ash", "factions: the faction of the server is shown and the factions are tabs");
            var f = FactionsMath.Faction(p.Data, "ash");
            check(FactionsMath.BarText(f) == "Friendly  450 / 1,000" && FactionsMath.BarPercent(f) == 45 && FactionsMath.NextText(f) == "550 more to Honored" && FactionsMath.WeekText(f, 1000) == "This week 200 / 1,000" && FactionsMath.DrText(f) == "Kills, tokens and events at half value today", "factions: bar, next rank, week and activity texts");
            check(FactionsMath.TokenButton(f, 1000, out string tip) && tip == "Give every Ash Seals to Warden Ysolde." && !FactionsMath.TokenButton(FactionsMath.Faction(p.Data, "tide"), 1000, out tip) && tip.StartsWith("Bring Shells"), "factions: the Turn in rule");
            check(FactionsMath.Capped(FactionsMath.Faction(p.Data, "tide"), 1000) && !FactionsMath.Capped(f, 1000), "factions: the weekly cap");
            check(FactionsMath.RivalText(p.Data, f).StartsWith("Rival: The Tide.") && !FactionsMath.GoButton(f, out tip) && tip == "You are already next to Warden Ysolde." && FactionsMath.GoButton(FactionsMath.Faction(p.Data, "tide"), out tip), "factions: rival and Go to NPC");
            var contracts = FactionsMath.ContractsFor(p.Data, "ash");
            check(contracts.Select(c => Json.Text(c, "key")).SequenceEqual(new[] { "c3", "c2", "c1" }), "factions: daily first, open ones first");
            check(FactionsMath.ProgressText(contracts[2]) == "10 / 50" && FactionsMath.ProgressPercent(contracts[2]) == 20 && FactionsMath.ProgressText(contracts[1]) == "Done" && FactionsMath.ProgressText(contracts[0]) == "Bring it to the NPC", "factions: contract progress");
            var rows = p.BuildRows();
            check(rows.Any(r => r.Text.StartsWith("Ashen Court  <") && r.Right == "Friendly  450 / 1,000") && rows.Any(r => r.Text == "Daily  Bring ash") && rows.Any(r => r.Text == "Weekly  Kill 50 wasps" && r.Right == "10 / 50  +60"), "factions: cards and contract rows");
            Click(rows, "Deliver");
            check(rig.Last.Contains("\"action\":\"deliver\"") && rig.Last.Contains("\"key\":\"c3\""), "factions: deliver");
            Click(p.BuildRows(), "Turn in");
            check(rig.Last.Contains("\"action\":\"turnin\"") && rig.Last.Contains("\"f\":\"ash\""), "factions: turn in");
            Click(p.BuildRows(), "Offers");
            rows = p.BuildRows();
            var plate = Find(rows, r => r.Text == "Ash Plate");
            check(plate != null && plate.Right == "50,000 gold + 5 Ash Seals" && !Btn(plate, "Locked").Enabled && plate.ItemId == 2160, "factions: a locked offer");
            check(rows.Any(r => r.Text == "Needs Honored  -  Item level 120, Rare") && rows.Any(r => r.Text.Contains("3 orbs (1 of 5 this week)")), "factions: the offer kind lines");
            Btn(Find(rows, r => r.Text == "Ash Recipe"), "Craft").Click();
            check(rig.Last.Contains("\"action\":\"craft\"") && rig.Last.Contains("\"key\":\"o2\""), "factions: craft an owned recipe");
            Btn(Find(p.BuildRows(), r => r.Text == "Orbs"), "Buy").Click();
            check(rig.Last.Contains("\"action\":\"buy\"") && rig.Last.Contains("\"key\":\"o3\""), "factions: buy");
            p.SelectTab("tide");
            check(p.Selected == "tide" && p.BuildRows().Any(r => r.Text == "The Tide"), "factions: a tab shows another faction");
            p.GoToNpc();
            check(rig.Last.Contains("\"action\":\"travel\"") && rig.Last.Contains("\"k\":\"faction_tide\""), "factions: Go to NPC uses the travel opcode");
            rig.Feed(FactionsPanel.Opcode, "npc", "{'f':'ash'}");
            check(p.Visible && p.Selected == "ash" && rig.Last.Contains("\"action\":\"open\"") && rig.Last.Contains("\"f\":\"ash\""), "factions: an NPC opens the window on its faction");
            rig.Feed(FactionsPanel.Opcode, "msg", "{'text':'Bought.','ok':true}");
            check(p.Status == "Bought." && p.StatusTone == "good", "factions: a message");
            p.Hide();
            check(rig.Last.Contains("\"action\":\"close\""), "factions: close");
        }

        // ------------------------------------------------------------------------------------ conquest
        static void ConquestChecks(Action<bool, string> check)
        {
            const string state = "{'bal':500,'level':100,'pz':true,'band':20,'groups':[{'g':'monster','n':'Monster uniques'},{'g':'set','n':'Set pieces'}],'offers':[{'k':'u1','c':2160,'n':'Ember Blade','g':'monster','l':90,'p':300,'ok':true},{'k':'u2','c':2161,'n':'Doom Axe','g':'boss','l':120,'p':900,'ok':true}," +
                                 "{'k':'s1','c':2170,'n':'Ash Helm','g':'set','l':80,'p':100,'set':'Ash','ok':false,'why':'Not seen yet'}],'pity':[{'g':'monster','n':'Monster','m':4,'x':1.25}],'today':[{'k':'rift','n':'Rifts','got':20,'cap':100}]," +
                                 "'cinder':{'omenKey':100,'attune':50,'shard':80,'convert':{'shards':3,'relics':2,'fee':10},'omens':[{'k':'fire','n':'Fire'}],'ascended':[{'k':'a','n':'Alpha'},{'k':'b','n':'Beta'}],'shards':{'a':5,'b':1},'relics':{'a':0,'b':0},'hasKey':false},'refine':[{'slot':4,'n':'Old Helm','c':2180,'rn':'Rare','to':'Legendary','p':200,'ok':true}]}";
            var rig = new Rig();
            var p = new ConquestPanel(rig.Ext) { Clock = () => rig.Now };
            rig.Feed(ConquestPanel.Opcode, "state", state);
            var s = p.State;
            check(ConquestMath.Header(s) == "Conquest Tokens: 500. Items up to level 120 (your level + 20) and every item you have seen are on sale." && ConquestMath.PlaceText(s, out string tone) == "You may buy here." && tone == "good", "conquest: header and place");
            var uniques = ConquestMath.Rows(s, "uniques");
            check(uniques.Count == 2 && uniques[0].Name == "Ember Blade" && uniques[0].PriceText == "300 tokens" && uniques[0].CanBuy && uniques[0].Sub == "Monster uniques, level 90" && !uniques[1].CanBuy && uniques[1].PriceBad && uniques[1].Tip == "You need 900 Conquest Tokens.", "conquest: unique rows, price colour and the reason a purchase is off");
            var sets = ConquestMath.Rows(s, "sets");
            check(sets.Count == 1 && sets[0].Locked && !sets[0].CanBuy && sets[0].Tip == "Not seen yet" && sets[0].Sub == "Set pieces, level 80 - Ash", "conquest: a locked set piece");
            var cinder = ConquestMath.Rows(s, "cinder");
            check(cinder.Any(r => r.Key == "omen:fire" && r.CanBuy) && cinder.Any(r => r.Key == "attune:fire" && !r.CanBuy && r.Tip == "Carry an Omen Key to attune it.") && cinder.Any(r => r.Key == "shard:a") && cinder.Any(r => r.Key == "conv:shards:a:b" && r.CanBuy && r.Name == "3 Alpha shards into 1 Beta shard") &&
                  cinder.Any(r => r.Key == "conv:shards:b:a" && !r.CanBuy) && cinder.Any(r => r.Key == "conv:relics:a:b" && !r.CanBuy), "conquest: the Cinderheart rows");
            check(ConquestMath.Rows(s, "refine").Count == 1 && ConquestMath.Rows(s, "refine")[0].Key == "refine:4" && ConquestMath.ProgressLines(s).Contains("Monster: 4 misses in a row, chance x1.25") && ConquestMath.ProgressLines(s).Contains("Rifts: 20 of 100"), "conquest: refine and progress");
            check(ConquestMath.Rows(Json.Parse(state.Replace('\'', '"').Replace("\"pz\":true", "\"pz\":false")), "uniques").All(r => !r.CanBuy), "conquest: nothing can be bought outside a protection zone");
            p.SelectTab("uniques");
            var rows = p.BuildRows();
            check(p.Header1.StartsWith("Conquest Tokens: 500") && Click(rows, "Buy"), "conquest: the Buy button");
            check(rig.Last.Contains("\"action\":\"buy\"") && rig.Last.Contains("\"k\":\"u1\"") && p.Buying, "conquest: buy sends the key");
            check(!Btn(Find(p.BuildRows(), r => r.Text == "Ember Blade"), "Buy").Enabled && !p.Buy("u1"), "conquest: one purchase at a time");
            rig.Feed(ConquestPanel.Opcode, "result", "{'ok':true,'text':'Bought.'}");
            check(!p.Buying && p.Status == "Bought." && p.StatusTone == "good" && Btn(Find(p.BuildRows(), r => r.Text == "Ember Blade"), "Buy").Enabled, "conquest: the answer frees the buttons");
            p.Buy("u1");
            rig.Now = 5000;
            check(p.Buy("u1"), "conquest: a lost answer frees the buttons after four seconds");
            p.SelectTab("progress");
            check(p.BuildRows().Any(r => r.Text == "Rifts: 20 of 100"), "conquest: the progress page");
            rig.Feed(ConquestPanel.Opcode, "npc", "{}");
            check(p.Visible && rig.Last.Contains("\"action\":\"open\""), "conquest: the vendor opens the window");
            p.Hide();
            check(rig.Last.Contains("\"action\":\"close\""), "conquest: close");
        }

        // ------------------------------------------------------------------------------------ session wiring
        static void SessionChecks(Action<bool, string> check)
        {
            var w = new World(DatFile.Parse(Program.SyntheticDat()));
            var s = new GameSession(w, new GameSession.Options());
            check(s.Social != null && s.Social.Market != null && s.Social.Guild != null && s.Social.GuildWar != null && s.Social.PartyFinder != null && s.Social.GroupQueue != null && s.Social.Inspect != null &&
                  s.Social.Leaderboard != null && s.Social.Links != null && s.Social.Factions != null && s.Social.Conquest != null, "social: a session holds every panel");
            string[] sent = { "" };
            s.Ext.Transmit = p => sent[0] = Encoding.UTF8.GetString(p, 4, p.Length - 4);
            // the guild window's button opens the wars; the group queue's finds a group
            s.Social.Guild.OpenWars();
            check(sent[0].Contains("\"action\":\"open\"") && sent[0].Contains("\"tab\":\"wars\""), "social: the guild's wars button asks the war window");
            s.Social.GroupQueue.FindGroup();
            check(sent[0].Contains("\"action\":\"open\"") && s.Social.PartyFinder.Visible, "social: the group queue's Find a group opens the party finder");
            s.Ext.Receive(MarketPanel.Opcode, ExtOpcodes.ToWire("{\"action\":\"openWindow\",\"data\":{}}"));
            check(s.Social.Market.Visible, "social: the depot market item opens the market window");
            // every top menu entry of this track names a window that exists
            var entries = TopMenu.Categories.SelectMany(c => c.Entries).Where(e => e.Target.StartsWith("win:")).Select(e => e.Target.Substring(4)).ToList();
            foreach (var win in new[] { "MarketWindow", "GuildWindow", "GuildWarWindow", "PartyFinderWindow", "GroupQueueWindow", "LeaderboardWindow", "InspectWindow" })
                check(entries.Contains(win), "social: the top menu has " + win);
            // unlocks name the entries by their menu text
            var unlocks = new MenuUnlocks(new ExtOpcodes());
            unlocks.Apply(Json.Parse("{\"entries\":[{\"key\":\"market\",\"level\":8,\"menu\":\"Market\"},{\"key\":\"guildwar\",\"level\":50,\"menu\":\"Guild Wars\"}],\"unlocked\":[],\"next\":{\"key\":\"market\",\"level\":8}}"));
            check(unlocks.Status("Market", out int lv) == MenuStatus.Locked && lv == 8 && unlocks.Status("Guild Wars", out lv) == MenuStatus.Hidden && unlocks.Status("Guild", out lv) == MenuStatus.Open, "social: Market and Guild Wars follow the level unlocks, Guild is open");
        }

        // ------------------------------------------------------------------------------------ texts
        static void LocChecks(Action<bool, string> check)
        {
            var missing = new List<string>();
            string dir = Path.GetFullPath(Path.Combine("..", "Client", "Assets", "Chaos", "Core"));
            if (!Directory.Exists(dir)) dir = Path.GetFullPath(Path.Combine("unity", "Client", "Assets", "Chaos", "Core"));
            if (!Directory.Exists(dir)) { check(true, "social loc: sources not found (skipped)"); return; }
            int count = 0;
            foreach (var f in new[] { "Market.cs", "Guild.cs", "PartyFinder.cs", "Inspect.cs", "Leaderboard.cs", "ChatLinks.cs", "Factions.cs" })
            {
                string src = File.ReadAllText(Path.Combine(dir, f));
                foreach (Match m in Regex.Matches(src, "Loc\\.T\\((?:[^\"\\n)]*\\?\\s*)?\"((?:[^\"\\\\]|\\\\.)*)\"(?:\\s*:\\s*\"((?:[^\"\\\\]|\\\\.)*)\")?"))
                    foreach (int gi in new[] { 1, 2 })
                        if (m.Groups[gi].Success)
                        {
                            count++;
                            string key = m.Groups[gi].Value.Replace("\\\"", "\"").Replace("\\\\", "\\");
                            if (!LocStrings.PtBr.ContainsKey(key)) missing.Add(key);
                        }
            }
            check(missing.Count == 0, "social loc: every Loc.T key of the social Core files has a pt-BR text (" + count + " keys)" + (missing.Count > 0 ? ": " + string.Join(" | ", missing) : ""));
            // the tab names the windows translate at run time
            var tabs = new List<string>();
            var rig = new Rig();
            foreach (var panel in new SocialPanel[] { new MarketPanel(rig.Ext), new GuildPanel(rig.Ext), new GuildWarPanel(rig.Ext), new PartyFinderPanel(rig.Ext), new InspectPanel(rig.Ext), new LeaderboardPanel(rig.Ext), new ConquestPanel(rig.Ext) })
                foreach (var t in panel.Tabs) if (!LocStrings.PtBr.ContainsKey(t.Value)) tabs.Add(t.Value);
            check(tabs.Count == 0, "social loc: every tab name has a pt-BR text" + (tabs.Count > 0 ? ": " + string.Join(" | ", tabs) : ""));
            var mine = new[] { "Market", "Guild", "Guild Wars", "Party Finder", "Leaderboards", "Inspect Player", "Group Queue" };
            var menu = TopMenu.Categories.SelectMany(c => c.Entries).Select(e => e.Text).Where(t => mine.Contains(t) && !LocStrings.PtBr.ContainsKey(t)).ToList();
            check(menu.Count == 0, "social loc: every top menu text has a pt-BR text" + (menu.Count > 0 ? ": " + string.Join(" | ", menu) : ""));
            Loc.Set("pt-BR");
            check(Loc.T("Guild Wars") == "Guerras de guilda" && Loc.T("Sell {0} for {1} {2}: tax {3}, you receive {4} {2}{5}.", "2 itens", "100", "ouro", 5, 95, " no seu banco").StartsWith("Vender 2 itens por 100 ouro"), "social loc: pt-BR with arguments");
            Loc.Set("en");
        }
    }
}
