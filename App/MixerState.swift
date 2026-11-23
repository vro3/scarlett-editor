import Foundation

struct MixerFrame: Equatable {
    let bus: Int
    let gains: [UInt16]
    let sources: [UInt16]
    let destinations: UInt32
    var output: Int = 2
    var isolated: Bool { (0..<4).contains(output) && destinations & ~(1 << (6+output)) == 0 }
    var feedsOutput: Bool { destinations & (1 << (6+output)) != 0 }
    var feedsLine3: Bool { feedsOutput }
    init(bus: Int, gains: [UInt16], sources: [UInt16], destinations: UInt32) {
        self.bus=bus; self.gains=gains; self.sources=sources; self.destinations=destinations
    }
    init(reply: [UInt64]) throws {
        guard reply.count == 6, reply[0] < 6, reply[5] < (1 << 18) else { throw MixerError.invalid }
        bus=Int(reply[0]); gains=MixerMath.unpack(reply[1]) + MixerMath.unpack(reply[2])
        sources=MixerMath.unpack(reply[3]) + MixerMath.unpack(reply[4]); destinations=UInt32(reply[5])
        guard gains.allSatisfy({ $0 <= 32612 }), sources.allSatisfy(MixerMath.validSource) else { throw MixerError.invalid }
    }
}
enum MixerError: LocalizedError {
    case invalid, recovery, shared, sourceChanged, detachFirst
    var errorDescription: String? {
        switch self {
        case .detachFirst: return "Restore the output source before restoring these levels."
        case .invalid: return "Invalid mixer data. Read the mix again before continuing."
        case .recovery: return "Mixer levels changed or a previous write is uncertain. Read levels, then restore the saved levels or explicitly accept the current mix as a new baseline."
        case .shared: return "This mix also feeds another destination. Choose an unused mix; its levels affect every destination using it."
        case .sourceChanged: return "Mixer input assignments changed. Restore is blocked. Read levels and explicitly accept the current mix as a new baseline to continue."
        }
    }
}
enum MixerMath {
    static func validSource(_ s: UInt16) -> Bool { s == 0 || (0x80...0x83).contains(s) || (0x300...0x305).contains(s) || (0x600...0x603).contains(s) }
    static func pack(_ values: [UInt16]) -> UInt64 { values.prefix(4).enumerated().reduce(0) { $0 | UInt64($1.element) << ($1.offset * 16) } }
    static func unpack(_ value: UInt64) -> [UInt16] { (0..<4).map { UInt16(truncatingIfNeeded: value >> ($0 * 16)) } }
    static func gain(db: Double) -> UInt16 {
        guard db.isFinite else { return 0 }
        let quantized=(min(12,max(-80,db))*2).rounded()/2
        return UInt16(min(32612, floor(8192 * pow(10,quantized/20))))
    }
    static func db(_ gain: UInt16) -> Double { gain == 0 ? -80 : min(12,max(-80,(20 * log10(Double(gain)/8192)*2).rounded()/2)) }
    static func label(_ gain: UInt16) -> String { gain == 0 ? "Muted" : String(format: "%+.1f dB", db(gain)) }
}
struct MixerRecovery: Codable, Equatable {
    let serial: String
    let bus: Int
    let original: [UInt16]
    let sources: [UInt16]
    var verified: [UInt16]
    var audible: [UInt16]
    var pending: Bool
    var uncertain: Bool
    var valid: Bool {
        !serial.isEmpty && (0..<6).contains(bus) && [original,verified,audible].allSatisfy { $0.count == 8 && $0.allSatisfy { $0 <= 32612 } } && sources.count == 8 && sources.allSatisfy(MixerMath.validSource)
    }
    func permits(_ frame: MixerFrame, restoring: Bool) -> Bool {
        valid && frame.bus == bus && frame.sources == sources && frame.isolated && (restoring || (!uncertain && frame.gains == verified))
    }
}
struct MixerRecoveryStore {
    let directory: URL
    private func file(_ serial: String,_ bus: Int) -> URL { directory.appendingPathComponent(serial.utf8.map { String(format:"%02x",$0) }.joined() + "-mix\(bus).json") }
    func load(serial: String,bus: Int) throws -> MixerRecovery? {
        let url=file(serial,bus)
        guard FileManager.default.fileExists(atPath:url.path) else { return nil }
        let saved=try JSONDecoder().decode(MixerRecovery.self,from:Data(contentsOf:url))
        guard saved.valid && saved.serial == serial && saved.bus == bus else { throw MixerError.invalid }; return saved
    }
    func replaceBaseline(_ saved: MixerRecovery) throws {
        // Preserve the old recovery record before explicitly superseding it.
        if let old=try load(serial:saved.serial,bus:saved.bus) {
            let archive=directory.appendingPathComponent("archive-" + UUID().uuidString + ".json")
            try JSONEncoder().encode(old).write(to:archive,options:.atomic)
        }
        try save(saved)
    }
    func save(_ saved: MixerRecovery) throws {
        guard saved.valid else { throw MixerError.invalid }
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        try JSONEncoder().encode(saved).write(to:file(saved.serial,saved.bus),options:.atomic)
    }
}
struct MixerDraft {
    var gains: [UInt16] = []
    var audible: [UInt16] = []
    mutating func load(_ frame: MixerFrame, remembered: [UInt16]?) {
        gains=frame.gains
        audible=frame.gains.enumerated().map { index,gain in gain > 0 ? gain : (remembered?[index] ?? 0) }
    }
    mutating func setDB(_ db: Double, channel: Int) {
        guard gains.indices.contains(channel) else { return }
        gains[channel]=MixerMath.gain(db:db)
        if gains[channel]>0 { audible[channel]=gains[channel] }
    }
    mutating func adjust(_ channel: Int, increasing: Bool) {
        guard gains.indices.contains(channel) else { return }
        // Zero has no finite dB value: start at the lowest representable nonzero coefficient.
        let old=gains[channel]
        var next=old == 0 && increasing ? -78 : MixerMath.db(old) + (increasing ? 0.5 : -0.5)
        // Skip half-dB values that quantize to the same integer coefficient.
        while next > -80 && next < 12 && MixerMath.gain(db:next)==old { next += increasing ? 0.5 : -0.5 }
        setDB(next, channel:channel)
    }
    mutating func toggleMute(_ channel: Int) {
        guard gains.indices.contains(channel) else { return }
        if gains[channel]>0 { audible[channel]=gains[channel]; gains[channel]=0 }
        else if audible[channel]>0 { gains[channel]=audible[channel] }
        // Unknown previous level never unmutes at an invented gain. Move its fader instead.
    }
}

