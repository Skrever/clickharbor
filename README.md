# ClickHarbor

**English** · [Русский](README.ru.md)

ClickHarbor is a native macOS app for configuring IO Airox and Aurora mice. It stores your settings directly on the mouse.

## Download

[Download the latest release](https://github.com/Skrever/clickharbor/releases/latest)

ClickHarbor requires **macOS 14 Sonoma or later**. The universal build supports Apple silicon and Intel Macs.

1. Download and open the file ending in `-macOS-universal.dmg` from the release assets.
2. Drag **ClickHarbor** to **Applications** in the disk image. If you downloaded the ZIP, unzip it and move `ClickHarbor.app` to **Applications**.
3. Open ClickHarbor and connect your mouse using a method from the table below.

The downloadable build uses ad hoc signing and is unnotarized. macOS may display a verification alert the first time you open it. [Apple’s guide to first-launch alerts](https://support.apple.com/en-us/102445)

## Supported mice

| Model | Connection |
| --- | --- |
| IO Airox | USB data cable |
| IO Aurora | USB data cable or the original 2.4 GHz receiver |

ClickHarbor shows a message when it detects an unsupported external mouse. If Aurora is asleep, move it or press a button to let the app reconnect.

## Using ClickHarbor

- Choose the number and active position of DPI stages. Set DPI for both axes together or edit X and Y separately.
- Pick a color for each DPI stage. Aurora also offers steady and breathing indicator modes, brightness, and breathing speed.
- Set the polling rate to 125, 250, 500, or 1000 Hz.
- Adjust debounce, lift-off distance, angle snapping, ripple control, and the idle sleep timer. The sensor and power controls depend on the mouse.
- Remap six buttons to mouse actions, keys, shortcuts, or media controls. Record and edit macros, set repeat behavior, and import or export macros as JSON.
- Save settings as named profiles on your Mac. Aurora can also switch onboard profiles when its firmware exposes them.
- Read battery and firmware information. Aurora offers receiver pairing and a factory reset when the connected device is identified.

The app interface is in Russian. Use **Считать** to read the mouse’s current settings and **Применить** to write your changes. ClickHarbor reads settings back after writing to confirm the result.

The interface follows the system’s light or dark appearance and respects macOS Reduce Motion.

DPI colors control the devices’ indicator. The Windows drivers for these models do not expose a separate body RGB zone. Firmware updates, Airox factory reset, and the Airox wireless receiver are outside the current support scope. ClickHarbor can install new Airox macros and recognize an existing assignment. The Airox interface does not expose the stored macro sequence for reading.

## Build from source

To build from source, use macOS 15 or later with the Xcode Command Line Tools and Swift 6.

```sh
./build.sh
```

The app is written to `build/ClickHarbor.app`. Run `./release.sh` to create the universal DMG and ZIP with their SHA-256 checksums in `build/`.
