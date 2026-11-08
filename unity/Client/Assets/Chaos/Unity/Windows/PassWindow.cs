// Season Pass (opcode 227, Core/CollectPass.cs): the tier track (free and premium rewards, claim), the daily and weekly challenges, the packs page (buy, upgrade, gift).
// Reached from the top menu (Adventure) or opened by the server.
using System.Collections.Generic;
using Chaos.Core;
using UnityEngine;

namespace Chaos.Client
{
    public sealed class PassWindow : ModelWindow
    {
        public override string Title => Loc.T("Season Pass");
        protected override Rect Place(float w, float h) => new Rect(w / 2 - 320, 50, 640, 560);

        Vector2 tierScroll, chalScroll, offerScroll;
        bool scrolled, giftAsk;
        string giftName = "";
        Dictionary<string, object> giftOffer;
        int page;

        protected override bool ModelVisible(ChaosApp app) => app.Session.Pass.Visible;
        protected override void ModelShow(ChaosApp app) => app.Session.Pass.Show();
        protected override void ModelHide(ChaosApp app) { app.Session.Pass.Hide(); giftAsk = false; }

        protected override void Body(ChaosApp app, Rect inner)
        {
            var p = app.Session?.Pass;
            if (p == null) return;
            double now = app.Session.Now;
            if (p.State == null) { GUI.Label(new Rect(inner.x + 8, inner.y + 8, 300, 22), Loc.T("Loading..."), app.SmallStyle); return; }
            var season = p.Season;
            GUI.Label(new Rect(inner.x + 6, inner.y, inner.width - 200, 22), p.Title(), app.TitleStyle);
            GUI.Label(new Rect(inner.xMax - 260, inner.y + 2, 256, 20), p.TimerText(now), new GUIStyle(app.SmallStyle) { alignment = TextAnchor.UpperRight });
            if (season == null) { GUI.Label(new Rect(inner.x + 8, inner.y + 40, inner.width - 16, 40), Loc.T("No season pass is running."), app.SmallStyle); return; }
            float y = inner.y + 26;
            GUI.Label(new Rect(inner.x + 6, y, 120, 20), Loc.T("Tier {0} / {1}", p.Tier, p.MaxTier), app.SmallStyle);
            CU.Label(app, new Rect(inner.x + 130, y, 120, 20), p.HasPremium ? Loc.T("Premium track") : Loc.T("Free track"), p.HasPremium ? "#ff9a3c" : "#8c8070", false);
            int pct = PassState.Progress(p.State, out string text);
            CU.Bar(app, new Rect(inner.x + 250, y + 2, inner.width - 400, 16), pct, text, new Color(0.7f, 0.45f, 0.1f));
            int n = PassState.ClaimableCount(p.State);
            if (CU.Button(new Rect(inner.xMax - 146, y, 142, 22), n > 0 ? Loc.T("Claim all ({0})", n) : Loc.T("Claim all"), n > 0)) p.ClaimAll();
            y += 28;
            page = CU.Tabs(new Rect(inner.x + 4, y, 300, 24), new[] { Loc.T("Rewards"), Loc.T("Challenges"), Loc.T("Packs") }, page);
            y += 30;
            var body = new Rect(inner.x, y, inner.width, inner.yMax - y - 24);
            if (page == 0) Tiers(app, p, body); else if (page == 1) Challenges(app, p, body, now); else Packs(app, p, body);
            string hint = p.Notice.Length > 0 && now - p.NoticeAt < 6000 ? p.Notice : Loc.T("Claim rewards as you reach each tier.");
            CU.Label(app, new Rect(inner.x + 6, inner.yMax - 22, inner.width - 12, 20), hint, p.Notice.Length > 0 && now - p.NoticeAt < 6000 ? "#f6cf72" : "#8c8070", false);
            CU.Tooltip(app, new Rect(0, 0, Area.width, Area.height));

            if (p.ConfirmText != null)
            {
                bool yes = CU.Ask(app, inner, p.ConfirmText, Loc.T("Yes"), Loc.T("No"), out bool answered);
                if (answered) { if (yes) p.Confirm(); else p.CancelConfirm(); }
            }
            else if (giftAsk)
            {
                var box = new Rect(inner.x + 60, inner.y + inner.height / 2 - 50, inner.width - 120, 100);
                ChaosApp.Fill(box, new Color(0.08f, 0.06f, 0.1f, 0.98f));
                GUI.Label(new Rect(box.x + 8, box.y + 6, box.width - 16, 20), Loc.T("Gift {0}", CF.T(giftOffer, "name")) + "  -  " + Loc.T("Character name:"), app.SmallStyle);
                giftName = CU.Field(app, new Rect(box.x + 8, box.y + 30, box.width - 16, 24), "passGift", giftName, 30);
                if (GUI.Button(new Rect(box.x + 8, box.y + 64, 100, 26), Loc.T("Ok"))) { p.AskGift(giftOffer, giftName); giftAsk = false; }
                if (GUI.Button(new Rect(box.xMax - 108, box.y + 64, 100, 26), Loc.T("Cancel"))) giftAsk = false;
            }
        }

