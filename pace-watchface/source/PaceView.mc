import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.WatchUi;

// Pace: a layered analog watch face for the Forerunner 165 (390x390 AMOLED).
//
// All positions below are written for a 390x390 screen (centre 195,195), the same
// coordinates as the HTML preview. px()/py() scale them to the real screen and
// apply the small burn-in shift used in always-on mode.
class PaceView extends WatchUi.WatchFace {

    // Accent pairs: [minute colour, hour colour]
    private var _accents as Array<Array<Number>> = [
        [0xD4F78A, 0xB9A5FF],   // Lime / Lavender
        [0x7FE3FF, 0xFFB27A],   // Sky / Peach
        [0xFFD166, 0x9EE6B0],   // Gold / Mint
        [0xFF9EC7, 0xA0C4FF]    // Pink / Blue
    ];

    const WHITE  = 0xEDEDED;
    const GREY   = 0x8A8A8A;
    const DARK   = 0x3A3A3A;
    const BLACK  = 0x000000;

    private var _a1 as Number = 0xD4F78A;   // minute accent
    private var _a2 as Number = 0xB9A5FF;   // hour accent

    private var _sleeping as Boolean = false;
    private var _scale as Float = 1.0;
    private var _cx as Float = 195.0;
    private var _cy as Float = 195.0;

    // Vector fonts (null if the watch can't provide them; we then fall back to system fonts)
    private var _hasVector as Boolean = false;
    private var _fOuter as Graphics.VectorFont or Null;      // outer seconds ring numbers
    private var _fOuterNow as Graphics.VectorFont or Null;   // the number at 12 o'clock (current second)
    private var _fInner as Graphics.VectorFont or Null;      // minute ring numbers
    private var _fPill as Graphics.VectorFont or Null;       // digital time
    private var _fBig as Graphics.VectorFont or Null;        // battery %, date number, seconds number
    private var _fSmall as Graphics.VectorFont or Null;      // weekday, "%"

    function initialize() {
        WatchFace.initialize();
        loadSettings();
    }

    function loadSettings() as Void {
        var idx = 0;
        try {
            var v = Application.Properties.getValue("AccentPair");
            if (v instanceof Number && v >= 0 && v < _accents.size()) {
                idx = v;
            }
        } catch (e) {
            idx = 0;
        }
        _a1 = _accents[idx][0];
        _a2 = _accents[idx][1];
    }

    function onLayout(dc as Graphics.Dc) as Void {
        _scale = dc.getWidth() / 390.0;
        _fOuter    = vfont(["RobotoCondensedRegular", "RobotoRegular"], 15);
        _fOuterNow = vfont(["RobotoCondensedBold", "RobotoBold", "RobotoRegular"], 19);
        _fInner    = vfont(["RobotoCondensedBold", "RobotoBold", "RobotoRegular"], 22);
        _fPill     = vfont(["RobotoCondensedBold", "RobotoBold", "RobotoRegular"], 28);
        _fBig      = vfont(["RobotoCondensedBold", "RobotoBold", "RobotoRegular"], 30);
        _fSmall    = vfont(["RobotoCondensedBold", "RobotoBold", "RobotoRegular"], 16);
        // A loop, not a 6-way `!= null &&` chain: that chain makes the type checker run out of memory.
        _hasVector = true;
        var fonts = [_fOuter, _fOuterNow, _fInner, _fPill, _fBig, _fSmall];
        for (var i = 0; i < fonts.size(); i++) {
            if (fonts[i] == null) { _hasVector = false; }
        }
    }

    private function vfont(faces as Array<String>, size as Number) as Graphics.VectorFont or Null {
        if (Graphics has :getVectorFont) {
            return Graphics.getVectorFont({ :face => faces, :size => (size * _scale).toNumber() });
        }
        return null;
    }

    // Wrist raised: redraw every second.
    function onExitSleep() {
        _sleeping = false;
        WatchUi.requestUpdate();
    }

