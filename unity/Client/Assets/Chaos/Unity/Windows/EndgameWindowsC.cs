// Endgame windows, part C (track L): the guild siege, the arena, the battleground, the Scorched Marches and the bounty board, each with its HUD.
// Models: Core/EndgamePvp.cs. No Ctrl hotkeys; they open from the Adventure menu or by the server.
using System;
using System.Collections.Generic;
using Chaos.Core;
using UnityEngine;

namespace Chaos.Client
{
    // ================================================================================================ Guild siege
    public sealed class SiegeWindow : GameWindow
    {
        bool lastVisible;
        Vector2 scroll;
        public override string Title => Loc.T("Guild Siege");
        protected override Rect Place(float w, float h) => new Rect(w / 2 - 250, 60, 500, 500);
        public override void Reset() { lastVisible = false; Open = false; }

        public override void Tick(ChaosApp app)
        {
            var s = app.Session?.Endgame?.Siege;
            if (s == null) return;
            WindowSync.Run(ref lastVisible, this, s.Visible, s.Show, s.Hide);
        }

        protected override void Body(ChaosApp app, Rect inner)
        {
            var s = app.Session?.Endgame?.Siege;
            if (s == null) return;
            var info = s.Info;
            var view = new Rect(inner.x + 4, inner.y + 2, inner.width - 8, inner.height - 4);
            float w = view.width - 20;
            var list = new List<KeyValuePair<string, string>>();
            scroll = GUI.BeginScrollView(view, scroll, new Rect(0, 0, w, 1200));
            float y = 2;
            if (info == null) { Eu.Label(app, new Rect(0, y, w, 20), Loc.T("Asking the server..."), Eu.Dim, 12); GUI.EndScrollView(); return; }
            Eu.Label(app, new Rect(0, y, w, 18), Loc.T("Next siege: {0} (server time)", Json.Get(info, "whenText") is string wt ? wt : "?"), Eu.Bright, 13, true);
            y += 20;
            Eu.Label(app, new Rect(0, y, w, 18), s.CountdownText(app.Session.Now), Eu.Gold, 14, true);
            y += 22;
            y += Eu.Wrap(app, 0, y, w, Json.Text(info, "status"), Eu.Text, 12);
            y += 4;
            string guild = Json.Text(info, "guild");
            if (guild.Length > 0)
            {
                int members = Json.Int(info, "members");
                Eu.Label(app, new Rect(0, y, w, 18), Loc.T(members == 1 ? "{0} - {1} member{2}" : "{0} - {1} members{2}", guild, members, Json.Truthy(info, "signed") ? Loc.T(", signed up") : ""), Eu.Text, 13, true);
            }
            else Eu.Label(app, new Rect(0, y, w, 18), Loc.T("You are not in a guild."), Eu.Dim, 13);
            y += 20;
            bool canJoin = Json.Truthy(info, "canJoin"), signed = Json.Truthy(info, "signed");
            string reason = (!canJoin && !signed) ? Json.Text(info, "joinReason") : (signed ? Loc.T("Members enter through the portals next to the temples when it starts.") : "");
            y += Eu.Wrap(app, 0, y, w, reason, Eu.Dim, 11);
            if (Eu.Button(new Rect(0, y, 140, 26), Loc.T("Sign up"), canJoin)) s.Join();
            if (Eu.Button(new Rect(148, y, 140, 26), Loc.T("Withdraw"), Json.Truthy(info, "canLeave"))) s.Leave();
            y += 36;
            var signups = Eg.Objects(info, "signups");
            Eu.Label(app, new Rect(0, y, w, 18), Loc.T("Signed up ({0} / {1})", signups.Count, Json.Int(info, "capacity")), Eu.Gold, 13, true);
            y += 20;
            if (signups.Count == 0) { Eu.Label(app, new Rect(4, y, w, 16), Loc.T("No guild yet."), Eu.Dim, 12); y += 17; }
            for (int i = 0; i < signups.Count; i++) { Eu.Label(app, new Rect(4, y, w, 16), (i + 1) + ". " + Json.Text(signups[i], "name"), Json.Truthy(signups[i], "own") ? "#ffe7a6" : Eu.Text, 12); y += 16; }
            y += 6;
            Eu.Label(app, new Rect(0, y, w, 18), Loc.T("Champions"), Eu.Gold, 13, true);
            y += 20;
            var champs = Eg.Objects(info, "champions");
            if (champs.Count == 0) { Eu.Label(app, new Rect(4, y, w, 16), Loc.T("No champions this week."), Eu.Dim, 12); y += 17; }
            foreach (object c in champs) { Eu.Label(app, new Rect(4, y, w, 16), Json.Text(c, "name") + " - " + Loc.T("until {0}", Json.Get(c, "untilText") is string ut ? ut : "?"), Eu.Bright, 12); y += 16; }
            y += 6;
            Eu.Label(app, new Rect(0, y, w, 18), Loc.T("Rules"), Eu.Gold, 13, true);
            y += 20;
            foreach (string r in Eg.Strings(info, "rules")) y += Eu.Wrap(app, 4, y, w - 4, "- " + r, Eu.Text, 11);
            GUI.EndScrollView();
        }
    }

    public sealed class SiegeHudWindow : EgHudWindow
    {
        public override string Title => Loc.T("Guild Siege");
        protected override Rect Place(float w, float h) => new Rect(w - 300, 120, 280, 220);
        protected override bool Wanted(ChaosApp app) => app.Session.Endgame.Siege.Hud != null;

        protected override void Body(ChaosApp app, Rect inner)
        {
            var s = app.Session?.Endgame?.Siege;
            if (s == null || s.Hud == null) return;
            var d = s.Hud;
            float x = inner.x + 6, w = inner.width - 12, y = inner.y + 2;
            Eu.Label(app, new Rect(x, y, w, 18), SiegeView.Title(d), Eu.Bright, 14, true);
            y += 20;
            Eu.Label(app, new Rect(x, y, w, 20), Json.Text(d, "phase") == "ending" ? Loc.T("Final score") : Eg.Clock(Json.Number(d, "left")), "#f4d27a", 16, true);
            y += 22;
            string holder = SiegeView.Holder(d, out string hc);
            Eu.Label(app, new Rect(x, y, w, 16), holder, hc, 12, true);
            y += 20;
            foreach (object t in SiegeView.Sorted(Json.Get(d, "teams")))
            {
                ChaosApp.Fill(new Rect(x, y + 2, 10, 12), Eu.Hex(Json.Text(t, "color"), "#8c8070"));
                int mem = Json.Int(t, "members");
                Eu.Label(app, new Rect(x + 16, y, w - 110, 16), Json.Text(t, "name", "?") + (mem > 0 ? " (" + mem + ")" : ""), Json.Truthy(t, "own") ? "#ffe7a6" : "#e8dcc2", 12);
                Eu.Label(app, new Rect(x + w - 94, y, 36, 16), Json.Int(t, "kills") + " K", Eu.Dim, 11, false, TextAnchor.UpperRight);
                Eu.Label(app, new Rect(x + w - 54, y, 54, 16), Fmt.Short(Json.Number(t, "score")), Eu.Text, 12, true, TextAnchor.UpperRight);
                y += 17;
            }
            string you = SiegeView.YouText(Json.Get(d, "you"));
            if (you.Length > 0) Eu.Label(app, new Rect(x, y + 4, w, 16), you, Eu.Text, 11);
        }
    }