        void Tiers(ChaosApp app, PassState p, Rect body)
        {
            var t = p.Tiers;
            if (t == null || !t.Complete) { GUI.Label(new Rect(body.x + 8, body.y + 4, 300, 22), Loc.T("Loading..."), app.SmallStyle); return; }
            float rowH = 54f;
            GUI.Label(new Rect(body.x + 60, body.y, 250, 18), Loc.T("Free"), app.SmallStyle);
            GUI.Label(new Rect(body.x + 60 + body.width / 2 - 20, body.y, 250, 18), Loc.T("Premium"), app.SmallStyle);
            var view = new Rect(body.x + 4, body.y + 20, body.width - 8, body.height - 20);
            if (!scrolled && p.ScrollToCurrent) { tierScroll = new Vector2(0, Mathf.Max(0, Mathf.Min(p.Tier, t.Total - 1) * rowH - 40)); scrolled = true; p.ScrollToCurrent = false; }
            tierScroll = CU.Rows(view, tierScroll, t.Total, rowH, (i, r) =>
            {
                int tier = i + 1;
                t.Rows.TryGetValue(tier, out var row);
                bool reached = tier <= p.Tier;
                var ts = new GUIStyle(app.TitleStyle);
                ts.normal.textColor = reached ? new Color(0.96f, 0.81f, 0.45f) : new Color(0.55f, 0.5f, 0.44f);
                GUI.Label(new Rect(r.x + 2, r.y + 14, 40, 22), tier.ToString(), ts);
                float half = (r.width - 50) / 2f;
                Cell(app, p, new Rect(r.x + 44, r.y, half - 4, r.height), CF.G(row, "free"), tier, PassState.Free);
                Cell(app, p, new Rect(r.x + 44 + half, r.y, half - 4, r.height), CF.G(row, "premium"), tier, PassState.Premium);
            });
        }

        void Cell(ChaosApp app, PassState p, Rect r, object reward, int tier, int track)
        {
            string st = PassState.CellState(p.State, tier, track);
            ChaosApp.Fill(r, st == "claimable" ? new Color(0.25f, 0.2f, 0.07f, 1f) : new Color(1f, 1f, 1f, 0.04f));
            if (!(reward is Dictionary<string, object>)) return;
            var pic = new Rect(r.x + 4, r.y + 8, 38, 38);
            ChaosApp.Fill(pic, new Color(0.11f, 0.09f, 0.12f, 1f));
            if (CF.I(reward, "item") > 0) app.DrawItem(pic, (ushort)CF.I(reward, "item"), Mathf.Max(1, CF.I(reward, "count")));
            else if (CF.I(reward, "look") > 0) app.DrawOutfit(pic, new Outfit(CF.I(reward, "look"), 78, 94, 114, 0, CF.I(reward, "addons")));
            else { var gs = new GUIStyle(app.SmallStyle) { alignment = TextAnchor.MiddleCenter }; gs.normal.textColor = CU.Hex(CF.G(reward, "color") as string, Color.white); GUI.Label(pic, Glyph(CF.T(reward, "kind")), gs); }
            string tip = st == "premium" ? Loc.T("Premium track: unlock it on the Packs page.") : st == "locked" ? Loc.T("Reach tier {0} first.", tier) : st == "closed" ? Loc.T("The claim window of this season is over.") : null;
            var color = st == "claimed" ? "#6b8f5a" : st == "claimable" ? "#f6cf72" : st == "closed" ? "#6b6258" : "#8c8070";
            CU.Label(app, new Rect(pic.xMax + 6, r.y + 4, r.width - 140, r.height - 8), CF.T(reward, "text"), color);
            if (tip != null) GUI.Label(r, new GUIContent("", tip));
            if (st == "claimable" || st == "claimed")
                if (CU.Button(new Rect(r.xMax - 84, r.y + 14, 78, 26), st == "claimed" ? Loc.T("Got it") : Loc.T("Claim"), st == "claimable")) p.Claim(tier, track);
        }

        static string Glyph(string kind) => kind == "title" ? "T" : kind == "portal" ? "P" : kind == "frame" ? "F" : kind == "shader" ? "S" : "?";

