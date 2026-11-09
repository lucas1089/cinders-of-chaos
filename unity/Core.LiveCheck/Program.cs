// dotnet run -c Release --project unity/Core.LiveCheck -- HOST LOGIN_PORT ACCOUNT [CHARACTER|-] [--seconds N] [--report FILE]
//                                                           [--identity extended|chaos] [--otb items.otb | --pair DIR] [--no-ext]
// The password comes from the environment variable CHAOS_LIVE_PASSWORD, never from the arguments. Keys: CHAOS_CLIENT_KEY (guard key, 64 hex
// digits) and CHAOS_RSA_PUBLIC (the server's RSA modulus in decimal), both optional, the same variables the Unity client reads.
// Logs in, enters the game, parses every packet for N seconds with the Core parser, walks in 8 directions, sends the open request of every
// extended opcode Unity handles and writes a JSON and a text report (unity/README.md "Live check (O433)"). Exit 0 when the login, the entry and
// the walk worked and the parser had no error; 1 otherwise; 2 on a usage error.
using System;
using System.IO;

namespace Chaos.Core.LiveCheck
{
    static class Program
    {
        static int Usage(string why)
        {
            if (why != null) Console.Error.WriteLine(why);
            Console.Error.WriteLine("usage: Core.LiveCheck HOST LOGIN_PORT ACCOUNT [CHARACTER|-] [--seconds N] [--report FILE] [--identity extended|chaos]");
            Console.Error.WriteLine("                      [--otb items.otb | --pair DIR] [--no-ext]   (password: environment variable CHAOS_LIVE_PASSWORD)");
            Console.Error.WriteLine("                      [--scenario newplayer,questlog,firstunlock,firstkill,firstquest,tooltip,stairs,floorchange,npc,sell,market,modal,moremodals,party,sharedkill,rift,riftboss,partyrift,rifttier,riftfail,omen,coffer,guardians,partnerdeath,lastlife,party3,trialwindows,riftsolodeath,riftkilled,omenparty,wrathnova,death,pvpdeath|all] [--items-xml FILE] [--npc NAME] [--npc-at X,Y,Z] [--stairs-at X,Y,Z]");
            Console.Error.WriteLine("                      [--rift-tier N] [--rift-mods name:value,...] [--keeper-at X,Y,Z]");
            Console.Error.WriteLine("                      [--guardian-tier N] [--twin-mods name:value,...] [--wrath-mods name:value,...] [--guardian-parts twin,wrath] [--hit-size N] [--reflect-probe tier|rift] [--archivist-at X,Y,Z]   (third account: CHAOS_LIVE_ACCOUNT3, CHAOS_LIVE_PASSWORD3, CHAOS_LIVE_CHARACTER3)");
            Console.Error.WriteLine("                      [--modal-npc NAME] [--modal-word WORD] [--modal-at X,Y,Z] [--rift-kill /CMD] [--rift-near /CMD]");
            Console.Error.WriteLine("                      [--killer MONSTER] [--weak MONSTER] [--rift-key-id N] [--scenario-seconds N] [--aware WxH]   (second account: CHAOS_LIVE_ACCOUNT2, CHAOS_LIVE_PASSWORD2, CHAOS_LIVE_CHARACTER2)");
            return 2;
        }

        static Pos ParsePos(string t)
        {
            var parts = t.Split(',');
            if (parts.Length != 3) throw new ArgumentException("a position is X,Y,Z: " + t);
            return new Pos(int.Parse(parts[0]), int.Parse(parts[1]), int.Parse(parts[2]));
        }

