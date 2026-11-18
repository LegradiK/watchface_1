# watchface_1

A digital Garmin Connect IQ watch face written in Monkey C, built and tested for the **Forerunner 245**.

It shows the date and 24-hour time at the top, three bars for watch battery, Body Battery and heart rate in the middle, and a step-goal ring around the edge.

## Features

- **Time**: always 24-hour (`HH:MM`), in a custom bitmap font
- **Day and date**: day of the week (e.g. `TUE`) above the date as `YYYY.MM.DD`
- **Three bars**, one per row, each with an icon on the left and its value on the right:


  | Icon           | Shows         | Range       | Default colour |
  | ---------------- | --------------- | ------------- | ---------------- |
  | Battery        | Watch battery | 0–100      | Green          |
  | Heart          | Body Battery  | 0–100      | Blue           |
  | EKG pulse line | Heart rate    | 40–200 bpm | Red            |
- **Step ring**: fills clockwise from 12 o'clock towards the daily step goal (10,000 if no goal is set), with a footprints icon and the step count at the bottom
- **Missing data** shows as `--` with an empty bar instead of crashing
- **Adaptive layout**: positions are calculated from the real font sizes, so the face still fits if you remake the fonts at a different size
- **AMOLED support**: on AMOLED watches in low-power mode, only a dim, shifting time is drawn to avoid burn-in

All icons are drawn in code from basic shapes, so no image files are needed.

## Requirements

