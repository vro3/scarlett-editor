# ScarlettEditor — direct iPad hardware prototype

The installed prototype is named Scarlett Direct.

An independent project by Vince Romanelli (Performance Percussion). It is not
affiliated with, endorsed by, or supported by Focusrite. Scarlett is a trademark of
its owner. It writes routing and mixer settings to real hardware: use it at your
own risk, with monitoring turned down. Released under the [MIT License](LICENSE); bundled third-party material keeps its
own license (see `THIRD-PARTY-NOTICES.txt` and `App/Fonts/`).

A native iPad app plus a USB DriverKit extension for **Scarlett 4i4 3rd Gen**
(USB 1235:8212). This is a development experiment, not a released product.
No Mac bridge, network service, firmware update, or firmware flash commands.

## Verified prototype result

On November 15, 2026, the M5 iPad Pro directly read firmware 1605 and routing,
changed Line Output 3 from Playback 3 to Off, verified the full routing table,
restored Playback 3, and verified again after app relaunch. App build 10 / driver
build 9. [Hardware evidence](docs/evidence/connection/RESULT.md).
The user confirmed silence during the isolated Playback 3 listening test in build 12.
The Acer USB-C hub also passed control/read-back after a larger PSU was connected;
the user also confirmed tone → silence → tone through the hub. Uninterrupted playback with
another audio app is not yet verified.

## Scope

Read routing, change **Line Output 3** to Off, Analogue 1–4 or Playback 1–4,
read the complete active routing table back, and restore that output's original
source. Only bank 0 (44.1/48 kHz) is written. All other entries in that bank are
preserved; higher-rate banks are untouched. The selected driver's own USB clock-frequency reads guard the rate; the iPad's active audio output is not a control-target or clock safety gate.

Recovery snapshots (all 18 original routing words, device USB serial, model, date,
and pending-write marker) are stored atomically in private Application Support.
Saving must succeed before a write. They survive app relaunch and driver updates
while the app data container is retained; uninstalling the app removes them.
Restore writes only the saved Line 3 source, preserving the device's current
unrelated routes. Restore is an explicit user action, not a guarantee after app
termination, cable loss, or a high-rate switch. Reconnect the same serial-numbered
interface at 44.1/48 kHz, Read, confirm low monitoring, then Restore.
Duplicate or missing serials block writes. USB serials are device-provided identity,
not cryptographic identity; duplicate serials across sequentially connected units
cannot be distinguished. Do not swap units sharing the same serial.

Build 14 temporarily blocks writes when more than one interface is visible to
the app, pending independent review and controlled hardware acceptance. The
sidebar is not an exhaustive inventory of all attached USB audio endpoints.
Every write requires explicit sidebar target selection and low-monitoring
confirmation. No automatic write or tone launch hooks remain in any configuration.

Line Output 3 shares the left headphone route on this model according to the
Linux `s4i4_gen3_info` port labels. Headphone coupling has not been independently
listened to in our hardware tests. Turn down both speaker and headphone levels.
Read-back is configuration evidence, not proof of audible isolation or uninterrupted
playback. Other apps must not change sample rate/configuration during a write.

## Build and test

Requirements: Xcode with iOS and DriverKit SDKs, Apple development team signing,
and an M-series iPad. The tested development destination is an M5 iPad Pro.
To build your own copy, set your own Apple development team and bundle identifiers
in `scripts/make_project.py`; the public copy carries placeholders.

```sh
python3 scripts/make_project.py
./scripts/test.sh
xcodebuild -project ScarlettDirect.xcodeproj -scheme ScarlettDirect \
  -configuration Debug -destination 'generic/platform=iOS' \
  -derivedDataPath /tmp/scarlett-mixer -allowProvisioningUpdates build
```

`make_project.py` generates the committed Xcode project, metadata and entitlements.
USB development entitlement specifies vendor 0x1235; matching is additionally
restricted to product 0x8212, interface 3, class 255. Specifying product in the
entitlement failed Xcode development-profile validation; vendor-only matched the
Apple-generated development profile. This is not evidence of distribution approval.

## Physical acceptance

1. Install the app including its signed driver on the M-series iPad.
2. Enable Scarlett Direct's driver in iPad Settings (search for Drivers).
3. Disconnect the Scarlett from the Mac and connect directly to the iPad,
   using powered USB equipment if needed. Turn monitoring down.
4. Open Scarlett Direct, explicitly select the 4i4 in the sidebar, and tap **Refresh**. A hardware reply
   must show firmware and the original output source before Apply is enabled.
5. Choose a different source for Line Output 3, acknowledge low monitoring level,
   then **Apply route**. Success requires exact full-table read-back.
6. Confirm the physical signal on output 3, then **Restore original**.
7. Repeat while a separate iPad audio app plays; verify playback is uninterrupted.

Do not report direct control proven until steps 4–6 have occurred on hardware.
A signed build or successful install is not a routing result.

Diagnostics: **Connection details → Share connection log** exports the log,
also stored at `Library/Caches/ScarlettHardwareLog.txt`. Normal launch only discovers
and reads. An outside routing change refuses Apply without writing; after reading,
**Use current routing as baseline** explicitly replaces the saved baseline.
That action is blocked while recovery is pending/uncertain. Restore can instead
recover just Line 3 while preserving current unrelated changes.

A command error aborts pending notification I/O and marks the protocol session
uninitialized. The next Read performs the handshake before GET_MUX; writes do not
implicitly reinitialize. Lost-ACK recovery on real USB remains an acceptance test.

## Sources and provenance

- Apple DriverKit iPad guide: https://developer.apple.com/documentation/driverkit/creating-drivers-for-ipados
- Apple user-client sample: https://developer.apple.com/documentation/driverkit/communicating-between-a-driverkit-extension-and-a-client-app
- Linux Scarlett protocol implementation (wire-format reference, GPL-2.0):
  https://github.com/torvalds/linux/blob/master/sound/usb/mixer_scarlett2.c
  (`s4i4_gen3_info`, USB packet header, init, GET_MUX, SET_MUX, port IDs).

Protocol serialization and routing logic here are independently written from
those protocol facts. No Linux driver source is included. The Apple sample was
used as an API/build reference; its license is preserved in THIRD-PARTY-NOTICES.txt.

## Listening acceptance

The former environment-triggered Off/restore and tone sequences have been removed.
Future listening tests use explicit, supervised UI actions after independent review.
Use a separate audio source and observe rear Line Output 3, then explicitly restore.
Historical build-12 listening evidence remains valid for that build only.

## Device and routing GUI

Build 13 adds the suite-styled device sidebar and explicit source → Line Output 3 routing. Other outputs are view-only; audio-only interfaces are labeled separately. [Implementation and real iPad screenshots](docs/evidence/gui/README.md).

## Review fixes

Build 14 / driver 10 addresses the independent review with serial-keyed recovery, explicit baseline acknowledgement, selected-device writes, and removal of automatic write hooks. See [review handoff](docs/evidence/review-fixes/README.md) for checks and remaining hardware tests.

## Hardware mixer prototype

App 15 / driver 11 adds hardware-backed mix faders and mute controls, with isolated-mix guards and durable level recovery. Locally built and tested; not yet installed or hardware-verified. See [mixer review handoff](docs/evidence/mixer/README.md).

## Four-output mixer

App 19 / driver 13 extends output editing to all four analogue outputs and selects internal mixes automatically. Locally tested only; review and hardware acceptance pending. [Implementation and review handoff](docs/evidence/four-outputs/README.md).
