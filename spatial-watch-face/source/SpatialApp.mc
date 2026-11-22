import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

class SpatialApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    private var _view as SpatialView?;

    function getInitialView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] {
        _view = new SpatialView();
        return [_view as SpatialView];
    }

    // Customize on the watch (face picker). Same properties as the Connect settings.
    function getSettingsView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] or Null {
        return new CustomizeMenu([["Hands", "Hands", ["Ivory", "Sage", "Sky"]], ["Data", "Data colour", ["Sage", "Ivory", "Orange"]]]).views();
    }

    function onSettingsChanged() as Void {
        if (_view != null) { (_view as SpatialView).loadSettings(); }
        WatchUi.requestUpdate();
    }
}