        void Challenges(ChaosApp app, PassState p, Rect body, double now)
        {
            if (CF.G(p.State, "daily") == null) { GUI.Label(new Rect(body.x + 8, body.y + 4, body.width - 16, 40), Loc.T("Challenges start with the season."), CU.Wrap(app)); return; }
            var all = new List<KeyValuePair<string, object>>();
            all.Add(new KeyValuePair<string, object>(p.DailyTitle(now), null));
            foreach (var c in CF.Rows(CF.G(CF.G(p.State, "daily"), "list"))) all.Add(new KeyValuePair<string, object>(null, c));
            all.Add(new KeyValuePair<string, object>(p.WeeklyTitle(now), null));
            foreach (var c in CF.Rows(CF.G(CF.G(p.State, "weekly"), "list"))) all.Add(new KeyValuePair<string, object>(null, c));
            all.Add(new KeyValuePair<string, object>(Loc.T("Daily XP sources"), null));
            var sources = new List<string>();
            foreach (var s in CF.Rows(CF.G(p.State, "sources"))) sources.Add(PassState.SourceLine(s));
            all.Add(new KeyValuePair<string, object>(string.Join("    ", sources), "src"));
            chalScroll = CU.Rows(new Rect(body.x + 4, body.y, body.width - 8, body.height), chalScroll, all.Count, 30, (i, r) =>
            {
                var kv = all[i];
                if (kv.Value == null) { GUI.Label(r, kv.Key, app.TitleStyle); return; }
                if (kv.Value is string) { GUI.Label(r, kv.Key, app.SmallStyle); return; }
                string text = PassState.Challenge(kv.Value, out string prog, out int pct, out bool done);
                ChaosApp.Fill(r, new Color(1f, 1f, 1f, 0.04f));
                CU.Label(app, new Rect(r.x + 4, r.y + 2, r.width * 0.5f, 22), text, done ? "#6b8f5a" : null, false);
                CU.Bar(app, new Rect(r.x + r.width * 0.5f, r.y + 6, r.width * 0.3f, 14), pct, prog, new Color(0.45f, 0.1f, 0.1f));
                GUI.Label(new Rect(r.xMax - 70, r.y + 2, 66, 22), Loc.T("+{0} XP", CF.I(kv.Value, "xp")), app.SmallStyle);
            });
        }

        void Packs(ChaosApp app, PassState p, Rect body)
        {
            GUI.Label(new Rect(body.x + 6, body.y, 300, 20), Loc.T("Your Chaos Coins: {0}", CF.I(p.State, "coins")), app.SmallStyle);
            var frame = CF.G(p.State, "frame") as Dictionary<string, object>;
            if (frame != null)
            {
                bool on = GUI.Toggle(new Rect(body.xMax - 260, body.y, 256, 20), CF.B(frame, "on"), Loc.T("Show {0}", CF.T(frame, "name")), GUI.skin.toggle);
                if (on != CF.B(frame, "on")) p.SetFrame(on);
            }
            var offers = CF.Rows(CF.G(p.State, "offers"));
            bool activeSeason = p.SeasonStatus == "active";
            offerScroll = CU.Rows(new Rect(body.x + 4, body.y + 24, body.width - 8, body.height - 24), offerScroll, offers.Count, 70, (i, r) =>
            {
                var o = offers[i];
                ChaosApp.Fill(r, new Color(1f, 1f, 1f, 0.04f));
                var pic = new Rect(r.x + 4, r.y + 4, 56, 56);
                if (CF.I(o, "look") > 0) app.DrawOutfit(pic, new Outfit(CF.I(o, "look"), 78, 94, 114, 0, 3));
                else if (CF.I(o, "item") > 0) app.DrawItem(pic, (ushort)CF.I(o, "item"), 1);
                GUI.Label(new Rect(r.x + 66, r.y + 2, r.width - 240, 18), CF.T(o, "name", "?"), app.TitleStyle);
                string contents = CF.G(o, "text") as string ?? string.Join(", ", CF.Values(CF.G(o, "contents")));
                string why = CF.T(o, "why");
                if (!CF.B(o, "owned") && why.Length > 0 && why != "Owned.") contents += "\n" + why;
                GUI.Label(new Rect(r.x + 66, r.y + 20, r.width - 240, 46), contents, CU.Wrap(app));
                string bt = PassState.OfferButton(o, out bool en);
                if (CU.Button(new Rect(r.xMax - 164, r.y + 8, 110, 26), bt, en)) p.AskBuy(o, CF.Long(CF.G(o, "price")), null);
                if (CU.Button(new Rect(r.xMax - 164, r.y + 38, 110, 24), Loc.T("Gift"), activeSeason)) { giftOffer = o; giftName = ""; giftAsk = true; }
            });
        }
    }
}
