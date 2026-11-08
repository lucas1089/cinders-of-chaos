// The community windows (SocialWindow.cs draws them; the models are in Core/Community.cs, CommunityGoal.cs, CommunityExtras.cs). None has a hotkey: the top menu opens them
// (Core/TopMenu.cs) or the server does (the survey at level 20 and 50, the Brazier, the pocket boss NPC, the mentor offer, the patch notes at the login).
using Chaos.Core;
using UnityEngine;

namespace Chaos.Client
{
    /// <summary>The admin panel: only in the menu once the server sent a catalog, which it does for staff accounts alone (the same gate as the main client).</summary>
    public sealed class AdminWindow : SocialWindow
    {
        bool available;
        public override string Title => Loc.T("Admin Panel");
        public override bool InMenu => available;
        protected override SocialPanel Panel(GameSession s) => s?.Community?.Admin;
        protected override Rect Place(float w, float h) => new Rect(Mathf.Max(8, w / 2 - 330), 50, Mathf.Min(660, w - 16), Mathf.Min(600, h - 60));
        public override void Tick(ChaosApp app) { base.Tick(app); available = app.Session?.Community?.Admin.HasCatalog == true; }
    }

    public sealed class BossSpawnsWindow : SocialWindow
    {
        public override string Title => Loc.T("Boss Spawns");
        public override string TravelKey => "pocketboss";
        protected override SocialPanel Panel(GameSession s) => s?.Community?.BossSpawns;
        protected override Rect Place(float w, float h) => new Rect(Mathf.Max(8, w / 2 - 320), 50, Mathf.Min(640, w - 16), Mathf.Min(600, h - 60));
    }

    /// <summary>The new player survey: opens by itself at level 20 and 50.</summary>
    public sealed class SurveyWindow : SocialWindow
    {
        public override string Title => Loc.T("A few questions");
        public override bool InMenu => false;
        protected override SocialPanel Panel(GameSession s) => s?.Community?.Survey;
        protected override Rect Place(float w, float h) => new Rect(Mathf.Max(8, w / 2 - 240), 90, Mathf.Min(480, w - 16), Mathf.Min(380, h - 100));
    }

    public sealed class NemesisWindow : SocialWindow
    {
        public override string Title => Loc.T("Nemesis");
        protected override SocialPanel Panel(GameSession s) => s?.Community?.Nemesis;
        protected override Rect Place(float w, float h) => new Rect(Mathf.Max(8, w / 2 - 220), 80, Mathf.Min(440, w - 16), Mathf.Min(420, h - 90));
    }

    public sealed class ReferralWindow : SocialWindow
    {
        public override string Title => Loc.T("Referral");
        protected override SocialPanel Panel(GameSession s) => s?.Community?.Referral;
        protected override Rect Place(float w, float h) => new Rect(Mathf.Max(8, w / 2 - 280), 60, Mathf.Min(560, w - 16), Mathf.Min(560, h - 70));
    }

    public sealed class CommunityGoalWindow : SocialWindow
    {
        public override string Title => Loc.T("Community");
        protected override SocialPanel Panel(GameSession s) => s?.Community?.Goal;
        protected override Rect Place(float w, float h) => new Rect(Mathf.Max(8, w / 2 - 290), 56, Mathf.Min(580, w - 16), Mathf.Min(600, h - 66));
    }

    public sealed class ChronicleWindow : SocialWindow
    {
        public override string Title => Loc.T("Chronicle");
        protected override SocialPanel Panel(GameSession s) => s?.Community?.Chronicle;
        protected override Rect Place(float w, float h) => new Rect(Mathf.Max(8, w / 2 - 300), 50, Mathf.Min(600, w - 16), Mathf.Min(620, h - 60));
    }

    public sealed class MentorWindow : SocialWindow
    {
        public override string Title => Loc.T("Mentors");
        protected override SocialPanel Panel(GameSession s) => s?.Community?.Mentor;
        protected override Rect Place(float w, float h) => new Rect(Mathf.Max(8, w / 2 - 310), 50, Mathf.Min(620, w - 16), Mathf.Min(620, h - 60));
    }

    public sealed class PatchNotesWindow : SocialWindow
    {
        public override string Title => Loc.T("Patch Notes");
        protected override SocialPanel Panel(GameSession s) => s?.Community?.PatchNotes;
        protected override Rect Place(float w, float h) => new Rect(Mathf.Max(8, w / 2 - 320), 46, Mathf.Min(640, w - 16), Mathf.Min(640, h - 56));
    }

    public sealed class DropFeedWindow : SocialWindow
    {
        public override string Title => Loc.T("Drop Feed");
        protected override SocialPanel Panel(GameSession s) => s?.Community?.DropFeed;
        protected override Rect Place(float w, float h) => new Rect(Mathf.Max(8, w / 2 - 210), 110, Mathf.Min(420, w - 16), Mathf.Min(170, h - 120));
    }

