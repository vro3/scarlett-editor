# Four-output mixer — app 19 / driver 13

UI: four selectable analogue outputs, vertical source faders and mute. Outputs 3/4 are also headphone L/R. No public mix-bus picker. Direct routing remains in the overflow menu. Outputs are independently editable; stereo linking is not implemented in this change.

## Allocation and preservation

Selecting an output reads routing and all six mix rows; selection never writes. An exclusive existing mix is reused. Shared mixes are copied into a completely unused row before connection. For a direct source, an unused row is prepared with that source at unity and the others at zero (or all zero for Off). Existing shared mixer-input assignments are preserved: unavailable source assignments and exhausted buses block setup. Assigned sources only are displayed; this is not yet a mixer-input assignment editor.

Edit confirmation prepares the unused row, verifies it, then attaches it to the selected output. Each step saves recovery before writing. The chosen bus is remembered in the output recovery record before preparation so a failed connection/relaunch can select the same unused row. A failure can leave an unused mix prepared; it does not automatically roll back. Restore levels and Restore output source remain explicit menu actions. The previous route is retained per output. Existing Output 3 recovery files stay at the original path; other outputs use separate directories. Mixer recovery remains per serial and bus, including previously archived baselines.

## Driver contract

Selectors 12/13 apply/restore an output route. Their single scalar contains output index 0–3 in bits 16+ and source in bits 0–15; indices outside 0–3 are rejected before narrowing. Only the selected analogue destination changes; all 18 entries are verified after SET_MUX.

Mixer selectors 8–11 encode bus in low byte and output index + 1 above it. Zero high byte retains the legacy Output 3 scope. Destination isolation now allows only the selected output, never other analogue outputs, PCM destinations or mixer inputs. Before connecting a mix, GET_MIX checks its gains and assignments against the captured state. Clock, identity, uncertainty, recovery and multiple-visible-interface restrictions remain.

## Local evidence

Host tests pass, including C++ sanitizer tests for each output's route preservation and mix ownership, Swift allocation tests for exclusive reuse, shared-copy planning, direct-source levels, preferred recovery bus, exhaustion and unavailable sources. These exercise production policy helpers, not physical USB or the complete DriverKit entry point. Unsigned Debug and Release builds pass. Wide/narrow PNGs render production components with fixture data in a macOS hosting view; they are not iPad hardware evidence.

## Before installation/writes

Request Fable review of this diff against bbb6154, focusing on selectors 12/13, output-scoped recovery, two-step prepare/connect failures and shared-mix isolation. No installation or hardware commands during this change. Keep only the 4i4 attached for acceptance. Record all six rows and all 18 routes, exercise each of four outputs independently, compare untouched rows/routes, listen at each physical output, restore levels then routing, and verify recovery across restart/failure. Review and hardware tests remain pending. No six-independent-output or stereo-link claim.
