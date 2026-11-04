import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

// Entry point for the Pace watch face.
class PaceApp extends Application.AppBase {

    private var _view as PaceView?;

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state) {
    }

    function onStop(state) {
    }

    function getInitialView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] {
        _view = new PaceView();
        return [_view];
    }

    // Called when the colour setting is changed in Garmin Connect.
    function onSettingsChanged() as Void {
        if (_view != null) {
            _view.loadSettings();
        }
        WatchUi.requestUpdate();
    }
}
