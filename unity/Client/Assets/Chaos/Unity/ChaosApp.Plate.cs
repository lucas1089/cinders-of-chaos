// The character plate (client game_chaoshud): the player's outfit in a small frame, name, level, health and mana bars with
// numbers (right click: percent instead), and the experience line with the percent to the next level. All of it comes from
// the base 0xA0 stats packet and the player's outfit; the main client's plate uses no extended opcode either.
using Chaos.Core;
using UnityEngine;

namespace Chaos.Client
{
    public sealed partial class ChaosApp
    {
        bool plateAsPercent, plateChoiceLoaded, plateSmooth = true, plateDragging;
        Vector2 plateDragLast;
        string plateChoiceFor = "";
        readonly HudBarTrack plateHp = new HudBarTrack(), plateMp = new HudBarTrack();   // the eased bars (Core/HudBars.cs)

        void PlatePanel(float scale)
        {
            using var _slow = SlowCalls.Scope("PlatePanel", "OnGUI");
            var p = session?.Parser;
            var me = world?.Player;
            if (p == null) return;
            string name = me?.Name ?? "";
            // the percent choice is kept per character
            if (!plateChoiceLoaded || plateChoiceFor != name)
            {
                plateChoiceFor = name;
                plateChoiceLoaded = true;
                plateAsPercent = PlayerPrefs.GetInt("chaos.plate.percent." + name.ToLowerInvariant(), 0) == 1;
                plateSmooth = PlayerPrefs.GetInt("chaos.plate.smooth", 1) == 1;
                plateHp.Reset(); plateMp.Reset();   // another character: the first value is taken at once
            }
            double plateNow = session.Now;
            plateHp.Observe(HudBarTrack.Percent(p.Health, p.MaxHealth), plateNow);
            plateMp.Observe(HudBarTrack.Percent(p.Mana, p.MaxMana), plateNow);
            Rect box = StatusRect();
            uiRects.Add(Scaled(box, scale));
            Fill(box, new Color(0.04f, 0.03f, 0.05f, 0.8f));
            Fill(new Rect(box.x, box.y, 2, box.height), new Color(0.6f, 0.45f, 0.18f));
            // portrait in a gold ring
            var ring = new Rect(box.x + 8, box.y + 8, 44, 44);
            Fill(ring, new Color(0.6f, 0.45f, 0.18f));
            Fill(new Rect(ring.x + 2, ring.y + 2, ring.width - 4, ring.height - 4), new Color(0.08f, 0.06f, 0.09f));
            if (me != null) DrawOutfit(new Rect(ring.x + 4, ring.y + 4, ring.width - 8, ring.height - 8), me.Outfit);
            GUI.Label(new Rect(box.x + 58, box.y + 4, box.width - 64, 22), (name.Length > 0 ? name : "...") + "   " + Loc.T("Lv {0}", p.Level), titleStyle);
            var hp = new Rect(box.x + 58, box.y + 28, box.width - 66, 16);
            var mp = new Rect(box.x + 58, box.y + 46, box.width - 66, 16);
            PlateBar(hp, p.Health, p.MaxHealth, new Color(0.75f, 0.12f, 0.1f), plateHp, plateNow);
            PlateBar(mp, p.Mana, p.MaxMana, new Color(0.15f, 0.35f, 0.85f), plateMp, plateNow);
            PlateGrip(box);
            // experience: the server's percent (0xA0), text with what is missing
            int pct = Plate.LevelPercent(p.LevelPercent);
            var xp = new Rect(box.x + 8, box.y + 70, box.width - 16, 14);
            Fill(xp, new Color(0f, 0f, 0f, 0.9f));
            Fill(new Rect(xp.x + 1, xp.y + 1, (xp.width - 2) * pct / 100f, xp.height - 2), new Color(0.78f, 0.62f, 0.2f));
            var st = new GUIStyle(small) { alignment = TextAnchor.MiddleCenter, fontSize = 11 };
            st.normal.textColor = Color.white;
            string missing = p.Experience > 0 ? "  (" + Plate.Short(Plate.ExperienceToNext(p.Experience, p.Level)) + ")" : "";
            GUI.Label(xp, Loc.T("{0}% to level {1}", pct, p.Level + 1) + missing, st);
            var e = Event.current;
            if (e.type == EventType.MouseDown && e.button == 1 && (hp.Contains(e.mousePosition) || mp.Contains(e.mousePosition)))
            {
                // the bar menu of the main client's plate: numbers or percent, eased bars on or off
                string key = "chaos.plate.percent." + name.ToLowerInvariant();
                var items = new System.Collections.Generic.List<System.Collections.Generic.KeyValuePair<string, System.Action>>
                {
                    new System.Collections.Generic.KeyValuePair<string, System.Action>(plateAsPercent ? Loc.T("Show numbers") : Loc.T("Show percent"), () => { plateAsPercent = !plateAsPercent; PlayerPrefs.SetInt(key, plateAsPercent ? 1 : 0); }),
                    new System.Collections.Generic.KeyValuePair<string, System.Action>(plateSmooth ? Loc.T("Eased bars: on") : Loc.T("Eased bars: off"), () => { plateSmooth = !plateSmooth; PlayerPrefs.SetInt("chaos.plate.smooth", plateSmooth ? 1 : 0); }),
                };
                ShowMenu(MouseUi(), items);
                e.Use();
            }
        }

