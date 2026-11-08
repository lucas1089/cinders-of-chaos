// Extended opcodes (0x32 both ways, the way every Chaos module talks to the server): a small JSON reader and writer, the
// chunked protocol (server Chaos.sendChunked, client modules/gamelib/protocolgame.lua onExtendedOpcode, base patch
// 0043) and a dispatcher by opcode. No library: Unity 2022 has no System.Text.Json by default.
//
// Wire: 0x32, u8 opcode, u16 length, bytes. The bytes are UTF-8 text. ByteReader.Str reads them as Latin-1 (one char per
// byte), so ExtOpcodes.Receive takes that "wire string" and turns it back into UTF-16; Send writes the UTF-8 bytes itself.
// Message: JSON {"action": text, "data": anything}. Over 8192 bytes the server sends parts: "S" + text (start), "P" +
// text (part), "E" + text (end); a payload that fits goes out as it is and starts with "{". The client sends one string
// (the server drops a request over 16384 bytes, patch 0075 / Chaos.opcodeRequestMax) and never chunks.
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Text;

namespace Chaos.Core
{
    /// <summary>JSON values as plain C# objects: null, bool, double, string, List&lt;object&gt;, Dictionary&lt;string, object&gt;.</summary>
    public static class Json
    {
        public const int MaxDepth = 64;

        public sealed class JsonException : Exception
        {
            public JsonException(string message) : base(message) { }
        }

        // ------------------------------------------------------------------------------------ parse
        /// <summary>Parses one JSON value; text after it (but spaces) is an error. Throws JsonException.</summary>
        public static object Parse(string text)
        {
            if (text == null) throw new JsonException("no text");
            int i = 0;
            Space(text, ref i);
            object v = Value(text, ref i, 0);
            Space(text, ref i);
            if (i != text.Length) throw new JsonException("text after the value at " + i);
            return v;
        }

        /// <summary>Parse, or null when the text is not JSON (the way Chaos.decode answers nil).</summary>
        public static object TryParse(string text)
        {
            try { return Parse(text); }
            catch (JsonException) { return null; }
        }

        static void Space(string s, ref int i)
        {
            while (i < s.Length && (s[i] == ' ' || s[i] == '\t' || s[i] == '\n' || s[i] == '\r')) i++;
        }

        static object Value(string s, ref int i, int depth)
        {
            if (depth > MaxDepth) throw new JsonException("nested deeper than " + MaxDepth);
            if (i >= s.Length) throw new JsonException("the text ends early");
            char c = s[i];
            switch (c)
            {
                case '{': return Obj(s, ref i, depth);
                case '[': return Arr(s, ref i, depth);
                case '"': return Str(s, ref i);
                case 't': Word(s, ref i, "true"); return true;
                case 'f': Word(s, ref i, "false"); return false;
                case 'n': Word(s, ref i, "null"); return null;
                default:
                    if (c == '-' || (c >= '0' && c <= '9')) return Num(s, ref i);
                    throw new JsonException("unexpected '" + c + "' at " + i);
            }
        }

        static void Word(string s, ref int i, string w)
        {
            if (string.CompareOrdinal(s, i, w, 0, w.Length) != 0) throw new JsonException("bad word at " + i);
            i += w.Length;
        }

        static object Num(string s, ref int i)
        {
            int start = i;
            if (s[i] == '-') i++;
            int digits = 0;
            while (i < s.Length && s[i] >= '0' && s[i] <= '9') { i++; digits++; }
            if (digits == 0) throw new JsonException("bad number at " + start);
            if (i < s.Length && s[i] == '.')
            {
                i++;
                int frac = 0;
                while (i < s.Length && s[i] >= '0' && s[i] <= '9') { i++; frac++; }
                if (frac == 0) throw new JsonException("bad number at " + start);
            }
            if (i < s.Length && (s[i] == 'e' || s[i] == 'E'))
            {
                i++;
                if (i < s.Length && (s[i] == '+' || s[i] == '-')) i++;
                int exp = 0;
                while (i < s.Length && s[i] >= '0' && s[i] <= '9') { i++; exp++; }
                if (exp == 0) throw new JsonException("bad number at " + start);
            }
            double v;
            if (!double.TryParse(s.Substring(start, i - start), NumberStyles.Float, CultureInfo.InvariantCulture, out v) ||
                double.IsInfinity(v) || double.IsNaN(v))
                throw new JsonException("bad number at " + start);
            return v;
        }

