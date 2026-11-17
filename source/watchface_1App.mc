import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

// Entry point of the watch face.
// The class name must match the "entry" attribute in manifest.xml.
class watchface_1App extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    // Called when the app starts
    function onStart(state as Dictionary?) as Void {
    }

    // Called when the app stops
    function onStop(state as Dictionary?) as Void {
    }

    // Returns the first view to show: our watch face
    function getInitialView() as [Views] or [Views, InputDelegates] {
        return [ new watchface_1View() ];
    }

    // Called when the user changes a setting in Garmin Connect
    // (or in the simulator's Edit Persistent Storage menu)
    function onSettingsChanged() as Void {
        WatchUi.requestUpdate();
    }
}

// Lets other code get the app object if needed
function getApp() as watchface_1App {
    return Application.getApp() as watchface_1App;
}