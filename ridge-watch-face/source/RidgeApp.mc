import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

class RidgeApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    private var _view as RidgeView?;

    function getInitialView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] {
        _view = new RidgeView();
        return [_view];
    }


    // Customize on the watch (face picker). Same properties as the Connect settings.
    function getSettingsView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] or Null {
        return new CustomizeMenu([["Accent", "Accent colour", ["Teal", "Glacier", "Lime", "Amber", "Coral", "White"]]]).views();
    }

    // Accent colour changed in Garmin Connect or the Customize menu.
    function onSettingsChanged() as Void {
        if (_view != null) {
            _view.loadSettings();
        }
        WatchUi.requestUpdate();
    }
}
