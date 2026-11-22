import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.WatchUi;

// Replays the black-hole loop while awake, or stops after one pass ("Once per wake").
class GargLoop extends WatchUi.AnimationDelegate {

    private var _view as WeakReference;

    function initialize(view as GargView) {
        AnimationDelegate.initialize();
        _view = view.weak();
    }

    function onAnimationEvent(event as WatchUi.AnimationEvent, options as Dictionary) as Void {
        if (event == WatchUi.ANIMATION_EVENT_COMPLETE) {
            var v = _view.get() as GargView?;
            if (v != null) {
                v.loopDone();
            }
        }
    }
}

// Gargantua: a ray-traced black hole (tools/render.py) swallowing its accretion disk.
//
// Awake:      full-screen Monkey Motion loop + time layer on top.
// Always-on:  animation stopped; only a dim photon ring and the time, nudged every minute
//             (AMOLED burn-in protection, well under 10% of pixels lit).
class GargView extends WatchUi.WatchFace {

    const TIMES = [0xF2E6D6, 0xFFFFFF, 0xF8B040];   // Cream (the disk's hottest colour), White, Amber
    const MUTED = 0xB3A796;    // date: bright enough to stay crisp at 19 px
    const DIM   = 0x7A7A7A;
    const RING  = 0x5A4636;

    // Must match tools/render.py: hole centre (195,178), shadow radius 62 px on a 390 px screen.
    const HOLE_Y = 178;
    const HOLE_R = 62;
    const TIME_Y = 322;         // centre of the time, below the lower lensed arc
    const TEXT_TOP = 290;       // animation is ~black below here (max 36/255), so the text box can be opaque

    private var _anim as WatchUi.AnimationLayer;
    private var _text as WatchUi.Layer?;
    private var _sleeping as Boolean = false;      // drawing the always-on version
    private var _sleepCall as Boolean = false;     // onEnterSleep seen
    private var _playing as Boolean = false;
    private var _timeCol as Number = 0xF2E6D6;
    private var _once as Boolean = false;          // battery: one pass per wake instead of looping
    private var _scale as Float = 1.0;
    private var _fTime as Graphics.FontType = Graphics.FONT_NUMBER_MEDIUM;
    private var _fDate as Graphics.FontType = Graphics.FONT_XTINY;

    function initialize() {
        WatchFace.initialize();
        _anim = new WatchUi.AnimationLayer(Rez.Drawables.Gargantua, null);
        loadSettings();
    }

    function loadSettings() as Void {
        _timeCol = TIMES[settingIndex("TimeColour", TIMES.size())] as Number;
        _once = settingIndex("Animation", 2) == 1;
    }

    // End of one pass: loop again unless set to play once per wake.
    function loopDone() as Void {
        if (_once) {
            _playing = false;
        } else {
            play();
        }
    }

    function onLayout(dc as Graphics.Dc) as Void {
        var w = dc.getWidth();
        _scale = w / 390.0;
        if (Graphics has :getVectorFont) {
            var t = Graphics.getVectorFont({ :face => ["RobotoCondensedRegular", "RobotoRegular"], :size => s(60) });
            var d = Graphics.getVectorFont({ :face => ["RobotoCondensedBold", "RobotoCondensedRegular"], :size => s(19) });
            if (t != null) { _fTime = t; }
            if (d != null) { _fDate = d; }
        }
        // Opaque text box under the hole: anti-aliasing against solid black gives sharp edges,
        // against a transparent layer it leaves soft fringes.
        _text = new WatchUi.Layer({ :locX => s(75), :locY => s(TEXT_TOP), :width => s(240), :height => s(90) });
        addLayer(_anim);
        addLayer(_text);
    }

    function onShow() as Void {
        play();
    }

    function onHide() as Void {
        stop();
    }

    // The system's sleep signal; onUpdate combines it with the display mode.
    function onExitSleep() as Void {
        _sleepCall = false;
        WatchUi.requestUpdate();
    }

    function onEnterSleep() as Void {
        _sleepCall = true;
        WatchUi.requestUpdate();
    }

    // Also reached from onUpdate: the FR165 may switch to always-on without onEnterSleep.
    private function setLowPower(low as Boolean) as Void {
        _sleeping = low;
        _anim.setVisible(!low);
        (_text as WatchUi.Layer).setVisible(!low);
        if (low) { stop(); } else { play(); }
    }

    function play() as Void {
        if (_sleeping) {
            _playing = false;
            return;
        }
        _playing = true;
        _anim.play({ :delegate => new GargLoop(self) });
    }

    private function stop() as Void {
        if (_playing) {
            _anim.stop();
            _playing = false;
        }
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        if (dc has :setAntiAlias) { dc.setAntiAlias(true); }

        var now = Gregorian.info(Time.now(), Time.FORMAT_MEDIUM);
        var time = timeString(now);
        var date = Lang.format("$1$ $2$", [now.day_of_week, now.day]).toUpper();

        var low = isLowPower(_sleepCall);
        if (low != _sleeping) { setLowPower(low); }
        if (low) {
            drawAlwaysOn(dc, time, now.min as Number);
            return;
        }
        var tdc = (_text as WatchUi.Layer).getDc();
        if (tdc == null) { return; }
        tdc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        tdc.clear();
        if (tdc has :setAntiAlias) { tdc.setAntiAlias(true); }
        var cx = s(120);
        tdc.setColor(_timeCol, Graphics.COLOR_TRANSPARENT);
        tdc.drawText(cx, s(TIME_Y - TEXT_TOP), _fTime, time, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        tdc.setColor(MUTED, Graphics.COLOR_TRANSPARENT);
        tdc.drawText(cx, s(TIME_Y - TEXT_TOP + 44), _fDate, date, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // Dim outline of the shadow plus the time, burn-in safe (AlwaysOn.mc).
    private function drawAlwaysOn(dc as Graphics.Dc, time as String, min as Number) as Void {
        var o = aodShift(min);
        var cx = dc.getWidth() / 2 + o[0];
        dc.setColor(RING, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(1);
        dc.drawCircle(cx, s(HOLE_Y) + o[1], s(HOLE_R));
        dc.setColor(DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, s(TIME_Y) + o[1], _fTime, time, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        burnInMask(dc, min);
    }

    private function timeString(now as Gregorian.Info) as String {
        var h = now.hour as Number;
        if (!System.getDeviceSettings().is24Hour) {
            h = h % 12;
            if (h == 0) { h = 12; }
        }
        return Lang.format("$1$:$2$", [h, (now.min as Number).format("%02d")]);
    }

    private function s(v as Number) as Number {
        return (v * _scale).toNumber();
    }
}
