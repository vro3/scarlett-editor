# Build 6 driver connection investigation

Verified November 15, 2026 on the M5 iPad Pro development device.

- User confirmed driver enabled and Scarlett connected; app could not locate its IOService. This is not evidence that the toggle was disabled.
- Device process inventory at 14:23 local showed three processes still using the original `ScarlettDriver.dext/ScarlettDriver` package. Current app builds embed `com.performancepercussion.scarlettdirect.driver.dext`.
- Build 6 removes the optional SetName startup step, matching Apple’s sample registration sequence, and corrects the misleading connection error. Whether SetName caused failure remains unverified.
- `scripts/test.sh`: protocol validation and restricted USB matching checks passed.
- Signed Xcode Debug build succeeded; device installation succeeded.
- User disabled driver and unplugged hardware. Three stale development-driver processes remained. Sent normal termination via devicectl; subsequent inventory showed only the new app, no Scarlett driver process.
- After re-enable, the new bundle process appeared and the diagnostic bootstrap service was found by the app. Driver bundle activation is verified; attachment to the Scarlett is not.
- Build 7 keeps driver build 6 unchanged and lets read-only requests reach the control service independently of AVAudioSession output selection. Driver sample-rate enforcement remains; app audio checks remain mandatory for writes.
- Build 7 installed successfully. Its read reported only `Speaker [Speaker]` and no ScarlettDriver service. Repeating after the user reconnected the Scarlett at the hub produced the same result.
- User confirms the Scarlett is powered and attached via a known-working hub. The absence of a current audio route does not establish a defective hub.
- Console live logs on the M5 iPad show the SystemExtensions approval-state query fails `mach-lookup com.apple.DriverKitAppServer` due to sandbox restrictions. This query is diagnostic-only and does not establish USB access denial. No Scarlett crash report was found.
- No routing writes have occurred. Next discriminator: compare AVAudioSession output with the development driver disabled while keeping the physical connection unchanged.

Local raw receipts: `/tmp/scarlett-v6-build.log`, `/tmp/scarlett-v6-install.json`, `/tmp/scarlett-v6-processes.json`, `/tmp/scarlett-v6-stopped.json`. Device identifiers are omitted here.

## Driver-off baseline and direct connection

- At 14:34, verified no Scarlett driver process and no bootstrap service. Audio remained Speaker with the hub setup unchanged.
- App build 8 adds CoreMIDI device enumeration and live audio-route-change logging; removes the sandbox-denied SystemExtensions query. Signed build and installation passed.
- At 14:35, both remembered Scarlett MIDI entries were offline while connected through the hub, with driver off.
- Verified CoreDevice uses a connected localNetwork/TCP transport before user disconnected the hub.
- At 14:36, user connected Scarlett directly to iPad. App build 8 reports `Scarlett 4i4 USB [USBAudio]` and an online Scarlett MIDI entry, with driver still off. This verifies direct USB audio/MIDI enumeration. It does not establish that the hub is defective or that the control protocol works.
- Awaiting driver re-enable for the routing read. No routing writes have occurred.

## Control-service connection and endpoint fix

- At 14:36 after re-enable with direct USB, the app successfully opened ScarlettDriver and called its diagnostic selector. It reported startup stage 4, clock ID 41, error 0xe00002c7. No routing write was requested.
- Startup had required the interrupt endpoint maximum packet size to equal the eight-byte acknowledgement length. The Linux protocol reference instead takes the endpoint maximum from the descriptor and independently checks actual acknowledgement length (mixer_scarlett2.c:8550 and 8768 in the downloaded reference).
- Build 9 accepts interrupt-IN capacity 8–1024 bytes, allocates that capacity, retains the exact-eight-byte ACK check, and logs endpoint metadata on errors. This corrects the overly strict assumption; hardware validation is still pending.
- Protocol and matching tests passed; signed build and installation passed. User disabled the old driver; process inventory after installation contained no Scarlett driver. Awaiting activation of build 9.
