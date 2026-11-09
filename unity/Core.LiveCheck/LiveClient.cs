// One game connection of the live check: the world, the session and what the scenarios read of them (server lines, refused steps, exceptions).
// The primary connection of a run and the partner of the party and death scenarios (a second account) are both a LiveClient; LiveRun.Pump polls both.
using System;
using System.Collections.Generic;

namespace Chaos.Core.LiveCheck
{
    public sealed class SaidLine
    {
        public string Who = "", Text = "";
        public byte Type;
    }

    public sealed class LiveClient
    {
        public readonly World World;
        public readonly GameSession S;
        /// <summary>The character's name as the character list gave it (used in chat commands; never written to a report).</summary>
        public readonly string Character;
        public int Cancels;
        public readonly List<string> Thrown = new List<string>();
        /// <summary>Extended opcode messages that were invalid JSON or threw in a Core handler on this connection (phase 24; the primary's are also counted per opcode).</summary>
        public int ExtErrors;
        /// <summary>Every chat line and server message, in order (capped at 20000).</summary>
        public readonly List<SaidLine> Said = new List<SaidLine>();

        public LiveClient(World w, GameSession s, string character)
        {
            World = w; S = s; Character = character;
            s.Chat += (who, text, type) => { if (Said.Count < 20000) Said.Add(new SaidLine { Who = who, Text = text, Type = type }); };
            var prev = s.Parser.WalkCancelled;
            s.Parser.WalkCancelled = d => { Cancels++; prev(d); };
            var prevLog = s.Ext.Log;
            s.Ext.Log = m => { if (m.StartsWith("extended opcode ", StringComparison.Ordinal)) ExtErrors++; prevLog(m); };
        }

        public Pos Pos { get { var p = World.Player; return p == null ? default : p.Position; } }
        public bool Entered => S.Parser.LoggedIn && World.Player != null && World.Tiles.Count > 0;

        /// <summary>One Poll. A parse error costs the packet (the session logs it), any other exception is kept.</summary>
        public void Poll()
        {
            try { S.Poll(); }
            catch (Exception e) when (!(e is ProtocolException))
            {
                if (Thrown.Count < 50) Thrown.Add(e.GetType().Name + ": " + e.Message);
            }
        }

        /// <summary>The server messages (no speaker) from line `from` on.</summary>
        public List<string> ServerTexts(int from)
        {
            var o = new List<string>();
            for (int i = Math.Max(0, from); i < Said.Count; i++) if (Said[i].Who.Length == 0) o.Add(Said[i].Text);
            return o;
        }

        /// <summary>Logs in to a game server like the Unity client: login server, character list, game login. Null session when the login failed (error says why).</summary>
        public static LiveClient Connect(LiveOptions o, DatFile dat, string account, string password, string character, out string error)
        {
            error = null;
            var res = LoginClient.Login(o.Host, o.Port, account, password, o.Rsa).GetAwaiter().GetResult();
            if (res.Error != null) { error = "login: " + res.Error; return null; }
            var ch = character != null ? res.Characters.Find(x => x.Name == character) : (res.Characters.Count > 0 ? res.Characters[0] : null);
            if (ch == null) { error = "no such character in the list"; return null; }
            var world = new World(dat);
            var s = new GameSession(world, new GameSession.Options
            {
                Host = ch.Host, Port = ch.Port, Account = account, Password = password, SessionKey = res.SessionKey, Character = ch.Name,
                GuardKey = o.GuardKey, RsaModulus = o.Rsa, Identity = o.Chaos ? ClientIdentity.Chaos(30) : ClientIdentity.Extended,
                AwareWidth = o.Chaos ? o.AwareWidth : 0, AwareHeight = o.Chaos ? o.AwareHeight : 0,
            });
            var c = new LiveClient(world, s, ch.Name);
            s.Start();
            return c;
        }

        public void Close()
        {
            try { S.Logout(); } catch (Exception) { }
            var end = Environment.TickCount64 + 300;
            while (Environment.TickCount64 < end) { Poll(); System.Threading.Thread.Sleep(5); }
            S.Dispose();
        }
    }
}
