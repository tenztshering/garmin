import Toybox.Application;
import Toybox.Lang;
import Toybox.Test;
import Toybox.WatchUi;

// On-watch Customize menu: the watch's face picker shows it next to Delete.
// Each row is [property key, title, [choice labels]]. Selecting a row steps to the next
// choice, saves it (the same property the Garmin Connect settings use) and re-applies it.
class CustomizeMenu extends WatchUi.Menu2InputDelegate {

    private var _rows as Array;

    function initialize(rows as Array) {
        Menu2InputDelegate.initialize();
        _rows = rows;
    }

    function views() as [WatchUi.Views, WatchUi.InputDelegates] {
        var m = new WatchUi.Menu2({ :title => "Customize" });
        for (var i = 0; i < _rows.size(); i++) {
            m.addItem(new WatchUi.MenuItem((_rows[i] as Array)[1] as String, label(i), i, null));
        }
        return [m, self];
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var i = item.getId() as Number;
        var row = _rows[i] as Array;
        Application.Properties.setValue(row[0] as String, (current(i) + 1) % (row[2] as Array).size());
        item.setSubLabel(label(i));
        Application.getApp().onSettingsChanged();
        WatchUi.requestUpdate();
    }

    private function current(i as Number) as Number {
        var row = _rows[i] as Array;
        var v = Application.Properties.getValue(row[0] as String);
        return (v instanceof Number && v >= 0 && v < (row[2] as Array).size()) ? v : 0;
    }

    private function label(i as Number) as String {
        return ((_rows[i] as Array)[2] as Array)[current(i)] as String;
    }
}

// Reads a list setting, falling back to 0 when unset or out of range.
function settingIndex(key as String, n as Number) as Number {
    var v = Application.Properties.getValue(key);
    return (v instanceof Number && v >= 0 && v < n) ? v : 0;
}

// Selecting a row steps its setting to the next choice and wraps back to the first.
(:test)
function customizeStepsAndWraps(logger as Test.Logger) as Boolean {
    var rows = [["Accent", "Accent colour", ["A", "B", "C"]]];
    var key = "Accent";
    var saved = Application.Properties.getValue(key);
    Application.Properties.setValue(key, 1);
    var menu = new CustomizeMenu(rows);
    menu.views();
    var item = new WatchUi.MenuItem("Accent colour", "B", 0, null);
    menu.onSelect(item);
    Test.assertEqual(2, Application.Properties.getValue(key));
    Test.assertEqual("C", item.getSubLabel());
    menu.onSelect(item);
    Test.assertEqual(0, Application.Properties.getValue(key));
    Application.Properties.setValue(key, saved as Number);
    return true;
}
