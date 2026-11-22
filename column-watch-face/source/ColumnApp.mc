import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

class ColumnApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    private var _view as ColumnView?;

    function getInitialView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] {
        _view = new ColumnView();
        return [_view as ColumnView];
    }

    // Customize on the watch (face picker). Same properties as the Connect settings.
    function getSettingsView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] or Null {
        return new CustomizeMenu([["Accent", "Accent colour", ["Green", "Saffron", "Blue", "Pink", "White"]]]).views();
    }

    function onSettingsChanged() as Void {
        if (_view != null) { (_view as ColumnView).loadSettings(); }
        WatchUi.requestUpdate();
    }
}
