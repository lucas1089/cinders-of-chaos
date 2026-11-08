// Phase 12, track H (Core/Phase12H.cs): the shared window clamp and the smoke run's oversize, thin and empty body checks.
using System;
using System.Collections.Generic;

namespace Chaos.Core.Tests
{
    static class Phase12HTests
    {
        public static void Run(Action<bool, string> check)
        {
            FitChecks(check);
            BodyChecks(check);
            InkChecks(check);
            ReportChecks(check);
        }

        static void FitChecks(Action<bool, string> check)
        {
            var ok = WindowFit.Fit(new SmokeBox(390, 110, 500, 380), 1280, 720);
            check(ok.X == 390 && ok.Y == 110 && ok.W == 500 && ok.H == 380, "window fit: a window that fits is left alone");
            var big = WindowFit.Fit(new SmokeBox(-300, -40, 2400, 1500), 1280, 720);
            check(big.W == 1272 && big.H == 712 && big.X == 4 && big.Y == 4, "window fit: a window larger than the screen shrinks to it less the margins and moves in: " + big.X + "," + big.Y + " " + big.W + "x" + big.H);
            var right = WindowFit.Fit(new SmokeBox(1200, 600, 300, 200), 1280, 720);
            check(right.XMax == 1276 && right.YMax == 716 && right.W == 300 && right.H == 200, "window fit: a window past the right and bottom edge moves in");
            var nan = WindowFit.Fit(new SmokeBox(float.NaN, float.NaN, float.NaN, float.NaN), 1280, 720);
            check(!float.IsNaN(nan.X + nan.Y + nan.W + nan.H) && nan.W >= 1 && nan.H >= 1, "window fit: NaN becomes a small rect on the screen");
            var tiny = WindowFit.Fit(new SmokeBox(10, 10, 100, 100), 4, 4);
            check(tiny.W == 100 && tiny.H == 100, "window fit: a screen of no size gives the rect back");
            check(WindowFit.Exceeds(1273, 100, 1280, 720) && WindowFit.Exceeds(100, 713, 1280, 720) && !WindowFit.Exceeds(1272, 712, 1280, 720), "window fit: exceeds means over the screen less the margins");
            // the 960 x 540 phone screen: the Marches rules window (500 x 380 at y 110) moves up and stays whole
            var phone = WindowFit.Fit(new SmokeBox(230, 110, 500, 380), 960, 540);
            check(phone.YMax <= 536 && phone.Y >= 4 && phone.H == 380, "window fit: the 500 x 380 pop-up on a 960 x 540 screen moves in whole");
            check(WindowFit.ScrollContent(100, 300) == 300 && WindowFit.ScrollContent(500, 300) == 500, "window fit: scroll content is never shorter than the view");
            check(WindowFit.ViewHeight(340, 32, 4) == 304 && WindowFit.ViewHeight(10, 32, 4) == 1, "window fit: the view is the body less the button bar, at least 1");
        }

        static void BodyChecks(Action<bool, string> check)
        {
            check(SmokeBody.BodyHeight(40) == 8 && SmokeBody.Thin(40), "smoke body: the old 40 high raid call-out had an 8 high body: thin");
            check(!SmokeBody.Thin(62) && SmokeBody.BodyHeight(62) == 30, "smoke body: the new 62 high call-out has a 30 high body");
            check(SmokeBody.Thin(55) && !SmokeBody.Thin(56) && !SmokeBody.Thin(float.NaN), "smoke body: the limit is a 24 high body (window 56)");
            var inner = SmokeBody.Inner(new SmokeBox(100, 50, 400, 300), 2f, 1280, 720);
            check(inner.X == 208 && inner.Y == 156 && inner.W == 784 && inner.H == 536, "smoke body: inner box numbers: " + inner.X + "," + inner.Y + " " + inner.W + "x" + inner.H);
            var off = SmokeBody.Inner(new SmokeBox(2000, 2000, 100, 100), 1f, 1280, 720);
            check(off.W == 0 && off.H == 0, "smoke body: a window off the screen has no body");
            var cut = SmokeBody.Inner(new SmokeBox(1200, 600, 400, 400), 1f, 1280, 720);
            check(cut.XMax <= 1280 && cut.YMax <= 720 && cut.W > 0, "smoke body: the box is cut to the screen");
        }

        /// <summary>An RGBA image filled with one colour; the draw callback paints marks.</summary>
        static byte[] Image(int w, int h, byte r, byte g, byte b, Action<byte[], int, int, Action<int, int, byte, byte, byte>> draw = null)
        {
            var px = new byte[w * h * 4];
            for (int i = 0; i < w * h; i++) { px[i * 4] = r; px[i * 4 + 1] = g; px[i * 4 + 2] = b; px[i * 4 + 3] = 255; }
            draw?.Invoke(px, w, h, (x, y, rr, gg, bb) => { int i = (y * w + x) * 4; px[i] = rr; px[i + 1] = gg; px[i + 2] = bb; });
            return px;
        }