        static string Str(string s, ref int i)
        {
            i++;   // the opening quote
            var sb = new StringBuilder();
            while (true)
            {
                if (i >= s.Length) throw new JsonException("a string is not closed");
                char c = s[i++];
                if (c == '"') return sb.ToString();
                if (c < 0x20) throw new JsonException("a control character in a string at " + (i - 1));
                if (c != '\\') { sb.Append(c); continue; }
                if (i >= s.Length) throw new JsonException("a string is not closed");
                char e = s[i++];
                switch (e)
                {
                    case '"': sb.Append('"'); break;
                    case '\\': sb.Append('\\'); break;
                    case '/': sb.Append('/'); break;
                    case 'b': sb.Append('\b'); break;
                    case 'f': sb.Append('\f'); break;
                    case 'n': sb.Append('\n'); break;
                    case 'r': sb.Append('\r'); break;
                    case 't': sb.Append('\t'); break;
                    case 'u':
                        if (i + 4 > s.Length) throw new JsonException("bad \\u escape at " + i);
                        int code;
                        if (!int.TryParse(s.Substring(i, 4), NumberStyles.AllowHexSpecifier, CultureInfo.InvariantCulture, out code))
                            throw new JsonException("bad \\u escape at " + i);
                        i += 4;
                        sb.Append((char)code);   // a surrogate pair arrives as two escapes: two chars, the pair
                        break;
                    default: throw new JsonException("bad escape \\" + e + " at " + (i - 1));
                }
            }
        }

        static List<object> Arr(string s, ref int i, int depth)
        {
            i++;
            var list = new List<object>();
            Space(s, ref i);
            if (i < s.Length && s[i] == ']') { i++; return list; }
            while (true)
            {
                Space(s, ref i);
                list.Add(Value(s, ref i, depth + 1));
                Space(s, ref i);
                if (i >= s.Length) throw new JsonException("an array is not closed");
                if (s[i] == ',') { i++; continue; }
                if (s[i] == ']') { i++; return list; }
                throw new JsonException("expected , or ] at " + i);
            }
        }

        static Dictionary<string, object> Obj(string s, ref int i, int depth)
        {
            i++;
            var map = new Dictionary<string, object>();
            Space(s, ref i);
            if (i < s.Length && s[i] == '}') { i++; return map; }
            while (true)
            {
                Space(s, ref i);
                if (i >= s.Length || s[i] != '"') throw new JsonException("expected a key at " + i);
                string key = Str(s, ref i);
                Space(s, ref i);
                if (i >= s.Length || s[i] != ':') throw new JsonException("expected : at " + i);
                i++;
                Space(s, ref i);
                map[key] = Value(s, ref i, depth + 1);
                Space(s, ref i);
                if (i >= s.Length) throw new JsonException("an object is not closed");
                if (s[i] == ',') { i++; continue; }
                if (s[i] == '}') { i++; return map; }
                throw new JsonException("expected , or } at " + i);
            }
        }

        // ------------------------------------------------------------------------------------ write
        /// <summary>Compact JSON of null, bool, numbers, string, IEnumerable (an array) and IDictionary with string keys.
        /// Whole numbers are written without a fraction. Keys of a Dictionary come out in its order.</summary>
        public static string Serialize(object v)
        {
            var sb = new StringBuilder();
            Write(sb, v, 0);
            return sb.ToString();
        }

