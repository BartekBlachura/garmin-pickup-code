import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

class PickupCodeApp extends Application.AppBase {

    private var _view as PickupCodeView?;

    function initialize() {
        AppBase.initialize();
    }

    function getInitialView() as [Views] or [Views, InputDelegates] {
        _view = new PickupCodeView();
        return [ _view ];
    }

    // On-device settings, reached from the activity settings on the watch
    // (Settings -> Trigger App Settings in the simulator).
    function getSettingsView() as [Views] or [Views, InputDelegates] or Null {
        var menu = new SettingsMenu();
        return [ menu, new SettingsMenuDelegate(menu) ];
    }

    // Called when the phone app changes the properties.
    function onSettingsChanged() as Void {
        var view = _view;
        if (view != null) {
            view.reload();
        }
        WatchUi.requestUpdate();
    }
}
