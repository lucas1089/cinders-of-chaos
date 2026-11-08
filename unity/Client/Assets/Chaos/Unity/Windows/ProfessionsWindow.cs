// Professions (opcode 195, Core/CollectProfessions.cs) with the seven crafting skills of the skills packet (game_craftskills): gathering levels, the areas where nodes grow,
// the Material Broker's demand board (sell one material or all). Top menu (Economy); the broker NPC opens it.
using System.Collections.Generic;
using Chaos.Core;
using UnityEngine;

namespace Chaos.Client
{
    public sealed class ProfessionsWindow : ModelWindow
    {
        public override string Title => Loc.T("Professions");
        protected override Rect Place(float w, float h) => new Rect(w / 2 - 370, 40, 740, 600);

        Vector2 areaScroll, boardScroll;

        protected override bool ModelVisible(ChaosApp app) => app.Session.Professions.Visible;
        protected override void ModelShow(ChaosApp app) => app.Session.Professions.Show();
        protected override void ModelHide(ChaosApp app) => app.Session.Professions.Hide();

        protected override void Body(ChaosApp app, Rect inner)
        {
            var p = app.Session?.Professions;
            if (p == null) return;
            if (p.State == null) { GUI.Label(new Rect(inner.x + 8, inner.y + 8, 300, 22), Loc.T("Loading..."), app.SmallStyle); return; }
            GUI.Label(new Rect(inner.x + 6, inner.y, inner.width - 12, 20), p.BonusText(), app.SmallStyle);
            float y = inner.y + 24;
            // gathering professions
            var profs = p.ProfRows();
            var raw = CF.Rows(CF.G(p.State, "profs"));
            float cw = (inner.width - 8) / 2f;
            for (int i = 0; i < profs.Count; i++)
            {
                var r = profs[i];
                var cell = new Rect(inner.x + 4 + (i % 2) * cw, y + (i / 2) * 50, cw - 4, 46);
                ChaosApp.Fill(cell, new Color(1f, 1f, 1f, 0.04f));
                GUI.Label(new Rect(cell.x + 4, cell.y + 2, 150, 18), new GUIContent(r.Name, p.ProfTooltip(raw[i], r)), app.SmallStyle);
                GUI.Label(new Rect(cell.x + 150, cell.y + 2, 70, 18), Loc.T("Level {0}", r.Level), app.SmallStyle);
                CU.Label(app, new Rect(cell.x + 4, cell.y + 20, cell.width - 8, 14), r.TierText, r.TierColor, false);
                CU.Bar(app, new Rect(cell.x + 4, cell.y + 32, cell.width - 8, 12), r.Pct, r.XpText, new Color(0.35f, 0.65f, 0.3f));
            }
            y += ((profs.Count + 1) / 2) * 50 + 4;
            // the seven crafting skills
            GUI.Label(new Rect(inner.x + 6, y, 300, 20), Loc.T("Crafting skills"), app.TitleStyle);
            y += 22;
            var cs = app.Session.CraftSkills;
            float sw = (inner.width - 8) / 4f;
            for (int i = 0; i < cs.Length; i++)
            {
                var cell = new Rect(inner.x + 4 + (i % 4) * sw, y + (i / 4) * 36, sw - 4, 34);
                GUI.Label(new Rect(cell.x + 2, cell.y, cell.width - 40, 16), new GUIContent(Loc.T(CraftTableState.SkillNames[i]), CraftSkills.Tooltip(i, cs[i])), app.SmallStyle);
                var vs = new GUIStyle(app.SmallStyle) { alignment = TextAnchor.UpperRight };
                vs.normal.textColor = cs[i].Level > cs[i].Base ? new Color(0.27f, 0.68f, 0.15f) : new Color(0.75f, 0.75f, 0.75f);
                GUI.Label(new Rect(cell.xMax - 60, cell.y, 58, 16), CraftSkills.ShortLevel(cs[i].Level), vs);
                CU.Bar(app, new Rect(cell.x + 2, cell.y + 18, cell.width - 4, 8), cs[i].Percent, null, new Color(0.35f, 0.7f, 0.3f));
            }
            y += 78;
            // areas
            float split = inner.width * 0.4f;
            float avail = inner.yMax - y - 70;
            GUI.Label(new Rect(inner.x + 6, y, split, 20), Loc.T("Where to gather"), app.TitleStyle);
            var areas = p.AreaLines();
            areaScroll = CU.Rows(new Rect(inner.x + 4, y + 22, split - 6, avail - 22), areaScroll, areas.Count, 46, (i, r) =>
            {
                var a = areas[i];
                CU.Label(app, new Rect(r.x + 2, r.y, r.width - 4, 18), a.Title, a.Color, false);
                GUI.Label(new Rect(r.x + 2, r.y + 17, r.width - 4, 28), new GUIContent(a.Text, a.Tip), CU.Wrap(app));
            });
            // the board
            float bx = inner.x + split + 6;
            GUI.Label(new Rect(bx, y, 300, 20), Loc.T("Material Broker"), app.TitleStyle);
            var demand = p.DemandRows();
            boardScroll = CU.Rows(new Rect(bx, y + 22, inner.xMax - bx - 4, avail - 22), boardScroll, demand.Count, 40, (i, r) =>
            {
                var d = demand[i];
                ChaosApp.Fill(r, new Color(1f, 1f, 1f, 0.04f));
                if (d.ClientId > 0) app.DrawItem(new Rect(r.x + 3, r.y + 3, 32, 32), (ushort)d.ClientId, 1);
                string nm = d.Name.Length > 0 ? char.ToUpperInvariant(d.Name[0]) + d.Name.Substring(1) : d.Name;
                CU.Label(app, new Rect(r.x + 40, r.y + 1, r.width - 190, 18), nm, d.TierColor, false);
                GUI.Label(new Rect(r.x + 40, r.y + 19, r.width - 190, 18), Loc.T("{0} tier {1}, {2}", ProfessionsState.ProfName(p.State, d.Prof), d.Tier, d.HaveText), new GUIStyle(app.SmallStyle) { fontSize = Mathf.Min(10, app.SmallStyle.fontSize) });
                GUI.Label(new Rect(r.xMax - 150, r.y + 1, 80, 18), d.PriceText, app.SmallStyle);
                CU.Label(app, new Rect(r.xMax - 150, r.y + 19, 40, 18), d.MultText, d.MultColor, false);
                GUI.Label(new Rect(r.xMax - 110, r.y + 19, 50, 18), d.SoldText, new GUIStyle(app.SmallStyle) { fontSize = Mathf.Min(9, app.SmallStyle.fontSize) });
                string tip = d.CanSell ? Loc.T("Sell {0} for {1} gold", d.Units, ProfessionsState.FmtNum(d.Worth)) : p.AtBroker ? Loc.T("Nothing to sell, or the daily limit is reached") : Loc.T("Stand next to a Material Broker");
                if (CU.Button(new Rect(r.xMax - 56, r.y + 6, 54, 26), Loc.T("Sell"), d.CanSell, tip)) p.Sell(d.Id);
            });
            // footer
            float fy = inner.yMax - 66;
            CU.Label(app, new Rect(inner.x + 6, fy, inner.width - 200, 20), p.BrokerText(), p.AtBroker ? ProfessionsState.Good : ProfessionsState.Warn, false);
            p.SellAllEstimate(out int units, out double gold);
            if (CU.Button(new Rect(inner.xMax - 190, fy - 2, 186, 26), units > 0 ? Loc.T("Sell All ({0} gold)", ProfessionsState.FmtNum(gold)) : Loc.T("Sell All"), p.AtBroker && units > 0)) p.SellAll();
            CU.Label(app, new Rect(inner.x + 6, fy + 22, inner.width - 12, 20), p.StatusText, p.StatusColor, false);
            CU.Label(app, new Rect(inner.x + 6, fy + 42, inner.width - 12, 20), p.Footer(), "#8c8070", false);
            CU.Tooltip(app, new Rect(0, 0, Area.width, Area.height));
        }
    }
}