        static void Write(StringBuilder sb, object v, int depth)
        {
            if (depth > MaxDepth) throw new JsonException("nested deeper than " + MaxDepth);
            switch (v)
            {
                case null: sb.Append("null"); return;
                case bool b: sb.Append(b ? "true" : "false"); return;
                case string s: Quote(sb, s); return;
                case double d: Number(sb, d); return;
                case float f: Number(sb, f); return;
                case int n: sb.Append(n.ToString(CultureInfo.InvariantCulture)); return;
                case long n: sb.Append(n.ToString(CultureInfo.InvariantCulture)); return;
                case uint n: sb.Append(n.ToString(CultureInfo.InvariantCulture)); return;
                case ulong n: sb.Append(n.ToString(CultureInfo.InvariantCulture)); return;
                case short n: sb.Append(n.ToString(CultureInfo.InvariantCulture)); return;
                case ushort n: sb.Append(n.ToString(CultureInfo.InvariantCulture)); return;
                case byte n: sb.Append(n.ToString(CultureInfo.InvariantCulture)); return;
                case System.Collections.IDictionary map:
                {
                    sb.Append('{');
                    bool first = true;
                    foreach (System.Collections.DictionaryEntry e in map)
                    {
                        if (!first) sb.Append(',');
                        first = false;
                        Quote(sb, Convert.ToString(e.Key, CultureInfo.InvariantCulture));
                        sb.Append(':');
                        Write(sb, e.Value, depth + 1);
                    }
                    sb.Append('}');
                    return;
                }
                case System.Collections.IEnumerable list:
                {
                    sb.Append('[');
                    bool first = true;
                    foreach (object o in list)
                    {
                        if (!first) sb.Append(',');
                        first = false;
                        Write(sb, o, depth + 1);
                    }
                    sb.Append(']');
                    return;
                }
                default: throw new JsonException("cannot write a " + v.GetType().Name);
            }
        }

        static void Number(StringBuilder sb, double d)
        {
            if (double.IsNaN(d) || double.IsInfinity(d)) throw new JsonException("cannot write " + d);
            if (d == Math.Floor(d) && Math.Abs(d) < 9007199254740992.0) sb.Append(((long)d).ToString(CultureInfo.InvariantCulture));
            else sb.Append(d.ToString("R", CultureInfo.InvariantCulture));
        }

        static void Quote(StringBuilder sb, string s)
        {
            sb.Append('"');
            foreach (char c in s)
            {
                switch (c)
                {
                    case '"': sb.Append("\\\""); break;
                    case '\\': sb.Append("\\\\"); break;
                    case '\n': sb.Append("\\n"); break;
                    case '\r': sb.Append("\\r"); break;
                    case '\t': sb.Append("\\t"); break;
                    case '\b': sb.Append("\\b"); break;
                    case '\f': sb.Append("\\f"); break;
                    default:
                        if (c < 0x20) sb.Append("\\u").Append(((int)c).ToString("x4", CultureInfo.InvariantCulture));
                        else sb.Append(c);
                        break;
                }
            }
            sb.Append('"');
        }

        // ------------------------------------------------------------------------------------ read helpers
        public static object Get(object o, string key)
        {
            return o is Dictionary<string, object> m && m.TryGetValue(key, out var v) ? v : null;
        }

        public static string Text(object o, string key, string fallback = "")
        {
            var v = Get(o, key);
            return v is string s ? s : v is double d && !double.IsNaN(d) && !double.IsInfinity(d) ? NumberText(d) : fallback;
        }

        /// <summary>A number as text the way Lua's tostring writes a whole number (12, not 12.0).</summary>
        public static string NumberText(double d) => d == Math.Floor(d) && Math.Abs(d) < 1e15 ? ((long)d).ToString(CultureInfo.InvariantCulture) : d.ToString("R", CultureInfo.InvariantCulture);

        /// <summary>A number as the server may send it: a JSON number, or a numeric string ("12", "1.5": storage values and
        /// tostring() results reach the wire as text). Null when it is neither.</summary>
        public static double? AsNumber(object v)
        {
            if (v is double d) return d;
            if (v is string s && s.Length > 0 && s.Length < 40 && double.TryParse(s.Trim(), NumberStyles.Float, CultureInfo.InvariantCulture, out var x) && !double.IsNaN(x) && !double.IsInfinity(x)) return x;
            return null;
        }

        public static double Number(object o, string key, double fallback = 0)
        {
            return AsNumber(Get(o, key)) ?? fallback;
        }

        public static int Int(object o, string key, int fallback = 0)
        {
            var n = AsNumber(Get(o, key));
            return n is double d && !double.IsNaN(d) ? (int)Math.Max(int.MinValue, Math.Min(int.MaxValue, d)) : fallback;
        }

        public static bool Bool(object o, string key, bool fallback = false)
        {
            return Get(o, key) is bool b ? b : fallback;
        }

        /// <summary>A flag as the server may send it: the Lua JSON encoder writes true/false for booleans, but many payloads carry
        /// 1/0 (done = 1, open = 1, pw = 1), and a few strings ("1", "true"). True for true, a nonzero number, "1" or "true" (any case);
        /// false for false, 0, NaN and any other string; null, lists and objects give the fallback. Json.Bool is strict (only a JSON
        /// boolean) and is for reading what this client wrote itself.</summary>
        public static bool Truthy(object v, bool fallback = false)
        {
            switch (v)
            {
                case bool b: return b;
                case double d: return !double.IsNaN(d) && d != 0;
                case string s:
                    s = s.Trim();
                    return s == "1" || s.Equals("true", StringComparison.OrdinalIgnoreCase);
                default: return fallback;
            }
        }

