import Toybox.Activity;
import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Timer;
import Toybox.WatchUi;

// One hero: the round count, white, sitting on the chorten's dome. Everything else steps back:
// the chorten is a dim background, the time and stats are soft grey, the ring is thin.
// Ring: rounds towards the goal (one segment per round up to 21, solid for 108), or with no
// goal your position round the circuit from the start line (the tick at 12 o'clock).
// Paused dims the count and ring so the stopped state reads at a glance.
class KoraView extends WatchUi.View {

    const WHITE   = 0xFFFFFF;
    const SAFFRON = 0xF8A420;
    const SAFF_DIM = 0x7C5410;   // paused ring
    const SOFT    = 0xC8C0B0;   // time and stats
    const MUTED   = 0x8A8478;   // hints, paused count
    const TRACK   = 0x2A2622;
    const GREEN   = 0x68D868;
    const RED     = 0xF85050;

    private var _bg as WatchUi.BitmapResource?;
    private var _timer as Timer.Timer = new Timer.Timer();
    private var _scale as Float = 1.0;

    function initialize() {
        View.initialize();
    }

    function onLayout(dc as Graphics.Dc) as Void {
        _scale = dc.getWidth() / 390.0;
        _bg = WatchUi.loadResource(Rez.Drawables.Chorten) as WatchUi.BitmapResource;
    }

    function onShow() as Void {
        _timer.start(method(:tick), 1000, true);
    }

    function onHide() as Void {
        _timer.stop();
    }

    function tick() as Void {
        WatchUi.requestUpdate();
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var app = Application.getApp() as KoraApp;
        var c = dc.getWidth() / 2;
        dc.setColor(WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        if (dc has :setAntiAlias) { dc.setAntiAlias(true); }

        var bg = _bg as WatchUi.BitmapResource;
        dc.drawBitmap(c - bg.getWidth() / 2, s(82), bg);

        var counter = app.counter;
        var n = counter != null ? counter.count : 0;
        var info = Activity.getActivityInfo();
        var goal = app.goal;
        var started = app.hasSession();
        var paused = started && !app.isRecording();
        var done = goal > 0 && n >= goal;
        var lit = paused ? SAFF_DIM : done ? GREEN : SAFFRON;
        var CJ = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;

        drawRing(dc, c, goal, n, lit, counter, app.isRecording());

        // top: state before and while starting, then the elapsed time
        if (!started) {
            dc.setColor(app.fix ? GREEN : MUTED, Graphics.COLOR_TRANSPARENT);
            dc.drawText(c, s(app.fix ? 42 : 50), Graphics.FONT_TINY, app.fix ? "GPS ready" : "Finding GPS…", CJ);
            if (app.fix) {
                dc.setColor(WHITE, Graphics.COLOR_TRANSPARENT);
                dc.drawText(c, s(72), Graphics.FONT_XTINY, "Press START", CJ);
            }
        } else if (paused) {
            dc.setColor(SAFFRON, Graphics.COLOR_TRANSPARENT);
            dc.drawText(c, s(50), Graphics.FONT_TINY, "PAUSED", CJ);
        } else {
            var locking = counter != null && !counter.hasAnchor();
            dc.setColor(locking ? MUTED : SOFT, Graphics.COLOR_TRANSPARENT);
            dc.drawText(c, s(50), Graphics.FONT_TINY, locking ? "Locking start…" : clock(info.timerTime), CJ);
        }

        // the count
        dc.setColor(paused ? MUTED : WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(c, s(192), Graphics.FONT_NUMBER_THAI_HOT, n.toString(), CJ);
        var label = done ? "GOAL REACHED"
            : !started ? (goal == 0 ? "NO GOAL" : "GOAL " + goal.toString())
            : goal == 0 ? (n == 1 ? "ROUND" : "ROUNDS") : "OF " + goal.toString();
        dc.setColor(done ? GREEN : SAFFRON, Graphics.COLOR_TRANSPARENT);
        dc.drawText(c, s(268), Graphics.FONT_XTINY, label, CJ);

        // bottom: how to change the goal before starting; distance · heart rate after
        if (!started) {
            dc.setColor(MUTED, Graphics.COLOR_TRANSPARENT);
            dc.drawText(c, s(312), Graphics.FONT_XTINY, "UP / DOWN  change goal", CJ);
            dc.drawText(c, s(340), Graphics.FONT_XTINY, app.batterySaver() ? "Battery saver on" : "Hold UP  settings", CJ);
            return;
        }
        var km = (app.walked() / 1000.0).format("%.2f") + " km";
        var hr = info.currentHeartRate != null ? "   " + info.currentHeartRate.toString() + " bpm" : "";
        dc.setColor(SOFT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(c, s(312), Graphics.FONT_TINY, km + hr, CJ);
        if (app.isRecording() && !app.fix) {
            dc.setColor(RED, Graphics.COLOR_TRANSPARENT);
            dc.drawText(c, s(342), Graphics.FONT_XTINY, "weak GPS", CJ);
        }
    }

    private function drawRing(dc as Graphics.Dc, c as Number, goal as Number, n as Number, lit as Number,
            counter as RoundCounter?, recording as Boolean) as Void {
        var r = c - s(6);
        dc.setPenWidth(s(6));
        if (goal > 0 && goal <= 21) {
            var seg = 360.0 / goal;
            for (var i = 0; i < goal; i++) {
                dc.setColor(i < n ? lit : TRACK, Graphics.COLOR_TRANSPARENT);
                dc.drawArc(c, c, r, Graphics.ARC_CLOCKWISE, (90 - i * seg - 1.5).toNumber(),
                    (90 - (i + 1) * seg + 1.5).toNumber());
            }
            return;
        }
        dc.setColor(TRACK, Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(c, c, r);
        if (goal > 0) {                                     // 108: one solid arc
            dc.setColor(lit, Graphics.COLOR_TRANSPARENT);
            if (n >= goal) {
                dc.drawCircle(c, c, r);
            } else if (n > 0) {
                dc.drawArc(c, c, r, Graphics.ARC_CLOCKWISE, 90, 90 - (360 * n / goal));
            }
            return;
        }
        // no goal: start-line tick at 12 o'clock, arc and dot to where you are now
        dc.setColor(SOFT, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(c - s(1), c - r - s(6), s(3), s(12));
        var pos = counter != null && recording ? counter.position() : null;
        if (pos != null) {
            var deg = (360 * pos).toNumber();
            dc.setColor(lit, Graphics.COLOR_TRANSPARENT);
            if (deg > 2) { dc.drawArc(c, c, r, Graphics.ARC_CLOCKWISE, 90, 90 - deg); }
            var rad = Math.toRadians(deg);
            var x = c + (r * Math.sin(rad)).toNumber();
            var y = c - (r * Math.cos(rad)).toNumber();
            dc.fillCircle(x, y, s(9));
            dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(x, y, s(3));
        }
    }

    private function clock(ms as Number?) as String {
        var t = ms != null ? ms / 1000 : 0;
        var h = t / 3600;
        var m = (t / 60) % 60;
        var sec = t % 60;
        return h > 0 ? h.toString() + ":" + m.format("%02d") + ":" + sec.format("%02d")
                     : m.toString() + ":" + sec.format("%02d");
    }

    private function s(v as Number) as Number {
        return (v * _scale).toNumber();
    }
}