    // ================================================================================================ Arena
    public sealed class ArenaWindow : GameWindow
    {
        bool lastVisible;
        Vector2 scroll;
        public override string Title => Loc.T("Arena");
        protected override Rect Place(float w, float h) => new Rect(w / 2 - 320, 60, 640, 520);
        public override void Reset() { lastVisible = false; Open = false; }

        public override void Tick(ChaosApp app)
        {
            var a = app.Session?.Endgame?.Arena;
            if (a == null) return;
            EndgameBridge.Wire(app);
            WindowSync.Run(ref lastVisible, this, a.Visible, a.Show, a.Hide);
        }

        protected override void Body(ChaosApp app, Rect inner)
        {
            var a = app.Session?.Endgame?.Arena;
            if (a == null) return;
            double now = app.Session.Now;
            float x = inner.x + 4, w = inner.width - 8, y = inner.y + 2;
            if (a.State == null) { Eu.Label(app, new Rect(x, y, w, 20), Loc.T("Asking the server..."), Eu.Dim, 12); return; }
            var ratings = Json.Get(a.State, "ratings");
            var season = Json.Get(a.State, "season");
            var brackets = Json.Get(season, "brackets");
            float cw = (w - 16) / 3;
            for (int i = 0; i < ArenaState.Modes.Length; i++)
            {
                string mode = ArenaState.Modes[i];
                var r = Json.Get(ratings, mode);
                var card = new Rect(x + i * (cw + 8), y, cw, 150);
                Eu.Panel(card, 0.07f);
                Eu.Label(app, new Rect(card.x + 6, card.y + 4, card.width - 12, 18), ArenaText.ModeTitle(mode), Eu.Bright, 14, true);
                string line = ArenaText.SeasonLine(Json.Get(brackets, mode), Json.Number(season, "id"), out string col, out _);
                Eu.Label(app, new Rect(card.x + 6, card.y + 24, card.width - 12, 16), line, col, 11);
                Eu.Label(app, new Rect(card.x + 6, card.y + 42, card.width - 12, 30), (Json.Get(r, "rating") is double rt ? (int)rt : 1000).ToString(), Eu.Gold, 24, true);
                Eu.Label(app, new Rect(card.x + 6, card.y + 76, card.width - 12, 16), Loc.T("W-L-D {0}   best {1}", ArenaText.Record(r), Json.Get(r, "best") is double b ? (int)b : (Json.Get(r, "rating") is double rr ? (int)rr : 1000)), Eu.Dim, 11);
                int waiting = (int)Json.Number(Json.Get(a.State, "queueCount"), mode);
                Eu.Label(app, new Rect(card.x + 6, card.y + 92, card.width - 12, 14), mode == "1v1" ? Loc.T("{0} player(s) waiting.", waiting) : Loc.T("Party of exactly {0}: {1} team(s) waiting.", mode == "2v2" ? Loc.T("two") : Loc.T("three"), waiting), Eu.Dim, 10);
                if (Eu.Button(new Rect(card.x + 8, card.yMax - 34, card.width - 16, 26), Loc.T("Queue {0}", mode), !a.InQueue && !a.InMatch)) a.Queue(mode);
            }
            y += 160;
            Eu.Label(app, new Rect(x, y, w - 130, 18), a.StatusText(now), Eu.Text, 12, true);
            if (Eu.Button(new Rect(x + w - 120, y - 2, 120, 24), Loc.T("Leave Queue"), a.InQueue)) a.LeaveQueue();
            y += 22;
            Eu.Label(app, new Rect(x, y, w, 16), a.RulesLine(), Eu.Dim, 11);
            y += 16;
            y += Eu.Wrap(app, x, y, w, a.RulesTip(), Eu.Dim, 10);
            y += 4;
            Eu.Label(app, new Rect(x, y, w, 18), Loc.T("Recent matches"), Eu.Gold, 13, true);
            y += 20;
            var recent = Eg.Objects(a.State, "recent");
            var view = new Rect(x, y, w, inner.yMax - y - 2);
            int rowH = 22;
            scroll = GUI.BeginScrollView(view, scroll, new Rect(0, 0, view.width - 18, Mathf.Max(view.height, recent.Count * rowH)));
            if (recent.Count == 0) Eu.Label(app, new Rect(4, 2, view.width - 24, rowH), Loc.T("No matches yet."), Eu.Dim, 12);
            double stamp = Json.Get(a.State, "now") is double sn ? sn : 0;
            for (int i = 0; i < recent.Count; i++)
            {
                object m = recent[i];
                float ry = i * rowH;
                string rc;
                string res = ArenaText.Result(Json.Text(m, "result"), out rc);
                double before = Json.Number(m, "before"), after = Json.Number(m, "after");
                Eu.Label(app, new Rect(4, ry, 40, rowH), Json.Text(m, "mode"), Eu.Text, 11);
                Eu.Label(app, new Rect(48, ry, 70, rowH), res, rc, 11, true);
                Eu.Label(app, new Rect(120, ry, 130, rowH), (long)before + " -> " + (long)after + " (" + Eg.Delta(after - before) + ")", Eu.Text, 11);
                string vs = Loc.T("vs {0}", Json.Get(m, "opponents") is string op ? op : "?");
                if (Json.Text(m, "partner").Length > 0) vs += Loc.T(" (with {0})", Json.Text(m, "partner"));
                Eu.Label(app, new Rect(254, ry, view.width - 380, rowH), vs, Eu.Dim, 11);
                Eu.Label(app, new Rect(view.width - 122, ry, 100, rowH), ArenaText.Ago(stamp - Json.Number(m, "at")), Eu.Dim, 11, false, TextAnchor.UpperRight);
            }
            GUI.EndScrollView();
        }
    }

    public sealed class ArenaHudWindow : EgHudWindow
    {
        public override string Title => Loc.T("Arena");
        protected override Rect Place(float w, float h) => new Rect(w / 2 - 260, 8, 520, 190);
        protected override bool Wanted(ChaosApp app) => app.Session.Endgame.Arena.HudShown(app.Session.Now);

        void Side(ChaosApp app, Rect area, List<object> players, bool mine)
        {
            float y = area.y;
            foreach (object p in players)
            {
                Eu.Label(app, new Rect(area.x, y, area.width, 14), Json.Text(p, "name", "?"), Json.Truthy(p, "defeated") ? "#6b6258" : (mine ? Eu.Bright : "#e03a1e"), 11, true);
                double hp = Json.Number(p, "hp");
                if (Json.Truthy(p, "defeated")) Eu.Bar(app, new Rect(area.x, y + 14, area.width, 12), 0, "#000000", Loc.T("defeated"), 10);
                else Eu.Bar(app, new Rect(area.x, y + 14, area.width, 12), hp, ArenaText.HpColor(hp), (int)hp + "%", 10);
                y += 30;
            }
        }

