# Independent-review fixes — app 14 / driver 10

Review target: the commit containing this file, based on GUI commit `9107c6e`.
Original independent report reviewed `84960e0`; its uncommitted report file is preserved unchanged.

## Finding disposition

1. **Target identity:** client opens only the explicitly selected registry entry; every write re-enumerates and rechecks its USB serial. The sidebar shows the serial. Missing/duplicate visible serials block writes. The old “any Scarlett audio output” and unrelated audio-session sample-rate gates are removed; the selected driver's USB clock is authoritative. As a temporary acceptance gate, app writes are disabled whenever more than one interface is visible. This gate is not an exhaustive USB inventory or a claim of multi-device acceptance. Two identical 4i4s remain untested.
2. **Durable recovery:** before any write the app atomically saves a pending marker with all 18 original words, model, serial and capture time in Application Support. Storage failure blocks the write. Reads/relaunches do not replace an existing snapshot. Restore sends only its saved Line 3 source and preserves current unrelated routes. Full read-back must pass before pending is cleared. On definite pre-write failure, the prior pending state is restored. Recovery is manual after app termination/disconnect; the same serial and 44.1/48 kHz are required. The baseline UI cannot discard a pending recovery. No claim of guaranteed restore during disconnection or at higher rates.
3. **Drift:** Apply still fails closed if current routing differs from expected. Read alone does not acknowledge drift. The explicit, confirmed baseline action reads and accepts current routing without a SET_MUX. Restore can recover just Line 3 across unrelated external changes. Shared `RouteSession` policy is exercised with a fake device. Errors distinguish pre-write rejection from a potentially applied write using the driver transaction stage.
4. **Launch hooks:** automatic write/tone hooks and their automatic monitoring confirmation are removed entirely, including Debug. Normal launch only discovers/reads. Only the DEBUG screenshot hook remains. Scene inactivity clears monitoring confirmation.
5. **Docs:** corrected the build directory and obsolete UI labels; documented the Linux reference's headphone L/R mapping and that physical headphone coupling was not independently listened to. Added a correction to the older audit's startup-cleanup claim. Failed driver setup now immediately closes the opened interface. The requested Driver settings sidebar shortcut opens the app's Settings page using Apple's public settings URL.

Additional hardening: command errors synchronously abort notification I/O and invalidate the protocol handshake; only a subsequent Read/baseline operation can initialize again. Uncertain-write state survives this reinitialization. USB descriptor copies use IOUSBHostFreeDescriptor. Clock is checked again immediately before the bank-0 write. A clock change can still race between this check and the command; no exclusive clock ownership is claimed.

## Verification performed

- `bash scripts/test.sh`: ASan/UBSan wire-format and fake-device state-policy checks; Swift durable-storage tests; exact USB matching assertion. See `host-tests.txt`.
- Fake-device cases: unread state, outside edits, read not silently acknowledging edits, explicit rebaseline, lost write reply, pending recovery blocking Apply/rebaseline, full-table verification failure, restore preserving current unrelated routes, new driver-session recovery.
- Storage cases: process/store restart, serial isolation, path encoding, corrupt/invalid record rejection, and observable atomic-save failure. These test production `RecoveryStore` directly.
- Signed Debug and Release builds succeeded with Xcode 26.3. Final build directories `/tmp/scarlett-review` and `/tmp/scarlett-review-release`.
- Regeneration of project/plists/entitlements was byte-identical. Release executable lacks the old write/tone environment keys and DEBUG screenshot key.
- Installed app 14 / driver 10 on M5 iPad. New serial selector returned `SERIAL-REDACTED`; firmware 1605 and routes `600080 601081 602082 603083` read successfully while 2i2 remained active audio. See `ipad-read.txt`.
- Copied the real Application Support snapshot from the iPad: 18 words, matching serial/model, original Line 3 Playback 3, pending=false. Relaunched the app, copied it again, compared parsed JSON: same snapshot and capture time. See `recovery-snapshot.json`.
- Inspected actual iPad screenshot for serial display and Driver settings shortcut. See `ipad-screen.png`.
- **No routing writes, test tones, forced timeouts, cable pulls, rate changes or baseline resets were run on hardware in this pass.** The user requested independent review before two-device writes.

## Driver API changes for review

All methods retain one UInt64 input and six UInt64 output scalars, no structures/async completion.

| Selector | Behavior |
|---|---|
| 0 | Read current routes; handshake when needed; capture initial driver baseline once |
| 1 | Apply allowed direct source to Line 3 after drift/uncertainty checks |
| 2 | Legacy restore of driver-session original Line 3 |
| 3 | Read diagnostic stage/errors/firmware/clock/endpoint |
| 4 | Read and explicitly replace driver baseline, refused while uncertain; no routing write |
| 5 | Read up to 47 ASCII serial bytes plus NUL, packed in the six output scalars |
| 6 | Explicit saved-source restore; permits valid mixer sources as well as direct sources, because an original route may use a mix |
| 7 | Export six original routing words per chunk (input 0–2); app validates complete 18-word snapshot |

The driver validates source ranges, its own device clock, captured state, and read-back. Durable snapshot provenance and the temporary visible-device-count gate are app responsibilities. Selector 6 does not authenticate that a supplied valid source was historically present; an entitled client is trusted to supply its validated recovery source. Review this boundary explicitly.

## Remaining acceptance and review focus

Read-only review first. Do not enable a write hook (none remains) or run multi-device writes. Review changes from `9107c6e`, particularly snapshot lifetime, write-error classification, serial selection, new selectors, rebaseline/restore policy and timeout re-handshake. The app data container survives updates but not uninstall; recovery is not guaranteed after uninstall. USB serials are not cryptographic and sequential units with identical serials cannot be distinguished.

Hardware acceptance still required after review: supervised single-device apply/restore on this new driver; pending-write relaunch/driver replacement; disconnect during request/ACK/read-back; real timeout resynchronization; rate switch away/back; concurrent audio; two-device identity and two identical 4i4s. The fake-device policy tests do not execute DriverKit notification queues or USB timing. Distribution entitlement, firmware expansion and additional models remain unverified.
