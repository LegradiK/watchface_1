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
//       battery icon = watch battery (0-100)
//       heart icon   = Body Battery  (0-100)
//       EKG icon     = heart rate    (40-200 bpm)
//   - each row on one line: icon on the left, bar, number on the right
//   - a ring round the edge for steps towards the daily goal,
//     with a footprints icon and the step count at the bottom
class watchface_1View extends WatchUi.WatchFace {

    // Fixed colour for each bar and its number (they never change)
    const COLOUR_BATTERY = Graphics.COLOR_GREEN;
    const COLOUR_BODY = Graphics.COLOR_BLUE;
    const COLOUR_HEART = Graphics.COLOR_RED;
    const COLOUR_STEPS = 0xFFFF55;
    const COLOUR_TRACK = Graphics.COLOR_DK_GRAY;

    // Heart-rate range that maps onto an empty / full bar
    const HR_MIN = 40;
    const HR_MAX = 200;

    // Which icon to draw at the start of each bar row
    const ICON_BATTERY = 0;
    const ICON_HEART = 1;   // Body Battery
    const ICON_PULSE = 2;   // heart rate (EKG line)

    // All icons are drawn in a box this wide, in pixels
    const ICON_WIDTH = 20;

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
    // Each row is:  [icon]  [=========bar=========]  [number]
    private var _firstRowY as Number = 0;   // vertical centre of the first row
    private var _rowGap as Number = 0;      // distance between row centres
    private var _labelLeft as Number = 0;   // x where labels/icons start
    private var _barLeft as Number = 0;     // x where every bar starts
    private var _barWidth as Number = 0;    // full length of every bar
    private var _valueRight as Number = 0;  // x where numbers end (right-aligned)

    // Vertical centres of the text, worked out in onLayout from the real font heights
    private var _dayY as Number = 0;
    private var _dateY as Number = 0;
    private var _timeY as Number = 0;
    private var _stepsY as Number = 0;

    // Custom font for the time (resources/fonts/fonts.xml, id "TimeFont"),
    // loaded once in onLayout
    private var _timeFont as FontResource? = null;

    // The same typeface at a small size for everything else
    // (resources/fonts/fonts.xml, id "SmallFont")
    private var _smallFont as FontResource? = null;

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

        _timeFont = WatchUi.loadResource(Rez.Fonts.TimeFont) as FontResource;
        _smallFont = WatchUi.loadResource(Rez.Fonts.SmallFont) as FontResource;

