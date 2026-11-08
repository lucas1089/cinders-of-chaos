// Cosmetics (opcode 225, Core/CollectCosmetics.cs): ten tabs of effects, colours and labels, the Collection with its score, the "only mine" filter (game_unlocks),
// use and preview. The wardrobe the server sends for the outfit lists is read by the same model (CosmeticsState.Wardrobe). Top menu (Character).
using System.Collections.Generic;
using System.Linq;
using Chaos.Core;
using UnityEngine;

namespace Chaos.Client
{
    public sealed class CosmeticsWindow : ModelWindow
    {
        public override string Title => Loc.T("Cosmetics");
        protected override Rect Place(float w, float h) => new Rect(w / 2 - 330, 50, 660, 540);

        Vector2 listScroll, descScroll;

        protected override bool ModelVisible(ChaosApp app) => app.Session.Cosmetics.Visible;
        protected override void ModelShow(ChaosApp app) => app.Session.Cosmetics.Show();
        protected override void ModelHide(ChaosApp app) => app.Session.Cosmetics.Hide();

        protected override void Body(ChaosApp app, Rect inner)
        {
            var c = app.Session?.Cosmetics;
            if (c == null) return;
            if (c.State == null) { GUI.Label(new Rect(inner.x + 8, inner.y + 8, 300, 22), Loc.T("Loading..."), app.SmallStyle); return; }
            var labels = CosmeticsLogic.Kinds.Select(k => Loc.T(k[1])).ToArray();
            int cur = System.Array.FindIndex(CosmeticsLogic.Kinds, k => k[0] == c.Tab);
            int tab = CU.Tabs(new Rect(inner.x + 4, inner.y, inner.width - 8, 24), labels, Mathf.Max(0, cur), 70);
            if (tab != cur) { c.SelectTab(CosmeticsLogic.Kinds[tab][0]); listScroll = Vector2.zero; }
            float y = inner.y + 54;
            var rows = c.TabRows();
            string sel = c.DefaultSelection();
            if (c.SelectedId == null) c.SelectedId = sel;
            var left = new Rect(inner.x + 4, y, 290, inner.height - 54 - 52);
            listScroll = CU.Rows(left, listScroll, rows.Count, 44, (i, r) =>
            {
                var row = rows[i];
                bool on = row.Id == c.SelectedId;
                bool locked = UnlocksCore.IsLocked(row) || row.OtherLine;
                var prev = GUI.color;
                if (locked) GUI.color = new Color(1, 1, 1, UnlocksCore.LockedOpacity + 0.3f);
                ChaosApp.Fill(r, on ? new Color(0.35f, 0.25f, 0.1f, 1f) : new Color(1f, 1f, 1f, 0.04f));
                string sw = row.Color ?? row.Accent;
                string iconPath = CosmeticIcons.Path(row);
                var icon = iconPath != null ? app.ArtTexture(iconPath) : null;
                if (icon != null) GUI.DrawTexture(new Rect(r.x + 4, r.y + 6, 30, 30), icon, ScaleMode.ScaleToFit, true);   // the effect icon (game_cosmetics images/fx), a footprint's print
                else if (sw != null && CosmeticsLogic.ValidColor(sw)) ChaosApp.Fill(new Rect(r.x + 4, r.y + 6, 30, 30), CU.Hex(sw, Color.white));
                else if (row.Item > 0) app.DrawItem(new Rect(r.x + 3, r.y + 5, 32, 32), (ushort)row.Item, 1);
                GUI.Label(new Rect(r.x + 40, r.y + 2, r.width - 44, 20), new GUIContent(row.Name + (row.Selected ? "  *" : ""), UnlocksCore.Tooltip(row) ?? ""), app.SmallStyle);
                CU.Label(app, new Rect(r.x + 40, r.y + 21, r.width - 44, 20), CosmeticsLogic.SubText(row), "#8c8070", false);
                GUI.color = prev;
                if (Event.current.type == EventType.MouseDown && Event.current.button == 0 && r.Contains(Event.current.mousePosition)) { c.SelectedId = row.Id; Event.current.Use(); }
            });

            // detail
            var d = new Rect(left.xMax + 8, y, inner.xMax - left.xMax - 12, left.height);
            var shown = rows.FirstOrDefault(r => r.Id == c.SelectedId);
            if (shown != null) Detail(app, c, shown, d);
            CU.Tooltip(app, new Rect(0, 0, Area.width, Area.height));

            // footer
            float fy = inner.yMax - 48;
            bool onlyMine = GUI.Toggle(new Rect(inner.x + 6, fy, 180, 20), c.OnlyMine(c.Tab), Loc.T("Only what I own"), GUI.skin.toggle);
            if (onlyMine != c.OnlyMine(c.Tab)) c.SetOnlyMine(c.Tab, onlyMine);
            string status = c.StatusText.Length > 0 && app.Session.Now - c.StatusAt < 4000 ? c.StatusText : c.StatusLine();
            CU.Label(app, new Rect(inner.x + 190, fy, inner.width - 196, 20), status, c.StatusText.Length > 0 && app.Session.Now - c.StatusAt < 4000 ? (c.StatusOk ? "#8cd08c" : "#e07060") : "#a89c86", false);
            string score = c.ScoreLine();
            if (score.Length > 0) GUI.Label(new Rect(inner.x + 6, fy + 22, inner.width - 12, 20), score, app.SmallStyle);
        }