        protected override void Body(ChaosApp app, Rect inner)
        {
            var a = app.Session?.Endgame?.Arena;
            if (a == null) return;
            double now = app.Session.Now;
            float x = inner.x + 6, w = inner.width - 12, y = inner.y + 2;
            if (a.ResultShown(now))
            {
                var res = a.Result;
                string rc;
                Eu.Label(app, new Rect(x, y + 10, w, 34), ArenaText.Result(Json.Text(res, "result"), out rc), rc, 28, true, TextAnchor.UpperCenter);
                string rating = Json.Get(res, "rated") != null && !Json.Truthy(res, "rated", true) ? Loc.T("Not rated") : ArenaText.RatingLine(Json.Number(res, "before"), Json.Number(res, "after"), Json.Number(res, "delta"));
                Eu.Label(app, new Rect(x, y + 50, w, 18), rating, Eu.Text, 14, false, TextAnchor.UpperCenter);
                string reward = Json.Text(res, "reward").Length > 0 ? Loc.T("Reward: {0}", Json.Text(res, "reward")) + (Json.Truthy(res, "firstWin") ? Loc.T(" (first win today)") : "") : "";
                var se = Json.Get(res, "season");
                if (se is Dictionary<string, object> && !(Json.Get(res, "rated") != null && !Json.Truthy(res, "rated", true))) reward = (reward.Length > 0 ? reward + "   " : "") + ArenaText.SeasonDelta(se);
                Eu.Label(app, new Rect(x, y + 72, w, 36), reward, Eu.Bright, 12, false, TextAnchor.UpperCenter, true);
                return;
            }
            var hud = a.Hud;
            if (hud == null) return;
            Eu.Label(app, new Rect(x, y, w, 16), Loc.T("Arena {0}", Json.Text(hud, "mode")), Eu.Text, 12, true, TextAnchor.UpperCenter);
            string big = ArenaText.HudCenter(Json.Text(hud, "phase"), Json.Number(hud, "left"), out string small);
            Eu.Label(app, new Rect(x + w / 2 - 60, y + 18, 120, 36), big, Json.Text(hud, "phase") == "countdown" ? "#e03a1e" : Eu.Bright, 28, true, TextAnchor.UpperCenter);
            Eu.Label(app, new Rect(x + w / 2 - 60, y + 54, 120, 16), Loc.T(small), Eu.Dim, 11, false, TextAnchor.UpperCenter);
            float sw = w / 2 - 70;
            Side(app, new Rect(x, y + 20, sw, 150), a.Side(true), true);
            Side(app, new Rect(x + w - sw, y + 20, sw, 150), a.Side(false), false);
        }
    }

    // ================================================================================================ Battleground
    public sealed class BattlegroundWindow : GameWindow
    {
        bool lastVisible, confirmLeave;
        Vector2 scroll;
        public override string Title => Loc.T("Battleground");
        protected override Rect Place(float w, float h) => new Rect(w / 2 - 300, 50, 600, 540);
        public override void Reset() { lastVisible = false; Open = false; confirmLeave = false; }

        public override void Tick(ChaosApp app)
        {
            var b = app.Session?.Endgame?.Battleground;
            if (b == null) return;
            EndgameBridge.Wire(app);
            WindowSync.Run(ref lastVisible, this, b.Visible, b.Show, b.Hide);
        }

        protected override void Body(ChaosApp app, Rect inner)
        {
            var b = app.Session?.Endgame?.Battleground;
            if (b == null) return;
            double now = app.Session.Now;
            float x = inner.x + 4, w = inner.width - 8, y = inner.y + 2;
            string[] keys = { "queue", "season", "vendor" };
            string[] names = { Loc.T("Queue"), Loc.T("Season"), Loc.T("Vendor") };
            for (int i = 0; i < 3; i++)
                if (GUI.Toggle(new Rect(x + i * 96, y, 92, 24), b.Tab == keys[i], names[i], GUI.skin.button) && b.Tab != keys[i]) b.ShowTab(keys[i]);
            if (GUI.Button(new Rect(x + w - 110, y, 110, 24), Loc.T("Scoreboard"))) b.ToggleBoard();
            y += 30;
            if (b.State == null) { Eu.Label(app, new Rect(x, y, w, 20), Loc.T("Asking the server..."), Eu.Dim, 12); return; }
            var list = new Rect(x, y, w, inner.yMax - y - 78);
            Eu.Panel(list, 0.04f);
            float contentH = DrawTab(app, b, new Rect(0, 0, list.width - 18, 4000), now, true);
            scroll = GUI.BeginScrollView(list, scroll, new Rect(0, 0, list.width - 18, Mathf.Max(list.height, contentH)));
            DrawTab(app, b, new Rect(0, 0, list.width - 18, contentH), now, false);
            GUI.EndScrollView();

            float by = inner.yMax - 72;
            Eu.Label(app, new Rect(x, by, w, 18), b.Message, b.MessageOk ? Eu.Good : Eu.Bright, 12);
            if (confirmLeave)
            {
                Eu.Label(app, new Rect(x, by + 18, w - 190, 30), Loc.T("Leave the match now? You become a deserter: a loss, no rewards and no queue for a while."), Eu.Bright, 11, false, TextAnchor.UpperLeft, true);
                if (GUI.Button(new Rect(x + w - 180, by + 22, 86, 26), Loc.T("Leave"))) { confirmLeave = false; b.QueueOrLeave(); }
                if (GUI.Button(new Rect(x + w - 90, by + 22, 90, 26), Loc.T("Stay"))) confirmLeave = false;
                return;
            }
            string label = b.InMatch ? Loc.T("Leave Match") : b.InQueue ? Loc.T("Leave Queue") : Loc.T("Queue");
            bool enabled = b.InMatch || b.InQueue || b.CanQueue;
            if (Eu.Button(new Rect(x, by + 22, 200, 30), label, enabled)) { if (b.InMatch) confirmLeave = true; else b.QueueOrLeave(); }
        }