- [Connect IQ SDK](https://developer.garmin.com/connect-iq/sdk/) (built with SDK 9.2.0), installed through the SDK Manager
- Device files for the Forerunner 245 (`fr245`), downloaded in the SDK Manager
- [VS Code](https://code.visualstudio.com/) with the **Monkey C** extension by Garmin
- Java 8 or newer
- A developer key (Command Palette → **Monkey C: Generate a Developer Key**)
- Minimum API level: 3.2.0

## Project structure

```
watchface_1/
├── manifest.xml              # app ID, target devices, permissions, languages
├── monkey.jungle             # build configuration
├── resources/
│   ├── drawables/            # launcher icon
│   ├── fonts/
│   │   ├── fonts.xml         # declares TimeFont and SmallFont
│   │   ├── time.fnt / time.png    # large font for the time
│   │   └── small.fnt / small.png  # small font for everything else
│   └── strings/
└── source/
    ├── watchface_1App.mc     # app entry point; returns the view
    └── watchface_1View.mc    # all drawing and data reading
```

## Permissions

`manifest.xml` must include the **SensorHistory** permission, which is needed to read Body Battery:

```xml
<iq:permissions>
    <iq:uses-permission id="SensorHistory"/>
</iq:permissions>
```

You can add it through Command Palette → **Monkey C: Edit Permissions**.

## Fonts

The face uses two bitmap fonts made with [Hiero](https://libgdx.com/wiki/tools/hiero) from [Share Tech Mono](https://fonts.google.com/specimen/Share+Tech+Mono) (Google Fonts):


| Font ID     | File        | Suggested size | Characters                  |
| ------------- | ------------- | ---------------- | ----------------------------- |
| `TimeFont`  | `time.fnt`  | 48–64 px      | `0123456789:`               |
| `SmallFont` | `small.fnt` | 14–20 px      | `0123456789:. ` plus `A–Z` |

To make a font in Hiero:

1. Choose **File** as the source and browse to `ShareTechMono-Regular.ttf`.
2. Set the size and choose **Java** rendering.
3. Replace the sample text with only the characters you need, then click **Sample text**.
4. Set the color effect to white and all padding to 1 (or 0 for a tighter layout).
5. Check that **Glyph cache** shows **Pages: 1**.
6. **File → Save BMFont files (text)...**

Copy the `.fnt` and `.png` files into `resources/fonts/`. Make sure the `filter` in `fonts.xml` lists the same characters as the font:

```xml
<fonts>
    <font id="TimeFont" filename="time.fnt" filter="0123456789:" antialias="true"/>
    <font id="SmallFont" filename="small.fnt" filter="0123456789:. ABCDEFGHIJKLMNOPQRSTUVWXYZ" antialias="true"/>
</fonts>
```

If the fonts can't be loaded, the face falls back to Garmin's built-in fonts.

## Running in the simulator

1. Open `source/watchface_1View.mc` in VS Code.
2. Press **Ctrl+F5** (Run Without Debugging) and choose `fr245`.
3. Use the simulator menus to test:
   - **Simulation → Activity Monitoring**: steps
   - **Simulation → Activity Data**: heart rate
   - **Settings → Low Power Mode**: sleep behaviour
   - **File → View Memory**: memory usage

Use **F5** (debugging) to see crash details in the VS Code **Debug Console**.

### Linux notes

The simulator needs `libwebkit2gtk-4.0-37`. On Ubuntu 24.04 and newer it isn't in the default repositories, so it has to be installed from the Ubuntu 22.04 (jammy) repository pinned at low priority.

On Wayland, start the simulator in X11 mode to avoid display problems:

```bash
GDK_BACKEND=x11 "$(cat ~/.Garmin/ConnectIQ/current-sdk.cfg)/bin/simulator" &
```

## Installing on the watch

1. Command Palette → **Monkey C: Build for Device** → `fr245` → **Release**. This creates `bin/watchface_1.prg`.
2. On the watch, set **Settings → System → USB Mode → Mass Storage**.
3. Connect the watch by USB and copy the file:
   ```bash
   cp bin/watchface_1.prg /media/$USER/GARMIN/GARMIN/APPS/
   sync
   ```
4. Eject the drive, unplug the watch, then hold **UP → Watch Face** and select it.

## Customising

All the main settings are constants at the top of `watchface_1View.mc`:


| Constant                                                        | Controls                                      |
| ----------------------------------------------------------------- | ----------------------------------------------- |
| `COLOUR_BATTERY`, `COLOUR_BODY`, `COLOUR_HEART`, `COLOUR_STEPS` | Colour of each bar, its icon and its number   |
| `COLOUR_TRACK`                                                  | Colour of the empty part of the bars and ring |
| `HR_MIN`, `HR_MAX`                                              | Heart rate that counts as an empty / full bar |
| `BAR_HEIGHT`                                                    | Thickness of the bars                         |
| `RING_WIDTH`                                                    | Thickness of the step ring                    |
| `ICON_WIDTH`                                                    | Width reserved for each icon                  |

### Colours on the Forerunner 245

The 245 has a 64-colour MIP screen. Each colour channel can only be `00`, `55`, `AA` or `FF`, so colours made from those values display exactly (for example `0xFFFF55` or `0x55AAFF`). Any other value is rounded to the nearest of the 64 colours.

Some of Garmin's built-in colour names aren't quite what they sound like. For example, `Graphics.COLOR_YELLOW` is `0xFFAA00`, which looks amber. Use hex values when you need an exact shade.

## Troubleshooting


| Problem                               | Likely cause                                                                                  |
| --------------------------------------- | ----------------------------------------------------------------------------------------------- |
| `Cannot find entry point class`       | `entry` in `manifest.xml` doesn't match the App class name                                    |
| `Permission 'SensorHistory' required` | Permission missing from `manifest.xml`                                                        |
| `Undefined symbol`                    | A function or variable name was changed in one place but not another                          |
| **IQ!** on the screen                 | The app crashed at runtime; run with **F5** and check the Debug Console                       |
| Blank characters                      | The character isn't in the font, or isn't in the `filter` in `fonts.xml`                      |
| Simulator times out                   | A stuck simulator is still running; close it with `pkill -f bin/simulator` and start it again |

## Credits

- Font: [Share Tech Mono](https://fonts.google.com/specimen/Share+Tech+Mono) by Carrois Apostrophe, licensed under the [SIL Open Font License 1.1](https://openfontlicense.org). The bitmap versions in `resources/fonts/` are converted from the original TTF.