        /// <summary>The strip on top of the plate: drag it to move the plate (the saved place of the "status" HUD piece, as the layout edit mode keeps it), double click puts it back.</summary>
        void PlateGrip(Rect box)
        {
            var grip = new Rect(box.x + 2, box.y, box.width - 2, 6);
            var e = Event.current;
            bool over = grip.Contains(e.mousePosition) || plateDragging;
            if (e.type == EventType.Repaint)
            {
                Fill(grip, over ? new Color(0.6f, 0.45f, 0.18f, 0.55f) : new Color(1f, 1f, 1f, 0.05f));
                for (int i = -2; i <= 2; i++) Fill(new Rect(grip.center.x + i * 6 - 1, grip.y + 2, 2, 2), new Color(1f, 1f, 1f, over ? 0.7f : 0.25f));
            }
            if (e.type == EventType.MouseDown && e.button == 0 && grip.Contains(e.mousePosition) && !HudLayout.Editing)
            {
                if (e.clickCount >= 2) { HudLayout.Reset("status"); SaveHud(); }
                else { plateDragging = true; plateDragLast = e.mousePosition; }
                e.Use();
            }
            else if (plateDragging && e.type == EventType.MouseDrag)
            {
                HudLayout.Drag("status", 8, 8, 248, 92, hudW, hudH, e.mousePosition.x - plateDragLast.x, e.mousePosition.y - plateDragLast.y);
                plateDragLast = e.mousePosition;
                e.Use();
            }
            else if (plateDragging && (e.type == EventType.MouseUp || e.rawType == EventType.MouseUp)) { plateDragging = false; SaveHud(); e.Use(); }
        }

        void PlateBar(Rect r, int v, int max, Color c, HudBarTrack track, double now)
        {
            Fill(r, new Color(0f, 0f, 0f, 0.9f));
            int px = Plate.FillWidth(v, max, (int)r.width - 2);
            if (plateSmooth)
            {
                track.Widths(v, max, (int)r.width - 2, now, out px, out int chip, out _);
                if (chip > px) Fill(new Rect(r.x + 1 + px, r.y + 1, chip - px, r.height - 2), new Color(1f, 1f, 1f, 0.55f));   // the pale chip of a fall
            }
            if (px > 0) Fill(new Rect(r.x + 1, r.y + 1, px, r.height - 2), c);
            var st = new GUIStyle(small) { alignment = TextAnchor.MiddleCenter, fontSize = 12 };
            st.normal.textColor = Color.white;
            GUI.Label(r, Plate.BarText(v, max, plateAsPercent), st);
        }
    }
}