        public static bool Truthy(object o, string key, bool fallback = false) => Truthy(Get(o, key), fallback);

        public static List<object> List(object o, string key)
        {
            var v = Get(o, key);
            if (v is List<object> l) return l;
            // an array the encoder wrote as an object because its keys are the strings "1", "2", ...: its values in key order
            if (v is Dictionary<string, object> m && m.Count > 0)
            {
                var keys = new List<KeyValuePair<int, object>>();
                foreach (var kv in m)
                {
                    if (!int.TryParse(kv.Key, NumberStyles.None, CultureInfo.InvariantCulture, out int i)) return new List<object>();
                    keys.Add(new KeyValuePair<int, object>(i, kv.Value));
                }
                keys.Sort((a, b) => a.Key.CompareTo(b.Key));
                var o2 = new List<object>(keys.Count);
                foreach (var kv in keys) o2.Add(kv.Value);
                return o2;
            }
            return new List<object>();
        }
    }

    /// <summary>A decoded {action, data} message of one opcode.</summary>
    public sealed class ExtMessage
    {
        public byte Opcode;
        public string Action = "";
        /// <summary>The "data" member (a Json value), null when missing.</summary>
        public object Data;
        /// <summary>The whole decoded object.</summary>
        public object Root;
        public override string ToString() => Opcode + " " + Action;
    }

    /// <summary>Joins the parts of a chunked message, per opcode, exactly as the main client does (protocolgame.lua
    /// onExtendedOpcode with base patch 0043).</summary>
    public sealed class ExtChunks
    {
        /// <summary>The most text one message may reach (the main client has no limit; the biggest the server sends is about 25 KB).</summary>
        public int MaxChars = 4 * 1024 * 1024;
        readonly Dictionary<byte, StringBuilder> open = new Dictionary<byte, StringBuilder>();
        /// <summary>A part came with no start before it and was dropped (the main client logs a warning).</summary>
        public int Dropped;

        /// <summary>Takes one wire string; returns the whole text when a message is complete, else null.</summary>
        public string Feed(byte opcode, string buffer)
        {
            char status = buffer.Length > 0 ? buffer[0] : '\0';
            bool isS = status == 'S', isP = status == 'P', isE = status == 'E';
            if (!isS && !isP && !isE)
            {
                open.Remove(opcode);   // one whole message; a chain that was open is forgotten
                return buffer;
            }
            if (isS) open[opcode] = new StringBuilder();
            if (!open.TryGetValue(opcode, out var sb)) { Dropped++; return null; }
            if (sb.Length + buffer.Length - 1 > MaxChars)
            {
                open.Remove(opcode);
                Dropped++;
                return null;
            }
            sb.Append(buffer, 1, buffer.Length - 1);
            if (isE)
            {
                open.Remove(opcode);
                return sb.ToString();
            }
            return null;
        }

        public void Reset() { open.Clear(); }

        /// <summary>The parts the server's Chaos.splitExtended makes of a text: itself when it fits in 8192 bytes, else "S", "P"... "E"
        /// parts of 8000 bytes (the server cuts bytes, so a test passes the text as a wire string of one char per byte).</summary>
        public static List<string> Split(string wire, int max = 8192, int size = 8000)
        {
            var parts = new List<string>();
            if (wire.Length <= max) { parts.Add(wire); return parts; }
            size = Math.Min(size, max - 1);
            for (int i = 0; i < wire.Length; i += size) parts.Add(wire.Substring(i, Math.Min(size, wire.Length - i)));
            for (int i = 0; i < parts.Count; i++) parts[i] = (i == 0 ? "S" : i == parts.Count - 1 ? "E" : "P") + parts[i];
            return parts;
        }
    }

    /// <summary>The extended opcode layer of one connection: sends {action, data}, joins chunks, decodes and hands each
    /// message to the handlers of its opcode. Single-threaded: call Receive from the thread that polls the session.</summary>
    public sealed class ExtOpcodes
    {
        /// <summary>The server drops a request over this many bytes (Chaos.opcodeRequestMax).</summary>
        public const int MaxRequestBytes = 16384;