        static void InkChecks(Action<bool, string> check)
        {
            var box = new SmokeBox(10, 10, 200, 100);
            var flat = Image(256, 128, 10, 8, 12);
            float ink = SmokeBody.Ink(flat, 256, 128, box, false, out int n);
            check(ink == 0f && n == 200 * 100 && SmokeBody.Empty(ink, n), "smoke ink: a flat body is empty (" + n + " samples)");
            // a text line: 150 x 10 light pixels
            var text = Image(256, 128, 10, 8, 12, (px, w, h, set) => { for (int y = 40; y < 50; y++) for (int x = 20; x < 170; x++) set(x, y, 214, 201, 174); });
            ink = SmokeBody.Ink(text, 256, 128, box, false, out n);
            check(ink > 0.06f && ink < 0.09f && !SmokeBody.Empty(ink, n), "smoke ink: a line of text is ink: " + ink);
            // a frame gradient the main colour absorbs: small steps are not ink
            var grad = Image(256, 128, 0, 0, 0, (px, w, h, set) => { for (int y = 0; y < h; y++) for (int x = 0; x < w; x++) set(x, y, (byte)(10 + y / 8), (byte)(8 + y / 8), (byte)(12 + y / 8)); });
            ink = SmokeBody.Ink(grad, 256, 128, box, false, out n);
            check(SmokeBody.Empty(ink, n), "smoke ink: a soft gradient is still empty: " + ink);
            // a single 2 pixel dot is under the limit (0.004 of 20000 = 80 pixels)
            var dot = Image(256, 128, 10, 8, 12, (px, w, h, set) => { for (int y = 40; y < 42; y++) for (int x = 20; x < 22; x++) set(x, y, 255, 255, 255); });
            ink = SmokeBody.Ink(dot, 256, 128, box, false, out n);
            check(SmokeBody.Empty(ink, n), "smoke ink: four pixels do not make a body: " + ink);
            // the rows of a Unity texture start at the bottom: the same marks flipped
            var low = Image(256, 128, 10, 8, 12, (px, w, h, set) => { for (int y = 128 - 50; y < 128 - 40; y++) for (int x = 20; x < 170; x++) set(x, y, 214, 201, 174); });
            ink = SmokeBody.Ink(low, 256, 128, box, true, out n);
            check(ink > 0.06f && ink < 0.09f, "smoke ink: bottom-up rows read the same line: " + ink);
            ink = SmokeBody.Ink(low, 256, 128, new SmokeBox(10, 10, 200, 50), false, out n);
            check(SmokeBody.Empty(ink, n), "smoke ink: read top-down the flipped marks are outside a box above them");
            // a big box is strided: under MaxSamples pixels looked at
            var big = Image(1280, 720, 10, 8, 12);
            ink = SmokeBody.Ink(big, 1280, 720, new SmokeBox(0, 0, 1280, 720), false, out n);
            check(n <= SmokeBody.MaxSamples && n > 5000 && ink == 0f, "smoke ink: a full screen is sampled with a stride: " + n + " samples");
            // too few pixels: no verdict
            ink = SmokeBody.Ink(flat, 256, 128, new SmokeBox(10, 10, 4, 4), false, out n);
            check(n == 16 && !SmokeBody.Empty(ink, n), "smoke ink: a 4 x 4 box has too few samples to call empty");
            ink = SmokeBody.Ink(null, 256, 128, box, false, out n);
            check(n == 0 && ink == 0f && !SmokeBody.Empty(ink, n), "smoke ink: no image, no verdict");
            ink = SmokeBody.Ink(new byte[10], 256, 128, box, false, out n);
            check(n == 0 && !SmokeBody.Empty(ink, n), "smoke ink: a short buffer gives no verdict");
        }

        static void ReportChecks(Action<bool, string> check)
        {
            check(SmokeRect.Oversize(1300, 400, 1280, 720) && SmokeRect.Oversize(400, 800, 1280, 720) && !SmokeRect.Oversize(1280, 720, 1280, 720) && !SmokeRect.Oversize(1280.5f, 720, 1280, 720) && !SmokeRect.Oversize(float.NaN, 5, 1280, 720),
                "smoke rect: oversize is a side larger than the screen");
            var rep = new SmokeReport();
            var a = rep.Begin("win:PvpZoneConfirmWindow", "win"); a.Frames = 4; a.HasRect = true; a.Oversize = true; rep.End();
            var b = rep.Begin("win:RaidCalloutWindow", "win"); b.Frames = 4; b.HasRect = true; b.Thin = true; b.Ink = 0f; rep.End();
            var c = rep.Begin("win:SkillsWindow", "win"); c.Frames = 4; c.HasRect = true; c.EmptyBody = true; c.Ink = 0.001f; rep.End();
            var d = rep.Begin("win:BankWindow", "win"); d.Frames = 4; d.HasRect = true; d.Ink = 0.12f; rep.End();
            check(a.Problem && b.Problem && c.Problem && !d.Problem, "smoke report: oversize, thin and empty bodies are problems");
            check(rep.OversizeCount == 1 && rep.EmptyCount == 2 && rep.WithProblems == 3, "smoke report: oversize 1, thin or empty 2");
            check(rep.DetailLine().EndsWith("1 oversize, 2 thin or empty body"), "smoke report: the detail line names them: " + rep.DetailLine());
            var root = Json.TryParse(rep.ToJson(1280, 720)) as Dictionary<string, object>;
            var sum = root == null ? null : root["summary"] as Dictionary<string, object>;
            var wins = root == null ? null : root["windows"] as List<object>;
            check(sum != null && (double)sum["oversize"] == 1 && (double)sum["emptyBody"] == 2, "smoke json: summary oversize and emptyBody");
            if (wins == null) return;
            var w0 = wins[0] as Dictionary<string, object>; var w1 = wins[1] as Dictionary<string, object>; var w3 = wins[3] as Dictionary<string, object>;
            check((bool)w0["oversize"] && !(bool)w0["thin"] && !w0.ContainsKey("ink") && (bool)w1["thin"] && (double)w1["ink"] == 0 && !(bool)w3["emptyBody"] && (double)w3["ink"] == 0.12, "smoke json: per window oversize, thin, emptyBody and ink");
        }
    }
}