        float DrawTab(ChaosApp app, BattlegroundState b, Rect area, double now, bool measureOnly)
        {
            float y = 4, x = area.x + 4, w = area.width - 8;
            Action<string, string, int, bool> text = (t, color, size, bold) =>
            {
                float h = Eu.Height(app, t, w, size);
                if (!measureOnly) Eu.Label(app, new Rect(x, y, w, h), t, color, size, bold, TextAnchor.UpperLeft, true);
                y += h + 3;
            };
            var state = b.State;
            var season = Json.Get(state, "season");
            Action cards = () =>
            {
                if (!(season is Dictionary<string, object>)) return;
                var order = Eg.Strings(season, "order");
                if (order.Count == 0) order.AddRange(BgView.BracketOrder);
                float cw = (w - 3 * 6) / 4;
                for (int i = 0; i < order.Count && i < 4; i++)
                {
                    var c = BgView.Card(Json.Get(Json.Get(season, "brackets"), order[i]), Json.Get(season, "tiers"), Json.Get(season, "placement") is double pl ? pl : 5);
                    var r = new Rect(x + i * (cw + 6), y, cw, 78);
                    if (!measureOnly)
                    {
                        Eu.Panel(r, 0.07f);
                        Eu.Label(app, new Rect(r.x + 4, r.y + 2, r.width - 8, 16), c.Name, Eu.Text, 12, true);
                        Eu.Label(app, new Rect(r.x + 4, r.y + 20, r.width - 8, 16), c.Tier, c.Color, 11, true);
                        Eu.Label(app, new Rect(r.x + 4, r.y + 36, r.width - 8, 24), c.Rating, Eu.Gold, 18, true);
                        Eu.Label(app, new Rect(r.x + 4, r.y + 60, r.width - 8, 14), c.Record, Eu.Dim, 10);
                    }
                }
                y += 84;
            };
            if (b.Tab == "queue")
            {
                var rules = Json.Get(state, "rules");
                text(Loc.T("Ember Wells"), "#ff9a3c", 14, true);
                text(Loc.T("{0}v{1} to {2}v{3}. Take and hold the three braziers: every held one scores, the first team to {4} wins. Downed players come back with the next wave (every {5}s). No item or experience loss. Damage and healing between players are scaled to your bracket's level.",
                    Json.Get(rules, "teamMin") is double tm ? (int)tm : 5, Json.Get(rules, "teamMin") is double tm2 ? (int)tm2 : 5, Json.Get(rules, "teamMax") is double tx ? (int)tx : 10, Json.Get(rules, "teamMax") is double tx2 ? (int)tx2 : 10,
                    Json.Get(rules, "win") is double wn ? (int)wn : 1000, Json.Get(rules, "wave") is double wv ? (int)wv : 15), "#b8ab92", 11, false);
                var br = Json.Get(state, "bracket");
                text(Loc.T("Your bracket: {0}", br is Dictionary<string, object> ? Json.Text(br, "name") + Loc.T(" (stats scaled to level {0})", Json.Int(br, "ref")) : Loc.T("none")), Eu.Text, 12, false);
                text(Loc.T("Queue as"), Eu.Gold, 13, true);
                var roles = BgView.RoleOptions(state);
                if (!measureOnly)
                    for (int i = 0; i < roles.Count; i++)
                    {
                        bool on = GUI.Toggle(new Rect(x + i * 100, y, 94, 24), roles[i].Chosen, roles[i].Text, GUI.skin.button);
                        if (on && !roles[i].Chosen && !b.InQueue) b.SetRole(roles[i].Key);
                    }
                y += 30;
                string status = BgView.QueueStatus(state, b.Elapsed(now), out string sc);
                text(status, sc, 12, false);
                text(Loc.T("Solo, or the party leader queues the party (up to {0}). Parties stay together; tanks and healers are spread over both teams.", Json.Get(rules, "partyMax") is double pm ? (int)pm : 5), Eu.Dim, 11, false);
                text(Loc.T("Season ratings"), Eu.Gold, 13, true);
                cards();
                text(BgView.HonorLine(state), Eu.Bright, 12, false);
                text(BgView.RecordLine(state), Eu.Dim, 11, false);
            }
            else if (b.Tab == "season")
            {
                if (!(season is Dictionary<string, object>)) { text(Loc.T("PvP seasons are not running on this server."), Eu.Dim, 12, false); return y; }
                text(BgView.SeasonTitle(season, b.Elapsed(now)), "#ff9a3c", 14, true);
                var decay = Json.Get(season, "decay");
                text(Loc.T("A season lasts {0} weeks. Each bracket has its own rating; the first {1} rated matches place you. At the end the best placed bracket decides your tier and rewards, then every rating is pulled halfway back to 1500. Ratings of {2} and more lose {3} a week after {4} days without a rated match of that bracket (never below {2}).",
                    Json.Get(season, "weeks") is double wk ? (int)wk : 8, Json.Get(season, "placement") is double pc ? (int)pc : 5, Json.Get(decay, "from") is double df ? (int)df : 2000,
                    Json.Get(decay, "perWeek") is double pw ? (int)pw : 30, Json.Get(decay, "graceDays") is double gd ? (int)gd : 14), "#b8ab92", 11, false);
                cards();
                text(Loc.T("Season rewards by tier"), Eu.Gold, 13, true);
                foreach (object t in Json.List(season, "tiers"))
                {
                    var parts = new List<string>();
                    if (Json.Get(t, "title") is string tt) parts.Add(Loc.T("title \"{0} (S{1})\"", tt, Json.Get(season, "id") is double sd ? (int)sd : 0));
                    if (Json.Get(t, "frame") is string fr) parts.Add(Loc.T("{0} plate frame", fr));
                    int cos = Json.List(t, "cosmetics").Count;
                    if (cos > 0) parts.Add(cos + (cos == 1 ? " cosmetic" : " cosmetics"));
                    parts.Add(Eg.Number(Json.Number(t, "honor")) + " honor");
                    text(Json.Text(t, "name") + " (" + (Json.Number(t, "min") > 0 ? Eg.Number(Json.Number(t, "min")) + "+" : "-") + ")", Eg.Hex(Json.Text(t, "color"), Eu.Text), 12, true);
                    text("   " + string.Join(", ", parts), Eu.Dim, 11, false);
                }
            }
            else
            {
                double honor = Json.Number(state, "honor");
                text(BgView.HonorLine(state), Eu.Bright, 13, true);
                text(Loc.T("Honor comes from battleground matches (win, loss, downs, wells taken, the weekly first win) and the season rewards. The vendor sells cosmetics and consumables only."), Eu.Dim, 11, false);
                foreach (object o in Eg.Objects(state, "vendor"))
                {
                    var v = BgView.VendorRow(o, honor);
                    var rc = new Rect(x, y, w, 42);
                    if (!measureOnly)
                    {
                        Eu.Panel(rc, 0.06f);
                        if (Json.Text(o, "kind") == "item" && Json.Get(o, "item") is double item) app.DrawItem(new Rect(rc.x + 4, rc.y + 5, 32, 32), (ushort)item, 1);
                        Eu.Label(app, new Rect(rc.x + 42, rc.y + 3, rc.width - 190, 18), v.Title, Eu.Text, 13, true);
                        Eu.Label(app, new Rect(rc.x + 42, rc.y + 22, rc.width - 190, 16), v.Sub, Eu.Dim, 11);
                        if (Eu.Button(new Rect(rc.xMax - 130, rc.y + 8, 124, 26), v.Button, v.Can)) b.Buy(Json.Text(o, "key"));
                    }
                    y += 45;
                }
            }
            return y + 6;
        }
    }

