// Phase 7 track X, character select: the outfit with its wings, aura and shader on a card, and the create character window.
// Ports of client_chaos_charselect (charselect_core.lua figure / smallAura / mergeOutfit, charcreate.lua) and of the website's
// account API (website/README.md "Client API": the answer's `account` block and the `create` action).
using System;
using System.Collections.Generic;

namespace Chaos.Core
{
    // ============================================================================================================ outfit layers
    /// <summary>One picture of a drawn outfit: the aura under it, the wings at the body's place and the body itself.</summary>
    public struct OutfitLayer
    {
        public enum Role { Aura, Wings, Body, Mount }   // Mount: phase 8 B (the look preview draws the mount under the rider)
        public Role Kind;
        public int LookType;
        /// <summary>Offset in tiles (32 sprite pixels) added to the layer's place: +x right, +y down.</summary>
        public float DX, DY;
    }

    /// <summary>Which pictures an outfit draws and where they stand (charselect_core.lua figure, smallAura and the engine's wing offset).</summary>
    public static class OutfitLayers
    {
        /// <summary>Sprite pixels the engine moves a winged body up and left of its wings (feature GameWingOffset, charselect.lua wingLift).</summary>
        public const int WingLift = 6;

        /// <summary>A card shows an aura only when it is a ring on the ground: one tile at most (the main client's table also needs its mass at the feet).
        /// A tall aura (flames, a pillar of light) stood behind the character and hid it (the main client leaves it out of the preview).</summary>
        public static bool SmallAura(int width, int height) => width <= 1 && height <= 1;

        /// <summary>The layers, back to front. size(id) = the thing's width and height in tiles, or (0, 0) when unknown.
        /// A big aura is moved by (w - 1) * 16 and (h - 1) * 16 pixels (GameBigAurasCenter); a winged body sits WingLift up and left.</summary>
        public static List<OutfitLayer> Plan(Outfit o, Func<int, KeyValuePair<int, int>> size, bool smallAurasOnly, Func<int, KeyValuePair<float, float>> displacement = null)
        {
            var list = new List<OutfitLayer>();
            if (o == null || o.LookType == 0) return list;
            if (o.Aura > 0)
            {
                var s = size != null ? size(o.Aura) : new KeyValuePair<int, int>(0, 0);
                if (s.Key > 0 && s.Value > 0 && (!smallAurasOnly || SmallAura(s.Key, s.Value)))
                    list.Add(new OutfitLayer { Kind = OutfitLayer.Role.Aura, LookType = o.Aura, DX = (s.Key - 1) * 16f / 32f, DY = (s.Value - 1) * 16f / 32f });
            }
            // phase 8 B: the mount stands under the rider, who rides up by the mount's displacement (Outfit::draw moves the origin by it)
            float liftX = 0f, liftY = 0f;
            if (o.Mount > 0)
            {
                var ms = size != null ? size(o.Mount) : new KeyValuePair<int, int>(0, 0);
                if (ms.Key > 0 && ms.Value > 0)
                {
                    list.Add(new OutfitLayer { Kind = OutfitLayer.Role.Mount, LookType = o.Mount });
                    var d = displacement != null ? displacement(o.Mount) : new KeyValuePair<float, float>(0f, 0f);
                    liftX = d.Key / 32f; liftY = d.Value / 32f;
                }
            }
            bool winged = false;
            if (o.Wings > 0)
            {
                var s = size != null ? size(o.Wings) : new KeyValuePair<int, int>(0, 0);
                if (s.Key > 0 && s.Value > 0) { list.Add(new OutfitLayer { Kind = OutfitLayer.Role.Wings, LookType = o.Wings }); winged = true; }
            }
            float lift = winged ? WingLift / 32f : 0f;
            list.Add(new OutfitLayer { Kind = OutfitLayer.Role.Body, LookType = o.LookType, DX = -lift - liftX, DY = -lift - liftY });
            return list;
        }
    }

    // ============================================================================================================ shader tint
    /// <summary>The colour an outfit shader gives a picture, and how it moves: an approximation of the main client's GLSL files in a tint that
    /// IMGUI can draw (the shader itself runs in the engine). Strength is 0 to 1 of the way from white to the tint.</summary>
    public struct ShaderTint
    {
        public float R, G, B;
        public float Base, Swing, Speed;   // strength = Base + Swing * sin(time * Speed)
        public bool None;

