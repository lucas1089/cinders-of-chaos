// Phase 7, track Z: game_playerinspect. The passive tree of the inspected character, read-only (game_passivetree viewother.lua showOtherTree): the server's `tree` packet
// {name, nodes [ids], masteries [{id, choice}], cls, line, vocation, spent, total} against the tree data the client has. Pure.
using System;
using System.Collections.Generic;

namespace Chaos.Core
{
    public sealed class InspectTreeView
    {
        public string Name = "", Line = "", Vocation = "";
        public int Spent, Total;
        public readonly HashSet<int> Owned = new HashSet<int>();
        public readonly Dictionary<int, string> Choices = new Dictionary<int, string>();

        /// <summary>The view of a `tree` packet; null when it holds no node list.</summary>
        public static InspectTreeView From(object d)
        {
            if (!(Json.Get(d, "nodes") is List<object> nodes)) return null;
            var v = new InspectTreeView { Name = Json.Text(d, "name"), Line = Json.Text(d, "line"), Vocation = Json.Text(d, "vocation"), Spent = Json.Int(d, "spent"), Total = Json.Int(d, "total") };
            foreach (object n in nodes) if (n is double id) v.Owned.Add((int)id);
            foreach (object m in Json.List(d, "masteries")) v.Choices[Json.Int(m, "id")] = Json.Text(m, "choice");
            return v;
        }

        /// <summary>A node the view draws: not hidden, and of every line or of the inspected character's line.</summary>
        public bool Shown(TreeNode n) => !n.Hidden && (n.Line.Length == 0 || Line.Length == 0 || n.Line == Line);

        /// <summary>The title line: "Name: 12 / 30 points".</summary>
        public string Summary() => Loc.T("{0}: {1} / {2} points", Name, Spent, Total);

        /// <summary>The node as this character sees it (the class variant), and the mastery choice text appended when the node is a mastery with one.</summary>
        public string Tip(TreeNode n)
        {
            var shown = n.For(Vocation.Length > 0 ? Vocation : null);
            var lines = new List<string> { shown.Name };
            if (shown.Desc.Length > 0) lines.Add(shown.Desc);
            foreach (string s in shown.Stats) lines.Add(s);
            if (n.IsMastery && Choices.TryGetValue(n.Id, out string choice) && choice.Length > 0) lines.Add(Loc.T("Choice: {0}", choice));
            lines.Add(Owned.Contains(n.Id) ? Loc.T("Taken") : Loc.T("Not taken"));
            return string.Join("\n", lines);
        }

        /// <summary>The scale and centre that fit the tree's bounds into a view of w x h pixels.</summary>
        public static void Fit(TreeData d, float w, float h, out float zoom, out float cx, out float cy)
        {
            float tw = d.MaxX - d.MinX + 200, th = d.MaxY - d.MinY + 200;
            zoom = Math.Max(0.04f, Math.Min(1.5f, Math.Min(w / tw, h / th)));
            cx = (d.MinX + d.MaxX) / 2; cy = (d.MinY + d.MaxY) / 2;
        }
    }
}
