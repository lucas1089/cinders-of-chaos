// Pets (opcode 254, Core/CollectPets.cs): the species you have and the ones you can still find, the chosen pet with its level, abilities, summon, dismiss and rename.
// The window asks the server again every 3 seconds while it is open. Top menu (Character).
using System.Collections.Generic;
using Chaos.Core;
using UnityEngine;

namespace Chaos.Client
{
    public sealed class PetsWindow : ModelWindow
    {
        public override string Title => Loc.T("Pets");
        protected override Rect Place(float w, float h) => new Rect(w / 2 - 300, 60, 600, 500);

        Vector2 listScroll, abilScroll;
        string renameText = "", renamedFor;

        protected override bool ModelVisible(ChaosApp app) => app.Session.Pets.Visible;
        protected override void ModelShow(ChaosApp app) => app.Session.Pets.Show();
        protected override void ModelHide(ChaosApp app) => app.Session.Pets.Hide();
        protected override void ModelTick(ChaosApp app) => app.Session.Pets.Tick(app.Session.Now);

        protected override void Body(ChaosApp app, Rect inner)
        {
            var p = app.Session?.Pets;
            if (p == null) return;
            if (p.State == null) { GUI.Label(new Rect(inner.x + 8, inner.y + 8, 300, 22), Loc.T("Loading..."), app.SmallStyle); return; }
            var entries = p.Entries();
            var left = new Rect(inner.x + 4, inner.y, 210, inner.height - 50);
            listScroll = CU.Rows(left, listScroll, entries.Count, 46, (i, r) =>
            {
                var e = entries[i];
                bool sel = e.Key == p.Selected;
                ChaosApp.Fill(r, sel ? new Color(0.35f, 0.25f, 0.1f, 1f) : new Color(1f, 1f, 1f, 0.04f));
                var prev = GUI.color;
                if (!e.Owned) GUI.color = new Color(1, 1, 1, 0.5f);
                if (e.Look > 0) app.DrawOutfit(new Rect(r.x + 3, r.y + 3, 38, 38), new Outfit(e.Look, 0, 0, 0, 0));
                GUI.color = prev;
                CU.Label(app, new Rect(r.x + 46, r.y + 3, r.width - 50, 20), e.Name, e.Owned ? null : "#8c8070", false);
                CU.Label(app, new Rect(r.x + 46, r.y + 23, r.width - 50, 20), p.RowSub(e), "#8c8070", false);
                if (Event.current.type == EventType.MouseDown && Event.current.button == 0 && r.Contains(Event.current.mousePosition)) { p.Selected = e.Key; Event.current.Use(); }
            });
            var sel2 = PetsState.Find(entries, p.Selected);
            var d = new Rect(left.xMax + 8, inner.y, inner.xMax - left.xMax - 12, inner.height - 50);
            if (sel2 != null) Detail(app, p, sel2, d);
            CU.Label(app, new Rect(inner.x + 6, inner.yMax - 44, inner.width - 12, 42), p.StatusText(), "#a89c86");
        }

        void Detail(ChaosApp app, PetsState p, PetEntry e, Rect d)
        {
            if (renamedFor != e.Key) { renamedFor = e.Key; renameText = ""; }
            ChaosApp.Fill(new Rect(d.x, d.y, 72, 72), new Color(0.11f, 0.09f, 0.12f, 1f));
            if (e.Look > 0) app.DrawOutfit(new Rect(d.x + 4, d.y + 4, 64, 64), new Outfit(e.Look, 0, 0, 0, 0));
            GUI.Label(new Rect(d.x + 80, d.y, d.width - 80, 22), p.TitleText(e), app.TitleStyle);
            string sp = e.Owned ? e.SpeciesName + (e.Pet != null && CF.G(e.Pet, "element") != null ? "  -  " + CF.T(e.Pet, "element") : "") : Loc.T("Not owned yet");
            GUI.Label(new Rect(d.x + 80, d.y + 24, d.width - 80, 20), sp, app.SmallStyle);
            if (e.Owned && e.Pet != null) CU.Bar(app, new Rect(d.x + 80, d.y + 48, d.width - 80, 16), CF.I(e.Pet, "pct"), PetsState.XpText(e.Pet), new Color(0.3f, 0.5f, 0.2f));
            var lines = p.AbilityLines(e);
            var view = new Rect(d.x, d.y + 80, d.width, d.height - 80 - 90);
            float h = 0;
            var st = CU.Wrap(app);
            var heights = new List<float>();
            foreach (var l in lines) { float lh = 18 + st.CalcHeight(new GUIContent(l.LockText != null ? l.Text + "  " + l.LockText : l.Text), view.width - 24) + 4; heights.Add(lh); h += lh; }
            abilScroll = GUI.BeginScrollView(view, abilScroll, new Rect(0, 0, view.width - 18, Mathf.Max(view.height, h)));
            float y = 0;
            for (int i = 0; i < lines.Count; i++)
            {
                var l = lines[i];
                CU.Label(app, new Rect(0, y, view.width - 20, 18), l.Title, l.Locked ? "#8c8070" : "#e8b84a", false);
                CU.Label(app, new Rect(8, y + 18, view.width - 28, heights[i] - 18), l.LockText != null ? l.Text + "  " + l.LockText : l.Text, l.Locked ? "#6b6258" : null);
                y += heights[i];
            }
            GUI.EndScrollView();
            if (!e.Owned) CU.Label(app, new Rect(d.x, d.yMax - 86, d.width, 34), Loc.T("How to get it:") + " " + e.How, "#c8b89a");
            var b = p.Buttons(e);
            if (b.Rename)
            {
                renameText = CU.Field(app, new Rect(d.x, d.yMax - 52, d.width - 100, 24), "petRename", renameText, 24);
                if (CU.Button(new Rect(d.xMax - 96, d.yMax - 52, 96, 24), Loc.T("Rename"), PetsState.CleanName(renameText) != null) || (Event.current.type == EventType.KeyDown && Event.current.keyCode == KeyCode.Return && GUI.GetNameOfFocusedControl() == "petRename"))
                    if (p.Rename(e.Key, renameText)) renameText = "";
            }
            if (CU.Button(new Rect(d.x, d.yMax - 24, 120, 24), Loc.T("Call out"), b.Summon)) p.Summon(e.Key);
            if (CU.Button(new Rect(d.x + 126, d.yMax - 24, 120, 24), Loc.T("Dismiss"), b.Dismiss)) p.Dismiss();
        }
    }
}
