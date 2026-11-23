import XCTest
@testable import ScarlettDirect

// Test-only bundle. Never linked into the shipping app; no write launch hooks.
@MainActor final class MixerHardwareTests: XCTestCase {
    func testEightChannels() async throws {
        let serial=ProcessInfo.processInfo.environment["SCARLETT_TEST_SERIAL"] ?? ""
        guard !serial.isEmpty else { throw XCTSkip("Explicit serial required for hardware acceptance") }
        // Let the app's normal read-only startup finish before creating the test connection.
        try await Task.sleep(for:.seconds(3))
        let model=RoutingModel()
        model.discover()
        guard model.devices.count==1, let target=model.devices.first, target.serial==serial else { throw XCTSkip("Exactly the selected Scarlett must be connected") }
        model.selectDevice(target.id)
        let read: Bool=await withCheckedContinuation { continuation in model.run(0) { continuation.resume(returning:$0) } }
        XCTAssertTrue(read); guard read else { return }
        let loaded: Bool=await withCheckedContinuation { continuation in model.loadOutputMix { continuation.resume(returning:$0) } }
        XCTAssertTrue(loaded); guard loaded else { return }
        let frame=try XCTUnwrap(model.mixFrame)
        guard frame.feedsOutput, frame.isolated, Set(frame.sources)==Set(InputExpansionJournal.allSources), frame.gains.allSatisfy({$0==0}) else {
            throw XCTSkip("Output 3 must already have an exclusive eight-channel mixer with all faders muted")
        }
        let beforeRoutes=try model.hardware.liveRoutes()
        func rows() throws -> [MixerFrame] {
            try (0..<6).map { try MixerFrame(reply:model.hardware.call(8,source:UInt64($0)|3<<8)) }
        }
        let before=try rows()
        let saved=try XCTUnwrap(model.mixStore.load(serial:serial,bus:frame.bus))
        let cache=FileManager.default.urls(for:.cachesDirectory,in:.userDomainMask)[0]
        var evidence: [[String:Any]]=[]
        func record(_ step:String,_ actual:[MixerFrame]) throws {
            evidence.append(["step":step,"routes":try model.hardware.liveRoutes(),"rows":actual.map { ["bus":$0.bus,"sources":$0.sources,"gains":$0.gains,"destinations":$0.destinations] }])
            let data=try JSONSerialization.data(withJSONObject:["serial":serial,"output":3,"events":evidence],options:[.prettyPrinted,.sortedKeys])
            try data.write(to:cache.appendingPathComponent("EightChannelAcceptance.json"),options:.atomic)
        }
        func verify(_ wanted:[UInt16],_ step:String) throws {
            let actual=try rows()
            guard try model.hardware.liveRoutes()==beforeRoutes else { throw NSError(domain:"HardwareTest",code:1,userInfo:[NSLocalizedDescriptionKey:"Routing changed at "+step]) }
            for bus in 0..<6 {
                let expected=bus==frame.bus ? wanted : before[bus].gains
                guard actual[bus].gains==expected, actual[bus].sources==before[bus].sources, actual[bus].destinations==before[bus].destinations else {
                    throw NSError(domain:"HardwareTest",code:2,userInfo:[NSLocalizedDescriptionKey:"Row preservation/read-back failed at "+step])
                }
            }
            try record(step,actual)
        }
        func send() async throws {
            let ok: Bool=await withCheckedContinuation { continuation in model.mixOperation(restoring:false,write:true) { continuation.resume(returning:$0) } }
            guard ok else { throw NSError(domain:"HardwareTest",code:3,userInfo:[NSLocalizedDescriptionKey:model.mixerStatus]) }
        }
        func restore() throws {
            guard try model.hardware.serial()==serial else { throw MixerError.invalid }
            _ = try model.hardware.call(0)
            _ = try model.hardware.callInputs(10,inputs:[UInt64(frame.bus)|3<<8,MixerMath.pack(Array(frame.gains[0..<4])),MixerMath.pack(Array(frame.gains[4..<8]))])
            try verify(frame.gains,"FINAL RESTORED")
            try model.mixStore.save(saved)
        }
        try record("BASELINE",before)
        model.confirmed=true; model.explicitlySelected=true; model.mixerArmed=true
        do {
            for index in (0..<8).sorted(by:{frame.sources[$0]<frame.sources[$1]}) {
                let name=sourceName(UInt64(frame.sources[index]))
                var wanted=frame.gains; wanted[index]=MixerMath.gain(db:-40)
                model.mixDraft.setDB(-40,channel:index)
                try await send(); try verify(wanted,name+" fader -40 dB")
                model.mixDraft.toggleMute(index)
                try await send(); try verify(frame.gains,name+" mute")
                model.mixDraft.toggleMute(index)
                try await send(); try verify(wanted,name+" unmute")
                model.mixDraft.toggleMute(index)
                try await send(); try verify(frame.gains,name+" returned to muted")
            }
            try restore()
        } catch {
            do { try restore() } catch { XCTFail("Recovery failed: \(error)") }
            throw error
        }
        print("HARDWARE PASS: eight fader/mute/unmute channels, all six rows and 18 routes verified; original levels restored")
    }
}