    public sealed class BattlegroundHudWindow : EgHudWindow
    {
        public override string Title => Loc.T("Ember Wells");
        protected override Rect Place(float w, float h) => new Rect(w / 2 - 230, 8, 460, 190);
        protected override bool Wanted(ChaosApp app) => app.Session.Endgame.Battleground.Hud != null;

        protected override void Body(ChaosApp app, Rect inner)
        {
            var b = app.Session?.Endgame?.Battleground;
            if (b == null || b.Hud == null) return;
            double now = app.Session.Now;
            var d = b.Hud;
            int mine = b.MyTeam, other = 3 - mine;
            var teams = Json.Get(d, "teams") as List<object> ?? new List<object> { "Team 1", "Team 2" };
            var colors = Json.Get(d, "colors") as List<object> ?? new List<object> { "#ff9a3c", "#8fb8ff" };
            var score = Json.Get(d, "score") as List<object> ?? new List<object> { 0.0, 0.0 };
            var players = Json.Get(d, "players") as List<object> ?? new List<object> { 0.0, 0.0 };
            Func<List<object>, int, string, string> sAt = (l, i, f) => i >= 1 && i <= l.Count && l[i - 1] is string s ? s : f;
            Func<List<object>, int, double> nAt = (l, i) => i >= 1 && i <= l.Count && l[i - 1] is double v ? v : 0;
            double win = Json.Get(d, "win") is double wd ? wd : 1000;
            float x = inner.x + 6, w = inner.width - 12, y = inner.y + 2;
            float half = w / 2 - 60;
            Eu.Label(app, new Rect(x, y, half, 16), sAt(teams, mine, "?") + " (" + (int)nAt(players, mine) + ")", sAt(colors, mine, Eu.Text), 12, true);
            Eu.Label(app, new Rect(x + w - half, y, half, 16), sAt(teams, other, "?") + " (" + (int)nAt(players, other) + ")", sAt(colors, other, Eu.Text), 12, true, TextAnchor.UpperRight);
            Eu.Bar(app, new Rect(x, y + 18, half, 14), BgView.ScorePercent(nAt(score, mine), win), sAt(colors, mine, Eu.Text), (int)nAt(score, mine) + " / " + (int)win);
            Eu.Bar(app, new Rect(x + w - half, y + 18, half, 14), BgView.ScorePercent(nAt(score, other), win), sAt(colors, other, Eu.Text), (int)nAt(score, other) + " / " + (int)win);
            double el = b.HudElapsed(now);
            string big = BgView.HudCenter(d, Math.Max(0, Json.Number(d, "left") - el), out string small);
            Eu.Label(app, new Rect(x + w / 2 - 55, y, 110, 30), big, Json.Text(d, "phase") == "prep" ? "#e03a1e" : Eu.Bright, 22, true, TextAnchor.UpperCenter);
            Eu.Label(app, new Rect(x + w / 2 - 55, y + 28, 110, 14), Loc.T(small), Eu.Dim, 10, false, TextAnchor.UpperCenter);
            y += 46;
            var wells = Json.List(d, "braziers");
            float ww = wells.Count > 0 ? (w - (wells.Count - 1) * 6) / wells.Count : w;
            for (int i = 0; i < wells.Count; i++)
            {
                var well = BgView.Brazier(wells[i], Json.Get(d, "teams"), Json.Get(d, "colors"));
                var r = new Rect(x + i * (ww + 6), y, ww, 44);
                Eu.Panel(r, 0.08f);
                Eu.Label(app, new Rect(r.x + 4, r.y + 3, r.width - 8, 16), well.Name, Eu.Text, 12, true, TextAnchor.UpperCenter);
                Eu.Label(app, new Rect(r.x + 4, r.y + 22, r.width - 8, 16), well.Text, well.Color, 11, true, TextAnchor.UpperCenter);
            }
            y += 50;
            string notice = BgView.HudNotice(d, Math.Max(0, Json.Number(d, "respawn") - el), Math.Max(0, Json.Number(d, "afk") - el), out string nc);
            if (notice.Length > 0) Eu.Label(app, new Rect(x, y, w, 18), notice, nc, 12, true, TextAnchor.UpperCenter);
        }
    }

    /// <summary>The scoreboard while a match runs and the summary after it.</summary>
    public sealed class BattlegroundBoardWindow : GameWindow
    {
        bool lastVisible;
        Vector2 scroll;
        public override string Title => Loc.T("Ember Wells: Scoreboard");
        public override bool InMenu => false;
        protected override Rect Place(float w, float h) => new Rect(w / 2 - 330, 90, 660, 440);
        public override void Reset() { lastVisible = false; Open = false; }

        public override void Tick(ChaosApp app)
        {
            var b = app.Session?.Endgame?.Battleground;
            if (b == null) return;
            WindowSync.Run(ref lastVisible, this, b.BoardVisible, b.ToggleBoard, b.HideBoard);
        }

