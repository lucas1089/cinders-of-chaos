// The 10.98 wire protocol as the Cinders of Chaos server speaks it (stock TFS 1.4.2 framing plus our patches):
// framing, the login and game login packets, and a TCP connection that reads packets on a background thread.
// Byte layouts: docs in unity/README.md "Protocol"; reference implementations server/tools/loadtest.py (login,
// guard, walk) and server/tools/cast_relay.py (the server stream as our client reads it).
using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Net.Sockets;
using System.Security.Cryptography;
using System.Threading;
using System.Threading.Tasks;

namespace Chaos.Core
{
    public static partial class Protocol
    {
        public const ushort Version = 1098;

        /// <summary>The standard open-server RSA modulus (public). The live server has its own key (src-patch 0046):
        /// the build takes it from CHAOS_RSA_PUBLIC, the login screen can override it.</summary>
        public const string OpenRsaModulus =
            "1091201329673994292788609605089955415282375029027981291234687579" +
            "3726629149257644633073969600111060390723088861007265581882535850" +
            "3429057592827629436413108566029093628212635953836686562675849720" +
            "6207862794310902180176810615217550567108238764764442605581471797" +
            "07119674283982419152118103759076030616683978566631413";
        /// <summary>OS byte of the login packets: >= 10 is what the client guard wants (21 = our client on Linux).</summary>
        public const ushort Os = 21;

        /// <summary>u16 size, u32 adler32 of the body, body.</summary>
        public static byte[] Frame(byte[] body)
        {
            return new ByteWriter().U16((ushort)(body.Length + 4)).U32(Adler32.Of(body, 0, body.Length)).Raw(body).ToArray();
        }

        /// <summary>The encrypted packet of one payload: frame(XTEA(u16 length, payload, padding)).</summary>
        public static byte[] Encrypt(byte[] payload, uint[] key)
        {
            var w = new ByteWriter().U16((ushort)payload.Length).Raw(payload);
            int pad = (8 - w.Length % 8) % 8;
            for (int i = 0; i < pad; i++) w.U8(0x33);
            byte[] inner = w.ToArray();
            Xtea.Encrypt(inner, 0, inner.Length, key);
            return Frame(inner);
        }

        /// <summary>The payload of a packet body (the bytes after the u16 size): checksum checked, XTEA decrypted.</summary>
        public static byte[] Decrypt(byte[] body, uint[] key)
        {
            if (body.Length < 12 || (body.Length - 4) % 8 != 0) throw new ProtocolException("bad encrypted packet size " + body.Length);
            uint sum = (uint)(body[0] | body[1] << 8 | body[2] << 16 | body[3] << 24);
            if (sum == 0) throw new ProtocolException("a compressed packet (the prototype never asks for compression)");
            if (sum != Adler32.Of(body, 4, body.Length - 4)) throw new ProtocolException("packet checksum mismatch");
            var inner = new byte[body.Length - 4];
            Array.Copy(body, 4, inner, 0, inner.Length);
            Xtea.Decrypt(inner, 0, inner.Length, key);
            int n = inner[0] | inner[1] << 8;
            if (n + 2 > inner.Length) throw new ProtocolException("inner length " + n + " beyond the packet");
            var payload = new byte[n];
            Array.Copy(inner, 2, payload, 0, n);
            return payload;
        }

        public static uint[] NewXteaKey()
        {
            var b = new byte[16];
            using (var rng = RandomNumberGenerator.Create()) rng.GetBytes(b);
            var k = new uint[4];
            for (int i = 0; i < 4; i++) k[i] = (uint)(b[4 * i] | b[4 * i + 1] << 8 | b[4 * i + 2] << 16 | b[4 * i + 3] << 24);
            return k;
        }

