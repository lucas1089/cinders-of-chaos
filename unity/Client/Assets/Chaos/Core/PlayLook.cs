// game_lookpreview (track P): the pure part of the shared look preview panel. A window that picks a look gives the panel an option (an outfit, a mount, wings,
// an aura, a shader, a store bundle ...); the panel turns it into the outfit it draws on the character as worn, or on the plain figure. Rules: lookpreview_core.lua
// (base, composeRaw, fromStoreLook, key, turn). The effect stage (spell skins, kill effects), the footprints and the outline are drawn by the engine of the main
// client; here an option of those kinds gives a note and the figure unchanged, except that its parts still compose (a bundle).
using System;
using System.Collections.Generic;

namespace Chaos.Core
{
    public sealed class PreviewOption
    {
        public string Kind = "none";
        public int Look, Addons;
        public string Shader = "", Art = "", Frame = "";
        public bool Pulse, KillFx;
        public Outfit Outfit;
        public List<PreviewOption> Parts;
        public object Play;

        public static PreviewOption Of(string kind, int look = 0) => new PreviewOption { Kind = kind, Look = look };
    }

    public static class LookPreview
    {
        /// <summary>The plain figure "boneco simples": a citizen look in greys with nothing extra, so one effect reads on its own.</summary>
        public static Outfit Neutral() => new Outfit(128, 76, 57, 76, 95) { Shader = "" };

        public const string UnknownShader = "This shader is not in your client yet.";
        public const string NoOutline = "Your client cannot draw outlines yet.";
        public static readonly HashSet<string> Kinds = new HashSet<string> { "outfit", "addons", "mount", "wings", "aura", "shader", "outline", "effects", "look", "subject", "bundle", "none" };

        public static Outfit Copy(Outfit o) => new Outfit(o.LookType, o.Head, o.Body, o.Legs, o.Feet, o.Addons, o.Mount) { LookTypeEx = o.LookTypeEx, Wings = o.Wings, Aura = o.Aura, Shader = o.Shader ?? "" };

        /// <summary>The outfit a panel starts from: the own one as worn, or the plain figure ("simple", or no own outfit).</summary>
        public static Outfit Base(bool simple, Outfit own)
        {
            if (simple || own == null || own.LookType <= 0) return Neutral();
            return Copy(own);
        }

        /// <summary>The note for a kind the figure cannot show, or null.</summary>
        public static string Note(PreviewOption opt)
        {
            if (opt == null) return null;
            switch (opt.Kind)
            {
                case "footprint": return Loc.T("Footprints are left on the ground as you walk.");
                case "nameplate": return Loc.T("Name plates show over characters in the game world.");
                case "transmog": return Loc.T("Item looks show on the item, not on the character.");
                case "effects": return Loc.T("Effects play in the game world.");
                case "outline": return Loc.T("Outlines show in the game world.");
                default: return null;
            }
        }

        public static bool Showable(PreviewOption opt) => opt == null || Kinds.Contains(opt.Kind);

        /// <summary>Does the plain-figure switch mean anything: a pet has no wearer, a kill effect plays on a troll.</summary>
        public static bool HasWearer(PreviewOption opt) => opt == null || !(opt.Kind == "subject" || (opt.Kind == "effects" && opt.KillFx));

        /// <summary>What to draw for an option: the outfit and a note. known(name) tells whether an outfit shader is in the client (an unknown name is left off with a note).</summary>
        public static Outfit Compose(bool simple, Outfit own, PreviewOption opt, Func<string, bool> known, out string note)
        {
            var o = ComposeRaw(simple, own, opt, out note);
            if (!string.IsNullOrEmpty(o.Shader) && known != null && !known(o.Shader)) { o.Shader = ""; note = note ?? Loc.T(UnknownShader); }
            return o;
        }