        protected override void Body(ChaosApp app, Rect inner)
        {
            var b = app.Session?.Endgame?.Battleground;
            var data = b?.BoardData;
            if (b == null || data == null) { if (b != null) Eu.Label(app, new Rect(inner.x + 6, inner.y + 4, 300, 20), Loc.T("Asking the server..."), Eu.Dim, 12); return; }
            float x = inner.x + 6, w = inner.width - 12, y = inner.y + 2;
            var teams = Json.Get(data, "teams") as List<object> ?? new List<object> { "Team 1", "Team 2" };
            int team = Json.Get(data, "team") is double td ? (int)td : b.MyTeam;
            Func<int, string> name = i => i >= 1 && i <= teams.Count && teams[i - 1] is string s ? s : "?";
            if (b.Summary != null)
            {
                var sm = BgView.Summary(b.Summary, b.MyTeam);
                Eu.Label(app, new Rect(x, y, w, 30), sm.Title, sm.Color, 24, true, TextAnchor.UpperCenter);
                Eu.Label(app, new Rect(x, y + 30, w, 18), sm.Score, Eu.Text, 14, false, TextAnchor.UpperCenter);
                Eu.Label(app, new Rect(x, y + 48, w, 16), (sm.Rating.Length > 0 ? sm.Rating + "   " : "") + "(" + sm.Reason + ")", Eu.Dim, 11, false, TextAnchor.UpperCenter);
                Eu.Label(app, new Rect(x, y + 64, w, 16), sm.Honor, Eu.Bright, 12, false, TextAnchor.UpperCenter);
                y += 86;
            }
            else
            {
                var sc = Json.Get(data, "score") as List<object> ?? new List<object> { 0.0, 0.0 };
                Func<int, long> sv = i => i >= 1 && i <= sc.Count && sc[i - 1] is double v ? (long)v : 0;
                Eu.Label(app, new Rect(x, y, w, 22), Loc.T("Scoreboard"), Eu.Gold, 16, true, TextAnchor.UpperCenter);
                Eu.Label(app, new Rect(x, y + 22, w, 18), name(team) + " " + sv(team) + "  -  " + sv(3 - team) + " " + name(3 - team), Eu.Text, 14, false, TextAnchor.UpperCenter);
                y += 46;
            }
            var sides = BgView.BoardSides(Json.Get(data, "rows"), team);
            var view = new Rect(x, y, w, inner.yMax - y - 2);
            int rows = sides[0].Count + sides[1].Count + 4;
            scroll = GUI.BeginScrollView(view, scroll, new Rect(0, 0, view.width - 18, Mathf.Max(view.height, rows * 20 + 20)));
            float cy = 0, cw = view.width - 18;
            for (int side = 0; side < 2; side++)
            {
                int t = side == 0 ? team : 3 - team;
                Eu.Label(app, new Rect(0, cy, cw, 18), name(t) + (side == 0 ? Loc.T(" (your team)") : ""), side == 0 ? Eu.Bright : "#e03a1e", 13, true);
                cy += 19;
                string[] head = { Loc.T("Name"), Loc.T("Role"), "K", "A", "D", Loc.T("Wells"), Loc.T("Damage"), Loc.T("Healing"), b.Summary != null ? Loc.T("Honor") : "" };
                float[] cx = { 0, cw * 0.24f, cw * 0.38f, cw * 0.44f, cw * 0.50f, cw * 0.56f, cw * 0.65f, cw * 0.77f, cw * 0.90f };
                for (int i = 0; i < head.Length; i++) Eu.Label(app, new Rect(cx[i], cy, 80, 16), head[i], Eu.Dim, 11);
                cy += 17;
                foreach (var r in sides[side])
                {
                    string[] cells = { r.Name, r.Role, r.Kills.ToString(), r.Assists.ToString(), r.Downs.ToString(), r.Captures.ToString(), r.Damage, r.Healing, r.Honor };
                    for (int i = 0; i < cells.Length; i++)
                        Eu.Label(app, new Rect(cx[i], cy, i == 0 ? cw * 0.24f : 90, 16), cells[i], i == 1 ? r.RoleColor : (r.Left && i == 0 ? "#6b6258" : Eu.Text), 11, i == 0);
                    cy += 17;
                }
                cy += 8;
            }
            GUI.EndScrollView();
        }
    }

    // ================================================================================================ Scorched Marches
    public sealed class PvpZoneWindow : GameWindow
    {
        bool lastVisible;
        Vector2 scroll;
        public override string Title => Loc.T("Scorched Marches");
        protected override Rect Place(float w, float h) => new Rect(w / 2 - 290, 40, 580, 560);
        public override void Reset() { lastVisible = false; Open = false; }

        public override void Tick(ChaosApp app)
        {
            var z = app.Session?.Endgame?.PvpZone;
            if (z == null) return;
            EndgameBridge.Wire(app);
            WindowSync.Run(ref lastVisible, this, z.Visible, z.Show, z.Hide);
        }

        protected override void Body(ChaosApp app, Rect inner)
        {
            var z = app.Session?.Endgame?.PvpZone;
            if (z == null) return;
            float x = inner.x + 4, w = inner.width - 8, y = inner.y + 2;
            if (z.State == null) { Eu.Label(app, new Rect(x, y, w, 20), Loc.T("Asking the server..."), Eu.Dim, 12); return; }
            var list = new Rect(x, y, w, inner.yMax - y - 76);
            Eu.Panel(list, 0.04f);
            float contentH = DrawList(app, z, new Rect(0, 0, list.width - 18, 4000), true);
            scroll = GUI.BeginScrollView(list, scroll, new Rect(0, 0, list.width - 18, Mathf.Max(list.height, contentH)));
            DrawList(app, z, new Rect(0, 0, list.width - 18, contentH), false);
            GUI.EndScrollView();
            float by = inner.yMax - 70;
            Eu.Label(app, new Rect(x, by, w, 18), z.Message, z.MessageOk ? Eu.Good : Eu.Bright, 12);
            string text = PvpZoneView.EnterButton(z.State, out bool can, out string tip);
            if (Eu.Button(new Rect(x, by + 22, 220, 30), Loc.T(text), can)) z.ConfirmAsked = true;
            if (tip.Length > 0) Eu.Label(app, new Rect(x + 228, by + 22, w - 228, 40), tip, Eu.Dim, 11, false, TextAnchor.UpperLeft, true);
        }

