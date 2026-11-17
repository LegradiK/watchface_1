import Toybox.ActivityMonitor;
import Toybox.Activity;
import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.WatchUi;

// Digital watch face: time, date, battery ring, steps, seconds when awake.
class watchface_1View extends WatchUi.WatchFace {

    private var _isAwake as Boolean = true;
    private var _burnInProtection as Boolean = false;

    // Screen geometry, worked out once in onLayout
    private var _cx as Number = 0;   // centre x
    private var _cy as Number = 0;   // centre y
    private var _r as Number = 0;    // radius (half the shorter side)

    function initialize() {
        WatchFace.initialize();

        // AMOLED watches need burn-in protection in low-power mode
        var settings = System.getDeviceSettings();
        if (settings has :requiresBurnInProtection) {
            _burnInProtection = settings.requiresBurnInProtection;
        }
    }

    // Called once, when the screen size is known
    function onLayout(dc as Dc) as Void {
        _cx = dc.getWidth() / 2;
        _cy = dc.getHeight() / 2;
        _r = (_cx < _cy) ? _cx : _cy;
    }

    // Called when the face becomes visible
    function onShow() as Void {
    }

    // Called every time the watch wants a redraw:
    // about once a second when awake, once a minute when asleep
    function onUpdate(dc as Dc) as Void {
        if (dc has :setAntiAlias) {
            dc.setAntiAlias(true);
        }

        // Clear the screen
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        // AMOLED in low power: draw only a minimal time to avoid burn-in
        if (_burnInProtection && !_isAwake) {
            drawLowPowerTime(dc);
            return;
        }

        drawBattery(dc);
        drawDate(dc);
        drawTime(dc);
        drawHeartRate(dc);
    }

    // Called when the face is hidden
    function onHide() as Void {
    }

    // Wrist raised: redraw every second
    function onExitSleep() as Void {
        _isAwake = true;
        WatchUi.requestUpdate();
    }

    // Wrist down: redraw once a minute
    function onEnterSleep() as Void {
        _isAwake = false;
        WatchUi.requestUpdate();
    }

    // ---------------------------------------------------------------
    // Drawing helpers
    // ---------------------------------------------------------------

    // Hours and minutes in the centre, seconds underneath when awake
    private function drawTime(dc as Dc) as Void {
        var clock = System.getClockTime();
        var text = formatHour(clock.hour) + ":" + clock.min.format("%02d");

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_cx, _cy, Graphics.FONT_NUMBER_HOT, text,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

    }

    // Day, date and month above the time, e.g. "Tue 17 Nov"
    private function drawDate(dc as Dc) as Void {
        var info = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        var text = info.year.format("%04d") + "."
            + (info.month as Number).format("%02d") + "."
            + info.day.format("%02d");

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_cx, _cy - (_r * 0.45).toNumber(), Graphics.FONT_SMALL, text,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // Current heart rate below the time, e.g. "72 bpm" (or "-- bpm" if unknown)
    private function drawHeartRate(dc as Dc) as Void {
        var hr = getHeartRate();
        var text = (hr == null) ? "-- bpm" : hr.toString() + " bpm";

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_cx, _cy + (_r * 0.52).toNumber(), Graphics.FONT_TINY, text,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // Live heart rate if available, otherwise the latest stored reading
    private function getHeartRate() as Number? {
        var info = Activity.getActivityInfo();
        if (info != null && info.currentHeartRate != null) {
            return info.currentHeartRate;
        }

        if (ActivityMonitor has :getHeartRateHistory) {
            var sample = ActivityMonitor.getHeartRateHistory(1, true).next();
            if (sample != null && sample.heartRate != ActivityMonitor.INVALID_HR_SAMPLE) {
                return sample.heartRate;
            }
        }
        return null;   // no sensor data yet
    }

    // Ring round the edge that empties as the battery drains
    private function drawBattery(dc as Dc) as Void {
        var pct = System.getSystemStats().battery;   // Float, 0.0 to 100.0
        var colour = (pct < 20) ? Graphics.COLOR_RED : getAccentColour();
        var ringR = _r - 6;

        dc.setPenWidth(6);

        // Faint full track
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(_cx, _cy, ringR);

        // Filled part, clockwise from 12 o'clock.
        // Angles: 0 = 3 o'clock, 90 = 12 o'clock, counting anticlockwise.
        dc.setColor(colour, Graphics.COLOR_TRANSPARENT);
        if (pct >= 99.5) {
            dc.drawCircle(_cx, _cy, ringR);
        } else if (pct > 0) {
            var endAngle = 90 - (360 * pct / 100).toNumber();
            dc.drawArc(_cx, _cy, ringR, Graphics.ARC_CLOCKWISE, 90, endAngle);
        }

        dc.setPenWidth(1);
    }

    // AMOLED low-power mode: small dim time that shifts each minute
    // so the same pixels don't stay lit
    private function drawLowPowerTime(dc as Dc) as Void {
        var clock = System.getClockTime();
        var text = formatHour(clock.hour) + ":" + clock.min.format("%02d");

        // Move up to 10 px in a small pattern, based on the minute
        var dx = (clock.min % 5) * 4 - 8;
        var dy = ((clock.min / 5) % 5) * 4 - 8;

        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_cx + dx, _cy + dy, Graphics.FONT_NUMBER_MEDIUM, text,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // ---------------------------------------------------------------
    // Small utilities
    // ---------------------------------------------------------------

    // Respects the watch's 12/24-hour setting
    private function formatHour(hour as Number) as String {
        if (!System.getDeviceSettings().is24Hour) {
            hour = hour % 12;
            if (hour == 0) {
                hour = 12;
            }
            return hour.toString();
        }
        return hour.format("%02d");
    }

    // Reads the AccentColor setting from properties.xml,
    // falling back to blue if it's missing
    // Accent colour for the battery ring.
    // Hard-coded for now; switch to the setting once properties.xml exists.
    private function getAccentColour() as Number {
        return Graphics.COLOR_BLUE;
    }
}