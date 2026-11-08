// Phase 7 track X glue: the outfit with its wings, aura and shader (character cards and the create window's preview) and the in-client
// create character window of the character select. Rules: Core/Phase7XCharacter.cs. The website creates the character through its
// account API (website/README.md "Client API"), with the token of the login the list already did (ChaosApp.Phase6V.cs).
using System.Collections;
using System.Collections.Generic;
using Chaos.Core;
using UnityEngine;

namespace Chaos.Client
{
    public sealed partial class ChaosApp
    {
        // ------------------------------------------------------------------------------------ outfit with wings, aura and shader
        /// <summary>Draws an outfit like DrawOutfit and adds what the website knows: the aura under it (a ring on the ground only: tall ones hide the body),
        /// the wings at the body's place with the body lifted 6 pixels, and the shader as a pulsing tint. Without any of them it is DrawOutfit.</summary>
        public void DrawOutfitFx(Rect r, Outfit o, bool smallAurasOnly = true, Dir facing = Dir.South)
        {
            if (o == null || dat == null || atlas == null) return;
            if (o.LookType == 0 || (o.Wings == 0 && o.Aura == 0 && o.Mount == 0 && string.IsNullOrEmpty(o.Shader))) { DrawOutfit(r, o, facing); return; }
            var layers = OutfitLayers.Plan(o, id =>
            {
                var t = dat.Outfit(id);
                return t == null ? new KeyValuePair<int, int>(0, 0) : new KeyValuePair<int, int>(t.Idle.Width, t.Idle.Height);
            }, smallAurasOnly, id => { var t = dat.Outfit(id); return t == null ? new KeyValuePair<float, float>(0f, 0f) : new KeyValuePair<float, float>(t.DisplacementX, t.DisplacementY); });
            int n = 1;
            foreach (var l in layers)
            {
                var t = dat.Outfit(l.LookType);
                if (t != null) n = Mathf.Max(n, Mathf.Max(t.Idle.Width, t.Idle.Height));
            }
            float cell = r.width / n;
            var anchor = new Vector2(r.xMax - cell, r.yMax - cell);   // the bottom right cell of every layer: the tile the character stands on
            var tint = OutfitShaderTint.Of(o.Shader);
            var old = GUI.color;
            foreach (var l in layers)
            {
                bool shaded = !tint.None && l.Kind != OutfitLayer.Role.Aura;
                GUI.color = shaded ? Color.Lerp(Color.white, new Color(tint.R, tint.G, tint.B, 1f), tint.Strength(Time.unscaledTime)) : Color.white;
                DrawLayer(anchor + new Vector2(l.DX * cell, l.DY * cell), cell, o, l, facing);
            }
            GUI.color = old;
        }

        void DrawLayer(Vector2 at, float cell, Outfit o, OutfitLayer l, Dir facing = Dir.South)
        {
            var t = dat.Outfit(l.LookType);
            if (t == null) return;
            var g = t.Idle;
            int dir = (int)facing;
            if (g.PatternX < 8 && dir > 3) dir = 2;
            dir %= Mathf.Max(1, g.PatternX);
            // wings and auras move when their thing has frames; the body stands
            int phase = l.Kind != OutfitLayer.Role.Body && l.Kind != OutfitLayer.Role.Mount && g.Phases > 1 ? (int)(Time.unscaledTime * 6f) % g.Phases : 0;
            bool body = l.Kind == OutfitLayer.Role.Body;
            for (int addon = 0; addon < g.PatternY; addon++)
            {
                if (addon > 0 && (!body || (o.Addons & (1 << (addon - 1))) == 0)) continue;
                for (int hh = 0; hh < g.Height; hh++)
                    for (int ww = 0; ww < g.Width; ww++)
                    {
                        uint baseId = g.Sprite(ww, hh, 0, dir, addon, 0, phase);
                        uint maskId = body && g.Layers > 1 ? g.Sprite(ww, hh, 1, dir, addon, 0, phase) : 0;
                        int slot;
                        if (maskId == 0) slot = atlas.Sprite(baseId);
                        else
                        {
                            ulong key = (ulong)baseId << 28 ^ (ulong)(o.Head & 127) << 21 ^ (ulong)(o.Body & 127) << 14 ^ (ulong)(o.Legs & 127) << 7 ^ (ulong)(o.Feet & 127);
                            slot = atlas.Composed(key, () =>
                            {
                                var rgba = atlas.Raw(baseId);
                                var mask = atlas.Raw(maskId);
                                if (rgba != null && mask != null) OutfitColors.Apply(rgba, mask, o);
                                return rgba;
                            });
                        }
                        if (slot == 0) continue;
                        atlas.Upload();
                        GUI.DrawTextureWithTexCoords(new Rect(at.x - ww * cell, at.y - hh * cell, cell, cell), atlas.Texture, atlas.Uv(slot));
                    }
            }
        }