        public float Strength(double seconds) => Math.Max(0f, Math.Min(1f, Base + Swing * (float)Math.Sin(seconds * Speed)));
    }

    public static class OutfitShaderTint
    {
        // the colour word of a shader name (shaders.xml names and the Chaos ones of outfitshaderlist.lua), first match wins
        static readonly object[][] Colors =
        {
            new object[] { "ember", 1.00f, 0.55f, 0.25f }, new object[] { "orange", 1.00f, 0.60f, 0.25f }, new object[] { "infernal", 1.00f, 0.50f, 0.20f },
            new object[] { "cinder", 1.00f, 0.60f, 0.30f }, new object[] { "blood", 0.95f, 0.30f, 0.35f }, new object[] { "heartblood", 0.95f, 0.30f, 0.35f },
            new object[] { "crimson", 0.95f, 0.30f, 0.30f }, new object[] { "red", 0.95f, 0.35f, 0.35f },
            new object[] { "frost", 0.55f, 0.80f, 1.00f }, new object[] { "rime", 0.65f, 0.85f, 1.00f }, new object[] { "blue", 0.50f, 0.65f, 1.00f },
            new object[] { "azure", 0.50f, 0.65f, 1.00f }, new object[] { "arcane", 0.60f, 0.55f, 1.00f },
            new object[] { "venom", 0.50f, 0.95f, 0.45f }, new object[] { "verdant", 0.55f, 0.95f, 0.50f }, new object[] { "green", 0.50f, 0.95f, 0.50f },
            new object[] { "golden", 1.00f, 0.88f, 0.40f }, new object[] { "yellow", 1.00f, 0.90f, 0.40f }, new object[] { "holy", 1.00f, 0.95f, 0.65f },
            new object[] { "radiance", 1.00f, 0.95f, 0.65f }, new object[] { "crown", 1.00f, 0.70f, 0.35f },
            new object[] { "void", 0.75f, 0.45f, 1.00f }, new object[] { "pink", 1.00f, 0.55f, 0.85f },
            new object[] { "spectral", 0.80f, 0.95f, 0.95f }, new object[] { "ghost", 0.80f, 0.95f, 0.95f }, new object[] { "ivory", 1.00f, 0.97f, 0.88f },
            new object[] { "white", 1.00f, 1.00f, 1.00f }, new object[] { "pale", 0.95f, 0.95f, 1.00f }, new object[] { "ash", 0.75f, 0.72f, 0.70f },
        };

        /// <summary>The tint of a shader name; None for "" (no shader). A name with no colour word gets a soft gold glow.</summary>
        public static ShaderTint Of(string name)
        {
            var t = new ShaderTint { R = 1f, G = 0.88f, B = 0.55f, Base = 0.30f, Swing = 0.08f, Speed = 2.0f };
            if (string.IsNullOrEmpty(name)) { t.None = true; return t; }
            string n = name.ToLowerInvariant();
            foreach (var c in Colors)
                if (n.Contains((string)c[0])) { t.R = (float)c[1]; t.G = (float)c[2]; t.B = (float)c[3]; break; }
            // the motion by the family: pulses beat, sparks flicker fast, waves roll slowly, haze and glow breathe
            if (n.Contains("energizer") || n.Contains("pulse") || n.Contains("blood")) { t.Base = 0.30f; t.Swing = 0.18f; t.Speed = 4.0f; }
            else if (n.Contains("pixent") || n.Contains("sparks") || n.Contains("flicker")) { t.Base = 0.28f; t.Swing = 0.14f; t.Speed = 9.0f; }
            else if (n.Contains("dortmond") || n.Contains("waves")) { t.Base = 0.30f; t.Swing = 0.10f; t.Speed = 1.3f; }
            else if (n.Contains("ghost") || n.Contains("spectral")) { t.Base = 0.22f; t.Swing = 0.10f; t.Speed = 1.7f; }
            return t;
        }
    }

    // ============================================================================================================ create window
    public sealed class CreateClass
    {
        public int Id, Male, Female;
        public string Name = "", Plays = "", Icon = "";
        public bool Locked;
    }

    public sealed class CreateMode
    {
        public string Key = "", Name = "", Warning = "";
        public bool Hardcore;
    }

    public sealed class SeasonChoice
    {
        public int Season;
        public string Mode = "", Label = "", Warning = "";
        public bool Hardcore;
    }