// Allocate only an existing exclusive mix or a completely unused bus.
struct OutputMixPlan {
    let frame: MixerFrame
    let initialGains: [UInt16]?
    var replacesUnavailableSource: Bool = false
    static func make(output: Int, source: UInt64, rows: [MixerFrame], preferredBus: Int? = nil) throws -> OutputMixPlan {
        guard (0..<4).contains(output), rows.count==6, Set(rows.map(\.bus))==Set(0..<6), rows.allSatisfy({ $0.gains.count==8 && $0.sources.count==8 && $0.sources==rows[0].sources }) else { throw MixerError.invalid }
        let existing=rows.first { UInt64(0x300+$0.bus)==source }
        if var row=existing, row.destinations == 1 << (6+output) {
            row.output=output; return OutputMixPlan(frame:row,initialGains:nil)
        }
        guard var free=rows.first(where:{$0.bus==preferredBus && $0.destinations==0}) ?? rows.first(where:{$0.destinations==0}) else { throw OutputMixError.noFreeMix }
        let gains: [UInt16]
        if let existing { gains=existing.gains }
        else if source==0 { gains=Array(repeating:0,count:8) }
        else {
            guard let channel=free.sources.firstIndex(of:UInt16(source)) else {
                free.output=output
                return OutputMixPlan(frame:free,initialGains:Array(repeating:0,count:8),replacesUnavailableSource:true)
            }
            var values=[UInt16](repeating:0,count:8); values[channel]=8192; gains=values
        }
        free.output=output
        return OutputMixPlan(frame:free,initialGains:gains)
    }
}
enum OutputMixError: LocalizedError {
    case noFreeMix, sourceUnavailable
    var errorDescription: String? {
        switch self {
        case .noFreeMix: return "All internal mixes are in use. Existing outputs have been preserved."
        case .sourceUnavailable: return "This source is not assigned to a mixer input. Use direct routing; existing mixer input assignments have been preserved."
        }
    }
}