import AVFAudio
extension MixerHardwareTests {
    func testOutputOneAndThreeTone() async throws {
        let serial=ProcessInfo.processInfo.environment["SCARLETT_TEST_SERIAL"] ?? ""
        guard !serial.isEmpty else { throw XCTSkip("Explicit serial required") }
        try await Task.sleep(for:.seconds(3))
        let model=RoutingModel(); model.discover()
        guard model.devices.count==1, let target=model.devices.first, target.serial==serial else { throw XCTSkip("Selected interface only") }
        model.selectDevice(target.id)
        let ok: Bool=await withCheckedContinuation { c in model.run(0) { c.resume(returning:$0) } }
        guard ok else { throw MixerError.invalid }
        let device=model.hardware, routes=try device.liveRoutes()
        func rows() throws -> [MixerFrame] { try (0..<6).map { try MixerFrame(reply:device.call(8,source:UInt64($0)|3<<8)) } }
        let before=try rows()
        let outputs=[0,2]
        let buses=try outputs.map { output -> Int in
            let source=(routes[6+output]>>12)&0xfff
            guard (0x300...0x305).contains(source) else { throw XCTSkip("Output must already have a mixer") }
            let bus=Int(source-0x300)
            guard before[bus].destinations == 1 << (6+output) else { throw XCTSkip("Output mixer must be exclusive") }
            return bus
        }
        guard let slot=before[0].sources.firstIndex(of:0x602), before.allSatisfy({$0.sources==before[0].sources && $0.gains[slot]==0}) else { throw XCTSkip("Playback 3 must be assigned and muted in every row") }
        let cache=FileManager.default.urls(for:.cachesDirectory,in:.userDomainMask)[0]
        var events:[[String:Any]]=[]
        func capture(_ step:String) throws {
            let actual=try rows(), currentRoutes=try device.liveRoutes()
            guard currentRoutes==routes else { throw MixerError.recovery }
            events.append(["step":step,"routes":currentRoutes,"rows":actual.map { ["bus":$0.bus,"sources":$0.sources,"gains":$0.gains,"destinations":$0.destinations] }])
            try JSONSerialization.data(withJSONObject:["serial":serial,"events":events],options:[.prettyPrinted,.sortedKeys]).write(to:cache.appendingPathComponent("OutputToneAcceptance.json"),options:.atomic)
        }
        try capture("BASELINE")
        func write(_ pair:Int,_ gain:UInt16,_ restoring:Bool=false) throws {
            guard try device.serial()==serial else { throw MixerError.invalid }
            let bus=buses[pair], output=outputs[pair]
            var wanted=before[bus].gains; if !restoring { wanted[slot]=gain }
            _ = try device.callInputs(restoring ? 10 : 9,inputs:[UInt64(bus)|UInt64(output+1)<<8,MixerMath.pack(Array(wanted[0..<4])),MixerMath.pack(Array(wanted[4..<8]))])
            let actual=try rows()
            for m in 0..<6 {
                guard actual[m].sources==before[m].sources, actual[m].destinations==before[m].destinations,
                      actual[m].gains==(m==bus ? wanted : before[m].gains) else { throw MixerError.recovery }
            }
        }
        let session=AVAudioSession.sharedInstance()
        let category=session.category, mode=session.mode, options=session.categoryOptions, count=session.preferredOutputNumberOfChannels
        try session.setCategory(.playback,mode:.default)
        try session.setActive(true)
        defer { try? session.setActive(false,options:.notifyOthersOnDeactivation); try? session.setCategory(category,mode:mode,options:options); if count>0 { try? session.setPreferredOutputNumberOfChannels(count) } }
        guard session.maximumOutputNumberOfChannels>=4 else { throw XCTSkip("Four USB playback channels unavailable") }
        try session.setPreferredOutputNumberOfChannels(4)
        try await Task.sleep(for:.milliseconds(200))
        let channels=session.currentRoute.outputs.first(where:{$0.portType == .usbAudio})?.channels ?? []
        guard session.outputNumberOfChannels>=4,
              let third=channels.first(where:{$0.channelNumber==3}), let fourth=channels.first(where:{$0.channelNumber==4}) else { throw MixerError.invalid }
        // Finite -30 dBFS stereo file: Playback 3 tone, Playback 4 zeros.
        let rate=44100, frames=rate*20
        var samples=[Int16](repeating:0,count:frames*2)
        for i in 0..<frames {
            let ramp=min(1.0,Double(min(i,frames-1-i))/441.0)
            samples[i*2]=Int16(1036*ramp*sin(2*Double.pi*440*Double(i)/Double(rate))).littleEndian
        }
        let pcm=samples.withUnsafeBytes { Data($0) }; var wav=Data()
        func word<T:FixedWidthInteger>(_ n:T) { var v=n.littleEndian; withUnsafeBytes(of:&v) { wav.append(contentsOf:$0) } }
        wav.append(contentsOf:"RIFF".utf8);word(UInt32(36+pcm.count));wav.append(contentsOf:"WAVEfmt ".utf8)
        word(UInt32(16));word(UInt16(1));word(UInt16(2));word(UInt32(rate));word(UInt32(rate*4));word(UInt16(4));word(UInt16(16));wav.append(contentsOf:"data".utf8);word(UInt32(pcm.count));wav.append(pcm)
        let player=try AVAudioPlayer(data:wav,fileTypeHint:"wav"); player.channelAssignments=[third,fourth];player.prepareToPlay()
        defer { player.stop() }
        do {
            try write(0,8192)
            guard player.play() else { throw MixerError.invalid }
            print("LISTEN: OUTPUT 1 — four seconds"); try capture("OUTPUT 1 TONE")
            try await Task.sleep(for:.seconds(4))
            try write(0,0); print("LISTEN: SILENCE — four seconds");try capture("SILENCE")
            try await Task.sleep(for:.seconds(4))
            try write(1,8192); print("LISTEN: OUTPUT 3 — four seconds");try capture("OUTPUT 3 TONE")
            try await Task.sleep(for:.seconds(4))
            player.stop(); try write(1,0)
            try write(0,0,true);try write(1,0,true);try capture("FINAL RESTORED")
            print("TONE TEST PASS: Output 1 / silence / Output 3; all routes and levels restored. Listening confirmation pending.")
        } catch {
            player.stop()
            _ = try? device.call(0)
            for pair in 0..<2 { do { try write(pair,0,true) } catch { XCTFail("Tone recovery failed: \(error)") } }
            try? capture("ERROR RECOVERY")
            throw error
        }
    }
}

