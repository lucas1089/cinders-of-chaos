// Battle list (Ctrl+B): the creatures on the player's floor in view, nearest first.
// Left-click attacks (again to stop), right-click follows.
using System;
using System.Collections.Generic;
using Chaos.Core;
using UnityEngine;

namespace Chaos.Client
{
    public sealed class BattleListWindow : GameWindow
    {
        const float RowH = 28f;
        Vector2 scroll;
        readonly List<Creature> rows = new List<Creature>();

        public override string Title => "Battle";
        public override KeyCode Hotkey => KeyCode.B;
        protected override Rect Place(float w, float h) => new Rect(w - 216, 314, 208, 260);
        public override void Reset() { scroll = Vector2.zero; rows.Clear(); }

        static Color TypeColor(Creature c)
        {
            switch (c.Type)
            {
                case 0: return new Color(0.3f, 0.85f, 0.3f);    // player
                case 1: return new Color(0.9f, 0.25f, 0.2f);    // monster
                case 2: return new Color(0.35f, 0.65f, 1f);     // npc
                default: return new Color(0.95f, 0.8f, 0.2f);   // summons
            }
        }

        void Collect(World world)
        {
            rows.Clear();
            var me = world.Player;
            if (me == null) return;
            Pos origin = me.Position;
            foreach (var c in world.Creatures.Values)
            {
                if (c == me || c.Position.Z != origin.Z) continue;
                // the visible 15 x 11 tiles
                if (Math.Abs(c.Position.X - origin.X) > 7 || Math.Abs(c.Position.Y - origin.Y) > 5) continue;
                rows.Add(c);
            }
            rows.Sort((a, b) =>
            {
                int da = Math.Max(Math.Abs(a.Position.X - origin.X), Math.Abs(a.Position.Y - origin.Y));
                int db = Math.Max(Math.Abs(b.Position.X - origin.X), Math.Abs(b.Position.Y - origin.Y));
                int d = da.CompareTo(db);
                return d != 0 ? d : string.CompareOrdinal(a.Name, b.Name);
            });
        }

        protected override void Body(ChaosApp app, Rect inner)
        {
            var session = app.Session;
            var world = app.World;
            if (session == null || world == null) return;
            var e = Event.current;
            // the list is rebuilt on layout; repaint and mouse events use it as it is
            if (e.type == EventType.Layout) Collect(world);
            uint target = session.AttackTarget;
            float contentW = inner.width - 18;
            scroll = GUI.BeginScrollView(inner, scroll, new Rect(0, 0, contentW, Mathf.Max(inner.height, rows.Count * RowH)));
            for (int i = 0; i < rows.Count; i++)
            {
                var c = rows[i];
                var row = new Rect(0, i * RowH, contentW, RowH - 2);
                bool attacked = c.Id == target;
                ChaosApp.Fill(row, attacked ? new Color(0.45f, 0.08f, 0.08f, 0.9f) : new Color(1f, 1f, 1f, 0.06f));
                ChaosApp.Fill(new Rect(row.x + 4, row.y + 4, 12, 12), TypeColor(c));
                GUI.Label(new Rect(row.x + 22, row.y, row.width - 26, 20), c.Name, app.SmallStyle);
                var bar = new Rect(row.x + 22, row.y + 20, row.width - 28, 4);
                ChaosApp.Fill(bar, new Color(0f, 0f, 0f, 0.85f));
                int hp = c.HealthPercent;
                var hpCol = hp > 50 ? new Color(0.2f, 0.85f, 0.2f) : hp > 20 ? new Color(0.95f, 0.8f, 0.1f) : new Color(0.9f, 0.15f, 0.1f);
                ChaosApp.Fill(new Rect(bar.x, bar.y, bar.width * Mathf.Clamp01(hp / 100f), bar.height), hpCol);
                if (e.type == EventType.MouseDown && row.Contains(e.mousePosition))
                {
                    if (e.button == 0)
                    {
                        if (attacked) session.CancelAttack(); else session.Attack(c.Id);
                    }
                    else if (e.button == 1) session.Follow(c.Id);
                    e.Use();
                }
            }
            GUI.EndScrollView();
        }
    }
}
