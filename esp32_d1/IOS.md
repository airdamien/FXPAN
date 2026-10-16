# iOS: fire the Mini D1 over BLE

Implement this in the FXPAN iOS app. Leave the Pi Zero USB path alone. The firmware and wire list are in this same directory (`esp32_d1/README.md`). The board is already flashed separately. Do not change `esp32_d1/`.

## What the board does

It advertises as `FXPAN-D1` with the Nordic UART service.

| UUID | Direction |
|------|-----------|
| `6E400001-B5A3-F393-E0A9-E50E24DCCA9E` | Service to scan for |
| `6E400002-B5A3-F393-E0A9-E50E24DCCA9E` | Write the command here (write, or write without response) |
| `6E400003-B5A3-F393-E0A9-E50E24DCCA9E` | Subscribe. Replies arrive as notifications |

Commands are one UTF-8 line ending in `\n`. Replies are one UTF-8 line ending in `\n`. Notifications can split a line, so accumulate until `\n`, the same way `Inbox` in `ios/FXPAN/SyncLink.swift` does.

| Send | Success reply |
|------|----------------|
| `PING\n` | `OK\n` |
| `FIRE\n` | `OK focus_ms=100 shutter_ms=300\n` |
| `FIRE <ms>\n` | `OK focus_ms=100 shutter_ms=<ms>\n` |

`<ms>` is the shutter hold. `1` through `120000`. The existing helper `SyncLink.hold(_:)` already computes it: `300` unless the photo is bulb, then the on-screen seconds as milliseconds, clamped to that same range. A line that does not start with `OK` is a failure. The board pulses before it replies, so the wait has to cover focus (100 ms) plus the shutter hold plus a few seconds, matching `SyncLink.fire`.

## App behavior

Add a third release value, `bt`, next to `usb` and `sync`. Do not send BLE traffic when release is `usb` or `sync`. Do not point `SyncLink` at the ESP32. `SyncLink` stays the Zero at `10.55.0.1:2323`.

When release is `bt`, a still capture uses the same sequence as `CameraHub.captureSync`: arm the paired Nikons, close the USB sessions, wait 800 ms, send `FIRE`, wait 200 ms, reopen USB, download from camera RAM. The only swap is `BLELink.fire` instead of `SyncLink.fire`. If the BLE write or the reply fails, reopen USB and throw, as `captureSync` already does when the Zero does not answer.

`PING` sets a ready flag the UI can show. Scan and connect when release is `bt`. A lost link clears ready and starts scanning again. Do not ping BLE while a `FIRE` is in flight.

## Files to change

- New `ios/FXPAN/BLELink.swift`. CoreBluetooth central. Scan for the service UUID above, connect, discover the two characteristics, subscribe to TX, write the line to RX. Public surface mirrors `SyncLink`: `ping() async -> Bool` and `fire(_ photo: Photo) async throws -> String`. Share the hold calculation with `SyncLink.hold` rather than copying the bulb math. `import CoreBluetooth`.
- `ios/FXPAN/CameraHub.swift` `capture()`. The `photo.drive.release == "sync"` branch calls `captureSync`. Also call it for `"bt"`, with the fire step selected by the release value.
- `ios/FXPAN/AppModel.swift`. `probeSync` and `watchSync` only ping the Zero, and the boot path auto-switches release to `sync` when `SyncLink.ping()` succeeds. Add a BLE ready flag. Do not let a BLE ping flip release to `sync`, and do not let a Zero ping flip release away from `bt`.
- `ios/FXPAN/Screens.swift` `releaseBlock`. The chip row is `[("usb", "USB"), ("sync", "Sync")]`. Add `("bt", "BT")`. The value string should say `BT` when connected and `BT · waiting` when it is not. The hint can say the shutter uses the Mini D1 instead of the Zero.
- `ios/FXPAN/HomeView.swift` Drive summary. It maps release to `Sync` or `USB`. Map `bt` to `BT`.
- `ios/FXPAN/Chrome.swift`. The top bar draws a Sync dot when `release == "sync"`. Draw the same kind of dot for `bt`, labeled `BT`, filled from the BLE ready flag.
- `ios/FXPAN.xcodeproj/project.pbxproj`. `GENERATE_INFOPLIST_FILE` is on. Add `INFOPLIST_KEY_NSBluetoothAlwaysUsageDescription` to both the Debug and Release target settings. Text: `FXPAN fires the shutter on the Mini D1 trigger over Bluetooth.` Add the new Swift file to the app target.

No background mode. The shutter is pressed with the app open. No classic Bluetooth serial profile. iOS will not see an SPP port.

## Done when

Release `USB` and `Sync` behave as they do now. Release `BT`, with a paired Nikon and a flashed Mini D1 in range, shows ready after the board connects, and the shutter closes USB, gets an `OK` line back, reopens USB, and downloads the frame. A missing board shows `BT · waiting` and the shutter fails without leaving the USB session closed.
