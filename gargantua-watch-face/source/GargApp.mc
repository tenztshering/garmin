import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

class GargApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    private var _view as GargView?;

    function getInitialView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] {
        _view = new GargView();
        return [_view as GargView];
    }

    // Customize on the watch (face picker). Same properties as the Connect settings.
    function getSettingsView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] or Null {
        return new CustomizeMenu([["TimeColour", "Time colour", ["Cream", "White", "Amber"]], ["Animation", "Animation", ["Always", "Once per wake"]]]).views();
    }

    function onSettingsChanged() as Void {
        if (_view != null) { (_view as GargView).loadSettings(); }
        WatchUi.requestUpdate();
    }
}