    /// <summary>A text for the window: the English key and its arguments; the window runs it through Loc.T.</summary>
    public struct Hint
    {
        public string Key;
        public object[] Args;
        public Hint(string key, params object[] args) { Key = key; Args = args; }
        public bool IsNone => Key == null;
    }

    /// <summary>The `account` block of the website's login and state answers, as far as the create window reads it.</summary>
    public sealed class CreateState
    {
        public bool Terms = true;
        public string TermsUrl = "";
        public int MinL = 3, MaxL = 20, MaxW = 3;
        public int SeasonId;
        public string SeasonName = "", SeasonTag = "";
        public readonly List<CreateClass> Classes = new List<CreateClass>();
        public readonly List<CreateMode> Modes = new List<CreateMode>();

        public static CreateState From(object account)
        {
            if (!(account is Dictionary<string, object>)) return null;
            var s = new CreateState { Terms = Json.Get(account, "terms") as bool? ?? true, TermsUrl = Json.Text(account, "termsUrl") };
            object rules = Json.Get(account, "rules");
            if (rules != null) { s.MinL = Json.Int(rules, "minL", 3); s.MaxL = Json.Int(rules, "maxL", 20); s.MaxW = Json.Int(rules, "maxW", 3); }
            foreach (object c in Json.List(account, "classes"))
                s.Classes.Add(new CreateClass
                {
                    Id = Json.Int(c, "id"), Name = Json.Text(c, "name"), Plays = Json.Text(c, "plays"), Icon = Json.Text(c, "icon"),
                    Locked = Json.Bool(c, "locked"), Male = Json.Int(c, "male"), Female = Json.Int(c, "female"),
                });
            object season = Json.Get(account, "season");
            if (season is Dictionary<string, object> && Json.Get(season, "id") is double sid)
            {
                s.SeasonId = (int)sid; s.SeasonName = Json.Text(season, "name"); s.SeasonTag = Json.Text(season, "tag");
                foreach (object m in Json.List(season, "modes"))
                    s.Modes.Add(new CreateMode { Key = Json.Text(m, "key"), Name = Json.Text(m, "name"), Warning = Json.Text(m, "warning"), Hardcore = Json.Bool(m, "hc") });
            }
            return s;
        }
    }

    public sealed class CreateAnswer
    {
        public bool Ok;
        public string Message = "", Name = "", Error = "", Url = "";
        public bool TermsNeeded => Error == "terms";
    }

    /// <summary>The create window's rules: the name check, the class and season choices, the request and the answer (charcreate.lua, charselect_core.lua).</summary>
    public static class CharCreate
    {
        /// <summary>The website's starter colours (ZnoteX's defaults), the preview's colours.</summary>
        public const int StarterHead = 78, StarterBody = 68, StarterLegs = 58, StarterFeet = 76, StarterAddons = 3;