        static byte[] RsaBlock(Rsa rsa, ByteWriter plain)
        {
            if (plain.Length > rsa.Size) throw new ProtocolException("login data too long for one RSA block (shorter names)");
            byte[] block = new byte[rsa.Size];
            var rnd = new byte[rsa.Size];
            using (var rng = RandomNumberGenerator.Create()) rng.GetBytes(rnd);
            Array.Copy(rnd, block, rsa.Size);   // the real client pads with random bytes
            Array.Copy(plain.ToArray(), block, plain.Length);
            return rsa.Encrypt(block);
        }

        /// <summary>Talk on the default channel: 0x96, talk type 1 (say), the text.</summary>
        public static byte[] SayPacket(string text) => new ByteWriter().U8(0x96).U8(1).Str(text).ToArray();

        /// <summary>The first packet on the login port (src-patch 0021: clientId = guard identifier).</summary>
        public static byte[] LoginPacket(Rsa rsa, uint[] xtea, string account, string password, uint clientId)
        {
            var b1 = new ByteWriter().U8(0);
            foreach (uint k in xtea) b1.U32(k);
            b1.Str(account).Str(password).U16(0);   // u16 0: no client markers
            var b2 = new ByteWriter().U8(0).Str("").U8(0);   // no auth token, not stay-logged
            var body = new ByteWriter().U8(0x01).U16(Os).U16(Version).U32(clientId).U32(0).U32(0).U32(0).U8(0);
            body.Raw(RsaBlock(rsa, b1)).Raw(RsaBlock(rsa, b2));
            return Frame(body.ToArray());
        }

        /// <summary>The first packet on the game port, answering the challenge. Markers: u16 0 (option B of the spec:
        /// no feature list, outfits without wings / aura / shader, one 0x64 map, no item attributes, no compression).</summary>
        public static byte[] GameLoginPacket(Rsa rsa, uint[] xtea, string sessionKey, string character, uint clientId,
                                             uint timestamp, byte random)
        {
            var b = new ByteWriter().U8(0);
            foreach (uint k in xtea) b.U32(k);
            b.U8(0).Str(sessionKey).Str(character).U32(timestamp).U8(random).U16(0);
            var body = new ByteWriter().U8(0x0A).U16(Os).U16(Version).U32(clientId).U16(0).U8(0);
            body.Raw(RsaBlock(rsa, b));
            return Frame(body.ToArray());
        }
    }

    /// <summary>One TCP connection with the protocol's framing; packets are read on a background thread.</summary>
    public sealed class Connection : IDisposable
    {
        readonly TcpClient tcp;
        readonly NetworkStream stream;
        readonly object sendGate = new object();
        public uint[] Key;   // XTEA once the login packet is sent
        public readonly ConcurrentQueue<byte[]> Received = new ConcurrentQueue<byte[]>();   // raw bodies (after u16 size)
        public volatile string Error;
        public volatile bool Closed;
        Thread reader;

        Connection(TcpClient t)
        {
            tcp = t;
            tcp.NoDelay = true;
            stream = tcp.GetStream();
        }

        public static async Task<Connection> Open(string host, int port, int timeoutMs = 10000)
        {
            var t = new TcpClient();
            var connect = t.ConnectAsync(host, port);
            if (await Task.WhenAny(connect, Task.Delay(timeoutMs)) != connect)
            {
                t.Dispose();
                throw new ProtocolException("no answer from " + host + ":" + port);
            }
            await connect;
            return new Connection(t);
        }

        public void SendRaw(byte[] packet)
        {
            lock (sendGate) stream.Write(packet, 0, packet.Length);
        }

        public void Send(byte[] payload) { SendRaw(Protocol.Encrypt(payload, Key)); }

        byte[] ReadExactly(int n)
        {
            var b = new byte[n];
            int got = 0;
            while (got < n)
            {
                int k = stream.Read(b, got, n - got);
                if (k <= 0) return null;
                got += k;
            }
            return b;
        }

        /// <summary>One packet body, blocking; null when the server closed the connection.</summary>
        public byte[] ReadBody()
        {
            byte[] head = ReadExactly(2);
            if (head == null) return null;
            int size = head[0] | head[1] << 8;
            if (size == 0) throw new ProtocolException("empty packet");
            return ReadExactly(size);
        }

