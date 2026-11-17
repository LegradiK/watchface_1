import Toybox.Activity;
import Toybox.ActivityMonitor;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.SensorHistory;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.WatchUi;

// Digital watch face:
//   - day of the week, YYYY.MM.DD date and 24-hour time at the top
//   - three horizontal bars underneath that shrink as the value drops:
//       battery icon = watch battery (0-100 %)
//       HP   = Body Battery  (0-100)
//       HR   = heart rate    (40-200 bpm)
//   - each row on one line: label/icon on the left, bar, number on the right
//   - a ring round the edge for steps towards the daily goal, count at the top
class watchface_1View extends WatchUi.WatchFace {

    // Fixed colour for each bar and its number (they never change)
    const COLOUR_BATTERY = Graphics.COLOR_GREEN;
    const COLOUR_BODY = Graphics.COLOR_BLUE;
    const COLOUR_HEART = Graphics.COLOR_RED;
    const COLOUR_STEPS = Graphics.COLOR_YELLOW;
    const COLOUR_TRACK = Graphics.COLOR_DK_GRAY;

    // Heart-rate range that maps onto an empty / full bar
    const HR_MIN = 40;
    const HR_MAX = 200;

    // Bar thickness and step-ring thickness, in pixels
    const BAR_HEIGHT = 6;
    const RING_WIDTH = 6;

    private var _isAwake as Boolean = true;
    private var _burnInProtection as Boolean = false;

    // Screen geometry, worked out once in onLayout
    private var _cx as Number = 0;   // centre x
    private var _cy as Number = 0;   // centre y
    private var _r as Number = 0;    // radius (half the shorter side)

    // Bar layout, worked out once in onLayout.
    // Each row is:  [label/icon]  [=========bar=========]  [number]
    private var _firstRowY as Number = 0;   // vertical centre of the first row
    private var _rowGap as Number = 0;      // distance between row centres
    private var _labelLeft as Number = 0;   // x where labels/icons start
    private var _barLeft as Number = 0;     // x where every bar starts
    private var _barWidth as Number = 0;    // full length of every bar
    private var _valueRight as Number = 0;  // x where numbers end (right-aligned)

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

        _firstRowY = _cy + (_r * 0.22).toNumber();
        _rowGap = (_r * 0.14).toNumber();

        // The rows must fit inside the round screen at the lowest row,
        // leaving room for the step ring round the edge
        var lowestEdge = _firstRowY + _rowGap * 2 + 8;
        var dy = lowestEdge - _cy;
        var halfWidth = Math.sqrt(_r * _r - dy * dy).toNumber() - 20;

        var labelColumn = 24;   // room for "HP", "HR" or the battery icon
        var valueColumn = 34;   // room for "100%"
        var padding = 4;        // gap between columns