        static int Main(string[] args)
        {
            var o = new LiveOptions();
            int pos = 0;
            for (int i = 0; i < args.Length; i++)
            {
                string a = args[i];
                string Next() => i + 1 < args.Length ? args[++i] : throw new ArgumentException(a + " needs a value");
                try
                {
                    switch (a)
                    {
                        case "--seconds": o.Seconds = Math.Max(1, int.Parse(Next())); break;
                        case "--report": o.Report = Next(); break;
                        case "--identity": o.Chaos = Next().Equals("chaos", StringComparison.OrdinalIgnoreCase); break;
                        case "--otb": o.OtbFile = Next(); break;
                        case "--pair": o.PairDir = Next(); break;
                        case "--no-ext": o.SkipExt = true; break;
                        case "--scenario":
                            foreach (string n in Next().Split(',', StringSplitOptions.RemoveEmptyEntries))
                            {
                                string name = n.Trim().ToLowerInvariant();
                                if (name != "all" && Array.IndexOf(LiveRun.AllScenarios, name) < 0) return Usage("unknown scenario " + name + " (" + string.Join(", ", LiveRun.AllScenarios) + ", all)");
                                if (!o.Scenarios.Contains(name)) o.Scenarios.Add(name);
                            }
                            break;
                        case "--items-xml": o.ItemsXml = Next(); break;
                        case "--npc": o.NpcName = Next(); break;
                        case "--npc-at": o.NpcAt = ParsePos(Next()); break;
                        case "--stairs-at": o.StairsAt = ParsePos(Next()); break;
                        case "--killer": o.Killer = Next(); break;
                        case "--weak": o.Weak = Next(); break;
                        case "--modal-npc": o.ModalNpc = Next(); break;
                        case "--modal-word": o.ModalWord = Next(); break;
                        case "--modal-at": o.ModalAt = ParsePos(Next()); break;
                        case "--rift-kill": o.RiftKill = Next(); break;
                        case "--rift-near": o.RiftNear = Next(); break;
                        case "--rift-tier": o.RiftTier = Math.Max(1, int.Parse(Next())); break;
                        case "--rift-mods": o.RiftMods = Next(); break;
                        case "--keeper-at": o.KeeperAt = ParsePos(Next()); break;
                        case "--archivist-at": o.ArchivistAt = ParsePos(Next()); break;
                        case "--guardian-tier": o.GuardianTier = Math.Max(1, int.Parse(Next())); break;
                        case "--twin-mods": o.TwinMods = Next(); break;
                        case "--wrath-mods": o.WrathMods = Next(); break;
                        case "--guardian-parts": o.GuardianParts = Next().ToLowerInvariant(); break;
                        case "--reflect-probe": o.ReflectProbe = Next().ToLowerInvariant() == "rift" ? "rift" : "tier"; break;
                        case "--hit-size": o.HitSize = Math.Max(0, int.Parse(Next())); break;
                        case "--rift-key-id": o.RiftKeyServerId = int.Parse(Next()); break;
                        case "--scenario-seconds": o.ScenarioMs = Math.Max(5, int.Parse(Next())) * 1000; break;
                        case "--aware":
                        {
                            var wh = Next().Split('x');
                            if (wh.Length != 2) return Usage("--aware needs WxH, for example 29x21");
                            o.AwareWidth = int.Parse(wh[0]); o.AwareHeight = int.Parse(wh[1]);
                            break;
                        }
                        default:
                            if (a.StartsWith("--", StringComparison.Ordinal)) return Usage("unknown option " + a);
                            switch (pos++)
                            {
                                case 0: o.Host = a; break;
                                case 1: o.Port = int.Parse(a); break;
                                case 2: o.Account = a; break;
                                case 3: o.Character = a == "-" ? null : a; break;
                                default: return Usage("too many arguments");
                            }
                            break;
                    }
                }
                catch (Exception e) when (e is FormatException || e is ArgumentException || e is OverflowException) { return Usage(e.Message); }
            }
            if (pos < 3) return Usage(null);
            o.Account2 = Environment.GetEnvironmentVariable("CHAOS_LIVE_ACCOUNT2");
            o.Password2 = Environment.GetEnvironmentVariable("CHAOS_LIVE_PASSWORD2");
            o.Character2 = Environment.GetEnvironmentVariable("CHAOS_LIVE_CHARACTER2");
            if (string.IsNullOrEmpty(o.Character2)) o.Character2 = null;
            o.Account3 = Environment.GetEnvironmentVariable("CHAOS_LIVE_ACCOUNT3");
            o.Password3 = Environment.GetEnvironmentVariable("CHAOS_LIVE_PASSWORD3");
            o.Character3 = Environment.GetEnvironmentVariable("CHAOS_LIVE_CHARACTER3");
            if (string.IsNullOrEmpty(o.Character3)) o.Character3 = null;
            o.Password = Environment.GetEnvironmentVariable("CHAOS_LIVE_PASSWORD");
            if (string.IsNullOrEmpty(o.Password)) return Usage("set CHAOS_LIVE_PASSWORD");
            string keyText = Environment.GetEnvironmentVariable("CHAOS_CLIENT_KEY");
            if (!string.IsNullOrEmpty(keyText))
            {
                o.GuardKey = ClientGuard.ParseKey(keyText);
                if (o.GuardKey == null) return Usage("CHAOS_CLIENT_KEY must be 64 hex digits");
            }
            string rsa = Environment.GetEnvironmentVariable("CHAOS_RSA_PUBLIC");
            if (!string.IsNullOrEmpty(rsa)) o.Rsa = rsa.Trim();

            DatFile dat;
            string datSource;
            try
            {
                if (o.PairDir != null) { dat = DatFile.Load(Path.Combine(o.PairDir, "Tibia.dat")); datSource = "pair"; }
                else if (o.OtbFile != null) { dat = OtbDat.Build(File.ReadAllBytes(o.OtbFile)); datSource = "otb"; }
                else return Usage("give --otb items.otb (server) or --pair DIR (Tibia.dat): the parser needs the item types");
            }
            catch (Exception e) when (e is IOException || e is ProtocolException || e is InvalidDataException) { return Usage("item types: " + e.Message); }

            var run = new LiveRun(o, dat, datSource);
            int code = run.Execute();
            Console.WriteLine(run.TextReport());
            if (o.Report != null)
            {
                File.WriteAllText(o.Report, Json.Serialize(run.JsonReport()) + "\n");
                File.WriteAllText(Path.ChangeExtension(o.Report, ".txt"), run.TextReport());
                Console.WriteLine("report: " + o.Report + " and " + Path.ChangeExtension(o.Report, ".txt"));
            }
            return code;
        }
    }
}
