# Physical 4i4 eight-input acceptance — November 15, 2026

User authorized testing all eight channels after enabling the driver and faders, with no analog sources connected. Ran a separate serial-gated XCTest bundle hosted by the iPad app. It calls the production RoutingModel/MixerDraft write path; it is not part of the shipping app, contains no app launch write hook, and does not simulate finger gestures.

Device: M5 iPad Pro over wireless development connection, Scarlett 4i4 Gen 3 serial SERIAL-REDACTED, firmware 1605, app 29 / driver 15. Output 3 already used an exclusive Mix 1 with all eight gains zero. Existing output sources were Mix 2, Mix 3, Mix 1, Mix 4 respectively.

## Observed result

XCTest passed in 8.267 seconds. For Analog 1–4 and Playback 1–4 independently:

1. Set the selected gain to −40 dB (coefficient 81).
2. Mute, verifying zero.
3. Unmute, verifying the remembered coefficient.
4. Return to zero.

After each of these 32 app writes, read all six mixer rows and all 18 routes. Every selected-row coefficient matched; the other five rows, source assignments, destination masks, and routing table stayed equal to the baseline. A final explicit restore verified the full original state again and restored the app's pre-test mixer recovery record. The 34 raw snapshots are in readbacks.json; a host equality check confirmed final rows/routes equal the baseline exactly.

The normal non-test app 29 was reinstalled afterwards. Driver source and version were unchanged. Initial test-bundle compilation failed to expose the app module; corrected only the disposable generator's testability/module settings, then ran the successful test. No hardware commands occurred in the failed compilation.

## Limits

No analog signal, audio capture, audible signal isolation, distortion/noise check, physical touch interaction, or other output's eight-channel write sequence was tested. This establishes real USB control/read-back for all eight source faders on Output 3, with all other rows/routes preserved. It is not a release-readiness claim.

## Re-run

Only with explicit hardware-test authorization, the selected serial as the sole interface, and Output 3 already using an exclusive eight-input mix at zero gain:

```
python3 scripts/make_hardware_tests.py SERIAL
xcodebuild -project ScarlettHardwareTests.xcodeproj -scheme MixerHardwareTests -destination 'platform=iOS,id=IPAD_UDID' -allowProvisioningUpdates test
```

The test skips on mismatched serial/count/layout or nonzero initial selected-row gains. The generated project is ignored; source generator and test are tracked. Test results and snapshots must be inspected rather than treating a skipped test as a pass. Reinstall the normal app after testing.

## Rear outputs 1 and 3 tone test

User clarified that rear outputs 1 and 3 (not analog inputs) were connected and authorized a tone test. `testOutputOneAndThreeTone` passed on the iPad in 16.755 seconds. A finite 440 Hz −30 dBFS stereo WAV was explicitly assigned to USB Playback 3 (left tone) and Playback 4 (right zeros). Playback 3 was initially zero on all six mixes. The test enabled its coefficient at unity on Output 1's exclusive row for four seconds, returned it to zero for four seconds, then enabled it on Output 3's exclusive row for four seconds. Each change read all rows and routes; final original gains and routes matched the baseline exactly (output-tone-readbacks.json). Normal build 29 reinstalled afterwards. Listening confirmation pending; this is not yet evidence of audible output.

## Simultaneous low/high listening confirmation

The user was unsure about the sequential test and requested two simultaneous tones: low on rear output 1 and high on rear output 3. `testLowOneHighThreeTone` passed in 14.283 seconds. It played 220 Hz via USB Playback 3 to output 1 and 880 Hz via USB Playback 4 to output 3, both −30 dBFS, for ten seconds. The user replied **“both”**, confirming both tones were audible. This confirms audibility of both tones; it is not independent measurement of channel crosstalk or a full analog-input signal test. Final all-six-row/all-18-route snapshot equals baseline exactly (low-high-readbacks.json). Normal build 29 restored afterwards.