    // Wrist lowered: switch to the dim always-on face (redrawn once a minute).
    function onEnterSleep() {
        _sleeping = true;
        WatchUi.requestUpdate();
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var ct = System.getClockTime();

        // In always-on mode nudge everything by a couple of pixels each minute
        // so the same pixels are not lit for long (AMOLED burn-in protection).
        var ox = 0;
        var oy = 0;
        if (_sleeping) {
            var shifts = [[0, 0], [2, 0], [0, 2], [-2, 0], [0, -2]];
            var s = shifts[ct.min % 5];
            ox = s[0];
            oy = s[1];
        }
        _cx = w / 2.0 + ox;
        _cy = h / 2.0 + oy;

        dc.setColor(BLACK, BLACK);
        dc.clear();
        if (dc has :setAntiAlias) {
            dc.setAntiAlias(true);
        }

        if (_sleeping) {
            drawLowPower(dc, ct);
        } else {
            drawActive(dc, ct);
        }
    }

    // ------------------------------------------------------------------ active face

    private function drawActive(dc as Graphics.Dc, ct as System.ClockTime) as Void {
        var sec = ct.sec;
        var min = ct.min;

        // 1. Outer seconds ring: it rotates so the current second sits at 12 o'clock.
        for (var i = 0; i < 60; i++) {
            var a = (i - sec) * 6;
            if (i % 2 == 0) {
                var d = dist60(i, sec);
                var col = (d == 0) ? WHITE : ((d <= 2) ? 0xB0B0B0 : 0x6A6A6A);
                var font = (d == 0) ? _fOuterNow : _fOuter;
                dc.setColor(col, Graphics.COLOR_TRANSPARENT);
                textAt(dc, 181, 168, a, font, Graphics.FONT_XTINY, i.format("%02d"), a);
            } else {
                dc.setColor(0x4A4A4A, Graphics.COLOR_TRANSPARENT);
                var p = polar(181, a);
                dc.fillCircle(p[0], p[1], 2 * _scale);
            }
        }

        // 2. Minute ring: bold numbers every 5 minutes, ticks light up as the hour passes.
        dc.setPenWidth((4 * _scale).toNumber());
        for (var j = 0; j < 60; j++) {
            var ma = j * 6;
            if (j % 5 == 0) {
                dc.setColor(WHITE, Graphics.COLOR_TRANSPARENT);
                textAt(dc, 157, -163, ma, _fInner, Graphics.FONT_TINY, j.format("%02d"), readable(ma));
            } else {
                dc.setColor(j <= min ? _a1 : DARK, Graphics.COLOR_TRANSPARENT);
                var t0 = polar(152, ma);
                var t1 = polar(162, ma);
                dc.drawLine(t0[0], t0[1], t1[0], t1[1]);
            }
        }

        drawBattery(dc);
        drawDate(dc, false);
        drawPill(dc, ct, false);
        drawSecondsDial(dc, sec);
        drawHands(dc, ct, false);
    }

