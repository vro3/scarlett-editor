import Foundation

struct RecoverySnapshot: Codable, Equatable {
    let serial: String
    let model: String
    let routes: [UInt32]
    let capturedAt: Date
    var allocatedMix: Int? = nil
    var pending: Bool
    func originalSource(output: Int) -> UInt64 { UInt64((routes[6+output] >> 12) & 0xfff) }
    var originalSource: UInt64 { originalSource(output:2) }
    var valid: Bool {
        guard allocatedMix == nil || (0..<6).contains(allocatedMix!), model == "1235:8212", !serial.isEmpty, routes.count == 18 else { return false }
        return routes.enumerated().allSatisfy { index, word in
            let destination = index < 6 ? 0x600 + index : index < 10 ? 0x80 + index - 6 : 0x300 + index - 10
            let source = (word >> 12) & 0xfff
            return word >> 24 == 0 && word & 0xfff == destination && (source == 0 || (0x80...0x83).contains(source) || (0x300...0x305).contains(source) || (0x600...0x603).contains(source))
        }
    }
}
struct RecoveryStore {
    let directory: URL
    private func url(_ serial: String) -> URL {
        // Hex encoding prevents serials from introducing path components.
        directory.appendingPathComponent(serial.utf8.map { String(format: "%02x", $0) }.joined() + ".json")
    }
    func load(_ serial: String) throws -> RecoverySnapshot? {
        let file = url(serial)
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        let snapshot = try JSONDecoder().decode(RecoverySnapshot.self, from: Data(contentsOf: file))
        guard snapshot.valid && snapshot.serial == serial else { throw RecoveryError.invalid }
        return snapshot
    }
    func save(_ snapshot: RecoverySnapshot) throws {
        guard snapshot.valid else { throw RecoveryError.invalid }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(snapshot).write(to: url(snapshot.serial), options: .atomic)
    }
    enum RecoveryError: LocalizedError {
        case invalid
        var errorDescription: String? { "Recovery snapshot is invalid. Routing writes are blocked; preserve the saved file for inspection." }
    }
}