    public sealed class CreditsWindow : SocialWindow
    {
        public override string Title => Loc.T("Credits");
        protected override SocialPanel Panel(GameSession s) => s?.Community?.Credits;
        protected override Rect Place(float w, float h) => new Rect(Mathf.Max(8, w / 2 - 300), 50, Mathf.Min(600, w - 16), Mathf.Min(620, h - 60));
    }

    public sealed class StreamerWindow : SocialWindow
    {
        public override string Title => Loc.T("Streamer and cinema mode");
        protected override SocialPanel Panel(GameSession s) => s?.Community?.StreamerWindow;
        protected override Rect Place(float w, float h) => new Rect(Mathf.Max(8, w / 2 - 270), 80, Mathf.Min(540, w - 16), Mathf.Min(400, h - 90));
    }

    public sealed class PerfWindow : SocialWindow
    {
        public override string Title => Loc.T("Performance");
        protected override SocialPanel Panel(GameSession s) => s?.Community?.PerfWindow;
        protected override Rect Place(float w, float h) => new Rect(Mathf.Max(8, w - 380), 120, Mathf.Min(360, w - 16), Mathf.Min(360, h - 130));
    }

    public sealed class ShotsWindow : SocialWindow
    {
        public override string Title => Loc.T("Screenshots");
        protected override SocialPanel Panel(GameSession s) => s?.Community?.ShotsWindow;
        protected override Rect Place(float w, float h) => new Rect(Mathf.Max(8, w / 2 - 250), 90, Mathf.Min(500, w - 16), Mathf.Min(380, h - 100));
    }

    /// <summary>Customise Character: the large look preview with a checkbox per layer, the Equipped now strip, the categories, a search box and the card grid of one category (a click picks,
    /// a card under the pointer is previewed), Apply. Phase 8 track B; the rules are Core/Phase8B.cs ExtrasView and the panel's. The outfit, mount, wings, aura and shader cards and the colour
    /// palette tabs are in the Outfit window.</summary>
    public sealed class OutfitExtrasWindow : SocialWindow
    {
        public override string Title => Loc.T("Customise Character");
        protected override SocialPanel Panel(GameSession s) => s?.Community?.OutfitExtras;
        protected override Rect Place(float w, float h) => new Rect(Mathf.Max(8, w / 2 - 330), 60, Mathf.Min(660, w - 16), Mathf.Min(500, h - 70));

        string category = "outline", search = "";
        int facing = LookPreview.South;
        bool showMount = true, showWings = true, showAura = true, showShader = true;
        Vector2 cardScroll;

        public override void Reset() { base.Reset(); category = "outline"; search = ""; facing = LookPreview.South; cardScroll = Vector2.zero; }

