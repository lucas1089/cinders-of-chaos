// The helper window's phase 7 track X parts: the "Follow and sell" tab (Follow a friend or the party leader, Auto sell through the Auto Seller, the
// exercise weapon) and the level-up notice with "Auto-update my spells" on the Shooter tab. Rules and engine glue: Core/Phase7XHelper.cs.
using Chaos.Core;
using UnityEngine;

namespace Chaos.Client
{
    public sealed partial class HelperWindow
    {
        LevelUpNotice noticeShown;
        string followEdit;

        /// <summary>The "Auto-update my spells" switch and, after a level-up with new spells, the question with Add and Ignore. Returns the height used.</summary>
        float DrawLevelUp(float x, float y, float w)
        {
            float used = 0f;
            var cfg = engine.Config;
            bool au = GUI.Toggle(new Rect(x, y, w, 22), cfg.AutoUpdateSpells, Loc.T("Auto-update my spells"));
            if (au != cfg.AutoUpdateSpells) { cfg.AutoUpdateSpells = au; dirty = true; }
            used += 24f;
            var n = engine.LevelNotice;
            if (n != null)
            {
                var box = new Rect(x, y + used, w, 74);
                ChaosApp.Fill(box, new Color(0.45f, 0.3f, 0.12f, 0.35f));
                GUI.Label(new Rect(box.x + 6, box.y + 2, box.width - 12, 36), Loc.T("New spell available: {0}.", n.List) + "\n" + Loc.T("Add to rotation?"), hint);
                if (GUI.Button(new Rect(box.x + 6, box.y + 42, 90, 26), Loc.T("Add")))
                {
                    int added = engine.AcceptLevelNotice();
                    message = added > 0 ? Loc.T("Added {0} spell(s) to the rotation.", added) : Loc.T("The five slots are in use: clear one first.");
                    dirty = true;
                }
                if (GUI.Button(new Rect(box.x + 102, box.y + 42, 90, 26), Loc.T("Ignore"))) { engine.IgnoreLevelNotice(); dirty = true; }
                used += 80f;
            }
            return used;
        }

        // ------------------------------------------------------------------------------------ the Follow and sell tab
        void DrawFollowSell(float x, float y, float w)
        {
            var cfg = engine.Config;
            var fo = cfg.Follow;
            GUI.Label(new Rect(x, y, w, 18), Loc.T("Follow"), rowName);
            y += 20;
            bool fe = GUI.Toggle(new Rect(x, y, 150, 24), fo.Enabled, Loc.T("Follow a player"));
            if (fe != fo.Enabled) { fo.Enabled = fe; dirty = true; }
            GUI.Label(new Rect(x + 152, y + 2, w - 152, 20), Loc.T(HelperTextsP7.FollowText(engine.FollowWhy)), new GUIStyle(hint) { alignment = TextAnchor.UpperRight });
            y += 28;
            if (GUI.Toggle(new Rect(x, y, w / 2 - 2, 24), fo.Mode == "name", Loc.T("A friend by name"), GUI.skin.button) && fo.Mode != "name") { fo.Mode = "name"; dirty = true; }
            if (GUI.Toggle(new Rect(x + w / 2 + 2, y, w / 2 - 2, 24), fo.Mode == "leader", Loc.T("The party leader"), GUI.skin.button) && fo.Mode != "leader") { fo.Mode = "leader"; dirty = true; }
            y += 28;
            if (fo.Mode == "name")
            {
                if (followEdit == null) followEdit = fo.Name;
                GUI.SetNextControlName("helperFollowName");
                string nt = GUI.TextField(new Rect(x, y, w, 24), followEdit, HelperAlly.NameMax);
                if (GUI.GetNameOfFocusedControl() == "helperFollowName") ui.MarkTextEditing();
                if (nt != followEdit)
                {
                    followEdit = nt;
                    fo.Name = HelperAlly.CleanName(nt) ?? "";
                    dirty = true;
                }
                y += 28;
            }
            GUI.Label(new Rect(x, y + 2, 120, 20), Loc.T("Distance"), rowName);
            fo.Distance = Stepper(new Rect(x + 120, y, 120, 24), fo.Distance, 1, HelperFollowCfg.DistanceMax, 1, Loc.T(" tiles"));
            y += 28;
            GUI.Label(new Rect(x, y, w, 44), Loc.T("Asks the server to walk you after the player. The fight systems pause while you follow. Not in a protection zone."), hint);
            y += 52;

            var se = cfg.Sell;
            GUI.Label(new Rect(x, y, w, 18), Loc.T("Auto sell"), rowName);
            y += 20;
            bool sen = GUI.Toggle(new Rect(x, y, 150, 24), se.Enabled, Loc.T("Sell my Loot Bag"));
            if (sen != se.Enabled) { se.Enabled = sen; dirty = true; }
            GUI.Label(new Rect(x + 152, y + 2, w - 152, 20), Loc.T(HelperTextsP7.SellText(engine.SellWhy)), new GUIStyle(hint) { alignment = TextAnchor.UpperRight });
            y += 28;
            GUI.Label(new Rect(x, y + 2, 120, 20), Loc.T("Every"), rowName);
            if (GUI.Button(new Rect(x + 120, y, 120, 24), Loc.T("{0} minutes", se.Interval)))
            {
                int i = System.Array.IndexOf(HelperSellCfg.Minutes, se.Interval);
                se.Interval = HelperSellCfg.Minutes[(i + 1) % HelperSellCfg.Minutes.Length];
                dirty = true;
            }
            y += 28;
            bool bc = GUI.Toggle(new Rect(x, y, 200, 24), se.BelowCap, Loc.T("Also when capacity is low"));
            if (bc != se.BelowCap) { se.BelowCap = bc; dirty = true; }
            se.Capacity = Stepper(new Rect(x + w - 150, y, 150, 24), se.Capacity, 0, HelperSellCfg.CapacityMax, 10, " oz");
            y += 28;
            GUI.Label(new Rect(x, y, w, 44), Loc.T("Only asks the Auto Seller; the server decides what is sold. Needs the Auto Seller (Store, Convenience) or an active Chaos Pact."), hint);
            y += 52;

            var ex = cfg.Exercise;
            GUI.Label(new Rect(x, y, w, 18), Loc.T("Exercise weapon"), rowName);
            y += 20;
            bool ee = GUI.Toggle(new Rect(x, y, 150, 24), ex.Enabled, Loc.T("Train on a dummy"));
            if (ee != ex.Enabled) { ex.Enabled = ee; dirty = true; }
            string wn = ex.Id == 0 ? Loc.T("Any exercise weapon I carry") : Loc.T(ExerciseName(ex.Id));
            if (GUI.Button(new Rect(x + 152, y, w - 152, 24), wn))
            {
                // any, then each of the eight in turn
                int at = -1;
                for (int i = 0; i < HelperExercise.Weapons.Length; i++) if (HelperExercise.Weapons[i].Key == ex.Id) at = i;
                ex.Id = at + 1 >= HelperExercise.Weapons.Length ? 0 : HelperExercise.Weapons[at + 1].Key;
                dirty = true;
            }
            y += 28;
            GUI.Label(new Rect(x, y, w, 44), Loc.T("In a protection zone, standing still for two seconds, uses the weapon on a training dummy within five tiles."), hint);
        }

        static string ExerciseName(int id)
        {
            foreach (var wp in HelperExercise.Weapons) if (wp.Key == id) return wp.Value;
            return "#" + id;
        }
    }
}
