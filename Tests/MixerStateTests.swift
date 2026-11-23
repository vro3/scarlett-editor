import Foundation
@main struct MixerStateTests {
    static func inputExpansion() throws {
        let sources: [UInt16]=[0x80,0x81,0x600,0x601,0,0,0,0]
        let expanded=try InputExpansionJournal.expandedSources(sources)
        assert(expanded==[0x80,0x81,0x600,0x601,0x82,0x83,0x602,0x603])
        var routes: [UInt32]=[]
        for i in 0..<18 {
            let dest: Int
            if i<6 { dest=0x600+i } else if i<10 { dest=0x80+i-6 } else { dest=0x300+i-10 }
            routes.append(UInt32(dest))
        }
        for i in 0..<8 { routes[10+i] |= UInt32(sources[i])<<12 }
        let routeArgs=InputExpansionJournal.routeArguments(routes)
        assert(routeArgs.count==4)
        for i in 0..<18 { assert((routeArgs[i/5] >> ((i%5)*12))&0xfff == UInt64((routes[i]>>12)&0xfff)) }
        let rows: [[UInt16]]=(0..<6).map { m in (0..<8).map { i in UInt16(1000+m*100+i) } }
        let saved=(0..<6).map { MixerRecovery(serial:"unit",bus:$0,original:rows[$0],sources:sources,verified:rows[$0],audible:rows[$0],pending:true,uncertain:false) }
        let journal=InputExpansionJournal(serial:"unit",routes:routes,rows:rows,recoveries:saved,sources:sources,expanded:expanded,pending:true)
        assert(journal.valid)
        func frames(_ gains:[[UInt16]],_ inputs:[UInt16]) -> [MixerFrame] {
            (0..<6).map { MixerFrame(bus:$0,gains:gains[$0],sources:inputs,destinations:0) }
        }
        assert(journal.acceptsProgress(routes:routes,rows:frames(rows,sources)))
        // Interrupted after any number of row writes can resume only at known values.
        for count in 0...6 {
            var partial=rows
            for m in 0..<count { partial[m]=journal.normalized(partial[m]) }
            assert(journal.acceptsProgress(routes:routes,rows:frames(partial,sources)))
        }
        let zeroed: [[UInt16]]=rows.map { journal.normalized($0) }
        assert(journal.acceptsProgress(routes:journal.expandedRoutes,rows:frames(zeroed,expanded)))
        assert(!journal.acceptsProgress(routes:journal.expandedRoutes,rows:frames(rows,expanded)))
        var drift=rows; drift[0][0]+=1
        assert(!journal.acceptsProgress(routes:routes,rows:frames(drift,sources)))
        var routeDrift=routes; routeDrift[6] |= 0x600<<12
        assert(!journal.acceptsProgress(routes:routeDrift,rows:frames(rows,sources)))
        for bus in 0..<6 {
            let result=journal.migrated(bus)
            assert(result.sources==expanded && result.original==zeroed[bus] && result.verified==zeroed[bus] && result.pending && !result.uncertain)
        }
        let dir=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:dir) }
        let store=MixerRecoveryStore(directory:dir)
        try store.saveInputs(journal)
        let restored=try store.loadInputs("unit"); assert(restored!.rows==rows)
        do { _ = try InputExpansionJournal.expandedSources(Array(repeating:0x80,count:8)); fatalError("Evicted occupied slots") } catch {}
        print("PASS: input journal validates partial progress, rejects drift, preserves baselines and persists")
    }
    static func main() throws {
        try inputExpansion()

        assert(MixerMath.gain(db:0)==8192)
        assert(MixerMath.gain(db:12)==32612)
        assert(MixerMath.gain(db:-80)==0)
        assert(MixerMath.gain(db:.nan)==0)
        var last: UInt16=0
        for step in 0...184 {
            let gain=MixerMath.gain(db:Double(step)/2-80)
            assert(gain>=last && gain<=32612); last=gain
        }
        let original: [UInt16]=[8192,4096,0,100,0,0,0,0]
        let sources: [UInt16]=[0x80,0x81,0x600,0x601,0,0,0,0]
        let frame=MixerFrame(bus:0,gains:original,sources:sources,destinations:1<<8)
        let packed=[UInt64(0),MixerMath.pack(Array(original[0..<4])),MixerMath.pack(Array(original[4..<8])),MixerMath.pack(Array(sources[0..<4])),MixerMath.pack(Array(sources[4..<8])),UInt64(1<<8)]
        assert(tryFrame(packed)==frame)
        var invalid=packed; invalid[0]=6
        do { _ = try MixerFrame(reply:invalid); fatalError("Invalid bus accepted") } catch {}
        var draft=MixerDraft(); draft.load(frame,remembered:nil)
        draft.toggleMute(1); assert(draft.gains[1]==0 && draft.audible[1]==4096)
        draft.toggleMute(1); assert(draft.gains==original)
        draft.toggleMute(2); assert(draft.gains[2]==0) // Never invent an unmute gain.
        draft.setDB(-12,channel:0); assert(draft.gains[0]==2057)
        assert(Array(draft.gains.dropFirst())==Array(original.dropFirst()))
        var saved=MixerRecovery(serial:"test/serial",bus:0,original:original,sources:sources,verified:original,audible:original,pending:false,uncertain:false)
        assert(saved.permits(frame,restoring:false)); saved.pending=true; saved.uncertain=true
        assert(!saved.permits(frame,restoring:false) && saved.permits(frame,restoring:true))
        let shared=MixerFrame(bus:0,gains:original,sources:sources,destinations:(1<<8)|(1<<6))
        assert(!saved.permits(shared,restoring:true))
        let remapped=MixerFrame(bus:0,gains:original,sources:Array(sources.reversed()),destinations:1<<8)
        assert(!saved.permits(remapped,restoring:true))
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let store=MixerRecoveryStore(directory:root); try store.save(saved)
        let recovered=try MixerRecoveryStore(directory:root).load(serial:saved.serial,bus:0)
        assert(recovered==saved)
        let other=try store.load(serial:saved.serial,bus:1); assert(other==nil)
        draft.load(frame,remembered:nil); draft.adjust(0,increasing:false)
        assert(draft.gains[0]==MixerMath.gain(db:-0.5))
        draft.adjust(2,increasing:true); assert(draft.gains[2]==1)
        draft.adjust(2,increasing:true); assert(draft.gains[2]>1)
        let replacement=MixerRecovery(serial:saved.serial,bus:0,original:remapped.gains,sources:remapped.sources,verified:remapped.gains,audible:remapped.gains,pending:false,uncertain:false)
        try store.replaceBaseline(replacement)
        let replaced=try store.load(serial:saved.serial,bus:0); assert(replaced==replacement)
        let archives=try FileManager.default.contentsOfDirectory(at:root,includingPropertiesForKeys:nil).filter { $0.lastPathComponent.hasPrefix("archive-") }
        assert(archives.count==1)
        let archived=try JSONDecoder().decode(MixerRecovery.self,from:Data(contentsOf:archives[0])); assert(archived==saved)
        for output in 0..<4 {
            let rows=(0..<6).map { MixerFrame(bus:$0,gains:original,sources:sources,destinations:$0==0 ? UInt32((1<<6)|(1<<7)) : 0) }
            let plan=try OutputMixPlan.make(output:output,source:0x300,rows:rows)
            assert(plan.frame.bus==1 && plan.frame.output==output && plan.initialGains==original)
            let direct=try OutputMixPlan.make(output:output,source:0x80,rows:rows)
            assert(direct.initialGains==[8192,0,0,0,0,0,0,0])
            var exclusive=rows; exclusive[0]=MixerFrame(bus:0,gains:original,sources:sources,destinations:UInt32(1<<(6+output)))
            let reuse=try OutputMixPlan.make(output:output,source:0x300,rows:exclusive)
            assert(reuse.frame.bus==0 && reuse.initialGains==nil && reuse.frame.isolated)
        }
        let occupied=(0..<6).map { MixerFrame(bus:$0,gains:original,sources:sources,destinations:1) }
        do { _=try OutputMixPlan.make(output:0,source:0x80,rows:occupied); fatalError("Occupied mix stolen") } catch {}
        let empty=(0..<6).map { MixerFrame(bus:$0,gains:original,sources:sources,destinations:0) }
        let preferred=try OutputMixPlan.make(output:0,source:0x80,rows:empty,preferredBus:4); assert(preferred.frame.bus==4)
        let silent=try OutputMixPlan.make(output:2,source:0x602,rows:empty)
        assert(silent.replacesUnavailableSource && silent.initialGains==Array(repeating:0,count:8))
        assert(silent.frame.sources==sources && silent.frame.destinations==0)
        assert(empty.allSatisfy { $0.gains==original && $0.sources==sources })
        print("PASS: four-output exclusive reuse, shared cloning, direct-source preparation, exhaustion and unavailable-source guards")
        print("PASS: mixer dB endpoints/monotonicity, packing, mute/unmute, untouched gains, shared/remapped guards, durable per-bus recovery")
    }
    static func tryFrame(_ values:[UInt64])->MixerFrame { try! MixerFrame(reply:values) }
}