extension MixerHardwareTests {
    func testLowOneHighThreeTone() async throws {
        let serial=ProcessInfo.processInfo.environment["SCARLETT_TEST_SERIAL"] ?? ""
        guard !serial.isEmpty else { throw XCTSkip("Explicit serial required") }
        try await Task.sleep(for:.seconds(3))
        let model=RoutingModel(); model.discover()
        guard model.devices.count==1, let target=model.devices.first, target.serial==serial else { throw XCTSkip("Selected interface only") }
        model.selectDevice(target.id)
        let ok: Bool=await withCheckedContinuation { c in model.run(0) { c.resume(returning:$0) } }
        guard ok else { throw MixerError.invalid }
        let device=model.hardware, routes=try device.liveRoutes()
        func rows() throws -> [MixerFrame] { try (0..<6).map { try MixerFrame(reply:device.call(8,source:UInt64($0)|3<<8)) } }
        let before=try rows()
        let outputs=[0,2]
        let buses=try outputs.map { output -> Int in
            let source=(routes[6+output]>>12)&0xfff
            guard (0x300...0x305).contains(source) else { throw XCTSkip("Output must already have a mixer") }
            let bus=Int(source-0x300)
            guard before[bus].destinations == 1 << (6+output) else { throw XCTSkip("Output mixer must be exclusive") }
            return bus
        }
        guard let slot=before[0].sources.firstIndex(of:0x602), before.allSatisfy({$0.sources==before[0].sources && $0.gains[slot]==0 && $0.sources.contains(0x603) && $0.gains[$0.sources.firstIndex(of:0x603)!]==0}) else { throw XCTSkip("Playback 3 must be assigned and muted in every row") }
        let highSlot=try XCTUnwrap(before[0].sources.firstIndex(of:0x603))
        var expected=before.map(\.gains)
        let cache=FileManager.default.urls(for:.cachesDirectory,in:.userDomainMask)[0]
        var events:[[String:Any]]=[]
        func capture(_ step:String) throws {
            let actual=try rows(), currentRoutes=try device.liveRoutes()
            guard currentRoutes==routes else { throw MixerError.recovery }
            events.append(["step":step,"routes":currentRoutes,"rows":actual.map { ["bus":$0.bus,"sources":$0.sources,"gains":$0.gains,"destinations":$0.destinations] }])
            try JSONSerialization.data(withJSONObject:["serial":serial,"events":events],options:[.prettyPrinted,.sortedKeys]).write(to:cache.appendingPathComponent("LowHighToneAcceptance.json"),options:.atomic)
        }
        try capture("BASELINE")
        func write(_ pair:Int,_ gain:UInt16,_ restoring:Bool=false) throws {
            guard try device.serial()==serial else { throw MixerError.invalid }
            let bus=buses[pair], output=outputs[pair]
            var wanted=before[bus].gains; if !restoring { wanted[pair==0 ? slot : highSlot]=gain }
            _ = try device.callInputs(restoring ? 10 : 9,inputs:[UInt64(bus)|UInt64(output+1)<<8,MixerMath.pack(Array(wanted[0..<4])),MixerMath.pack(Array(wanted[4..<8]))])
            expected[bus]=wanted
            let actual=try rows()
            for m in 0..<6 {
                guard actual[m].sources==before[m].sources, actual[m].destinations==before[m].destinations,
                      actual[m].gains==expected[m] else { throw MixerError.recovery }
            }
        }
        let session=AVAudioSession.sharedInstance()
        let category=session.category, mode=session.mode, options=session.categoryOptions, count=session.preferredOutputNumberOfChannels
        try session.setCategory(.playback,mode:.default)
        try session.setActive(true)
        defer { try? session.setActive(false,options:.notifyOthersOnDeactivation); try? session.setCategory(category,mode:mode,options:options); if count>0 { try? session.setPreferredOutputNumberOfChannels(count) } }
        guard session.maximumOutputNumberOfChannels>=4 else { throw XCTSkip("Four USB playback channels unavailable") }
        try session.setPreferredOutputNumberOfChannels(4)
        try await Task.sleep(for:.milliseconds(200))
        let channels=session.currentRoute.outputs.first(where:{$0.portType == .usbAudio})?.channels ?? []
        guard session.outputNumberOfChannels>=4,
              let third=channels.first(where:{$0.channelNumber==3}), let fourth=channels.first(where:{$0.channelNumber==4}) else { throw MixerError.invalid }
        // Finite -30 dBFS tones: Playback 3 low (220 Hz), Playback 4 high (880 Hz).
        let rate=44100, frames=rate*12
        var samples=[Int16](repeating:0,count:frames*2)
        for i in 0..<frames {
            let ramp=min(1.0,Double(min(i,frames-1-i))/441.0)
            samples[i*2]=Int16(1036*ramp*sin(2*Double.pi*220*Double(i)/Double(rate))).littleEndian
            samples[i*2+1]=Int16(1036*ramp*sin(2*Double.pi*880*Double(i)/Double(rate))).littleEndian
        }
        let pcm=samples.withUnsafeBytes { Data($0) }; var wav=Data()
        func word<T:FixedWidthInteger>(_ n:T) { var v=n.littleEndian; withUnsafeBytes(of:&v) { wav.append(contentsOf:$0) } }
        wav.append(contentsOf:"RIFF".utf8);word(UInt32(36+pcm.count));wav.append(contentsOf:"WAVEfmt ".utf8)
        word(UInt32(16));word(UInt16(1));word(UInt16(2));word(UInt32(rate));word(UInt32(rate*4));word(UInt16(4));word(UInt16(16));wav.append(contentsOf:"data".utf8);word(UInt32(pcm.count));wav.append(pcm)
        let player=try AVAudioPlayer(data:wav,fileTypeHint:"wav"); player.channelAssignments=[third,fourth];player.prepareToPlay()
        defer { player.stop() }
        do {
            try write(0,8192); try write(1,8192)
            guard player.play() else { throw MixerError.invalid }
            print("LISTEN: LOW 220 Hz on output 1 + HIGH 880 Hz on output 3 — ten seconds")
            try capture("LOW 1 AND HIGH 3")
            try await Task.sleep(for:.seconds(10))
            player.stop()
            try write(0,0,true);try write(1,0,true);try capture("FINAL RESTORED")
            print("LOW/HIGH TEST PASS: both tones sent; original rows and routes restored. Listening confirmation pending.")
        } catch {
            player.stop()
            _ = try? device.call(0)
            for pair in 0..<2 { do { try write(pair,0,true) } catch { XCTFail("Tone recovery failed: \(error)") } }
            try? capture("ERROR RECOVERY")
            throw error
        }
    }
}
