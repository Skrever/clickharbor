# ClickHarbor

**English** · [Русский](README.ru.md)

ClickHarbor is a native macOS app for configuring IO Airox and Aurora mice. It stores your settings directly on the mouse.

## Download

[Download the latest release](https://github.com/Skrever/clickharbor/releases/latest)

ClickHarbor requires **macOS 14 Sonoma or later**. The universal build supports Apple silicon and Intel Macs.

1. Download the universal ZIP from the release assets. For version 2.0.0, the file is `ClickHarbor-2.0.0-macOS-universal.zip`.
2. Unzip it and move `ClickHarbor.app` to **Applications**.
3. Open ClickHarbor and connect your mouse using a method from the table below.

The downloadable build uses ad hoc signing and is unnotarized. macOS may display a verification alert the first time you open it. [Apple’s guide to first-launch alerts](https://support.apple.com/en-us/102445)

## Supported mice

| Model | Connection |
| --- | --- |
| IO Airox | USB data cable |
| IO Aurora | USB data cable or the original 2.4 GHz receiver |

ClickHarbor shows a message when it detects an unsupported external mouse. If Aurora is asleep, move it or press a button to let the app reconnect.

## Using ClickHarbor

- Edit DPI stages and choose the active stage.
- Set the polling rate to 125, 250, 500, or 1000 Hz.
- Adjust button debounce.
- Remap six buttons. Media actions include Play/Pause, Next Track, and Previous Track.

The app interface is in Russian. Use **Считать** to read the mouse’s current settings and **Применить** to write your changes. ClickHarbor reads settings back after writing to confirm the result.

The interface follows the system’s light or dark appearance and respects macOS Reduce Motion.

## Build from source

Install the Xcode Command Line Tools with Swift 6 on macOS, then run the build.

```sh
./build.sh
```

The app is written to `build/ClickHarbor.app`. Run `./release.sh` to package the universal ZIP and its SHA-256 checksum in `build/`.
