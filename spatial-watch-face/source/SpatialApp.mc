import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

class SpatialApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    function getInitialView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] {
        return [new SpatialView()];
    }
}
