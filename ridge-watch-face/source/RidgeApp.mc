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

    // Accent colour changed in Garmin Connect.
    function onSettingsChanged() as Void {
        if (_view != null) {
            _view.loadSettings();
        }
        WatchUi.requestUpdate();
    }
}