        float DrawList(ChaosApp app, PvpZoneState z, Rect area, bool measureOnly)
        {
            float y = 4, x = area.x + 4, w = area.width - 8;
            Action<string, string, int, bool> text = (t, color, size, bold) =>
            {
                float h = Eu.Height(app, t, w, size);
                if (!measureOnly) Eu.Label(app, new Rect(x, y, w, h), t, color, size, bold, TextAnchor.UpperLeft, true);
                y += h + 3;
            };
            var s = z.State;
            text(Loc.T("How it works"), "#ff7a2a", 14, true);
            foreach (string l in PvpZoneView.Steps(s)) text(l, "#e8dcc2", 12, false);
            text(Loc.T("Open PvP, risk and reward"), "#ff7a2a", 14, true);
            var mon = Json.Get(s, "monsters");
            text(Loc.T("Level {0}+. Everyone in the Marches can attack you, whatever the world's rules. Nobody dies: a defeat throws you out and drops the embers you carry; your killer may take them. Bank them by standing {1}s in a safe exit circle. Monsters have x{2} health, x{3} damage and give x{4} experience and x{5} loot. No equipment or experience is ever lost here.",
                Json.Get(s, "minLevel") is double ml ? (int)ml : 150, Json.Get(s, "exitSeconds") is double es ? (int)es : 5,
                (Json.Get(mon, "hp") is double hp ? hp : 1).ToString("0.0", System.Globalization.CultureInfo.InvariantCulture), (Json.Get(mon, "damage") is double dm ? dm : 1).ToString("0.00", System.Globalization.CultureInfo.InvariantCulture),
                (Json.Get(mon, "exp") is double ex ? ex : 1).ToString("0.0", System.Globalization.CultureInfo.InvariantCulture), (Json.Get(mon, "loot") is double lt ? lt : 1).ToString("0.0", System.Globalization.CultureInfo.InvariantCulture)), "#b8ab92", 11, false);
            var hc = Json.Get(s, "hc");
            if (Json.Truthy(hc, "isHc")) text(Json.Truthy(hc, "allow") ? Loc.T("Hardcore: a defeat here may end your Hardcore run.") : Loc.T("Hardcore characters cannot enter the Marches: a Hardcore life is not staked in open PvP."), "#ff5a5a", 12, false);
            text(Loc.T("The Cinder Shrine"), Eu.Gold, 13, true);
            var contest = Json.Get(s, "contest");
            text(PvpZoneView.ContestLine(contest, Json.Number(contest, "left"), out string cc), cc, 12, false);
            text(PvpZoneView.HolderLine(contest, out string hcol), hcol, 12, false);
            text(Loc.T("Every {0} the Shrine Warden rises. Slay it, then hold the circle with your faction: the holder's faction gets +{1}% experience and +{2}% loot everywhere for {3} minutes.",
                Eg.SpanHours((Json.Get(s, "everyMinutes") is double em ? em : 120) * 60), Json.Int(Json.Get(s, "buff"), "exp"), Json.Int(Json.Get(s, "buff"), "loot"), Json.Get(s, "holdMinutes") is double hm ? (int)hm : 60), Eu.Dim, 11, false);
            text(Loc.T("Your pledge"), Eu.Gold, 13, true);
            text(Loc.T("Defeating a player pledged to another faction gives {0} reputation (the sworn rival full, the others half), at most {1} a day (today {2}). Unpledged players earn no reputation and cannot take the shrine.",
                Json.Int(s, "repPerKill"), Json.Int(s, "repDailyCap"), Json.Int(s, "repToday")), Eu.Dim, 11, false);
            foreach (object f in Eg.Objects(s, "factions"))
            {
                string name = PvpZoneView.FactionRow(f, s, out string btn, out bool can, out string tip);
                var rc = new Rect(x, y, w, 40);
                if (!measureOnly)
                {
                    Eu.Panel(rc, 0.06f);
                    Eu.Label(app, new Rect(rc.x + 6, rc.y + 3, rc.width - 140, 18), name, Eg.Hex(Json.Text(f, "color"), Eu.Gold), 13, true);
                    Eu.Label(app, new Rect(rc.x + 6, rc.y + 22, rc.width - 140, 16), tip, Eu.Dim, 11);
                    if (Eu.Button(new Rect(rc.xMax - 124, rc.y + 7, 118, 26), Loc.T(btn), can)) z.Pledge(Json.Text(f, "key"));
                }
                y += 43;
            }
            text(Loc.T("Embers vendor"), Eu.Gold, 13, true);
            text(Loc.T("Banked: {0} embers   Carried: {1} / {2}", Eg.Number(Json.Number(s, "banked")), Eg.Number(Json.Number(s, "carried")), Eg.Number(Json.Number(s, "carryMax"))), Eu.Bright, 12, false);
            foreach (object o in Eg.Objects(s, "vendor"))
            {
                string sub = PvpZoneView.VendorRow(o, Json.Number(s, "banked"), out string btn, out bool can);
                var rc = new Rect(x, y, w, 40);
                if (!measureOnly)
                {
                    Eu.Panel(rc, 0.06f);
                    if (Json.Text(o, "kind") == "item" && Json.Get(o, "id") is double id) app.DrawItem(new Rect(rc.x + 4, rc.y + 4, 32, 32), (ushort)id, 1);
                    Eu.Label(app, new Rect(rc.x + 42, rc.y + 3, rc.width - 180, 18), Json.Text(o, "name"), Eu.Text, 13, true);
                    Eu.Label(app, new Rect(rc.x + 42, rc.y + 22, rc.width - 180, 16), Loc.T(sub), Eu.Dim, 11);
                    if (Eu.Button(new Rect(rc.xMax - 130, rc.y + 7, 124, 26), btn == "Owned" ? Loc.T("Owned") : btn, can)) z.Buy(Json.Text(o, "key"));
                }
                y += 43;
            }
            text(Loc.T("Record"), Eu.Gold, 13, true);
            text(PvpZoneView.RecordLine(s), Eu.Dim, 11, false);
            return y + 6;
        }
    }

    /// <summary>The rules and the confirmation before entering the Marches.</summary>
    public sealed class PvpZoneConfirmWindow : EgHudWindow
    {
        bool accept, hcAccept;
        Vector2 scroll;
        const float BarH = 32f;   // the Enter and Cancel buttons stay in view whatever the rules text takes
        public override string Title => Loc.T("Enter the Marches");
        // phase 12, track H: at most the screen, however many rules the server sends (the text and the ticks scroll, the buttons do not)
        protected override Rect Place(float w, float h) => new Rect(Mathf.Max(8, w / 2 - 250), 110, Mathf.Min(500, w - 16), Mathf.Min(380, h - 118));
        protected override bool Wanted(ChaosApp app) => app.Session.Endgame.PvpZone.ConfirmAsked;
        public override bool RaiseWhenShown => true;   // pvpzone.lua: confirm:show() raise() focus(), over the Marches window that opens with it
        public override void Reset() { base.Reset(); accept = hcAccept = false; scroll = Vector2.zero; }

        protected override void Body(ChaosApp app, Rect inner)
        {
            var z = app.Session?.Endgame?.PvpZone;
            if (z == null) return;
            var hc = Json.Get(z.State, "hc");
            bool showHc = Json.Truthy(hc, "isHc") && Json.Truthy(hc, "allow");
            var view = new Rect(inner.x + 2, inner.y + 2, inner.width - 4, WindowFit.ViewHeight(inner.height - 2, BarH, 4));
            float tw = view.width - 24;
            string risk = PvpZoneView.RiskText(z.State);
            float textH = string.IsNullOrEmpty(risk) ? 0f : Eu.Height(app, risk, tw, 12) + 3;
            float content = 4 + textH + 6 + 24 + (showHc ? 24 : 0);
            scroll = GUI.BeginScrollView(view, scroll, new Rect(0, 0, view.width - 18, WindowFit.ScrollContent(content, view.height)));
            float y = 4;
            y += Eu.Wrap(app, 4, y, tw, risk, Eu.Text, 12);
            y += 6;
            accept = GUI.Toggle(new Rect(4, y, tw, 22), accept, " " + Loc.T("I understand the risk."));
            y += 24;
            if (showHc) hcAccept = GUI.Toggle(new Rect(4, y, tw, 22), hcAccept, " " + Loc.T("I accept that a defeat may end my Hardcore run."));
            GUI.EndScrollView();
            float x = inner.x + 6, w = inner.width - 12, by = inner.yMax - BarH + 2;
            bool ok = PvpZoneView.CanConfirm(z.State, accept, hcAccept) && Json.Truthy(z.State, "canEnter", true);
            if (Eu.Button(new Rect(x, by, w / 2 - 4, 28), Loc.T("Enter"), ok)) { z.Enter(accept, hcAccept); accept = hcAccept = false; }
            if (GUI.Button(new Rect(x + w / 2 + 4, by, w / 2 - 4, 28), Loc.T("Cancel"))) { z.CancelConfirm(); accept = hcAccept = false; }
        }
    }

    public sealed class PvpZoneHudWindow : EgHudWindow
    {
        public override string Title => Loc.T("Scorched Marches");
        protected override Rect Place(float w, float h) => new Rect(8, 108, 300, 200);
        protected override bool Wanted(ChaosApp app) => app.Session.Endgame.PvpZone.Inside;

