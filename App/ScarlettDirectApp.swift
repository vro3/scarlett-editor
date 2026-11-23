import SwiftUI
import AVFAudio

@main struct ScarlettDirectApp: App {
    var body: some Scene { WindowGroup { RoutingView() } }
}
private let driverName = "ScarlettDriver"
struct HardwareFailure: LocalizedError {
    let message: String
    let mayHaveWritten: Bool
    var errorDescription: String? { message }
}
final class DriverConnection: @unchecked Sendable {
    private var connection: io_connect_t = 0
    private var registryID: UInt64?
    deinit { if connection != 0 { IOServiceClose(connection) } }
    func select(_ id: UInt64?) { if connection != 0 { IOServiceClose(connection); connection = 0 }; registryID = id }
    func call(_ selector: UInt32, source: UInt64 = 0) throws -> [UInt64] { try callInputs(selector, inputs: [source]) }
    func callInputs(_ selector: UInt32, inputs: [UInt64]) throws -> [UInt64] {
        if connection == 0 {
            guard let registryID else { throw HardwareFailure(message: "Select a connected interface first.", mayHaveWritten: false) }
            let service = IOServiceGetMatchingService(kIOMainPortDefault, IORegistryEntryIDMatching(registryID))
            guard service != 0 else { throw HardwareFailure(message: "The selected control connection is gone. Refresh interfaces. No command was sent.", mayHaveWritten: false) }
            defer { IOObjectRelease(service) }
            let result = IOServiceOpen(service, mach_task_self_, 0, &connection)
            guard result == KERN_SUCCESS else { connection = 0; throw HardwareFailure(message: String(format: "Could not open selected driver (0x%08x). No command was sent.", result), mayHaveWritten: false) }
        }
        var output = [UInt64](repeating: 0, count: 6)
        var count: UInt32 = 6
        let result = inputs.withUnsafeBufferPointer { IOConnectCallScalarMethod(connection, selector, $0.baseAddress, UInt32($0.count), &output, &count) }
        guard result == KERN_SUCCESS, count == 6 else {
            var diagnostic = [UInt64](repeating: 0, count: 6), zero: UInt64 = 0
            var diagnosticCount: UInt32 = 6
            let diagResult = IOConnectCallScalarMethod(connection, 3, &zero, 1, &diagnostic, &diagnosticCount)
            IOServiceClose(connection); connection = 0
            let writing = [UInt32(1), 2, 6, 9, 10, 12, 13, 14, 15].contains(selector)
            let mayHaveWritten = writing && (diagResult != KERN_SUCCESS || diagnosticCount != 6 || (40...50).contains(diagnostic[0]))
            let reason: String
            if selector >= 8 && (selector <= 11 || selector == 14) && (result == ScarlettReturnBusy || result == ScarlettReturnNotReady) { reason = "Mixer state or connection changed. Read routing and levels. Restore is available only with unchanged input assignments and an isolated mix; otherwise explicitly accept a new mix baseline." }
            else if result == ScarlettReturnBusy { reason = "Routing changed outside this app. Nothing was written. Read again, then explicitly use current routing as the baseline, or restore the saved source." }
            else if result == ScarlettReturnUnsupported { reason = "This device state is not supported. Restore requires the same interface at 44.1 or 48 kHz. The recovery snapshot is retained." }
            else if result == ScarlettReturnNotReady { reason = "Read routing to reconnect. If a previous write is uncertain, restore its saved source before applying another change." }
            else { reason = String(format: "Hardware operation failed (0x%08x).", result) }
            throw HardwareFailure(message: reason + (mayHaveWritten ? " A write may have taken effect; the recovery snapshot is retained." : " No hardware write was sent by this operation."), mayHaveWritten: mayHaveWritten)
        }
        return output
    }
    func serial() throws -> String {
        let values = try call(5)
        let bytes = values.flatMap { value -> [UInt8] in (0..<8).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) } }
        let serial = String(bytes: bytes.prefix(while: { $0 != 0 }), encoding: .ascii) ?? ""
        guard !serial.isEmpty else { throw HardwareFailure(message: "The interface has no usable USB serial. Writes are blocked because recovery cannot identify it safely.", mayHaveWritten: false) }
        return serial
    }
    func liveRoutes() throws -> [UInt32] {
        try (0..<3).flatMap { try call(16, source: UInt64($0)).map { UInt32(truncatingIfNeeded: $0) } }
    }
    func snapshot() throws -> [UInt32] {
        try (0..<3).flatMap { try call(7, source: UInt64($0)).map { UInt32(truncatingIfNeeded: $0) } }
    }
}
@MainActor final class RoutingModel: ObservableObject {
    @Published var status = "Connect an interface and select it in the sidebar."
    @Published var log = "No hardware commands sent." {
        didSet {
            NSLog("Scarlett Direct: %@", log)
            if let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
                try? log.write(to: directory.appendingPathComponent("ScarlettHardwareLog.txt"), atomically: true, encoding: .utf8)
            }
        }
    }
    @Published var devices: [InterfaceDevice] = []
    @Published var deviceID: String?
    @Published var outputs: [UInt64] = []
    @Published var audioOutput = "No active USB audio output"
    @Published var current: UInt64?
    @Published var original: UInt64?
    @Published var selected: UInt64 = 0x80
    @Published var busy = false
    @Published var ready = false
    @Published var confirmed = false
    @Published var recoveryPending = false
    @Published var explicitlySelected = false
    @Published var selectedOutput = 2
    var preparedGains: [UInt16]?
    @Published var startsSilent = false
    @Published var mixIndex = 0
    @Published var mixFrame: MixerFrame?
    @Published var mixDraft = MixerDraft()
    @Published var mixerArmed = false
    @Published var mixerStatus = "Read a mix to load its hardware levels."
    var mixRecovery: MixerRecovery?
    let mixStore = MixerRecoveryStore(directory: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("MixerRecovery"))
    let testingAudio = false // Automatic write/tone launch hooks have been removed.
    private var recovery: RecoverySnapshot?
    let hardware = DriverConnection()
    let queue = DispatchQueue(label: "ScarlettDirect.USB")
    private var store: RecoveryStore {
        let root=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("RoutingRecovery")
        return RecoveryStore(directory:selectedOutput==2 ? root : root.appendingPathComponent("Output\(selectedOutput+1)"))
    }
    func clearOutputState() {
        ready=false; current=nil; original=nil; selected=0; recovery=nil; recoveryPending=false
        confirmed=false; mixDraft=MixerDraft(); mixerStatus="Loading output…"
    }
    var savedOutputMix: Int? { recovery?.allocatedMix }
    func rememberOutputMix(_ mix: Int) throws {
        guard var snapshot=recovery, (0..<6).contains(mix) else { throw MixerError.invalid }
        snapshot.allocatedMix=mix
        try store.save(snapshot)
        recovery=snapshot
    }
    var selectedDevice: InterfaceDevice? { devices.first { $0.id == deviceID } }
    var writeBlock: String? {
        if let block=targetWriteBlock { return block }
        if let serial=selectedDevice?.serial {
            do { if try mixStore.loadInputs(serial)?.pending == true { return "Input setup is unfinished. Tap Enable faders to resume." } }
            catch { return "Input recovery could not be read. Writes are blocked." }
        }
        return nil
    }
    var targetWriteBlock: String? {
        guard explicitlySelected else { return "Tap the interface in the sidebar to confirm the control target." }
        guard let serial = selectedDevice?.serial, !serial.isEmpty else { return "A verified USB serial is required before writing." }
        guard devices.filter({ $0.serial == serial }).count == 1 else { return "Duplicate USB serials: disconnect the other interface before writing." }
        // Temporary acceptance gate: do not expose unreviewed multi-device writes.
        guard devices.count == 1 else { return "Multi-device writes are paused pending independent review. Keep only the target interface connected for writing." }
        return nil
    }
    func discover() {
        guard !busy else { return }
        var found: [InterfaceDevice] = [], iterator: io_iterator_t = 0
        if IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceNameMatching(driverName), &iterator) == KERN_SUCCESS {
            defer { IOObjectRelease(iterator) }
            while case let service = IOIteratorNext(iterator), service != 0 {
                var id: UInt64 = 0
                if IORegistryEntryGetRegistryEntryID(service, &id) == KERN_SUCCESS {
                    let probe = DriverConnection(); probe.select(id)
                    let serial = try? probe.serial()
                    found.append(InterfaceDevice(id: "driver-\(id)", name: "Scarlett 4i4", detail: "3rd Gen · USB control", registryID: id, serial: serial))
                }
                IOObjectRelease(service)
            }
        }
        found.sort { $0.id < $1.id }
        let ports = AVAudioSession.sharedInstance().currentRoute.outputs.filter { $0.portType == .usbAudio }
        audioOutput = ports.map(\.portName).joined(separator: ", ")
        if audioOutput.isEmpty { audioOutput = "No active USB audio output" }
        for port in ports where !port.portName.localizedCaseInsensitiveContains("4i4") || found.isEmpty {
            found.append(InterfaceDevice(id: "audio-" + port.uid, name: port.portName, detail: "Audio endpoint · no control connection", registryID: nil, serial: nil))
        }
        let previous = selectedDevice
        devices = found
        if !found.contains(where: { $0.id == deviceID }) { selectDevice(found.first?.id, explicit: false) }
        else if previous?.serial != selectedDevice?.serial { selectDevice(deviceID, explicit: false) }
        log += "\nInterfaces: " + found.map { "\($0.name) [\($0.id)] serial=\($0.serial ?? "unavailable")" }.joined(separator: "; ")
    }
    func selectDevice(_ id: String?, explicit: Bool = true) {
        guard !busy else { return }
        mixFrame = nil; mixDraft = MixerDraft(); mixRecovery = nil; mixerArmed = false
        deviceID = id; explicitlySelected = explicit; ready = false; current = nil; original = nil; outputs = []; confirmed = false
        recovery = nil; recoveryPending = false
        hardware.select(selectedDevice?.registryID)
        status = selectedDevice?.registryID == nil ? "Routing control is not available for this interface in this build." : "Read routing to see where sound is going."
    }
    func recordAudioRoute() {
        confirmed = false; mixerArmed = false
        log += "\nAudio route changed; monitoring confirmation reset."
        discover()
    }
    func suspend() { confirmed = false; mixerArmed = false }
    func run(_ selector: UInt32, completion: ((Bool) -> Void)? = nil) {
        guard !busy else { completion?(false); return }
        if deviceID == nil { discover() }
        guard let target = selectedDevice, target.registryID != nil else { status = "Select an interface with USB control."; completion?(false); return }
        let writing = selector == 1 || selector == 2
        let priorRecovery = recovery
        do {
            if writing {
                // Re-enumerate before every write; a stale list must not authorize a newly attached unit.
                discover()
                guard deviceID == target.id, selectedDevice?.serial == target.serial else { throw HardwareFailure(message: "The selected connection changed. Read routing again.", mayHaveWritten: false) }
                if let block = writeBlock { throw HardwareFailure(message: block, mayHaveWritten: false) }
                guard confirmed, ready, var snapshot = recovery else { throw HardwareFailure(message: "Read routing and confirm low speaker/headphone levels first.", mayHaveWritten: false) }
                if selector == 1 && recoveryPending { throw HardwareFailure(message: "Restore the saved source before applying another change.", mayHaveWritten: false) }
                snapshot.pending = true
                try store.save(snapshot) // Must reach disk before sending any routing write.
                recovery = snapshot; recoveryPending = true
            }
            if selector == 4 && recoveryPending { throw HardwareFailure(message: "Restore the saved source before replacing the baseline.", mayHaveWritten: false) }
        } catch { status = error.localizedDescription; log += "\n" + status; completion?(false); return }
        busy = true
        let source = selector == 2 ? recovery!.originalSource(output:selectedOutput) : selected
        let routeOutput=selectedOutput
        let device = hardware
        let command: UInt32 = selector == 2 ? 13 : selector == 1 ? 12 : selector
        queue.async { [weak self] in
            let result = Result { () -> ([UInt64], String?, [UInt32]) in
                let serial = try? device.serial()
                if writing && serial != target.serial { throw HardwareFailure(message: "Device serial changed. Nothing was written.", mayHaveWritten: false) }
                let values = try device.call(command, source: writing ? source | UInt64(routeOutput)<<16 : source)
                let routes = (selector == 0 || selector == 4) ? try device.snapshot() : []
                return (values, serial, routes)
            }
            Task { @MainActor in
                guard let self else { return }
                self.busy = false
                switch result {
                case .success(let (values, serial, routes)):
                    self.mixFrame=nil; self.mixerArmed=false // Routing changed or refreshed: invalidate cached mix destinations.
                    self.outputs = values.dropFirst(2).map { ($0 >> 12) & 0xfff }
                    self.current = (values[2+routeOutput] >> 12) & 0xfff
                    do {
                        if let serial {
                            if selector == 0 || selector == 4 {
                                let saved = try self.store.load(serial)
                                let candidate = RecoverySnapshot(serial: serial, model: "1235:8212", routes: routes, capturedAt: Date(), pending: false)
                                if selector == 4 && saved?.pending == true { throw RecoveryStore.RecoveryError.invalid }
                                self.recovery = selector == 4 ? candidate : (saved ?? candidate)
                                try self.store.save(self.recovery!)
                            } else if selector == 2, var snapshot = self.recovery {
                                guard self.current == snapshot.originalSource(output:routeOutput) else { throw HardwareFailure(message: "Restore source did not match. Snapshot retained.", mayHaveWritten: true) }
                                snapshot.pending = false; try self.store.save(snapshot); self.recovery = snapshot
                            }
                        }
                        self.original = self.recovery?.originalSource(output:routeOutput)
                        self.recoveryPending = self.recovery?.pending ?? false
                        self.ready = true
                        if selector == 0 || selector == 4 { self.selected = self.current ?? 0 }
                        self.status = selector == 0 ? "Read from selected Scarlett · firmware \(values[0])" : selector == 4 ? "Current routing accepted as the new baseline. No routing was written." : selector == 1 ? "Routing change read back from hardware. Recovery snapshot saved." : "Saved output source restored and verified."
                        self.log += "\n\(Date().formatted(date: .omitted, time: .standard)) · \(self.status)\n" + values.dropFirst(2).map { String(format: "%06llx", $0) }.joined(separator: " ")
                        completion?(true)
                    } catch {
                        self.ready = false; self.status = "Recovery storage: " + error.localizedDescription; self.log += "\n" + self.status; completion?(false)
                    }
                case .failure(let error):
                    if writing, let failure = error as? HardwareFailure, !failure.mayHaveWritten, let priorRecovery {
                        do { try self.store.save(priorRecovery); self.recovery = priorRecovery; self.recoveryPending = priorRecovery.pending }
                        catch { self.log += "\nCould not clear conservative pending recovery marker: \(error.localizedDescription)" }
                    }
                    self.status = error.localizedDescription; self.ready = false
                    self.log += "\n" + self.status; completion?(false)
                }
            }
        }
    }
}
