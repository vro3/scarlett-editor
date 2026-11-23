# Eight mixer inputs — app 28 / driver 15

Adds missing Analogue 1–4 and Playback 1–4 to empty shared mixer-input slots when the user taps Enable faders. Existing assignments stay in place; the UI sorts channel names without changing their hardware indices. All six rows have added columns set to zero and verified before SET_MUX connects the missing inputs. Existing columns, all output routes and loopback routes are preserved. Full/duplicate/internal-mix layouts that cannot fit the eight direct sources are refused rather than evicted.

## Boundary and recovery

- Selector 15 accepts 16 scalar arguments: four groups of five 12-bit route sources (18 canonical destinations, unused bits zero), followed by two packed gain scalars for each of six rows. Driver compares every route and coefficient with this app-saved state and its own sessions before writing.
- Selector 16 reads a fresh six-word routing chunk; three chunks return all routes.
- Selector 17 is a read-only routing-session acknowledgement for resuming a journal-validated partial expansion. The app independently validates all current routes/rows against its journal before using 17 and per-row selector 11; selector 15 still checks the exact validated state after those acknowledgements.
- Serial-keyed journal saves all original routes, six rows and their recovery records before writes. New columns are silenced in the migrated recovery baselines so Restore levels cannot revive an old coefficient under a newly assigned source. Old baselines for occupied columns are retained. The original journal stays on disk; a later expansion archives it.
- Pending journal blocks ordinary app writes. Retry accepts only original/fully expanded routing and original-or-zero values in added columns; occupied columns must match exactly. Unexpected drift or partially changed routing remains blocked with the journal preserved. This is resume recovery, not a generic rollback button.
- Multi-device app write gate, serial binding, 44.1/48 kHz restriction, and explicit Enable action remain. Discovery/read never expands inputs. After successful setup the same Enable action reloads the output plan and continues enabling it.

## Verification

- `scripts/test.sh`: nine PASS lines (saved in tests.txt), including production C++ expansion planner, every route/coefficient snapshot comparison, six-row silence/preservation, full-slot rejection, Swift packing, partial-progress acceptance, drift rejection, baseline migration and journal persistence.
- Signed Debug and Release iOS builds passed, app 28 / driver 15.
- Project/plists/entitlements regenerate byte-identically; diff whitespace check passed.
- Production mixer components rendered with eight fixture channels and visually inspected (mixer.png). This is a host component render, not an iPad touch or hardware test.
- No hardware commands, installation, or listening test in this implementation pass. Installation awaits the user turning the old driver off.

## Hardware acceptance still required

With only the 4i4 connected: capture routes and all six rows, enable one output, verify added sources and zero coefficients across all rows, and compare occupied columns plus output/loopback routes with the capture. Feed Playback 3 and 4 separately from an iPad audio app, exercise their faders/mute on an isolated output, then verify restoration. Read-back and listening are distinct checks. Host tests do not execute the DriverKit USB entry point or reproduce USB interruption on hardware.

## Installation

After the user confirmed the driver was off, app 28 / bundled driver 15 installed successfully on the M5 iPad via devicectl and the app launched. Driver re-enable and hardware acceptance remain pending. No routing or mixer write was sent during installation.
