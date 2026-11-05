import Toybox.Activity;
import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.Weather;
import Toybox.WatchUi;

// Ridge: big halftone time behind a mountain line drawing, weather + date above,
// the sun's path through the day below, and the next sunrise/sunset at the bottom.
// The halftone + mountains are one pre-rendered bitmap (tools/render.py) drawn over the
// digits. Coordinates are for 390x390 and scaled by s().
class RidgeView extends WatchUi.WatchFace {

    const WHITE = 0xFFFFFF;
    // accent colours: same order as tools/render.py ACCENTS and the settings list
    const ACCENTS = [0x40B8B0, 0x78C4F8, 0xB8E060, 0xF8B040, 0xF87868, 0xE8E8E8];
    const GREY  = 0x9A9A9A;
    const DARK  = 0x3C3C3C;
    const SUN   = 0xF8A828;
    const DIM   = 0x808080;

    const TIME_Y = 168;                 // must match tools/render.py preview / halftone band
    const OV_X = 20;                    // overlay placement, must match tools/render.py
    const OV_Y = 140;
    const GRAPH_X0 = 78;                // sun graph box
    const GRAPH_X1 = 312;
    const HORIZON_Y = 300;
    const AMP = 30;                     // curve height at solar noon, px

    private var _overlay as WatchUi.BitmapResource?;
    private var _accent as Number = 0x40B8B0;
    private const OVERLAYS = [Rez.Drawables.Overlay0, Rez.Drawables.Overlay1, Rez.Drawables.Overlay2,
        Rez.Drawables.Overlay3, Rez.Drawables.Overlay4, Rez.Drawables.Overlay5];
    private var _sleeping as Boolean = false;
    private var _scale as Float = 1.0;
    private var _fTime as Graphics.FontType = Graphics.FONT_NUMBER_THAI_HOT;
    private var _fTimeAod as Graphics.FontType = Graphics.FONT_NUMBER_HOT;
    private var _fMed as Graphics.FontType = Graphics.FONT_SMALL;
    private var _fSmall as Graphics.FontType = Graphics.FONT_XTINY;

    // weather + sun, refreshed once a minute
    private var _lastMin as Number = -1;
    private var _temp as String = "--";
    private var _lohi as String = "--/--";
    private var _cond as Number = -1;
    private var _rise as Float = 6.0;   // local hours
    private var _set as Float = 18.0;
    private var _hasSun as Boolean = false;

    function initialize() {
        WatchFace.initialize();
    }

    function onLayout(dc as Graphics.Dc) as Void {
        _scale = dc.getWidth() / 390.0;
        loadSettings();
        if (Graphics has :getVectorFont) {
            var b = ["RobotoCondensedBold", "RobotoRegular"];
            var t = Graphics.getVectorFont({ :face => b, :size => s(132) });
            var ta = Graphics.getVectorFont({ :face => ["RobotoCondensedRegular", "RobotoRegular"], :size => s(96) });
            var m = Graphics.getVectorFont({ :face => b, :size => s(27) });
            var sm = Graphics.getVectorFont({ :face => ["RobotoCondensedRegular", "RobotoRegular"], :size => s(21) });
            if (t != null) { _fTime = t; }
            if (ta != null) { _fTimeAod = ta; }
            if (m != null) { _fMed = m; }
            if (sm != null) { _fSmall = sm; }
        }
    }