        // ------------------------------------------------------------------------------------ create character window
        bool creating;
        string newName = "", newStatus = "";
        int newClass = -1, newSex = 1, newSeason;
        bool newUnderstood, newBusy, newStatusBad, newSlotsFull;

        /// <summary>The state the create window reads: the account block of the login answer (null without the website's API).</summary>
        CreateState CreateInfo => acct != null ? acct.Create : null;

        void BeginCreate()
        {
            var s = CreateInfo;
            creating = true;
            newName = ""; newStatus = ""; newStatusBad = false; newBusy = false; newSex = 1; newSeason = 0; newUnderstood = false;
            newClass = CharCreate.FirstOpenClass(s);
            if (acct != null)
            {
                var line = CharCreate.SlotsLine(Mathf.Max(charModel.Cards.Count, acct.SlotsUsed), acct.SlotsLimit, out newSlotsFull);
                if (!line.IsNone) { newStatus = Loc.T(line.Key, line.Args); newStatusBad = newSlotsFull; }
            }
        }

        void SetNewStatus(Hint h, bool bad) { newStatus = h.IsNone ? "" : Loc.T(h.Key, h.Args); newStatusBad = bad; }

        void CharCreateGui(float w, float h)
        {
            var s = CreateInfo;
            if (s == null) { creating = false; return; }
            float bw = Mathf.Min(w - 24, 520f), bh = Mathf.Min(h - 24, 520f);
            var box = new Rect(w / 2 - bw / 2, h / 2 - bh / 2, bw, bh);
            GUILayout.BeginArea(box, GUI.skin.box);
            GUILayout.Label(Loc.T("Create character"), titleStyle);
            // name
            GUILayout.Label(Loc.T("Name"), small);
            GUI.SetNextControlName("newCharName");
            newName = GUILayout.TextField(newName ?? "", s.MaxL);
            if (GUI.GetNameOfFocusedControl() == "newCharName") MarkTextEditing();
            var nameHint = CharCreate.CheckName(newName, s.MinL, s.MaxL, s.MaxW);
            var shown = nameHint.IsNone || newName.Length == 0 ? CharCreate.Rules(s) : nameHint;
            var hs = new GUIStyle(small) { fontSize = 11 };
            hs.normal.textColor = !nameHint.IsNone && newName.Length > 0 ? new Color(0.88f, 0.23f, 0.12f) : new Color(0.55f, 0.5f, 0.44f);
            GUILayout.Label(Loc.T(shown.Key, shown.Args), hs);

            // classes: a coloured square per line; a locked one is dim
            GUILayout.Label(Loc.T("Class"), small);
            GUILayout.BeginHorizontal();
            foreach (var c in s.Classes)
            {
                var col = ClassTable.Of(c.Id);
                Color cc = ColorUtility.TryParseHtmlString(col.Color, out var parsed) ? parsed : Color.white;
                var old = GUI.color;
                GUI.color = c.Locked ? new Color(1f, 1f, 1f, 0.4f) : (c.Id == newClass ? Color.Lerp(Color.white, cc, 0.5f) : Color.white);
                string label = (c.Id == newClass ? "> " : "") + c.Name;
                if (GUILayout.Button(new GUIContent(label, c.Locked ? Loc.T("{0}: locked for this account. Reach level 200 with any character of your account to unlock it.", c.Name) : c.Plays), GUILayout.Height(26)))
                    newClass = c.Id;
                GUI.color = old;
            }
            GUILayout.EndHorizontal();
            var chosen = CharCreate.ClassOf(s, newClass);
            var cs = new GUIStyle(small) { fontSize = 11, wordWrap = true };
            cs.normal.textColor = chosen != null && chosen.Locked ? new Color(0.88f, 0.23f, 0.12f) : new Color(0.84f, 0.79f, 0.68f);
            GUILayout.Label(chosen == null ? Loc.T("Choose a class.")
                : chosen.Locked ? Loc.T("{0}: locked for this account. Reach level 200 with any character of your account to unlock it.", chosen.Name)
                : chosen.Name + ": " + (chosen.Plays.Length > 0 ? chosen.Plays : Loc.T("a base class. You choose its ascension at level 100.")), cs);

            // sex and the preview of the class look
            GUILayout.BeginHorizontal();
            int sex = GUILayout.Toolbar(newSex == 1 ? 0 : 1, new[] { Loc.T("Male"), Loc.T("Female") }) == 0 ? 1 : 0;
            newSex = sex;
            GUILayout.EndHorizontal();
            var pv = GUILayoutUtility.GetRect(96, 96, GUILayout.ExpandWidth(false));
            Fill(pv, new Color(0f, 0f, 0f, 0.5f));
            var look = CharCreate.PreviewOutfit(chosen, newSex);
            if (look != null) DrawOutfit(new Rect(pv.x + 16, pv.y + 16, 64, 64), look);

            // season
            var seasons = CharCreate.SeasonChoices(s);
            if (seasons.Count > 1)
            {
                GUILayout.Label(Loc.T("Season"), small);
                var labels = new string[seasons.Count];
                for (int i = 0; i < labels.Length; i++) labels[i] = i == 0 ? Loc.T(seasons[i].Label) : seasons[i].Label;
                newSeason = Mathf.Clamp(GUILayout.SelectionGrid(Mathf.Clamp(newSeason, 0, seasons.Count - 1), labels, 1), 0, seasons.Count - 1);
            }
            else newSeason = 0;
            var pick = seasons[Mathf.Clamp(newSeason, 0, seasons.Count - 1)];
            if (pick.Warning.Length > 0) GUILayout.Label(pick.Warning, cs);
            if (pick.Hardcore) newUnderstood = GUILayout.Toggle(newUnderstood, Loc.T("I understand"));
            else newUnderstood = false;

            // buttons
            var why = CharCreate.CanCreate(s, newName, newClass, pick, newUnderstood, newBusy);
            GUILayout.BeginHorizontal();
            if (!s.Terms && GUILayout.Button(Loc.T("Open the Terms page"), GUILayout.Height(30)) && s.TermsUrl.StartsWith("https://", System.StringComparison.Ordinal))
                Application.OpenURL(s.TermsUrl);
            GUI.enabled = why.IsNone && !newSlotsFull;
            if (GUILayout.Button(Loc.T("Create"), GUILayout.Height(30))) SubmitCreate(pick);
            GUI.enabled = true;
            if (GUILayout.Button(Loc.T("Cancel"), GUILayout.Height(30)) && !newBusy) creating = false;
            GUILayout.EndHorizontal();
            if (!why.IsNone && newStatus.Length == 0) GUILayout.Label(Loc.T(why.Key, why.Args), hs);
            if (newStatus.Length > 0)
            {
                var st = new GUIStyle(small) { fontSize = 12, wordWrap = true };
                st.normal.textColor = newStatusBad ? new Color(0.88f, 0.23f, 0.12f) : new Color(0.84f, 0.79f, 0.68f);
                GUILayout.Label(newStatus, st);
            }
            var e = Event.current;
            if (e.type == EventType.KeyDown && e.keyCode == KeyCode.Escape && !newBusy) { creating = false; e.Use(); }
            GUILayout.EndArea();
        }