        readonly ExtChunks chunks = new ExtChunks();
        readonly Dictionary<byte, List<Action<ExtMessage>>> handlers = new Dictionary<byte, List<Action<ExtMessage>>>();
        readonly Dictionary<byte, List<Action<string>>> raw = new Dictionary<byte, List<Action<string>>>();
        /// <summary>Puts one packet payload (0x32 ...) on the wire. GameSession sets it to the encrypted connection.</summary>
        public Action<byte[]> Transmit = delegate { };
        /// <summary>Errors worth a log line: invalid JSON, a handler that threw. The rest of the messages go on.</summary>
        public Action<string> Log = delegate { };
        public int Received, Sent, Invalid;

        public ExtChunks Chunks => chunks;

        /// <summary>A handler for the decoded {action, data} messages of an opcode (the main client's registerExtendedJSONOpcode).
        /// Several handlers may share an opcode, in the order they were added.</summary>
        public void On(byte opcode, Action<ExtMessage> handler)
        {
            if (!handlers.TryGetValue(opcode, out var list)) handlers[opcode] = list = new List<Action<ExtMessage>>();
            list.Add(handler);
        }

        /// <summary>A handler for the plain text of an opcode (registerExtendedOpcode): energy shield "es:cur:max", monk chi
        /// "chi:..", the guard. Chunk parts are not joined for it, as in the main client.</summary>
        public void OnText(byte opcode, Action<string> handler)
        {
            if (!raw.TryGetValue(opcode, out var list)) raw[opcode] = list = new List<Action<string>>();
            list.Add(handler);
        }

        public bool Handles(byte opcode) => handlers.ContainsKey(opcode) || raw.ContainsKey(opcode);

        /// <summary>One 0x32 message as GameParser reads it: the opcode and the Latin-1 "wire string" of its bytes.</summary>
        public void Receive(byte opcode, string wire)
        {
            Received++;
            if (raw.TryGetValue(opcode, out var plain))
                foreach (var h in plain.ToArray()) Guarded(opcode, () => h(wire));
            if (!handlers.TryGetValue(opcode, out var list)) return;
            string whole = chunks.Feed(opcode, wire);
            if (whole == null) return;
            object root = Json.TryParse(FromWire(whole));
            if (!(root is Dictionary<string, object>))
            {
                Invalid++;
                Log("extended opcode " + opcode + ": invalid JSON");
                return;
            }
            var msg = new ExtMessage { Opcode = opcode, Root = root, Action = Json.Text(root, "action"), Data = Json.Get(root, "data") };
            foreach (var h in list.ToArray()) Guarded(opcode, () => h(msg));
        }

        void Guarded(byte opcode, Action call)
        {
            try { call(); }
            catch (Exception e) { Log("extended opcode " + opcode + ": " + e.Message); }   // as the main client: logged, nothing else stops
        }

        /// <summary>Sends {"action": action, "data": data}; data may be null (left out).</summary>
        public bool Send(byte opcode, string action, object data = null)
        {
            var root = new Dictionary<string, object> { { "action", action } };
            if (data != null) root["data"] = data;
            return SendText(opcode, Json.Serialize(root));
        }

        /// <summary>Sends a text as it is (the plain opcodes). False when it is over the size the server accepts.</summary>
        public bool SendText(byte opcode, string text)
        {
            byte[] bytes = Encoding.UTF8.GetBytes(text ?? "");
            if (bytes.Length > MaxRequestBytes) { Log("extended opcode " + opcode + ": " + bytes.Length + " bytes is over " + MaxRequestBytes); return false; }
            Transmit(new ByteWriter().U8(0x32).U8(opcode).U16((ushort)bytes.Length).Raw(bytes).ToArray());
            Sent++;
            return true;
        }

        static readonly Encoding Latin1 = Encoding.GetEncoding("ISO-8859-1");

        /// <summary>The text of a wire string: its chars are bytes, the bytes are UTF-8.</summary>
        public static string FromWire(string wire) => Encoding.UTF8.GetString(Latin1.GetBytes(wire));
        /// <summary>The wire string of a text (what ByteReader.Str would give for these UTF-8 bytes).</summary>
        public static string ToWire(string text) => Latin1.GetString(Encoding.UTF8.GetBytes(text ?? ""));
    }
}
