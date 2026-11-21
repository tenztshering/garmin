import Toybox.Activity;
import Toybox.ActivityRecording;
import Toybox.Application;
import Toybox.Attention;
import Toybox.FitContributor;
import Toybox.Lang;
import Toybox.Position;
import Toybox.System;
import Toybox.WatchUi;

// Kora: a walking activity that counts circumambulations of a chorten.
// START locks your position; every time you walk round and come back, the round count
// goes up, the watch buzzes and a lap is added. The ring fills towards a goal
// (3-108), or with no goal shows where you are round the circuit. Saved to Garmin Connect as a walk with a
// "rounds" field.
class KoraApp extends Application.AppBase {

    var fix as Boolean = false;
    var counter as RoundCounter?;
    var goal as Number = 0;             // 0 = no goal: the ring shows your position instead
    private var _session as ActivityRecording.Session?;
    private var _field as FitContributor.Field?;

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state as Dictionary?) as Void {
        var g = Application.Properties.getValue("Goal");
        if (g instanceof Number && GOALS.indexOf(g) >= 0) { goal = g; }
        // all satellite systems: best fix next to a big chorten
        var config = Position.CONFIGURATION_GPS_GLONASS_GALILEO_BEIDOU_L1;
        if ((Position has :hasConfigurationSupport) && Position.hasConfigurationSupport(config)) {
            Position.enableLocationEvents({ :acquisitionType => Position.LOCATION_CONTINUOUS,
                :configuration => config }, method(:onPosition));
        } else {
            Position.enableLocationEvents(Position.LOCATION_CONTINUOUS, method(:onPosition));
        }
    }

    function onStop(state as Dictionary?) as Void {
        Position.enableLocationEvents(Position.LOCATION_DISABLE, method(:onPosition));
    }

    const GOALS = [0, 3, 7, 13, 21, 108];

    // UP/DOWN before START: step through the goals.
    function stepGoal(dir as Number) as Void {
        var i = GOALS.indexOf(goal);
        goal = GOALS[(i + dir + GOALS.size()) % GOALS.size()] as Number;
        Application.Properties.setValue("Goal", goal);
        WatchUi.requestUpdate();
    }

    function getInitialView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] {
        return [new KoraView(), new KoraDelegate()];
    }

    function onPosition(info as Position.Info) as Void {
        fix = info.accuracy >= Position.QUALITY_USABLE;
        var c = counter;
        if (fix && c != null && isRecording() && info.position != null) {
            var p = (info.position as Position.Location).toRadians();
            if (c.update(p[0].toFloat(), p[1].toFloat())) {
                onRound();
            }
        }
        WatchUi.requestUpdate();
    }

    function isRecording() as Boolean {
        return _session != null && (_session as ActivityRecording.Session).isRecording();
    }

    function hasSession() as Boolean {
        return _session != null;
    }

    function start() as Void {
        if (_session == null) {
            var s = ActivityRecording.createSession({ :name => "Kora", :sport => Activity.SPORT_WALKING });
            _field = s.createField("rounds", 0, FitContributor.DATA_TYPE_UINT16,
                { :mesgType => FitContributor.MESG_TYPE_SESSION, :units => "rounds" });
            (_field as FitContributor.Field).setData(0);
            _session = s;
            var r = Application.Properties.getValue("Radius");
            counter = new RoundCounter(r instanceof Number ? r.toFloat() : 8.0);
        }
        (_session as ActivityRecording.Session).start();
    }

    function pause() as Void {
        (_session as ActivityRecording.Session).stop();
    }

    // Lap button: count a round by hand when GPS can't see the sky.
    function manualRound() as Void {
        var c = counter;
        if (c != null && isRecording()) {
            c.add();
            onRound();
        }
    }

    private function onRound() as Void {
        (_field as FitContributor.Field).setData((counter as RoundCounter).count);
        (_session as ActivityRecording.Session).addLap();
        var n = (counter as RoundCounter).count;
        if (Attention has :vibrate) {
            // goal reached: long-short-long
            Attention.vibrate(n == goal
                ? [new Attention.VibeProfile(100, 600), new Attention.VibeProfile(0, 200), new Attention.VibeProfile(100, 600)]
                : [new Attention.VibeProfile(100, 400)]);
        }
        if (Attention has :playTone) {
            Attention.playTone(Attention.TONE_LAP);
        }
        WatchUi.requestUpdate();
    }

    function walked() as Number {
        var d = Activity.getActivityInfo().elapsedDistance;
        return d != null ? d.toNumber() : 0;
    }

    function save() as Void {
        (_session as ActivityRecording.Session).save();
        _session = null;
    }

    function discard() as Void {
        (_session as ActivityRecording.Session).discard();
        _session = null;
    }
}

// START: start / pause (opens Resume, Save, Discard). BACK: lap = count a round by hand.
// UP/DOWN before starting: choose the goal.
// Screen taps are ignored so a sleeve can't stop the activity.
class KoraDelegate extends WatchUi.BehaviorDelegate {

    function initialize() {
        BehaviorDelegate.initialize();
    }

    function onKey(evt as WatchUi.KeyEvent) as Boolean {
        if (evt.getKey() != WatchUi.KEY_ENTER) { return false; }
        var app = Application.getApp() as KoraApp;
        if (app.isRecording()) {
            app.pause();
            showStopMenu();
        } else {
            app.start();
        }
        WatchUi.requestUpdate();
        return true;
    }

    function onBack() as Boolean {
        var app = Application.getApp() as KoraApp;
        if (app.isRecording()) {
            app.manualRound();
            return true;
        }
        if (app.hasSession()) {          // paused: don't drop the activity by accident
            showStopMenu();
            return true;
        }
        return false;                    // nothing recorded: exit
    }

    function onSelect() as Boolean {
        return true;
    }

    function onPreviousPage() as Boolean {
        return stepGoal(1);
    }

    function onNextPage() as Boolean {
        return stepGoal(-1);
    }

    private function stepGoal(dir as Number) as Boolean {
        var app = Application.getApp() as KoraApp;
        if (app.hasSession()) { return false; }      // locked once walking
        app.stepGoal(dir);
        return true;
    }
}

function showStopMenu() as Void {
    var app = Application.getApp() as KoraApp;
    var c = app.counter;
    var n = c != null ? c.count : 0;
    var menu = new WatchUi.Menu2({ :title => n.toString() + (n == 1 ? " round" : " rounds") });
    menu.addItem(new WatchUi.MenuItem("Resume", null, :resume, null));
    menu.addItem(new WatchUi.MenuItem("Save", null, :save, null));
    menu.addItem(new WatchUi.MenuItem("Discard", null, :discard, null));
    WatchUi.pushView(menu, new StopMenuDelegate(), WatchUi.SLIDE_UP);
}

class StopMenuDelegate extends WatchUi.Menu2InputDelegate {

    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var app = Application.getApp() as KoraApp;
        var id = item.getId();
        if (id == :resume) {
            app.start();
            WatchUi.popView(WatchUi.SLIDE_DOWN);
        } else if (id == :save) {
            app.save();
            System.exit();
        } else {
            WatchUi.pushView(new WatchUi.Confirmation("Discard kora?"), new DiscardDelegate(), WatchUi.SLIDE_UP);
        }
    }
}

class DiscardDelegate extends WatchUi.ConfirmationDelegate {

    function initialize() {
        ConfirmationDelegate.initialize();
    }

    function onResponse(response as WatchUi.Confirm) as Boolean {
        if (response == WatchUi.CONFIRM_YES) {
            (Application.getApp() as KoraApp).discard();
            System.exit();
        }
        return true;
    }
}