    // Reads the accent setting (Garmin Connect app > watch face > Settings) and loads the
    // matching mountain overlay. Called at start and whenever the setting changes.
    function loadSettings() as Void {
        var i = 0;
        try {
            var v = Application.Properties.getValue("Accent");
            if (v instanceof Number && v >= 0 && v < ACCENTS.size()) { i = v; }
        } catch (e) {
            i = 0;
        }
        _accent = ACCENTS[i];
        _overlay = null;
        _overlay = WatchUi.loadResource(OVERLAYS[i]) as WatchUi.BitmapResource;
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
        var info = Gregorian.info(now, Time.FORMAT_MEDIUM);
        var time = timeString(info.hour as Number, info.min as Number);
        var cc = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        if (dc has :setAntiAlias) { dc.setAntiAlias(true); }

        if (_sleeping) {
            // Always-on: thinner, smaller, dim time only (~5% pixels), nudged 2 px a minute.
            var sh = [[0, 0], [2, 0], [0, 2], [-2, 0], [0, -2]];
            var o = sh[(info.min as Number) % 5];
            dc.setColor(DIM, Graphics.COLOR_TRANSPARENT);
            dc.drawText(s(195) + o[0], s(TIME_Y) + o[1], _fTimeAod, time, cc);
            return;
        }

        if (info.min != _lastMin) {
            refresh(now);
            _lastMin = info.min as Number;
        }

        drawBattery(dc);
        drawWeather(dc);
        drawDate(dc, info);

        dc.setColor(WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(s(195), s(TIME_Y), _fTime, time, cc);
        if (_overlay != null) {
            dc.drawBitmap(s(OV_X), s(OV_Y), _overlay as WatchUi.BitmapResource);
        }

        var hNow = (info.hour as Number) + (info.min as Number) / 60.0;
        drawSunGraph(dc, hNow);
        drawNextSun(dc, hNow);
    }

    // ---------------------------------------------------------------- data

    private function refresh(now as Time.Moment) as Void {
        var c = Weather.getCurrentConditions();
        if (c == null) { return; }
        var f = System.getDeviceSettings().temperatureUnits == System.UNIT_STATUTE;
        if (c.temperature != null) {
            _temp = deg(c.temperature as Numeric, f) + (f ? "°F" : "°C");
        }
        if (c.lowTemperature != null && c.highTemperature != null) {
            _lohi = deg(c.lowTemperature as Numeric, f) + "/" + deg(c.highTemperature as Numeric, f);
        }
        _cond = c.condition != null ? c.condition as Number : -1;

        // Weather's own location first; else the last GPS fix the watch knows about.
        var loc = c.observationLocationPosition;
        if (loc == null) {
            var ai = Activity.getActivityInfo();
            if (ai != null) { loc = ai.currentLocation; }
        }
        if (loc != null) {
            var r = Weather.getSunrise(loc, now);
            var st = Weather.getSunset(loc, now);
            if (r != null && st != null) {
                _rise = localHours(r);
                _set = localHours(st);
                _hasSun = true;
            }
        }
    }

    private function deg(c as Numeric, f as Boolean) as String {
        var v = f ? c * 9.0 / 5.0 + 32 : c.toFloat();
        return Math.round(v).toNumber().toString();
    }

    private function localHours(m as Time.Moment) as Float {
        var i = Gregorian.info(m, Time.FORMAT_SHORT);
        return (i.hour as Number) + (i.min as Number) / 60.0;
    }

    // ---------------------------------------------------------------- top row

    private function drawBattery(dc as Graphics.Dc) as Void {
        var pct = System.getSystemStats().battery;
        var x = s(181);
        var y = s(26);
        var w = s(26);
        var h = s(13);
        dc.setColor(GREY, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(s(2));
        dc.drawRoundedRectangle(x, y, w, h, s(2));
        dc.fillRectangle(x + w, y + s(4), s(3), s(5));
        dc.setColor(pct > 15 ? _accent : 0xF04040, Graphics.COLOR_TRANSPARENT);
        var fill = ((w - s(6)) * pct / 100).toNumber();
        if (fill < 1) { fill = 1; }
        dc.fillRectangle(x + s(3), y + s(3), fill, h - s(6));
    }

    private function drawWeather(dc as Graphics.Dc) as Void {
        drawCondition(dc, s(80), s(84));
        var l = Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER;
        dc.setColor(WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(s(110), s(72), _fMed, _temp, l);
        dc.setColor(GREY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(s(110), s(98), _fSmall, _lohi, l);
        // divider
        dc.setColor(DARK, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(s(2));
        dc.drawLine(s(196), s(60), s(196), s(110));
    }

    private function drawDate(dc as Graphics.Dc, info as Gregorian.Info) as Void {
        var l = Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER;
        var date = Lang.format("$1$ $2$", [(info.month as String).toUpper(), (info.day as Number).format("%02d")]);
        dc.setColor(WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(s(208), s(72), _fMed, date, l);
        dc.setColor(_accent, Graphics.COLOR_TRANSPARENT);
        dc.drawText(s(208), s(98), _fMed, weekday(info), l);
    }

    private function weekday(info as Gregorian.Info) as String {
        // FORMAT_MEDIUM gives "Mon"; the face wants the full name.
        var names = ["SUNDAY", "MONDAY", "TUESDAY", "WEDNESDAY", "THURSDAY", "FRIDAY", "SATURDAY"];
        var n = Gregorian.info(Time.now(), Time.FORMAT_SHORT).day_of_week as Number;
        return names[n - 1];
    }

    // Small icon for the current weather: sun, sun + cloud, cloud, or cloud + rain.
    private function drawCondition(dc as Graphics.Dc, x as Number, y as Number) as Void {
        var c = _cond;
        var sun = c == Weather.CONDITION_CLEAR || c == Weather.CONDITION_MOSTLY_CLEAR;
        var part = c == Weather.CONDITION_PARTLY_CLOUDY || c == Weather.CONDITION_PARTLY_CLEAR;
        var rain = c == Weather.CONDITION_RAIN || c == Weather.CONDITION_LIGHT_RAIN
            || c == Weather.CONDITION_HEAVY_RAIN || c == Weather.CONDITION_SHOWERS
            || c == Weather.CONDITION_SCATTERED_SHOWERS || c == Weather.CONDITION_THUNDERSTORMS
            || c == Weather.CONDITION_DRIZZLE || c == Weather.CONDITION_CHANCE_OF_SHOWERS;
        if (sun || part) {
            dc.setColor(SUN, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(x + s(sun ? 0 : 6), y - s(sun ? 0 : 8), s(sun ? 13 : 10));
            if (sun) { return; }
        }
        // cloud
        dc.setColor(WHITE, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x - s(8), y + s(2), s(8));
        dc.fillCircle(x + s(2), y - s(3), s(10));
        dc.fillCircle(x + s(11), y + s(3), s(7));
        dc.fillRoundedRectangle(x - s(16), y + s(2), s(34), s(9), s(4));
        if (rain) {
            dc.setColor(_accent, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(s(2));
            for (var i = -1; i <= 1; i++) {
                dc.drawLine(x + s(i * 9 + 2), y + s(15), x + s(i * 9 - 2), y + s(23));
            }
        }
    }

    // ---------------------------------------------------------------- sun graph

    // 24 h across the box, midnight at both ends. The curve crosses the horizon at sunrise
    // and sunset; above it (daylight) is teal, below it grey. White dot = now.
    private function drawSunGraph(dc as Graphics.Dc, hNow as Float) as Void {
        var x0 = GRAPH_X0;
        var x1 = GRAPH_X1;
        // faint dotted grid, one column per 2 h
        dc.setColor(DARK, Graphics.COLOR_TRANSPARENT);
        for (var i = 0; i <= 12; i++) {
            var gx = s(x0 + (x1 - x0) * i / 12);
            for (var gy = HORIZON_Y - 34; gy <= HORIZON_Y + 22; gy += 4) {
                dc.drawPoint(gx, s(gy));
            }
        }
        // horizon
        dc.setColor(WHITE, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(s(2));
        dc.drawLine(s(x0 - 14), s(HORIZON_Y), s(x1 + 14), s(HORIZON_Y));

        var px = 0;
        var py = 0;
        for (var i = 0; i <= 48; i++) {
            var h = i / 2.0;
            var x = s(x0 + (x1 - x0) * h / 24.0);
            var y = s(curveY(h));
            if (i > 0) {
                dc.setColor(y <= s(HORIZON_Y) ? _accent : GREY, Graphics.COLOR_TRANSPARENT);
                dc.setPenWidth(s(3));
                dc.drawLine(px, py, x, y);
            }
            px = x;
            py = y;
        }
        var nx = s(x0 + (x1 - x0) * hNow / 24.0);
        var ny = s(curveY(hNow));
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(nx, ny, s(9));
        dc.setColor(WHITE, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(nx, ny, s(6));
    }

    private function curveY(h as Float) as Float {
        var noon = (_rise + _set) / 2.0;
        var c0 = Math.cos(Math.PI * (_set - _rise) / 24.0);     // value at sunrise/sunset
        var v = (Math.cos(2 * Math.PI * (h - noon) / 24.0) - c0) / (1 - c0);
        return HORIZON_Y - AMP * v;
    }

    // Next sunrise or sunset, with a half-sun icon between hours and minutes.
    private function drawNextSun(dc as Graphics.Dc, hNow as Float) as Void {
        var y = s(350);
        var t = (hNow < _rise || hNow >= _set) ? _rise : _set;
        var hs = "--";
        var ms = "--";
        if (_hasSun) {
            var hh = t.toNumber();
            var mm = ((t - hh) * 60).toNumber();
            if (!System.getDeviceSettings().is24Hour) {
                hh = hh % 12;
                if (hh == 0) { hh = 12; }
            }
            hs = hh.format("%02d");
            ms = mm.format("%02d");
        }
        dc.setColor(_hasSun ? WHITE : GREY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(s(176), y, _fMed, hs, Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText(s(214), y, _fMed, ms, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        drawHalfSun(dc, s(195), y, t == _rise);
    }

    private function drawHalfSun(dc as Graphics.Dc, x as Number, y as Number, rising as Boolean) as Void {
        dc.setColor(_accent, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x, y + s(3), s(9));
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(x - s(12), y + s(4), s(24), s(10));
        dc.setColor(_accent, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(s(2));
        dc.drawLine(x - s(14), y + s(6), x + s(14), y + s(6));
        // small arrow: up for sunrise, down for sunset
        var ay = y - s(14);
        var d = rising ? -s(4) : s(4);
        dc.drawLine(x - s(4), ay - d, x, ay + d);
        dc.drawLine(x + s(4), ay - d, x, ay + d);
    }

    private function timeString(h as Number, m as Number) as String {
        if (!System.getDeviceSettings().is24Hour) {
            h = h % 12;
            if (h == 0) { h = 12; }
        }
        return Lang.format("$1$:$2$", [h.format("%02d"), m.format("%02d")]);
    }

    private function s(v as Numeric) as Number {
        return (v * _scale).toNumber();
    }
}