// Durable journal for the shared input expansion. Original rows remain available after migration.
struct InputExpansionJournal: Codable {
    let serial: String
    let routes: [UInt32]
    let rows: [[UInt16]]
    let recoveries: [MixerRecovery]
    let sources: [UInt16]
    let expanded: [UInt16]
    var pending: Bool
    static let allSources: [UInt16] = [0x80,0x81,0x82,0x83,0x600,0x601,0x602,0x603]
    static func expandedSources(_ sources: [UInt16]) throws -> [UInt16] {
        guard sources.count==8 else { throw MixerError.invalid }
        var result=sources
        for source in allSources where !result.contains(source) {
            guard let slot=result.firstIndex(of:0) else { throw OutputMixError.sourceUnavailable }
            result[slot]=source
        }
        return result
    }
    static func routeArguments(_ routes: [UInt32]) -> [UInt64] {
        (0..<4).map { group in
            var packed: UInt64=0
            for i in 0..<5 where group*5+i<18 { packed |= UInt64((routes[group*5+i]>>12)&0xfff) << (i*12) }
            return packed
        }
    }
    var added: [Int] { (0..<8).filter { sources[$0] != expanded[$0] } }
    func normalized(_ values: [UInt16]) -> [UInt16] {
        var result=values; for slot in added { result[slot]=0 }; return result
    }
    var valid: Bool {
        guard !serial.isEmpty, routes.count==18, rows.count==6, recoveries.count==6,
              sources.count==8, (try? Self.expandedSources(sources))==expanded,
              rows.allSatisfy({ $0.count==8 && $0.allSatisfy({$0<=32612}) }),
              recoveries.enumerated().allSatisfy({ $0.element.valid && $0.element.serial==serial && $0.element.bus==$0.offset && $0.element.sources==sources && $0.element.verified==rows[$0.offset] && !$0.element.uncertain }) else { return false }
        return routes.enumerated().allSatisfy { i,w in
            let destination = i<6 ? 0x600+i : i<10 ? 0x80+i-6 : 0x300+i-10
            return w>>24==0 && w&0xfff==destination && MixerMath.validSource(UInt16((w>>12)&0xfff))
        } &&
            sources == routes[10..<18].map { UInt16(($0>>12)&0xfff) }
    }
    var expandedRoutes: [UInt32] {
        var result=routes
        for i in added { result[10+i]=(result[10+i]&0xfff)|(UInt32(expanded[i])<<12) }
        return result
    }
    func acceptsProgress(routes actual: [UInt32], rows current: [MixerFrame]) -> Bool {
        guard valid, current.count==6, actual==routes || actual==expandedRoutes else { return false }
        for m in 0..<6 {
            guard current[m].bus==m, current[m].gains.count==8,
                  current[m].sources==actual[10..<18].map({UInt16(($0>>12)&0xfff)}) else { return false }
            for i in 0..<8 {
                let gain=current[m].gains[i]
                if added.contains(i) {
                    if actual==expandedRoutes { if gain != 0 { return false } }
                    else if gain != rows[m][i] && gain != 0 { return false }
                } else if gain != rows[m][i] { return false }
            }
        }
        return true
    }
    func migrated(_ bus: Int) -> MixerRecovery {
        let old=recoveries[bus]
        return MixerRecovery(serial:serial,bus:bus,original:normalized(old.original),sources:expanded,
            verified:normalized(rows[bus]),audible:normalized(old.audible),pending:old.pending,uncertain:false)
    }
}
extension MixerRecoveryStore {
    private func inputFile(_ serial: String) -> URL {
        directory.appendingPathComponent(serial.utf8.map { String(format:"%02x",$0) }.joined()+"-inputs.json")
    }
    func loadInputs(_ serial: String) throws -> InputExpansionJournal? {
        let path=inputFile(serial)
        guard FileManager.default.fileExists(atPath:path.path) else { return nil }
        let record=try JSONDecoder().decode(InputExpansionJournal.self,from:Data(contentsOf:path))
        guard record.valid, record.serial==serial else { throw MixerError.invalid }
        return record
    }
    func saveInputs(_ record: InputExpansionJournal) throws {
        guard record.valid else { throw MixerError.invalid }
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        if record.pending, let old=try loadInputs(record.serial), !old.pending {
            try JSONEncoder().encode(old).write(to:directory.appendingPathComponent("input-archive-"+UUID().uuidString+".json"),options:.atomic)
        }
        try JSONEncoder().encode(record).write(to:inputFile(record.serial),options:.atomic)
    }
}
