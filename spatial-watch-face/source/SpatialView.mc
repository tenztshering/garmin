import Toybox.ActivityMonitor;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

// Spatial: the hour is drawn as giant geometric digits, one layer of frosted glass over a
// solid orange one ("10" = glass pill over an orange disc), with analog hands on top.
// The 12 hour scenes are pre-rendered (tools/render.py) because the watch can't blur;
// hands and data are drawn live so they stay sharp. Coordinates are for 390x390, scaled by s().
//
// Left arc:    steps towards the daily goal.
// Right ticks: battery, one tick per 10%.
class SpatialView extends WatchUi.WatchFace {

    const HAND  = 0xF4F2EC;   // hands
    const INK   = 0x232C22;   // inset line in the hands + centre pin
    const SAGE  = 0xC8D6A8;   // data fills and labels
    const TRACK = 0x4A5846;   // unfilled arc / ticks
    const DIM   = 0x8A8A8A;   // always-on digits

    private var _scene as WatchUi.BitmapResource?;
    private var _sceneHour as Number = -1;
    private const SCENES = [Rez.Drawables.Hour01, Rez.Drawables.Hour02, Rez.Drawables.Hour03,
        Rez.Drawables.Hour04, Rez.Drawables.Hour05, Rez.Drawables.Hour06, Rez.Drawables.Hour07,
        Rez.Drawables.Hour08, Rez.Drawables.Hour09, Rez.Drawables.Hour10, Rez.Drawables.Hour11,
        Rez.Drawables.Hour12];
    private var _sleeping as Boolean = false;
    private var _scale as Float = 1.0;
    private var _fData as Graphics.FontType = Graphics.FONT_XTINY;
    private var _vData as Graphics.VectorFont?;

    function initialize() {
        WatchFace.initialize();
    }

    function onLayout(dc as Graphics.Dc) as Void {
        _scale = dc.getWidth() / 390.0;
        if (Graphics has :getVectorFont) {
            _vData = Graphics.getVectorFont({ :face => ["RobotoCondensedBold", "RobotoRegular"], :size => s(20) });
            if (_vData != null) { _fData = _vData as Graphics.VectorFont; }
        }
    }

    function onExitSleep() as Void {
        _sleeping = false;
        WatchUi.requestUpdate();
    }

    function onEnterSleep() as Void {
        _sleeping = true;
        WatchUi.requestUpdate();
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var ct = System.getClockTime();

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        if (dc has :setAntiAlias) { dc.setAntiAlias(true); }

        if (_sleeping) {
            // Always-on: thin dim hands only, nudged 2 px a minute against burn-in.
            var shifts = [[0, 0], [2, 0], [0, 2], [-2, 0], [0, -2]];
            var o = shifts[ct.min % 5];
            drawHands(dc, ct, o[0], o[1], true);
            return;
        }

        // Load only the current hour's scene (each is a full-screen bitmap).
        var h12 = ct.hour % 12;
        if (h12 == 0) { h12 = 12; }
        if (h12 != _sceneHour) {
            _scene = null;
            _scene = WatchUi.loadResource(SCENES[h12 - 1]) as WatchUi.BitmapResource;
            _sceneHour = h12;
        }
        dc.drawBitmap(0, 0, _scene as WatchUi.BitmapResource);
        drawSteps(dc);
        drawBattery(dc);
        drawHands(dc, ct, 0, 0, false);
    }