        public void StartReading()
        {
            reader = new Thread(() =>
            {
                try
                {
                    while (true)
                    {
                        byte[] body = ReadBody();
                        if (body == null) break;
                        Received.Enqueue(body);
                    }
                }
                catch (Exception e)
                {
                    if (!Closed) Error = e.Message;
                }
                Closed = true;
            }) { IsBackground = true, Name = "chaos-net" };
            reader.Start();
        }

        public void Dispose()
        {
            Closed = true;
            try { tcp.Close(); } catch (Exception) { }
        }
    }

    public sealed class CharacterEntry
    {
        public string Name, World, Host;
        public int Port, Level, Vocation;
        public Outfit Outfit;
    }

    public sealed class LoginResult
    {
        public string Error, Motd, SessionKey;
        public readonly List<CharacterEntry> Characters = new List<CharacterEntry>();
    }

    public static class LoginClient
    {
        /// <summary>Account login on the login port: the session key and the character list, or an error text.</summary>
        public static async Task<LoginResult> Login(string host, int port, string account, string password,
                                                    string rsaModulus = Protocol.OpenRsaModulus, ushort build = 30)
        {
            var key = Protocol.NewXteaKey();
            var rsa = new Rsa(rsaModulus);
            using (var c = await Connection.Open(host, port))
            {
                c.Key = key;
                c.SendRaw(Protocol.LoginPacket(rsa, key, account, password, ClientGuard.Identifier(build)));
                return await Task.Run(() =>
                {
                    var res = new LoginResult();
                    while (true)
                    {
                        byte[] body;
                        try { body = c.ReadBody(); }
                        catch (System.IO.IOException) { body = null; }
                        if (body == null) break;
                        ParseLogin(Protocol.Decrypt(body, key), res);
                        if (res.Error != null || res.SessionKey != null && res.Characters.Count > 0) break;
                    }
                    if (res.Error == null && res.SessionKey == null)
                        res.Error = "The login server closed the connection (wrong server key or client build?)";
                    return res;
                });
            }
        }

        public static void ParseLogin(byte[] payload, LoginResult res)
        {
            var r = new ByteReader(payload);
            while (!r.AtEnd)
            {
                byte op = r.U8();
                switch (op)
                {
                    case 0x0B: case 0x0A: res.Error = r.Str(); return;
                    case 0x0C: case 0x0D: r.U8(); break;
                    case 0x14: res.Motd = r.Str(); break;
                    case 0x28: res.SessionKey = r.Str(); break;
                    case 0x64:
                        var worlds = new Dictionary<int, (string name, string host, int port)>();
                        int nw = r.U8();
                        for (int i = 0; i < nw; i++)
                        {
                            int id = r.U8();
                            string name = r.Str(), host = r.Str();
                            int port = r.U16();
                            r.U8();
                            worlds[id] = (name, host, port);
                        }
                        int nc = r.U8();
                        for (int i = 0; i < nc; i++)
                        {
                            int wid = r.U8();
                            var ch = new CharacterEntry { Name = r.Str(), Level = (int)r.U32(), Vocation = r.U16() };
                            ch.Outfit = new Outfit { LookType = r.U16() };
                            if (ch.Outfit.LookType != 0)
                            {
                                ch.Outfit.Head = r.U8(); ch.Outfit.Body = r.U8(); ch.Outfit.Legs = r.U8(); ch.Outfit.Feet = r.U8(); ch.Outfit.Addons = r.U8();
                            }
                            else ch.Outfit.LookTypeEx = r.U16();
                            ch.Outfit.Mount = r.U16();
                            if (worlds.TryGetValue(wid, out var w)) { ch.World = w.name; ch.Host = w.host; ch.Port = w.port; }
                            res.Characters.Add(ch);
                        }
                        r.U8(); r.U8(); r.U32();   // account status, premium, premium end
                        break;
                    default:
                        return;   // something newer: the session key and list are what we need
                }
            }
        }
    }
}