        public static Outfit ComposeRaw(bool simple, Outfit own, PreviewOption opt, out string note)
        {
            note = null;
            string kind = opt == null ? "none" : opt.Kind;
            if (kind == "subject") return new Outfit { LookType = opt.Look, Shader = "" };
            var o = Base(simple, own);
            if (kind == "bundle")
            {
                if (opt.Parts != null)
                    foreach (var p in opt.Parts)
                    {
                        if (p == null || p.Kind == "bundle" || p.Kind == "subject" || p.Kind == "effects" || p.Kind == "footprint") continue;
                        o = ComposeRaw(false, o, p, out string pn);
                        note = note ?? pn;
                    }
                return o;
            }
            if (kind == "look" && opt.Outfit != null)
            {
                if (simple) { o.Mount = opt.Outfit.Mount; o.Wings = opt.Outfit.Wings; o.Aura = opt.Outfit.Aura; o.Shader = opt.Outfit.Shader ?? ""; }
                else o = Base(false, opt.Outfit);
            }
            else if (kind == "outfit" || kind == "addons")
            {
                if (opt.Look > 0) o.LookType = opt.Look;
                o.Addons = kind == "addons" ? 3 : opt.Addons;
            }
            else if (kind == "mount") o.Mount = opt.Look;
            else if (kind == "wings") o.Wings = opt.Look;
            else if (kind == "aura") o.Aura = opt.Look;
            else if (kind == "shader") o.Shader = opt.Shader ?? "";
            note = Note(opt);
            return o;
        }

        static string Name(string v) => !string.IsNullOrEmpty(v) && v.Length <= 64 && System.Text.RegularExpressions.Regex.IsMatch(v, "^[A-Za-z0-9_ ]+$") ? v : null;

        /// <summary>The look of a store offer or category (server shop_core.lua lookOf) as an option; null for what is not worn. The table is data: everything is checked.</summary>
        public static PreviewOption FromStoreLook(object l, int depth = 0)
        {
            if (l == null || depth > 1) return null;
            string k = Json.Text(l, "kind");
            int look = Json.Int(l, "look");
            switch (k)
            {
                case "outfit": case "addons":
                    return look > 0 ? new PreviewOption { Kind = "outfit", Look = look, Addons = k == "addons" ? 3 : Json.Get(l, "addons") == null ? 3 : Json.Int(l, "addons") } : null;
                case "mount": case "wings": case "aura": case "subject":
                    return look > 0 ? PreviewOption.Of(k, look) : null;
                case "shader":
                    return Json.Text(l, "shader").Length > 0 ? new PreviewOption { Kind = "shader", Shader = Json.Text(l, "shader") } : null;
                case "outline": { var a = Name(Json.Text(l, "art")); return a != null ? new PreviewOption { Kind = "outline", Art = a, Pulse = Json.Truthy(l, "pulse") } : null; }
                case "footprint": { var a = Name(Json.Text(l, "art")); return a != null ? new PreviewOption { Kind = "footprint", Art = a } : null; }
                case "effects": { var pl = Json.List(l, "play"); return pl != null && pl.Count > 0 ? new PreviewOption { Kind = "effects", Play = pl, KillFx = Json.Truthy(l, "killfx") } : null; }
                case "nameplate": { var f = Name(Json.Text(l, "frame")); return f != null ? new PreviewOption { Kind = "nameplate", Frame = f } : null; }
                case "bundle":
                {
                    var parts = new List<PreviewOption>();
                    var src = Json.List(l, "parts");
                    if (src != null) foreach (var p in src) { var o = FromStoreLook(p, depth + 1); if (o != null) parts.Add(o); }
                    return parts.Count > 0 ? new PreviewOption { Kind = "bundle", Parts = parts } : null;
                }
            }
            return null;
        }

        /// <summary>A button of the Outfit window's list (row "outfit", "mount", "aura" or "shader") as an option.</summary>
        public static PreviewOption FromOutfitButton(string row, Outfit o)
        {
            if (o == null) return null;
            switch (row)
            {
                case "outfit": return new PreviewOption { Kind = "outfit", Look = o.LookType, Addons = o.Addons };
                case "mount": return PreviewOption.Of("mount", o.LookType);
                case "aura": return PreviewOption.Of("aura", o.Aura);
                case "shader": return new PreviewOption { Kind = "shader", Shader = o.Shader ?? "" };
            }
            return null;
        }

        /// <summary>The same outfit: no redraw while a window's outfit has not changed.</summary>
        public static string Key(Outfit o) => o == null ? "" : string.Join(",", o.LookType, o.Head, o.Body, o.Legs, o.Feet, o.Addons, o.Mount, o.Wings, o.Aura, o.Shader ?? "");

        /// <summary>Directions as the client numbers them for the panel: 0 north, 1 east, 2 south, 3 west; a step clockwise is +1.</summary>
        public const int South = 2;
        public const double AutoTurnMs = 1600;
        public static int Turn(int dir, int step) => ((dir + step) % 4 + 4) % 4;
    }
}