    private function drawHands(dc as Graphics.Dc, ct as System.ClockTime, ox as Number, oy as Number, dim as Boolean) as Void {
        var c = 195.0;
        var ha = Math.toRadians((ct.hour % 12) * 30 + ct.min * 0.5);
        var ma = Math.toRadians(ct.min * 6);
        var col = dim ? DIM : HAND;
        // hour: short and wide; minute: long. Dark inset line along the outer part, as in a
        // physical hand with a lume slot.
        capsule(dc, c, c, ha, -12, 100, dim ? 6 : 15, col, ox, oy);
        capsule(dc, c, c, ma, -12, 168, dim ? 5 : 12, col, ox, oy);
        if (!dim) {
            capsule(dc, c, c, ha, 34, 90, 6, INK, 0, 0);
            capsule(dc, c, c, ma, 40, 158, 4, INK, 0, 0);
            dc.setColor(HAND, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(s(c), s(c), s(9));
            dc.setColor(INK, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(s(c), s(c), s(3));
        }
    }

    // Line with round ends along angle a (0 = 12 o'clock, clockwise), from radius r0 to r1.
    private function capsule(dc as Graphics.Dc, cx as Float, cy as Float, a as Float, r0 as Number, r1 as Number,
            w as Number, col as Number, ox as Number, oy as Number) as Void {
        var sx = Math.sin(a);
        var cy_ = -Math.cos(a);
        var x0 = s(cx + r0 * sx) + ox;
        var y0 = s(cy + r0 * cy_) + oy;
        var x1 = s(cx + r1 * sx) + ox;
        var y1 = s(cy + r1 * cy_) + oy;
        dc.setColor(col, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(s(w));
        dc.drawLine(x0, y0, x1, y1);
        dc.fillCircle(x0, y0, s(w) / 2);
        dc.fillCircle(x1, y1, s(w) / 2);
    }

    // Arc on the left edge, filling bottom-up from 215 deg to 145 deg.
    private function drawSteps(dc as Graphics.Dc) as Void {
        var info = ActivityMonitor.getInfo();
        var steps = info.steps != null ? info.steps as Number : 0;
        var goal = (info.stepGoal != null && info.stepGoal > 0) ? info.stepGoal as Number : 10000;
        var frac = steps.toFloat() / goal;
        if (frac > 1.0) { frac = 1.0; }
        var c = s(195);
        var r = s(176);
        dc.setPenWidth(s(12));
        dc.setColor(TRACK, Graphics.COLOR_TRANSPARENT);
        dc.drawArc(c, c, r, Graphics.ARC_CLOCKWISE, 215, 145);
        if (frac > 0.01) {
            dc.setColor(SAGE, Graphics.COLOR_TRANSPARENT);
            dc.drawArc(c, c, r, Graphics.ARC_CLOCKWISE, 215, 215 - (70 * frac).toNumber());
        }
        drawCurved(dc, groupThousands(steps), 236, Graphics.RADIAL_TEXT_DIRECTION_COUNTER_CLOCKWISE);
    }

    // Ticks on the right edge, one per 10% battery, longer towards the top.
    private function drawBattery(dc as Graphics.Dc) as Void {
        var pct = System.getSystemStats().battery;
        var lit = Math.ceil(pct / 10.0).toNumber();
        var c = 195.0;
        dc.setPenWidth(s(4));
        for (var i = 0; i < 10; i++) {
            var a = Math.toRadians(-27 + i * 6);       // bottom (-27 deg) to top (+27 deg)
            var len = 6 + i * 1.1;
            var r1 = 188.0;             // hugs the bezel, clear of the hour digits
            var r0 = r1 - len;
            dc.setColor(i < lit ? SAGE : TRACK, Graphics.COLOR_TRANSPARENT);
            dc.drawLine(s((c + r0 * Math.cos(a)).toNumber()), s((c - r0 * Math.sin(a)).toNumber()),
                        s((c + r1 * Math.cos(a)).toNumber()), s((c - r1 * Math.sin(a)).toNumber()));
        }
        drawCurved(dc, pct.toNumber().toString() + "%", 314, Graphics.RADIAL_TEXT_DIRECTION_CLOCKWISE);
    }

    private function drawCurved(dc as Graphics.Dc, txt as String, angle as Number, dir as Graphics.RadialTextDirection) as Void {
        dc.setColor(SAGE, Graphics.COLOR_TRANSPARENT);
        if (_vData != null && dc has :drawRadialText) {
            dc.drawRadialText(s(195), s(195), _vData as Graphics.VectorFont, txt,
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER, angle, s(174), dir);
        }
    }

    private function groupThousands(n as Number) as String {
        if (n < 1000) { return n.toString(); }
        return (n / 1000).toString() + "," + (n % 1000).format("%03d");
    }

    private function s(v as Number or Float) as Number {
        return (v * _scale).toNumber();
    }
}