        void Detail(ChaosApp app, CosmeticsState c, CosRow r, Rect d)
        {
            GUI.Label(new Rect(d.x, d.y, d.width, 22), r.Name + (r.Selected ? "  (" + Loc.T("in use") + ")" : ""), app.TitleStyle);
            var sample = new Rect(d.x, d.y + 26, d.width, 56);
            ChaosApp.Fill(sample, new Color(0.11f, 0.1f, 0.09f, 1f));
            if (r.Kind == "chatcolor" && CosmeticsLogic.ValidColor(r.Color))
                CU.Label(app, new Rect(sample.x + 6, sample.y + 18, sample.width - 12, 20), Loc.T("12:00 You [1]: Hail, ash-walkers!"), r.Color, false);
            else if (r.Kind == "lootbeam")
            {
                var bg = CosmeticsLogic.ValidColor(r.Accent) ? CU.Hex(r.Accent, Color.black) : new Color(0.06f, 0.05f, 0.05f, 0.94f);
                float x = sample.x + 4;
                foreach (var s in new[] { new[] { "Legendary", "#ffd040" }, new[] { "Magic", "#4a90ff" }, new[] { "Divine", "#c8e8ff" } })
                {
                    string t = Loc.T("{0} Ashen Blade", Loc.T(s[0]));
                    var br = new Rect(x, sample.y + 18, 100, 20);
                    ChaosApp.Fill(br, bg);
                    CU.Label(app, br, t, s[1], false, TextAnchor.MiddleCenter);
                    x += 104;
                }
            }
            else if (CosmeticIcons.Path(r) != null && app.ArtTexture(CosmeticIcons.Path(r)) is Texture2D big)
            {
                if (r.Kind == "footprint") { GUI.DrawTexture(new Rect(sample.center.x - 74, sample.y + 8, 40, 40), big, ScaleMode.ScaleToFit, true); GUI.DrawTexture(new Rect(sample.center.x + 34, sample.y + 8, 40, 40), big, ScaleMode.ScaleToFit, true); }
                else GUI.DrawTexture(new Rect(sample.center.x - 24, sample.y + 4, 48, 48), big, ScaleMode.ScaleToFit, true);
            }
            else if (r.Item > 0) app.DrawItem(new Rect(sample.center.x - 16, sample.y + 12, 32, 32), (ushort)r.Item, 1);
            else GUI.Label(new Rect(sample.x + 6, sample.y + 6, sample.width - 12, 46), Loc.T("Everyone near you sees the chosen effects."), CU.Wrap(app));
            string how = r.How ?? "";
            if (r.Id == "0") how = "";
            else if (r.Owned) how = r.Source == "store" ? Loc.T("Unlocked for your account") : Loc.T("Unlocked") + (how.Length > 0 ? " - " + how : "");
            descScroll = GUI.BeginScrollView(new Rect(d.x, d.y + 90, d.width, d.height - 90 - 80), descScroll, new Rect(0, 0, d.width - 18, 400));
            GUI.Label(new Rect(0, 0, d.width - 20, 280), (r.Desc ?? "") + (r.Collection && r.Use != null ? "\n" + r.Use : ""), CU.Wrap(app));
            GUI.EndScrollView();
            GUI.Label(new Rect(d.x, d.yMax - 78, d.width, 40), how, CU.Wrap(app));
            if (!r.Collection)
            {
                if (CU.Button(new Rect(d.x, d.yMax - 32, 100, 28), Loc.T("Use"), CosmeticsLogic.CanUse(r) && UnlocksCore.CanUse(r))) c.Select(r);
                // a spell skin or kill effect with its steps plays on the look preview's effect stage (phase 9, track E; cosmetics.lua previewOption)
                var playOpt = PreviewStage.FromPlayRow(r.Kind, r.Play);
                if ((r.Preview || CosmeticsLogic.Drawn(r.Kind) || playOpt != null) && CU.Button(new Rect(d.x + 106, d.yMax - 32, 100, 28), Loc.T("Preview"), !CosmeticsLogic.Drawn(r.Kind) || !string.IsNullOrEmpty(r.Art)))
                {
                    // an outline or a footprint is drawn on the character in the shared look preview, and so are the effects of a skin; the others the server plays round you
                    if (playOpt != null) app.ShowLookPreview(playOpt);
                    else if (CosmeticsLogic.Drawn(r.Kind)) app.ShowLookPreview(new PreviewOption { Kind = r.Kind, Art = r.Art, Pulse = r.Pulse > 0 });
                    else c.PreviewRow(r);
                }
            }
        }
    }
}
