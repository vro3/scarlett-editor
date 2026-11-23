# Mixer prototype — app 15 / driver 11

Local implementation only. Not installed or tested against the Scarlett. Installed build 14 / driver 10 remains unchanged.

## Controls

Mix & levels selects one of the six 4i4 Gen3 mixes. Assigned inputs show their actual hardware source names, a half-dB fader, and mute/unmute. Faders send on release. Mute writes zero gain; unmute recalls the previous level. Unknown muted levels require moving the fader. Unassigned inputs are hidden and preserved. Input assignments are not editable in this prototype.

Routing a mix to Line Output 3 is a separate explicit action. Other output destinations remain uneditable. A mix feeding any other destination is locked, including loopback or another mixer input. The existing multiple-visible-interface write block remains.

## Driver and recovery

Selectors 8/9/10 read, set and restore an eight-coefficient mix row. GET_MIX 0x2001 requests a zero-based mix index and count 8; SET_MIX 0x2002 sends the index and eight little-endian UInt16 coefficients. Unity is 8192; conversion uses floor(8192 × 10^(dB/20)), half-dB steps, maximum +12 dB. These facts were checked against the Linux wire reference:
https://github.com/torvalds/linux/blob/master/sound/usb/mixer_scarlett2.c

Writes recheck serial, clock, input assignments, destination ownership and current gain row. A durable per-serial/per-mix original snapshot and uncertain marker are saved before writing. Exact gain read-back and unchanged routing are required. Restore is explicit and still requires unchanged input assignments and isolated destination ownership. It is not automatic on termination or unplugging. Failed commands require a new read/handshake; uncertain writes require recovery. Uninstalling the app removes its recovery files.

## Local checks

Host tests cover packet sizes and bounds, coefficient packing/conversion, mute recall, untouched gains, shared-destination rejection, source remapping, external gain drift, simulated uncertain-state policy and durable recovery reload. C++ tests run with AddressSanitizer and UndefinedBehaviorSanitizer. Existing routing and recovery tests also pass. Debug and Release signed builds pass. Project regeneration is deterministic.

The PNGs render the production SwiftUI panel in a macOS NSHostingView at 900 and 420 points with explicitly labeled preview data. They check layout, not iPad interaction or USB behavior.

See [review fixes](REVIEW-FIXES.md) for app 16 / driver 12 and corrected test scope.

## Review and hardware still required

Fable should review the new selector contract, USB command layout, recovery transitions and destination guards. Then test with one 4i4 at 44.1/48 kHz: read all rows and assignments; save baseline; use a mix isolated to Line 3; move one fader; read back all coefficients; listen; mute/unmute; restore levels and original routing. Verify unrelated mixes/routes remain unchanged. Test relaunch recovery and controlled lost-ACK recovery separately. Do not test writes with both interfaces until independent review and the earlier multi-device acceptance work are complete.