        protected override void Body(ChaosApp app, Rect inner)
        {
            var p = Panel(app.Session) as OutfitExtrasPanel;
            if (p == null) return;
            var rows = p.Rows();
            var small = new GUIStyle(app.SmallStyle) { fontSize = 12, wordWrap = true };
            if (rows.Count == 0) { GUI.Label(new Rect(inner.x + 8, inner.y + 8, 300, 22), Loc.T("Loading..."), app.SmallStyle); return; }
            foreach (var row in rows)
                if (!p.Form.ContainsKey("x_" + row.Key)) p.Form["x_" + row.Key] = System.Math.Max(0, row.Options.FindIndex(o => o.Value == row.Current)).ToString();
            System.Func<string, int> chosen = k => p.Form.ContainsKey("x_" + k) ? p.Index("x_" + k) : -1;
            var cur = rows.Find(r => r.Key == category) ?? rows[0];
            category = cur.Key;
            var e = Event.current;
            var mouse = e.mousePosition;

            // left: the large look preview, the layer boxes and the Equipped now strip
            float lw = 196;
            var stage = new Rect(inner.x + 6, inner.y + 4, lw - 8, lw - 8);
            ChaosApp.Fill(stage, new Color(0.07f, 0.06f, 0.08f, 1f));
            var me = app.World?.Player;
            // the cards (right side) are laid out first so a hover is known when the preview is drawn
            float rx = inner.x + lw + 6, rw = inner.xMax - rx - 6;
            float cy = inner.y + 4;
            var cats = new string[rows.Count];
            for (int i = 0; i < rows.Count; i++) cats[i] = rows[i].Label;
            int ci = rows.IndexOf(cur);
            int ni = CU.Tabs(new Rect(rx, cy, rw, 24), cats, ci, 60);
            if (ni != ci) { category = rows[ni].Key; cur = rows[ni]; cardScroll = Vector2.zero; }
            cy += 28 * Mathf.Max(1, Mathf.CeilToInt(rows.Count * 74f / rw));
            GUI.Label(new Rect(rx, cy + 2, 52, 22), Loc.T("Search"), small);
            string ns = GUI.TextField(new Rect(rx + 54, cy, rw - 54 - 28, 22), search);
            if (ns != search) { search = ns; cardScroll = Vector2.zero; }
            if (GUI.GetNameOfFocusedControl() == "" && GUI.changed) app.MarkTextEditing();
            if (GUI.Button(new Rect(rx + rw - 24, cy, 24, 22), "x")) { search = ""; cardScroll = Vector2.zero; }
            if (new Rect(rx + 54, cy, rw - 54 - 28, 22).Contains(mouse)) app.MarkTextEditing();
            cy += 28;
            float gridH = inner.yMax - cy - 74;
            var shown = ExtrasView.Filter(cur, search);
            int per = Mathf.Max(1, Mathf.FloorToInt((rw - 18) / 128f));
            float cw = (rw - 18 - (per - 1) * 4) / per;
            var view = new Rect(rx, cy, rw, gridH);
            int hoverIdx = -1;
            cardScroll = GUI.BeginScrollView(view, cardScroll, new Rect(0, 0, rw - 18, Mathf.Max(gridH, Mathf.CeilToInt(shown.Count / (float)per) * 46f)));
            int pick = chosen(cur.Key);
            for (int n = 0; n < shown.Count; n++)
            {
                int oi = shown[n];
                var r = new Rect((n % per) * (cw + 4), (n / per) * 46f, cw, 42);
                bool on = oi == pick;
                ChaosApp.Fill(r, on ? new Color(0.35f, 0.25f, 0.1f, 1f) : new Color(1f, 1f, 1f, 0.05f));
                if (on) ItemSlots.Frame(r, "#e8b84a");
                var tex = cur.Options[oi].Row != null ? app.ArtTexture(CosmeticIcons.Path(cur.Options[oi].Row) ?? "") : null;
                float tx = r.x + 4;
                if (tex != null) { GUI.DrawTexture(new Rect(r.x + 4, r.y + 5, 32, 32), tex, ScaleMode.ScaleToFit, true); tx = r.x + 40; }
                GUI.Label(new Rect(tx, r.y + 2, r.xMax - tx - 2, 38), cur.Options[oi].Text, small);
                if (r.Contains(mouse)) { hoverIdx = oi; }
                if (e.type == EventType.MouseDown && e.button == 0 && r.Contains(mouse)) { p.Form["x_" + cur.Key] = oi.ToString(); e.Use(); }
            }
            GUI.EndScrollView();
            if (view.Contains(mouse) == false) hoverIdx = -1;
            if (cur.Locked > 0) GUI.Label(new Rect(rx, view.yMax + 2, rw, 20), Loc.T("{0} more not unlocked yet. See Character > Cosmetics and the Store.", cur.Locked), small);

            // the large preview: the chosen options, the hovered card in place of its row's
            var opt = ExtrasView.Bundle(rows, chosen, hoverIdx >= 0 ? cur.Key : null, hoverIdx);
            if (me != null)
            {
                app.DrawPreviewUnder(opt, stage);
                app.DrawOutfitFx(new Rect(stage.x + 12, stage.y + 12, stage.width - 24, stage.height - 24), ExtrasView.Layers(me.Outfit, showMount, showWings, showAura, showShader), false, (Dir)facing);
                app.DrawPreviewOver(opt, stage, me.Name);
            }
            float y = stage.yMax + 4;
            if (GUI.Button(new Rect(inner.x + 6, y, 30, 22), "<")) facing = LookPreview.Turn(facing, -1);
            if (GUI.Button(new Rect(inner.x + 40, y, 30, 22), ">")) facing = LookPreview.Turn(facing, 1);
            y += 26;
            showMount = GUI.Toggle(new Rect(inner.x + 6, y, 92, 20), showMount, Loc.T("Mount"));
            showWings = GUI.Toggle(new Rect(inner.x + 100, y, 92, 20), showWings, Loc.T("Wings"));
            y += 20;
            showAura = GUI.Toggle(new Rect(inner.x + 6, y, 92, 20), showAura, Loc.T("Aura"));
            showShader = GUI.Toggle(new Rect(inner.x + 100, y, 92, 20), showShader, Loc.T("Shader"));
            y += 24;
            // Equipped now: one line per row with the chosen option; a click shows its category
            GUI.Label(new Rect(inner.x + 6, y, lw, 18), Loc.T("Equipped now"), app.SmallStyle);
            y += 18;
            foreach (var row in rows)
            {
                var r = new Rect(inner.x + 6, y, lw - 8, 17);
                if (row.Key == category) ChaosApp.Fill(r, new Color(1f, 1f, 1f, 0.06f));
                GUI.Label(r, ExtrasView.Equipped(row, chosen(row.Key)), new GUIStyle(small) { fontSize = 11, wordWrap = false, clipping = TextClipping.Clip });
                if (e.type == EventType.MouseDown && e.button == 0 && r.Contains(mouse)) { category = row.Key; cardScroll = Vector2.zero; e.Use(); }
                y += 17;
                if (y > inner.yMax - 4) break;
            }

            // bottom right: Apply and the status
            if (p.Status.Length > 0)
            {
                var old = GUI.contentColor; GUI.contentColor = ToneColor(p.StatusTone);
                GUI.Label(new Rect(rx, inner.yMax - 44, rw - 110, 40), p.Status, small);
                GUI.contentColor = old;
            }
            if (GUI.Button(new Rect(inner.xMax - 108, inner.yMax - 30, 100, 26), Loc.T("Apply"))) p.Apply();
        }
    }
}