        void SubmitCreate(SeasonChoice pick)
        {
            string url = SiteUrls.Account(host);
            if (url == null || acctToken.Length == 0 || newBusy) return;
            newBusy = true;
            SetNewStatus(new Hint("Creating your character..."), false);
            string body = CharCreate.CreateRequest(acctToken, newName, newClass, newSex, pick, newUnderstood, AccountApi.Nonce(() => UnityEngine.Random.Range(0, 16)));
            StartCoroutine(CreateRun(url, body));
        }

        IEnumerator CreateRun(string url, string body)
        {
            string text = "";
            yield return PostJson(url, body, t => text = t);
            newBusy = false;
            var a = CharCreate.ParseCreate(text);
            if (a.Ok)
            {
                newStatus = a.Message.Length > 0 ? a.Message : Loc.T("Created.");
                newStatusBad = false;
                string made = a.Name.Length > 0 ? a.Name : newName.Trim();
                PlayerPrefs.SetString("chaos.lastchar", made);
                creating = false;
                RefreshCharacterList();
                yield break;
            }
            if (a.TermsNeeded && CreateInfo != null) { CreateInfo.Terms = false; if (a.Url.Length > 0) CreateInfo.TermsUrl = a.Url; }
            if (a.Error == "token") { AccountEnd(); AccountStart(); creating = false; }
            newStatus = a.Message.Length > 0 ? a.Message : Loc.T("The website gave no answer.");
            newStatusBad = true;
        }

        /// <summary>Reads the character list from the login server again (the new character is on it) and drops the website token: the list rebuilds and logs in again.</summary>
        async void RefreshCharacterList()
        {
            try
            {
                var fresh = await LoginClient.Login(host, int.Parse(port), account, password, RsaModulus(), ClientBuild());
                if (fresh.Error != null) { status = fresh.Error; return; }
                AccountEnd();
                login = fresh;
            }
            catch (System.Exception ex) { status = "Login failed: " + ex.Message; }
        }
    }
}
