# Device sidebar and routing GUI — build 13

Implemented and installed on the M5 iPad Pro on November 15, 2026.

- Native split view, Dusk surfaces from Breakbeat DesignTokens.swift, suite highlight #2B3CF0, bundled Atkinson Hyperlegible Next with OFL license.
- Sidebar enumerates ScarlettDriver services by registry entry ID. Selecting a device closes the old client and opens only that ID; selection resets routing state and monitoring confirmation. IDs are connection identities, not persistent serial identities.
- Active USB audio endpoints without a matching supported model appear as audio-only entries. This is not a complete enumeration of every USB audio device attached to iPadOS. Same-model audio/control correlation and two identical 4i4s remain unverified.
- All four analogue output sources are displayed from real hardware reads. Only Line Output 3 is editable, using the existing driver contract. Source selection stages a choice; Apply sends it. Restore retains the existing driver-session semantics.
- No Driver/ or Shared/ source changes. Fable's independent review remains a separate artifact, not a release sign-off.

Verification: signed Debug iPad build passed; installed and launched; specific registry-ID connection read firmware 1605 and unchanged routing (see read.txt). Both attached 4i4 and active-audio 2i2 were discovered. Real iPad screenshots inspected for the routing and audio-only states. Protocol ASan/UBSan tests and exact USB matching assertion passed. No hardware writes or tones were run for this GUI verification. App build 13; driver version 9.

Debug-only SCARLETT_CAPTURE_UI=1 saves a window screenshot after four seconds to Library/Caches/RoutingScreen.png. Normal launch discovers and reads the selected controllable device; it does not write. Driver startup may initially leave an audio-only endpoint selected; tap the 4i4 after refreshing in that case.

Remaining: interaction testing at enlarged text/narrow windows, multiple identical controllable units, other model profiles, expanded output editing, and independent review findings. The audio test hook now requires one controllable interface and active 4i4 audio, but serial-level audio/control correlation is not implemented.
