import Toybox.Application;
import Toybox.Lang;
import Toybox.Position;
import Toybox.WatchUi;

class TopoApp extends Application.AppBase {

    private var _view as TopoView?;

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state as Dictionary?) as Void {
        startGps();
    }

    function onStop(state as Dictionary?) as Void {
        Position.enableLocationEvents(Position.LOCATION_DISABLE, method(:onPosition));
    }

    function onPosition(info as Position.Info) as Void {
        if (_view != null) {
            (_view as TopoView).setPosition(info);
        }
    }

    function getInitialView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] {
        var v = new TopoView();
        _view = v;
        v.setKeepAwake(!batterySaver());
        v.setPosition(Position.getInfo());   // centre on the last known position straight away
        return [v, new TopoDelegate(v)];
    }

    // Changed in Garmin Connect, or from the on-watch menu below.
    function onSettingsChanged() as Void {
        startGps();
        if (_view != null) {
            (_view as TopoView).setKeepAwake(!batterySaver());
        }
    }

    function batterySaver() as Boolean {
        var v = Application.Properties.getValue("BatterySaver");
        return (v instanceof Boolean) && v;
    }

    // Battery saver: GPS satellites only. Otherwise all systems for the best fix.
    private function startGps() as Void {
        Position.enableLocationEvents(Position.LOCATION_DISABLE, method(:onPosition));
        var config = batterySaver() ? Position.CONFIGURATION_GPS
                                    : Position.CONFIGURATION_GPS_GLONASS_GALILEO_BEIDOU_L1;
        if ((Position has :hasConfigurationSupport) && Position.hasConfigurationSupport(config)) {
            Position.enableLocationEvents({
                :acquisitionType => Position.LOCATION_CONTINUOUS,
                :configuration => config
            }, method(:onPosition));
        } else {
            Position.enableLocationEvents(Position.LOCATION_CONTINUOUS, method(:onPosition));
        }
    }
}

// UP zooms in, DOWN zooms out, hold UP (menu) for settings.
class TopoDelegate extends WatchUi.BehaviorDelegate {

    private var _view as TopoView;

    function initialize(view as TopoView) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    function onPreviousPage() as Boolean {
        _view.zoom(-1);
        return true;
    }

    function onNextPage() as Boolean {
        _view.zoom(1);
        return true;
    }

    function onMenu() as Boolean {
        var app = Application.getApp() as TopoApp;
        var menu = new WatchUi.Menu2({:title => WatchUi.loadResource(Rez.Strings.Settings) as String});
        menu.addItem(new WatchUi.ToggleMenuItem(
            WatchUi.loadResource(Rez.Strings.BatterySaver) as String,
            WatchUi.loadResource(Rez.Strings.BatterySaverSub) as String,
            :batterySaver, app.batterySaver(), null));
        WatchUi.pushView(menu, new SettingsDelegate(), WatchUi.SLIDE_UP);
        return true;
    }
}

class SettingsDelegate extends WatchUi.Menu2InputDelegate {

    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        if (item.getId() == :batterySaver) {
            Application.Properties.setValue("BatterySaver", (item as WatchUi.ToggleMenuItem).isEnabled());
            (Application.getApp() as TopoApp).onSettingsChanged();
        }
    }
}
