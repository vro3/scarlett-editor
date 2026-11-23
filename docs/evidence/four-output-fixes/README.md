# Four-output review fixes — app 20 / driver 14

Review base a82e4f6. Not installed; no hardware commands sent.

1. Restore levels automatically restores the original output source first when the selected row was allocated by this app and is still attached. It then rereads that same row and restores its old coefficients. New selector 14 requires zero destinations at the driver immediately before writing: a reattachment or other user of the row refuses restoration. Existing, non-allocated mixes retain normal level restoration. Partial failure stops the sequence and preserves recovery.
2. Enable rejects pending route recovery and existing mixer/identity guards before persisting allocation or preparing levels. A race after preflight still fails through the existing driver checks.
3. Overflow menu has Enable recovery, a monitoring confirmation that sets only local confirmation and disarms editing. It does not prepare, attach or write. Restore controls can be used after relaunch without Edit.
4. Prepared display/status is used only when the saved recovery permits normal editing. Rejected preparation clears the candidate strips. Restored inactive rows are cleared rather than displayed as audible output levels. Enable explicitly says it changes the output source when preparation is required.
5. Output switching immediately clears current/original/source/recovery/readiness/confirmation/draft state before reading the new output.
6. Outputs 3/4 say Line + Headphones L/R; baseline menu uses levels instead of mix.

Verification: host tests pass, including a production unused-row predicate test rejecting all 18 destinations for detached-only recovery. Existing four-output allocation/recovery policy tests pass. Unsigned Debug and Release builds pass, project regeneration is identical. Production UI component render inspected. These are local policy/build checks, not end-to-end USB, complete app orchestration or audible recovery tests.

Fable should review selector 14 dispatch/argument validation, restore source → same-row read → detached-only restore ordering, partial failure behavior, pending-connect preflight, local-only recovery confirmation and stale display handling. Then single-4i4 installation/acceptance can proceed. Multi-device write gate remains unchanged. App 18 / driver 12 was the last installed build; 19 was never installed.