        protected override void Body(ChaosApp app, Rect inner)
        {
            var z = app.Session?.Endgame?.PvpZone;
            if (z == null || z.Hud == null) return;
            var d = z.Hud;
            double el = z.HudElapsed(app.Session.Now);
            float x = inner.x + 6, w = inner.width - 12, y = inner.y + 2;
            double pct = PvpZoneView.CarryPercent(d, out string bc);
            Eu.Bar(app, new Rect(x, y, w, 16), pct, bc, PvpZoneView.EmbersLine(d));
            y += 20;
            string pl = PvpZoneView.PledgeLine(Json.Get(d, "pledge"), out string pc);
            Eu.Label(app, new Rect(x, y, w, 16), pl, pc, 12, true);
            y += 17;
            var contest = Json.Get(d, "contest");
            string cl = PvpZoneView.ContestLine(contest, Math.Max(0, Json.Number(contest, "left") - el), out string cc);
            Eu.Label(app, new Rect(x, y, w, 16), cl, cc, 11);
            y += 16;
            string hl = PvpZoneView.HolderLine(contest, out string hcol);
            Eu.Label(app, new Rect(x, y, w, 16), hl, hcol, 11);
            y += 16;
            string st = PvpZoneView.StatusLine(d, Math.Max(0, Json.Number(d, "protect") - el), out string sc);
            Eu.Label(app, new Rect(x, y, w, 16), st, sc, 11, true);
            y += 20;
            string exitWhere = null, shrineWhere = null;
            var me = app.World?.Player;
            if (me != null)
            {
                PvpZoneView.Nearest(z.Marks, "exit", me.Position.X, me.Position.Y, me.Position.Z, out exitWhere);
                PvpZoneView.Nearest(z.Marks, "shrine", me.Position.X, me.Position.Y, me.Position.Z, out shrineWhere);
            }
            foreach (var l in PvpZoneView.GoalLines(d, exitWhere, shrineWhere)) y += Eu.Wrap(app, x, y, w, l.Key, l.Value, 11);
        }
    }

    // ================================================================================================ Bounty board
    public sealed class BountyWindow : GameWindow
    {
        bool lastVisible;
        Vector2 scroll;
        public override string Title => Loc.T("Bounty Board");
        protected override Rect Place(float w, float h) => new Rect(w / 2 - 330, 50, 660, 520);
        public override void Reset() { lastVisible = false; Open = false; }

        public override void Tick(ChaosApp app)
        {
            var b = app.Session?.Endgame?.Bounty;
            if (b == null) return;
            WindowSync.Run(ref lastVisible, this, b.Visible, b.Show, b.Hide);
            if (b.WantsRefresh(app.Session.Now)) b.Refresh();
        }

        protected override void Body(ChaosApp app, Rect inner)
        {
            var b = app.Session?.Endgame?.Bounty;
            if (b == null) return;
            double now = app.Session.Now;
            float x = inner.x + 4, w = inner.width - 8, y = inner.y + 2;
            if (!b.HasBoard) { Eu.Label(app, new Rect(x, y, w, 20), Loc.T("Asking the server..."), Eu.Dim, 12); return; }
            Eu.Label(app, new Rect(x, y, w * 0.4f, 18), b.ActiveText(), Eu.Text, 12, true);
            Eu.Label(app, new Rect(x + w * 0.4f, y, w * 0.3f, 18), b.WeekText(), Eu.Bright, 12, false, TextAnchor.UpperCenter);
            Eu.Label(app, new Rect(x + w * 0.7f, y, w * 0.3f, 18), Loc.T("New contracts in {0}", BountyView.FormatTime(b.NextLeft(now))), Eu.Dim, 12, false, TextAnchor.UpperRight);
            y += 24;
            float tx = x;
            foreach (var band in b.Bands)
            {
                bool on = band == b.Current;
                var tab = new Rect(tx, y, 96, 24);
                if (GUI.Toggle(tab, on, band.Label.Length > 0 ? band.Label : Loc.T("Band {0}", band.Index), GUI.skin.button) && !on) b.SelectBand(band);
                tx += 100;
            }
            y += 30;
            var cur = b.Current;
            var view = new Rect(x, y, w, inner.yMax - y - 2);
            int rowH = 74;
            int n = cur != null ? cur.Contracts.Count : 0;
            scroll = GUI.BeginScrollView(view, scroll, new Rect(0, 0, view.width - 18, Mathf.Max(view.height, n * rowH)));
            if (n == 0) Eu.Label(app, new Rect(4, 4, view.width - 24, 20), Loc.T("No contracts in this band."), Eu.Dim, 12);
            for (int i = 0; i < n; i++)
            {
                var c = cur.Contracts[i];
                var r = new Rect(0, i * rowH, view.width - 20, rowH - 4);
                Eu.Panel(r, 0.06f);
                // the creature of the contract (game_bounty row.creature): its outfit with the colours the server sent
                var look = OutfitJson.Read(c.Outfit, c.Look);
                if (look != null) app.DrawOutfit(new Rect(r.x + 4, r.y + 8, 56, 56), look);
                Eu.Label(app, new Rect(r.x + 62, r.y + 3, 50, 14), BountyView.KindText(c.Type), BountyView.KindColor(c.Type), 10, true);
                string tc = BountyView.TierColor(c.Tier);
                Eu.Label(app, new Rect(r.x + 114, r.y + 2, r.width - 276, 18), c.Name + (c.Level > 0 ? "  (" + c.Level + ")" : ""), c.Type == "elite" && tc != null ? tc : Eu.Text, 14, true);
                Eu.Label(app, new Rect(r.x + 62, r.y + 22, r.width - 246, 16), BountyView.TaskText(c), Eu.Text, 12);
                string reward = BountyView.RewardText(c.Reward, out _);
                Eu.Label(app, new Rect(r.x + 62, r.y + 40, r.width - 246, 16), Loc.T("Reward:") + " " + reward, Eu.Bright, 11);
                if (c.State != "open")
                    Eu.Bar(app, new Rect(r.x + 62, r.y + 57, r.width - 246, 12), Mathf.Floor(c.Progress * 100f / Mathf.Max(1, c.Count)), c.State == "done" ? "#2f7a2a" : "#8a1010", Fmt.Short(c.Progress) + " / " + Fmt.Short(c.Count), 10);
                var ab = new Rect(r.xMax - 170, r.y + 8, 160, 26);
                if (c.State == "open") { if (Eu.Button(ab, Loc.T("Accept"), !b.Full)) b.Accept(c.Key); }
                else if (c.State == "active")
                {
                    if (GUI.Button(ab, Loc.T("Abandon"))) b.Abandon(c.Key);
                    if (b.Rerolls > 0 && GUI.Button(new Rect(ab.x, ab.y + 30, ab.width, 24), Loc.T("Reroll ({0})", b.Rerolls))) b.Reroll(c.Key);
                }
                else Eu.Button(ab, Loc.T("Completed"), false);
            }
            GUI.EndScrollView();
        }
    }
}