    private function drawBattery(dc as Graphics.Dc) as Void {
        var bat = System.getSystemStats().battery.toNumber();
        var col = (bat < 15) ? 0xFF6B6B : ((bat < 30) ? 0xFFB020 : _a1);
        var x = px(128);
        var y = py(122);
        var r = 38 * _scale;

        dc.setColor(0x1B2014, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x, y, r);
        dc.setPenWidth((2 * _scale).toNumber());
        dc.setColor(0x2C3322, Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(x, y, r);

        // Gauge runs clockwise over 300 degrees, starting at 7 o'clock.
        // Garmin arcs use 0 = 3 o'clock, counter-clockwise positive.
        var ar = (r - 6 * _scale);
        dc.setPenWidth((5 * _scale).toNumber());
        dc.setColor(0x333333, Graphics.COLOR_TRANSPARENT);
        dc.drawArc(x, y, ar, Graphics.ARC_CLOCKWISE, 240, 300);
        if (bat > 0) {
            var end = 240 - (300 * bat / 100);
            if (end < 0) { end += 360; }
            dc.setColor(col, Graphics.COLOR_TRANSPARENT);
            if (bat >= 100) {
                dc.drawArc(x, y, ar, Graphics.ARC_CLOCKWISE, 240, 300);
            } else {
                dc.drawArc(x, y, ar, Graphics.ARC_CLOCKWISE, 240, end);
            }
        }

        dc.setColor(col, Graphics.COLOR_TRANSPARENT);
        plain(dc, x, y, _fBig, Graphics.FONT_SMALL, bat.toString());
        dc.setColor(GREY, Graphics.COLOR_TRANSPARENT);
        plain(dc, x, y + 24 * _scale, _fSmall, Graphics.FONT_XTINY, "%");
    }

    private function drawDate(dc as Graphics.Dc, dim as Boolean) as Void {
        var info = Gregorian.info(Time.now(), Time.FORMAT_MEDIUM);
        var dow = info.day_of_week.toString().toUpper();
        var x = px(272);
        var y = py(195);
        if (dim) {
            dc.setColor(0x555555, Graphics.COLOR_TRANSPARENT);
            plain(dc, x, y, _fSmall, Graphics.FONT_XTINY, dow + " " + info.day.toString());
            return;
        }
        dc.setColor(0x1A1726, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x, y, 40 * _scale);
        dc.setPenWidth((2 * _scale).toNumber());
        dc.setColor(0x2C2840, Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(x, y, 40 * _scale);
        dc.setColor(_a2, Graphics.COLOR_TRANSPARENT);
        plain(dc, x, y - 13 * _scale, _fSmall, Graphics.FONT_XTINY, dow);
        dc.setColor(WHITE, Graphics.COLOR_TRANSPARENT);
        plain(dc, x, y + 12 * _scale, _fBig, Graphics.FONT_SMALL, info.day.toString());
    }

    private function drawPill(dc as Graphics.Dc, ct as System.ClockTime, dim as Boolean) as Void {
        var hour = ct.hour;
        if (!System.getDeviceSettings().is24Hour) {
            hour = hour % 12;
            if (hour == 0) { hour = 12; }
        }
        var label = hour.format("%02d") + ":" + ct.min.format("%02d");
        var x = px(62);
        var y = py(176);
        var w = 100 * _scale;
        var h = 40 * _scale;
        if (!dim) {
            dc.setColor(0x1B2014, Graphics.COLOR_TRANSPARENT);
            dc.fillRoundedRectangle(x, y, w, h, h / 2);
        }
        dc.setPenWidth((3 * _scale).toNumber());
        dc.setColor(dim ? 0x444444 : _a1, Graphics.COLOR_TRANSPARENT);
        dc.drawRoundedRectangle(x, y, w, h, h / 2);
        dc.setColor(dim ? 0x777777 : WHITE, Graphics.COLOR_TRANSPARENT);
        plain(dc, x + w / 2, y + h / 2, _fPill, Graphics.FONT_SMALL, label);
    }

    private function drawSecondsDial(dc as Graphics.Dc, sec as Number) as Void {
        var x = px(195);
        var y = py(283);
        var r = 40 * _scale;
        for (var i = 0; i < 12; i++) {
            var a = Math.toRadians(i * 30);
            var dx = x + r * Math.sin(a);
            var dy = y - r * Math.cos(a);
            dc.setColor((sec / 5 >= i) ? _a1 : DARK, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(dx, dy, ((i % 3 == 0) ? 4.5 : 3) * _scale);
        }
        var sa = Math.toRadians(sec * 6);
        dc.setColor(_a2, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x + r * Math.sin(sa), y - r * Math.cos(sa), 7 * _scale);
        dc.setColor(_a1, Graphics.COLOR_TRANSPARENT);
        plain(dc, x, y, _fBig, Graphics.FONT_SMALL, sec.format("%02d"));
    }

    private function drawHands(dc as Graphics.Dc, ct as System.ClockTime, dim as Boolean) as Void {
        var minDeg = ct.min * 6;
        var hrDeg = (ct.hour % 12) * 30 + ct.min / 2.0;
        var stroke = dim ? 3 : 5;
        pillHand(dc, hrDeg, 92, 22, stroke, dim ? 0x666666 : _a2);
        pillHand(dc, minDeg, 138, 20, stroke, dim ? 0x888888 : _a1);

        var c = polar(0, 0);
        dc.setColor(dim ? 0x666666 : _a1, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(c[0], c[1], 12 * _scale);
        dc.setColor(BLACK, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(c[0], c[1], 8 * _scale);
    }

    // A rounded "pill" hand drawn as an outline: coloured capsule, black capsule inside.
    private function pillHand(dc as Graphics.Dc, deg as Numeric, len as Numeric, width as Numeric, stroke as Numeric, color as Number) as Void {
        var r = width / 2.0;
        var p0 = polar(14 + r, deg);
        var p1 = polar(len - r, deg);

        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth((width * _scale).toNumber());
        dc.drawLine(p0[0], p0[1], p1[0], p1[1]);
        dc.fillCircle(p0[0], p0[1], r * _scale);
        dc.fillCircle(p1[0], p1[1], r * _scale);

        var inner = (width - 2 * stroke);
        dc.setColor(BLACK, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth((inner * _scale).toNumber());
        dc.drawLine(p0[0], p0[1], p1[0], p1[1]);
        dc.fillCircle(p0[0], p0[1], (r - stroke) * _scale);
        dc.fillCircle(p1[0], p1[1], (r - stroke) * _scale);
    }

    // ------------------------------------------------------------------ always-on face

    private function drawLowPower(dc as Graphics.Dc, ct as System.ClockTime) as Void {
        dc.setPenWidth((3 * _scale).toNumber());
        dc.setColor(0x444444, Graphics.COLOR_TRANSPARENT);
        for (var i = 0; i < 12; i++) {
            var p0 = polar(162, i * 30);
            var p1 = polar(174, i * 30);
            dc.drawLine(p0[0], p0[1], p1[0], p1[1]);
        }
        drawDate(dc, true);
        drawPill(dc, ct, true);
        drawHands(dc, ct, true);
    }

    // ------------------------------------------------------------------ helpers

    private function px(v as Numeric) as Numeric {
        return _cx + (v - 195) * _scale;
    }

    private function py(v as Numeric) as Numeric {
        return _cy + (v - 195) * _scale;
    }

    // Point at radius r (design pixels) and angle deg (clockwise from 12 o'clock).
    private function polar(r as Numeric, deg as Numeric) as Array<Numeric> {
        var a = Math.toRadians(deg);
        return [_cx + r * _scale * Math.sin(a), _cy - r * _scale * Math.cos(a)];
    }

    // Shortest distance between two seconds on a 60-second dial.
    private function dist60(a as Number, b as Number) as Number {
        var d = (a - b).abs() % 60;
        return (d > 30) ? 60 - d : d;
    }

    // Keep text upright in the bottom half of the minute ring.
    private function readable(deg as Number) as Number {
        var d = ((deg % 360) + 360) % 360;
        return (d > 90 && d < 270) ? d + 180 : d;
    }

    // Draw text centred at a point on a ring, rotated by rotDeg (clockwise).
    // Without rotated text the labels stay upright, so on the sides they are wide radially
    // and the two rings collide. Then `edge` places them by size instead: a positive edge is
    // the ring radius the label sits just outside of, a negative edge the one it sits inside.
    private function textAt(dc as Graphics.Dc, r as Numeric, edge as Numeric, deg as Numeric, vfont as Graphics.VectorFont or Null, sysFont as Graphics.FontType, str as String, rotDeg as Numeric) as Void {
        var just = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
        if (!(_hasVector && (dc has :drawAngledText))) {
            var dim = dc.getTextDimensions(str, sysFont);
            var a = Math.toRadians(deg);
            // Text boxes include side bearing and line spacing; the digits themselves are smaller.
            var ext = (Math.sin(a).abs() * dim[0] * 0.85 + Math.cos(a).abs() * dim[1] * 0.6) / 2.0 / _scale;
            r = (edge > 0) ? edge + ext : -edge - ext;
        }
        var p = polar(r, deg);
        if (_hasVector && (dc has :drawAngledText)) {
            // Garmin angles are counter-clockwise, ours are clockwise.
            var ang = ((360 - rotDeg.toNumber()) % 360 + 360) % 360;
            dc.drawAngledText(p[0], p[1], vfont as Graphics.VectorFont, str, just, ang);
        } else {
            dc.drawText(p[0], p[1], sysFont, str, just);
        }
    }

    // Draw upright centred text.
    private function plain(dc as Graphics.Dc, x as Numeric, y as Numeric, vfont as Graphics.VectorFont or Null, sysFont as Graphics.FontType, str as String) as Void {
        var just = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
        if (_hasVector && (dc has :drawAngledText)) {
            dc.drawAngledText(x, y, vfont as Graphics.VectorFont, str, just, 0);
        } else {
            dc.drawText(x, y, sysFont, str, just);
        }
    }
}
