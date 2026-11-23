import Foundation
@main struct RecoveryStoreTests {
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = RecoveryStore(directory: directory)
        let routes: [UInt32] = (0..<18).map { i in
            let destination: Int
            if i < 6 { destination = 0x600 + i }
            else if i < 10 { destination = 0x80 + i - 6 }
            else { destination = 0x300 + i - 10 }
            let source = UInt32(0x600 + i % 4)
            return UInt32(destination) | (source << 12)
        }
        var snapshot = RecoverySnapshot(serial: "unit/../A", model: "1235:8212", routes: routes, capturedAt: Date(timeIntervalSince1970: 0), pending: false)
        assert(snapshot.valid)
        try store.save(snapshot)
        snapshot.pending = true; try store.save(snapshot)
        // A new store instance represents a new process/driver installation.
        let relaunched = RecoveryStore(directory: directory)
        let recovered = try relaunched.load(snapshot.serial)
        assert(recovered == snapshot && recovered?.pending == true)
        let absent = try relaunched.load("different-device"); assert(absent == nil)
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        assert(files.count == 1 && files[0].deletingLastPathComponent().standardizedFileURL.path == directory.standardizedFileURL.path)
        try Data("broken".utf8).write(to: files[0])
        do { _ = try relaunched.load(snapshot.serial); fatalError("Corrupt recovery accepted") } catch {}
        let invalid = RecoverySnapshot(serial: "A", model: "1235:8212", routes: [], capturedAt: Date(), pending: true)
        do { try store.save(invalid); fatalError("Invalid snapshot accepted") } catch {}
        // Atomic save failure must be observable, not silently permit a write.
        let fileInsteadOfDirectory = directory.appendingPathComponent("file")
        try Data().write(to: fileInsteadOfDirectory)
        do { try RecoveryStore(directory: fileInsteadOfDirectory).save(snapshot); fatalError("Save should fail") } catch {}
        print("PASS: durable recovery restart/device isolation/corruption/path safety/save failure")
    }
}
