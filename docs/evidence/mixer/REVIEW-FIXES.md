# Mixer review follow-up — app 16 / driver 12

Review base: 17e9b42. Local-only changes; no installation or hardware commands.

- Added selector 11: fresh read and explicit driver mix baseline acknowledgement, without SET_MIX. The UI confirmation explicitly supersedes pending recovery. Previous valid disk snapshot is archived before atomic replacement. Storage failure blocks edits; old recovery is retained. A read never silently replaces a baseline.
- Added driver-state rebaseline tests for changed assignments and uncertainty, and disk archive/replacement tests.
- Mixer failures use mixer-specific advice. Invalid data no longer claims nothing was sent. Storage failure after verified hardware write explicitly says the write succeeded. Restore is disabled when assignments or destination ownership prohibit it.
- Preflight rejection rolls the draft back to the last read frame. Routing replies invalidate mix destination state; restoring the output source rereads the mix.
- VoiceOver adjustments and explicit keyboard-accessible buttons use half-dB changes and call the same send action. From mute, increment starts at the smallest nonzero coefficient (-78 dB); hardware quantization means near-silence coefficients cannot represent every half-dB step.
- Removed misleading test assertions/labels for preservation of other mix rows and actual lost ACK transport. These remain hardware acceptance requirements. Host tests cover shared policy functions, not the DriverKit entry point or full app orchestration.

Checks: scripts/test.sh passes with sanitizer C++ tests; unsigned Debug and Release builds pass; project regeneration identical; production panel rendered at 420 points in an offscreen macOS hosting view. No on-device VoiceOver, keyboard, enlarged-text or audio verification claimed. The +12 dB endpoint and bit-exact hardware gain storage remain explicit acceptance risks from the original review. Multiple-visible-interface write block remains unchanged.

Review selector 11 and disk archive ordering, failure messages, UI invalidation and accessibility send behavior before installing. Then run the original single-4i4 acceptance plan, recording all six rows before/after. No multi-device writes.