        /// <summary>The first check of a typed name, before the website's own: none when fine. Letters and spaces, one space between words, at least two letters a word.</summary>
        public static Hint CheckName(string name, int minL = 3, int maxL = 20, int maxW = 3)
        {
            string n = (name ?? "").Trim();
            if (n.Length == 0) return new Hint("Enter a name.");
            foreach (char c in n) if (!((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || c == ' ')) return new Hint("Use letters and spaces only.");
            if (n.Contains("  ")) return new Hint("Use one space between words.");
            int words = 0;
            foreach (string w in n.Split(' ')) { if (w.Length == 0) continue; words++; if (w.Length == 1) return new Hint("Every word needs at least two letters."); }
            if (words > maxW) return new Hint("Use at most {0} words.", maxW);
            if (n.Length < minL || n.Length > maxL) return new Hint("The name needs {0} to {1} letters.", minL, maxL);
            return default(Hint);
        }

        /// <summary>The line under the name box when the field is empty or fine.</summary>
        public static Hint Rules(CreateState s) => new Hint("{0} to {1} letters, up to {2} words.", s?.MinL ?? 3, s?.MaxL ?? 20, s?.MaxW ?? 3);

        /// <summary>The season choices: "No season" first, then one per mode of the running season, "Name Tag: Mode".</summary>
        public static List<SeasonChoice> SeasonChoices(CreateState s)
        {
            var list = new List<SeasonChoice> { new SeasonChoice { Season = 0, Label = "No season (standard character)" } };
            if (s != null && s.SeasonId > 0)
                foreach (var m in s.Modes)
                    list.Add(new SeasonChoice
                    {
                        Season = s.SeasonId, Mode = m.Key, Hardcore = m.Hardcore, Warning = m.Warning,
                        Label = (s.SeasonName.Length > 0 ? s.SeasonName : "Season") + " " + s.SeasonTag + ": " + (m.Name.Length > 0 ? m.Name : m.Key),
                    });
            return list;
        }

        /// <summary>The first class the account may create (-1 when all are locked).</summary>
        public static int FirstOpenClass(CreateState s)
        {
            if (s != null) foreach (var c in s.Classes) if (!c.Locked) return c.Id;
            return -1;
        }

        public static CreateClass ClassOf(CreateState s, int id)
        {
            if (s != null) foreach (var c in s.Classes) if (c.Id == id) return c;
            return null;
        }

        /// <summary>The look type the preview shows for a class and sex (sex 1 male, 0 female); 0 when the website sent none.</summary>
        public static int LookOf(CreateClass c, int sex) => c == null ? 0 : sex == 0 ? c.Female : c.Male;

        public static Outfit PreviewOutfit(CreateClass c, int sex)
        {
            int look = LookOf(c, sex);
            return look > 0 ? new Outfit(look, StarterHead, StarterBody, StarterLegs, StarterFeet, StarterAddons) : null;
        }

        /// <summary>Why Create cannot be pressed (none when it can): a name that fails, a locked class, Terms not accepted, an unconfirmed hardcore choice.</summary>
        public static Hint CanCreate(CreateState s, string name, int vocation, SeasonChoice season, bool understood, bool busy)
        {
            if (busy) return new Hint("Creating your character...");
            if (s == null) return new Hint("Reading your account from the website...");
            if (!s.Terms) return new Hint("Accept the current Terms of Use on the website first, then come back.");
            var h = CheckName(name, s.MinL, s.MaxL, s.MaxW);
            if (!h.IsNone) return h;
            var c = ClassOf(s, vocation);
            if (c == null) return new Hint("Choose a class.");
            if (c.Locked) return new Hint("{0}: locked for this account. Reach level 200 with any character of your account to unlock it.", c.Name);
            if (season != null && season.Hardcore && !understood) return new Hint("Hardcore has one life: tick \"I understand\" to choose it.");
            return default(Hint);
        }

        /// <summary>The slots line of the window: the free ones, or none left.</summary>
        public static Hint SlotsLine(int used, int limit, out bool full)
        {
            full = limit >= 0 && used >= limit;
            if (limit < 0) return default(Hint);
            if (full) return new Hint("No free character slot: more are sold in the game store (Storage & Slots > Character Slot).");
            return new Hint("Character slots: {0} of {1} used.", used, limit);
        }

        public static string CreateRequest(string token, string name, int vocation, int sex, SeasonChoice season, bool hardcore, string nonce) =>
            Json.Serialize(new Dictionary<string, object>
            {
                { "action", "create" }, { "token", token }, { "nonce", nonce }, { "name", (name ?? "").Trim() }, { "vocation", vocation }, { "sex", sex },
                { "season", season?.Season ?? 0 }, { "mode", season?.Mode ?? "" }, { "hardcore", hardcore }, { "town", 0 },
            });

        /// <summary>The answer of `create`: ok with the stored name and the website's message, or the errors (one line each, no repeats), or the 403 "terms" with the accept page.</summary>
        public static CreateAnswer ParseCreate(string body)
        {
            var a = new CreateAnswer();
            object root = Json.TryParse(body);
            if (!(root is Dictionary<string, object>)) { a.Error = "noanswer"; return a; }
            a.Ok = Json.Bool(root, "ok");
            a.Name = Json.Text(root, "name");
            a.Url = Json.Text(root, "url");
            if (a.Ok) { a.Message = Json.Text(root, "message"); return a; }
            a.Error = Json.Text(root, "error", "failed");
            var seen = new HashSet<string>();
            var lines = new List<string>();
            foreach (object e in Json.List(root, "errors")) if (e is string es && seen.Add(es)) lines.Add(es);
            a.Message = lines.Count > 0 ? string.Join("\n", lines) : Json.Text(root, "message");
            return a;
        }
    }
}
