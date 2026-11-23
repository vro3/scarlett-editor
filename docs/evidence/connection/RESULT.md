# Direct iPad USB routing: passed

November 15, 2026, 14:40 America/Chicago. Native app build 10, driver build 9.
M5 iPad Pro; Scarlett 4i4 3rd Gen, firmware 1605; direct USB connection.

The iPad executed the following sequence after the user confirmed low monitoring levels:

| Stage | Analogue output route words (1–4) | Result |
|---|---|---|
| Read | 600080 601081 602082 603083 | Line 3 = Playback 3 |
| Set Line 3 Off | 600080 601081 000082 603083 | Hardware read-back passed |
| Restore | 600080 601081 602082 603083 | Hardware read-back passed |
| Relaunch in read-only mode | 600080 601081 602082 603083 | Restored state confirmed |

The driver compares all 18 entries, not only these four displayed output words,
before accepting either write. See ScarlettDriver.cpp Perform/ReadRoutes.

[Routing test log](routing-test.txt) and [independent relaunch read](final-read.txt)
were retrieved from the iPad app cache using devicectl. Unrelated MIDI inventory
lines were removed; all transaction and result lines are retained.

The Mac installed/launched the app and retrieved logs over Wi-Fi. USB control
transactions ran in the iPad's DriverKit extension; no desktop USB or network
routing bridge exists in the source. Normal launch never performs routing writes.
The explicit development environment SCARLETT_VERIFY_OFF_RESTORE=1 invokes the
bounded test, including restore after a failed write attempt. It was run once.
The app was then relaunched with SCARLETT_AUTO_READ=1 only.

Signed builds and installation passed. Protocol sanitizer tests and USB matching
checks passed before the hardware test. Scope is this model, firmware and bank 0.
Uninterrupted concurrent audio, disconnect recovery, persistence
across power loss, distribution approval and other models remain unverified.
The previous hub setup did not enumerate Scarlett in this session; direct USB did.
This does not establish a general hub incompatibility.

## Listening test, app build 12

At 14:45 the first listening test used USB Playback 1 and left Output 1's existing
Playback 1 route untouched. The user reported faint bleed during Line 3 Off.
This was not counted as an isolation pass, and its physical cause was not proven.

At 14:47 build 12 requested four USB output channels and assigned the player's
left tone explicitly to USB Playback 3, with its silent right channel assigned
to Playback 4. The iPad reported four output channels. The user, listening on
a speaker/mixer connected to rear Line Output 3, reported **“silence in the middle”**
of the tone → Off → tone sequence. Every full-table read-back and final restore
passed. [Isolation test log](audio-isolation-test.txt).

This is a user-observed listening result, not a measured noise-floor specification.
Concurrent third-party audio and hub operation remain separate checks.

## Acer hub with larger power supply

The user identifies the hub as an Acer USB-C five-port hub; exact model, charger
ratings, and cable specifications are not yet recorded. It initially failed to
enumerate Scarlett even with a charger connected and Scarlett in a data port.
The user changed to a larger PSU while instructed to leave the other connections
unchanged. At 14:50, USB audio/MIDI enumeration and the direct routing read passed.

App build 12 then completed Playback 3 → Off → Playback 3 and restore through the
hub. Every full-table read-back passed. At 14:51 a separate read-only app relaunch
confirmed restored Playback 3. Tone playback had stopped. See [hub read](hub-read.txt),
[hub timed test](hub-audio-test.txt), and [final read](hub-final-read.txt).

The larger-PSU setup is verified for control transactions. The user confirmed
**“Yes—tone, silence, tone”** for the hub run. Do not infer charger wattage, per-port
current, a defective hub, or universal compatibility from this single setup.