        _labelLeft = _cx - halfWidth;
        _valueRight = _cx + halfWidth;
        _barLeft = _labelLeft + labelColumn + padding;
        _barWidth = (_valueRight - valueColumn - padding) - _barLeft;
    }

    function onShow() as Void {
    }

    // Called about once a second when awake, once a minute when asleep
    function onUpdate(dc as Dc) as Void {
        if (dc has :setAntiAlias) {
            dc.setAntiAlias(true);
        }

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        // AMOLED in low power: draw only a minimal time to avoid burn-in
        if (_burnInProtection && !_isAwake) {
            drawLowPowerTime(dc);
            return;
        }

        // Read all values once per redraw
        var battery = System.getSystemStats().battery.toNumber();   // 0-100
        var bodyBattery = getBodyBattery();                         // 0-100 or null
        var heartRate = getHeartRate();                             // bpm or null

        var hrFraction = 0.0;
        if (heartRate != null) {
            hrFraction = (heartRate - HR_MIN).toFloat() / (HR_MAX - HR_MIN);
        }

        drawStepRing(dc);
        drawDate(dc);
        drawTime(dc);

        // Three rows, one under the other
        drawBarRow(dc, _firstRowY, null, battery.toString() + "%",
            battery / 100.0, COLOUR_BATTERY);
        drawBarRow(dc, _firstRowY + _rowGap, "HP",
            (bodyBattery == null) ? "--" : bodyBattery.toString(),
            (bodyBattery == null) ? 0.0 : bodyBattery / 100.0, COLOUR_BODY);
        drawBarRow(dc, _firstRowY + _rowGap * 2, "HR",
            (heartRate == null) ? "--" : heartRate.toString(),
            hrFraction, COLOUR_HEART);
    }

    function onHide() as Void {
    }

    function onExitSleep() as Void {
        _isAwake = true;
        WatchUi.requestUpdate();
    }

    function onEnterSleep() as Void {
        _isAwake = false;
        WatchUi.requestUpdate();
    }

    // ---------------------------------------------------------------
    // Drawing helpers
    // ---------------------------------------------------------------

    // One row on a single line: label or icon on the left, bar in the middle,
    // number on the right. Pass null as the label to draw the battery icon.
    // The coloured part of the bar shrinks to the left as the fraction (0.0-1.0) drops.
    private function drawBarRow(dc as Dc, centreY as Number, label as String?,
            value as String, fraction as Float, colour as Number) as Void {
        if (fraction < 0.0) {
            fraction = 0.0;
        } else if (fraction > 1.0) {
            fraction = 1.0;
        }

        // Left: label or icon
        if (label == null) {
            drawBatteryIcon(dc, _labelLeft, centreY, fraction, colour);
        } else {
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(_labelLeft, centreY, Graphics.FONT_XTINY, label,
                Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        }

        // Middle: dark full-length track, then the coloured part
        var barY = centreY - BAR_HEIGHT / 2;
        dc.setColor(COLOUR_TRACK, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(_barLeft, barY, _barWidth, BAR_HEIGHT, BAR_HEIGHT / 2);

        var filled = (_barWidth * fraction).toNumber();
        if (filled >= BAR_HEIGHT) {
            dc.setColor(colour, Graphics.COLOR_TRANSPARENT);
            dc.fillRoundedRectangle(_barLeft, barY, filled, BAR_HEIGHT, BAR_HEIGHT / 2);
        }

        // Right: number
        dc.setColor(colour, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_valueRight, centreY, Graphics.FONT_XTINY, value,
            Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // Small battery icon, drawn with shapes: an outline, a terminal nub on
    // the right, and an inner fill that matches the charge level.
    // x = left edge, centreY = vertical centre of the icon.
    private function drawBatteryIcon(dc as Dc, x as Number, centreY as Number,
            fraction as Float, colour as Number) as Void {
        var w = 18;   // body width
        var h = 10;   // body height
        var top = centreY - h / 2;

        // Outline and nub
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(1);
        dc.drawRectangle(x, top, w, h);
        dc.fillRectangle(x + w, top + 3, 2, h - 6);

        // Fill inside the outline (2 px padding)
        var innerW = ((w - 4) * fraction).toNumber();
        if (innerW > 0) {
            dc.setColor(colour, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(x + 2, top + 2, innerW, h - 4);
        }
    }

    // Ring round the edge showing progress towards today's step goal,
    // filling clockwise from 12 o'clock, with the step count at the top.
    // Arc angles: 0 = 3 o'clock, 90 = 12 o'clock, counting anticlockwise.
    private function drawStepRing(dc as Dc) as Void {
        var info = ActivityMonitor.getInfo();
        var steps = (info.steps == null) ? 0 : info.steps;
        var goal = (info.stepGoal == null || info.stepGoal == 0) ? 10000 : info.stepGoal;

        var fraction = steps.toFloat() / goal;
        if (fraction > 1.0) {
            fraction = 1.0;
        }

        var radius = _r - RING_WIDTH / 2 - 1;
        dc.setPenWidth(RING_WIDTH);

        // Dark full track
        dc.setColor(COLOUR_TRACK, Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(_cx, _cy, radius);

        // Progress
        dc.setColor(COLOUR_STEPS, Graphics.COLOR_TRANSPARENT);
        if (fraction >= 0.995) {
            dc.drawCircle(_cx, _cy, radius);
        } else if (fraction > 0.005) {
            var endAngle = 90 - (360 * fraction).toNumber();
            dc.drawArc(_cx, _cy, radius, Graphics.ARC_CLOCKWISE, 90, endAngle);
        }
        dc.setPenWidth(1);

        // Step count above the date
        dc.setColor(COLOUR_STEPS, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_cx, _cy - (_r * 0.84).toNumber(), Graphics.FONT_XTINY, steps.toString(),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // 24-hour time near the top, e.g. "08:05"
    private function drawTime(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_cx, _cy - (_r * 0.16).toNumber(), Graphics.FONT_NUMBER_HOT, getTimeText(),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // Day of the week (e.g. "TUE") with the date as YYYY.MM.DD underneath
    private function drawDate(dc as Dc) as Void {
        var now = Time.now();

        // Day name in the watch's language, upper case
        var medium = Gregorian.info(now, Time.FORMAT_MEDIUM);
        var dayName = (medium.day_of_week as String).toUpper();

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_cx, _cy - (_r * 0.66).toNumber(), Graphics.FONT_XTINY, dayName,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Date as numbers
        var info = Gregorian.info(now, Time.FORMAT_SHORT);
        var text = info.year.format("%04d") + "."
            + (info.month as Number).format("%02d") + "."
            + info.day.format("%02d");

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_cx, _cy - (_r * 0.50).toNumber(), Graphics.FONT_TINY, text,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // AMOLED low-power mode: small dim time that shifts each minute
    private function drawLowPowerTime(dc as Dc) as Void {
        var min = System.getClockTime().min;
        var dx = (min % 5) * 4 - 8;
        var dy = ((min / 5) % 5) * 4 - 8;

        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_cx + dx, _cy + dy, Graphics.FONT_NUMBER_MEDIUM, getTimeText(),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // ---------------------------------------------------------------
    // Data helpers
    // ---------------------------------------------------------------

    // Always 24-hour, ignoring the watch's 12/24 setting
    private function getTimeText() as String {
        var clock = System.getClockTime();
        return clock.hour.format("%02d") + ":" + clock.min.format("%02d");
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
        return null;
    }

    // Latest Body Battery value (0-100), or null if the watch has none.
    // Needs the SensorHistory permission in manifest.xml.
    private function getBodyBattery() as Number? {
        if ((Toybox has :SensorHistory) && (SensorHistory has :getBodyBatteryHistory)) {
            var sample = SensorHistory.getBodyBatteryHistory({
                :period => 1,
                :order => SensorHistory.ORDER_NEWEST_FIRST
            }).next();
            if (sample != null && sample.data != null) {
                return sample.data.toNumber();
            }
        }
        return null;
    }
}