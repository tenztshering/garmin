import Toybox.Activity;
import Toybox.ActivityMonitor;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.Weather;
import Toybox.WatchUi;

// Column: tall hour/minute digits stacked on the left, a battery bar down the middle,
// weather + steps + calories + heart rate on the right.
//
// The big digits are drawn from lines and arcs (drawDigit) because no device font is
// this narrow; that also keeps them razor-sharp at any size. Coordinates are for
// 390x390 and scaled by s().
class ColumnView extends WatchUi.WatchFace {

    const WHITE = 0xFFFFFF;
    const GREEN = 0x58E05A;
    const TRACK = 0x2E2E2E;
    const GREY  = 0x8A8A8A;

    // big digits: two per row, 36 x 84 px each, 10 px apart, 7 px strokes (readable at a glance)
    const DW = 36;
    const DH = 84;
    const DGAP = 10;
    const DX = 86;          // left edge of the first digit
    const HOUR_Y = 92;      // top of the hour digits
    const MIN_Y = 186;      // top of the minute digits
    const PEN = 7;

    const BAR_X = 195;
    const BAR_Y0 = 97;
    const BAR_Y1 = 263;

    const ICON_X = 248;     // right column
    const TEXT_X = 268;

    private var _sleeping as Boolean = false;
    private var _scale as Float = 1.0;
    private var _fSmall as Graphics.FontType = Graphics.FONT_TINY;
    private var _fTiny as Graphics.FontType = Graphics.FONT_XTINY;

    private var _lastMin as Number = -1;
    private var _temp as String = "--";
    private var _cond as Number = -1;

    function initialize() {
        WatchFace.initialize();
    }