        layOut(dc);
    }

    // Works out every position from the actual heights and widths of the fonts,
    // so the layout still fits if you remake the fonts at a different size.
    //
    // Top to bottom:  day / date / time / three bar rows ... footprints + steps at the bottom
    private function layOut(dc as Dc) as Void {
        var smallH = dc.getFontHeight(getSmallFont());
        var timeH = dc.getFontHeight(getTimeFont());

        var gap = 2;                 // space between stacked items
        _rowGap = smallH + 2;        // distance between bar rows

        // Steps sit at the bottom, just inside the step ring
        _stepsY = _cy + _r - RING_WIDTH - 4 - smallH / 2;

        // Space available for the main block: below the ring at the top,
        // above the steps text at the bottom
        var top = _cy - _r + RING_WIDTH + 6;
        var bottom = _stepsY - smallH / 2 - gap;

        var blockH = smallH + smallH + timeH + gap * 2 + _rowGap * 3;
        var y = top + (bottom - top - blockH) / 2;   // centre the block in that space
        if (y < top) {
            y = top;   // fonts too big to fit: start at the top and let it overflow downwards
        }

        _dayY = y + smallH / 2;
        y += smallH;
        _dateY = y + smallH / 2;
        y += smallH + gap;
        _timeY = y + timeH / 2;
        y += timeH + gap;
        _firstRowY = y + _rowGap / 2;

        // Widths: the rows must fit inside the round screen at the lowest row,
        // leaving room for the step ring round the edge
        var lowestEdge = _firstRowY + _rowGap * 2 + smallH / 2;
        var dy = lowestEdge - _cy;
        if (dy > _r - 30) {
            dy = _r - 30;   // safety: never take the square root of a negative number
        }
        var halfWidth = Math.sqrt(_r * _r - dy * dy).toNumber() - RING_WIDTH - 8;

        // Icon column
        var labelColumn = ICON_WIDTH;

        // Value column: wide enough for "200"
        var valueColumn = dc.getTextWidthInPixels("200", getSmallFont());
        var padding = 4;

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
        drawBarRow(dc, _firstRowY, ICON_BATTERY, battery.toString(),
            battery / 100.0, COLOUR_BATTERY);
        drawBarRow(dc, _firstRowY + _rowGap, ICON_HEART,
            (bodyBattery == null) ? "--" : bodyBattery.toString(),
            (bodyBattery == null) ? 0.0 : bodyBattery / 100.0, COLOUR_BODY);
        drawBarRow(dc, _firstRowY + _rowGap * 2, ICON_PULSE,
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

    // One row on a single line: icon on the left, bar in the middle,
    // number on the right. The coloured part of the bar shrinks to the left
    // as the fraction (0.0-1.0) drops.
    private function drawBarRow(dc as Dc, centreY as Number, icon as Number,
            value as String, fraction as Float, colour as Number) as Void {
        if (fraction < 0.0) {
            fraction = 0.0;
        } else if (fraction > 1.0) {
            fraction = 1.0;
        }

        // Left: icon
        if (icon == ICON_BATTERY) {
            drawBatteryIcon(dc, _labelLeft, centreY, fraction, colour);
        } else if (icon == ICON_HEART) {
            drawHeartIcon(dc, _labelLeft, centreY, colour);
        } else {
            drawPulseIcon(dc, _labelLeft, centreY, colour);
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
        dc.drawText(_valueRight, centreY, getSmallFont(), value,
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

    // Heart, drawn from two circles (the top bumps) and a triangle (the point).
    // x = left edge of the icon box, centreY = vertical centre.
    private function drawHeartIcon(dc as Dc, x as Number, centreY as Number,
            colour as Number) as Void {
        var cx = x + ICON_WIDTH / 2;   // middle of the icon box
        var top = centreY - 3;         // centre line of the two bumps

        dc.setColor(colour, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(cx - 3, top, 4);
        dc.fillCircle(cx + 3, top, 4);
        dc.fillPolygon([
            [cx - 7, top + 1],
            [cx + 7, top + 1],
            [cx, centreY + 7]
        ]);
    }

    // EKG pulse line: flat, small bump, tall spike, dip, flat.
    // x = left edge of the icon box, centreY = the flat baseline.
    private function drawPulseIcon(dc as Dc, x as Number, centreY as Number,
            colour as Number) as Void {
        var points = [
            [x,      centreY],
            [x + 5,  centreY],
            [x + 7,  centreY - 2],
            [x + 9,  centreY],
            [x + 11, centreY - 7],
            [x + 13, centreY + 5],
            [x + 15, centreY],
            [x + 20, centreY]
        ];

        dc.setColor(colour, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        for (var i = 0; i < points.size() - 1; i++) {
            var a = points[i];
            var b = points[i + 1];
            dc.drawLine(a[0], a[1], b[0], b[1]);
        }
        dc.setPenWidth(1);
    }

    // Two footprints, drawn from ellipses (soles) and circles (heels),
    // the right foot a little higher than the left.
    // x = left edge of the icon box, centreY = vertical centre.
    private function drawFeetIcon(dc as Dc, x as Number, centreY as Number,
            colour as Number) as Void {
        dc.setColor(colour, Graphics.COLOR_TRANSPARENT);

        // Left foot
        dc.fillEllipse(x + 5, centreY - 1, 3, 4);
        dc.fillCircle(x + 5, centreY + 5, 2);

        // Right foot, raised
        dc.fillEllipse(x + 14, centreY - 4, 3, 4);
        dc.fillCircle(x + 14, centreY + 2, 2);
    }

    // Ring round the edge showing progress towards today's step goal,
    // filling clockwise from 12 o'clock, with footprints and the step count at the bottom.
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

        // Footprints icon and step count at the bottom, centred together
        var text = steps.toString();
        var textW = dc.getTextWidthInPixels(text, getSmallFont());
        var totalW = ICON_WIDTH + 4 + textW;
        var left = _cx - totalW / 2;

        drawFeetIcon(dc, left, _stepsY, COLOUR_STEPS);

        dc.setColor(COLOUR_STEPS, Graphics.COLOR_TRANSPARENT);
        dc.drawText(left + ICON_WIDTH + 4, _stepsY, getSmallFont(), text,
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // 24-hour time near the top, e.g. "08:05"
    private function drawTime(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_cx, _timeY, getTimeFont(), getTimeText(),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // Day of the week (e.g. "TUE") with the date as YYYY.MM.DD underneath
    private function drawDate(dc as Dc) as Void {
        var now = Time.now();

        // Day name in the watch's language, upper case
        var medium = Gregorian.info(now, Time.FORMAT_MEDIUM);
        var dayName = (medium.day_of_week as String).toUpper();

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_cx, _dayY, getSmallFont(), dayName,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Date as numbers
        var info = Gregorian.info(now, Time.FORMAT_SHORT);
        var text = info.year.format("%04d") + "."
            + (info.month as Number).format("%02d") + "."
            + info.day.format("%02d");

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_cx, _dateY, getSmallFont(), text,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // AMOLED low-power mode: small dim time that shifts each minute
    private function drawLowPowerTime(dc as Dc) as Void {
        var min = System.getClockTime().min;
        var dx = (min % 5) * 4 - 8;
        var dy = ((min / 5) % 5) * 4 - 8;

        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_cx + dx, _cy + dy, getTimeFont(), getTimeText(),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // ---------------------------------------------------------------
    // Data helpers
    // ---------------------------------------------------------------

    // Custom fonts, falling back to built-in ones if they haven't loaded
    private function getTimeFont() {
        return (_timeFont != null) ? _timeFont : Graphics.FONT_NUMBER_HOT;
    }

    private function getSmallFont() {
        return (_smallFont != null) ? _smallFont : Graphics.FONT_XTINY;
    }

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