    function onLayout(dc as Graphics.Dc) as Void {
        _scale = dc.getWidth() / 390.0;
        // Small text uses the watch's built-in fonts: they are hinted to the pixel grid, so they
        // render crisper than scaled vector fonts at these sizes.
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
        var now = Time.now();
        var info = Gregorian.info(now, Time.FORMAT_SHORT);
        var h = info.hour as Number;
        if (!System.getDeviceSettings().is24Hour) {
            h = h % 12;
            if (h == 0) { h = 12; }
        }
        var m = info.min as Number;

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        if (dc has :setAntiAlias) { dc.setAntiAlias(true); }

        if (_sleeping) {
            // Always-on: the time only, thin and dim, nudged 2 px a minute against burn-in.
            var sh = [[0, 0], [2, 0], [0, 2], [-2, 0], [0, -2]];
            var o = sh[m % 5];
            drawTime(dc, h, m, GREY, 4, o[0], o[1]);
            return;
        }

        if (m != _lastMin) {
            refreshWeather();
            _lastMin = m;
        }

        drawTime(dc, h, m, WHITE, PEN, 0, 0);
        drawDate(dc, info);
        drawBattery(dc);
        drawStats(dc);

        var days = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"];
        dc.setColor(WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(s(195), s(336), _fSmall, days[(info.day_of_week as Number) - 1],
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // ---------------------------------------------------------------- time + date

    private function drawTime(dc as Graphics.Dc, h as Number, m as Number, col as Number, pen as Number,
            ox as Number, oy as Number) as Void {
        dc.setColor(col, Graphics.COLOR_TRANSPARENT);
        drawDigit(dc, h / 10, DX + ox, HOUR_Y + oy, pen);
        drawDigit(dc, h % 10, DX + DW + DGAP + ox, HOUR_Y + oy, pen);
        drawDigit(dc, m / 10, DX + ox, MIN_Y + oy, pen);
        drawDigit(dc, m % 10, DX + DW + DGAP + ox, MIN_Y + oy, pen);
    }

    // Month + day as MMDD under the time, day in green.
    private function drawDate(dc as Graphics.Dc, info as Gregorian.Info) as Void {
        var y = s(293);   // below the taller minute digits
        var x = s(DX - 2);
        var mm = (info.month as Number).format("%02d");
        var j = Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER;
        dc.setColor(WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, _fSmall, mm, j);
        dc.setColor(GREEN, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x + dc.getTextWidthInPixels(mm, _fSmall), y, _fSmall, (info.day as Number).format("%02d"), j);
    }

    // ---------------------------------------------------------------- battery

    private function drawBattery(dc as Graphics.Dc) as Void {
        var st = System.getSystemStats();
        var pct = st.battery;
        dc.setColor(WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(s(195), s(69), _fTiny, pct.toNumber().toString() + "%",
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        var x = s(BAR_X);
        var y0 = s(BAR_Y0);
        var y1 = s(BAR_Y1);
        dc.setPenWidth(s(3));
        dc.setColor(TRACK, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(x, y0, x, y1);
        var top = y1 - ((y1 - y0) * pct / 100).toNumber();
        dc.setColor(pct > 15 ? GREEN : 0xF04040, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(x, top, x, y1);

        if (st.charging) {
            // lightning bolt
            var bx = s(195);
            var by = s(293);
            dc.setColor(GREEN, Graphics.COLOR_TRANSPARENT);
            dc.fillPolygon([[bx + s(3), by - s(11)], [bx - s(7), by + s(2)], [bx - s(1), by + s(2)],
                [bx - s(3), by + s(11)], [bx + s(7), by - s(2)], [bx + s(1), by - s(2)]]);
        }
    }

    // ---------------------------------------------------------------- right column

    private function refreshWeather() as Void {
        var c = Weather.getCurrentConditions();
        if (c == null) { return; }
        if (c.temperature != null) {
            var t = (c.temperature as Numeric).toFloat();
            if (System.getDeviceSettings().temperatureUnits == System.UNIT_STATUTE) {
                t = t * 9.0 / 5.0 + 32;
            }
            _temp = Math.round(t).toNumber().toString() + "°";
        }
        _cond = c.condition != null ? c.condition as Number : -1;
    }

    private function drawStats(dc as Graphics.Dc) as Void {
        var am = ActivityMonitor.getInfo();
        var steps = am.steps != null ? (am.steps as Number).toString() : "--";
        var cal = am.calories != null ? (am.calories as Number).toString() : "--";
        var hr = heartRate();

        var j = Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER;
        var rows = [[136, _temp], [193, steps], [223, cal], [255, hr]];
        dc.setColor(WHITE, Graphics.COLOR_TRANSPARENT);
        for (var i = 0; i < rows.size(); i++) {
            dc.drawText(s(TEXT_X), s(rows[i][0] as Number), _fSmall, rows[i][1] as String, j);
        }

        var x = s(ICON_X);
        drawWeatherIcon(dc, x, s(136));
        dc.setColor(GREEN, Graphics.COLOR_TRANSPARENT);
        drawShoe(dc, x, s(193));
        drawFlame(dc, x, s(223));
        drawHeart(dc, x, s(255));
    }

    // Current HR if a sensor reading exists, else the latest sample from the history.
    private function heartRate() as String {
        var ai = Activity.getActivityInfo();
        if (ai != null && ai.currentHeartRate != null) {
            return (ai.currentHeartRate as Number).toString();
        }
        if (ActivityMonitor has :getHeartRateHistory) {
            var it = ActivityMonitor.getHeartRateHistory(1, true);
            var smp = it.next();
            if (smp != null && smp.heartRate != ActivityMonitor.INVALID_HR_SAMPLE) {
                return (smp.heartRate as Number).toString();
            }
        }
        return "--";
    }

    // ---------------------------------------------------------------- icons (~18 px)

    private function drawWeatherIcon(dc as Graphics.Dc, x as Number, y as Number) as Void {
        var c = _cond;
        if (c == Weather.CONDITION_CLEAR || c == Weather.CONDITION_MOSTLY_CLEAR) {
            dc.setColor(0xF8A828, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(x, y, s(8));
            return;
        }
        dc.setColor(WHITE, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x - s(5), y + s(1), s(5));
        dc.fillCircle(x + s(1), y - s(3), s(7));
        dc.fillCircle(x + s(7), y + s(2), s(4));
        dc.fillRoundedRectangle(x - s(10), y + s(1), s(21), s(6), s(3));
    }

    private function drawShoe(dc as Graphics.Dc, x as Number, y as Number) as Void {
        dc.fillPolygon([[x - s(10), y + s(6)], [x - s(10), y], [x - s(2), y - s(2)], [x + s(3), y - s(9)],
            [x + s(7), y - s(7)], [x + s(5), y - s(1)], [x + s(10), y + s(2)], [x + s(10), y + s(6)]]);
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(s(2));
        dc.drawLine(x - s(10), y + s(3), x + s(10), y + s(3));     // sole line
        dc.setColor(GREEN, Graphics.COLOR_TRANSPARENT);
    }

    private function drawFlame(dc as Graphics.Dc, x as Number, y as Number) as Void {
        dc.fillPolygon([[x - s(1), y - s(11)], [x + s(5), y - s(4)], [x + s(8), y + s(3)], [x + s(6), y + s(8)],
            [x, y + s(10)], [x - s(6), y + s(8)], [x - s(8), y + s(3)], [x - s(5), y - s(3)], [x - s(2), y]]);
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon([[x, y + s(1)], [x + s(3), y + s(6)], [x, y + s(9)], [x - s(3), y + s(6)]]);
        dc.setColor(GREEN, Graphics.COLOR_TRANSPARENT);
    }

    private function drawHeart(dc as Graphics.Dc, x as Number, y as Number) as Void {
        dc.fillCircle(x - s(5), y - s(2), s(5));
        dc.fillCircle(x + s(5), y - s(2), s(5));
        dc.fillPolygon([[x - s(10), y], [x + s(10), y], [x, y + s(9)]]);
    }

    // ---------------------------------------------------------------- monoline digits

    // Draws digit d in a DW x DH box at (x0, y0) (390-px coordinates) with round-ended strokes.
    // Top and bottom are semicircles (radius DW/2); the middle joint is at half height.
    private function drawDigit(dc as Graphics.Dc, d as Number, x0 as Number, y0 as Number, pen as Number) as Void {
        var r = DW / 2;
        var xl = x0;
        var xr = x0 + DW;
        var xc = x0 + r;
        var ty = y0 + r;            // centre of the top semicircle
        var by = y0 + DH - r;       // centre of the bottom semicircle
        var mid = y0 + DH / 2;
        var yb = y0 + DH;
        dc.setPenWidth(s(pen));
        if (d == 0) {
            arc(dc, xc, ty, r, 0, 180, pen); arc(dc, xc, by, r, 180, 360, pen);
            ln(dc, xl, ty, xl, by, pen); ln(dc, xr, ty, xr, by, pen);
        } else if (d == 8) {
            // two stacked loops meeting at the middle
            arc(dc, xc, ty, r, 0, 180, pen); arc(dc, xc, mid - r, r, 180, 360, pen);
            ln(dc, xl, ty, xl, mid - r, pen); ln(dc, xr, ty, xr, mid - r, pen);
            arc(dc, xc, mid + r, r, 0, 180, pen); arc(dc, xc, by, r, 180, 360, pen);
            ln(dc, xl, mid + r, xl, by, pen); ln(dc, xr, mid + r, xr, by, pen);
        } else if (d == 1) {
            lc(dc, xc, y0, xc, yb, pen); lc(dc, xc, y0, xl + 1, y0 + r, pen);
        } else if (d == 2) {
            arc(dc, xc, ty, r, 0, 180, pen); ln(dc, xr, ty, xr, ty + 8, pen);
            lc(dc, xr, ty + 8, xl, yb, pen); lc(dc, xl, yb, xr, yb, pen);
        } else if (d == 3) {
            arc(dc, xc, ty, r, 0, 180, pen); ln(dc, xr, ty, xr, by, pen);
            arc(dc, xc, by, r, 180, 360, pen); lc(dc, xc - 2, mid, xr - 1, mid, pen);
        } else if (d == 4) {
            var y4 = y0 + DH * 2 / 3;
            lc(dc, xr - 3, y0, xl, y4, pen); lc(dc, xl, y4, xr + 2, y4, pen); lc(dc, xr - 3, y0, xr - 3, yb, pen);
        } else if (d == 5) {
            var yk = mid - 4;
            lc(dc, xr, y0, xl, y0, pen); lc(dc, xl, y0, xl, yk, pen); lc(dc, xl, yk, xc, yk, pen);
            arc(dc, xc, yk + r, r, 0, 90, pen); ln(dc, xr, yk + r, xr, by, pen);
            arc(dc, xc, by, r, 180, 360, pen);
        } else if (d == 6) {
            arc(dc, xc, ty, r, 0, 180, pen); ln(dc, xl, ty, xl, by, pen); arc(dc, xc, by, r, 180, 360, pen);
            ln(dc, xr, mid + r, xr, by, pen); arc(dc, xc, mid + r, r, 0, 90, pen); ln(dc, xl, mid, xc, mid, pen);
        } else if (d == 7) {
            lc(dc, xl, y0, xr, y0, pen); lc(dc, xr, y0, xl + 4, yb, pen);
        } else if (d == 9) {
            arc(dc, xc, ty, r, 0, 180, pen); ln(dc, xr, ty, xr, by, pen); arc(dc, xc, by, r, 180, 360, pen);
            ln(dc, xl, ty, xl, mid - r, pen); arc(dc, xc, mid - r, r, 180, 270, pen); lc(dc, xc, mid, xr - 1, mid, pen);
        }
    }

    // Straight stroke. Butt ends join the arcs cleanly; lc() adds round ends for free ends
    // and sharp corners (a cap where a line meets an arc would show as a bead).
    private function ln(dc as Graphics.Dc, x1 as Number, y1 as Number, x2 as Number, y2 as Number, pen as Number) as Void {
        dc.drawLine(s(x1), s(y1), s(x2), s(y2));
    }

    private function lc(dc as Graphics.Dc, x1 as Number, y1 as Number, x2 as Number, y2 as Number, pen as Number) as Void {
        dc.drawLine(s(x1), s(y1), s(x2), s(y2));
        var rr = (s(pen) - 1) / 2.0;
        dc.fillCircle(s(x1), s(y1), rr);
        dc.fillCircle(s(x2), s(y2), rr);
    }

    // counter-clockwise arc, degrees (0 = 3 o'clock), centred on the stroke
    private function arc(dc as Graphics.Dc, cx as Number, cy as Number, r as Number, a0 as Number, a1 as Number, pen as Number) as Void {
        dc.drawArc(s(cx), s(cy), s(r), Graphics.ARC_COUNTER_CLOCKWISE, a0, a1);
    }

    private function s(v as Numeric) as Number {
        return (v * _scale + 0.5).toNumber();
    }
}
